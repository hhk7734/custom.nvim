local M = {}

M.HIGHLIGHT_FG = 0x58a6ff
local HIGHLIGHT_FG_HEX = "#58a6ff"

local function merged_winhighlight(current)
  local parts = {}
  local replaced = false
  for part in tostring(current or ""):gmatch("[^,]+") do
    if part:match("^%s*WinSeparator:") then
      parts[#parts + 1] = "WinSeparator:SidebarResizeHandle"
      replaced = true
    elseif part ~= "" then
      parts[#parts + 1] = part
    end
  end

  if not replaced then
    parts[#parts + 1] = "WinSeparator:SidebarResizeHandle"
  end

  return table.concat(parts, ",")
end

function M.apply_highlights()
  vim.api.nvim_set_hl(0, "SidebarResizeHandle", { fg = HIGHLIGHT_FG_HEX, bold = true })
end

function M.style_window(win)
  vim.wo[win].winhighlight = merged_winhighlight(vim.wo[win].winhighlight)
end

function M.setup()
  M.apply_highlights()

  local group = vim.api.nvim_create_augroup("sidebar-resize-handle", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = M.apply_highlights,
  })
end

return M
