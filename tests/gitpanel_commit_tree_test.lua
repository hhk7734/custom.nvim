vim.opt.runtimepath:append(vim.fn.getcwd())

local gitpanel = require("core.gitpanel")
local test = assert(gitpanel._test, "gitpanel test helpers are exposed")

gitpanel.setup()

local lines, entries, marks = test.render_commit_file_tree(
  {
    { path = "lua/core/gitpanel.lua", status = "M" },
    { path = "README.md", status = "A" },
  },
  "abc123",
  {
    ["abc123\0lua"] = true,
    ["abc123\0lua/core"] = true,
  }
)

local expected = {
  "    ✗ lua",
  "      ✗ core",
  "         ✗ gitpanel.lua",
  "     ★ README.md",
}

assert(vim.deep_equal(lines, expected), vim.inspect(lines))
assert(entries[1].dir == "lua", vim.inspect(entries[1]))
assert(entries[2].dir == "lua/core", vim.inspect(entries[2]))
assert(entries[3].path == "lua/core/gitpanel.lua", vim.inspect(entries[3]))
assert(entries[4].path == "README.md", vim.inspect(entries[4]))

local function has_hl(marks, line, hl)
  for _, mark in ipairs(marks) do
    if mark.line == line and mark.hl == hl then
      return true
    end
  end
  return false
end

assert(has_hl(marks, 3, "NvimTreeGitDirtyIcon"), vim.inspect(marks))
assert(has_hl(marks, 4, "NvimTreeGitNewIcon"), vim.inspect(marks))

local collapsed_lines, collapsed_entries = test.render_commit_file_tree(
  {
    { path = "lua/core/gitpanel.lua", status = "M" },
    { path = "README.md", status = "A" },
  },
  "abc123",
  {
    ["abc123\0lua"] = false,
  }
)

assert(
  vim.deep_equal(collapsed_lines, {
    "    ✗ lua",
    "     ★ README.md",
  }),
  vim.inspect(collapsed_lines)
)
assert(collapsed_entries[1].dir == "lua", vim.inspect(collapsed_entries[1]))
assert(collapsed_entries[2].path == "README.md", vim.inspect(collapsed_entries[2]))

local change_lines, change_entries, change_marks = test.render_change_file_tree({
  { path = "lua/core/gitpanel.lua", status = "M" },
  { path = "README.md", status = "?", untracked = true },
}, "changes")

assert(
  vim.deep_equal(change_lines, {
    "  ✗ lua",
    "    ✗ core",
    "       ✗ gitpanel.lua",
    "   ★ README.md",
  }),
  vim.inspect(change_lines)
)
assert(change_entries[1].change_dir == "lua", vim.inspect(change_entries[1]))
assert(change_entries[2].change_dir == "lua/core", vim.inspect(change_entries[2]))
assert(change_entries[3].repo_path == "lua/core/gitpanel.lua", vim.inspect(change_entries[3]))
assert(change_entries[4].repo_path == "README.md", vim.inspect(change_entries[4]))
assert(has_hl(change_marks, 3, "NvimTreeGitDirtyIcon"), vim.inspect(change_marks))
assert(has_hl(change_marks, 4, "NvimTreeGitNewIcon"), vim.inspect(change_marks))
