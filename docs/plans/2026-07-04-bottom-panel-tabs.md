# Bottom Panel Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the edgy/toggleterm/trouble bottom panel with a custom `lua/core/panel.lua` — one window, Terminal/Problems tabs in a clickable winbar strip with a ✕ — and drop the Terminal/Problems activity-bar buttons, per `docs/specs/2026-07-04-bottom-panel-tabs.md`.

**Architecture:** The module owns a `botright` split (the activitybar reconciler pulls the bar/sidebar columns back, same as it did against edgy's `wincmd J`). Tabs are buffer swaps in that window: a persistent `:terminal` buffer (ft `panelterminal`) and a scratch diagnostics list (ft `panelproblems`). The winbar is a static string re-rendered on view/diagnostic changes; its click regions dispatch to one dedicated global (`_G.PanelTabClick` — statusline `%@…@` needs a `v:lua`-reachable function name).

**Tech Stack:** Neovim (Lua) only. edgy.nvim, toggleterm.nvim, trouble.nvim get removed.

**Context notes for the implementer:**
- Headless: the activity bar does not auto-open; open panels explicitly. Layout geometry is verifiable headless; real mouse clicks are not (call `PanelTabClick` directly).
- 80x24 headless screen: bar w5 col0, sidebar w30 col6, editor/panel col37 w43, full column height 21.
- Repo rules: no hardcoded nerd-font PUA glyphs (devicons at runtime); stylua on changed Lua files (`~/.local/share/nvim/mason/bin/stylua`); single-scope Conventional Commits.
- Mid-sequence state is fine: Task 1's `<C-`>`/`<leader>xx` maps overwrite the toggleterm/trouble lazy stubs (panel.setup runs after lazy in init.lua); edgy ignores the new panel filetypes, so nothing fights until the plugins are removed in Task 3.

---

### Task 1: `lua/core/panel.lua` + wiring in init.lua / opt.lua

**Files:**
- Create: `lua/core/panel.lua`
- Modify: `init.lua:17` (add setup call), `lua/core/opt.lua` (append splitkeep)

- [ ] **Step 1: Write `lua/core/panel.lua`**

```lua
-- VSCode-style bottom panel: one window with Terminal and Problems as tabs
-- in a clickable winbar strip. Tabs swap buffers in place; the terminal
-- buffer (and its shell) survives closing the panel. Mirrors the gitpanel
-- module structure (state table, local helpers, M.open/close/toggle/setup).
local M = {}

local HEIGHT = 12
local ns = vim.api.nvim_create_namespace("panel")

-- Ordered tab list; minwid in the winbar click regions is the index here
-- (3 = the ✕ button).
local VIEWS = {
  { key = "terminal", label = "Terminal", ft = "panelterminal" },
  { key = "problems", label = "Problems", ft = "panelproblems" },
}

local state = {
  win = nil,
  -- key of the visible (or last visible) view; open() reuses it
  view = nil,
  -- view key -> bufnr, created lazily and kept alive across close/switch
  bufs = {},
  -- problems buffer line number -> { bufnr, lnum, col }, rebuilt on render
  lines = {},
}

local SEVERITY = {
  [vim.diagnostic.severity.ERROR] = { "E", "DiagnosticError" },
  [vim.diagnostic.severity.WARN] = { "W", "DiagnosticWarn" },
  [vim.diagnostic.severity.INFO] = { "I", "DiagnosticInfo" },
  [vim.diagnostic.severity.HINT] = { "H", "DiagnosticHint" },
}

local function win_valid()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

-- File icons come from nvim-web-devicons at runtime; never hardcode
-- nerd-font/PUA glyphs in source (see repo memory).
local function file_icon(path)
  local ok, icon = pcall(function()
    local devicons = require("nvim-web-devicons")
    return devicons.get_icon(vim.fn.fnamemodify(path, ":t"), vim.fn.fnamemodify(path, ":e"), { default = true })
  end)
  return (ok and icon) or ""
end

-- Winbar tab strip. Static string, re-rendered on view/diagnostic changes.
-- %<minwid>@<func>@ regions need a v:lua-reachable function name, hence the
-- single dedicated global PanelTabClick (defined below).
local function winbar()
  local count = #vim.diagnostic.get()
  local parts = {}
  for i, v in ipairs(VIEWS) do
    local label = v.label
    if v.key == "problems" and count > 0 then
      label = label .. " (" .. count .. ")"
    end
    local hl = (state.view == v.key) and "PanelTabActive" or "PanelTabInactive"
    parts[#parts + 1] = "%#" .. hl .. "#%" .. i .. "@v:lua.PanelTabClick@ " .. label .. " %X"
  end
  return table.concat(parts) .. "%#PanelTabFill#%=%3@v:lua.PanelTabClick@ ✕ %X"
end

local function refresh_winbar()
  if win_valid() then
    vim.wo[state.win].winbar = winbar()
  end
end

-- First window that isn't a sidebar/panel occupant; nil if none exist.
local function main_win()
  local exclude =
    { activitybar = true, gitpanel = true, NvimTree = true, panelterminal = true, panelproblems = true }
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not exclude[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] then
      return win
    end
  end
  return nil
end

local function select_entry(entry)
  if not entry then
    return
  end
  local win = main_win()
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("aboveleft split")
  end
  vim.api.nvim_set_current_buf(entry.bufnr)
  vim.api.nvim_win_set_cursor(0, { entry.lnum, entry.col })
end

local function render_problems()
  local buf = state.bufs.problems
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end

  -- Group by file: stable order by name, then by line within a file.
  local by_file = {}
  for _, d in ipairs(vim.diagnostic.get()) do
    local name = vim.api.nvim_buf_get_name(d.bufnr)
    by_file[name] = by_file[name] or { bufnr = d.bufnr, items = {} }
    table.insert(by_file[name].items, d)
  end
  local names = vim.tbl_keys(by_file)
  table.sort(names)

  local lines, entries, marks = {}, {}, {}
  for _, name in ipairs(names) do
    local group = by_file[name]
    table.sort(group.items, function(a, b)
      return a.lnum < b.lnum
    end)
    table.insert(lines, string.format("%s %s", file_icon(name), vim.fn.fnamemodify(name, ":~:.")))
    marks[#lines] = { col = 0, end_col = #lines[#lines], hl = "Title" }
    for _, d in ipairs(group.items) do
      local sev = SEVERITY[d.severity] or { "?", "Comment" }
      local msg = (d.message or ""):gsub("%s*\n.*", "")
      table.insert(lines, string.format("  %s %d:%d %s", sev[1], d.lnum + 1, d.col + 1, msg))
      -- The severity letter sits right after the 2-space indent.
      marks[#lines] = { col = 2, end_col = 3, hl = sev[2] }
      entries[#lines] = { bufnr = d.bufnr, lnum = d.lnum + 1, col = d.col }
    end
  end
  if #lines == 0 then
    lines = { "No problems detected" }
  end
  state.lines = entries

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for lnum, m in pairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, m.col, { end_col = m.end_col, hl_group = m.hl })
  end
end

local function ensure_problems_buf()
  local buf = state.bufs.problems
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "panelproblems"
  vim.bo[buf].modifiable = false
  state.bufs.problems = buf
  vim.keymap.set("n", "<CR>", function()
    select_entry(state.lines[vim.api.nvim_win_get_cursor(0)[1]])
  end, { buffer = buf, desc = "panel: jump to problem" })
  vim.keymap.set("n", "q", function()
    M.close()
  end, { buffer = buf, desc = "panel: close" })
  return buf
end

local function ensure_terminal_buf()
  local buf = state.bufs.terminal
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  buf = vim.api.nvim_create_buf(false, true)
  state.bufs.terminal = buf
  return buf
end

-- Start the shell job for a fresh terminal buffer. Must run with the buffer
-- current in the panel window (jobstart {term=true} attaches to it).
local function start_shell(buf)
  vim.api.nvim_win_call(state.win, function()
    vim.fn.jobstart({ vim.o.shell }, { term = true })
  end)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "panelterminal"
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = buf,
    once = true,
    callback = function()
      -- A dead shell must never be re-shown: close the panel if it is
      -- visible there, then wipe the buffer (scheduled — the buffer cannot
      -- be deleted while the autocmd still runs in it).
      vim.schedule(function()
        if win_valid() and vim.api.nvim_win_get_buf(state.win) == buf then
          M.close()
        end
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        if state.bufs.terminal == buf then
          state.bufs.terminal = nil
        end
      end)
    end,
  })
end

function M.show(key)
  if not win_valid() then
    return M.open(key)
  end
  local buf = key == "terminal" and ensure_terminal_buf() or ensure_problems_buf()
  vim.api.nvim_set_current_win(state.win)
  vim.api.nvim_win_set_buf(state.win, buf)
  state.view = key
  if key == "terminal" then
    if vim.bo[buf].buftype ~= "terminal" then
      start_shell(buf)
    end
    vim.cmd.startinsert()
  else
    render_problems()
  end
  refresh_winbar()
end

function M.open(key)
  key = key or state.view or "terminal"
  if win_valid() then
    return M.show(key)
  end
  -- Full-width bottom split; the activity bar's ensure_layout autocmds pull
  -- the bar/sidebar back into full-height columns, leaving the panel under
  -- the editor area only (same dance it did with edgy's "wincmd J").
  vim.cmd("botright " .. HEIGHT .. "split")
  state.win = vim.api.nvim_get_current_win()

  local wo = vim.wo[state.win]
  wo.winfixheight = true
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.statuscolumn = ""
  wo.wrap = false
  wo.fillchars = "eob: "

  M.show(key)
end

function M.close()
  if not win_valid() then
    state.win = nil
    return
  end
  -- Closing the last window of a tabpage is an error (E444); keep the panel.
  local tab = vim.api.nvim_win_get_tabpage(state.win)
  if #vim.api.nvim_tabpage_list_wins(tab) == 1 then
    return
  end
  vim.api.nvim_win_close(state.win, true)
  state.win = nil
end

function M.toggle(key)
  if win_valid() then
    if state.view == key then
      M.close()
    else
      M.show(key)
    end
  else
    M.open(key)
  end
end

-- Buffer-area clicks arrive via activitybar's global <LeftMouse> dispatcher
-- (a buffer-local mapping would shadow bar clicks). Returns true when the
-- click was handled. Winbar clicks (winrow 1 while a winbar is set) must
-- fall through so the native %@ regions receive them.
function M.click(pos)
  if not win_valid() or pos.winid ~= state.win or state.view ~= "problems" then
    return false
  end
  if pos.winrow == 1 then
    return false
  end
  local entry = state.lines[pos.line]
  if not entry then
    return false
  end
  vim.schedule(function()
    select_entry(entry)
  end)
  return true
end

-- Winbar %@ click handler; must be a v:lua-reachable global.
-- minwid: VIEWS index, or 3 for the ✕ button.
_G.PanelTabClick = function(minwid, _, button)
  if button ~= "l" then
    return
  end
  if minwid == 3 then
    M.close()
    return
  end
  local view = VIEWS[minwid]
  if view and state.view ~= view.key then
    M.show(view.key)
  end
end

function M.setup()
  vim.api.nvim_set_hl(0, "PanelTabActive", { link = "TabLineSel", default = true })
  vim.api.nvim_set_hl(0, "PanelTabInactive", { link = "TabLine", default = true })
  vim.api.nvim_set_hl(0, "PanelTabFill", { link = "TabLineFill", default = true })

  -- Note: some terminal emulators do not transmit Ctrl+` (it needs the
  -- extended-keys protocol). If nothing happens on keypress, replace
  -- "<C-`>" with "<C-\>" here — everything else stays the same.
  vim.keymap.set({ "n", "t" }, "<C-`>", function()
    M.toggle("terminal")
  end, { desc = "toggle terminal tab" })
  vim.keymap.set("n", "<leader>xx", function()
    M.toggle("problems")
  end, { desc = "toggle problems tab" })

  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = vim.api.nvim_create_augroup("panel", {}),
    callback = function()
      if win_valid() then
        refresh_winbar()
        if state.view == "problems" then
          render_problems()
        end
      end
    end,
  })

  vim.api.nvim_create_user_command("Panel", function(cmd)
    local arg = cmd.args ~= "" and cmd.args or "terminal"
    if arg == "close" then
      M.close()
    else
      M.toggle(arg)
    end
  end, {
    nargs = "?",
    complete = function()
      return { "terminal", "problems", "close" }
    end,
  })
