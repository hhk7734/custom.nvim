vim.opt.runtimepath:append(vim.fn.getcwd())

local gitpanel = require("core.gitpanel")
local test = assert(gitpanel._test, "gitpanel test helpers are exposed")

local function run(cmd, cwd)
  local res = vim.system(cmd, { cwd = cwd }):wait()
  assert(res.code == 0, table.concat(cmd, " ") .. "\n" .. (res.stderr or "") .. (res.stdout or ""))
  return res
end

local function diff_windows()
  local wins = vim.tbl_filter(function(win)
    return vim.wo[win].diff
  end, vim.api.nvim_tabpage_list_wins(0))
  table.sort(wins, function(a, b)
    return vim.api.nvim_win_get_position(a)[2] < vim.api.nvim_win_get_position(b)[2]
  end)
  return wins
end

local function editor_windows()
  local exclude = { gitpanel = true, activitybar = true, NvimTree = true, panelterminal = true, panelproblems = true }
  local wins = vim.tbl_filter(function(win)
    return not exclude[vim.bo[vim.api.nvim_win_get_buf(win)].filetype]
  end, vim.api.nvim_tabpage_list_wins(0))
  table.sort(wins, function(a, b)
    return vim.api.nvim_win_get_position(a)[2] < vim.api.nvim_win_get_position(b)[2]
  end)
  return wins
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
run({ "git", "init" }, root)
run({ "git", "config", "user.email", "test@example.com" }, root)
run({ "git", "config", "user.name", "Test User" }, root)

vim.fn.writefile({ "old" }, root .. "/changed.txt")
vim.fn.writefile({ "old-second" }, root .. "/second.txt")
run({ "git", "add", "changed.txt", "second.txt" }, root)
run({ "git", "commit", "-m", "initial" }, root)

vim.fn.writefile({ "new" }, root .. "/changed.txt")
vim.fn.writefile({ "new-second" }, root .. "/second.txt")
vim.fn.writefile({ "added" }, root .. "/added.txt")
run({ "git", "add", "changed.txt", "second.txt", "added.txt" }, root)
run({ "git", "commit", "-m", "update files" }, root)
local hash = vim.trim(run({ "git", "rev-parse", "--short", "HEAD" }, root).stdout)

vim.cmd("enew")
vim.fn.chdir(root)

test.open_commit_entry(root, { hash = hash, path = "changed.txt", status = "M" })

local wins = diff_windows()
assert(#wins == 2, "expected two diff windows, got " .. #wins)
local left_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(wins[1]), 0, -1, false)
local right_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(wins[2]), 0, -1, false)
assert(vim.deep_equal(left_lines, { "old" }), vim.inspect(left_lines))
assert(vim.deep_equal(right_lines, { "new" }), vim.inspect(right_lines))

vim.cmd("diffoff!")
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if #vim.api.nvim_tabpage_list_wins(0) > 1 then
    pcall(vim.api.nvim_win_close, win, true)
  end
end
vim.cmd("enew")

test.open_commit_entry(root, { hash = hash, path = "added.txt", status = "A" })

assert(vim.api.nvim_buf_get_name(0):find("gitpanel://commit/" .. hash .. "/added.txt", 1, true))
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "added" }))
assert(not vim.wo.diff, "added commit file should open directly, not as a diff")

vim.cmd("enew")
vim.fn.chdir(root)
gitpanel.setup()
gitpanel.open()

local commits_win
for _, win in ipairs(vim.api.nvim_list_wins()) do
  local winbar = vim.wo[win].winbar
  if winbar and winbar:find("Commits", 1, true) then
    commits_win = win
    break
  end
end
assert(commits_win, "commits window exists")
local sidebar_width = vim.api.nvim_win_get_width(commits_win)

vim.api.nvim_set_current_win(commits_win)
vim.api.nvim_win_set_cursor(commits_win, { 1, 0 })
vim.api.nvim_feedkeys(vim.keycode("<CR>"), "xt", false)
local expanded = vim.wait(1000, function()
  local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(commits_win), 0, -1, false)
  for _, line in ipairs(lines) do
    if line:find("changed.txt", 1, true) then
      return true
    end
  end
  return false
end, 20)
assert(expanded, "commit file tree did not expand")

local commits_buf = vim.api.nvim_win_get_buf(commits_win)
local changed_line
local second_line
for i, line in ipairs(vim.api.nvim_buf_get_lines(commits_buf, 0, -1, false)) do
  if line:find("changed.txt", 1, true) then
    changed_line = i
  elseif line:find("second.txt", 1, true) then
    second_line = i
  end
end
assert(changed_line, vim.inspect(vim.api.nvim_buf_get_lines(commits_buf, 0, -1, false)))
assert(second_line, vim.inspect(vim.api.nvim_buf_get_lines(commits_buf, 0, -1, false)))

gitpanel.click({ winid = commits_win, winrow = changed_line + 1, line = changed_line })
local clicked_diff = vim.wait(1000, function()
  return #diff_windows() == 2
end, 20)
assert(clicked_diff, "clicking a changed commit file should open a side-by-side diff")
assert(
  vim.api.nvim_win_get_width(commits_win) == sidebar_width,
  "sidebar width changed after first commit diff selection"
)

gitpanel.click({ winid = commits_win, winrow = second_line + 1, line = second_line })
local replaced_diff = vim.wait(1000, function()
  local editor_wins = editor_windows()
  if #editor_wins ~= 2 then
    return false
  end
  local left = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(editor_wins[1]), 0, -1, false)
  local right = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(editor_wins[2]), 0, -1, false)
  return vim.deep_equal(left, { "old-second" }) and vim.deep_equal(right, { "new-second" })
end, 20)
assert(replaced_diff, "selecting another commit file should replace the existing two-pane diff")
assert(
  vim.api.nvim_win_get_width(commits_win) == sidebar_width,
  "sidebar width changed after replacing commit diff selection"
)
