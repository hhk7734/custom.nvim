local on_attach = require("plugins.configs.lspconfig").on_attach
local capabilities = require("plugins.configs.lspconfig").capabilities

local lspconfig = require "lspconfig"
local root_pattern = lspconfig.util.root_pattern

-- if you just want default config for the servers then put them in a table
local servers = { "html", "cssls", "clangd" }

for _, lsp in ipairs(servers) do
  lspconfig[lsp].setup {
    on_attach = on_attach,
    capabilities = capabilities,
  }
end

--
-- lspconfig.pyright.setup { blabla}

lspconfig.rome.setup {
  on_attach = on_attach,
  capabilities = capabilities,
  root_dir = root_pattern("rome.json"),
}

lspconfig.gopls.setup {
  on_attach = on_attach,
  capabilities = capabilities,
  root_dir = root_pattern("go.mod"),
}

lspconfig.yamlls.setup {
  on_attach = on_attach,
  capabilities = capabilities,
}
