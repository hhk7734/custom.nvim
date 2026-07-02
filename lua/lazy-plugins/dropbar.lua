return {
  -- https://github.com/Bekaboo/dropbar.nvim
  "Bekaboo/dropbar.nvim",

  event = "VeryLazy",

  -- For file icons.
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },

  keys = {
    {
      "<leader>;",
      function()
        require("dropbar.api").pick()
      end,
      desc = "dropbar pick",
    },
  },

  opts = {},
}
