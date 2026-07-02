return {
  -- https://github.com/folke/edgy.nvim
  "folke/edgy.nvim",

  event = "VeryLazy",

  init = function()
    -- Recommended by edgy: keep text stable when panels open/close.
    vim.opt.splitkeep = "screen"
  end,

  opts = {
    -- Snappy, VSCode-like toggling.
    animate = { enabled = false },

    bottom = {
      {
        ft = "toggleterm",
        title = "Terminal",
        size = { height = 12 },
        -- Only manage normal splits; floating toggleterm windows stay floating.
        filter = function(_, win)
          return vim.api.nvim_win_get_config(win).relative == ""
        end,
      },
      {
        ft = "trouble",
        title = "Problems",
        size = { height = 12 },
      },
    },
  },
}
