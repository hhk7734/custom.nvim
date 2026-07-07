if vim.g.vscode then
  -- with VSCode
else
  -- without VSCode
end

-- Leaders must be set before any <leader> mapping is created and before
-- lazy.nvim loads, so keymap/plugin specs resolve <leader> correctly.
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- common
require("core.keymap")
require("core.opt")
require("config.lazy")
require("core.sidebar.resize_handle").setup()
require("core.activitybar").setup()
require("core.gitpanel").setup()
require("core.panel").setup()
