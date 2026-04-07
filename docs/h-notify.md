# h-notify

Push and manage in-pane notifications with macOS alerts, tmux menu navigation, and Claude Code hook integration.

## Synopsis

```bash
h notify <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `push [-t type] <message>` | Push a notification for the current pane |
| `ls` | List all current notifications |
| `menu` | Show a tmux popup menu of notifications |
| `jump <index>` | Navigate to a notification's pane and dismiss it |
| `clear` | Clear all notifications |
| `remove_pane <pane_id>` | Remove notifications for a pane (called by tmux hook) |
| `remove_window <window_id>` | Remove notifications for a window (called by tmux hook) |
| `remove_session <session>` | Remove notifications for a session (called by tmux hook) |
| `tmux` | tmux setup subcommands |
| `claude` | Claude Code hook subcommands |

Notification log is stored at `~/.config/hiiro/data/notify_log.yml`. One entry per pane (new pushes replace the existing entry for that pane).

Notification types:

| Type | Prefix | Sound | Title |
|------|--------|-------|-------|
| `info` | `[INFO]` | Pop | Info |
| `success` | `[OK]` | Glass | Success |
| `error` | `[ERR]` | Basso | Error |
| `warning` | `[WARN]` | Purr | Warning |

### claude

Subcommands for integrating with Claude Code notification hooks in `~/.claude/settings.json`.

| Subcommand | Description |
|------------|-------------|
| `setup` | Set `Notification` and `Stop` hooks to use `h alert` + `h notify push` |
| `add_hooks` | Inject `h notify push` into existing hooks (non-destructive) |
| `reset_hooks` | Strip `h notify push` from existing hooks |
| `load_hooks` | Print a reminder to restart claude |

**Examples**

```bash
h notify claude setup
h notify claude add_hooks
```
### clear

Remove all notifications from the log.

**Examples**

```bash
h notify clear
```

### jump

Navigate to the pane for notification at `index` and dismiss it from the log. Dead panes are pruned automatically.

**Examples**

```bash
h notify jump 0
h notify jump 2
```

### ls

List all notifications with index, type prefix, session/pane, command, message, and time.

**Examples**

```bash
h notify ls
```

### menu

Show a tmux `display-menu` popup listing the last 10 notifications. Each entry lets you jump to that pane. Includes a "Clear all" option at the bottom. Bound to `prefix + N` after `h notify tmux setup`.

**Examples**

```bash
h notify menu
```

### push

Push a notification for the current tmux pane. Fires a `terminal-notifier` macOS alert and stores the entry in the log.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--type` | `-t` | Notification type (`success`, `error`, `info`, `warning`) | `info` |

**Examples**

```bash
h notify push "Build complete"
h notify push -t success "Tests passed"
h notify push -t error "Deploy failed"
```

### tmux

Subcommands for setting up tmux hooks.

| Subcommand | Description |
|------------|-------------|
| `setup` | Write `~/.config/tmux/h-notify.tmux.conf` with hooks and `prefix+N` binding |
| `add_hooks` | Append `source-file` to `~/.tmux.conf` and reload |
| `reset_hooks` | Unset the notify tmux hooks |
| `load_hooks` | Source `~/.tmux.conf` to reload hooks |

**Examples**

```bash
h notify tmux setup
h notify tmux add_hooks
```

