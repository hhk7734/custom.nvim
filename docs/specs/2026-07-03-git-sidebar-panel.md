# Git sidebar panel (Source Control view)

- Date: 2026-07-03
- Status: approved design snapshot
- Supersedes the Source Control behavior of
  `2026-07-02-vscode-style-ui.md` (git button opened Diffview)

## Goal

Make the activity bar's git button behave like VSCode's Source Control view:
the sidebar swaps to a list of git changes, and selecting a changed file shows
its diff in the editor area. diffview.nvim is removed entirely (not the user's
style); gitsigns provides the diffs.

## Requirements

- The git button toggles a "Source Control" sidebar panel; opening it closes
  nvim-tree and vice versa (the explorer button closes the panel) — one
  sidebar occupant at a time, as in VSCode.
- The panel lists working-tree changes from `git status` in two sections:
  **Staged** and **Changes** (untracked files included under Changes).
- Selecting a file (mouse click or `<CR>`) opens it in a main editor window
  with a side-by-side diff: against the index for Changes, against `HEAD` for
  Staged; untracked files simply open. Selecting another file replaces the
  previous diff instead of stacking splits.
- Opening the panel from the git button focuses the panel (single-click file
  selection works immediately).
- The panel refreshes on file writes, focus gain, and gitsigns updates; `R`
  refreshes manually; `q` closes the panel.
- The active-icon highlight and bufferline tab alignment work exactly as they
  do for the tree (title over the sidebar reads "Source Control").
- diffview.nvim and its `<leader>g*` keymaps are removed.

## Design

### New module `lua/core/gitpanel.lua`

- Scratch-buffer sidebar, filetype `gitpanel`, width 30, `winfixwidth`,
  no numbers/signs/statuscolumn (same window styling as the activity bar).
- Opened to the right of the activity bar via
  `nvim_open_win(buf, enter, { win = <bar win>, split = "right", vertical … })`
  so there is no `topleft` ordering fight; falls back to `topleft 30vsplit`
  when the bar is closed. Closes any visible nvim-tree window first.
- Content: `git rev-parse --show-toplevel` resolves the repo root (paths are
  edited as absolute paths — `autochdir` is enabled in this config, so
  relative paths are unreliable), then `git status --porcelain` is parsed
  into Staged (index status `M A D R C T`) and Changes (worktree status not
  a space, plus `??`). Each file line renders: status letter, a
  nvim-web-devicons icon resolved at runtime (never hardcode nerd-font PUA
  glyphs in source — see repo memory), and the repo-relative path.
- Highlights: section headers link `Title`; status letters link the built-in
  `Added` / `Changed` / `Removed` groups; extmark-based like the activity bar.
- Selection (`<CR>` and buffer-local `<LeftMouse>`; the panel has focus after
  opening via the button, so a single click selects):
  1. wipe previous diff state: `diffoff!` plus closing any window whose
     buffer name starts with `gitsigns://`;
  2. pick a main window — first window whose filetype is not one of
     `activitybar, gitpanel, NvimTree, toggleterm, trouble` — or create one
     with `botright vsplit`;
  3. `edit` the absolute path;
  4. Changes section → `require("gitsigns").diffthis(nil, { vertical = true })`;
     Staged section → `diffthis("HEAD", { vertical = true })`; untracked →
     no diff, just the file.
- Refresh: `BufWritePost`, `FocusGained`, `User GitSignsUpdate` autocmds plus
  after every selection; `R` in the panel re-runs git status.
- `:GitPanel {open|close|toggle}` user command (default toggle);
  `require("core.gitpanel").setup()` is called from `init.lua` after the
  activity bar.

### Changes to existing files

- `lua/core/activitybar.lua`: the Source Control entry's action becomes
  `require("core.gitpanel").toggle()` with `is_active` checking a `gitpanel`
  window; the Explorer entry closes the panel before toggling the tree;
  `leave_bar`'s panel list gains `gitpanel`.
- `lua/lazy-plugins/bufferline.lua`: `tree_padding` generalizes to
  `sidebar_padding` matching a `NvimTree` **or** `gitpanel` window; the
  activitybar offset title becomes "File Explorer" / "Source Control"
  depending on the occupant; a `gitpanel` fallback offsets entry (matching
  only when the bar is closed) joins the existing `NvimTree` one.
- `init.lua`: `require("core.gitpanel").setup()`.
- Delete `lua/lazy-plugins/diffview.lua`; README drops the diffview row and
  documents the panel.

## Out of scope

- Staging/unstaging and commit UI from the panel.
- File/branch history (was diffview's `<leader>gh/gH`; gitsigns blame and
  hunk navigation remain).
- `:q` quit accounting for the panel window (same class as other extra
  splits).

## Alternatives considered

- **Keep Diffview as the git view** — rejected by the user ("not my style");
  removed instead.
- **neo-tree git_status source** — lists files in a sidebar but opens files
  rather than diffs, and adds a second tree plugin; rejected.
- **sidebar.nvim git section** — effectively unmaintained; rejected.
