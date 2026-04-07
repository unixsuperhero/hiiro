# h-window

Manage tmux windows — list, create, kill, rename, swap, navigate, and change layout.

## Synopsis

```bash
h window <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ls [args]` | List windows in current session |
| `lsa [args]` | List all windows across all sessions |
| `new [name]` | Create a new window |
| `kill [target]` | Kill a window |
| `rename [args]` | Rename a window |
| `swap [args]` | Swap windows |
| `move [args]` | Move a window |
| `link [args]` | Link a window |
| `unlink [target]` | Unlink a window |
| `select [target]` | Print target window ID (fuzzy-select if needed) |
| `copy [target]` | Copy window target to clipboard |
| `sw` / `switch [target]` | Switch to a window |
| `next [args]` | Move to next window |
| `prev [args]` | Move to previous window |
| `last [args]` | Move to last window |
| `info [target]` | Show window info |
| `vsplit` | Apply even-horizontal layout (side by side panes) |
| `hsplit` | Apply even-vertical layout (top/bottom panes) |
| `layout [name]` | Apply a named layout |

### kill

Kill a window. Fuzzy-select if no target given.

**Examples**

```bash
h window kill
h window kill :3
```

### layout

Apply a tmux layout. Fuzzy-select from available layouts if no name given. Supported layout names:

- `horizontal` / `ehorizontal` — even-vertical (top/bottom panes)
- `vertical` / `evertical` — even-horizontal (side-by-side panes)
- `mhorizontal` / `main_horizontal` — main-vertical
- `mvertical` / `main_vertical` — main-horizontal
- `tiled` — tiled

**Examples**

```bash
h window layout
h window layout horizontal
h window layout tiled
```

### ls / lsa

List windows in the current session (`ls`) or all windows across all sessions (`lsa`). Extra arguments are forwarded to `tmux list-windows`.

**Examples**

```bash
h window ls
h window lsa
```

### new

Create a new window, optionally named.

**Examples**

```bash
h window new
h window new my-window
```

### next / prev / last

Navigate to next, previous, or last window.

**Examples**

```bash
h window next
h window prev
h window last
```

### select / copy

Fuzzy-select a window and print its target ID or copy it to clipboard.

**Examples**

```bash
h window select
target=$(h window select)
h window copy
```

### sw / switch

Switch to a window. Fuzzy-select if no target given.

**Examples**

```bash
h window sw
h window switch my-session:my-window
```

### vsplit / hsplit

Shortcuts for common layouts:

- `vsplit` — apply `even-horizontal` layout (panes side by side)
- `hsplit` — apply `even-vertical` layout (panes stacked top/bottom)

**Examples**

```bash
h window vsplit
h window hsplit
```
