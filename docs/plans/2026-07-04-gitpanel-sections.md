# GitPanel Sections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the Source Control sidebar into foldable, resizable Changes and Commits sections (Staged/Changes as foldable sub-sections; commits open their patch), per `docs/specs/2026-07-04-gitpanel-sections.md`.

**Architecture:** gitpanel becomes two stacked windows in the sidebar column, each with a clickable winbar header (collapse = height 1 + `winfixheight`); sub-sections fold by re-rendering. The activity bar's `ensure_layout` is upgraded first — from "the sidebar is one leaf" to "the sidebar is a frame (leaf or col of sidebar windows)" with a stack-rebuilding repair — because the old reconciler would tear a stacked sidebar apart on every window event.

**Tech Stack:** Neovim (Lua) only. No plugin changes.

**Context notes for the implementer:**
- TASK ORDER IS LOAD-BEARING: Task 1 (reconciler) must be committed before Task 2 (stacked windows) ever runs.
- Headless: the activity bar does not auto-open; open panels explicitly. 80x24 screen → bar w5 col0, sidebar w30 col6, editor col37, column height 21.
- Repo rules: no hardcoded nerd-font PUA glyphs (the existing `file_icon` handles this); stylua on changed Lua files (`~/.local/share/nvim/mason/bin/stylua`); single-scope Conventional Commits.
- `▾`/`▸` (U+25BE/U+25B8) are single-width and safe to hardcode (not PUA).
- Deterministic Changes-list tests need a dirty scratch repo; build one in the scratchpad (Task 2 Step 4).

---

### Task 1: Frame-aware layout reconciler

**Files:**
- Modify: `lua/core/activitybar.lua` (replace `sidebar_win` and the sidebar half of `ensure_layout`; keep `is_column` for the bar)

- [ ] **Step 1: Replace `sidebar_win` with `sidebar_wins` + frame helpers**

Replace the existing `sidebar_win` function (keep `SIDEBAR_FTS` above it) with:

```lua
-- All non-floating sidebar windows in the current tabpage, ordered by
-- screen row (gitpanel stacks section windows in one column).
local function sidebar_wins()
  local wins = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if
      SIDEBAR_FTS[vim.bo[vim.api.nvim_win_get_buf(win)].filetype]
      and vim.api.nvim_win_get_config(win).relative == ""
    then
      wins[#wins + 1] = win
    end
  end
  table.sort(wins, function(a, b)
    return vim.api.nvim_win_get_position(a)[1] < vim.api.nvim_win_get_position(b)[1]
  end)
  return wins
end

-- Leaf windows of a winlayout frame, in order.
local function frame_leaves(frame, acc)
  acc = acc or {}
  if frame[1] == "leaf" then
    acc[#acc + 1] = frame[2]
  else
    for _, child in ipairs(frame[2]) do
      frame_leaves(child, acc)
    end
  end
  return acc
end

-- true if the given windows form one full-height sidebar frame: a direct
-- child of the top-level row that is a leaf (single window) or a "col"
-- containing exactly these windows and nothing else.
local function is_sidebar_frame(wins)
  local root = vim.fn.winlayout()
  if root[1] ~= "row" then
    return false
  end
  local want = {}
  for _, w in ipairs(wins) do
    want[w] = true
  end
  for _, frame in ipairs(root[2]) do
    local leaves = frame_leaves(frame)
    local all = #leaves == #wins
    for _, w in ipairs(leaves) do
      if not want[w] then
        all = false
      end
    end
    if all then
      return true
    end
  end
  return false
end
```

- [ ] **Step 2: Rewrite the sidebar half of `ensure_layout`**

Replace the body of `ensure_layout` (keep its comment, precondition, and the
bar re-assert) with:

