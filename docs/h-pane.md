# h-pane

Manage tmux panes — list, split, kill, zoom, capture, resize, and configure named home panes.

## Usage

```
h pane <subcommand> [args]
```

## Subcommands

### `ls`

List panes in the current window. Extra args passed to `tmux list-panes`.

**Args:** `[tmux_args...]`

### `lsa`

List all panes across all sessions.

**Args:** `[tmux_args...]`

### `split`

Split the current window. All args passed to `tmux split-window`.

**Args:** `[tmux_args...]`

### `splitv`

Split vertically.

**Args:** `[tmux_args...]`

### `splith`

Split horizontally.

**Args:** `[tmux_args...]`

### `kill`

Kill a pane (fuzzy-select if no target given).

**Args:** `[target]`

### `swap`

Swap panes. Args passed to `tmux swap-pane`.

**Args:** `[tmux_args...]`

### `zoom`

Toggle zoom on a pane.

**Args:** `[target]`

### `capture`

Capture the current pane's output. Args passed to `tmux capture-pane`.

**Args:** `[tmux_args...]`

### `select`

Fuzzy-select a pane ID and print it.

**Args:** `[target]`

### `copy`

Fuzzy-select a pane ID and copy it to clipboard.

**Args:** `[target]`

### `sw` [alias: `switch`]

Switch to a pane (fuzzy-select if no target).

**Args:** `[target]`

### `home`

Manage named home panes. Nested subcommands:

- `h pane home ls` — List configured home panes
- `h pane home add <name> <session> [path]` — Add a home pane mapping
- `h pane home rm <name>` — Remove a home pane
- `h pane home switch [name]` — Switch to a home pane (fuzzy-select if no name); creates the session/window if needed

### `move`

Move a pane. Args passed to `tmux move-pane`.

**Args:** `[tmux_args...]`

### `break`

Break a pane out into its own window.

**Args:** `[tmux_args...]`

### `join`

Join a pane into the current window. Args passed to `tmux join-pane`.

**Args:** `[tmux_args...]`

### `resize`

Resize a pane. Args passed to `tmux resize-pane`.

**Args:** `[tmux_args...]`

### `width`

Set the pane width to a specific size.

**Args:** `<size> [target]`

### `height`

Set the pane height to a specific size.

**Args:** `<size> [target]`

### `info`

Show details for the current (or target) pane: size, command, and path.

**Args:** `[target]`
