# Full-height sidebar, editor-width bottom panel

- Date: 2026-07-03
- Status: approved design snapshot
- Refines the layout of `2026-07-02-vscode-style-ui.md`, which left the
  bottom panel spanning under the sidebar

## Goal

Match VSCode's default layout: the sidebar (nvim-tree or the Source Control
panel) spans the full height between the bufferline and the statusline, and
the bottom panel (terminal, problems) spans only from the sidebar's right
edge to the screen's right edge.

```text
┌─────┬───────────────┬───────────────────────────────┐
│     │ sidebar title │ bufferline (buffer tabs)      │
│  a  ├───────────────┼───────────────────────────────┤
│  c  │               │ dropbar (breadcrumbs)         │
│  t  │  nvim-tree /  │                               │
│  i  │  gitpanel     │  editor                       │
│  v  │               │                               │
│  i  │               ├───────────────────────────────┤
│  t  │               │  bottom panel:                │
│  y  │               │  toggleterm / trouble (edgy)  │
│ bar │               │                               │
├─────┴───────────────┴───────────────────────────────┤
│ lualine (statusline)                                │
└─────────────────────────────────────────────────────┘
```

## Why it is not already like this

edgy positions its bottom windows with a hardcoded `wincmd J`
(`edgy/edgebar.lua`), which makes them full-width; whichever of
sidebar/panel opens last wins the shared corner. The activity bar already
solves this exact problem for itself: `ensure_position()` in
`lua/core/activitybar.lua` re-asserts `wincmd H` after nvim-tree opens.
Experiment confirmed the same works for the sidebar and that edgy does not
revert it in steady state — but edgy re-runs `wincmd J` when its own views
change (e.g. opening Problems while the terminal is open), so the fix must
re-assert on window lifecycle events, not just once.

## Requirements

- With a sidebar and the bottom panel both open, the sidebar is full height
  and the panel starts at the sidebar's right edge — regardless of the order
  in which they were opened or toggled.
- With no sidebar open, the panel spans everything right of the activity bar
  (current behavior).
- The activity bar stays the leftmost full-height column at width 5.
- Reconciliation is guarded: when the layout is already correct it does
  nothing, so re-triggering on frequent window events cannot cause feedback
  loops (`wincmd H` fires `WinResized`, which re-triggers the handler).
- Sidebar and panel keep their configured sizes (sidebar width 30, panel
  height 12); reconciliation preserves the sidebar's width across the move.
- The README Layout diagram and the "Bottom panel" bullet reflect the new
  arrangement.

## Design

All changes live in `lua/core/activitybar.lua`, which already owns layout
policing; no other module changes.

- `ensure_position()` generalizes to `ensure_layout()`:
  1. Precondition (as today): the bar window must be valid, otherwise only
     `render()` runs. With the bar closed (`:ActivityBar close`) the user
     has opted out of the managed layout.
  2. Find the sidebar window: first non-floating window in the current
     tabpage with filetype `NvimTree` or `gitpanel`.
  3. Correct-state check (cheap, runs first): bar at column 0 with width 5;
     if a sidebar exists, its height equals the bar's height. If correct,
     skip straight to `render()` — this is the loop guard (`wincmd` runs
     only when something is wrong).
  4. Fix: if a sidebar exists and is not full height, capture its width,
     `wincmd H` it (full-height leftmost column), restore the width. Then
     re-assert the bar exactly as today (`wincmd H` + width 5).
  5. Always finish with `render()` — the window events this handler rides
     previously triggered a bare `render()` for the active-icon highlights,
     and that behavior must survive the early return.
- Triggers:
  - The existing `FileType NvimTree` autocmd pattern gains `toggleterm` and
    `trouble` (the panel views whose opening makes edgy re-run `wincmd J`).
  - The existing multi-event autocmd (`WinEnter`, `WinClosed`, `WinResized`,
    `TermOpen`, `TermClose`) calls `ensure_layout` instead of bare
    `render()`; the guard makes this safe. This also covers the gitpanel
    reopen path, which re-uses its buffer and therefore fires no `FileType`.

## Accepted limitations

- edgy wraps its layout pass in `noautocmd`, so no event fires *after* it
  force-widens the panel; reconciliation rides the events of whatever user
  action triggered edgy. In rare sequences one stale frame may render before
  the next event lands — same class of transient as the existing
  "winfixwidth is not always honored" note in `render()`.
- Manually forcing a tracked sidebar window out of shape (e.g. `wincmd J` on
  nvim-tree) is undone by reconciliation; untracked windows and normal
  splits are unaffected.

## Alternatives considered

- **Register the sidebar as an edgy `left` view** — edgy stacks all `left`
  views vertically inside one edgebar, so the activity bar and sidebar
  cannot remain side-by-side columns; rejected.
- **Monkey-patch edgy's `wincmds.bottom`** — stops the full-width forcing at
  the source but breaks silently on plugin updates; rejected.
- **Manage the bottom panel manually instead of via edgy** — loses edgy's
  titles and size management for more code; rejected.

## Verification

Headless geometry assertions (window positions/sizes) for each order:
tree → terminal, terminal → tree, gitpanel → terminal, terminal open then
Problems toggle (edgy re-layout), sidebar closed → panel widens to the
editor area. Layout math is UI-independent, so headless checks are
sufficient here (unlike content rendering).
