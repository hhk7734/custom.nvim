vim.opt.runtimepath:append(vim.fn.getcwd())

local gitpanel = require("core.gitpanel")
local test = assert(gitpanel._test, "gitpanel test helpers are exposed")

local function run(cmd, cwd)
  local res = vim.system(cmd, { cwd = cwd }):wait()
  assert(res.code == 0, table.concat(cmd, " ") .. "\n" .. (res.stderr or "") .. (res.stdout or ""))
  return res
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
run({ "git", "init" }, root)
run({ "git", "config", "user.email", "test@example.com" }, root)
run({ "git", "config", "user.name", "Test User" }, root)

vim.fn.writefile({ "old" }, root .. "/changed.txt")
run({ "git", "add", "changed.txt" }, root)
run({ "git", "commit", "-m", "initial" }, root)
vim.fn.writefile({ "new" }, root .. "/changed.txt")
vim.fn.writefile({ "added" }, root .. "/added.txt")

vim.cmd("enew")
vim.fn.chdir(root)

test.open_change_entry({
  path = root .. "/changed.txt",
  repo_path = "changed.txt",
  section = "changes",
  status = "M",
})

local diff_wins = vim.tbl_filter(function(win)
  return vim.wo[win].diff
end, vim.api.nvim_tabpage_list_wins(0))
assert(#diff_wins == 2, "expected two diff windows, got " .. #diff_wins)
table.sort(diff_wins, function(a, b)
  return vim.api.nvim_win_get_position(a)[2] < vim.api.nvim_win_get_position(b)[2]
end)

local left_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(diff_wins[1]), 0, -1, false)
local right_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(diff_wins[2]), 0, -1, false)
assert(vim.deep_equal(left_lines, { "old" }), vim.inspect(left_lines))
assert(vim.deep_equal(right_lines, { "new" }), vim.inspect(right_lines))

vim.cmd("diffoff!")
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if #vim.api.nvim_tabpage_list_wins(0) > 1 then
    pcall(vim.api.nvim_win_close, win, true)
  end
end
vim.cmd("enew")

test.open_change_entry({
  path = root .. "/added.txt",
  repo_path = "added.txt",
  section = "changes",
  status = "A",
})

assert(vim.api.nvim_buf_get_name(0) == root .. "/added.txt", vim.api.nvim_buf_get_name(0))
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "added" }))
assert(not vim.wo.diff, "added file should open directly, not as a diff")

vim.cmd("enew")
vim.fn.chdir(root)
gitpanel.setup()
gitpanel.open()

local changes_win
for _, win in ipairs(vim.api.nvim_list_wins()) do
  local winbar = vim.wo[win].winbar
  if winbar and winbar:find("Changes", 1, true) then
    changes_win = win
    break
  end
end
assert(changes_win, "changes window exists")

local changes_buf = vim.api.nvim_win_get_buf(changes_win)
local changed_line
for i, line in ipairs(vim.api.nvim_buf_get_lines(changes_buf, 0, -1, false)) do
  if line:find("changed.txt", 1, true) then
    changed_line = i
    break
  end
end
assert(changed_line, vim.inspect(vim.api.nvim_buf_get_lines(changes_buf, 0, -1, false)))

gitpanel.click({ winid = changes_win, winrow = changed_line + 1, line = changed_line })
local clicked_diff = vim.wait(1000, function()
  local wins = vim.tbl_filter(function(win)
    return vim.wo[win].diff
  end, vim.api.nvim_tabpage_list_wins(0))
  return #wins == 2
end, 20)
assert(clicked_diff, "single-clicking a changed file should open a side-by-side diff")
