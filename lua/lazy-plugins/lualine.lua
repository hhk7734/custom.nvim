return {
  -- https://github.com/nvim-lualine/lualine.nvim
  "nvim-lualine/lualine.nvim",

  lazy = false,

  dependencies = { "nvim-tree/nvim-web-devicons" },

  opts = {
    -- Follow the active colorscheme (github-theme ships a lualine palette).
    theme = "auto",
    options = {
      -- The activity bar is a narrow icon strip and the search panel's input
      -- section is fixed-height; no statusline under either.
      disabled_filetypes = { statusline = { "activitybar", "searchpanelinput" } },
    },
  },
}
