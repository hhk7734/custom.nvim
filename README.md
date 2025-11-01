# custom.nvim

## Install

```shell
git clone git@github.com:hhk7734/custom.nvim.git ~/.config/nvim && nvim
```

## Uninstall

```shell
rm -rf ~/.config/nvim
rm -rf ~/.local/state/nvim
rm -rf ~/.local/share/nvim
```

## Neovim

### Startup

> [!NOTE] Reference
> [Neovim / Starting # Startup](https://neovim.io/doc/user/starting.html#startup)

1. Set `shell`.
2. Process the arguments.
3. Start a server.
4. Wait for UI to connect.
5. Setup `default-mappings` and `default-autocmds`. Create `popup-menu`.
6. Enable filetype and indent plugins.
7. Load user config `init.lua`.
8. Enable filetype detection.
9. Enable syntax highlighting.
10. Load `plugin/**/*.lua`.
11. ...

### lua

> [!NOTE] Reference
> [Neovim / Lua-guide](https://neovim.io/doc/user/lua-guide.html)
> [Neovim / Lua](https://neovim.io/doc/user/lua.html)

Neovim loads `init.lua` from `~/.config/nvim/` by default.

- `:lua vim.print(vim.o.runtimepath)`
  - [Neovim / Options # runtimepath](https://neovim.io/doc/user/options.html#'runtimepath')
  - filetype.lua
  - autoload/
  - colors/
  - compiler/
  - doc/
  - ftplugin/
  - indent/
  - keymap/
  - lang/
  - lsp/
  - `lua/`: lua plugins
  - pack/
  - parser/
  - plugin/
  - queries/
  - rplugin/
  - spell/
  - syntax/
  - totor/

### options

> [!NOTE] Reference
> [Neovim / Options](https://neovim.io/doc/user/options.html)

- `:lua vim.print(vim.o.<var>)`
- `:lua vim.print(vim.opt.<var>:get())`
