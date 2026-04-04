# h-title

Update the terminal tab title from the current tmux session's associated hiiro task name.

## Synopsis

```bash
h title <subcommand>
```

Uses OSC escape sequences to write to the client TTY. If no task is associated with the current session, falls back to the session name as the title.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `update` | Set the terminal tab title based on the current task |
| `setup` | Install tmux hooks and append to `~/.tmux.conf` |

## Subcommand Details

### `update`

Read the current tmux session name, find the associated hiiro task (from `tasks.yml`), and write an OSC escape sequence (`\033]0;<title>\007`) to the client TTY to set the terminal tab title. Silently does nothing if not in tmux or if the TTY write fails.

```bash
h title update
```

Normally called automatically by tmux hooks after `setup`.

### `setup`

Write `~/.config/tmux/h-title.tmux.conf` with tmux hooks:

- `client-session-changed` — calls `h title update` when switching sessions
- `after-new-session` — calls `h title update` on new sessions

Also appends a `source-file` line to `~/.tmux.conf`. Reload tmux after setup.

```bash
h title setup
tmux source-file ~/.tmux.conf
```

## Examples

```bash
# Initial setup (run once)
h title setup
tmux source-file ~/.tmux.conf

# Manually update the title (e.g., after changing tasks)
h title update
```