```lua
local function ensure_layout()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
    render()
    return
  end

  local sidebar = sidebar_wins()
  local bar_ok = is_column(state.win)
    and vim.api.nvim_win_get_position(state.win)[2] == 0
    and vim.api.nvim_win_get_width(state.win) == WIDTH
  local sidebar_ok = #sidebar == 0
    or (is_sidebar_frame(sidebar) and vim.api.nvim_win_get_position(sidebar[1])[2] == WIDTH + 1)

  if not (bar_ok and sidebar_ok) then
    if #sidebar > 0 then
      -- Rebuild the sidebar as one full-height column: lead window first,
      -- remaining section windows re-stacked beneath it, preserving the
      -- sections' height ratio across the rebuild.
      local width = vim.api.nvim_win_get_width(sidebar[1])
      local heights, old_total = {}, 0
      for i, w in ipairs(sidebar) do
        heights[i] = vim.api.nvim_win_get_height(w)
        old_total = old_total + heights[i]
      end
      vim.api.nvim_win_call(sidebar[1], function()
        vim.cmd("wincmd H")
      end)
      for i = 2, #sidebar do
        pcall(vim.fn.win_splitmove, sidebar[i], sidebar[i - 1], { vertical = false, rightbelow = true })
      end
      vim.api.nvim_win_set_width(sidebar[1], width)
      local new_total = 0
      for _, w in ipairs(sidebar) do
        new_total = new_total + vim.api.nvim_win_get_height(w)
      end
      for i = 1, #sidebar - 1 do
        pcall(vim.api.nvim_win_set_height, sidebar[i], math.max(1, math.floor(new_total * heights[i] / old_total)))
      end
    end
    vim.api.nvim_win_call(state.win, function()
      vim.cmd("wincmd H")
      vim.cmd("vertical resize " .. WIDTH)
    end)
  end

  render()
end
```

- [ ] **Step 3: Verify the single-window matrix still passes**

Run:
```sh
nvim --headless "+lua require('core.activitybar').open() require('nvim-tree.api').tree.open() require('core.panel').toggle('terminal') vim.wait(500) local win = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do win[vim.bo[vim.api.nvim_win_get_buf(w)].filetype] = w end print('A sidebar_full=' .. tostring(vim.api.nvim_win_get_height(win.NvimTree) == vim.api.nvim_win_get_height(win.activitybar)) .. ' panel_col=' .. vim.api.nvim_win_get_position(win.panelterminal)[2])" +qa! 2>&1
nvim --headless "+lua require('core.activitybar').open() require('core.gitpanel').open() require('core.panel').toggle('terminal') vim.wait(500) local win = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do win[vim.bo[vim.api.nvim_win_get_buf(w)].filetype] = w end print('B sidebar_full=' .. tostring(vim.api.nvim_win_get_height(win.gitpanel) == vim.api.nvim_win_get_height(win.activitybar)) .. ' panel_col=' .. vim.api.nvim_win_get_position(win.panelterminal)[2])" +qa! 2>&1
```
Expected: `A sidebar_full=true panel_col=37`, `B sidebar_full=true panel_col=37`.

- [ ] **Step 4: Format and commit**

```sh
stylua lua/core/activitybar.lua
git add lua/core/activitybar.lua
git commit -m "feat(activitybar): reconcile stacked sidebar windows"
```

---

### Task 2: gitpanel sections rewrite

**Files:**
- Rewrite: `lua/core/gitpanel.lua` (full file below)

- [ ] **Step 1: Replace the entire file with**

```lua
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

-- Wipes the previous selection's views: `diffoff!`, gitsigns revision
-- windows, and any previously opened commit patch buffer.
local function close_diffs()
  pcall(vim.cmd, "diffoff!")
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
    if vim.startswith(name, "gitsigns://") then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.startswith(vim.api.nvim_buf_get_name(buf), "gitpanel://commit/") then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
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
```

- [ ] **Step 2: Verify — two stacked sections, widths, heights**

Run:
```sh
nvim --headless "+lua require('core.activitybar').open() require('core.gitpanel').open() vim.wait(300) local wins = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'gitpanel' then wins[#wins + 1] = w end end table.sort(wins, function(a, b) return vim.api.nvim_win_get_position(a)[1] < vim.api.nvim_win_get_position(b)[1] end) print('count=' .. #wins .. ' col=' .. vim.api.nvim_win_get_position(wins[1])[2] .. ',' .. vim.api.nvim_win_get_position(wins[2])[2] .. ' w=' .. vim.api.nvim_win_get_width(wins[1]) .. ',' .. vim.api.nvim_win_get_width(wins[2]) .. ' h2=' .. vim.api.nvim_win_get_height(wins[2]))" +qa! 2>&1
```
Expected: `count=2 col=6,6 w=30,30 h2=7` (⅓ of the 21-row column, floored; changes gets the rest minus the separator).

- [ ] **Step 3: Verify — winbar headers and collapse round-trip**

