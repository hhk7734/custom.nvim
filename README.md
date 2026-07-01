# custom.nvim

## Install

```shell
git clone git@github.com:hhk7734/custom.nvim.git ~/.config/nvim && nvim
```

On first launch, the formatter tools (stylua, deno) are installed automatically
via Mason.

## Uninstall

```shell
rm -rf ~/.config/nvim
rm -rf ~/.local/state/nvim
rm -rf ~/.local/share/nvim
```

## Plugins

Managed with [lazy.nvim](https://github.com/folke/lazy.nvim); each spec lives in
`lua/lazy-plugins/`.

| Plugin                                                                          | Description                                                                                       |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| [tokyonight.nvim](https://github.com/folke/tokyonight.nvim)                     | Colorscheme (Tokyo Night, storm variant).                                                         |
| [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim)                    | Statusline (palenight theme).                                                                     |
| [bufferline.nvim](https://github.com/akinsho/bufferline.nvim)                   | Shows open buffers as tabs; double-click a tab to toggle pin.                                     |
| [indent-blankline.nvim](https://github.com/lukas-reineke/indent-blankline.nvim) | Indentation guide lines.                                                                          |
| [nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua)                     | File explorer sidebar.                                                                            |
| [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)              | Fuzzy finder for files, buffers, live grep, and more.                                             |
| [which-key.nvim](https://github.com/folke/which-key.nvim)                       | Popup listing the keybindings available after a prefix.                                           |
| [menu](https://github.com/nvzone/menu)                                          | Right-click context menu.                                                                         |
| [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)                      | Configurations for Neovim's built-in LSP client.                                                  |
| [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)                                 | Autocompletion engine (LSP, buffer, path, and Lua sources; with nvim-autopairs).                  |
| [conform.nvim](https://github.com/stevearc/conform.nvim)                        | Formatter runner (lua: stylua, markdown: deno fmt; formats on save).                              |
| [mason.nvim](https://github.com/mason-org/mason.nvim)                           | Package manager for external tools; auto-installs the configured tools (stylua, deno) on startup. |
| [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim)                     | Git add/change/delete signs in the gutter.                                                        |
| [diffview.nvim](https://github.com/sindrets/diffview.nvim)                      | Git diffs and file history (`<leader>g*`).                                                        |

## 참고

- [Lua 가이드](https://wiki.loliot.net/docs/lang/etc/vim/lua)
