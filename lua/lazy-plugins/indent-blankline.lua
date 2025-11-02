return {
  "lukas-reineke/indent-blankline.nvim",

  -- Lazy-load on event.
  event = { "BufReadPre" },

  config = function(_, opts)
    local highlight = {
      "RainbowRed",
      "RainbowYellow",
      "RainbowBlue",
      "RainbowOrange",
      "RainbowGreen",
      "RainbowViolet",
      "RainbowCyan",
    }

    local hooks = require("ibl.hooks")
    -- create the highlight groups in the highlight setup hook, so they are reset
    -- every time the colorscheme changes
    hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
      vim.api.nvim_set_hl(0, "RainbowRed", { fg = "#7f2f3f" })
      vim.api.nvim_set_hl(0, "RainbowYellow", { fg = "#7f6c2f" })
      vim.api.nvim_set_hl(0, "RainbowBlue", { fg = "#2f4f7f" })
      vim.api.nvim_set_hl(0, "RainbowOrange", { fg = "#7f4f2f" })
      vim.api.nvim_set_hl(0, "RainbowGreen", { fg = "#2f7f4f" })
      vim.api.nvim_set_hl(0, "RainbowViolet", { fg = "#5f2f7f" })
      vim.api.nvim_set_hl(0, "RainbowCyan", { fg = "#2f7f7f" })
    end)

    require("ibl").setup({
      indent = { char = "│", highlight = highlight },
      scope = {
        show_start = false,
        show_end = false,
      },
    })
  end,
}
