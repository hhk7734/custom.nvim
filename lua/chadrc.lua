-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v2.5/lua/nvconfig.lua

---@type ChadrcConfig
local M = {}

M.base46 = {
  theme = "github_dark",
  hl_override = {
    ["@comment"] = { fg = "#00aa1c" },
    ["@function.method"] = { bold = true },
  },
}

return M
