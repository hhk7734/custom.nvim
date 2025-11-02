return {
  -- https://github.com/neovim/nvim-lspconfig
  "neovim/nvim-lspconfig",

  -- Lazy-load on event.
  event = { "BufReadPre" },

  config = function()
    vim.lsp.enable({
      "lua_ls",
    })
  end,
}
