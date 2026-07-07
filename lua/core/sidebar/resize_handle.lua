local M = {}

M.HIGHLIGHT_FG = 0x58a6ff
M.INDICATOR = "┃"
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

function M.line_mark(line)
  return {
    line = line,
    col = 0,
    virt_text = { { M.INDICATOR, "SidebarResizeHandle" } },
    virt_text_pos = "right_align",
  }
end

function M.add_line_marks(marks, line_count)
  local index = 0
  for key in pairs(marks) do
    if type(key) == "number" and key > index then
      index = key
    end
  end
  for line = 1, line_count do
    index = index + 1
    marks[index] = M.line_mark(line)
  end
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
