# h-title

Update the terminal tab title from the current tmux session's associated hiiro task name.

## Usage

```
h title <subcommand>
```

## Subcommands

### `update`

Read the current tmux session name, find the associated hiiro task, and write an OSC escape sequence to the client TTY to set the terminal tab title. Silently does nothing if not in tmux or if the TTY write fails.

### `setup`

Write `~/.config/tmux/h-title.tmux.conf` with tmux hooks that call `h title update` on session change and new session events, then append a `source-file` line to `~/.tmux.conf`.
