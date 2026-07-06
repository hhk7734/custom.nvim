vim.opt.runtimepath:append(vim.fn.getcwd())

local gitpanel = require("core.gitpanel")
local test = assert(gitpanel._test, "gitpanel test helpers are exposed")

local function expect(actual, expected)
  assert(vim.deep_equal(actual, expected), vim.inspect(actual))
end

expect(test.diffview_args_for_change({ repo_path = "lua/core/gitpanel.lua", section = "changes" }, "/repo"), {
  "-C/repo",
  "--selected-file=lua/core/gitpanel.lua",
  "--",
  "lua/core/gitpanel.lua",
})

expect(test.diffview_args_for_change({ repo_path = "lua/core/gitpanel.lua", section = "staged" }, "/repo"), {
  "-C/repo",
  "--staged",
  "--selected-file=lua/core/gitpanel.lua",
  "--",
  "lua/core/gitpanel.lua",
})

expect(test.diffview_args_for_commit({ hash = "abc123", path = "lua/core/gitpanel.lua" }, "/repo"), {
  "-C/repo",
  "abc123^!",
  "--selected-file=lua/core/gitpanel.lua",
  "--",
  "lua/core/gitpanel.lua",
})
