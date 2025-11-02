return {
  "hrsh7th/nvim-cmp",

  -- Lazy-load on event.
  event = { "InsertEnter" },

  dependencies = {
    {
      "windwp/nvim-autopairs",

      opts = {
        fast_wrap = {},
        disable_filetype = { "TelescopePrompt", "vim" },
      },

      config = function(_, opts)
        require("nvim-autopairs").setup(opts)

        -- setup cmp for autopairs
        local cmp_autopairs = require("nvim-autopairs.completion.cmp")
        require("cmp").event:on("confirm_done", cmp_autopairs.on_confirm_done())
      end,
    },

    {
      "hrsh7th/cmp-nvim-lua",
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "https://codeberg.org/FelipeLema/cmp-async-path.git",
    },
  },

  opts = {
    completion = { completeopt = "menu,menuone" },

    sources = {
      { name = "nvim_lua" },
      { name = "nvim_lsp" },
      { name = "buffer" },
      { name = "async_path" },
    },
  },

  config = function(_, opts)
    local cmp = require("cmp")

    opts.mapping = {
      ["<C-Space>"] = cmp.mapping.complete(),

      ["<Tab>"] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_next_item()
        else
          fallback()
        end
      end, { "i", "s" }),

      ["<S-Tab>"] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_prev_item()
        else
          fallback()
        end
      end, { "i", "s" }),

      ["<CR>"] = cmp.mapping.confirm({
        behavior = cmp.ConfirmBehavior.Insert,
        select = true,
      }),
    }

    cmp.setup(opts)
  end,
}
