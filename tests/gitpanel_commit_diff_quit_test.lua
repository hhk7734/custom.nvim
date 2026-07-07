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

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
run({ "git", "init" }, root)
run({ "git", "config", "user.email", "test@example.com" }, root)
run({ "git", "config", "user.name", "Test User" }, root)

vim.fn.writefile({ "old" }, root .. "/changed.txt")
run({ "git", "add", "changed.txt" }, root)
run({ "git", "commit", "-m", "initial" }, root)

vim.fn.writefile({ "new" }, root .. "/changed.txt")
run({ "git", "add", "changed.txt" }, root)
run({ "git", "commit", "-m", "update file" }, root)
local hash = vim.trim(run({ "git", "rev-parse", "--short", "HEAD" }, root).stdout)

vim.cmd("enew")
vim.fn.chdir(root)
test.open_commit_entry(root, { hash = hash, path = "changed.txt", status = "M" })

local wins = diff_windows()
assert(#wins == 2, "expected two commit diff windows, got " .. #wins)

local side = vim.env.GITPANEL_QUIT_SIDE or "updated"
assert(side == "previous" or side == "updated", "unknown GITPANEL_QUIT_SIDE: " .. side)
vim.api.nvim_set_current_win(side == "previous" and wins[1] or wins[2])
assert(vim.api.nvim_buf_get_name(0):find("gitpanel://commit-" .. side .. "/", 1, true), vim.api.nvim_buf_get_name(0))

vim.cmd("quit")
error(":q in gitpanel commit-" .. side .. " closed only one diff window instead of exiting Neovim")
