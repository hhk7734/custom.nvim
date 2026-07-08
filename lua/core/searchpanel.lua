-- VSCode-style "Search" sidebar: two single-line input sections (search query
-- with case-sensitivity and regex toggles, replacement text with a
-- replace-all button) above a results section listing matched files as a tree with one
-- sub-line per match — the found line, or its replace preview once a
-- replacement is typed. Selecting a result opens the file, or a side-by-side
-- replace preview when a replacement is set. Not a plugin; mirrors
-- gitpanel.lua's structure (state table, local helpers, M.open/close/toggle/
-- setup). See docs/layout/sidebar/search-panel.md.
local M = {}

local tree_renderer = require("core.sidebar.tree_renderer")
local resize_handle = require("core.sidebar.resize_handle")
local preview = require("core.sidebar.preview")

local WIDTH = 30
local DEBOUNCE_MS = 250
-- Parsed match cap; the tree shows a truncation note when exceeded.
local MAX_MATCHES = 500
local ns = vim.api.nvim_create_namespace("searchpanel")

-- The input sections in top-to-bottom order. Each is its own window so the
-- boundary row below it is a real, draggable resize handle, like the
-- boundary between gitpanel's sections.
local INPUTS = {
  { key = "query", placeholder = "Search" },
  { key = "replace", placeholder = "Replace" },
}

local state = {
  inputs = { query = {}, replace = {} }, -- key -> { win, buf }
  results = {}, -- { win, buf, lines = lnum -> entry }
  query = "",
  replace = "",
  case_sensitive = false,
  regex = false,
  -- Search root resolved when the panel opens (autochdir moves cwd around).
  root = nil,
  -- Ordered files: { path (root-relative), matches = { { lnum, col, text } } }.
  files = {},
  -- "path:lnum" -> the line with every match replaced (rg --replace output,
  -- so replacement semantics — including ${n} captures — match the search).
  replaced = {},
  truncated = false,
  dir_expanded = {},
  file_expanded = {},
  -- Increments per refresh; async results from stale runs are dropped.
  seq = 0,
  timer = nil,
  quitting = false,
}

local function section_valid(s)
  return s.win and vim.api.nvim_win_is_valid(s.win)
end

local function find_win(ft)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == ft then
      return win
    end
  end
  return nil
end

local function search_root()
  local out = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error == 0 and #out > 0 then
    return out[1]
  end
  return vim.fn.getcwd()
end

