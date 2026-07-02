# VSCode-style UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a VSCode-style layout to this Neovim config: a custom icon activity
bar at the far left, an edgy-managed bottom panel (terminal + problems), and
breadcrumbs above code windows.

**Architecture:** Four new lazy.nvim plugin specs (edgy, toggleterm, trouble,
dropbar) follow the existing one-file-per-plugin pattern in
`lua/lazy-plugins/`. The activity bar is a custom module in
`lua/core/activitybar.lua` (no plugin exists for this) loaded from `init.lua`
after lazy.nvim. Three existing files get small integration changes
(bufferline, lualine, nvim-tree).

**Tech Stack:** Neovim 0.12.2, lazy.nvim, folke/edgy.nvim, akinsho/toggleterm.nvim,
folke/trouble.nvim, Bekaboo/dropbar.nvim, Lua.

**Spec:** `docs/specs/2026-07-02-vscode-style-ui.md`

**Testing strategy:** This repo is a Neovim config with no unit-test framework;
adding one for this feature would be YAGNI. Each task instead verifies with
headless `nvim` commands (exact command + expected output given per step) and,
where the behavior is mouse/UI-driven, an explicit manual check.

## Deviation from spec

The spec had edgy.nvim also managing the nvim-tree window in a `left` section.
During planning this turned out to conflict with the custom activity bar: both
edgy's left edgebar and the activity-bar column compete for the leftmost screen
edge, and edgy re-asserts its layout on window events, which would repeatedly
displace the activity bar. Resolution:

- edgy manages **only the bottom panel** (terminal + problems).
- nvim-tree keeps managing its own left-side placement, exactly as today; the
  existing bufferline offset keeps the "File Explorer" title.
- The "quit when only panels remain" logic **stays** in
  `lua/lazy-plugins/nvim-tree.lua` (updated in Task 7 to ignore the activity
  bar) instead of moving to edgy's `exit_when_last`, which only counts
  edgy-managed windows and would never trigger with the activity bar open.

All user-visible requirements from the spec are unchanged.

## File structure

