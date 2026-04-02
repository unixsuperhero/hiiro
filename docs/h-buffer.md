# h-buffer

Manage tmux paste buffers — list, show, copy to clipboard, save, load, paste, and delete.

## Usage

```
h buffer <subcommand> [args]
```

## Subcommands

### `ls`

List all tmux buffers. Extra args are passed directly to `tmux list-buffers`.

**Args:** `[tmux_args...]`

### `show`

Print the contents of a buffer (fuzzy-select if no name given).

**Args:** `[buffer_name] [tmux_args...]`

### `copy`

Copy a buffer's contents to the macOS clipboard via `pbcopy` (fuzzy-select if no name).

**Args:** `[buffer_name]`

### `save`

Save a buffer's contents to a file (fuzzy-select buffer if name not given).

**Args:** `<path> [buffer_name] [tmux_args...]`

### `load`

Load a file into the tmux buffer stack.

**Args:** `<path> [tmux_args...]`

### `set`

Set buffer contents; all args passed directly to `tmux set-buffer`.

**Args:** `[tmux_args...]`

### `paste`

Paste a buffer into the current pane.

**Args:** `[buffer_name] [tmux_args...]`

### `delete`

Delete a buffer (fuzzy-select if no name given).

**Args:** `[buffer_name]`

### `choose`

Open the tmux buffer chooser UI.

**Args:** `[tmux_args...]`

### `clear`

Delete all tmux buffers.

### `select`

Fuzzy-select a buffer name and print it.
