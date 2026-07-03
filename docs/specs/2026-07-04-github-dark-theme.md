# Colorscheme: GitHub Dark Default

- Date: 2026-07-04
- Status: approved design snapshot
- Supersedes the colorscheme choice of `2026-07-02-vscode-style-ui.md`
  (tokyonight storm)

## Goal

Switch the colorscheme from tokyonight (storm) to GitHub Dark Default
(`github_dark_default` from projekt0n/github-nvim-theme) — the palette
github.com uses in dark mode (near-black `#0d1117` background). The
statusline follows the theme instead of staying on palenight.

## Requirements

- `github_dark_default` is the active colorscheme at startup and lazy.nvim's
  install-time colorscheme.
- tokyonight.nvim is removed (spec deleted, install cleaned).
- lualine uses `theme = "auto"` so it adopts the github theme's shipped
  lualine palette (and any future colorscheme automatically).
- No changes to custom modules: panel tabs, activity bar, and gitpanel
  highlight groups are links to standard groups and must re-resolve to the
  new palette on their own.
- README reflects the new colorscheme row and the lualine row no longer
  claims palenight.

## Design

- Delete `lua/lazy-plugins/tokyonight.lua`; create
  `lua/lazy-plugins/github-theme.lua`: `projekt0n/github-nvim-theme` pinned
  to its latest release tag (repo convention), `lazy = false`,
  `priority = 1000`, `require("github-theme").setup({})` then
  `vim.cmd.colorscheme("github_dark_default")` — the same shape as the
  tokyonight spec it replaces.
- `lua/config/lazy.lua`: `install = { colorscheme = { "github_dark_default" } }`.
- `lua/lazy-plugins/lualine.lua`: `theme = "auto"`.
- `README.md`: colorscheme table row → github-nvim-theme, "Colorscheme
  (GitHub Dark Default)"; lualine row → "Statusline (theme follows the
  colorscheme)".

## Out of scope

- Keeping tokyonight installed for switching between themes.
- Per-group tuning for the new palette (activity bar, panel tabs, gitpanel
  keep their links; adjustments, if the near-black background makes anything
  too dim, are follow-up one-liners).
- Light/auto variants and background toggling.

## Alternatives considered

- **Add github-nvim-theme alongside tokyonight** — switchable themes nobody
  asked for; rejected (YAGNI).
- **Recolor tokyonight via highlight overrides** — a maintenance burden
  imitating a palette that exists as a first-class theme; rejected.
- Variant choice: user picked `github_dark_default` over `github_dark`
  (legacy soft), `github_dark_dimmed`, and `github_dark_high_contrast`;
  lualine `auto` over keeping palenight.

## Verification

Headless: `vim.g.colors_name == "github_dark_default"`; `Normal` bg is
`#0d1117`; `PanelTabActive` / `ActivityBarActive` resolve to values that
differ from the tokyonight ones (links re-resolved); startup smoke with no
errors; lualine loads with `theme = "auto"`. Interactive: eyeball the tab
strip, activity bar, and gitpanel contrast on the near-black background.
