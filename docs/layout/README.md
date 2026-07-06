# Layout

This Neovim config uses a VSCode-style workspace layout: a fixed activity bar on
the far left, one sidebar occupant beside it, the editor in the main area, and a
bottom panel under the editor.

For the compact project overview, see [`README.md`](../../README.md#layout). This
page is the detailed layout reference for the current behavior and invariants.

```text
┌─────┬──────────────────────────────┬──────────────────────────────────────────────────────────────────┐
│     │ sidebar title                │ bufferline (buffer tabs)                                         │
│  a  ├──────────────────────────────┼──────────────────────────────────────────────────────────────────┤
│  c  │                              │ dropbar (breadcrumbs)                                            │
│  t  │                              │                                                                  │
│  i  │                              │                                                                  │
│  v  │  nvim-tree /                 │                                                                  │
│  i  │  gitpanel                    │                                                                  │
│  t  │                              │  editor                                                          │
│  y  │                              │                                                                  │
│     │                              │                                                                  │
│  b  │                              │                                                                  │
│  a  │                              │                                                                  │
│  r  │                              │                                                                  │
│     │                              │                                                                  │
│     │                              │                                                                  │
│     │                              │                                                                  │
│     │                              ├──────────────────────────────────────────────────────────────────┤
│     │                              │  Terminal   Problems                                          ✕  │
│     │                              │ ▔▔▔▔▔▔▔▔▔▔                                                       │
│     │                              │                                                                  │
│     │                              │                                                                  │
│     │                              │                                                                  │
│     │                              │                                                                  │
├─────┴──────────────────────────────┴──────────────────────────────────────────────────────────────────┤
│ lualine (statusline)                                                                                  │
└───────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Regions

| Region       | Owner                                      | Behavior                                                                                                                        |
| ------------ | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| Activity bar | `lua/core/activitybar.lua`                 | Fixed-width icon column at the far left. Opens automatically and exposes Explorer, Search, Source Control, and Plugins actions. |
| Sidebar      | `nvim-tree.lua` or `lua/core/gitpanel.lua` | One primary occupant at a time. Explorer and Source Control replace each other instead of stacking side by side.                |
| Editor tabs  | `bufferline.nvim`                          | Buffer tabs stay aligned over the editor area, with a centered sidebar title when a sidebar is open.                            |
| Breadcrumbs  | `dropbar.nvim`                             | Path and symbol breadcrumbs render in normal editor windows.                                                                    |
| Bottom panel | `lua/core/panel.lua`                       | Terminal and Problems share one bottom window with clickable tabs and a close button.                                           |
| Statusline   | `lualine.nvim`                             | Renders across the bottom of the screen.                                                                                        |

## Activity Bar

The activity bar is a custom scratch window with filetype `activitybar`. Buttons
are click targets, not text commands:

| Button         | Action                         |
| -------------- | ------------------------------ |
| Explorer       | Toggle the nvim-tree sidebar.  |
| Search         | Open Telescope live grep.      |
| Source Control | Toggle the custom Git sidebar. |
| Plugins        | Open lazy.nvim.                |

Explorer and Source Control are active-state buttons. Search and Plugins are
transient actions and do not stay highlighted.

## Sidebar

The sidebar is always the column immediately to the right of the activity bar.
It can be either:

- Explorer: the `NvimTree` file explorer.
- Source Control: the `gitpanel` sidebar.

The Source Control sidebar contains two stacked windows in one column:

- Changes: staged and unstaged files, each as foldable sub-sections.
- Commits: recent commits; selecting one opens its patch in the editor area.

The sidebar column is kept full height so the bottom panel opens only under the
editor area, not under the activity bar or sidebar.

## Bottom Panel

The bottom panel is a single window owned by `lua/core/panel.lua`.

| Tab      | Behavior                                                                                    |
| -------- | ------------------------------------------------------------------------------------------- |
| Terminal | Opens a shell buffer. Closing the panel preserves the shell session while the job is alive. |
| Problems | Lists current diagnostics grouped by file. Selecting an entry jumps to the source location. |

The panel opens at roughly 30 percent of the screen height, with a minimum of 12
rows. It uses one clickable winbar strip for tabs and close control.

## Layout Invariants

- The activity bar remains the leftmost full-height column.
- A sidebar, when present, remains one full-height column to the right of the
  activity bar.
- Stacked `gitpanel` section windows count as one sidebar frame.
- The bottom panel spans only the editor area.
- Editor-only UI, including buffer tabs and breadcrumbs, must not draw over the
  activity bar or sidebar.

These invariants are reasserted on window changes because plugins may open
windows with their own split placement rules.
