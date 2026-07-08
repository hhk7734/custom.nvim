-- Shared editor-area preview machinery for sidebar panels (git panel, search
-- panel): named scratch buffers, side-by-side diff pairs, and the window
-- lifecycle that keeps the layout intact — :q on a preview quits nvim when the
-- preview is the last editor content (file-explorer parity), otherwise the
-- whole pair closes with the quit pane, and repairs never leave a sidebar as
-- the only window.
local M = {}

-- URI prefixes that mark a buffer as a sidebar preview scratch.
local SCHEMES = { "gitpanel://", "searchpanel://" }

-- Left/right panes of side-by-side pairs, by name prefix. Single-pane
-- previews (e.g. gitpanel://added/) are previews but not pair views.
local PAIR_PREFIXES = {
  "gitpanel://previous/",
  "gitpanel://updated/",
  "gitpanel://commit-previous/",
  "gitpanel://commit-updated/",
  "searchpanel://searched/",
  "searchpanel://replaced/",
}

local SIDEBAR_FTS = {
  activitybar = true,
  gitpanel = true,
  searchpanel = true,
  searchpanelinput = true,
  NvimTree = true,
  panelterminal = true,
  panelproblems = true,
}

-- Panel filetype -> fixed column width, registered by each panel's setup();
-- used to re-pin sidebar widths after layout repair and to anchor the
-- restored editor split beside a panel window.
local panel_widths = {}

local state = {
  closing_pairs = {},
  autocmds = false,
  quitting = false,
}

function M.register(ft, width)
  panel_widths[ft] = width
end

local function starts_with_any(name, prefixes)
  for _, prefix in ipairs(prefixes) do
    if vim.startswith(name, prefix) then
      return true
    end
  end
  return false
end

function M.is_preview(name)
  return starts_with_any(name, SCHEMES)
end

local function is_pair_view(name)
  return starts_with_any(name, PAIR_PREFIXES)
end

function M.is_sidebar_ft(ft)
  return SIDEBAR_FTS[ft] == true
end

-- First window that isn't a sidebar/panel occupant; nil if none exist.
function M.main_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not SIDEBAR_FTS[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] then
      return win
    end
  end
  return nil
end

-- Wipes previous pair state before opening another selection. When `keep_one`
-- is true, one existing pair scratch window is reused as the next main editor
-- window, so closing stale panes cannot make the sidebar absorb the whole
-- editor area.
function M.close_diffs(keep_one)
  pcall(vim.cmd, "diffoff!")
  local keep_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
    if vim.startswith(name, "gitsigns://") then
      pcall(vim.api.nvim_win_close, win, true)
    elseif is_pair_view(name) then
      if keep_one and not keep_win then
        keep_win = win
      else
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
  return keep_win
end

local function buffer_by_name(name)
  local bufnr = vim.fn.bufnr(name)
  if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
    return bufnr
  end
  return nil
end

function M.scratch_buffer(name, lines, path, opts)
  opts = opts or {}
  local buf = buffer_by_name(name)
  if not buf then
    buf = vim.api.nvim_create_buf(opts.listed ~= false, true)
    vim.api.nvim_buf_set_name(buf, name)
  end

  vim.bo[buf].buflisted = opts.listed ~= false
  vim.b[buf].sidebar_label = opts.label
  vim.b[buf].sidebar_tab_label = opts.tab_label or opts.label
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local ft = path and vim.filetype.match({ filename = path }) or nil
  if ft then
    vim.bo[buf].filetype = ft
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = opts.bufhidden or "hide"
  return buf
end

local function pair_key(a, b)
  return tostring(math.min(a, b)) .. ":" .. tostring(math.max(a, b))
end

local function pair_windows(buf, pair_buf)
  local pair = { [buf] = true, [pair_buf] = true }
  local wins = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if pair[vim.api.nvim_win_get_buf(win)] then
      wins[#wins + 1] = win
    end
  end
  return wins
end

local function has_non_pair_editor_window(buf, pair_buf)
  local pair = { [buf] = true, [pair_buf] = true }
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local win_buf = vim.api.nvim_win_get_buf(win)
    if not pair[win_buf] and not SIDEBAR_FTS[vim.bo[win_buf].filetype] then
      return true
    end
  end
  return false
end

local function fallback_editor_buffer(buf, pair_buf)
  local pair = {}
  if buf then
    pair[buf] = true
  end
  if pair_buf then
    pair[pair_buf] = true
  end

  for _, candidate in ipairs(vim.api.nvim_list_bufs()) do
    if
      not pair[candidate]
      and vim.api.nvim_buf_is_valid(candidate)
      and vim.bo[candidate].buflisted
      and not M.is_preview(vim.api.nvim_buf_get_name(candidate))
    then
      return candidate
    end
  end

  return vim.api.nvim_create_buf(true, false)
end

local function editor_window_exists()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not SIDEBAR_FTS[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] then
      return true
    end
  end
  return false
end

local function restore_editor_window_if_missing()
  if state.quitting or vim.v.dying > 0 or editor_window_exists() then
    return
  end

  local anchor_win = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if panel_widths[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] then
      anchor_win = win
      break
    end
  end
  anchor_win = anchor_win or vim.api.nvim_get_current_win()

  if not vim.api.nvim_win_is_valid(anchor_win) then
    return
  end

  vim.api.nvim_set_current_win(anchor_win)
  vim.cmd("botright vertical split")
  local editor_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(editor_win, fallback_editor_buffer())
  vim.wo[editor_win].diff = false

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local width = panel_widths[vim.bo[vim.api.nvim_win_get_buf(win)].filetype]
    if width then
      pcall(vim.api.nvim_win_set_width, win, width)
    end
  end
end

local function preserve_editor_window_if_last(buf, pair_buf)
  if has_non_pair_editor_window(buf, pair_buf) then
    return nil
  end

  local keep_win = pair_windows(buf, pair_buf)[1]
  if not keep_win then
    return nil
  end

  local replacement = fallback_editor_buffer(buf, pair_buf)
  vim.api.nvim_win_set_buf(keep_win, replacement)
  vim.wo[keep_win].diff = false
  return keep_win
end

local function delete_buffer_if_valid(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_del_var, buf, "sidebar_preview_pair_buf")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

local function close_pair(buf, pair_buf)
  if not (buf and pair_buf) then
    return
  end

  local key = pair_key(buf, pair_buf)
  if state.closing_pairs[key] then
    return
  end
  state.closing_pairs[key] = true

  vim.schedule(function()
    pcall(vim.cmd, "diffoff!")
    local keep_win = preserve_editor_window_if_last(buf, pair_buf)
    for _, win in ipairs(pair_windows(buf, pair_buf)) do
      if win ~= keep_win and #vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(win)) > 1 then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    delete_buffer_if_valid(buf)
    delete_buffer_if_valid(pair_buf)
    state.closing_pairs[key] = nil
  end)
end

local function ensure_autocmds()
  if state.autocmds then
    return
  end
  state.autocmds = true

  local group = vim.api.nvim_create_augroup("sidebar-preview", { clear = true })
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      if state.quitting or not M.is_preview(vim.api.nvim_buf_get_name(buf)) then
        return
      end

      local ok, pair_buf = pcall(vim.api.nvim_buf_get_var, buf, "sidebar_preview_pair_buf")
      pair_buf = ok and pair_buf or nil
      if has_non_pair_editor_window(buf, pair_buf or buf) then
        -- Another editor window survives this quit: let :q close the pane
        -- and take the rest of the preview down with it.
        if pair_buf then
          close_pair(buf, pair_buf)
        end
        return
      end

      -- The preview is the last editor content; quit nvim entirely, as the
      -- file explorer does when only the tree would remain.
      state.quitting = true
      local command = vim.v.cmdbang == 1 and "qall!" or "qall"
      local qok, err = pcall(vim.cmd, command)
      if not qok then
        state.quitting = false
        error(err)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(args)
      local ok, pair_buf = pcall(vim.api.nvim_buf_get_var, args.buf, "sidebar_preview_pair_buf")
      if ok then
        close_pair(args.buf, pair_buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    callback = function(args)
      if M.is_preview(vim.api.nvim_buf_get_name(args.buf)) then
        vim.schedule(restore_editor_window_if_missing)
      end
    end,
  })
end

local function link_pair(left, right)
  ensure_autocmds()
  vim.b[left].sidebar_preview_pair_buf = right
  vim.b[right].sidebar_preview_pair_buf = left
end

local function focus_editor_area()
  local win = M.close_diffs(true) or M.main_win()
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("botright vsplit")
  end
end

function M.open_scratch(name, lines, path, opts)
  -- Single-pane previews have no diff pair, but still need the QuitPre and
  -- editor-restore autocmds.
  ensure_autocmds()
  focus_editor_area()
  vim.api.nvim_win_set_buf(0, M.scratch_buffer(name, lines, path, opts))
end

function M.show_side_by_side(previous_name, previous_lines, updated_name, updated_lines, path, opts)
  opts = opts or {}
  focus_editor_area()

  local left = M.scratch_buffer(previous_name, previous_lines, path, {
    label = opts.previous_label,
    listed = false,
    tab_label = opts.tab_label,
  })
  local right = M.scratch_buffer(updated_name, updated_lines or {}, path, {
    label = opts.updated_label,
    listed = true,
    tab_label = opts.tab_label,
  })
  link_pair(left, right)

  local left_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(left_win, left)
  vim.cmd("rightbelow vertical split")
  local right_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(right_win, right)

  vim.api.nvim_win_call(left_win, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_win_call(right_win, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_set_current_win(right_win)
end

function M.show_existing_pair(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return false
  end

  local ok, pair_buf = pcall(vim.api.nvim_buf_get_var, buf, "sidebar_preview_pair_buf")
  if not (ok and vim.api.nvim_buf_is_valid(pair_buf)) then
    return false
  end

  local name = vim.api.nvim_buf_get_name(buf)
  local left = (name:find("previous/", 1, true) or name:find("searched/", 1, true)) and buf or pair_buf
  local right = left == buf and pair_buf or buf
  focus_editor_area()

  local left_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(left_win, left)
  vim.cmd("rightbelow vertical split")
  local right_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(right_win, right)

  vim.api.nvim_win_call(left_win, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_win_call(right_win, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_set_current_win(right_win)
  return true
end

return M
