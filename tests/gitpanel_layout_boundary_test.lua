local gitpanel = require("core.gitpanel")
local activitybar = require("core.activitybar")

local function run(cmd, cwd)
  local res = vim.system(cmd, { cwd = cwd }):wait()
  assert(res.code == 0, table.concat(cmd, " ") .. "\n" .. (res.stderr or "") .. (res.stdout or ""))
  return res
end

local function wins_by_ft(ft)
  local wins = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == ft then
      wins[#wins + 1] = win
    end
  end
  table.sort(wins, function(a, b)
    local ar, ac = unpack(vim.api.nvim_win_get_position(a))
    local br, bc = unpack(vim.api.nvim_win_get_position(b))
    return ac == bc and ar < br or ac < bc
  end)
  return wins
end

local function current_tab_has_ft(ft)
  return #wins_by_ft(ft) > 0
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
vim.fn.chdir(root)

activitybar.open()
gitpanel.open()

local tab = vim.api.nvim_get_current_tabpage()
local activity_wins = wins_by_ft("activitybar")
assert(#activity_wins == 1, "activity bar must be visible")
local activity_win = activity_wins[1]
local activity_width = vim.api.nvim_win_get_width(activity_win)

activitybar.close()
assert(vim.api.nvim_win_is_valid(activity_win), "activitybar.close() must not hide the activity bar")
assert(vim.api.nvim_win_get_width(activity_win) == activity_width, "activity bar width changed")
activitybar.toggle()
assert(vim.api.nvim_win_is_valid(activity_win), "activitybar.toggle() must not hide the activity bar")
assert(vim.api.nvim_win_get_width(activity_win) == activity_width, "activity bar width changed after toggle")

local sidebar_wins = wins_by_ft("gitpanel")
assert(#sidebar_wins == 2, "gitpanel sidebar must remain visible")
for _, win in ipairs(sidebar_wins) do
  local buf = vim.api.nvim_win_get_buf(win)
  assert(not vim.bo[buf].modifiable, "Source Control buffers must stay nomodifiable")
  assert(vim.bo[buf].readonly, "Source Control buffers must stay readonly")
end
local sidebar_width = vim.api.nvim_win_get_width(sidebar_wins[1])

local changes_win = sidebar_wins[1]
local changes_buf = vim.api.nvim_win_get_buf(changes_win)
local changed_line, second_line
for i, line in ipairs(vim.api.nvim_buf_get_lines(changes_buf, 0, -1, false)) do
  if line:find("changed.txt", 1, true) then
    changed_line = i
  elseif line:find("second.txt", 1, true) then
    second_line = i
  end
end
assert(changed_line and second_line, vim.inspect(vim.api.nvim_buf_get_lines(changes_buf, 0, -1, false)))

gitpanel.click({ winid = changes_win, winrow = changed_line + 1, line = changed_line })
assert(vim.api.nvim_get_current_tabpage() == tab, "diff selection must stay in the current tab")
assert(current_tab_has_ft("activitybar"), "diff selection must not hide the activity bar")
assert(current_tab_has_ft("gitpanel"), "diff selection must not hide the sidebar")
assert(not current_tab_has_ft("DiffviewFiles"), "gitpanel must not use diffview.nvim UI")
assert(vim.api.nvim_win_get_width(activity_win) == activity_width, "activity bar width changed after diff selection")
assert(vim.api.nvim_win_get_width(changes_win) == sidebar_width, "sidebar width changed after diff selection")

gitpanel.click({ winid = changes_win, winrow = second_line + 1, line = second_line })
assert(vim.api.nvim_get_current_tabpage() == tab, "reselection must stay in the current tab")
assert(current_tab_has_ft("activitybar"), "reselection must not hide the activity bar")
assert(current_tab_has_ft("gitpanel"), "reselection must not hide the sidebar")
assert(not current_tab_has_ft("DiffviewFiles"), "gitpanel must not use diffview.nvim UI")
assert(vim.api.nvim_win_get_width(activity_win) == activity_width, "activity bar width changed after reselection")
assert(vim.api.nvim_win_get_width(changes_win) == sidebar_width, "sidebar width changed after reselection")
