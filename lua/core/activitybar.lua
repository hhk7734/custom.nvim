-- VSCode-style activity bar: a fixed icon column at the far left.
-- Not a plugin; loaded from init.lua after lazy.nvim so that entry actions can
-- rely on plugin commands and lazy-loading via require().
local M = {}

-- Button geometry: each entry renders as a BUTTON_ROWS-tall, WIDTH-wide
-- clickable block with its icon on the middle row. Terminal cells cannot
-- scale glyphs (the icon's pixel size comes from the terminal font); a
-- taller and wider hit area is the terminal analogue of VSCode's square
-- activity-bar buttons.
local WIDTH = 5
local BUTTON_ROWS = 3
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
      -- One sidebar occupant at a time, as in VSCode.
      require("core.gitpanel").close()
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
      require("core.gitpanel").toggle()
    end,
    is_active = function()
      return win_with_ft("gitpanel")
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

  -- winfixwidth is not always honored when adjacent windows close; re-assert.
  if vim.api.nvim_win_get_width(state.win) ~= WIDTH then
    vim.api.nvim_win_set_width(state.win, WIDTH)
  end

  local top, bottom = {}, {}
  for _, e in ipairs(entries) do
    table.insert(e.bottom and bottom or top, e)
  end

  local lines = {}
  state.lines = {}
  local icon_row = math.floor((BUTTON_ROWS - 1) / 2) + 1
  local function add_button(e)
    for row = 1, BUTTON_ROWS do
      table.insert(lines, row == icon_row and ("  " .. e.icon) or "")
      state.lines[#lines] = e
    end
  end
  for _, e in ipairs(top) do
    add_button(e)
  end
  -- Pad so that `bottom` entries stick to the bottom of the window.
  local height = vim.api.nvim_win_get_height(state.win)
  while #lines < height - #bottom * BUTTON_ROWS do
    table.insert(lines, "")
  end
  for _, e in ipairs(bottom) do
    add_button(e)
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
-- focus; every other click keeps its default behavior. Clicks on the git
-- panel are routed from here too — a buffer-local mapping in the panel
-- would shadow this one while the panel has focus, swallowing bar clicks.
local function on_click()
  local pos = vim.fn.getmousepos()
  if pos.winid ~= state.win then
    local gitpanel = package.loaded["core.gitpanel"]
    if gitpanel and gitpanel.click(pos) then
      return ""
    end
    local panel = package.loaded["core.panel"]
    if panel and panel.click(pos) then
      return ""
    end
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

-- Sidebar occupants that must stay a full-height column beside the bar; the
-- bottom panel then only spans the editor area, as in VSCode.
local SIDEBAR_FTS = { NvimTree = true, gitpanel = true }

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

-- true if the window is a full-height column: its leaf is a direct child of
-- the top-level row (nothing stacked above or below it). Height comparisons
-- cannot detect the broken state — a full-width bottom window squashes the
-- bar and sidebar equally, so they would still match each other.
local function is_column(win)
  local root = vim.fn.winlayout()
  if root[1] ~= "row" then
    return false
  end
  for _, frame in ipairs(root[2]) do
    if frame[1] == "leaf" and frame[2] == win then
      return true
    end
  end
  return false
end

-- Re-assert the layout: bar leftmost at WIDTH, sidebar a full-height column
-- right of it. Both are forced out of shape by windows that open "topleft"
-- (nvim-tree) or full-width at the bottom (the panel opens "botright").
-- Acts only when the layout is wrong: "wincmd H" fires WinResized, which
-- re-triggers this handler, so the guard is what prevents a feedback loop.
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

-- The bar is not a place for the cursor (winfixbuf makes it a dead end for
-- :edit and friends); when focus lands here, hop to a real window instead.
local function leave_bar()
  if vim.api.nvim_get_current_win() ~= state.win then
    return
  end
  local fallback
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= state.win and vim.api.nvim_win_get_config(win).focusable then
      local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
      if ft ~= "NvimTree" and ft ~= "gitpanel" and ft ~= "panelterminal" and ft ~= "panelproblems" then
        vim.api.nvim_set_current_win(win)
        return
      end
      fallback = fallback or win
    end
  end
  if fallback then
    vim.api.nvim_set_current_win(fallback)
  end
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
      ensure_layout()
    end,
  })

  -- nvim-tree opens "topleft" and the bottom panel opens "botright" full
  -- width; both disturb the managed columns.
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "NvimTree", "panelterminal", "panelproblems" },
    callback = function()
      vim.schedule(ensure_layout)
    end,
  })

  -- Track open views for the active-icon highlight and bottom padding, and
  -- heal the column layout (ensure_layout ends with render()).
  vim.api.nvim_create_autocmd({ "WinEnter", "WinClosed", "WinResized", "TermOpen", "TermClose" }, {
    group = group,
    callback = function()
      vim.schedule(ensure_layout)
    end,
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      vim.schedule(leave_bar)
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