| File | Status | Responsibility |
| --- | --- | --- |
| `lua/lazy-plugins/edgy.lua` | create | Dock bottom panel windows with titles/sizes |
| `lua/lazy-plugins/toggleterm.lua` | create | Integrated terminal, `` Ctrl+` `` toggle |
| `lua/lazy-plugins/trouble.lua` | create | Problems (diagnostics) panel, `<leader>xx` |
| `lua/lazy-plugins/dropbar.lua` | create | Breadcrumbs winbar, `<leader>;` pick |
| `lua/core/activitybar.lua` | create | Custom icon activity bar (window, render, clicks) |
| `init.lua` | modify | Load the activity bar module after lazy.nvim |
| `lua/lazy-plugins/bufferline.lua` | modify | Tab-row offset over the activity bar |
| `lua/lazy-plugins/lualine.lua` | modify | No statusline segment under the activity bar |
| `lua/lazy-plugins/nvim-tree.lua` | modify | Last-window logic ignores the activity bar |
| `README.md` | modify | Document the new plugins and module |

---

### Task 1: edgy.nvim — bottom panel docking

**Files:**
- Create: `lua/lazy-plugins/edgy.lua`

- [ ] **Step 1: Write the plugin spec**

```lua
return {
  -- https://github.com/folke/edgy.nvim
  "folke/edgy.nvim",

  event = "VeryLazy",

  init = function()
    -- Recommended by edgy: keep text stable when panels open/close.
    vim.opt.splitkeep = "screen"
  end,

  opts = {
    -- Snappy, VSCode-like toggling.
    animate = { enabled = false },

    bottom = {
      {
        ft = "toggleterm",
        title = "Terminal",
        size = { height = 12 },
        -- Only manage normal splits; floating toggleterm windows stay floating.
        filter = function(_, win)
          return vim.api.nvim_win_get_config(win).relative == ""
        end,
      },
      {
        ft = "trouble",
        title = "Problems",
        size = { height = 12 },
      },
    },
  },
}
```

- [ ] **Step 2: Install and verify the config loads**

Run: `nvim --headless "+Lazy! sync" +qa 2>&1; echo "exit: $?"`
Expected: lazy.nvim install output containing `edgy.nvim`, ending with `exit: 0`, no `Error` lines.

Run: `nvim --headless '+lua require("edgy")' +qa 2>&1; echo "exit: $?"`
Expected: `exit: 0` with no error output.

- [ ] **Step 3: Commit**

```bash
git add lua/lazy-plugins/edgy.lua lazy-lock.json
git commit -m "feat(edgy): dock bottom panels with edgy.nvim"
```

---

### Task 2: toggleterm.nvim — integrated terminal

**Files:**
- Create: `lua/lazy-plugins/toggleterm.lua`

- [ ] **Step 1: Write the plugin spec**

The spec asks for VSCode's `` Ctrl+` ``. The mapping is defined in lazy's
`keys` (not toggleterm's `open_mapping`) so the plugin stays lazy-loaded until
first use. `mode = { "n", "t" }` makes the same key close the terminal from
terminal mode.

```lua
return {
  -- https://github.com/akinsho/toggleterm.nvim
  "akinsho/toggleterm.nvim",

  cmd = { "ToggleTerm", "TermExec" },

  keys = {
    -- Note: some terminal emulators do not transmit Ctrl+` (it needs the
    -- extended-keys protocol). If nothing happens on keypress, replace
    -- "<C-`>" with "<C-\>" here — everything else stays the same.
    { "<C-`>", "<cmd>ToggleTerm<CR>", mode = { "n", "t" }, desc = "toggle terminal" },
  },

  opts = {
    direction = "horizontal",
    size = 12,
  },
}
```

- [ ] **Step 2: Install and verify the terminal opens**

Run: `nvim --headless "+Lazy! sync" +qa 2>&1; echo "exit: $?"`
Expected: `exit: 0`, `toggleterm.nvim` installed.

Run: `nvim --headless "+ToggleTerm" '+lua print("ft=" .. vim.bo.filetype)' +qa 2>&1`
Expected output contains: `ft=toggleterm`

- [ ] **Step 3: Manual check (interactive)**

Open `nvim`, press `` Ctrl+` ``: a terminal opens at the bottom, 12 lines tall,
with an edgy "Terminal" title. Press `` Ctrl+` `` again inside it: it closes.
If the keypress does nothing, apply the `<C-\>` fallback noted in Step 1.

- [ ] **Step 4: Commit**

```bash
git add lua/lazy-plugins/toggleterm.lua lazy-lock.json
git commit -m "feat(toggleterm): add VSCode-style integrated terminal"
```

---

### Task 3: trouble.nvim — problems panel

**Files:**
- Create: `lua/lazy-plugins/trouble.lua`

- [ ] **Step 1: Write the plugin spec**

```lua
return {
  -- https://github.com/folke/trouble.nvim
  "folke/trouble.nvim",

  cmd = "Trouble",

  -- For file icons.
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },

  keys = {
    { "<leader>xx", "<cmd>Trouble diagnostics toggle<CR>", desc = "toggle problems" },
  },

  opts = {},
}
```

- [ ] **Step 2: Install and verify the config loads**

Run: `nvim --headless "+Lazy! sync" +qa 2>&1; echo "exit: $?"`
Expected: `exit: 0`, `trouble.nvim` installed.

Run: `nvim --headless '+lua require("trouble")' +qa 2>&1; echo "exit: $?"`
Expected: `exit: 0` with no error output.

- [ ] **Step 3: Manual check (interactive)**

Open a Lua file with a deliberate error (e.g. add `local x =` on a line in a
scratch file), press `<leader>xx`: a "Problems" panel opens at the bottom
listing the diagnostic. `<leader>xx` again closes it. Undo the deliberate error.

- [ ] **Step 4: Commit**

```bash
git add lua/lazy-plugins/trouble.lua lazy-lock.json
git commit -m "feat(trouble): add problems panel for diagnostics"
```

---

### Task 4: dropbar.nvim — breadcrumbs

**Files:**
- Create: `lua/lazy-plugins/dropbar.lua`

- [ ] **Step 1: Write the plugin spec**

```lua
return {
  -- https://github.com/Bekaboo/dropbar.nvim
  "Bekaboo/dropbar.nvim",

  event = "VeryLazy",

  -- For file icons.
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },

  keys = {
    {
      "<leader>;",
      function()
        require("dropbar.api").pick()
      end,
      desc = "dropbar pick",
    },
  },

  opts = {},
}
```

- [ ] **Step 2: Install and verify the config loads**

Run: `nvim --headless "+Lazy! sync" +qa 2>&1; echo "exit: $?"`
Expected: `exit: 0`, `dropbar.nvim` installed.

Run: `nvim --headless '+lua require("dropbar")' +qa 2>&1; echo "exit: $?"`
Expected: `exit: 0` with no error output.

- [ ] **Step 3: Manual check (interactive)**

Open `nvim lua/core/opt.lua`: a breadcrumb bar (path + symbols once the LSP
attaches) appears above the code. Click a crumb: a picker menu opens.
`<leader>;` starts pick mode. The winbar must NOT appear on the nvim-tree
window (dropbar skips special buftypes by default).

- [ ] **Step 4: Commit**

```bash
git add lua/lazy-plugins/dropbar.lua lazy-lock.json
git commit -m "feat(dropbar): add breadcrumbs winbar"
```

---

### Task 5: Activity bar module

**Files:**
- Create: `lua/core/activitybar.lua`
- Modify: `init.lua:12-15`
- Modify: `lua/lazy-plugins/lualine.lua:9-11`

- [ ] **Step 1: Write the module**

Create `lua/core/activitybar.lua` with exactly:

```lua
-- VSCode-style activity bar: a fixed icon column at the far left.
-- Not a plugin; loaded from init.lua after lazy.nvim so that entry actions can
-- rely on plugin commands and lazy-loading via require().
local M = {}

