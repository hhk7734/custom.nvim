# Source Control sidebar: Changes and Commits sections

- Date: 2026-07-04
- Status: approved design snapshot
- Extends `2026-07-03-git-sidebar-panel.md` (single-window panel) and the
  sidebar-frame handling of `2026-07-03-sidebar-full-height.md` (single-leaf
  sidebar assumption)

## Goal

Split the Source Control sidebar into two VSCode-style sections — **Changes**
and **Commits** — each foldable (collapse to its header) and resizable (drag
the separator between them). Inside the Changes section, **Staged** and
**Changes** become foldable sub-sections. Selecting a commit opens its full
patch in the editor area.

```text
│ ▾ Changes               │  <- winbar header, click to fold
│  ▾ Staged               │  <- sub-header, click/<CR> to fold
│   M lua/core/panel.lua  │
│  ▾ Changes              │
│   M README.md           │
│─────────────────────────│  <- draggable separator (statusline)
│ ▾ Commits               │
│  2cce5ec docs: ...      │
│  b3f3cca feat: ...      │
```

## Requirements

- The Source Control button/`:GitPanel` opens a sidebar of two stacked
  windows in one column beside the activity bar (width 30 as today):
  Changes on top, Commits below (Commits starts at ⅓ of the column height).
- Both section buffers keep filetype `gitpanel`, so bufferline offsets,
  `leave_bar`, and `main_win` exclusion tables keep working unchanged.
- Section headers are sticky winbars (`▾ <title>` expanded, `▸ <title>`
  collapsed). Clicking a header toggles collapse: collapsed = height 1 with
  `winfixheight` (the other section absorbs the space); expanding restores
  the height from before collapsing.
- Dragging the separator between the sections resizes them (per-window
  statuslines already exist; no new mechanism).
- Changes section: today's content and behavior (status letters, devicons,
  gitsigns diff on select), with `Staged`/`Changes` as foldable sub-headers
  (`▾`/`▸` prefix); click or `<CR>` on a sub-header toggles its list.
- Commits section: the repo's last 50 commits as `<short-hash> <subject>`
  lines, hash highlighted. Click/`<CR>` opens `git show <hash>` as a
  read-only scratch buffer (filetype `git`, name `gitpanel://commit/<hash>`)
  in a main editor window; opening another commit replaces the previous
  patch buffer.
- Refresh (`BufWritePost`, `FocusGained`, `GitSignsUpdate` autocmds and `R`)
  re-renders both sections; `q` in either section closes the whole sidebar;
  fold/collapse state survives refreshes while the panel stays open.
- The activity-bar layout reconciler treats a stack of sidebar windows as
  one sidebar frame: correct state accepts a top-level `col` frame whose
  leaves are all sidebar windows (single leaf remains valid for nvim-tree),
  and repair rebuilds the stack instead of tearing it apart.
- README's Source Control bullet documents the sections.

## Design

### `lua/core/gitpanel.lua` restructure

- `SECTIONS` ordered list: `changes`, `commits`. Per-section state: `win`,
  `buf`, `collapsed`, `saved_height`, and the line→entry map. Shared state:
  repo root, sub-section fold flags (`staged`, `changes`).
- `M.open()`: close nvim-tree (as today); create the Changes window via
  `nvim_open_win { win = <bar>, split = "right", width = 30 }` (fallback
  `topleft 30vsplit`), then the Commits window via
  `nvim_open_win { win = <changes win>, split = "below" }`; set Commits
  height to ⅓ of the Changes window's height after the split. Window options
  as today plus a `winbar` per section.
- Winbar: `%#GitPanelHeader#%<idx>@v:lua.GitPanelSectionClick@ ▾ <title> %X`
  — one module-owned global (same pattern and reasoning as `PanelTabClick`);
  `GitPanelHeader` links to `Title` (`default = true`). minwid = section
  index. The handler toggles collapse; winbar clicks reach the native `%@`
  regions because `M.click` returns false for `winrow == 1`.
