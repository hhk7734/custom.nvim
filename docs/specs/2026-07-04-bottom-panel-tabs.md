# Bottom panel with tabs (custom module)

- Date: 2026-07-04
- Status: approved design snapshot
- Supersedes the bottom-panel design of `2026-07-02-vscode-style-ui.md`
  (edgy docking of toggleterm and trouble; Terminal/Problems activity-bar
  buttons)

## Goal

Make the bottom panel behave like VSCode's: one panel, with **Terminal** and
**Problems** as switchable tabs in a clickable strip, and a ✕ button to close.
The activity bar loses its Terminal and Problems buttons. The panel is a
custom module (user's explicit choice over an edgy/winbar hybrid), which
makes **edgy.nvim, toggleterm.nvim, and trouble.nvim removable** — the same
simplification gitpanel made by replacing diffview.

```text
├──────────────────────────────────────────────────┤
│  Terminal   Problems (3)                       ✕ │   <- winbar tab strip
│ ▔▔▔▔▔▔▔▔▔▔                                        │      (active highlighted)
│ $ make test                                      │
│ ✓ all passing                                    │
```

## Requirements

- One panel window at the bottom of the editor area (height 12,
  `winfixheight`), spanning all editor vsplits but not the sidebar/activity
  bar (the existing `ensure_layout` reconciler keeps the columns intact).
- A one-row winbar tab strip: `Terminal`, `Problems` (with a live diagnostic
  count when > 0), and a right-aligned ✕. Clicking an inactive tab switches
  the view in place (buffer swap, no window churn); clicking the active tab
  does nothing; clicking ✕ closes the panel.
- Terminal view: a persistent shell — the buffer (and job) survive closing
  the panel and switching tabs; showing it focuses the panel and enters
  terminal mode. If the shell exits, the dead buffer is wiped and the next
  open starts a fresh shell (the panel closes if it was showing it).
- Problems view: all workspace diagnostics grouped by file — a file header
  line (devicons icon resolved at runtime, never hardcoded PUA glyphs — see
  repo memory), then one line per diagnostic: severity letter highlighted
  with the built-in `DiagnosticError/Warn/Info/Hint` groups, `lnum:col`, and
  the message. Re-renders on `DiagnosticChanged`. `<CR>` or mouse click
  jumps to the location in a main window; `q` closes the panel.
- Keybindings keep their muscle memory, gaining tab semantics:
  - `` Ctrl+` `` (n and t modes; keep the `<C-\>` fallback comment for
    terminals without the extended-keys protocol): panel hidden → open
    Terminal; showing Problems → switch to Terminal; showing Terminal →
    close.
  - `<leader>xx`: same pattern for Problems.
- Activity bar: Terminal and Problems entries removed (Explorer, Search,
  Source Control, and bottom-anchored Plugins remain).
- `:Panel {terminal|problems|close}` user command, matching `:GitPanel` /
  `:ActivityBar` convention.
- edgy.nvim, toggleterm.nvim, and trouble.nvim are removed; README's plugin
  table, activity-bar button list, panel bullet, and Layout diagram reflect
  all of it.

## Design

### New module `lua/core/panel.lua`

Follows the gitpanel structure (state table, local helpers, M.open/close/
toggle/setup).

- State: `win`, `view` ("terminal" | "problems"), lazily-created buffers per
  view, and a line→location map for the problems list.
- Window: `botright split` (full width at the bottom; activitybar's
  window-event autocmds reconcile the bar/sidebar back into full-height
  columns, exactly as they already do for edgy's `wincmd J`), height 12,
  `winfixheight`, no numbers/signs/statuscolumn, and the tab-strip winbar.
- Tab strip: built from an ordered `VIEWS` table
  (`terminal`/ft `panelterminal`, `problems`/ft `panelproblems`). Each label
  is a `%<minwid>@<handler>@ label %X` click region (minwid 1 = Terminal,
  2 = Problems, 3 = ✕ after `%=`); active tab uses `PanelTabActive`
  (default-linked to `TabLineSel`), inactive `PanelTabInactive` (→
  `TabLine`). The handler is referenced via `v:lua`; if the `%@` parser
  rejects the `require(...)` form, the module exposes one dedicated global
  for it (implementation verifies). The winbar re-renders when the view or
  the diagnostic count changes.
- Terminal buffer: created on first show by running `vim.o.shell` as a
  terminal job in the panel window (`jobstart(..., { term = true })`;
  `termopen` is deprecated), `bufhidden=hide`, unlisted, ft `panelterminal`.
  `TermClose` wipes the buffer so a dead shell is never re-shown.
- Problems buffer: scratch/nofile, ft `panelproblems`, rendered from
  `vim.diagnostic.get()` sorted by file then line; extmark highlights like
  gitpanel. Selection resolves a main window with the same exclusion-table
  pattern gitpanel uses (panel filetypes included) and jumps to
  `path:lnum:col`.
- Mouse routing: buffer-area clicks arrive through activitybar's global
  `<LeftMouse>` dispatcher (a buffer-local mapping would shadow bar clicks —
  same reasoning as gitpanel): the dispatcher gains a `panel.click(pos)`
  hook. Winbar clicks must NOT be swallowed: `panel.click` returns false for
  clicks outside the text area so the dispatcher passes them through to the
  native `%@` handlers.
- `setup()`: keymaps (`` <C-`> `` n/t → `toggle("terminal")`, `<leader>xx`
  n → `toggle("problems")`), the `:Panel` command, and the
  `DiagnosticChanged` autocmd. Called from `init.lua` after gitpanel.

