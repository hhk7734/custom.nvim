# Full-Height Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the sidebar (nvim-tree / gitpanel) span full height with the bottom panel only under the editor, per `docs/specs/2026-07-03-sidebar-full-height.md`.

**Architecture:** Generalize `ensure_position()` in `lua/core/activitybar.lua` into a guarded `ensure_layout()` that re-asserts both the bar (leftmost, width 5) and the sidebar (full-height column beside it) whenever window events fire, acting only when the layout is wrong. edgy's `wincmd J` on bottom windows is the force being countered; the guard prevents `WinResized` feedback loops.

**Tech Stack:** Neovim (Lua) only; no plugin changes. Verified with headless `nvim` geometry assertions (layout math needs no attached UI, unlike content rendering — see repo memory).

**Context notes for the implementer:**
- The activity bar does NOT auto-open in headless nvim; tests must call `require('core.activitybar').open()` explicitly.
- Headless default screen is 80x24: usable column height 21; bar w5 at col 0, sidebar w30 at col 6, editor/panel at col 37 w43.
- `README.md` already carries uncommitted Layout-section work in the working tree; Task 2's commit intentionally includes it.
- Run `stylua` (at `~/.local/share/nvim/mason/bin/stylua` if not on PATH) on changed Lua files before committing.

---

### Task 1: `ensure_layout()` in activitybar.lua

**Files:**
- Modify: `lua/core/activitybar.lua:166-177` (replace `ensure_position`), `:263-269` (VimEnter), `:271-278` (FileType autocmd), `:280-286` (multi-event autocmd)

- [ ] **Step 1: Replace `ensure_position` with `sidebar_win` + `ensure_layout`**

Replace this block:

```lua
-- Re-assert the far-left position after windows that also open "topleft"
-- (e.g. nvim-tree) push the bar inward.
local function ensure_position()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
    return
  end
  vim.api.nvim_win_call(state.win, function()
    vim.cmd("wincmd H")
    vim.cmd("vertical resize " .. WIDTH)
  end)
  render()
end
```

with:

```lua
-- Sidebar occupants that must stay a full-height column beside the bar; the
-- bottom panel then only spans the editor area, as in VSCode.
local SIDEBAR_FTS = { NvimTree = true, gitpanel = true }

-- First non-floating sidebar window in the current tabpage, or nil.
local function sidebar_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if
      SIDEBAR_FTS[vim.bo[vim.api.nvim_win_get_buf(win)].filetype]
      and vim.api.nvim_win_get_config(win).relative == ""
    then
      return win
    end
  end
  return nil
end

-- Re-assert the layout: bar leftmost at WIDTH, sidebar a full-height column
-- right of it. Both are forced out of shape by windows that open "topleft"
-- (nvim-tree) or full-width at the bottom (edgy runs "wincmd J" on its panel
-- windows whenever its views change). Acts only when the layout is wrong:
-- "wincmd H" fires WinResized, which re-triggers this handler, so the guard
-- is what prevents a feedback loop.
local function ensure_layout()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
    render()
    return
  end

  local sidebar = sidebar_win()
  local bar_ok = vim.api.nvim_win_get_position(state.win)[2] == 0 and vim.api.nvim_win_get_width(state.win) == WIDTH
  local sidebar_ok = not sidebar
    or (
      vim.api.nvim_win_get_height(sidebar) == vim.api.nvim_win_get_height(state.win)
      and vim.api.nvim_win_get_position(sidebar)[2] == WIDTH + 1
    )

  if not (bar_ok and sidebar_ok) then
    if sidebar then
      -- wincmd H makes it a full-height leftmost column but drops its width.
      local width = vim.api.nvim_win_get_width(sidebar)
      vim.api.nvim_win_call(sidebar, function()
        vim.cmd("wincmd H")
      end)
      vim.api.nvim_win_set_width(sidebar, width)
    end
    vim.api.nvim_win_call(state.win, function()
      vim.cmd("wincmd H")
      vim.cmd("vertical resize " .. WIDTH)
    end)
  end

  render()
end
```

- [ ] **Step 2: Point the VimEnter autocmd at `ensure_layout`**

```lua
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = function()
      M.open()
      ensure_layout()
    end,
  })
```

- [ ] **Step 3: Extend the FileType autocmd to the panel views**

Replace:

```lua
  -- nvim-tree also opens "topleft"; keep the bar at the far left.
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "NvimTree",
    callback = function()
      vim.schedule(ensure_position)
    end,
  })
```