- Collapse: save `nvim_win_get_height`, set height 1 + `winfixheight = true`;
  expand: `winfixheight = false`, restore saved height. Winbar re-rendered
  with `▸`/`▾` on every toggle.
- Changes rendering: as today, with header entries becoming
  `{ header = "staged" | "changes" }`; when a sub-section is folded its file
  lines are skipped and the header renders `▸ <name>`. `<CR>`/click on a
  header entry toggles the flag and re-renders (replacing today's
  "header rows only focus the panel" behavior).
- Commits rendering: `git -C <root> log --format=%h%x09%s -n 50` via
  `vim.system` (NUL/tab-safe, same rationale as `git_status`); lines
  `<hash> <subject>`, extmark on the hash linking `Identifier`. Entry map
  lnum → `{ hash }`.
- Commit selection: wipe any previous `gitpanel://commit/*` buffer and any
  gitsigns diff (reuse `close_diffs`), pick `main_win()` (or `botright
  vsplit` as today), create a scratch buffer named
  `gitpanel://commit/<hash>` filled with `git show <hash>` output,
  `filetype = git`, readonly/nomodifiable, `bufhidden = wipe`.
- `M.click(pos)`: matches either section window; `winrow == 1` → false
  (winbar pass-through); Changes window → existing select/toggle logic;
  Commits window → open the commit. `M.close()` closes both windows (E444
  guard once, closing valid ones).
- Keymaps (`<CR>`, `q`, `R`) set on both buffers.

### `lua/core/activitybar.lua` — frame-aware reconciler

- `sidebar_wins()` replaces `sidebar_win()`: all non-floating windows with a
  sidebar filetype in the current tabpage, ordered by screen row.
- Guard: in `vim.fn.winlayout()` (root must be `row`), the frame at the
  sidebar position must be either a leaf that is a sidebar window, or a
  `col` whose leaves are exactly sidebar windows; its window(s) sit at
  column `WIDTH + 1`.
- Repair: `wincmd H` the first sidebar window and restore its width; for
  each subsequent sidebar window run
  `vim.fn.win_splitmove(win, prev, { vertical = false, rightbelow = true })`;
  then re-assert the bar as today. Heights are left to the section module
  (collapse state re-asserts via `winfixheight`).

### Unchanged

- bufferline (`sidebar_win` finds the first `gitpanel` window; width-based
  padding is per-column, not per-window), `leave_bar`, `main_win` excludes,
  the Source Control button behavior, `SIDEBAR_FTS` content.

### `README.md`

- Source Control bullet: mentions the foldable/resizable Changes and
  Commits sections and that selecting a commit opens its patch.

## Out of scope

- Staging/unstaging from the panel (unchanged from the original gitpanel
  spec), commit-graph drawing, pagination beyond 50 commits, and per-file
  lists under each commit.
- Persisting fold/collapse state across panel close/reopen or nvim restarts.

## Alternatives considered

- **Single window with vim folds** — foldable but not resizable per
  section; fails a stated requirement.
- **edgy left edgebar for sections** — edgy was just removed; reintroducing
  a second window manager for two windows is not worth it.
- **3 top-level sections (Staged/Changes/Commits)** — offered; user chose
  Staged and Changes as foldable sub-sections inside Changes.

## Verification

Headless: two stacked `gitpanel` windows (order, widths, Commits ≈ ⅓
height); winbar headers render via `nvim_eval_statusline`;
`GitPanelSectionClick` collapse/expand round-trip restores heights;
sub-section fold hides/reveals file lines; commits render from this repo's
history; selecting a commit opens a `git`-filetype `gitpanel://commit/*`
buffer in a main window; reconciler matrix re-run (bottom panel squash with
the stacked sidebar, Explorer swap, close/reopen); startup smoke.
Interactive: separator drag, real winbar/header clicks, contrast of the new
header/hash highlights on GitHub Dark.