end

return M
```

- [ ] **Step 2: Wire setup in `init.lua`**

```lua
require("core.activitybar").setup()
require("core.gitpanel").setup()
require("core.panel").setup()
```

- [ ] **Step 3: Move splitkeep into `lua/core/opt.lua`**

Read the file first, then append (with edgy gone in Task 3, this must not be
lost):

```lua
-- Keep text stable when panels open/close at the bottom.
vim.opt.splitkeep = "screen"
```

- [ ] **Step 4: Verify — open, tab switch, close, persistence**

Run:
```sh
nvim --headless "+lua local p = require('core.panel') p.toggle('terminal') vim.wait(300) local win = vim.api.nvim_get_current_win() local buf = vim.api.nvim_win_get_buf(win) print('ft=' .. vim.bo[buf].filetype .. ' buftype=' .. vim.bo[buf].buftype .. ' h=' .. vim.api.nvim_win_get_height(win)) p.toggle('problems') local buf2 = vim.api.nvim_win_get_buf(win) print('ft2=' .. vim.bo[buf2].filetype .. ' same_win=' .. tostring(vim.api.nvim_get_current_win() == win)) p.toggle('problems') print('closed=' .. tostring(not vim.api.nvim_win_is_valid(win))) p.toggle('terminal') vim.wait(100) print('same_term_buf=' .. tostring(vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win()) == buf))" +qa! 2>&1
```
Expected: `ft=panelterminal buftype=terminal h=12`, `ft2=panelproblems same_win=true`, `closed=true`, `same_term_buf=true`.

- [ ] **Step 5: Verify — winbar content and click handler**

Run:
```sh
nvim --headless "+lua local p = require('core.panel') p.toggle('problems') local wb = vim.wo[vim.api.nvim_get_current_win()].winbar local s = vim.api.nvim_eval_statusline(wb, { winid = vim.api.nvim_get_current_win(), use_winbar = true }).str print('labels=' .. tostring(s:find('Terminal') ~= nil and s:find('Problems') ~= nil and s:find('✕') ~= nil)) PanelTabClick(1, 1, 'l') vim.wait(200) print('switched=' .. vim.bo[vim.api.nvim_win_get_buf(0)].filetype)" +qa! 2>&1
```
Expected: `labels=true`, `switched=panelterminal` (the ✕ close is verified in Step 6).

- [ ] **Step 6: Verify — diagnostics render, count badge, jump, ✕**

Run:
```sh
nvim --headless "+edit lua/core/panel.lua" "+lua vim.diagnostic.set(vim.api.nvim_create_namespace('t'), 0, { { lnum = 4, col = 2, message = 'seeded problem', severity = vim.diagnostic.severity.ERROR } }) local p = require('core.panel') p.toggle('problems') local win = vim.api.nvim_get_current_win() local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false) print('rendered=' .. tostring(#vim.tbl_filter(function(l) return l:find('seeded problem', 1, true) end, lines) == 1)) local wb = vim.api.nvim_eval_statusline(vim.wo[win].winbar, { winid = win, use_winbar = true }).str print('badge=' .. tostring(wb:find('Problems (1)', 1, true) ~= nil)) vim.api.nvim_win_set_cursor(win, { 2, 0 }) vim.fn.maparg('<CR>', 'n', false, true).callback() print('jumped=' .. vim.fn.expand('%:t') .. ':' .. vim.api.nvim_win_get_cursor(0)[1]) PanelTabClick(3, 1, 'l') local open = false for _, w in ipairs(vim.api.nvim_list_wins()) do if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'panelproblems' then open = true end end print('x_closed=' .. tostring(not open))" +qa! 2>&1
```
Expected: `rendered=true`, `badge=true`, `jumped=panel.lua:5`, `x_closed=true`.

- [ ] **Step 7: Verify — dead shell is wiped**

Run:
```sh
nvim --headless "+lua local p = require('core.panel') p.toggle('terminal') vim.wait(300) local buf = vim.api.nvim_win_get_buf(0) vim.fn.jobstop(vim.bo[buf].channel) vim.wait(500) print('wiped=' .. tostring(not vim.api.nvim_buf_is_valid(buf)))" +qa! 2>&1
```
Expected: `wiped=true` (the panel window may close with it; no errors).

- [ ] **Step 8: Format and commit**

```sh
stylua lua/core/panel.lua lua/core/opt.lua
git add lua/core/panel.lua lua/core/opt.lua init.lua
git commit -m "feat(panel): add bottom panel with terminal and problems tabs"
```

---

### Task 2: Activity bar — drop the two buttons, route panel clicks

**Files:**
- Modify: `lua/core/activitybar.lua` (entries table; `<LeftMouse>` dispatcher; `leave_bar`; `ensure_layout` FileType pattern)

- [ ] **Step 1: Delete the Terminal and Problems entries**

Remove both table entries from `entries` (the ones whose actions run
`ToggleTerm` and `Trouble diagnostics toggle`). Remaining: Explorer, Search,
Source Control, Plugins.

- [ ] **Step 2: Dispatcher tries the panel after gitpanel**

```lua
  if pos.winid ~= state.win then
    local gitpanel = package.loaded["core.gitpanel"]
    if gitpanel and gitpanel.click(pos) then
      return ""
    end
    local panel = package.loaded["core.panel"]
    if panel and panel.click(pos) then
      return ""
    end
    return "<LeftMouse>"
  end
