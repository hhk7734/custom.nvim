-- VSCode-style "Source Control" sidebar: two stacked, foldable, resizable
-- sections — Changes (git status; Staged/Changes foldable sub-lists;
-- selecting a file diffs it with gitsigns) and Commits (recent history;
-- selecting a commit opens its patch). Not a plugin; mirrors
-- activitybar.lua's structure (state table, local helpers, M.open/close/
-- toggle/setup).
local M = {}

local WIDTH = 30
-- Commits section's share of the sidebar column when the panel opens.
local COMMITS_RATIO = 1 / 3
local COMMITS_LIMIT = 50
local ns = vim.api.nvim_create_namespace("gitpanel")

-- Ordered top-level sections; minwid in the winbar click regions is the
-- index here.
local SECTIONS = {
  { key = "changes", title = "Changes" },
  { key = "commits", title = "Commits" },
}

local state = {
  -- key -> { win, buf, collapsed, saved_height, lines }; `lines` maps a
  -- buffer line number to its entry, rebuilt on every render.
  sections = {
    changes = { lines = {} },
    commits = { lines = {} },
  },
  -- Fold flags for the sub-sections inside Changes.
  folded = { staged = false, changes = false },
  -- repo root resolved on the last render; nil outside a git repo.
  root = nil,
}

local function section_valid(s)
  return s.win and vim.api.nvim_win_is_valid(s.win)
end

-- First window (any tabpage) showing a buffer with this filetype.
local function find_win(ft)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == ft then
      return win
    end
  end
  return nil
end

-- autochdir is enabled in this config, so the cwd tracks whatever buffer was
-- last entered; resolve the repo root explicitly instead of relying on it.
local function repo_root()
  local out = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 or #out == 0 then
    return nil
  end
  return out[1]
end

-- Parses `git status --porcelain -z` into Staged (index status `M A D R C T`)
-- and Changes (worktree status not a space, plus untracked `??`) lists.
-- NUL-delimited output is used because git emits it unquoted: with plain
-- --porcelain, paths with spaces or non-ASCII arrive quoted/octal-escaped
-- ('"a b.txt"') and would render (and open) with the quotes verbatim.
-- vim.system (not vim.fn.system) because Vimscript strings cannot hold NUL:
-- vim.fn.system would replace the delimiters with SOH bytes.
local function git_status(root)
  local res = vim.system({ "git", "-C", root, "status", "--porcelain", "-z" }):wait()
  if res.code ~= 0 or not res.stdout then
    return {}, {}
  end

  local staged, changes = {}, {}
  local records = vim.split(res.stdout, "\0", { plain = true, trimempty = true })
  local i = 1
  while i <= #records do
    local rec = records[i]
    i = i + 1
    if #rec >= 4 then
      local x, y = rec:sub(1, 1), rec:sub(2, 2)
      local path = rec:sub(4)
      -- Renames/copies put the old path in a separate NUL field right after
      -- the record; the record's own path is already the new one. Skip it.
      if x == "R" or x == "C" or y == "R" or y == "C" then
        i = i + 1
      end

      if x == "?" and y == "?" then
        table.insert(changes, { status = "?", path = path, untracked = true })
      else
        if x ~= " " and x ~= "?" then
          table.insert(staged, { status = x, path = path })
        end
        if y ~= " " and y ~= "?" then
          table.insert(changes, { status = y, path = path })
        end
      end
    end
  end
  return staged, changes
end

