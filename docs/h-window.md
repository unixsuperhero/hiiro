# h-window

Manage tmux windows — list, create, kill, rename, swap, navigate, and change layout.

## Usage

```
h window <subcommand> [args]
```

## Subcommands

### `ls`

List windows in the current session. Extra args passed to `tmux list-windows`.

**Args:** `[tmux_args...]`

### `lsa`

List all windows across all sessions.

**Args:** `[tmux_args...]`

### `new`

Create a new window with an optional name.

**Args:** `[name] [tmux_args...]`

### `kill`

Kill a window (fuzzy-select if no target given).

**Args:** `[target]`

### `rename`

Rename the current window. Args passed to `tmux rename-window`.

**Args:** `[tmux_args...]`

### `swap`

Swap windows. Args passed to `tmux swap-window`.

**Args:** `[tmux_args...]`

### `move`

Move window. Args passed to `tmux move-window`.

**Args:** `[tmux_args...]`

### `select`

Fuzzy-select a window target and print it.

**Args:** `[target]`

### `copy`

Fuzzy-select a window target and copy it to clipboard.

**Args:** `[target]`

### `sw` [alias: `switch`]

Switch to a window (fuzzy-select if no target).

**Args:** `[target]`

### `next`

Go to the next window.

**Args:** `[tmux_args...]`

### `prev`

Go to the previous window.

**Args:** `[tmux_args...]`

### `last`

Go to the last active window.

**Args:** `[tmux_args...]`

### `link`

Link a window to another session. Args passed to `tmux link-window`.

**Args:** `[tmux_args...]`

### `unlink`

Unlink a window from its session.

**Args:** `[target]`

### `info`

Show info about the current (or target) window.

**Args:** `[target]`

### `vsplit`

Apply `even-horizontal` layout to the current window (side-by-side panes).

### `hsplit`

Apply `even-vertical` layout to the current window (top/bottom panes).

### `layout`

Select a tmux layout by fuzzy name. Accepted names map to tmux layout strings (e.g., `horizontal`, `vertical`, `tiled`, `main_horizontal`, `main_vertical`, etc.).

**Args:** `[layout_name]`
