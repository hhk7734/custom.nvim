# GitPanel Sidebar

## Activity Bar: Source Control

```text
┌─────┬──────────────────────────────┬────────────────────────────────────────┐
│ 󰉋  │ Source Control                │ editor                                 │
│     ├──────────────────────────────┤                                        │
│   │   Changes                  │                                        │
│     │    gitpanel.lua [modified] │                                        │
│   │    added.txt [added]        │                                        │
│     │    deleted.txt [deleted]    │                                        │
│     ├──────────────────────────────┤                                        │
│   │  <hash> <title>             │                                        │
└─────┴──────────────────────────────┴────────────────────────────────────────┘
```

## Changes: Modified File

```text
┌──────────────────────────────┬──────────────────────┬──────────────────────┐
│   Changes                  │ previous             │ updated              │
│    gitpanel.lua [modified] │ old line             │ new line             │
└──────────────────────────────┴──────────────────────┴──────────────────────┘
```

## Changes: Added File

```text
┌──────────────────────────────┬─────────────────────────────────────────────┐
│   Changes                  │ added.txt                                   │
│    added.txt [added]        │ added file contents                         │
└──────────────────────────────┴─────────────────────────────────────────────┘
```

## Changes: Deleted File

```text
┌──────────────────────────────┬──────────────────────┬──────────────────────┐
│   Changes                  │ previous             │ updated              │
│    deleted.txt [deleted]    │ deleted file content │                      │
└──────────────────────────────┴──────────────────────┴──────────────────────┘
```

## Commits

```text
┌──────────────────────────────┬──────────────────────┬──────────────────────┐
│  <hash> <title>             │ parent               │ selected commit      │
│     lua                    │ old line             │ new line             │
│      gitpanel.lua [modified]│                      │                      │
│    added.txt [added]        │                      │ added file contents  │
└──────────────────────────────┴──────────────────────┴──────────────────────┘
```