```

- [ ] **Step 3: Swap panel filetypes in `leave_bar`**

```lua
      if
        ft ~= "NvimTree"
        and ft ~= "gitpanel"
        and ft ~= "panelterminal"
        and ft ~= "panelproblems"
      then
```

- [ ] **Step 4: Swap the FileType pattern in setup**

```lua
  -- nvim-tree opens "topleft" and the bottom panel opens "botright" full
  -- width; both disturb the managed columns.
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "NvimTree", "panelterminal", "panelproblems" },
    callback = function()
      vim.schedule(ensure_layout)
    end,
  })
```

- [ ] **Step 5: Verify — layout still reconciles around the new panel**

Run:
```sh
nvim --headless "+lua require('core.activitybar').open() require('nvim-tree.api').tree.open() require('core.panel').toggle('terminal') vim.wait(500) local win = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do win[vim.bo[vim.api.nvim_win_get_buf(w)].filetype] = w end print('sidebar_full=' .. tostring(vim.api.nvim_win_get_height(win.NvimTree) == vim.api.nvim_win_get_height(win.activitybar)) .. ' panel_col=' .. vim.api.nvim_win_get_position(win.panelterminal)[2])" +qa! 2>&1
```
Expected: `sidebar_full=true panel_col=37`.

- [ ] **Step 6: Format and commit**

```sh
stylua lua/core/activitybar.lua
git add lua/core/activitybar.lua
git commit -m "feat(activitybar): drop terminal and problems buttons for panel tabs"
```

---

### Task 3: gitpanel filetype swap + plugin removal

**Files:**
- Modify: `lua/core/gitpanel.lua:195` (main_win exclude)
- Delete: `lua/lazy-plugins/edgy.lua`, `lua/lazy-plugins/toggleterm.lua`, `lua/lazy-plugins/trouble.lua`

- [ ] **Step 1: Swap the exclude filetypes in `main_win`**

```lua
  local exclude =
    { activitybar = true, gitpanel = true, NvimTree = true, panelterminal = true, panelproblems = true }
