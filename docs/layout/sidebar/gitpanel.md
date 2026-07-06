# GitPanel Sidebar

`gitpanel` is the custom Source Control sidebar used by the activity bar. It is
not a standalone plugin; the implementation lives in `lua/core/gitpanel.lua` and
owns two stacked windows inside the single sidebar column.

## Opening and Closing

Use any of these entry points:

- Activity bar Source Control button: toggles the sidebar.
- `:GitPanel`: toggles the sidebar.
- `:GitPanel open`, `:GitPanel close`, `:GitPanel toggle`: explicit actions.

Opening `gitpanel` closes `nvim-tree` first, so Explorer and Source Control never
occupy two sidebars at the same time. The sidebar opens immediately to the right
of the activity bar; if the activity bar is missing, it falls back to a left
vertical split.

## Sections

The sidebar is one logical frame split into two section windows:

| Section | Initial size | Content |
| --- | --- | --- |
| Changes | Remaining height | Staged files and worktree changes from `git status --porcelain -z`. |
| Commits | About one third of the sidebar height | The last 50 commits from `git log`. |

Each section has a sticky winbar header. Click the header chevron to collapse or
expand that section. A collapsed section keeps only the header row visible and
restores its previous height when expanded.

## Changes Section

The Changes section contains two foldable sub-lists when they have entries:

- `Staged`: index changes with status letters from the first porcelain column.
- `Changes`: worktree changes and untracked files.

Click a sub-list header, or press `<CR>` on it, to fold or unfold it. File rows
show the Git status letter, a runtime file icon from `nvim-web-devicons`, and the
repo-relative path.

Selecting a file opens it in the main editor area and then:

- staged file: opens a vertical gitsigns diff against `HEAD`;
- unstaged tracked file: opens a vertical gitsigns diff against the index;
- untracked file: opens the file without a diff base.

Before opening a new file diff, `gitpanel` clears the previous diff view and
closes stale `gitsigns://` revision windows.

## Commits Section

The Commits section lists commit rows as:

```text
 <short-hash> <subject>
```

Selecting a commit opens `git show <hash>` in a read-only scratch buffer named
`gitpanel://commit/<hash>` with filetype `git`. Selecting another commit replaces
the previous patch buffer in the main editor area.

## Keyboard and Mouse

When focus is inside either section:

| Key | Action |
| --- | --- |
| `<CR>` | Activate the current row. |
| `R` | Refresh both sections. |
| `q` | Close the sidebar. |

Mouse clicks are routed through the activity bar's global click dispatcher so
clicks outside the panel continue to reach the rest of the UI. Blank rows focus
the section for keyboard navigation.

## Refresh Behavior

`gitpanel` refreshes on:

- `BufWritePost`;
- `FocusGained`;
- `User GitSignsUpdate`;
- explicit `R` in either section.

The repository root is resolved with `git rev-parse --show-toplevel` on render,
not by trusting the current working directory. This matters because `autochdir`
is enabled and the current directory can follow the last-entered buffer.

## Layout Invariants

- The Changes and Commits windows together count as one sidebar occupant.
- Both windows use fixed width and no status/sign/fold columns.
- The sidebar column remains full height so the bottom panel opens only under the
  editor area.
- Selecting files or commits uses an existing main editor window when possible;
  it avoids reusing activity bar, `gitpanel`, `NvimTree`, or bottom-panel
  windows.
