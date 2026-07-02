return {
  -- https://github.com/folke/trouble.nvim
  "folke/trouble.nvim",

  cmd = "Trouble",

  -- For file icons.
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },

  keys = {
    { "<leader>xx", "<cmd>Trouble diagnostics toggle<CR>", desc = "toggle problems" },
  },

  opts = {},
}
