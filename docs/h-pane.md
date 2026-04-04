# h-pane

Manage tmux panes — list, split, kill, zoom, capture, resize, and configure named home panes.

## Synopsis

```bash
h pane <subcommand> [args]
```

## Subcommands

| Subcommand | Aliases | Description |
|------------|---------|-------------|
| `ls` | — | List panes in the current window |
| `lsa` | — | List all panes across all sessions |
| `split` | — | Split the current window |
| `splitv` | — | Split vertically |
| `splith` | — | Split horizontally |
| `kill` | — | Kill a pane |
| `swap` | — | Swap panes |
| `zoom` | — | Toggle zoom on a pane |
| `capture` | — | Capture the current pane's output |
| `select` | — | Fuzzy-select a pane ID and print it |
| `copy` | — | Fuzzy-select a pane ID and copy to clipboard |
| `sw` | `switch` | Switch to a pane |
| `home` | — | Manage named home panes (nested subcommands) |
| `move` | — | Move a pane |
| `break` | — | Break a pane out into its own window |
| `join` | — | Join a pane into the current window |
| `resize` | — | Resize a pane |
| `width` | — | Set pane width |
| `height` | — | Set pane height |
| `info` | — | Show pane details |

## Subcommand Details

### `ls` / `lsa`

List panes in the current window, or all panes across all sessions with `lsa`. Extra args are forwarded to `tmux list-panes`.

```bash
h pane ls
h pane lsa
h pane ls -F '#{pane_id}: #{pane_current_command}'
```

### `split` / `splitv` / `splith`

Split the current window. `split` passes all args to `tmux split-window`. `splitv` creates a vertical split; `splith` creates a horizontal split.

```bash
h pane split
h pane split -p 30
h pane splitv
h pane splith
```

### `kill`

Kill a pane. With no target, fuzzy-selects.

```bash
h pane kill
h pane kill %12
```

### `zoom`

Toggle zoom on the current (or target) pane.

```bash
h pane zoom
h pane zoom %5
```

### `capture`

Capture the current pane's output and print it. Extra args forwarded to `tmux capture-pane`.

```bash
h pane capture
h pane capture -p -b buffer0
```

### `select` / `copy`

Fuzzy-select a pane ID and print it or copy to clipboard.

```bash
pane_id=$(h pane select)
h pane copy
```

### `sw` / `switch`

Switch to a pane. Fuzzy-selects if no target given.

```bash
h pane sw
h pane switch %8
```

### `home`

Manage named home panes with nested subcommands:

| Sub-subcommand | Description |
|----------------|-------------|
| `h pane home ls` | List configured home panes |
| `h pane home add <name> <session> [path]` | Add a home pane mapping |
| `h pane home rm <name>` | Remove a home pane |
| `h pane home switch [name]` | Switch to a home pane (fuzzy-selects if no name); creates session/window if needed |

```bash
h pane home add work main ~/work
h pane home add notes notes ~/notes
h pane home switch work
h pane home ls
```

### `move` / `break` / `join`

Move a pane, break it into a window, or join it into the current window.

```bash
h pane break
h pane join -s other-session:2
h pane move -t main:0
```

### `resize` / `width` / `height`

Resize a pane. `width` and `height` set specific dimensions.

```bash
h pane resize -x 80
h pane width 80
h pane height 30
```

### `info`

Show details for the current (or target) pane: ID, size, command, and path.

```bash
h pane info
h pane info %12
```

## Examples

```bash
# Set up named home panes for quick navigation
h pane home add work main ~/work
h pane home add notes notes ~/notes

# Jump to work pane
h pane home switch work

# Split current window for a quick test
h pane splith

# Zoom in on the current pane
h pane zoom

# Kill a pane interactively
h pane kill
```
