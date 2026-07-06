vim.opt.runtimepath:append(vim.fn.getcwd())

local gitpanel = require("core.gitpanel")
local test = assert(gitpanel._test, "gitpanel test helpers are exposed")

local lines, entries = test.render_commit_file_tree(
  {
    "lua/core/gitpanel.lua",
    "README.md",
  },
  "abc123",
  {
    ["abc123\0lua"] = true,
    ["abc123\0lua/core"] = true,
  }
)

local expected = {
  "  ▾ lua",
  "    ▾ core",
  "      gitpanel.lua",
  "  README.md",
}

assert(vim.deep_equal(lines, expected), vim.inspect(lines))
assert(entries[1].dir == "lua", vim.inspect(entries[1]))
assert(entries[2].dir == "lua/core", vim.inspect(entries[2]))
assert(entries[3].path == "lua/core/gitpanel.lua", vim.inspect(entries[3]))
assert(entries[4].path == "README.md", vim.inspect(entries[4]))

local collapsed_lines, collapsed_entries = test.render_commit_file_tree(
  {
    "lua/core/gitpanel.lua",
    "README.md",
  },
  "abc123",
  {
    ["abc123\0lua"] = false,
  }
)

assert(
  vim.deep_equal(collapsed_lines, {
    "  ▸ lua",
    "  README.md",
  }),
  vim.inspect(collapsed_lines)
)
assert(collapsed_entries[1].dir == "lua", vim.inspect(collapsed_entries[1]))
assert(collapsed_entries[2].path == "README.md", vim.inspect(collapsed_entries[2]))