```

- [ ] **Step 2: Delete the three plugin specs and clean installs**

```sh
git rm lua/lazy-plugins/edgy.lua lua/lazy-plugins/toggleterm.lua lua/lazy-plugins/trouble.lua
nvim --headless "+Lazy! clean" +qa
```

- [ ] **Step 3: Verify — startup clean, no stale commands**

Run:
```sh
nvim --headless "+lua vim.wait(300) print('startup-ok') print('toggleterm_gone=' .. tostring(vim.fn.exists(':ToggleTerm') == 0) .. ' trouble_gone=' .. tostring(vim.fn.exists(':Trouble') == 0) .. ' panel=' .. tostring(vim.fn.exists(':Panel') == 2))" +qa! 2>&1
```
Expected: `startup-ok`, `toggleterm_gone=true trouble_gone=true panel=true`, no error lines.

- [ ] **Step 4: Format and commit**

```sh
stylua lua/core/gitpanel.lua
git add lua/core/gitpanel.lua lua/lazy-plugins
git commit -m "refactor(plugins): remove edgy, toggleterm, trouble for core panel"
```

---

### Task 4: README

**Files:**
- Modify: `README.md` (plugin table, activity-bar bullet, bottom-panel bullet, Layout diagram)

- [ ] **Step 1: Remove the three plugin rows**

Delete the `edgy.nvim`, `toggleterm.nvim`, and `trouble.nvim` rows from the
plugin table.

- [ ] **Step 2: Update the activity-bar and bottom-panel bullets**

```markdown
- **Activity bar** (`lua/core/activitybar.lua`, `:ActivityBar toggle`): icon
  column at the far left. Buttons: Explorer (nvim-tree), Search (telescope
  live grep), Source Control (gitpanel), and Plugins (Lazy) at the bottom.