-- Last COMMITS_LIMIT commits as { hash, subject } (tab-delimited; a subject
-- cannot contain the tab we split on because git strips control characters
-- from %s output).
local function git_log(root)
  local res = vim.system({ "git", "-C", root, "log", "--format=%h%x09%s", "-n", tostring(COMMITS_LIMIT) }):wait()
  if res.code ~= 0 or not res.stdout then
    return {}
  end
  local commits = {}
  for _, line in ipairs(vim.split(res.stdout, "\n", { trimempty = true })) do
    local hash, subject = line:match("^(%x+)\t(.*)$")
    if hash then
      commits[#commits + 1] = { hash = hash, subject = subject }
    end
  end
  return commits
end

local function status_hl(status)
  if status == "A" or status == "?" then
    return "Added"
  elseif status == "D" then
    return "Removed"
  end
  return "Changed" -- M R C T
end

-- File icons come from nvim-web-devicons at runtime; never hardcode
-- nerd-font/PUA glyphs in source (see repo memory).
local function file_icon(path)
  local ok, icon = pcall(function()
    local devicons = require("nvim-web-devicons")
    return devicons.get_icon(vim.fn.fnamemodify(path, ":t"), vim.fn.fnamemodify(path, ":e"), { default = true })
  end)
  return (ok and icon) or ""
end

-- Sticky, clickable section header. %@ regions need a v:lua-reachable
-- global (same pattern and reasoning as the bottom panel's PanelTabClick).
local function winbar_for(idx)
  local section = SECTIONS[idx]
  local s = state.sections[section.key]
  local marker = s.collapsed and "▸" or "▾"
  return "%#GitPanelHeader#%" .. idx .. "@v:lua.GitPanelSectionClick@ " .. marker .. " " .. section.title .. " %X"
end

local function refresh_winbars()
  for i, section in ipairs(SECTIONS) do
    local s = state.sections[section.key]
    if section_valid(s) then
      vim.wo[s.win].winbar = winbar_for(i)
    end
  end
end

-- Writes rendered lines + extmarks into a section buffer.
local function write_section(s, lines, marks)
  vim.bo[s.buf].modifiable = true
  vim.api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
  vim.bo[s.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  for lnum, m in pairs(marks) do
    vim.api.nvim_buf_set_extmark(s.buf, ns, lnum - 1, m.col, { end_col = m.end_col, hl_group = m.hl })
  end
end

local function render_changes()
  local s = state.sections.changes
  if not (s.buf and vim.api.nvim_buf_is_valid(s.buf)) then
    return
  end

  local root = repo_root()
  state.root = root

  local lines, entries, marks = {}, {}, {}
  if not root then
    lines = { "Not a git repository" }
  else
    local staged, changes = git_status(root)
    if #staged == 0 and #changes == 0 then
      lines = { "No changes" }
    else
      -- A foldable sub-list: header line plus (unless folded) file lines.
      local function add_group(name, flag, items)
        if #items == 0 then
          return
        end
        local marker = state.folded[flag] and "▸" or "▾"
        table.insert(lines, marker .. " " .. name)
        entries[#lines] = { header = flag }
        marks[#lines] = { col = 0, end_col = #lines[#lines], hl = "Title" }
        if state.folded[flag] then
          return
        end
        for _, item in ipairs(items) do
          local icon = file_icon(item.path)
          table.insert(lines, string.format("  %s %s %s", item.status, icon, item.path))
          entries[#lines] = {
            path = root .. "/" .. item.path,
            section = flag,
            untracked = item.untracked,
            status = item.status,
          }
          -- The status letter sits right after the 2-space indent.
          marks[#lines] = { col = 2, end_col = 3, hl = status_hl(item.status) }
        end
      end
      add_group("Staged", "staged", staged)
      add_group("Changes", "changes", changes)
    end
  end

  s.lines = entries
  write_section(s, lines, marks)
end

local function render_commits()
  local s = state.sections.commits
  if not (s.buf and vim.api.nvim_buf_is_valid(s.buf)) then
    return
  end

  local root = state.root or repo_root()
  local lines, entries, marks = {}, {}, {}
  if not root then
    lines = { "Not a git repository" }
  else
    for _, c in ipairs(git_log(root)) do
      table.insert(lines, string.format(" %s %s", c.hash, c.subject))
      entries[#lines] = { hash = c.hash }
      marks[#lines] = { col = 1, end_col = 1 + #c.hash, hl = "Identifier" }
    end
    if #lines == 0 then
      lines = { "No commits" }
    end
  end

  s.lines = entries
  write_section(s, lines, marks)
end

local function render()
  render_changes()
  render_commits()
  refresh_winbars()
end

-- Wipes the previous selection's views: `diffoff!` plus closing gitsigns
-- revision windows. Commit patch buffers need no handling here: they are
-- bufhidden=wipe and every selection replaces them in the reused main
-- window, which hides (and thus wipes) them. Deleting them explicitly
-- while displayed would close the main window and leak its width into the
-- winfixwidth sidebar.
local function close_diffs()
  pcall(vim.cmd, "diffoff!")
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
    if vim.startswith(name, "gitsigns://") then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

-- First window that isn't a sidebar/panel occupant; nil if none exist.
local function main_win()
  local exclude = { activitybar = true, gitpanel = true, NvimTree = true, panelterminal = true, panelproblems = true }
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not exclude[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] then
      return win
    end
  end
  return nil
end

local function select_entry(entry)
  if not entry then
    return
  end

  close_diffs()

  local win = main_win()
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("botright vsplit")
  end

  vim.cmd("edit " .. vim.fn.fnameescape(entry.path))

  if entry.untracked then
    render()
    return
  end

  -- gitsigns attaches to a freshly-opened buffer asynchronously (its own
  -- BufReadPost autocmd triggers it) and only fills in compare_text (the
  -- index diff base) once that finishes; diffthis() asserts on it being
  -- present, so poll the cache instead of racing it. (Calling attach()
  -- again here would just be de-duplicated against the in-flight one, with
  -- its callback firing immediately rather than on completion.) vim.wait
  -- keeps the event loop turning while it does.
  local bufnr = vim.api.nvim_get_current_buf()
  local base = entry.section == "staged" and "HEAD" or nil
  vim.wait(1000, function()
    local bcache = require("gitsigns.cache").cache[bufnr]
    return bcache ~= nil and bcache.compare_text ~= nil
  end, 20)
  if vim.api.nvim_buf_is_valid(bufnr) then
    require("gitsigns").diffthis(base, { vertical = true })
  end

  -- gitsigns.diffthis restores focus to this window (the file just opened);
  -- VSCode moves focus to the diff too, so the panel is left unfocused.
  render()
end

-- Opens a commit's full patch as a read-only scratch buffer in a main
-- window; a newly selected commit replaces the previous one.
local function open_commit(entry)
  if not (entry and entry.hash and state.root) then
    return
  end

  local res = vim.system({ "git", "-C", state.root, "show", entry.hash }):wait()
  if res.code ~= 0 or not res.stdout then
    return
  end

  close_diffs()

  local win = main_win()
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("botright vsplit")
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "gitpanel://commit/" .. entry.hash)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(res.stdout, "\n"))
  vim.bo[buf].filetype = "git"
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_win_set_buf(0, buf)
end

local function toggle_fold(flag)
  state.folded[flag] = not state.folded[flag]
  render_changes()
end

-- Shared by <CR> and routed clicks: acts on one entry of one section.
local function activate(key, entry)
  if not entry then
    return
  end
  if key == "commits" then
    open_commit(entry)
  elseif entry.header then
    toggle_fold(entry.header)
  else
    select_entry(entry)
  end
end

local function select_current(key)
  local s = state.sections[key]
  if not section_valid(s) then
    return
  end
  activate(key, s.lines[vim.api.nvim_win_get_cursor(s.win)[1]])
end

-- Routed here by activitybar's global <LeftMouse> dispatcher. A buffer-local
-- mapping would shadow that dispatcher while the panel has focus, swallowing
-- clicks on the rest of the UI. Returns true when the click belongs to a
-- section window; winbar clicks (winrow 1) fall through so the native %@
-- header regions receive them.
function M.click(pos)
  for _, section in ipairs(SECTIONS) do
    local s = state.sections[section.key]
    if section_valid(s) and pos.winid == s.win then
      if pos.winrow == 1 then
        return false
      end
      vim.schedule(function()
        if not section_valid(s) or pos.line == 0 then
          return
        end
        pcall(vim.api.nvim_win_set_cursor, s.win, { pos.line, 0 })
        local entry = s.lines[pos.line]
        if entry then
          activate(section.key, entry)
        else
          -- Blank row: just focus the panel for keyboard navigation.
          vim.api.nvim_set_current_win(s.win)
        end
      end)
      return true
    end
  end
  return false
end

-- Collapse a section to its winbar header; expanding restores the height
-- it had before collapsing. winfixheight makes the collapsed height stick
-- while the neighbor section absorbs the space.
local function set_collapsed(key, collapsed)
  local s = state.sections[key]
  if not section_valid(s) or s.collapsed == collapsed then
    return
  end
  s.collapsed = collapsed
  if collapsed then
    s.saved_height = vim.api.nvim_win_get_height(s.win)
    vim.api.nvim_win_set_height(s.win, 1)
    vim.wo[s.win].winfixheight = true
  else
    vim.wo[s.win].winfixheight = false
    if s.saved_height then
      pcall(vim.api.nvim_win_set_height, s.win, s.saved_height)
    end
  end
  refresh_winbars()
end

-- Winbar %@ click handler; must be a v:lua-reachable global.
-- minwid: SECTIONS index.
_G.GitPanelSectionClick = function(minwid, _, button)
  if button ~= "l" then
    return
  end
  local section = SECTIONS[minwid]
  if section then
    set_collapsed(section.key, not state.sections[section.key].collapsed)
  end
end

local function setup_buffer(key)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "gitpanel"
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "hide"

  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "<CR>", function()
    select_current(key)
  end, vim.tbl_extend("force", opts, { desc = "git panel: select" }))
  vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", opts, { desc = "git panel: close" }))
  vim.keymap.set("n", "R", render, vim.tbl_extend("force", opts, { desc = "git panel: refresh" }))
  return buf
end

local function style_window(win, idx)
  local wo = vim.wo[win]
  wo.winfixwidth = true
  wo.winfixbuf = true
  wo.number = false
  wo.relativenumber = false
  wo.cursorline = true
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.statuscolumn = ""
  wo.wrap = false
  wo.fillchars = "eob: "
  wo.winbar = winbar_for(idx)
end

function M.open()
  local changes, commits = state.sections.changes, state.sections.commits
  if section_valid(changes) then
    vim.api.nvim_set_current_win(changes.win)
    return
  end

  -- One sidebar occupant at a time, as in VSCode.
  pcall(function()
    require("nvim-tree.api").tree.close()
  end)

  for key, s in pairs(state.sections) do
    if not (s.buf and vim.api.nvim_buf_is_valid(s.buf)) then
      s.buf = setup_buffer(key)
    end
  end

  local bar_win = find_win("activitybar")
  if bar_win then
    changes.win = vim.api.nvim_open_win(changes.buf, true, {
      win = bar_win,
      split = "right",
      width = WIDTH,
    })
  else
    vim.cmd("topleft " .. WIDTH .. "vsplit")
    changes.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(changes.win, changes.buf)
  end

  local total = vim.api.nvim_win_get_height(changes.win)
  commits.win = vim.api.nvim_open_win(commits.buf, false, {
    win = changes.win,
    split = "below",
    height = math.max(3, math.floor(total * COMMITS_RATIO)),
  })

  style_window(changes.win, 1)
  style_window(commits.win, 2)
  changes.collapsed, commits.collapsed = false, false

  render()
end

function M.close()
  for _, s in pairs(state.sections) do
    if section_valid(s) then
      -- Closing the last window of a tabpage is an error (E444).
      local tab = vim.api.nvim_win_get_tabpage(s.win)
      if #vim.api.nvim_tabpage_list_wins(tab) > 1 then
        vim.api.nvim_win_close(s.win, true)
      end
    end
    s.win = nil
  end
end

function M.toggle()
  if section_valid(state.sections.changes) or section_valid(state.sections.commits) then
    M.close()
  else
    M.open()
  end
end

function M.setup()
  vim.api.nvim_set_hl(0, "GitPanelHeader", { link = "Title", default = true })

  local group = vim.api.nvim_create_augroup("gitpanel", {})

  vim.api.nvim_create_autocmd({ "BufWritePost", "FocusGained" }, {
    group = group,
    callback = function()
      vim.schedule(render)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "GitSignsUpdate",
    callback = function()
      vim.schedule(render)
    end,
  })

  vim.api.nvim_create_user_command("GitPanel", function(cmd)
    M[cmd.args ~= "" and cmd.args or "toggle"]()
  end, {
    nargs = "?",
    complete = function()
      return { "open", "close", "toggle" }
    end,
  })
end

return M
