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

  opts = {},

  config = function(_, opts)
    require("diffview").setup(opts)
    local map = vim.keymap.set

    map("n", "<leader>gd", "<cmd>DiffviewOpen<CR>", { desc = "diffview open (working tree)" })
    map("n", "<leader>gD", "<cmd>DiffviewOpen main...HEAD<CR>", { desc = "diffview branch vs main" })
    map("n", "<leader>gh", "<cmd>DiffviewFileHistory %<CR>", { desc = "diffview current file history" })
    map("n", "<leader>gH", "<cmd>DiffviewFileHistory<CR>", { desc = "diffview branch history" })
    map("n", "<leader>gc", "<cmd>DiffviewClose<CR>", { desc = "diffview close" })
  end,
}
