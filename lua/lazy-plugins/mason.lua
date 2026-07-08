-- Mason packages to keep installed, pinned to an exact version (`name@version`)
-- for deterministic tooling. Use the version string mason reports (shown in
-- `:Mason`, i.e. Package:get_installed_version()); bump it here to update.
local ensure_installed = {
  "stylua@v2.5.2", -- Lua formatter (conform: lua)
  "deno@v2.9.0", -- Deno runtime; provides `deno fmt` (conform: markdown -> deno_fmt)
}

return {
  -- https://github.com/mason-org/mason.nvim
  -- Package manager for external tools (formatters, LSP servers, ...).
  -- Prepends its bin dir to $PATH, so conform finds tools installed here.
  "mason-org/mason.nvim",
  lazy = false,
  opts = {},
  config = function(_, opts)
    require("mason").setup(opts)

    -- In-house replacement for mason-tool-installer: enforce that each
    -- `ensure_installed` package is present AT its pinned version, using only
    -- mason's public API. refresh() always invokes the callback.
    local registry = require("mason-registry")
    local Package = require("mason-core.package")
    registry.refresh(function()
      for _, spec in ipairs(ensure_installed) do
        local name, version = Package.Parse(spec)
        local ok, pkg = pcall(registry.get_package, name)
        if ok and not pkg:is_installing() then
          -- A pinned version that differs from the installed one is a mismatch;
          -- an unpinned entry (no `@version`) only checks for presence.
          local mismatched = version ~= nil and pkg:get_installed_version() ~= version
          if not pkg:is_installed() or mismatched then
            pkg:install({ version = version })
          end
        end
      end
    end)
  end,
}
