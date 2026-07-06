return {
  -- https://github.com/sindrets/diffview.nvim
  "sindrets/diffview.nvim",

  commit = "4516612fe98ff56ae0415a259ff6361a89419b0a",

  cmd = {
    "DiffviewOpen",
    "DiffviewClose",
    "DiffviewFileHistory",
    "DiffviewFocusFiles",
    "DiffviewToggleFiles",
    "DiffviewRefresh",
  },

  dependencies = {
    "nvim-lua/plenary.nvim",
  },

  opts = {
    view = {
      default = {
        layout = "diff2_horizontal",
      },
      file_history = {
        layout = "diff2_horizontal",
      },
    },
    file_panel = {
      listing_style = "tree",
      win_config = {
        position = "left",
        width = 35,
      },
    },
  },
}