with:

```lua
  -- nvim-tree opens "topleft"; the panel views make edgy force its bottom
  -- windows full-width. Both disturb the managed columns.
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "NvimTree", "toggleterm", "trouble" },
    callback = function()
      vim.schedule(ensure_layout)
    end,
  })
```

- [ ] **Step 4: Route the window-event autocmd through `ensure_layout`**

Replace:

```lua
  -- Track open views for the active-icon highlight and bottom padding.
  vim.api.nvim_create_autocmd({ "WinEnter", "WinClosed", "WinResized", "TermOpen", "TermClose" }, {
    group = group,
    callback = function()
      vim.schedule(render)
    end,
  })
```

with:

```lua
  -- Track open views for the active-icon highlight and bottom padding, and
  -- heal the column layout (ensure_layout ends with render()).
  vim.api.nvim_create_autocmd({ "WinEnter", "WinClosed", "WinResized", "TermOpen", "TermClose" }, {
    group = group,
    callback = function()
      vim.schedule(ensure_layout)
    end,
  })
```

- [ ] **Step 5: Verify — sidebar first, then terminal**

Run:
```sh
nvim --headless "+lua require('core.activitybar').open() require('nvim-tree.api').tree.open() vim.cmd('ToggleTerm') vim.wait(500) local win = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do win[vim.bo[vim.api.nvim_win_get_buf(w)].filetype] = w end print('sidebar_full=' .. tostring(vim.api.nvim_win_get_height(win.NvimTree) == vim.api.nvim_win_get_height(win.activitybar)) .. ' term_col=' .. vim.api.nvim_win_get_position(win.toggleterm)[2])" +qa! 2>&1
```
Expected: `sidebar_full=true term_col=37`

- [ ] **Step 6: Verify — terminal first, then sidebar**

Run:
```sh
nvim --headless "+lua require('core.activitybar').open() vim.cmd('ToggleTerm') vim.wait(200) require('nvim-tree.api').tree.open() vim.wait(500) local win = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do win[vim.bo[vim.api.nvim_win_get_buf(w)].filetype] = w end print('sidebar_full=' .. tostring(vim.api.nvim_win_get_height(win.NvimTree) == vim.api.nvim_win_get_height(win.activitybar)) .. ' term_col=' .. vim.api.nvim_win_get_position(win.toggleterm)[2])" +qa! 2>&1
```
Expected: `sidebar_full=true term_col=37`

- [ ] **Step 7: Verify — gitpanel, then terminal**

Run:
```sh
nvim --headless "+lua require('core.activitybar').open() require('core.gitpanel').open() vim.cmd('ToggleTerm') vim.wait(500) local win = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do win[vim.bo[vim.api.nvim_win_get_buf(w)].filetype] = w end print('sidebar_full=' .. tostring(vim.api.nvim_win_get_height(win.gitpanel) == vim.api.nvim_win_get_height(win.activitybar)) .. ' term_col=' .. vim.api.nvim_win_get_position(win.toggleterm)[2])" +qa! 2>&1
```
Expected: `sidebar_full=true term_col=37`

- [ ] **Step 8: Verify — edgy re-layout (Problems while terminal open)**

Run:
```sh
nvim --headless "+lua require('core.activitybar').open() require('nvim-tree.api').tree.open() vim.cmd('ToggleTerm') vim.wait(300) vim.cmd('Trouble diagnostics toggle') vim.wait(700) local win = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do win[vim.bo[vim.api.nvim_win_get_buf(w)].filetype] = w end print('sidebar_full=' .. tostring(vim.api.nvim_win_get_height(win.NvimTree) == vim.api.nvim_win_get_height(win.activitybar)) .. ' trouble=' .. tostring(win.trouble ~= nil))" +qa! 2>&1
```
Expected: `sidebar_full=true trouble=true`

- [ ] **Step 9: Verify — closing the sidebar widens the panel**

Run:
```sh
nvim --headless "+lua require('core.activitybar').open() require('nvim-tree.api').tree.open() vim.cmd('ToggleTerm') vim.wait(400) require('nvim-tree.api').tree.close() vim.wait(400) local win = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do win[vim.bo[vim.api.nvim_win_get_buf(w)].filetype] = w end print('term_col=' .. vim.api.nvim_win_get_position(win.toggleterm)[2] .. ' term_w=' .. vim.api.nvim_win_get_width(win.toggleterm))" +qa! 2>&1
```
Expected: `term_col=6 term_w=74`