local WIDTH = 3
local ns = vim.api.nvim_create_namespace("activitybar")

local state = {
  buf = nil,
  win = nil,
  -- buffer line number -> entry, rebuilt on every render
  lines = {},
}

-- true if any window (any tabpage) shows a buffer with this filetype
local function win_with_ft(ft)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == ft then
      return true
    end
  end
  return false
end

-- Entries without is_active (e.g. Search) are transient and never highlighted.
local entries = {
  {
    icon = "󰉋",
    desc = "Explorer",
    action = function()
      require("nvim-tree.api").tree.toggle()
    end,
    is_active = function()
      return win_with_ft("NvimTree")
    end,
  },
  {
    icon = "",
    desc = "Search",
    action = function()
      require("telescope.builtin").live_grep()
    end,
  },
  {
    icon = "",
    desc = "Source Control",
    action = function()
      if win_with_ft("DiffviewFiles") then
        vim.cmd("DiffviewClose")
      else
        vim.cmd("DiffviewOpen")
      end
    end,
    is_active = function()
      return win_with_ft("DiffviewFiles")
    end,
  },
  {
    icon = "",
    desc = "Terminal",
    action = function()
      vim.cmd("ToggleTerm")
    end,
    is_active = function()
      return win_with_ft("toggleterm")
    end,
  },
  {
    icon = "󰀪",
    desc = "Problems",
    action = function()
      vim.cmd("Trouble diagnostics toggle")
    end,
    is_active = function()
      return win_with_ft("trouble")
    end,
  },
  {
    icon = "",
    desc = "Plugins (Lazy)",
    action = function()
      vim.cmd("Lazy")
    end,
    bottom = true,
  },
}

