-- VSCode-style activity bar: a fixed icon column at the far left.
-- Not a plugin; loaded from init.lua after lazy.nvim so that entry actions can
-- rely on plugin commands and lazy-loading via require().
local M = {}

local WIDTH = 3
local ns = vim.api.nvim_create_namespace("activitybar")

local state = {
  buf = nil,
  win = nil,
  -- buffer line number -> entry, rebuilt on every render
  lines = {},
}

-- true if any window (any tabpage) shows a buffer with this filetype
local function win_with_ft(ft)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == ft then
      return true
    end
  end
  return false
end

-- Entries without is_active (e.g. Search) are transient and never highlighted.
local entries = {
  {
    icon = "󰉋",
    desc = "Explorer",
    action = function()
      require("nvim-tree.api").tree.toggle()
    end,
    is_active = function()
      return win_with_ft("NvimTree")
    end,
  },
  {
    icon = "",
    desc = "Search",
    action = function()
      require("telescope.builtin").live_grep()
    end,
  },
  {
    icon = "",
    desc = "Source Control",
    action = function()
      if win_with_ft("DiffviewFiles") then
        vim.cmd("DiffviewClose")
      else
        vim.cmd("DiffviewOpen")
      end
    end,
    is_active = function()
      return win_with_ft("DiffviewFiles")
    end,
  },
  {
    icon = "",
    desc = "Terminal",
    action = function()
      vim.cmd("ToggleTerm")
    end,
    is_active = function()
      return win_with_ft("toggleterm")
    end,
  },
  {
    icon = "󰀪",
    desc = "Problems",
    action = function()
      vim.cmd("Trouble diagnostics toggle")
    end,
    is_active = function()
      return win_with_ft("trouble")
    end,
  },
  {
    icon = "",
    desc = "Plugins (Lazy)",
    action = function()
      vim.cmd("Lazy")
    end,
    bottom = true,
  },
}

local function render()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
    return
  end

  local top, bottom = {}, {}
  for _, e in ipairs(entries) do
    table.insert(e.bottom and bottom or top, e)
  end

  local lines = {}
  state.lines = {}
  for _, e in ipairs(top) do
    table.insert(lines, " " .. e.icon)
    state.lines[#lines] = e
  end
  -- Pad so that `bottom` entries stick to the bottom of the window.
  local height = vim.api.nvim_win_get_height(state.win)
  while #lines < height - #bottom do
    table.insert(lines, "")
  end
  for _, e in ipairs(bottom) do
    table.insert(lines, " " .. e.icon)
    state.lines[#lines] = e
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for lnum, e in pairs(state.lines) do
    vim.api.nvim_buf_set_extmark(state.buf, ns, lnum - 1, 0, {
      end_col = #lines[lnum],
      hl_group = (e.is_active and e.is_active()) and "ActivityBarActive" or "ActivityBarInactive",
    })
  end
end

-- Global <LeftMouse> expr mapping: handle clicks on the bar without moving
-- focus; every other click keeps its default behavior.
local function on_click()
  local pos = vim.fn.getmousepos()
  if pos.winid ~= state.win then
    return "<LeftMouse>"
  end
  local entry = state.lines[pos.line]
  if entry then
    -- Run outside the expr-mapping context.
    vim.schedule(function()
      entry.action()
      render()
    end)
  end
  return ""
end

-- Re-assert the far-left position after windows that also open "topleft"
-- (e.g. nvim-tree) push the bar inward.
local function ensure_position()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
    return
  end
  vim.api.nvim_win_call(state.win, function()
    vim.cmd("wincmd H")
    vim.cmd("vertical resize " .. WIDTH)
  end)
  render()
end

function M.open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    return
  end

  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].filetype = "activitybar"
    vim.bo[state.buf].modifiable = false
  end

  local prev = vim.api.nvim_get_current_win()
  vim.cmd("topleft " .. WIDTH .. "vsplit")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)

  local wo = vim.wo[state.win]
  wo.winfixwidth = true
  wo.winfixbuf = true
  wo.number = false
  wo.relativenumber = false
  wo.cursorline = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.statuscolumn = ""
  wo.wrap = false
  wo.fillchars = "eob: "

  vim.api.nvim_set_current_win(prev)
  render()
end

function M.close()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
    state.win = nil
    return
  end
  -- Closing the last window of a tabpage is an error (E444); keep the bar.
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
  vim.api.nvim_set_hl(0, "ActivityBarInactive", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "ActivityBarActive", { link = "Function", default = true })

  vim.keymap.set("n", "<LeftMouse>", on_click, { expr = true, desc = "activity bar click" })

  local group = vim.api.nvim_create_augroup("activitybar", {})

  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = function()
      M.open()
      ensure_position()
    end,
  })

  -- nvim-tree also opens "topleft"; keep the bar at the far left.
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "NvimTree",
    callback = function()
      vim.schedule(ensure_position)
    end,
  })

  -- Track open views for the active-icon highlight and bottom padding.
  vim.api.nvim_create_autocmd({ "WinEnter", "WinClosed", "WinResized", "TermOpen", "TermClose" }, {
    group = group,
    callback = function()
      vim.schedule(render)
    end,
  })

  vim.api.nvim_create_user_command("ActivityBar", function(cmd)
    M[cmd.args ~= "" and cmd.args or "toggle"]()
  end, {
    nargs = "?",
    complete = function()
      return { "open", "close", "toggle" }
    end,
  })
end

return M