```

```markdown
- **Bottom panel** (`lua/core/panel.lua`, `:Panel`): Terminal and Problems as
  tabs in a clickable strip with a ✕ close button; `` Ctrl+` `` toggles the
  Terminal tab and `<leader>xx` the Problems tab. The shell session survives
  closing the panel. It sits under the editor, and widens to everything right
  of the activity bar when no sidebar is open.
```

- [ ] **Step 3: Update the diagram's panel block**

Replace the two panel text rows (`  bottom panel:` and
`  toggleterm / trouble (edgy)`) with the tab strip (the underline row marks
the active tab; each row stays 105 columns — re-verify):

```text
│     │                              │  Terminal   Problems                                          ✕  │
│ bar │                              │ ▔▔▔▔▔▔▔▔▔▔                                                       │
```

- [ ] **Step 4: Format, verify, commit**

```sh
~/.local/share/nvim/mason/bin/deno fmt README.md
awk '/^┌/,/^└/ { print }' README.md | python3 -c "import sys
lines = sys.stdin.read().splitlines()
print('lines:', len(lines), 'widths:', {len(l) for l in lines})"
git add README.md
git commit -m "docs: document the bottom panel tabs in README"
```
Expected check output: `lines: 27 widths: {105}`.

---

### Task 5: End-to-end verification (no commit)

