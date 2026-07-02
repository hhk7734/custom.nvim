# VSCode-style UI: activity bar, panels, breadcrumbs

- Date: 2026-07-02
- Status: approved design snapshot

## Goal

Make the Neovim layout resemble VSCode — a far-left icon activity bar, a titled
explorer sidebar, a bottom panel with terminal and problems views, and
breadcrumbs above the code area — while keeping the existing stack (tokyonight,
bufferline, lualine, telescope, nvim-tree, gitsigns, diffview).

## Requirements

- A narrow clickable icon column at the far left with entries: Explorer,
  Search, Source Control, Terminal, Problems, and a bottom-anchored Settings
  entry. The active view's icon is highlighted.
- Sidebar and bottom panels have VSCode-like titles and stable sizes.
- The integrated terminal toggles with `` Ctrl+` `` (as in VSCode).
- A Problems view lists workspace diagnostics.
- Breadcrumbs (file path + document symbols) render above code windows.
- Existing behaviors are preserved: `<C-Left>` explorer focus-or-toggle,
  bufferline tab alignment over the sidebar, and Neovim exiting when only
  panel windows remain.
- Theme stays tokyonight. No VSCode colorscheme.

## Component choices

| Piece          | Implementation                                    |
| -------------- | ------------------------------------------------- |
| Activity bar   | custom module `lua/core/activitybar.lua`          |
| Panel docking  | [folke/edgy.nvim](https://github.com/folke/edgy.nvim) |
| Terminal       | [akinsho/toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) |
| Problems       | [folke/trouble.nvim](https://github.com/folke/trouble.nvim) |
| Breadcrumbs    | [Bekaboo/dropbar.nvim](https://github.com/Bekaboo/dropbar.nvim) |

No maintained plugin implements a VSCode-style icon activity bar (verified via
awesome-neovim / neovimcraft, 2026-07); it is therefore a small custom module.
Neovim 0.12.2 satisfies every plugin's version requirement.

## Design

### 1. Activity bar (custom, ~120 lines)

- A fixed 3-column window at the far left holding an unlisted scratch buffer,
  filetype `activitybar`; `winfixwidth`, no numbers, signs, cursorline, or
  statuscolumn.
- An entries table of `{ icon, desc, action, is_active }`:
  - `󰉋` Explorer → existing nvim-tree focus-or-toggle behavior
  - `` Search → `Telescope live_grep`
  - `` Source Control → Diffview toggle
  - `` Terminal → ToggleTerm toggle
  - `󰀪` Problems → Trouble diagnostics toggle
  - `⚙` Settings (rendered at the bottom of the column) → `Lazy`
- A buffer-local `<LeftMouse>` mapping resolves the clicked row with
  `vim.fn.getmousepos()` and runs the entry's action, then returns focus to
  the previous window. Actions `pcall(require, ...)` or use plugin commands so
  lazy.nvim's lazy loading is unaffected.
- Active-icon highlight: `WinEnter`/`WinClosed` autocmds re-evaluate each
  entry's `is_active()` and re-apply extmark highlights.
- `:ActivityBar toggle` user command; the bar auto-opens on `VimEnter`.
- Loaded from `init.lua` after `require("config.lazy")`.

### 2. edgy.nvim (panel docking)

- `left`: nvim-tree, title "Explorer", size 30, pinned.
- `bottom`: toggleterm (title "Terminal", size 12) and Trouble diagnostics
  (title "Problems").
- `exit_when_last = true` replaces the hand-rolled "quit when nvim-tree is the
  last window" autocmd currently in `lua/lazy-plugins/nvim-tree.lua` — edgy
  understands all managed panels, not just the tree, so this removes custom
  code rather than adding it.
- Animations disabled for snappy, VSCode-like toggling.

### 3. toggleterm.nvim

- Horizontal direction (bottom panel), `` open_mapping = [[<c-`>]] ``, size 12.

### 4. trouble.nvim

- v3, diagnostics mode. Opened via `<leader>xx` or the activity-bar icon.

### 5. dropbar.nvim

- Default configuration (path + LSP symbol breadcrumbs, clickable).
- Fuzzy-pick keymap `<leader>;`.
- Panel windows (activitybar, NvimTree, terminal, Trouble) show no winbar;
  dropbar's defaults already exclude special buftypes, with explicit filetype
  exclusions added only if needed.

### Changes to existing files

- `lua/lazy-plugins/bufferline.lua`: add an `offsets` entry for the
  `activitybar` filetype (blank text) so the tab row stays aligned.
- `lua/lazy-plugins/nvim-tree.lua`: remove the `BufEnter`/`QuitPre`
  last-window autocmd (superseded by edgy `exit_when_last`); keep the
  `<C-Left>` keymap, filters, and `on_attach`.
- `init.lua`: require the activity-bar module after lazy.nvim setup.
- New plugin spec files, one per plugin, following the existing pattern:
  `lua/lazy-plugins/edgy.lua`, `toggleterm.lua`, `trouble.lua`, `dropbar.lua`.

## Keymaps

| Key         | Action                        |
| ----------- | ----------------------------- |
| `` <C-`> `` | Toggle terminal (VSCode-like) |
| `<leader>xx`| Toggle Problems (Trouble)     |
| `<leader>;` | Dropbar fuzzy pick            |
| `<C-Left>`  | Explorer focus/toggle (unchanged) |

## Testing

- `nvim --headless "+Lazy! sync" +qa` completes without errors.
- Manual checklist: each activity-bar icon triggers its action and the active
  highlight follows; `` Ctrl+` `` toggles the terminal; Problems lists real
  diagnostics; breadcrumbs render and are clickable; bufferline stays aligned
  over the sidebar; `:qa` and closing the last code window exit cleanly with
  panels open.

## Alternatives considered

- **edgy.nvim only, no icon bar** — less bespoke code, but the icon strip was
  the explicit ask.
- **sidebar.nvim** — text sections rather than an icon bar; effectively
  unmaintained.
- **barbecue.nvim** for breadcrumbs — superseded by dropbar.nvim (clickable,
  actively maintained, fine on 0.12).
- **Mofiqul/vscode.nvim theme** — offered and declined; tokyonight stays.

## Out of scope

- Git / outline panels in the sidebar (easy to add to edgy later).
- Broader VSCode keybinding parity.
- Colorscheme changes.
