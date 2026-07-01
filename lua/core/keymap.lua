local map = vim.keymap.set

-- save
map({ "n", "i", "v" }, "<C-s>", "<cmd>w<CR>")
-- install x11-ssh-askpass
vim.env.SUDO_ASKPASS = "/usr/lib/ssh/ssh-askpass"
map(
  { "n", "i", "v" },
  "<C-S-s>",
  "<cmd>w ! sudo -A tee % > /dev/null<CR>",
  { desc = "save the current file with sudo privileges" }
)

-- indent
map("i", "<Tab>", "<C-t>", { desc = "add indent" })
map("i", "<S-Tab>", "<C-d>", { desc = "remove indent" })

-- comment
map("n", "<C-/>", "gcc", { remap = true, desc = "toggle comment" })
map("v", "<C-/>", "gc", { remap = true, desc = "toggle comment" })
-- Some terminals send <C-_> for <C-/>
map("n", "<C-_>", "gcc", { remap = true, desc = "toggle comment" })
map("v", "<C-_>", "gc", { remap = true, desc = "toggle comment" })

-- toggle soft line wrap
map("n", "<leader>w", "<cmd>set wrap!<CR>", { desc = "toggle line wrap" })
