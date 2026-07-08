-- Commit-graph lane engine adapted from gitgraph.nvim (MIT):
--   https://github.com/isakbm/gitgraph.nvim
--   lua/gitgraph/core.lua, lua/gitgraph/utils.lua, lua/gitgraph/git.lua
-- Original copyright (c) Isak Buhl-Mortensen. See the upstream LICENSE.
--
-- The algorithm is kept intact: commits are laid out over 2-wide columns in
-- alternating commit/connector rows; a commit's first parent inherits its
-- column (branches stick to their lane, so lines stay straight), other merge
-- parents reserve the next vacant column to the right, and ambiguous
-- "bi-crossings" are untangled by edge lifting. Connector glyphs come from a
-- 4-bit neighbor mask. Adapted here: git data via vim.system, output as
-- buffer lines plus { line, col, end_col, hl } extmark specs in
-- GitPanelGraph* highlight groups, and a per-row commit map for selection.
local bit = require("bit")

local M = {}

M.symbols = {
  commit = "●",
  commit_end = "●",
  merge_commit = "◉",
  merge_commit_end = "◉",

  GVER = "│",
  GHOR = "─",
  GCLD = "╮",
  GCRD = "╭",
  GCLU = "╯",
  GCRU = "╰",
  GLRU = "┴",
  GLRD = "┬",
  GLUD = "┤",
  GRUD = "├",
  GFORKU = "┼",
  GFORKD = "┼",
  GRUDCD = "├",
  GRUDCU = "├",
  GLUDCD = "┤",
  GLUDCU = "┤",
  GLRDCL = "┬",
  GLRDCR = "┬",
  GLRUCL = "┴",
  GLRUCR = "┴",
}

local DEFAULTS = {
  all = true,
  max_count = 200,
  timestamp = "%Y-%m-%d %H:%M",
  fields = { "hash", "timestamp", "author", "branch_name", "tag" },
}

