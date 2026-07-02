-- VSCode-style "Source Control" sidebar: lists `git status` changes and
-- shows the selected file's diff in the editor area (index diff for Changes,
-- HEAD diff for Staged; untracked files just open). Not a plugin; mirrors
-- activitybar.lua's structure (state table, local helpers, M.open/close/
-- toggle/setup).
local M = {}

local WIDTH = 30
local ns = vim.api.nvim_create_namespace("gitpanel")

local state = {
  buf = nil,
  win = nil,
  -- repo root resolved on the last render; nil outside a git repo.
  root = nil,
  -- buffer line number -> entry: "header" (section title, not selectable),
  -- a table (selectable file line), or nil (blank/status line). Rebuilt on
  -- every render.
  lines = {},
}

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

local function status_hl(status)
  if status == "A" or status == "?" then
    return "Added"
  elseif status == "D" then
    return "Removed"
  end
  return "Changed" -- M R C T
end

-- File icons come from nvim-web-devicons at runtime; never hardcode
-- nerd-font/PUA glyphs in source (see repo memory: they get corrupted).
local function file_icon(path)
  local ok, icon = pcall(function()
    local devicons = require("nvim-web-devicons")
    return devicons.get_icon(vim.fn.fnamemodify(path, ":t"), vim.fn.fnamemodify(path, ":e"), { default = true })
  end)
  return (ok and icon) or ""
end

-- Builds the panel's lines and the line->entry map (see `state.lines`).
local function build_lines()
  local root = repo_root()
  state.root = root
  if not root then
    return { "Not a git repository" }, {}
  end

  local staged, changes = git_status(root)
  local lines, entries = {}, {}

  if #staged == 0 and #changes == 0 then
    table.insert(lines, "No changes")
    return lines, entries
  end

  local function add_header(text)
    table.insert(lines, text)
    entries[#lines] = "header"
  end

  local function add_file(section, item)
    local icon = file_icon(item.path)
    table.insert(lines, string.format("  %s %s %s", item.status, icon, item.path))
    entries[#lines] = {
      path = root .. "/" .. item.path,
      section = section,
      untracked = item.untracked,
      status = item.status,
    }
  end

  if #staged > 0 then
    add_header("Staged")
    for _, item in ipairs(staged) do
      add_file("staged", item)
    end
  end
  if #changes > 0 then
    add_header("Changes")
    for _, item in ipairs(changes) do
      add_file("changes", item)
    end
  end
  return lines, entries
end

local function render()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
    return
  end

  local lines, entries = build_lines()
  state.lines = entries

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for lnum, entry in pairs(entries) do
    if entry == "header" then
      vim.api.nvim_buf_set_extmark(state.buf, ns, lnum - 1, 0, {
        end_col = #lines[lnum],
        hl_group = "Title",
      })
    else
      -- The status letter sits right after the 2-space indent (see
      -- add_file's "  %s %s %s" format).
      vim.api.nvim_buf_set_extmark(state.buf, ns, lnum - 1, 2, {
        end_col = 3,
        hl_group = status_hl(entry.status),
      })
    end
  end
end

-- Wipes the previous diff before a new selection: `diffoff!` plus closing any
-- window whose buffer is a gitsigns in-memory revision (`gitsigns://...`).
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
  local exclude = { activitybar = true, gitpanel = true, NvimTree = true, toggleterm = true, trouble = true }
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

local function select_current()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local entry = state.lines[lnum]
  if entry ~= "header" then
    select_entry(entry)
  end
end

-- Buffer-local mapping: unlike an unmapped <LeftMouse>, a mapped one does not
-- get Vim's automatic click-to-cursor behavior, so getmousepos() positions
-- the cursor by hand (same trick as activitybar.lua's on_click).
local function on_click()
  local pos = vim.fn.getmousepos()
  if pos.winid ~= state.win or pos.line == 0 then
    return
  end
  vim.api.nvim_win_set_cursor(state.win, { pos.line, 0 })
  select_current()
end

local function setup_buffer()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].filetype = "gitpanel"
  vim.bo[state.buf].modifiable = false
  vim.bo[state.buf].bufhidden = "hide"

  local opts = { buffer = state.buf, silent = true, nowait = true }
  vim.keymap.set("n", "<CR>", select_current, vim.tbl_extend("force", opts, { desc = "git panel: select" }))
  vim.keymap.set("n", "<LeftMouse>", on_click, vim.tbl_extend("force", opts, { desc = "git panel: select" }))
  vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", opts, { desc = "git panel: close" }))
  vim.keymap.set("n", "R", render, vim.tbl_extend("force", opts, { desc = "git panel: refresh" }))
end

function M.open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  -- One sidebar occupant at a time, as in VSCode.
  pcall(function()
    require("nvim-tree.api").tree.close()
  end)

  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    setup_buffer()
  end

  local bar_win = find_win("activitybar")
  if bar_win then
    state.win = vim.api.nvim_open_win(state.buf, true, {
      win = bar_win,
      split = "right",
      width = WIDTH,
    })
  else
    vim.cmd("topleft " .. WIDTH .. "vsplit")
    state.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.win, state.buf)
  end

  local wo = vim.wo[state.win]
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

  render()
end

function M.close()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
    state.win = nil
    return
  end
  -- Closing the last window of a tabpage is an error (E444); keep the panel.
  local tab = vim.api.nvim_win_get_tabpage(state.win)
  if #vim.api.nvim_tabpage_list_wins(tab) == 1 then
    return
  end
  vim.api.nvim_win_close(state.win, true)
  state.win = nil
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.open()
  end
end

function M.setup()
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
