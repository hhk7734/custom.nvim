require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

map({ "n", "i", "v" }, "<C-s>", "<cmd>w<CR>")

-- install x11-ssh-askpass
vim.env.SUDO_ASKPASS='/usr/lib/ssh/ssh-askpass'
map({ "n", "i", "v" }, "<C-S-s>", "<cmd>w ! sudo -A tee % > /dev/null<CR>", {desc = "save the current file with sudo privileges"})

map("i", "<Tab>", "<C-t>", { desc = "add indent" })
map("i", "<S-Tab>", "<C-d>", { desc = "remove indent" })

