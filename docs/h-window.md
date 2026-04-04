# h-window

Manage tmux windows — list, create, kill, rename, swap, navigate, and change layout.

## Synopsis

```bash
h window <subcommand> [args]
```

## Subcommands

| Subcommand | Aliases | Description |
|------------|---------|-------------|
| `ls` | — | List windows in the current session |
| `lsa` | — | List all windows across all sessions |
| `new` | — | Create a new window |
| `kill` | — | Kill a window |
| `rename` | — | Rename the current window |
| `swap` | — | Swap windows |
| `move` | — | Move window |
| `select` | — | Fuzzy-select a window target and print it |
| `copy` | — | Fuzzy-select a window and copy target to clipboard |
| `sw` | `switch` | Switch to a window |
| `next` | — | Go to the next window |
| `prev` | — | Go to the previous window |
| `last` | — | Go to the last active window |
| `link` | — | Link a window to another session |
| `unlink` | — | Unlink a window from its session |
| `info` | — | Show info about a window |
| `vsplit` | — | Apply `even-horizontal` layout (side-by-side panes) |
| `hsplit` | — | Apply `even-vertical` layout (top/bottom panes) |
| `layout` | — | Select a tmux layout by name |

## Subcommand Details

### `ls` / `lsa`

List windows in the current session, or all windows across all sessions with `lsa`. Extra args forwarded to `tmux list-windows`.

```bash
h window ls
h window lsa
h window ls -F '#{window_name}: #{window_panes} panes'
```

### `new`

Create a new window with an optional name.

```bash
h window new
h window new my-feature
```

### `kill`

Kill a window. Fuzzy-selects if no target given.

```bash
h window kill
h window kill @3
```

### `rename`

Rename the current window. Args forwarded to `tmux rename-window`.

```bash
h window rename my-feature
```

### `sw` / `switch`

Switch to a window. Fuzzy-selects if no target given.

```bash
h window sw
h window switch @3
```

### `next` / `prev` / `last`

Navigate between windows.

```bash
h window next
h window prev
h window last
```

### `vsplit` / `hsplit`

Apply a layout to the current window:

- `vsplit` — `even-horizontal` (side-by-side panes)
- `hsplit` — `even-vertical` (top/bottom panes)

```bash
h window vsplit
h window hsplit
```

### `layout`

Select a tmux layout by name. Fuzzy-selects if no name given. Accepted names (mapped to tmux layout strings):

| Input name | tmux layout |
|------------|-------------|
| `horizontal`, `ehorizontal` | `even-vertical` |
| `vertical`, `evertical` | `even-horizontal` |
| `main_horizontal`, `mhorizontal` | `main-vertical` |
| `main_vertical`, `mvertical` | `main-horizontal` |
| `tiled` | `tiled` |

```bash
h window layout
h window layout tiled
h window layout vertical
```

### `info`

Show info about the current (or target) window.

```bash
h window info
h window info @3
```

## Examples

```bash
# Open a new named window
h window new feature-work

# Switch to a window interactively
h window sw

# Arrange panes side by side
h window vsplit

# Go to next/previous window
h window next
h window prev
```
