vim.opt.runtimepath:append(vim.fn.getcwd())

local gitpanel = require("core.gitpanel")
local test = assert(gitpanel._test, "gitpanel test helpers are exposed")

local function run(cmd, cwd)
  local res = vim.system(cmd, { cwd = cwd }):wait()
  assert(res.code == 0, table.concat(cmd, " ") .. "\n" .. (res.stderr or "") .. (res.stdout or ""))
  return res
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

local function listed_no_name_buffers()
  local buffers = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and vim.api.nvim_buf_get_name(buf) == "" then
      buffers[#buffers + 1] = buf
    end
  end
  return buffers
end

local function count_gitpanel_tab_label(label)
  local count = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and vim.b[buf].gitpanel_tab_label == label then
      count = count + 1
    end
  end
  return count
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
run({ "git", "init" }, root)
run({ "git", "config", "user.email", "test@example.com" }, root)
run({ "git", "config", "user.name", "Test User" }, root)

vim.fn.writefile({ "old" }, root .. "/changed.txt")
vim.fn.writefile({ "old-second" }, root .. "/second.txt")
vim.fn.writefile({ "old-staged" }, root .. "/staged.txt")
vim.fn.writefile({ "old" }, root .. "/deleted.txt")
run({ "git", "add", "changed.txt", "second.txt", "staged.txt", "deleted.txt" }, root)
run({ "git", "commit", "-m", "initial" }, root)
vim.fn.writefile({ "new" }, root .. "/changed.txt")
vim.fn.writefile({ "new-second" }, root .. "/second.txt")
vim.fn.writefile({ "new-staged" }, root .. "/staged.txt")
vim.fn.writefile({ "added" }, root .. "/added.txt")
vim.fn.delete(root .. "/deleted.txt")
run({ "git", "add", "staged.txt" }, root)

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

assert(vim.api.nvim_buf_get_name(0):find("gitpanel://added/worktree/added.txt", 1, true), vim.api.nvim_buf_get_name(0))
assert(vim.b[vim.api.nvim_get_current_buf()].gitpanel_tab_label == "added.txt (worktree)")
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
local sidebar_width = vim.api.nvim_win_get_width(changes_win)

local changes_buf = vim.api.nvim_win_get_buf(changes_win)
assert(vim.wo[changes_win].winbar:find(" Changes", 1, true), vim.wo[changes_win].winbar)
local rendered_changes = vim.api.nvim_buf_get_lines(changes_buf, 0, -1, false)
assert(rendered_changes[1] == "  Staged Changes", vim.inspect(rendered_changes))
local saw_changes_group = false
local changed_line
local second_line
for i, line in ipairs(rendered_changes) do
  if line == "  Changes" then
    saw_changes_group = true
  elseif line:find("changed.txt", 1, true) then
    changed_line = i
    assert(line:find(" ✗ changed.txt", 1, true), line)
  elseif line:find("second.txt", 1, true) then
    second_line = i
    assert(line:find(" ✗ second.txt", 1, true), line)
  end
end
assert(saw_changes_group, vim.inspect(rendered_changes))
assert(changed_line, vim.inspect(rendered_changes))
assert(second_line, vim.inspect(rendered_changes))
local initial_no_name_count = #listed_no_name_buffers()
local changed_label = "changed.txt (index) -> changed.txt (worktree)"
local second_label = "second.txt (index) -> second.txt (worktree)"
local has_added = false
local has_deleted = false
for _, line in ipairs(rendered_changes) do
  has_added = has_added or (line:find(" ★ added.txt", 1, true) ~= nil)
  has_deleted = has_deleted or (line:find("  deleted.txt", 1, true) ~= nil)
end
assert(has_added, vim.inspect(rendered_changes))
assert(has_deleted, vim.inspect(rendered_changes))

gitpanel.click({ winid = changes_win, winrow = changed_line + 1, line = changed_line })
local clicked_diff = vim.wait(1000, function()
  local wins = vim.tbl_filter(function(win)
    return vim.wo[win].diff
  end, vim.api.nvim_tabpage_list_wins(0))
  return #wins == 2
end, 20)
assert(clicked_diff, "single-clicking a changed file should open a side-by-side diff")
assert(vim.b[vim.api.nvim_get_current_buf()].gitpanel_tab_label == changed_label)
assert(count_gitpanel_tab_label(changed_label) == 1, "first changed diff tab should be listed once")
assert(vim.api.nvim_win_get_width(changes_win) == sidebar_width, "sidebar width changed after first diff selection")

gitpanel.click({ winid = changes_win, winrow = second_line + 1, line = second_line })
local replaced_diff = vim.wait(1000, function()
  local wins = editor_windows()
  if #wins ~= 2 then
    return false
  end
  local left = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(wins[1]), 0, -1, false)
  local right = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(wins[2]), 0, -1, false)
  return vim.deep_equal(left, { "old-second" }) and vim.deep_equal(right, { "new-second" })
end, 20)
assert(replaced_diff, "selecting another changed file should replace the existing two-pane diff")
assert(vim.b[vim.api.nvim_get_current_buf()].gitpanel_tab_label == second_label)
assert(count_gitpanel_tab_label(changed_label) == 1, "first changed diff tab should remain listed once")
assert(count_gitpanel_tab_label(second_label) == 1, "second changed diff tab should be listed once")
assert(vim.api.nvim_win_get_width(changes_win) == sidebar_width, "sidebar width changed after replacing diff selection")
assert(
  #listed_no_name_buffers() == initial_no_name_count,
  "changed file reselection leaked [No Name] buffers: " .. vim.inspect(listed_no_name_buffers())
)

gitpanel.click({ winid = changes_win, winrow = changed_line + 1, line = changed_line })
local restored_diff = vim.wait(1000, function()
  local wins = editor_windows()
  if #wins ~= 2 then
    return false
  end
  local left = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(wins[1]), 0, -1, false)
  local right = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(wins[2]), 0, -1, false)
  return vim.deep_equal(left, { "old" }) and vim.deep_equal(right, { "new" })
end, 20)
assert(restored_diff, "selecting the first changed file again should replace the existing two-pane diff")
assert(vim.b[vim.api.nvim_get_current_buf()].gitpanel_tab_label == changed_label)
assert(count_gitpanel_tab_label(changed_label) == 1, "reselected first changed diff tab should not duplicate")
assert(count_gitpanel_tab_label(second_label) == 1, "second changed diff tab should remain listed once")
assert(vim.api.nvim_win_get_width(changes_win) == sidebar_width, "sidebar width changed after third diff selection")
assert(
  #listed_no_name_buffers() == initial_no_name_count,
  "repeated changed file selection leaked [No Name] buffers: " .. vim.inspect(listed_no_name_buffers())
)