Run:
```sh
nvim --headless "+lua require('core.gitpanel').open() vim.wait(300) local wins = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'gitpanel' then wins[#wins + 1] = w end end table.sort(wins, function(a, b) return vim.api.nvim_win_get_position(a)[1] < vim.api.nvim_win_get_position(b)[1] end) local s1 = vim.api.nvim_eval_statusline(vim.wo[wins[1]].winbar, { winid = wins[1], use_winbar = true }).str local s2 = vim.api.nvim_eval_statusline(vim.wo[wins[2]].winbar, { winid = wins[2], use_winbar = true }).str print('headers=' .. tostring(s1:find('Changes') ~= nil and s2:find('Commits') ~= nil)) local h = vim.api.nvim_win_get_height(wins[2]) GitPanelSectionClick(2, 1, 'l') print('collapsed_h=' .. vim.api.nvim_win_get_height(wins[2]) .. ' marker=' .. tostring(vim.wo[wins[2]].winbar:find('▸') ~= nil)) GitPanelSectionClick(2, 1, 'l') print('restored=' .. tostring(vim.api.nvim_win_get_height(wins[2]) == h))" +qa! 2>&1
```
Expected: `headers=true`, `collapsed_h=1 marker=true`, `restored=true`.

- [ ] **Step 4: Verify — sub-section folds against a dirty scratch repo**

Run:
```sh
cd /tmp/claude-1000/-home-hhk7734--config-nvim/2ce2bc3c-ebbd-4455-869f-367b29cfed88/scratchpad && rm -rf foldtest && mkdir foldtest && cd foldtest && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init && printf 'x\n' > f.txt && git add f.txt && printf 'y\n' > g.txt
nvim --headless "+lua require('core.gitpanel').open() vim.wait(300) local wins = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'gitpanel' then wins[#wins + 1] = w end end table.sort(wins, function(a, b) return vim.api.nvim_win_get_position(a)[1] < vim.api.nvim_win_get_position(b)[1] end) local buf = vim.api.nvim_win_get_buf(wins[1]) local before = #vim.api.nvim_buf_get_lines(buf, 0, -1, false) vim.api.nvim_set_current_win(wins[1]) vim.api.nvim_win_set_cursor(wins[1], { 1, 0 }) vim.fn.maparg('<CR>', 'n', false, true).callback() local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false) print('before=' .. before .. ' after=' .. #lines .. ' folded_marker=' .. tostring(lines[1]:find('▸') ~= nil)) vim.fn.maparg('<CR>', 'n', false, true).callback() print('unfolded=' .. tostring(#vim.api.nvim_buf_get_lines(buf, 0, -1, false) == before))" +qa! 2>&1
```
Expected: `before=4 after=3 folded_marker=true` (Staged header + file gone → header only, Changes group intact), `unfolded=true`. (Run from the `foldtest` directory.)

- [ ] **Step 5: Verify — commits render and open a patch**

Run (from the config repo):
```sh
nvim --headless "+lua require('core.gitpanel').open() vim.wait(300) local wins = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'gitpanel' then wins[#wins + 1] = w end end table.sort(wins, function(a, b) return vim.api.nvim_win_get_position(a)[1] < vim.api.nvim_win_get_position(b)[1] end) local cbuf = vim.api.nvim_win_get_buf(wins[2]) local n = #vim.api.nvim_buf_get_lines(cbuf, 0, -1, false) local head = vim.fn.systemlist({ 'git', 'rev-parse', '--short', 'HEAD' })[1] local first = vim.api.nvim_buf_get_lines(cbuf, 0, 1, false)[1] print('commits=' .. n .. ' head_first=' .. tostring(first:find(head, 1, true) ~= nil)) vim.api.nvim_set_current_win(wins[2]) vim.api.nvim_win_set_cursor(wins[2], { 1, 0 }) vim.fn.maparg('<CR>', 'n', false, true).callback() local shown = vim.api.nvim_get_current_buf() print('patch=' .. vim.api.nvim_buf_get_name(shown):match('gitpanel://commit/(%x+)') .. ' ft=' .. vim.bo[shown].filetype)" +qa! 2>&1
```
Expected: `commits=50 head_first=true`, then `patch=<HEAD short hash> ft=git`.

- [ ] **Step 6: Verify — fold state survives refresh**

