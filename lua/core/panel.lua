-- VSCode-style bottom panel: one window with Terminal and Problems as tabs
-- in a clickable winbar strip. Tabs swap buffers in place; the terminal
-- buffer (and its shell) survives closing the panel. Mirrors the gitpanel
-- module structure (state table, local helpers, M.open/close/toggle/setup).
local M = {}

local HEIGHT = 12
local ns = vim.api.nvim_create_namespace("panel")

-- Ordered tab list; minwid in the winbar click regions is the index here
-- (3 = the ✕ button).
local VIEWS = {
  { key = "terminal", label = "Terminal", ft = "panelterminal" },
  { key = "problems", label = "Problems", ft = "panelproblems" },
}

local state = {
  win = nil,
  -- key of the visible (or last visible) view; open() reuses it
  view = nil,
  -- view key -> bufnr, created lazily and kept alive across close/switch
  bufs = {},
  -- problems buffer line number -> { bufnr, lnum, col }, rebuilt on render
  lines = {},
}

local SEVERITY = {
  [vim.diagnostic.severity.ERROR] = { "E", "DiagnosticError" },
  [vim.diagnostic.severity.WARN] = { "W", "DiagnosticWarn" },
  [vim.diagnostic.severity.INFO] = { "I", "DiagnosticInfo" },
  [vim.diagnostic.severity.HINT] = { "H", "DiagnosticHint" },
}

local function win_valid()
  return state.win and vim.api.nvim_win_is_valid(state.win)
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

