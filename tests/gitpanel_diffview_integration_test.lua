local gitpanel = require("core.gitpanel")
local test = assert(gitpanel._test, "gitpanel test helpers are exposed")
local diffview = require("diffview")
assert(type(diffview.open) == "function", "diffview.nvim is available")

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

vim.fn.chdir(root)
test.open_change_entry({
  path = root .. "/changed.txt",
  repo_path = "changed.txt",
  section = "changes",
  status = "M",
})

local opened = vim.wait(3000, function()
  local ok, lib = pcall(require, "diffview.lib")
  return ok and #(lib.views or {}) == 1
end, 50)
assert(opened, "gitpanel changed-file selection should open a Diffview")

local has_panel = false
for _, win in ipairs(vim.api.nvim_list_wins()) do
  if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "DiffviewFiles" then
    has_panel = true
    break
  end
end
assert(has_panel, "Diffview file panel should be visible")

run({ "git", "add", "changed.txt" }, root)
run({ "git", "commit", "-m", "update changed" }, root)
local hash = vim.trim(run({ "git", "rev-parse", "--short", "HEAD" }, root).stdout)
vim.fn.chdir(root)
test.open_commit_entry(root, { hash = hash, path = "changed.txt", status = "M" })

local reopened = vim.wait(3000, function()
  local ok, lib = pcall(require, "diffview.lib")
  return ok and #(lib.views or {}) == 1
end, 50)
assert(reopened, "gitpanel commit-file selection should open a Diffview")
