vim.opt.runtimepath:append(vim.fn.getcwd())

local gitpanel = require("core.gitpanel")
gitpanel.setup()
gitpanel.open()

local commit_win
for _, win in ipairs(vim.api.nvim_list_wins()) do
  local winbar = vim.wo[win].winbar
  if winbar and winbar:find("Commits", 1, true) then
    commit_win = win
    break
  end
end
assert(commit_win, "commits window exists")
assert(vim.wo[commit_win].winbar:find(" Commits", 1, true), vim.wo[commit_win].winbar)

local buf = vim.api.nvim_win_get_buf(commit_win)
local before = vim.api.nvim_buf_get_lines(buf, 0, 2, false)
assert(before[1] and before[1]:match("^ %x+ "), vim.inspect(before))

gitpanel.click({ winid = commit_win, winrow = 2, line = 1 })
vim.wait(1000, function()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, 2, false)
  return lines[1] and lines[1]:match("^ %x+ ")
end, 20)
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]:match("^ %x+ "))

vim.api.nvim_set_current_win(commit_win)
vim.api.nvim_win_set_cursor(commit_win, { 1, 0 })

local map = vim.fn.maparg("<2-LeftMouse>", "n", false, true)
assert(type(map.callback) == "function", vim.inspect(map))

map.callback()

local expanded = vim.wait(1000, function()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, 4, false)
  return lines[1] and lines[1]:match("^ %x+ ") and lines[2] and lines[2]:match("^  ")
end, 20)
assert(expanded, vim.inspect(vim.api.nvim_buf_get_lines(buf, 0, 4, false)))