-- One raw commit per line: subject, (%D) decorations — parenthesized so the
-- field is never empty — date, author, short hash, short parent hashes, all
-- NUL-separated because subjects may contain anything else.
local function git_log(root, opts)
  local cmd = {
    "git",
    "-C",
    root,
    "log",
    "--date-order",
    "--pretty=format:%s%x00(%D)%x00%ad%x00%an%x00%h%x00%p",
    "--date=format:" .. opts.timestamp,
    "--max-count=" .. tostring(opts.max_count),
  }
  if opts.all then
    cmd[#cmd + 1] = "--all"
  end

  local res = vim.system(cmd):wait()
  if res.code ~= 0 or not res.stdout then
    return {}
  end

  local raw = {}
  for _, line in ipairs(vim.split(res.stdout, "\n", { trimempty = true })) do
    local fields = vim.split(line, "\0", { plain = true })
    if #fields == 6 then
      local branch_names, tags = {}, {}
      local describers = fields[2]:gsub("[%(%)]", "")
      for _, desc in ipairs(vim.split(describers, ", ", { plain = true, trimempty = true })) do
        if desc:match("^tag: ") then
          tags[#tags + 1] = desc
        else
          branch_names[#branch_names + 1] = desc
        end
      end

      raw[#raw + 1] = {
        msg = fields[1],
        branch_names = branch_names,
        tags = tags,
        author_date = fields[3],
        author_name = fields[4],
        hash = fields[5],
        parents = vim.split(fields[6], " ", { trimempty = true }),
      }
    end
  end
  return raw
end

local function process_raw_commits(raw_commits)
  local commits, sorted_commits = {}, {}
  for _, rc in ipairs(raw_commits) do
    sorted_commits[#sorted_commits + 1] = rc.hash
    commits[rc.hash] = {
      msg = rc.msg,
      branch_names = rc.branch_names,
      tags = rc.tags,
      author_date = rc.author_date,
      author_name = rc.author_name,
      hash = rc.hash,
      i = -1,
      j = -1,
      parents = rc.parents,
      children = {},
    }
  end
  return commits, sorted_commits
end

local function populate_child_parent_data(commits, sorted_commits)
  for _, c_hash in ipairs(sorted_commits) do
    local c = commits[c_hash]
    for _, h in ipairs(c.parents) do
      local p = commits[h]
      if p then
        p.children[#p.children + 1] = c.hash
      else
        -- virtual parent beyond the log window; not part of sorted_commits
        commits[h] = {
          hash = h,
          author_name = "virtual",
          msg = "virtual parent",
          author_date = "unknown",
          parents = {},
          children = { c.hash },
          branch_names = {},
          tags = {},
          i = -1,
          j = -1,
        }
      end
    end
  end
end

local function hash_of(cell)
  return cell and cell.commit and cell.commit.hash
end

local function propagate(cells)
  local new_cells = {}
  for _, cell in ipairs(cells) do
    if cell.connector then
      new_cells[#new_cells + 1] = { connector = " " }
    elseif cell.commit then
      new_cells[#new_cells + 1] = { commit = cell.commit }
    else
      new_cells[#new_cells + 1] = { connector = " " }
    end
  end
  return new_cells
end

local function find(cells, hash, start)
  for idx = start or 1, #cells, 2 do
    local c = cells[idx]
    if c.commit and c.commit.hash == hash then
      return idx
    end
  end
  return nil
end

local function next_vacant_j(cells, start)
  for i = start or 1, #cells, 2 do
    if cells[i].connector == " " then
      return i
    end
  end
  return #cells + 1
end

-- A bi-crossing is more than one branch propagating horizontally on one
-- connector row; it can only follow a merge commit whose parent interval
-- overlaps a multi-cell interval destined for the next commit.
local function get_is_bi_crossing(commit_row, connector_row, next_commit)
  if not next_commit then
    return false, false
  end

  local prev = commit_row.commit
  assert(prev, "expected a prev commit")
  if #prev.parents < 2 then
    return false, false
  end

  local row = connector_row
  local function interval_upd(x, k)
    if k < x.start then
      x.start = k
    end
    if k > x.stop then
      x.stop = k
    end
  end

  local emi = { start = #row.cells, stop = 1 }
  for k, cell in ipairs(row.cells) do
    if cell.commit and cell.emphasis then
      interval_upd(emi, k)
    end
  end

  local coi = { start = #row.cells, stop = 1 }
  for k, cell in ipairs(row.cells) do
    if cell.commit and cell.commit.hash == next_commit.hash then
      interval_upd(coi, k)
    end
  end

  -- unsafe if starts of intervals overlap and equal the direct parent location
  local safe = not (emi.start == coi.start and prev.j == emi.start)

  if coi.start == coi.stop then
    return false, safe
  end
  if coi.start == emi.start and coi.stop == emi.stop then
    return true, safe
  end
  for _, k in pairs(emi) do
    if coi.start < k and k < coi.stop then
      return true, safe
    end
  end
  for _, k in pairs(coi) do
    if emi.start < k and k < emi.stop then
      return true, safe
    end
  end

  return false, safe
end

local function resolve_bi_crossing(prev_commit_row, prev_connector_row, commit_row, connector_row, next)
  local prev_row = commit_row
  local this_row = connector_row
  assert(prev_row and this_row, "expecting two prior rows due to bi-connector")

  local function void_repeats(row)
    local start_voiding = false
    for k, cell in ipairs(row.cells) do
      if cell.commit and cell.commit.hash == next.hash then
        if not start_voiding then
          start_voiding = true
        elseif not row.cells[k].emphasis then
          row.cells[k] = { connector = " " }
        end
      end
    end
  end

  void_repeats(prev_row)
  void_repeats(this_row)

  -- also take care when the prev prev has a repeat where the repeat is not
  -- the direct parent of its child
  local prev_prev_row = prev_connector_row
  local prev_prev_prev_row = prev_commit_row
  assert(prev_prev_row and prev_prev_prev_row)
  do
    local start_voiding = false
    local replacer = nil
    for k, cell in ipairs(prev_prev_row.cells) do
      if cell.commit and cell.commit.hash == next.hash then
        if not start_voiding then
          start_voiding = true
          replacer = cell
        elseif k ~= prev_prev_prev_row.commit.j then
          local ppcell = prev_prev_prev_row.cells[k]
          if (not ppcell) or (ppcell and ppcell.connector == " ") then
            prev_prev_row.cells[k] = { connector = " " }
            replacer.emphasis = true
          end
        end
      end
    end
  end
end

local function generate_commit_row(c, prev_row)
  local j = nil
  local rowc = {}

  if prev_row then
    rowc = propagate(prev_row.cells)
    j = find(prev_row.cells, c.hash)
  end

  if j then
    c.j = j
    rowc[j] = { commit = c, is_commit = true }
    for k = j + 1, #rowc do
      local v = rowc[k]
      if v.commit and v.commit.hash == c.hash then
        rowc[k] = { connector = " " }
      end
    end
  else
    j = next_vacant_j(rowc)
    c.j = j
    rowc[j] = { commit = c, is_commit = true }
    rowc[j + 1] = { connector = " " }
  end

  return { cells = rowc, commit = c }, j
end

local function generate_connector_row(
  commits,
  prev_commit_row,
  prev_connector_row,
  commit_row,
  commit_loc,
  curr_commit,
  next_commit
)
  local found_bi_crossing = false
  local connector_cells = propagate(commit_row.cells)

  if #curr_commit.parents > 0 then
    local function reserve_remainder(rem_parents)
      for _, h in ipairs(rem_parents) do
        local j = find(commit_row.cells, h, commit_loc)
        if not j then
          local vacant = next_vacant_j(connector_cells, commit_loc)
          connector_cells[vacant] = { commit = commits[h], emphasis = true }
          connector_cells[vacant + 1] = { connector = " " }
        else
          connector_cells[j].emphasis = true
        end
      end
    end

    -- peek at the next commit; route an existing lane toward it when it is
    -- one of our parents
    local tracker = nil
    if next_commit then
      for _, cell in ipairs(connector_cells) do
        if cell.commit and cell.commit.hash == next_commit.hash then
          tracker = cell
          break
        end
      end
    end

    local next_p_idx = nil
    if tracker and next_commit then
      for k, h in ipairs(curr_commit.parents) do
        if h == next_commit.hash then
          next_p_idx = k
          break
        end
      end
    end

    if next_p_idx then
      assert(tracker)
      if #curr_commit.parents == 1 then
        connector_cells[commit_loc].commit = commits[curr_commit.parents[1]]
        connector_cells[commit_loc].emphasis = true
      else
        connector_cells[commit_loc] = { connector = " " }
        tracker.emphasis = true

        local rem_parents = {}
        for k, h in ipairs(curr_commit.parents) do
          if k ~= next_p_idx then
            rem_parents[#rem_parents + 1] = h
          end
        end
        assert(#rem_parents == #curr_commit.parents - 1, "unexpected amount of rem parents")
        reserve_remainder(rem_parents)

        if connector_cells[commit_loc].connector == " " then
          connector_cells[commit_loc].commit = tracker.commit
          connector_cells[commit_loc].emphasis = true
          connector_cells[commit_loc].connector = nil
          tracker.emphasis = false
        end
      end
    else
      connector_cells[commit_loc].commit = commits[curr_commit.parents[1]]
      connector_cells[commit_loc].emphasis = true

      local rem_parents = {}
      for k = 2, #curr_commit.parents do
        rem_parents[#rem_parents + 1] = curr_commit.parents[k]
      end
      reserve_remainder(rem_parents)
    end

    local connector_row = { cells = connector_cells }
    local is_bi_crossing, resolvable = get_is_bi_crossing(commit_row, connector_row, next_commit)
    if is_bi_crossing then
      found_bi_crossing = true
    end
    if is_bi_crossing and resolvable and next_commit then
      resolve_bi_crossing(prev_commit_row, prev_connector_row, commit_row, connector_row, next_commit)
    end

    return connector_row, found_bi_crossing
  else
    -- no parents: remove the already propagated connector for this commit
    for i = 1, #connector_cells, 2 do
      local cell = connector_cells[i]
      if cell.commit and cell.commit.hash == curr_commit.hash then
        connector_cells[i] = { connector = " " }
      end
    end
    return { cells = connector_cells }, found_bi_crossing
  end
end

local function straight_j(commits, sorted_commits)
  local graph = {}
  for i, c_hash in ipairs(sorted_commits) do
    local curr_commit = commits[c_hash]
    local next_commit = commits[sorted_commits[i + 1]]
    local prev_commit_row = graph[#graph - 1]
    local prev_connector_row = graph[#graph]

    local commit_row, commit_loc = generate_commit_row(curr_commit, prev_connector_row)
    graph[#graph + 1] = commit_row

    if i < #sorted_commits then
      graph[#graph + 1] = generate_connector_row(
        commits,
        prev_commit_row,
        prev_connector_row,
        commit_row,
        commit_loc,
        curr_commit,
        next_commit
      )
    end
  end
  return graph
end

local function insert_vert_and_hor_pipes(graph, sym)
  for i = 2, #graph - 1 do
    local row = graph[i]

    local function count_emph(cells)
      local n = 0
      for _, c in ipairs(cells) do
        if c.commit and c.emphasis then
          n = n + 1
        end
      end
      return n
    end

    local num_emphasized = count_emph(row.cells)

    -- vertical connections
    for j = 1, #row.cells, 2 do
      local this = graph[i].cells[j]
      local below = graph[i + 1].cells[j]
      local tch, bch = hash_of(this), hash_of(below)

      if not this.is_commit and not this.connector then
        local ignore_this = (num_emphasized > 1 and (this.emphasis or false))

        if not ignore_this and bch == tch then
          local has_repeats = false
          local first_repeat = nil
          for k = 1, #row.cells, 2 do
            local cell_k, cell_j = row.cells[k], row.cells[j]
            local rkc, rjc = (not cell_k.connector and cell_k.commit), (not cell_j.connector and cell_j.commit)
            if k ~= j and (rkc and rjc) and rkc.hash == rjc.hash then
              has_repeats = true
              first_repeat = k
              break
            end
          end

          if not has_repeats then
            this.connector = sym.GVER
          else
            local k = first_repeat
            local this_k = graph[i].cells[k]
            local below_k = graph[i + 1].cells[k]
            local bkc, tkc = (not below_k.connector and below_k.commit), (not this_k.connector and this_k.commit)
            if (bkc and tkc) and bkc.hash == tkc.hash then
              this.connector = sym.GVER
            end
          end
        end
      end
    end

    do
      -- the last row is a commit row without a following connector row
      assert(#graph % 2 == 1)
      local last_row = graph[#graph]
      for j = 1, #last_row.cells, 2 do
        local cell = last_row.cells[j]
        if cell.commit and not cell.is_commit then
          cell.connector = sym.GVER
        end
      end
    end

    -- horizontal connections: a stopped connector has a void cell below it
    local stopped = {}
    for j = 1, #row.cells, 2 do
      local this = graph[i].cells[j]
      local below = graph[i + 1].cells[j]
      if not this.connector and (not below or below.connector == " ") then
        assert(this.commit)
        stopped[#stopped + 1] = j
      end
    end

    local intervals = {}
    for _, j in ipairs(stopped) do
      for k = 1, j do
        local cell_k, cell_j = row.cells[k], row.cells[j]
        local rkc, rjc = (not cell_k.connector and cell_k.commit), (not cell_j.connector and cell_j.commit)
        if (rkc and rjc) and (rkc.hash == rjc.hash) then
          if k < j then
            intervals[#intervals + 1] = { start = k, stop = j }
          end
          break
        end
      end
    end

    -- intervals for the connectors of merge children
    do
      local low, high = #row.cells, 1
      for j = 1, #row.cells, 2 do
        local c = row.cells[j]
        if c.emphasis then
          if j > high then
            high = j
          end
          if j < low then
            low = j
          end
        end
      end
      if high > low then
        intervals[#intervals + 1] = { start = low, stop = high }
      end
    end

    if i % 2 == 0 then
      for _, interval in ipairs(intervals) do
        for j = interval.start + 1, interval.stop - 1 do
          local this = graph[i].cells[j]
          if this.connector == " " then
            this.connector = sym.GHOR
          end
        end
      end
    end
  end
end

local function insert_symbols_on_connector_rows(graph, sym)
  -- 4-bit neighbor mask (left, right, up, down) -> connector glyph
  local symb_map = {
    [10] = sym.GCLU,
    [9] = sym.GCLD,
    [6] = sym.GCRU,
    [5] = sym.GCRD,
    [14] = sym.GLRU,
    [13] = sym.GLRD,
    [11] = sym.GLUD,
    [7] = sym.GRUD,
  }

  for i = 2, #graph, 2 do
    local row = graph[i]
    local above = graph[i - 1]
    local below = graph[i + 1]

    for j = 1, #row.cells, 2 do
      local this = row.cells[j]
      if this.connector ~= sym.GVER then
        local lc = row.cells[j - 1]
        local rc = row.cells[j + 1]
        local uc = above and above.cells[j]
        local dc = below and below.cells[j]

        local l = lc and (lc.connector ~= " " or lc.commit) or false
        local r = rc and (rc.connector ~= " " or rc.commit) or false
        local u = uc and (uc.connector ~= " " or uc.commit) or false
        local d = dc and (dc.connector ~= " " or dc.commit) or false

        local nn = 0
        local symb_n = 0
        for bi, b in ipairs({ l, r, u, d }) do
          if b then
            nn = nn + 1
            symb_n = symb_n + bit.lshift(1, 4 - bi)
          end
        end

        local symbol = symb_map[symb_n] or "?"
        if i == #graph and symbol == "?" then
          symbol = sym.GVER
        end

        local commit_dir_above = above.commit and above.commit.j == j
        local clh_above = nil
        if above.commit and above.commit.j ~= j then
          clh_above = above.commit.j < j and "l" or "r"
        end

        if clh_above and symbol == sym.GLRD then
          symbol = clh_above == "l" and sym.GLRDCL or sym.GLRDCR
        elseif symbol == sym.GLRU then
          symbol = sym.GLRUCL
        end

        local merge_dir_above = commit_dir_above and #above.commit.parents > 1
        if symbol == sym.GLUD then
          symbol = merge_dir_above and sym.GLUDCU or sym.GLUDCD
        end
        if symbol == sym.GRUD then
          symbol = merge_dir_above and sym.GRUDCU or sym.GRUDCD
        end
        if nn == 4 then
          symbol = merge_dir_above and sym.GFORKD or sym.GFORKU
        end

        if this.commit then
          this.connector = symbol
        end
      end
    end
  end
end

-- Lane color from the column index, cycling through the branch groups.
local BRANCH_COLORS = 5
local function lane_hl(j)
  return "GitPanelGraphBranch" .. tostring(j % BRANCH_COLORS + 1)
end

local FIELD_HLS = {
  hash = "GitPanelGraphHash",
  timestamp = "GitPanelGraphTimestamp",
  author = "GitPanelGraphAuthor",
  branch_name = "GitPanelGraphBranchName",
  tag = "GitPanelGraphTag",
}

local function graph_to_lines(graph, sym, opts)
  local lines, marks, row_commits = {}, {}, {}
  local head_lnum = nil

  -- symbols that make a horizontal run attach to the lane on its right
  local continuation_symbols = {
    sym.GCLD,
    sym.GCLU,
    sym.GFORKD,
    sym.GFORKU,
    sym.GLUDCD,
    sym.GLUDCU,
    sym.GLRDCL,
    sym.GLRUCL,
  }

  local width = 0
  for _, row in ipairs(graph) do
    if #row.cells > width then
      width = #row.cells
    end
  end
  local padding = width + 2

  for idx, row in ipairs(graph) do
    local parts, bytecol = {}, 0
    local function add(str, hl)
      if hl then
        marks[#marks + 1] = { line = idx, col = bytecol, end_col = bytecol + #str, hl = hl }
      end
      parts[#parts + 1] = str
      bytecol = bytecol + #str
    end

    -- resolve every cell's symbol first; the GHOR color lookup needs them
    for _, cell in ipairs(row.cells) do
      if cell.connector then
        cell.symbol = cell.connector
      else
        assert(cell.commit)
        if #cell.commit.parents > 1 then
          cell.symbol = #cell.commit.children == 0 and sym.merge_commit_end or sym.merge_commit
        else
          cell.symbol = #cell.commit.children == 0 and sym.commit_end or sym.commit
        end
      end
    end

    for j, cell in ipairs(row.cells) do
      local hl = nil
      if cell.commit then
        hl = lane_hl(j)
      elseif cell.symbol == sym.GHOR then
        for k = j + 1, #row.cells do
          local rcell = row.cells[k]
          if rcell.commit and vim.tbl_contains(continuation_symbols, rcell.symbol) then
            hl = lane_hl(k)
            break
          end
        end
      end
      add(cell.symbol, hl)
    end

    local commit = row.commit
    if commit then
      row_commits[idx] = commit
      add((" "):rep(padding - #row.cells))

      local branch_names = #commit.branch_names > 0 and ("(%s)"):format(table.concat(commit.branch_names, " | ")) or nil
      if not head_lnum and branch_names and branch_names:match("HEAD %->") then
        head_lnum = idx
      end

      local values = {
        hash = commit.hash:sub(1, 7),
        timestamp = commit.author_date,
        author = commit.author_name,
        branch_name = branch_names,
        tag = #commit.tags > 0 and ("(%s)"):format(table.concat(commit.tags, " | ")) or nil,
      }
      for _, name in ipairs(opts.fields) do
        local value = values[name]
        if value then
          add(" ")
          add(value, FIELD_HLS[name])
        end
      end
    elseif idx > 1 then
      -- connector rows carry the previous commit's message
      local c = graph[idx - 1].commit
      assert(c)
      row_commits[idx] = c
      add((" "):rep(padding - #row.cells))
      add((" "):rep(8))
      add(c.msg)
    end

    lines[idx] = table.concat(parts):gsub("%s+$", "")
  end

  -- The last row is a commit row with no connector row after it, so its
  -- message would otherwise never render; give it a message-only row.
  local last = graph[#graph] and graph[#graph].commit
  if last then
    lines[#lines + 1] = ((" "):rep(padding + 8) .. last.msg):gsub("%s+$", "")
    row_commits[#lines] = last
  end

  return lines, marks, head_lnum, row_commits
end

-- Testable seam: raw commits in, rendered lines out.
function M._gitgraph(raw_commits, opts)
  opts = vim.tbl_extend("force", DEFAULTS, opts or {})

  local commits, sorted_commits = process_raw_commits(raw_commits)
  populate_child_parent_data(commits, sorted_commits)
  local graph = straight_j(commits, sorted_commits)
  insert_vert_and_hor_pipes(graph, M.symbols)
  insert_symbols_on_connector_rows(graph, M.symbols)

  local lines, marks, head_lnum, row_commits = graph_to_lines(graph, M.symbols, opts)
  return { lines = lines, marks = marks, head_lnum = head_lnum, row_commits = row_commits }
end

---@return table -- { lines, marks, head_lnum, row_commits }
function M.build(root, opts)
  opts = vim.tbl_extend("force", DEFAULTS, opts or {})
  local raw = git_log(root, opts)
  if #raw == 0 then
    return { lines = { "No commits" }, marks = {}, head_lnum = nil, row_commits = {} }
  end
  return M._gitgraph(raw, opts)
end

return M