-- Winbar tab strip. Static string, re-rendered on view/diagnostic changes.
-- %<minwid>@<func>@ regions need a v:lua-reachable function name, hence the
-- single dedicated global PanelTabClick (defined below).
local function winbar()
  local count = #vim.diagnostic.get()
  local parts = {}
  for i, v in ipairs(VIEWS) do
    local label = v.label
    if v.key == "problems" and count > 0 then
      label = label .. " (" .. count .. ")"
    end
    local hl = (state.view == v.key) and "PanelTabActive" or "PanelTabInactive"
    parts[#parts + 1] = "%#" .. hl .. "#%" .. i .. "@v:lua.PanelTabClick@ " .. label .. " %X"
  end
  return table.concat(parts) .. "%#PanelTabFill#%=%3@v:lua.PanelTabClick@ ✕ %X"
end

local function refresh_winbar()
  if win_valid() then
    vim.wo[state.win].winbar = winbar()
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
  local win = main_win()
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("aboveleft split")
  end
  vim.api.nvim_set_current_buf(entry.bufnr)
  vim.api.nvim_win_set_cursor(0, { entry.lnum, entry.col })
end

local function render_problems()
  local buf = state.bufs.problems
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end

  -- Group by file: stable order by name, then by line within a file.
  local by_file = {}
  for _, d in ipairs(vim.diagnostic.get()) do
    local name = vim.api.nvim_buf_get_name(d.bufnr)
    by_file[name] = by_file[name] or { bufnr = d.bufnr, items = {} }
    table.insert(by_file[name].items, d)
  end
  local names = vim.tbl_keys(by_file)
  table.sort(names)

  local lines, entries, marks = {}, {}, {}
  for _, name in ipairs(names) do
    local group = by_file[name]
    table.sort(group.items, function(a, b)
      return a.lnum < b.lnum
    end)
    table.insert(lines, string.format("%s %s", file_icon(name), vim.fn.fnamemodify(name, ":~:.")))
    marks[#lines] = { col = 0, end_col = #lines[#lines], hl = "Title" }
    for _, d in ipairs(group.items) do
      local sev = SEVERITY[d.severity] or { "?", "Comment" }
      local msg = (d.message or ""):gsub("%s*\n.*", "")
      table.insert(lines, string.format("  %s %d:%d %s", sev[1], d.lnum + 1, d.col + 1, msg))
      -- The severity letter sits right after the 2-space indent.
      marks[#lines] = { col = 2, end_col = 3, hl = sev[2] }
      entries[#lines] = { bufnr = d.bufnr, lnum = d.lnum + 1, col = d.col }
    end
  end
  if #lines == 0 then
    lines = { "No problems detected" }
  end
  state.lines = entries

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for lnum, m in pairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, m.col, { end_col = m.end_col, hl_group = m.hl })
  end
end

local function ensure_problems_buf()
  local buf = state.bufs.problems
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "panelproblems"
  vim.bo[buf].modifiable = false
  state.bufs.problems = buf
  vim.keymap.set("n", "<CR>", function()
    select_entry(state.lines[vim.api.nvim_win_get_cursor(0)[1]])
  end, { buffer = buf, desc = "panel: jump to problem" })
  vim.keymap.set("n", "q", function()
    M.close()
  end, { buffer = buf, desc = "panel: close" })
  return buf
end

local function ensure_terminal_buf()
  local buf = state.bufs.terminal
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  buf = vim.api.nvim_create_buf(false, true)
  state.bufs.terminal = buf
  return buf
end

-- Start the shell job for a fresh terminal buffer. Must run with the buffer
-- current in the panel window (jobstart {term=true} attaches to it).
local function start_shell(buf)
  vim.api.nvim_win_call(state.win, function()
    vim.fn.jobstart({ vim.o.shell }, { term = true })
  end)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "panelterminal"
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = buf,
    once = true,
    callback = function()
      -- A dead shell must never be re-shown: close the panel if it is
      -- visible there, then wipe the buffer (scheduled — the buffer cannot
      -- be deleted while the autocmd still runs in it).
      vim.schedule(function()
        if win_valid() and vim.api.nvim_win_get_buf(state.win) == buf then
          M.close()
        end
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        if state.bufs.terminal == buf then
          state.bufs.terminal = nil
        end
      end)
    end,
  })
end

function M.show(key)
  if not win_valid() then
    return M.open(key)
  end
  local buf = key == "terminal" and ensure_terminal_buf() or ensure_problems_buf()
  vim.api.nvim_set_current_win(state.win)
  vim.api.nvim_win_set_buf(state.win, buf)
  state.view = key
  if key == "terminal" then
    if vim.bo[buf].buftype ~= "terminal" then
      start_shell(buf)
    end
    vim.cmd.startinsert()
  else
    render_problems()
  end
  refresh_winbar()
end

function M.open(key)
  key = key or state.view or "terminal"
  if win_valid() then
    return M.show(key)
  end
  -- Full-width bottom split; the activity bar's ensure_layout autocmds pull
  -- the bar/sidebar back into full-height columns, leaving the panel under
  -- the editor area only (same dance it did with edgy's "wincmd J").
  vim.cmd("botright " .. HEIGHT .. "split")
  state.win = vim.api.nvim_get_current_win()

  local wo = vim.wo[state.win]
  wo.winfixheight = true
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.statuscolumn = ""
  wo.wrap = false
  wo.fillchars = "eob: "

  M.show(key)
end

function M.close()
  if not win_valid() then
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

function M.toggle(key)
  if win_valid() then
    if state.view == key then
      M.close()
    else
      M.show(key)
    end
  else
    M.open(key)
  end
end

-- Buffer-area clicks arrive via activitybar's global <LeftMouse> dispatcher
-- (a buffer-local mapping would shadow bar clicks). Returns true when the
-- click was handled. Winbar clicks (winrow 1 while a winbar is set) must
-- fall through so the native %@ regions receive them.
function M.click(pos)
  if not win_valid() or pos.winid ~= state.win or state.view ~= "problems" then
    return false
  end
  if pos.winrow == 1 then
    return false
  end
  local entry = state.lines[pos.line]
  if not entry then
    return false
  end
  vim.schedule(function()
    select_entry(entry)
  end)
  return true
end

-- Winbar %@ click handler; must be a v:lua-reachable global.
-- minwid: VIEWS index, or 3 for the ✕ button.
_G.PanelTabClick = function(minwid, _, button)
  if button ~= "l" then
    return
  end
  if minwid == 3 then
    M.close()
    return
  end
  local view = VIEWS[minwid]
  if view and state.view ~= view.key then
    M.show(view.key)
  end
end

function M.setup()
  vim.api.nvim_set_hl(0, "PanelTabActive", { link = "TabLineSel", default = true })
  vim.api.nvim_set_hl(0, "PanelTabInactive", { link = "TabLine", default = true })
  vim.api.nvim_set_hl(0, "PanelTabFill", { link = "TabLineFill", default = true })

  -- Note: some terminal emulators do not transmit Ctrl+` (it needs the
  -- extended-keys protocol). If nothing happens on keypress, replace
  -- "<C-`>" with "<C-\>" here — everything else stays the same.
  vim.keymap.set({ "n", "t" }, "<C-`>", function()
    M.toggle("terminal")
  end, { desc = "toggle terminal tab" })
  vim.keymap.set("n", "<leader>xx", function()
    M.toggle("problems")
  end, { desc = "toggle problems tab" })

  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = vim.api.nvim_create_augroup("panel", {}),
    callback = function()
      if win_valid() then
        refresh_winbar()
        if state.view == "problems" then
          render_problems()
        end
      end
    end,
  })

  vim.api.nvim_create_user_command("Panel", function(cmd)
    local arg = cmd.args ~= "" and cmd.args or "terminal"
    if arg == "close" then
      M.close()
    else
      M.toggle(arg)
    end
  end, {
    nargs = "?",
    complete = function()
      return { "terminal", "problems", "close" }
    end,
  })
end

return M
