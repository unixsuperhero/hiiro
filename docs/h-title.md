# h-title

Update the terminal tab title from the current tmux session's associated hiiro task name.

## Synopsis

```bash
h title <subcommand>
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `update` | Set the terminal tab title to the current task name (or session name) |
| `setup` | Install tmux hooks to auto-update the title |

### update

Reads the current tmux session name, finds the associated hiiro task (if any), and sets the terminal tab title via an escape sequence written to the client's TTY. If no task is found, uses the session name as the title. Silent no-op outside of tmux.

**Examples**

```bash
h title update
```

### setup

Writes a tmux config file at `~/.config/tmux/h-title.tmux.conf` with hooks that call `h title update` whenever the session changes. Appends a `source-file` line to `~/.tmux.conf`.

**Examples**

```bash
h title setup
tmux source-file ~/.tmux.conf
```
