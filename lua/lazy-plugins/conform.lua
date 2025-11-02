return {
  -- https://github.com/stevearc/conform.nvim
  "stevearc/conform.nvim",

  -- Lazy-load on event. BufWritePre means before saving a buffer.
  event = { "BufWritePre" },

  -- Lazy-load on command.
  cmd = { "ConformInfo" },

  -- require("conform").setup(opts)
  opts = {
    formatters_by_ft = {
      lua = { "stylua" },
    },

    default_format_opts = {
      timeout_ms = 2000,
      async = false,
      quiet = false,
      lsp_format = "fallback",
    },

    format_on_save = {},
  },
}
