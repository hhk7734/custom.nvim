# Layout

## Workspace

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

## Components

```text
Activity bar  → lua/core/activitybar.lua
Sidebar       → nvim-tree.lua / lua/core/gitpanel.lua
Editor tabs   → bufferline.nvim
Breadcrumbs   → dropbar.nvim
Bottom panel  → lua/core/panel.lua
Statusline    → lualine.nvim
```
