---@type MappingsTable
local M = {}

M.general = {
  n = {
    [";"] = { ":", "enter command mode", opts = { nowait = true } },
  },
}

-- more keybinds!

M.abc = {
  i = {
    ["<Tab>"] = { "<C-t>", "add indent" },
    ["<S-Tab>"] = { "<C-d>", "remove indent" },
  },
}

return M
