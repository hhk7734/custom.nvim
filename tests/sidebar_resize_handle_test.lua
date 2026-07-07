local activitybar = require("core.activitybar")
local gitpanel = require("core.gitpanel")
local resize_handle = require("core.sidebar.resize_handle")

resize_handle.setup()

local function wins_by_ft(ft)
  local wins = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == ft then
      wins[#wins + 1] = win
    end
  end
  return wins
end

local function assert_resize_handle(win, label)
  local winhighlight = vim.wo[win].winhighlight
  assert(
    winhighlight:find("WinSeparator:SidebarResizeHandle", 1, true),
    label .. " missing sidebar resize handle highlight: " .. winhighlight
  )
end

local handle_hl = vim.api.nvim_get_hl(0, { name = "SidebarResizeHandle", link = false })
assert(handle_hl.fg == resize_handle.HIGHLIGHT_FG, string.format("resize handle fg = %s", vim.inspect(handle_hl)))
assert(handle_hl.bold, "resize handle should be bold")

activitybar.open()
vim.cmd("topleft 30vsplit")
local tree_win = vim.api.nvim_get_current_win()
local tree_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(tree_win, tree_buf)
vim.bo[tree_buf].filetype = "NvimTree"
resize_handle.style_window(tree_win)
assert_resize_handle(tree_win, "nvim-tree")
vim.api.nvim_win_close(tree_win, true)

gitpanel.open()
local gitpanel_ready = vim.wait(1000, function()
  return #wins_by_ft("gitpanel") == 2
end, 20)
assert(gitpanel_ready, "gitpanel windows should open")
for _, win in ipairs(wins_by_ft("gitpanel")) do
  assert_resize_handle(win, "gitpanel")
end
