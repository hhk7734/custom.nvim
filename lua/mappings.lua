require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

map("i", "<Tab>", "<C-t>", { desc = "add indent" })
map("i", "<S-Tab>", "<C-d>", { desc = "remove indent" })