local function render()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
    return
  end

  local top, bottom = {}, {}
  for _, e in ipairs(entries) do
    table.insert(e.bottom and bottom or top, e)
  end

  local lines = {}
  state.lines = {}
  for _, e in ipairs(top) do
    table.insert(lines, " " .. e.icon)
    state.lines[#lines] = e
  end
  -- Pad so that `bottom` entries stick to the bottom of the window.
  local height = vim.api.nvim_win_get_height(state.win)
  while #lines < height - #bottom do
    table.insert(lines, "")
  end
  for _, e in ipairs(bottom) do
    table.insert(lines, " " .. e.icon)
    state.lines[#lines] = e
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for lnum, e in pairs(state.lines) do
    vim.api.nvim_buf_set_extmark(state.buf, ns, lnum - 1, 0, {
      end_col = #lines[lnum],
      hl_group = (e.is_active and e.is_active()) and "ActivityBarActive" or "ActivityBarInactive",
    })
  end
end

-- Global <LeftMouse> expr mapping: handle clicks on the bar without moving
-- focus; every other click keeps its default behavior.
local function on_click()
  local pos = vim.fn.getmousepos()
  if pos.winid ~= state.win then
    return "<LeftMouse>"
  end
  local entry = state.lines[pos.line]
  if entry then
    -- Run outside the expr-mapping context.
    vim.schedule(function()
      entry.action()
      render()
    end)
  end
  return ""
end

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

function M.open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    return
  end

  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].filetype = "activitybar"
    vim.bo[state.buf].modifiable = false
  end

  local prev = vim.api.nvim_get_current_win()
  vim.cmd("topleft " .. WIDTH .. "vsplit")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)

  local wo = vim.wo[state.win]
  wo.winfixwidth = true
  wo.winfixbuf = true
  wo.number = false
  wo.relativenumber = false
  wo.cursorline = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.statuscolumn = ""
  wo.wrap = false
  wo.fillchars = "eob: "

  vim.api.nvim_set_current_win(prev)
  render()
end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.open()
  end
end

function M.setup()
  vim.api.nvim_set_hl(0, "ActivityBarInactive", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "ActivityBarActive", { link = "Function", default = true })

  vim.keymap.set("n", "<LeftMouse>", on_click, { expr = true, desc = "activity bar click" })

  local group = vim.api.nvim_create_augroup("activitybar", {})

  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = function()
      M.open()
      ensure_position()
    end,
  })

  -- nvim-tree also opens "topleft"; keep the bar at the far left.
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "NvimTree",
    callback = function()
      vim.schedule(ensure_position)
    end,
  })

  -- Track open views for the active-icon highlight and bottom padding.
  vim.api.nvim_create_autocmd({ "WinEnter", "WinClosed", "WinResized", "TermOpen", "TermClose" }, {
    group = group,
    callback = function()
      vim.schedule(render)
    end,
  })

  vim.api.nvim_create_user_command("ActivityBar", function(cmd)
    M[cmd.args ~= "" and cmd.args or "toggle"]()
  end, {
    nargs = "?",
    complete = function()
      return { "open", "close", "toggle" }
    end,
  })
end

return M
```

- [ ] **Step 2: Load it from init.lua**

In `init.lua`, change:

```lua
-- common
require("core.keymap")
require("core.opt")
require("config.lazy")
```

to:

```lua
-- common
require("core.keymap")
require("core.opt")
require("config.lazy")
require("core.activitybar").setup()
```

- [ ] **Step 3: Hide the statusline segment under the bar**

In `lua/lazy-plugins/lualine.lua`, change:

```lua
  opts = {
    theme = "palenight",
  },
```

to:

```lua
  opts = {
    theme = "palenight",
    options = {
      -- The activity bar is a 3-column icon strip; no statusline under it.
      disabled_filetypes = { statusline = { "activitybar" } },
    },
  },
