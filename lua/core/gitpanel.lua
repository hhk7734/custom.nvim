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
  -- Fold flags for changes section directories.
  change_dir_expanded = {},
  -- Fold flags for commits and their changed directories.
  commit_expanded = {},
  commit_dir_expanded = {},
  commit_files = {},
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

local function git_commit_files(root, hash)
  local res = vim
    .system({
      "git",
      "-C",
      root,
      "diff-tree",
      "--root",
      "--no-commit-id",
      "--name-status",
      "-r",
      "-z",
      hash,
    })
    :wait()
  if res.code ~= 0 or not res.stdout then
    return {}
  end

  local files = {}
  local records = vim.split(res.stdout, "\0", { plain = true, trimempty = true })
  local i = 1
  while i <= #records do
    local status = records[i]
    i = i + 1
    local code = status:sub(1, 1)
    if code == "R" or code == "C" then
      local old_path, new_path = records[i], records[i + 1]
      i = i + 2
      if new_path then
        files[#files + 1] = { status = code, old_path = old_path, path = new_path }
      end
    else
      local path = records[i]
      i = i + 1
      if path then
        files[#files + 1] = { status = code, path = path }
      end
    end
  end
  return files
end

local function commit_dir_key(hash, dir)
  return hash .. "\0" .. dir
end

local function change_dir_key(section, dir)
  return section .. "\0" .. dir
end

local function new_tree_node(name, path)
  return { name = name, path = path, dirs = {}, files = {} }
end

local function normalize_commit_file(item)
  if type(item) == "string" then
    return { path = item }
  end
  return item
end

local function build_file_tree(files)
  local root = new_tree_node("", "")
  for _, raw in ipairs(files) do
    local item = normalize_commit_file(raw)
    local parts = vim.split(item.path, "/", { plain = true, trimempty = true })
    local node = root
    local prefix = {}
    for i = 1, #parts - 1 do
      prefix[#prefix + 1] = parts[i]
      local dir_path = table.concat(prefix, "/")
      node.dirs[parts[i]] = node.dirs[parts[i]] or new_tree_node(parts[i], dir_path)
      node = node.dirs[parts[i]]
    end
    if #parts > 0 then
      node.files[#node.files + 1] = {
        name = parts[#parts],
        old_path = item.old_path,
        path = item.path,
        status = item.status,
        untracked = item.untracked,
      }
    end
  end
  return root
end

local function sorted_dirs(dirs)
  local out = vim.tbl_values(dirs)
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

local function sorted_files(files)
  table.sort(files, function(a, b)
    return a.name < b.name
  end)
  return files
end

local function tree_icons()
  local ok, config = pcall(require, "nvim-tree.config")
  local renderer = ok and ((config.g and config.g.renderer) or (config.d and config.d.renderer)) or nil
  local icons = renderer and renderer.icons or {}
  local glyphs = icons.glyphs or {}
  local folder = glyphs.folder or {}
  local padding = icons.padding or {}
  return {
    arrow_closed = folder.arrow_closed or "",
    arrow_open = folder.arrow_open or "",
    file_default = glyphs.default or "",
    folder_default = folder.default or "",
    folder_open = folder.open or "",
    icon_padding = padding.icon or " ",
    folder_arrow_padding = padding.folder_arrow or " ",
  }
end

local function tree_arrow(expanded)
  local icons = tree_icons()
  return (expanded and icons.arrow_open or icons.arrow_closed) .. icons.folder_arrow_padding
end

local function tree_folder_icon(expanded)
  local icons = tree_icons()
  return expanded and icons.folder_open or icons.folder_default
end

local function tree_file_icon(path)
  local ok, icon = pcall(function()
    local devicons = require("nvim-web-devicons")
    return devicons.get_icon(vim.fn.fnamemodify(path, ":t"), vim.fn.fnamemodify(path, ":e"), { default = true })
  end)
  return (ok and icon) or tree_icons().file_default
end

local function render_tree_node(node, hash, dir_expanded, indent, lines, entries)
  for _, dir in ipairs(sorted_dirs(node.dirs)) do
    local expanded = dir_expanded[commit_dir_key(hash, dir.path)] ~= false
    local arrow = tree_arrow(expanded)
    local icon = tree_folder_icon(expanded)
    lines[#lines + 1] = string.rep(" ", indent) .. arrow .. icon .. tree_icons().icon_padding .. dir.name
    entries[#lines] = { hash = hash, dir = dir.path }
    if expanded then
      render_tree_node(dir, hash, dir_expanded, indent + 2, lines, entries)
    end
  end
  for _, file in ipairs(sorted_files(node.files)) do
    lines[#lines + 1] = string.rep(" ", indent) .. tree_file_icon(file.path) .. tree_icons().icon_padding .. file.name
    entries[#lines] = {
      hash = hash,
      old_path = file.old_path,
      path = file.path,
      status = file.status,
    }
  end
end

local function render_commit_file_tree(paths, hash, dir_expanded)
  local lines, entries = {}, {}
  render_tree_node(build_file_tree(paths), hash, dir_expanded, 2, lines, entries)
  return lines, entries
end

local function status_hl(status)
  if status == "A" or status == "?" then
    return "Added"
  elseif status == "D" then
    return "Removed"
  end
  return "Changed" -- M R C T
end

local function status_label(status, untracked)
  if untracked or status == "A" or status == "?" then
    return "added"
  elseif status == "D" then
    return "deleted"
  end
  return "modified" -- M R C T and any other tracked content change
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

local function render_change_tree_node(node, root, section, indent, lines, entries, marks)
  for _, dir in ipairs(sorted_dirs(node.dirs)) do
    local expanded = state.change_dir_expanded[change_dir_key(section, dir.path)] ~= false
    local arrow = tree_arrow(expanded)
    local icon = tree_folder_icon(expanded)
    lines[#lines + 1] = string.rep(" ", indent) .. arrow .. icon .. tree_icons().icon_padding .. dir.name
    entries[#lines] = { change_dir = dir.path, section = section }
    if expanded then
      render_change_tree_node(dir, root, section, indent + 2, lines, entries, marks)
    end
  end

  for _, file in ipairs(sorted_files(node.files)) do
    local label = status_label(file.status, file.untracked)
    lines[#lines + 1] = string.rep(" ", indent)
      .. tree_file_icon(file.path)
      .. tree_icons().icon_padding
      .. file.name
      .. " ["
      .. label
      .. "]"
    entries[#lines] = {
      path = root .. "/" .. file.path,
      repo_path = file.path,
      section = section,
      untracked = file.untracked,
      status = file.status,
    }
    local label_start = lines[#lines]:find("[" .. label .. "]", 1, true)
    if label_start then
      marks[#lines] = { col = label_start - 1, end_col = #lines[#lines], hl = status_hl(file.status) }
    end
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
      -- A foldable sub-list: header line plus a nvim-tree style file tree.
      local function add_group(name, flag, items)
        if #items == 0 then
          return
        end
        local expanded = not state.folded[flag]
        local marker = tree_arrow(expanded)
        local icon = tree_folder_icon(expanded)
        table.insert(lines, marker .. icon .. tree_icons().icon_padding .. name)
        entries[#lines] = { header = flag }
        marks[#lines] = { col = 0, end_col = #lines[#lines], hl = "Title" }
        if not expanded then
          return
        end
        render_change_tree_node(build_file_tree(items), root, flag, 2, lines, entries, marks)
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
      local marker = tree_arrow(state.commit_expanded[c.hash])
      table.insert(lines, string.format("%s%s %s", marker, c.hash, c.subject))
      entries[#lines] = { hash = c.hash }
      local hash_start = lines[#lines]:find(c.hash, 1, true) - 1
      marks[#lines] = { col = hash_start, end_col = hash_start + #c.hash, hl = "Identifier" }

      if state.commit_expanded[c.hash] then
        state.commit_files[c.hash] = state.commit_files[c.hash] or git_commit_files(root, c.hash)
        local tree_lines, tree_entries =
          render_commit_file_tree(state.commit_files[c.hash], c.hash, state.commit_dir_expanded)
        if #tree_lines == 0 then
          table.insert(lines, "  No files")
        else
          for i, line in ipairs(tree_lines) do
            table.insert(lines, line)
            entries[#lines] = tree_entries[i]
            if tree_entries[i].dir then
              local icons = tree_icons()
              local arrow_start = line:find(icons.arrow_open, 1, true) or line:find(icons.arrow_closed, 1, true)
              if arrow_start then
                marks[#lines] = { col = arrow_start - 1, end_col = arrow_start + #icons.arrow_open, hl = "Title" }
              end
            end
          end
        end
      end
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

local function is_gitpanel_diff_view(name)
  return vim.startswith(name, "gitpanel://previous/")
    or vim.startswith(name, "gitpanel://updated/")
    or vim.startswith(name, "gitpanel://commit-previous/")
    or vim.startswith(name, "gitpanel://commit-updated/")
end

-- Wipes previous diff state before opening another selection. When `keep_one`
-- is true, one existing GitPanel diff scratch window is reused as the next main
-- editor window, so closing stale panes cannot make the sidebar absorb the
-- whole editor area.
local function close_diffs(keep_one)
  pcall(vim.cmd, "diffoff!")
  local keep_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
    if vim.startswith(name, "gitsigns://") then
      pcall(vim.api.nvim_win_close, win, true)
    elseif is_gitpanel_diff_view(name) then
      if keep_one and not keep_win then
        keep_win = win
      else
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
  return keep_win
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

local function change_repo_path(entry, root)
  if entry.repo_path then
    return entry.repo_path
  end
  local prefix = root and (root .. "/") or nil
  if prefix and vim.startswith(entry.path, prefix) then
    return entry.path:sub(#prefix + 1)
  end
  return vim.fn.fnamemodify(entry.path, ":.")
end

local function git_blob_lines(root, spec)
  local res = vim.system({ "git", "-C", root, "show", spec }):wait()
  if res.code ~= 0 or not res.stdout then
    return nil
  end
  return vim.split(res.stdout:gsub("\n$", ""), "\n", { plain = true })
end

local function read_file_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or {}
end

local function scratch_buffer(name, lines, path)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local ft = vim.filetype.match({ filename = path })
  if ft then
    vim.bo[buf].filetype = ft
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  return buf
end

local function open_scratch(name, lines, path)
  local win = close_diffs(true) or main_win()
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("botright vsplit")
  end
  vim.api.nvim_win_set_buf(0, scratch_buffer(name, lines, path))
end

local function show_side_by_side(previous_name, previous_lines, updated_name, updated_lines, path)
  local win = close_diffs(true) or main_win()
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("botright vsplit")
  end

  local left = scratch_buffer(previous_name, previous_lines, path)
  local right = scratch_buffer(updated_name, updated_lines or {}, path)

  local left_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(left_win, left)
  vim.cmd("rightbelow vertical split")
  local right_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(right_win, right)

  vim.api.nvim_win_call(left_win, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_win_call(right_win, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_set_current_win(right_win)
end

local function show_change_diff(entry)
  local root = state.root or repo_root()
  if not root then
    return
  end
  local repo_path = change_repo_path(entry, root)

  local previous_spec = entry.section == "staged" and ("HEAD:" .. repo_path) or (":" .. repo_path)
  local updated_lines = entry.section == "staged" and git_blob_lines(root, ":" .. repo_path)
    or read_file_lines(entry.path)
  local previous_lines = git_blob_lines(root, previous_spec) or {}

  show_side_by_side(
    "gitpanel://previous/" .. repo_path,
    previous_lines,
    "gitpanel://updated/" .. repo_path,
    updated_lines or {},
    repo_path
  )
end

local function is_added_entry(entry)
  return entry.untracked or entry.status == "A" or entry.status == "?"
end

local function select_entry(entry)
  if not entry then
    return
  end

  if is_added_entry(entry) then
    local win = close_diffs(true) or main_win()
    if win then
      vim.api.nvim_set_current_win(win)
    else
      vim.cmd("botright vsplit")
    end
    vim.cmd("edit " .. vim.fn.fnameescape(entry.path))
    render()
    return
  end

  show_change_diff(entry)
  render()
end

-- Opens a commit file in the main area. Added files show their committed
-- contents directly; changed files show parent version on the left and the
-- committed version on the right.
local function open_commit_file(entry)
  if not (entry and entry.hash and entry.path and state.root) then
    return
  end

  local updated_lines = git_blob_lines(state.root, entry.hash .. ":" .. entry.path) or {}
  local name = "gitpanel://commit/" .. entry.hash .. "/" .. entry.path
  if is_added_entry(entry) then
    open_scratch(name, updated_lines, entry.path)
    return
  end

  local previous_path = entry.old_path or entry.path
  local previous_lines = git_blob_lines(state.root, entry.hash .. "^:" .. previous_path) or {}
  show_side_by_side(
    "gitpanel://commit-previous/" .. entry.hash .. "/" .. previous_path,
    previous_lines,
    "gitpanel://commit-updated/" .. entry.hash .. "/" .. entry.path,
    updated_lines,
    entry.path
  )
end

local function toggle_change_dir(section, dir)
  local key = change_dir_key(section, dir)
  state.change_dir_expanded[key] = state.change_dir_expanded[key] == false
  render_changes()
end

local function toggle_commit(hash)
  state.commit_expanded[hash] = not state.commit_expanded[hash]
  render_commits()
end

local function toggle_commit_dir(hash, dir)
  local key = commit_dir_key(hash, dir)
  state.commit_dir_expanded[key] = state.commit_dir_expanded[key] == false
  render_commits()
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
    if entry.path then
      open_commit_file(entry)
    elseif entry.dir then
      toggle_commit_dir(entry.hash, entry.dir)
    elseif entry.hash then
      toggle_commit(entry.hash)
    end
  elseif entry.header then
    toggle_fold(entry.header)
  elseif entry.change_dir then
    toggle_change_dir(entry.section, entry.change_dir)
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
        if entry and entry.path then
          activate(section.key, entry)
        else
          -- Nvim-tree style: a single click focuses/selects foldable rows;
          -- <CR> or double-click performs the row action.
          vim.api.nvim_set_current_win(s.win)
        end
      end)
      return true
    end
  end
  return false
end

local function double_click_current(key)
  local pos = vim.fn.getmousepos()
  local s = state.sections[key]
  if section_valid(s) and pos.winid == s.win and pos.line > 0 then
    pcall(vim.api.nvim_win_set_cursor, s.win, { pos.line, 0 })
  end
  select_current(key)
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
  vim.keymap.set("n", "<2-LeftMouse>", function()
    double_click_current(key)
  end, vim.tbl_extend("force", opts, { desc = "git panel: double-click select" }))
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

M._test = {
  render_commit_file_tree = render_commit_file_tree,
  open_change_entry = select_entry,
  open_commit_entry = function(root, entry)
    state.root = root
    open_commit_file(entry)
  end,
}

return M
