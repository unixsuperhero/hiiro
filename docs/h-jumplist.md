# h-jumplist

Vim-style tmux navigation history — jump backward and forward through pane/window/session focus history.

## Usage

```
h jumplist <subcommand>
```

History is stored per tmux client in `~/.config/hiiro/jumplist/`. Dead panes are automatically pruned. Duplicate consecutive entries are deduplicated. Forward history is truncated when you navigate to a new location (like vim).

## Subcommands

### `setup`

Write `~/.config/tmux/h-jumplist.tmux.conf` with tmux hooks to record navigation events and key bindings (`Ctrl-B` = back, `Ctrl-F` = forward). Append a `source-file` line to `~/.tmux.conf`.

### `record`

Record the current pane/window/session as a new jumplist entry. Called automatically by tmux hooks; typically not invoked manually. Suppresses itself if `TMUX_JUMPLIST_SUPPRESS=1` is set.

### `back`

Navigate to the previous position in history (older). If already at the oldest entry, shows a tmux message.

### `forward`

Navigate to the next position in history (newer). If already at the newest entry, shows a tmux message.

### `to`

Navigate directly to a specific history entry by index.

**Args:** `<index>`

### `ls` [alias: `list`]

Print the full jumplist with timestamps and a `<--` marker on the current position.

### `clear`

Clear the jumplist and reset position to the current pane.

### `path`

Print the jumplist file path for the current tmux client.