- [ ] **Step 1: Startup smoke + churn**

Run:
```sh
nvim --headless "+lua vim.wait(200) print('startup-ok')" +qa! 2>&1
nvim --headless "+lua require('core.activitybar').open() require('nvim-tree.api').tree.open() local p = require('core.panel') for _ = 1, 3 do p.toggle('terminal') vim.wait(150) p.toggle('problems') vim.wait(150) end local win = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do win[vim.bo[vim.api.nvim_win_get_buf(w)].filetype] = w end print('problems=' .. tostring(win.panelproblems ~= nil) .. ' sidebar_full=' .. tostring(vim.api.nvim_win_get_height(win.NvimTree) == vim.api.nvim_win_get_height(win.activitybar)))" +qa! 2>&1
```
Expected: `startup-ok`; `problems=true sidebar_full=true` (each toggle pair
ends with the Problems tab showing).

- [ ] **Step 2: Interactive checklist (report to user)**

- `` Ctrl+` ``: opens Terminal tab focused in terminal mode; again → closes; from Problems view → switches.
- `<leader>xx`: same pattern for Problems; count badge updates as diagnostics change.
- Mouse: click inactive tab → switch; click ✕ → close; click a problem line → jumps; activity-bar clicks still work with the panel open.
- Bar shows only Explorer / Search / Source Control / Plugins.