```

- [ ] **Step 4: Verify the bar opens at the far left**

Run: `nvim --headless '+lua for i, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do print(i, vim.bo[vim.api.nvim_win_get_buf(w)].filetype) end' +qa 2>&1`
Expected output contains a line `1 activitybar` (the bar exists and is window 1).

Run: `stylua --check lua/core/activitybar.lua; echo "exit: $?"`
Expected: `exit: 0`

- [ ] **Step 5: Manual check (interactive)**

Open `nvim lua/core/opt.lua`:
1. A 3-column icon column sits at the far left; the gear icon is at the bottom.
2. Click 󰉋: nvim-tree opens **to the right of the bar** (never left of it);
   the 󰉋 icon turns to the active highlight. Click again: tree closes,
   highlight reverts.
3. Click : Telescope live_grep opens (Esc to close).
4. Click : the terminal panel toggles and  gets the active highlight.
5. Click 󰀪: the Problems panel toggles.
6. Click the gear: Lazy UI opens (q to close).
7. `:ActivityBar toggle` closes the bar; `:ActivityBar toggle` reopens it.
8. Focus never moves to the bar when clicking (the cursor stays in your file).

- [ ] **Step 6: Commit**

```bash
git add lua/core/activitybar.lua init.lua lua/lazy-plugins/lualine.lua
git commit -m "feat(activitybar): add VSCode-style activity bar"
```

---

### Task 6: Bufferline offset over the activity bar

**Files:**
- Modify: `lua/lazy-plugins/bufferline.lua:38-46`

- [ ] **Step 1: Add the offset**

In `lua/lazy-plugins/bufferline.lua`, change:

```lua
      -- Reserve the left side for nvim-tree instead of drawing over it.
      offsets = {
        {
          filetype = "NvimTree",
          text = "File Explorer",
          text_align = "center",
          separator = true,
        },
      },
```

to:

```lua
      -- Reserve the left side for the activity bar and nvim-tree instead of
      -- drawing over them.
      offsets = {
        {
          filetype = "activitybar",
          text = "",
        },
        {
          filetype = "NvimTree",
          text = "File Explorer",
          text_align = "center",
          separator = true,
        },
      },
```

- [ ] **Step 2: Manual check (interactive)**

Open `nvim lua/core/opt.lua`, then open the tree (click 󰉋): the first buffer
tab starts exactly at the right edge of the tree, and the "File Explorer"
title is centered over the tree — not shifted 3 columns left.

- [ ] **Step 3: Commit**

```bash
git add lua/lazy-plugins/bufferline.lua
git commit -m "feat(bufferline): reserve offset for activity bar"
```

---

### Task 7: nvim-tree last-window logic ignores the activity bar

**Files:**
- Modify: `lua/lazy-plugins/nvim-tree.lua:54-90`

The existing autocmd counts "focusable windows" to decide when to quit. The
activity bar is a focusable split, so without this change `:q` in the last file
window would leave nvim running with just the tree and the bar. The old
BufEnter branch's toggle dance also assumed the tree was the very last window,
which is no longer true; it is replaced by explicitly reopening the alternate
buffer in a main window.

- [ ] **Step 1: Replace the autocmd**

In `lua/lazy-plugins/nvim-tree.lua`, replace the whole block:

```lua
    -- close vim if nvim-tree is the last window
    vim.api.nvim_create_autocmd({ "BufEnter", "QuitPre" }, {
      nested = false,
      callback = function(e)
        local tree = require("nvim-tree.api").tree

        -- Nothing to do if tree is not opened
        if not tree.is_visible() then
          return
        end

        -- How many focusable windows do we have? (excluding e.g. incline status window)
        local winCount = 0
        for _, winId in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_config(winId).focusable then
            winCount = winCount + 1
          end
        end

        -- We want to quit and only one window besides tree is left
        if e.event == "QuitPre" and winCount == 2 then
          vim.api.nvim_cmd({ cmd = "qall" }, {})
        end

        -- :bd was probably issued an only tree window is left
        -- Behave as if tree was closed (see `:h :bd`)
        if e.event == "BufEnter" and winCount == 1 then
          -- Required to avoid "Vim:E444: Cannot close last window"
          vim.defer_fn(function()
            -- close nvim-tree: will go to the last buffer used before closing
            tree.toggle({ find_file = true, focus = true })
            -- re-open nivm-tree
            tree.toggle({ find_file = true, focus = false })
          end, 10)
        end
      end,
    })