-- rg invocation shared by the match pass (--vimgrep, one row per match) and
-- the replace pass (--replace, one row per line with all matches replaced).
local function rg_args(with_replace)
  local args = { "rg", "--no-heading", "--color=never", "--no-messages" }
  args[#args + 1] = state.case_sensitive and "--case-sensitive" or "--ignore-case"
  if not state.regex then
    args[#args + 1] = "--fixed-strings"
  end
  if with_replace then
    args[#args + 1] = "--line-number"
    args[#args + 1] = "--replace"
    args[#args + 1] = state.replace
  else
    args[#args + 1] = "--vimgrep"
  end
  args[#args + 1] = "--"
  args[#args + 1] = state.query
  return args
end

local function parse_matches(stdout)
  local files, by_path = {}, {}
  local truncated = false
  local count = 0
  for _, line in ipairs(vim.split(stdout or "", "\n", { trimempty = true })) do
    local path, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")
    if path then
      if count >= MAX_MATCHES then
        truncated = true
        break
      end
      count = count + 1
      local file = by_path[path]
      if not file then
        file = { path = path, matches = {} }
        by_path[path] = file
        files[#files + 1] = file
      end
      file.matches[#file.matches + 1] = { lnum = tonumber(lnum), col = tonumber(col), text = text }
    end
  end
  return files, truncated
end

local function parse_replaced(stdout)
  local replaced = {}
  for _, line in ipairs(vim.split(stdout or "", "\n", { trimempty = true })) do
    local path, lnum, text = line:match("^(.-):(%d+):(.*)$")
    if path then
      replaced[path .. ":" .. lnum] = text
    end
  end
  return replaced
end

local function write_section(s, lines, marks)
  if not (s.buf and vim.api.nvim_buf_is_valid(s.buf)) then
    return
  end
  vim.bo[s.buf].modifiable = true
  vim.api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
  vim.bo[s.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(s.buf, ns, m.line - 1, m.col, { end_col = m.end_col, hl_group = m.hl })
  end
end

local function match_key(path, lnum)
  return path .. ":" .. lnum
end

local function child_display(match, file)
  local text = match.text
  if state.replace ~= "" then
    text = state.replaced[match_key(file.path, match.lnum)] or text
  end
  return vim.trim(text)
end

local function render_results()
  local s = state.results
  if not (s.buf and vim.api.nvim_buf_is_valid(s.buf)) then
    return
  end

  local lines, entries, marks
  if state.query == "" then
    lines, entries, marks = {}, {}, {}
  elseif #state.files == 0 then
    lines, entries, marks = { "No results" }, {}, {}
  else
    lines, entries, marks = tree_renderer.render_file_tree(state.files, {
      dir_expanded = function(dir)
        return state.dir_expanded[dir.path] ~= false
      end,
      file_expanded = function(file)
        return state.file_expanded[file.path] ~= false
      end,
      file_children = function(file)
        return (file.source or file).matches
      end,
      child_name = function(match, file)
        return { str = child_display(match, file.source or file), hl = { "SearchPanelMatch" } }
      end,
      child_entry = function(match, file)
        return { path = (file.source or file).path, lnum = match.lnum, col = match.col, match = true }
      end,
      dir_entry = function(dir)
        return { dir = dir.path }
      end,
      file_entry = function(file)
        return { path = file.path, file = true }
      end,
    })
    if state.truncated then
      lines[#lines + 1] = "… results truncated"
      marks[#marks + 1] = { line = #lines, col = 0, end_col = #lines[#lines], hl = "Comment" }
    end
  end

  s.lines = entries
  write_section(s, lines, marks)
end

local TOGGLES = {
  { label = "[Aa]", flag = "case_sensitive" },
  { label = "[.*]", flag = "regex" },
}

local function render_input()
  for _, spec in ipairs(INPUTS) do
    local s = state.inputs[spec.key]
    if s.buf and vim.api.nvim_buf_is_valid(s.buf) then
      vim.api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
      if (vim.api.nvim_buf_get_lines(s.buf, 0, 1, false)[1] or "") == "" then
        vim.api.nvim_buf_set_extmark(s.buf, ns, 0, 0, {
          virt_text = { { spec.placeholder, "Comment" } },
          virt_text_pos = "overlay",
        })
      end
    end
  end

  local query = state.inputs.query
  if query.buf and vim.api.nvim_buf_is_valid(query.buf) then
    local toggle_text = {}
    for _, toggle in ipairs(TOGGLES) do
      toggle_text[#toggle_text + 1] =
        { toggle.label, state[toggle.flag] and "SearchPanelToggleOn" or "SearchPanelToggleOff" }
    end
    vim.api.nvim_buf_set_extmark(query.buf, ns, 0, 0, {
      virt_text = toggle_text,
      virt_text_pos = "right_align",
    })
  end

  local replace = state.inputs.replace
  if replace.buf and vim.api.nvim_buf_is_valid(replace.buf) then
    vim.api.nvim_buf_set_extmark(replace.buf, ns, 0, 0, {
      virt_text = { { "[󰛔]", "SearchPanelButton" } },
      virt_text_pos = "right_align",
    })
  end
end

-- Each input buffer is exactly one line; pasted or <CR>-split extras fold
-- back into it.
local function input_line(s)
  local lines = vim.api.nvim_buf_get_lines(s.buf, 0, -1, false)
  if #lines > 1 then
    lines = { table.concat(lines, "") }
    vim.api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
  end
  return lines[1] or ""
end

local function run_search()
  state.seq = state.seq + 1
  local seq = state.seq

  if state.query == "" then
    state.files, state.replaced, state.truncated = {}, {}, false
    render_results()
    return
  end

  local pending = state.replace ~= "" and 2 or 1
  local files, truncated, replaced = nil, false, {}
  local function finish()
    pending = pending - 1
    if pending > 0 or seq ~= state.seq then
      return
    end
    state.files = files or {}
    state.truncated = truncated
    state.replaced = replaced
    render_results()
  end

  vim.system(rg_args(false), { cwd = state.root, text = true }, function(res)
    vim.schedule(function()
      if seq == state.seq then
        files, truncated = parse_matches(res.stdout)
      end
      finish()
    end)
  end)
  if state.replace ~= "" then
    vim.system(rg_args(true), { cwd = state.root, text = true }, function(res)
      vim.schedule(function()
        if seq == state.seq then
          replaced = parse_replaced(res.stdout)
        end
        finish()
      end)
    end)
  end
end

-- Re-reads the inputs and re-runs the search; the public entry point for
-- anything that changes query, replacement, or toggles.
function M.refresh()
  local query, replace = state.inputs.query, state.inputs.replace
  for _, s in pairs({ query, replace }) do
    if not (s.buf and vim.api.nvim_buf_is_valid(s.buf)) then
      return
    end
  end
  state.query = input_line(query)
  state.replace = input_line(replace)
  render_input()
  run_search()
end

local function debounced_refresh()
  if state.timer then
    state.timer:stop()
  end
  state.timer = vim.defer_fn(M.refresh, DEBOUNCE_MS)
end

local function toggle_flag(flag)
  state[flag] = not state[flag]
  M.refresh()
end

local function abs_path(rel)
  return (state.root or vim.fn.getcwd()) .. "/" .. rel
end

local function first_match(path)
  for _, file in ipairs(state.files) do
    if file.path == path then
      return file.matches[1]
    end
  end
  return nil
end

local function open_searched_file(path, lnum, col)
  local win = preview.close_diffs(true) or preview.main_win()
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("botright vsplit")
  end
  vim.cmd.edit(vim.fn.fnameescape(abs_path(path)))
  if lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, math.max((col or 1) - 1, 0) })
  end
end

local function read_file_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or {}
end

-- Replaced-file preview: the searched file on the left, the file with every
-- matched line swapped for its rg --replace output on the right.
local function open_replace_preview(path, lnum)
  local original = read_file_lines(abs_path(path))
  local replaced_lines = vim.deepcopy(original)
  for key, text in pairs(state.replaced) do
    local key_path, key_lnum = key:match("^(.*):(%d+)$")
    if key_path == path then
      replaced_lines[tonumber(key_lnum)] = text
    end
  end

  local name = vim.fn.fnamemodify(path, ":t")
  preview.show_side_by_side(
    "searchpanel://searched/" .. path,
    original,
    "searchpanel://replaced/" .. path,
    replaced_lines,
    path,
    {
      previous_label = name .. " (searched)",
      updated_label = name .. " (replace preview)",
      tab_label = name .. " -> " .. name .. " (Replace Preview)",
    }
  )
  if lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
  end
end

local function activate(entry)
  if not entry then
    return
  end
  if entry.dir then
    state.dir_expanded[entry.dir] = state.dir_expanded[entry.dir] == false
    render_results()
  elseif entry.file and state.replace == "" then
    local match = first_match(entry.path)
    open_searched_file(entry.path, match and match.lnum, match and match.col)
  elseif entry.file then
    open_replace_preview(entry.path)
  elseif entry.match and state.replace == "" then
    open_searched_file(entry.path, entry.lnum, entry.col)
  elseif entry.match then
    open_replace_preview(entry.path, entry.lnum)
  end
end

local function toggle_file_fold(path)
  state.file_expanded[path] = state.file_expanded[path] == false
  render_results()
end

local function select_current()
  local s = state.results
  if not section_valid(s) then
    return
  end
  activate(s.lines[vim.api.nvim_win_get_cursor(s.win)[1]])
end

-- Applies the replacement to every matched file on disk (through the buffer
-- when one is loaded), then re-searches. Files open in modified buffers are
-- skipped rather than silently clobbering unsaved edits.
function M.replace_all(opts)
  opts = opts or {}
  if state.query == "" or state.replace == "" or #state.files == 0 then
    return
  end

  local total = 0
  for _, file in ipairs(state.files) do
    total = total + #file.matches
  end
  if opts.confirm ~= false then
    local msg = string.format("Replace %d match(es) in %d file(s)?", total, #state.files)
    if vim.fn.confirm(msg, "&Yes\n&No", 2) ~= 1 then
      return
    end
  end

  -- Fresh, uncapped replace pass so the write never works from a truncated
  -- or stale preview map.
  local res = vim.system(rg_args(true), { cwd = state.root, text = true }):wait()
  local replaced_by_file = {}
  for key, text in pairs(parse_replaced(res.stdout)) do
    local path, lnum = key:match("^(.*):(%d+)$")
    replaced_by_file[path] = replaced_by_file[path] or {}
    replaced_by_file[path][tonumber(lnum)] = text
  end

  local skipped = {}
  for path, line_map in pairs(replaced_by_file) do
    local abs = abs_path(path)
    local buf = vim.fn.bufnr(abs)
    if buf > 0 and vim.api.nvim_buf_is_loaded(buf) then
      if vim.bo[buf].modified then
        skipped[#skipped + 1] = path
      else
        for lnum, text in pairs(line_map) do
          vim.api.nvim_buf_set_lines(buf, lnum - 1, lnum, false, { text })
        end
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("silent write")
        end)
      end
    else
      local lines = read_file_lines(abs)
      for lnum, text in pairs(line_map) do
        lines[lnum] = text
      end
      vim.fn.writefile(lines, abs)
    end
  end

  if #skipped > 0 then
    vim.notify("search panel: skipped files with unsaved changes: " .. table.concat(skipped, ", "), vim.log.levels.WARN)
  end
  vim.cmd("checktime")
  M.refresh()
end

-- Routed here by activitybar's global <LeftMouse> dispatcher (same reasoning
-- as gitpanel.click). The buttons are right-aligned virtual text, so clicks
-- there are mapped by screen coordinates (winrow/wincol): virtual-text
-- clicks report a clamped buffer line/column.
function M.click(pos)
  local query, replace, results = state.inputs.query, state.inputs.replace, state.results

  if section_valid(query) and pos.winid == query.win then
    local width = vim.api.nvim_win_get_width(query.win)
    -- Row 1 is the winbar; the input line is row 2.
    if pos.winrow == 2 and pos.wincol > width - 8 then
      vim.schedule(function()
        toggle_flag(pos.wincol <= width - 4 and "case_sensitive" or "regex")
      end)
      return true
    end
    -- Let the click place the cursor for editing.
    return false
  end

  if section_valid(replace) and pos.winid == replace.win then
    local width = vim.api.nvim_win_get_width(replace.win)
    if pos.winrow == 1 and pos.wincol > width - 3 then
      vim.schedule(function()
        M.replace_all()
      end)
      return true
    end
    return false
  end

  if section_valid(results) and pos.winid == results.win then
    vim.schedule(function()
      if not section_valid(results) or pos.line == 0 then
        return
      end
      pcall(vim.api.nvim_win_set_cursor, results.win, { pos.line, 0 })
      local entry = results.lines[pos.line]
      if entry and entry.file then
        -- Nvim-tree style: the fold arrow region toggles, the name opens.
        local depth = #vim.split(entry.path, "/", { plain = true }) - 1
        if pos.column <= depth * 2 + 4 then
          toggle_file_fold(entry.path)
        else
          activate(entry)
        end
      elseif entry and entry.path then
        activate(entry)
      else
        vim.api.nvim_set_current_win(results.win)
      end
    end)
    return true
  end

  return false
end

local function setup_input_buffer(key)
  local buf = vim.api.nvim_create_buf(false, true)
  -- Distinct filetype so lualine skips just these fixed-height sections;
  -- their boundary rows render as bare, draggable resize handles.
  vim.bo[buf].filetype = "searchpanelinput"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "hide"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { state[key] })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = debounced_refresh,
  })

  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set({ "n", "i" }, "<M-c>", function()
    toggle_flag("case_sensitive")
  end, vim.tbl_extend("force", opts, { desc = "search panel: toggle case sensitivity" }))
  vim.keymap.set({ "n", "i" }, "<M-r>", function()
    toggle_flag("regex")
  end, vim.tbl_extend("force", opts, { desc = "search panel: toggle regex" }))
  vim.keymap.set({ "n", "i" }, "<M-a>", function()
    M.replace_all()
  end, vim.tbl_extend("force", opts, { desc = "search panel: replace all" }))
  -- Search is live; <CR> moves to the results instead of inserting a line.
  vim.keymap.set("i", "<CR>", "<Esc>", vim.tbl_extend("force", opts, { desc = "search panel: leave insert" }))
  vim.keymap.set("n", "<CR>", function()
    if section_valid(state.results) then
      vim.api.nvim_set_current_win(state.results.win)
    end
  end, vim.tbl_extend("force", opts, { desc = "search panel: focus results" }))
  vim.keymap.set({ "n", "i" }, "<Tab>", function()
    local other = state.inputs[key == "query" and "replace" or "query"]
    if section_valid(other) then
      vim.api.nvim_set_current_win(other.win)
    end
  end, vim.tbl_extend("force", opts, { desc = "search panel: switch input" }))
  vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", opts, { desc = "search panel: close" }))
  return buf
end

local function setup_results_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "searchpanel"
  vim.bo[buf].modifiable = false
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "hide"

  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "<CR>", select_current, vim.tbl_extend("force", opts, { desc = "search panel: select" }))
  vim.keymap.set("n", "<2-LeftMouse>", select_current, vim.tbl_extend("force", opts, { desc = "search panel: select" }))
  vim.keymap.set("n", "za", function()
    local s = state.results
    if not section_valid(s) then
      return
    end
    local entry = s.lines[vim.api.nvim_win_get_cursor(s.win)[1]]
    if entry and entry.file then
      toggle_file_fold(entry.path)
    elseif entry and entry.dir then
      activate(entry)
    end
  end, vim.tbl_extend("force", opts, { desc = "search panel: toggle fold" }))
  vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", opts, { desc = "search panel: close" }))
  vim.keymap.set("n", "R", M.refresh, vim.tbl_extend("force", opts, { desc = "search panel: refresh" }))
  return buf
end

local function style_window(win, kind)
  local wo = vim.wo[win]
  wo.winfixwidth = true
  wo.winfixbuf = true
  wo.number = false
  wo.relativenumber = false
  wo.cursorline = kind == "results"
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.statuscolumn = ""
  wo.wrap = false
  wo.fillchars = "eob: "
  if kind ~= "results" then
    wo.winfixheight = true
  end
  if kind == "query" then
    wo.winbar = "%#SearchPanelHeader# Search %*"
  end
  resize_handle.style_section_window(win)
end

local function panel_sections()
  return { state.inputs.query, state.inputs.replace, state.results }
end

local function panel_open()
  for _, s in pairs(panel_sections()) do
    if section_valid(s) then
      return true
    end
  end
  return false
end

function M.open()
  local query, replace = state.inputs.query, state.inputs.replace
  if section_valid(query) then
    vim.api.nvim_set_current_win(query.win)
    return
  end

  -- One sidebar occupant at a time, as in VSCode.
  pcall(function()
    require("nvim-tree.api").tree.close()
  end)
  pcall(function()
    require("core.gitpanel").close()
  end)

  state.root = search_root()

  for _, spec in ipairs(INPUTS) do
    local s = state.inputs[spec.key]
    if not (s.buf and vim.api.nvim_buf_is_valid(s.buf)) then
      s.buf = setup_input_buffer(spec.key)
    end
  end
  if not (state.results.buf and vim.api.nvim_buf_is_valid(state.results.buf)) then
    state.results.buf = setup_results_buffer()
  end

  local bar_win = find_win("activitybar")
  if bar_win then
    query.win = vim.api.nvim_open_win(query.buf, true, {
      win = bar_win,
      split = "right",
      width = WIDTH,
    })
  else
    vim.cmd("topleft " .. WIDTH .. "vsplit")
    query.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(query.win, query.buf)
  end

  replace.win = vim.api.nvim_open_win(replace.buf, false, {
    win = query.win,
    split = "below",
  })
  state.results.win = vim.api.nvim_open_win(state.results.buf, false, {
    win = replace.win,
    split = "below",
  })

  style_window(query.win, "query")
  style_window(replace.win, "replace")
  style_window(state.results.win, "results")
  -- Winbar plus the query line; the replace section is its single line; the
  -- results section absorbs the rest.
  vim.api.nvim_win_set_height(query.win, 2)
  vim.api.nvim_win_set_height(replace.win, 1)

  render_input()
  render_results()
  vim.api.nvim_win_set_cursor(query.win, { 1, 0 })
end

function M.close()
  for _, s in pairs(panel_sections()) do
    if section_valid(s) then
      -- Closing the last window of a tabpage is an error (E444).
      local tab = vim.api.nvim_win_get_tabpage(s.win)
      if #vim.api.nvim_tabpage_list_wins(tab) > 1 then
        vim.api.nvim_win_close(s.win, true)
      end
    end
    s.win = nil
  end
end

function M.toggle()
  if panel_open() then
    M.close()
  else
    M.open()
  end
end

local function apply_highlights()
  vim.api.nvim_set_hl(0, "SearchPanelHeader", { link = "Title" })
  vim.api.nvim_set_hl(0, "SearchPanelToggleOn", { link = "Search" })
  vim.api.nvim_set_hl(0, "SearchPanelToggleOff", { link = "Comment" })
  vim.api.nvim_set_hl(0, "SearchPanelButton", { link = "Special" })
  vim.api.nvim_set_hl(0, "SearchPanelMatch", { link = "Comment" })
end

function M.setup()
  apply_highlights()
  preview.register("searchpanel", WIDTH)

  local group = vim.api.nvim_create_augroup("searchpanel", {})
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = apply_highlights,
  })

  -- :q behaves like the file explorer: when the panel is open and the quit
  -- would leave at most the panel plus one editor window, :q anywhere —
  -- including inside a panel section — escalates to quitting nvim. With more
  -- editor windows, :q in a panel section closes the whole panel and :q in
  -- an editor window keeps its default behavior. Preview scratches are
  -- handled by core.sidebar.preview's own QuitPre handler.
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function()
      if state.quitting or not panel_open() then
        return
      end
      if preview.is_preview(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())) then
        return
      end

      local cur = vim.api.nvim_get_current_win()
      local in_panel = false
      for _, s in pairs(panel_sections()) do
        if cur == s.win then
          in_panel = true
        end
      end
      local cur_is_editor = not preview.is_sidebar_ft(vim.bo[vim.api.nvim_win_get_buf(cur)].filetype)
      if not (in_panel or cur_is_editor) then
        return
      end

      local editors = 0
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if win ~= cur and not preview.is_sidebar_ft(vim.bo[vim.api.nvim_win_get_buf(win)].filetype) then
          editors = editors + 1
        end
      end

      if (cur_is_editor and editors >= 1) or (in_panel and editors >= 2) then
        if in_panel then
          -- Quitting one section takes the whole panel down with it.
          vim.schedule(M.close)
        end
        return
      end

      state.quitting = true
      local command = vim.v.cmdbang == 1 and "qall!" or "qall"
      local ok, err = pcall(vim.cmd, command)
      if not ok then
        state.quitting = false
        error(err)
      end
    end,
  })

  vim.api.nvim_create_user_command("SearchPanel", function(cmd)
    M[cmd.args ~= "" and cmd.args or "toggle"]()
  end, {
    nargs = "?",
    complete = function()
      return { "open", "close", "toggle" }
    end,
  })
end

M._test = {
  state = state,
  activate = activate,
  run_search = run_search,
}

return M