### Changes to existing files

- `lua/core/activitybar.lua`: Terminal and Problems entries deleted;
  `leave_bar`'s filetype list and `ensure_layout`'s FileType autocmd pattern
  swap `toggleterm`/`trouble` for `panelterminal`/`panelproblems`; the
  `<LeftMouse>` dispatcher tries `panel.click(pos)` alongside
  `gitpanel.click(pos)`.
- `lua/core/gitpanel.lua`: `main_win()` exclude table swaps
  `toggleterm`/`trouble` for the new panel filetypes.
- `lua/core/opt.lua`: gains `vim.opt.splitkeep = "screen"` (moved from
  edgy's `init`; still wanted for stable text when panels open/close).
- `init.lua`: `require("core.panel").setup()`.
- Delete `lua/lazy-plugins/edgy.lua`, `lua/lazy-plugins/toggleterm.lua`,
  `lua/lazy-plugins/trouble.lua`; run `:Lazy clean` (lockfile is gitignored).
- `README.md`: plugin table drops the three rows; activity-bar bullet lists
  the remaining buttons; the Bottom panel bullet describes the tabs, count
  badge, ✕, and keybindings; the Layout diagram's panel block shows the tab
  strip.

## Out of scope

- Multiple terminal instances, floating terminals, and `TermExec`-style
  command dispatch (toggleterm features nobody wired into this config's UI).
- Trouble's grouped/preview/filter diagnostics UI — the Problems tab is a
  flat VSCode-style list. `VIEWS` is ordered and extensible if more tabs are
  wanted later.
- Diagnostics count badge in the activity bar (the button is gone).

## Alternatives considered

- **Winbar tabs over edgy-managed windows (keep all three plugins)** — less
  code, but two window-management systems (edgy + this config's reconciler)
  keep negotiating, and the plugins' extra features are unused here.
  Presented as the recommendation; user chose the custom module.
- **edgy pinned views** — placeholders render side-by-side in the edgebar,
  not as switchable tabs, and offer no ✕; rejected.
- **Keeping trouble as the Problems tab content** — offered explicitly;
  user declined in favor of the full custom panel.

## Verification

Headless: `nvim_eval_statusline` renders the winbar (labels, count, ✕,
highlight groups); `toggle("terminal")` produces a height-12 `panelterminal`
window with bar/sidebar columns intact (existing geometry assertions);
`toggle("problems")` swaps the buffer in the same window; seeded diagnostics
render grouped lines and the count badge; a direct `click(minwid)` call
switches tabs and ✕ closes; `<CR>` on a problem line jumps to the location;
killing the shell job wipes the terminal buffer. Interactive checklist:
real winbar mouse clicks, `` Ctrl+` `` keypress transmission, visuals.