```

with:

```lua
    -- close vim if nvim-tree is the last window
    vim.api.nvim_create_autocmd({ "BufEnter", "QuitPre" }, {
      nested = false,
      callback = function(e)
        local tree = require("nvim-tree.api").tree

        -- Nothing to do if tree is not opened
        if not tree.is_visible() then
          return
        end

        -- How many "real" windows do we have? (excluding e.g. incline status
        -- window and the activity bar)
        local winCount = 0
        for _, winId in ipairs(vim.api.nvim_list_wins()) do
          local ft = vim.bo[vim.api.nvim_win_get_buf(winId)].filetype
          if vim.api.nvim_win_get_config(winId).focusable and ft ~= "activitybar" then
            winCount = winCount + 1
          end
        end

        -- We want to quit and only one window besides tree is left
        if e.event == "QuitPre" and winCount == 2 then
          vim.api.nvim_cmd({ cmd = "qall" }, {})
        end

        -- The tree is the only real window left (e.g. after <C-w>c on the
        -- last file window): reopen the alternate buffer in a main window.
        if e.event == "BufEnter" and winCount == 1 then
          vim.defer_fn(function()
            vim.cmd("botright vsplit")
            local alt = vim.fn.bufnr("#")
            if alt > 0 and vim.fn.buflisted(alt) == 1 then
              vim.api.nvim_set_current_buf(alt)
            else
              vim.cmd("enew")
            end
          end, 10)
        end
      end,
    })
```

- [ ] **Step 2: Manual check (interactive)**

1. `nvim lua/core/opt.lua`, open the tree (click 󰉋), then `:q` in the file
   window: nvim exits completely.
2. `nvim lua/core/opt.lua`, open the tree, then `<C-w>c` in the file window:
   a main window reopens showing `opt.lua` next to the tree (nvim does not get
   stuck on tree + bar only).

- [ ] **Step 3: Commit**

```bash
git add lua/lazy-plugins/nvim-tree.lua
git commit -m "refactor(nvim-tree): account for activity bar in last-window logic"
```

---

### Task 8: Documentation and final verification

**Files:**
- Modify: `README.md:25-40`

- [ ] **Step 1: Document the new plugins**

In `README.md`, append these rows to the plugin table (after the diffview row):

```markdown
| [edgy.nvim](https://github.com/folke/edgy.nvim)                                 | Docks the bottom panel (terminal, problems) with titles and fixed sizes.                          |
| [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim)                   | Integrated terminal in the bottom panel (`` Ctrl+` ``).                                           |
| [trouble.nvim](https://github.com/folke/trouble.nvim)                           | Problems panel listing diagnostics (`<leader>xx`).                                                |
| [dropbar.nvim](https://github.com/Bekaboo/dropbar.nvim)                         | VSCode-style breadcrumbs winbar (`<leader>;` to pick).                                            |
```

Then add this paragraph directly after the table:

```markdown
A custom VSCode-style activity bar (icon column at the far left) lives in
`lua/core/activitybar.lua`; toggle it with `:ActivityBar toggle`.
```

- [ ] **Step 2: Format and full headless check**

Run: `deno fmt README.md && stylua lua/ init.lua && git diff --stat`
Expected: only formatting-consistent output; no unexpected file churn.

Run: `nvim --headless "+Lazy! sync" +qa 2>&1; echo "exit: $?"`
Expected: `exit: 0`, no `Error` lines.

- [ ] **Step 3: Full manual checklist (interactive)**

With `nvim lua/core/opt.lua`:
- Activity bar far left, gear at the bottom; icons highlight when their view is open.
- 󰉋 toggles the tree; tabs stay aligned; "File Explorer" title centered.
- `` Ctrl+` `` toggles the terminal (title "Terminal", 12 lines).
- `<leader>xx` toggles Problems.
- Breadcrumbs above code; `<leader>;` picks; no winbar on tree/terminal/problems/bar.
- `:q` in the last file window (tree open) exits nvim.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document VSCode-style UI plugins in README"
```