- [ ] **Step 10: Format and commit**

```sh
stylua lua/core/activitybar.lua
git add lua/core/activitybar.lua
git commit -m "feat(activitybar): keep the sidebar full height beside the bar"
```

---

### Task 2: README — Layout section reflects the new arrangement

**Files:**
- Modify: `README.md` (diagram inside the `## Layout` section; "Bottom panel" bullet). The working tree already holds the uncommitted Layout section; this task's commit includes all of it.

- [ ] **Step 1: Replace the diagram**

Replace the entire fenced diagram in `## Layout` with (27 lines, 105 columns each — generated and width-checked):

```text
┌─────┬──────────────────────────────┬──────────────────────────────────────────────────────────────────┐
│     │ sidebar title                │ bufferline (buffer tabs)                                         │
│  a  ├──────────────────────────────┼──────────────────────────────────────────────────────────────────┤
│     │                              │ dropbar (breadcrumbs)                                            │
│  c  │                              │                                                                  │
│     │                              │                                                                  │
│  t  │  nvim-tree /                 │                                                                  │
│     │  gitpanel                    │                                                                  │
│  i  │                              │  editor                                                          │
│     │                              │                                                                  │
│  v  │                              │                                                                  │
│     │                              │                                                                  │
│  i  │                              │                                                                  │
│     │                              │                                                                  │
│  t  │                              │                                                                  │
│     │                              │                                                                  │
│  y  │                              │                                                                  │
│     │                              ├──────────────────────────────────────────────────────────────────┤
│     │                              │  bottom panel:                                                   │
│ bar │                              │  toggleterm / trouble (edgy)                                     │
│     │                              │                                                                  │
│     │                              │                                                                  │
│     │                              │                                                                  │
│     │                              │                                                                  │
├─────┴──────────────────────────────┴──────────────────────────────────────────────────────────────────┤
│ lualine (statusline)                                                                                  │
└───────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

- [ ] **Step 2: Update the "Bottom panel" bullet**

Replace:

```markdown
- **Bottom panel**: edgy docks the integrated terminal (`` Ctrl+` ``) and the
  Problems list; it spans everything right of the activity bar.
```

with:

```markdown
- **Bottom panel**: edgy docks the integrated terminal (`` Ctrl+` ``) and the
  Problems list; it sits under the editor, and widens to everything right of
  the activity bar when no sidebar is open.
```

- [ ] **Step 3: Format and verify**

Run:
```sh
~/.local/share/nvim/mason/bin/deno fmt README.md
awk '/^┌/,/^└/ { print }' README.md | python3 -c "import sys
lines = sys.stdin.read().splitlines()
print('lines:', len(lines), 'widths:', {len(l) for l in lines})"
```
Expected: `lines: 27 widths: {105}`

- [ ] **Step 4: Commit**

```sh
git add README.md
git commit -m "docs: document the layout in README"
```

---

### Task 3: End-to-end verification (no commit)

- [ ] **Step 1: Startup smoke**

Run:
```sh
nvim --headless "+lua vim.wait(200) print('startup-ok')" +qa! 2>&1
```
Expected: `startup-ok` with no error lines.

- [ ] **Step 2: Toggle churn — layout stays converged**

Open/close panels repeatedly and confirm the final state is correct (also exercises the guard's no-loop property; a feedback loop would hang or thrash):

```sh
nvim --headless "+lua require('core.activitybar').open() for _ = 1, 3 do require('nvim-tree.api').tree.toggle() vim.cmd('ToggleTerm') vim.wait(200) end vim.wait(400) local win = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do win[vim.bo[vim.api.nvim_win_get_buf(w)].filetype] = w end print('tree=' .. tostring(win.NvimTree ~= nil) .. ' term=' .. tostring(win.toggleterm ~= nil) .. ' sidebar_full=' .. tostring(win.NvimTree and vim.api.nvim_win_get_height(win.NvimTree) == vim.api.nvim_win_get_height(win.activitybar)))" +qa! 2>&1
```
Expected: `tree=true term=true sidebar_full=true` (odd toggle count leaves both open).

- [ ] **Step 3: Interactive checklist (report to user)**

- Open Explorer, then `` Ctrl+` ``: tree stays full height, terminal under the editor only.
- Toggle Problems while the terminal is open: sidebar unaffected.
- Close the sidebar: panel widens; reopen: panel narrows back.
- Bufferline "File Explorer" / "Source Control" titles still aligned over the sidebar.
