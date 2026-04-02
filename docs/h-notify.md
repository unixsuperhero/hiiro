# h-notify

Push and manage in-pane notifications with macOS alerts, tmux menu navigation, and Claude Code hook integration.

## Usage

```
h notify <subcommand> [options] [args]
```

## Global Options

These options are parsed from `args` before subcommand dispatch:

| Flag | Short | Description | Default |
|---|---|---|---|
| `--type` | `-t` | Notification type: `success`, `error`, `info`, `warning` | `info` |

## Subcommands

### `push`

Push a notification for the current tmux pane. Fires a macOS `terminal-notifier` alert and records the entry in the log (one entry per pane, newest first).

**Args:** `<message...>`

### `ls`

List all current notifications with index, type prefix, session/pane, command, message, and timestamp.

### `menu`

Open a tmux `display-menu` showing up to 10 pending notifications. Selecting one switches to that pane. A "Clear all" option is also provided.

### `jump`

Navigate to the pane associated with a notification by index and remove it from the log.

**Args:** `<index>`

### `clear`

Remove all notifications from the log.

### `remove_pane`

Remove all notifications associated with a pane ID (called automatically by tmux `after-kill-pane` hook).

**Args:** `<pane_id>`

### `remove_window`

Remove notifications for a window ID (called by tmux `window-unlinked` hook).

**Args:** `<window_id>`

### `remove_session`

Remove notifications for a session (called by tmux `session-closed` hook).

**Args:** `<session_name>`

### `tmux`

Manage tmux hook configuration for automatic notification cleanup. Nested subcommands:

- `h notify tmux setup` — Write `~/.config/tmux/h-notify.tmux.conf`
- `h notify tmux add_hooks` — Source the conf file from `~/.tmux.conf`
- `h notify tmux reset_hooks` — Unset the managed tmux hooks
- `h notify tmux load_hooks` — Reload `~/.tmux.conf` via `tmux source-file`

### `claude`

Manage Claude Code hook integration in `~/.claude/settings.json`. Nested subcommands:

- `h notify claude setup` — Write fresh `Notification` and `Stop` hooks that call `h alert` + `h notify push`
- `h notify claude add_hooks` — Inject `h notify push` into existing hooks without overwriting them
- `h notify claude reset_hooks` — Strip the `h notify push` portion from existing hooks
- `h notify claude load_hooks` — Print a reminder that Claude Code settings load on startup
