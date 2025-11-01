return {
  -- https://github.com/stevearc/conform.nvim
  "stevearc/conform.nvim",
  -- require("conform").setup(opts)
  opts = {
    formatters_by_ft = {
      lua = { "stylua" },
    },
    format_on_save = {
      timeout_ms = 1000,
      lsp_fallback = true,
    },
  },
}
