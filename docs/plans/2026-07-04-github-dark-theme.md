# GitHub Dark Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch the colorscheme from tokyonight (storm) to `github_dark_default` with lualine following the theme, per `docs/specs/2026-07-04-github-dark-theme.md`.

**Architecture:** Replace the tokyonight lazy spec with a github-nvim-theme spec of the same shape (`lazy = false`, `priority = 1000`, setup + `colorscheme`), update lazy.nvim's install-time colorscheme and lualine's theme, refresh the README. Custom UI highlight groups are links and re-resolve on their own.

**Tech Stack:** Neovim (Lua), lazy.nvim, projekt0n/github-nvim-theme `v1.1.2` (latest tag, verified via ls-remote).

**Context notes for the implementer:**
- Repo conventions: pin plugin release tags; stylua on changed Lua files (`~/.local/share/nvim/mason/bin/stylua`); single-scope Conventional Commits; `lazy-lock.json` is gitignored (never commit it).
- Headless nvim renders no UI but colorscheme/highlight state is fully verifiable.
- tokyonight values for comparison (must change): `Normal` bg `#24283b`, `PanelTabActive` bg `#7aa2f7`.

---

### Task 1: Swap the colorscheme plugin

**Files:**
- Create: `lua/lazy-plugins/github-theme.lua`
- Delete: `lua/lazy-plugins/tokyonight.lua`
- Modify: `lua/config/lazy.lua:30` (install colorscheme)

- [ ] **Step 1: Write the new plugin spec**

```lua
return {
  -- https://github.com/projekt0n/github-nvim-theme
  "projekt0n/github-nvim-theme",

  name = "github-theme",

  tag = "v1.1.2",

  lazy = false,

  -- Load before every other plugin so highlight groups resolve against the
  -- final palette.
  priority = 1000,

  config = function()
    require("github-theme").setup({})
    vim.cmd.colorscheme("github_dark_default")
  end,
}
```

- [ ] **Step 2: Delete the tokyonight spec**

```sh
git rm lua/lazy-plugins/tokyonight.lua
```

- [ ] **Step 3: Update lazy.nvim's install-time colorscheme**

In `lua/config/lazy.lua`, replace:

```lua
  install = { colorscheme = { "tokyonight" } },
```

with:

```lua
  install = { colorscheme = { "github_dark_default" } },
```

- [ ] **Step 4: Install and clean**

```sh
nvim --headless "+Lazy! install" +qa 2>&1 | tail -1
nvim --headless "+Lazy! clean" +qa 2>&1 | tail -1
```

- [ ] **Step 5: Verify the active palette**

Run:
```sh
nvim --headless "+lua vim.wait(200) print('scheme=' .. tostring(vim.g.colors_name)) local n = vim.api.nvim_get_hl(0, { name = 'Normal', link = false }) print('normal_bg=' .. string.format('#%06x', n.bg)) local p = vim.api.nvim_get_hl(0, { name = 'PanelTabActive', link = false }) print('paneltab_bg=#' .. string.format('%06x', p.bg) .. ' relinked=' .. tostring(p.bg ~= 0x7aa2f7)) local a = vim.api.nvim_get_hl(0, { name = 'ActivityBarActive', link = false }) print('bar_active_fg=' .. string.format('#%06x', a.fg))" +qa! 2>&1
```
Expected: `scheme=github_dark_default`, `normal_bg=#0d1117`, `relinked=true`, and a `bar_active_fg` value (Function's github color, not tokyonight's `#7aa2f7`).

- [ ] **Step 6: Format and commit**

```sh
stylua lua/lazy-plugins/github-theme.lua lua/config/lazy.lua
git add lua/lazy-plugins/github-theme.lua lua/config/lazy.lua lua/lazy-plugins/tokyonight.lua
git commit -m "feat(github-theme): switch colorscheme to github_dark_default"
```

---

### Task 2: lualine follows the theme

**Files:**
- Modify: `lua/lazy-plugins/lualine.lua:10`

- [ ] **Step 1: Set the theme to auto**

Replace:

```lua
    theme = "palenight",
```

with:

```lua
    -- Follow the active colorscheme (github-theme ships a lualine palette).
    theme = "auto",
```

- [ ] **Step 2: Verify lualine loads with the auto theme**

Run:
```sh
nvim --headless "+lua vim.wait(200) local ok = pcall(require, 'lualine') print('lualine_ok=' .. tostring(ok)) print('startup-ok')" +qa! 2>&1
```
Expected: `lualine_ok=true`, `startup-ok`, no error lines.

- [ ] **Step 3: Format and commit**

```sh
stylua lua/lazy-plugins/lualine.lua
git add lua/lazy-plugins/lualine.lua
git commit -m "feat(lualine): follow the active colorscheme"
```

---

### Task 3: README

**Files:**
- Modify: `README.md` (colorscheme and lualine table rows)

- [ ] **Step 1: Update the two rows**

Replace:

```markdown
| [tokyonight.nvim](https://github.com/folke/tokyonight.nvim)                     | Colorscheme (Tokyo Night, storm variant).                                                         |
| [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim)                    | Statusline (palenight theme).                                                                     |
```

with:

```markdown
| [github-nvim-theme](https://github.com/projekt0n/github-nvim-theme)             | Colorscheme (GitHub Dark Default).                                                                |
| [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim)                    | Statusline (theme follows the colorscheme).                                                       |
```

- [ ] **Step 2: Format and commit**

```sh
~/.local/share/nvim/mason/bin/deno fmt README.md
git add README.md
git commit -m "docs: document the github dark colorscheme"
```

---

### Task 4: End-to-end verification (no commit)

- [ ] **Step 1: Startup smoke + UI groups sanity**

Run:
```sh
nvim --headless "+lua vim.wait(200) print('startup-ok')" +qa! 2>&1
nvim --headless "+lua require('core.activitybar').open() require('nvim-tree.api').tree.open() require('core.panel').toggle('problems') vim.wait(400) local win = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do win[vim.bo[vim.api.nvim_win_get_buf(w)].filetype] = w end print('layout=' .. tostring(win.NvimTree ~= nil and win.panelproblems ~= nil) .. ' scheme=' .. tostring(vim.g.colors_name))" +qa! 2>&1
```
Expected: `startup-ok`; `layout=true scheme=github_dark_default`.

- [ ] **Step 2: Interactive checklist (report to user)**

- Overall palette is github.com dark mode (near-black background).
- Statusline no longer purple; matches the theme.
- Activity-bar active icon, panel tab strip (active/inactive contrast), and gitpanel status letters are readable on `#0d1117` — each is a one-line relink if too dim.
