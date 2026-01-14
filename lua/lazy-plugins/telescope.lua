return {
  "nvim-telescope/telescope.nvim",

  tag = "0.2.1",

  dependencies = {
    "nvim-lua/plenary.nvim",
  },

  -- Lazy-load on command.
  cmd = { "Telescope" },

  opts = function()
    return {
      defaults = {
        prompt_prefix = "   ",
        selection_caret = " ",
        entry_prefix = " ",
        -- prompt layout configurations.
        sorting_strategy = "ascending",
        layout_config = {
          horizontal = {
            prompt_position = "top",
            preview_width = 0.55,
          },
          width = 0.87,
          height = 0.80,
        },
        mappings = {
          n = { ["q"] = require("telescope.actions").close },
        },
      },
      pickers = {},
      extensions = {},
    }
  end,

  config = function(_, opts)
    require("telescope").setup(opts)
    local map = vim.keymap.set

    map("n", "<leader>fw", "<cmd>Telescope live_grep<CR>", { desc = "telescope live grep" })
    map("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { desc = "telescope find buffers" })
    map("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "telescope find files" })
    map(
      "n",
      "<leader>fa",
      "<cmd>Telescope find_files follow=true no_ignore=true hidden=true<CR>",
      { desc = "telescope find files with hidden" }
    )
  end,
}