Run (from the `foldtest` directory):
```sh
cd /tmp/claude-1000/-home-hhk7734--config-nvim/2ce2bc3c-ebbd-4455-869f-367b29cfed88/scratchpad/foldtest && nvim --headless "+lua require('core.gitpanel').open() vim.wait(300) local wins = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'gitpanel' then wins[#wins + 1] = w end end table.sort(wins, function(a, b) return vim.api.nvim_win_get_position(a)[1] < vim.api.nvim_win_get_position(b)[1] end) vim.api.nvim_set_current_win(wins[1]) vim.api.nvim_win_set_cursor(wins[1], { 1, 0 }) vim.fn.maparg('<CR>', 'n', false, true).callback() vim.fn.maparg('R', 'n', false, true).callback() local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(wins[1]), 0, -1, false) print('still_folded=' .. tostring(lines[1]:find('▸') ~= nil))" +qa! 2>&1
```
Expected: `still_folded=true`.

- [ ] **Step 7: Format and commit**

```sh
stylua lua/core/gitpanel.lua
git add lua/core/gitpanel.lua
git commit -m "feat(gitpanel): split the sidebar into Changes and Commits sections"
```

---

### Task 3: README

**Files:**
- Modify: `README.md` (Sidebar bullet)

- [ ] **Step 1: Update the Sidebar bullet**

Replace:

```markdown
- **Sidebar**: one occupant at a time, as in VSCode — the nvim-tree file
  explorer or the Source Control panel (`lua/core/gitpanel.lua`,
  `:GitPanel toggle`) listing staged and unstaged changes; selecting a file
  diffs it against the index or `HEAD` with gitsigns. The bufferline shows a
  centered title over the sidebar.
```

with:

```markdown
- **Sidebar**: one occupant at a time, as in VSCode — the nvim-tree file
  explorer or the Source Control panel (`lua/core/gitpanel.lua`,
  `:GitPanel toggle`) with two foldable, resizable sections: Changes
  (staged/unstaged lists as foldable sub-sections; selecting a file diffs it
  against the index or `HEAD` with gitsigns) and Commits (recent history;
  selecting a commit opens its patch). The bufferline shows a centered title
  over the sidebar.
```

- [ ] **Step 2: Format and commit**

```sh
~/.local/share/nvim/mason/bin/deno fmt README.md
git add README.md
git commit -m "docs: document the gitpanel sections in README"
```

---

### Task 4: End-to-end verification (no commit)

- [ ] **Step 1: Reconciler vs the stack — bottom panel squash**

Run:
```sh
nvim --headless "+lua require('core.activitybar').open() require('core.gitpanel').open() require('core.panel').toggle('terminal') vim.wait(600) local bar local g = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do local ft = vim.bo[vim.api.nvim_win_get_buf(w)].filetype if ft == 'gitpanel' then g[#g + 1] = w elseif ft == 'activitybar' then bar = w end end table.sort(g, function(a, b) return vim.api.nvim_win_get_position(a)[1] < vim.api.nvim_win_get_position(b)[1] end) local stack_h = vim.api.nvim_win_get_height(g[1]) + vim.api.nvim_win_get_height(g[2]) + 1 print('sections=' .. #g .. ' stack_full=' .. tostring(stack_h == vim.api.nvim_win_get_height(bar)) .. ' cols=' .. vim.api.nvim_win_get_position(g[1])[2] .. ',' .. vim.api.nvim_win_get_position(g[2])[2])" +qa! 2>&1
```
Expected: `sections=2 stack_full=true cols=6,6` (stack heights + 1 separator equal the bar's height; both sections beside the bar, panel under the editor).

- [ ] **Step 2: Explorer swap and reopen churn**

Run:
```sh
nvim --headless "+lua require('core.activitybar').open() local gp = require('core.gitpanel') gp.open() vim.wait(200) require('core.gitpanel').close() require('nvim-tree.api').tree.open() vim.wait(200) require('nvim-tree.api').tree.close() gp.open() vim.wait(300) local n = 0 for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'gitpanel' then n = n + 1 end end print('reopened_sections=' .. n)" +qa! 2>&1
```
Expected: `reopened_sections=2`.

- [ ] **Step 3: Startup smoke**

Run:
```sh
nvim --headless "+lua vim.wait(200) print('startup-ok')" +qa! 2>&1
```
Expected: `startup-ok`, no error lines.

- [ ] **Step 4: Interactive checklist (report to user)**

- Drag the separator between Changes and Commits — sections resize.
- Click each `▾` header — section collapses to its header; click again restores the height.
- Click `▸/▾ Staged` / `Changes` sub-headers — lists fold/unfold.
- Click a commit — its patch opens in the editor area; click a file — diff opens as before.
- Header/hash colors read well on GitHub Dark.
