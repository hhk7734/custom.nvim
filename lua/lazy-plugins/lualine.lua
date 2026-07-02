return {
  -- https://github.com/nvim-lualine/lualine.nvim
  "nvim-lualine/lualine.nvim",

  lazy = false,

  dependencies = { "nvim-tree/nvim-web-devicons" },

  opts = {
    theme = "palenight",
    options = {
      -- The activity bar is a 3-column icon strip; no statusline under it.
      disabled_filetypes = { statusline = { "activitybar" } },
    },
  },
}
