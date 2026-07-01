return {
  "sindrets/diffview.nvim",

  dependencies = {
    "nvim-lua/plenary.nvim",
  },

  -- Lazy-load on command.
  cmd = {
    "DiffviewOpen",
    "DiffviewClose",
    "DiffviewFileHistory",
    "DiffviewToggleFiles",
    "DiffviewFocusFiles",
  },

  -- Lazy-load on keypress (also registers the mappings with lazy.nvim).
  keys = {
    { "<leader>gd", "<cmd>DiffviewOpen<CR>", desc = "diffview open (working tree)" },
    { "<leader>gD", "<cmd>DiffviewOpen main...HEAD<CR>", desc = "diffview branch vs main" },
    { "<leader>gh", "<cmd>DiffviewFileHistory %<CR>", desc = "diffview current file history" },
    { "<leader>gH", "<cmd>DiffviewFileHistory<CR>", desc = "diffview branch history" },
    { "<leader>gc", "<cmd>DiffviewClose<CR>", desc = "diffview close" },
  },

  opts = {},
}
