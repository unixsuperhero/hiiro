# h-notify

Push and manage in-pane notifications with macOS alerts, tmux menu navigation, and Claude Code hook integration.

## Synopsis

```bash
h notify <subcommand> [options] [args]
```

Notifications are stored in a flat log at `~/.config/hiiro/data/notify_log.yml` (one entry per pane — newer entries replace older ones for the same pane). Each entry records pane ID, window ID, session, message, type, and timestamp.

## Global Options

Parsed from args before subcommand dispatch:

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--type` | `-t` | Notification type: `success`, `error`, `info`, `warning` | `info` |

Type presets:

| Type | Prefix | Sound | Title |
|------|--------|-------|-------|
| `success` | `[OK]` | Glass | Success |
| `error` | `[ERR]` | Basso | Error |
| `info` | `[INFO]` | Pop | Info |
| `warning` | `[WARN]` | Purr | Warning |

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `push` | Push a notification for the current tmux pane |
| `ls` | List all current notifications |
| `menu` | Open tmux menu showing pending notifications |
| `jump` | Navigate to a notification's pane by index |
| `clear` | Remove all notifications |
| `remove_pane` | Remove notifications for a pane (called by tmux hook) |
| `remove_window` | Remove notifications for a window (called by tmux hook) |
| `remove_session` | Remove notifications for a session (called by tmux hook) |
| `tmux` | Manage tmux hook configuration |
| `claude` | Manage Claude Code hook integration |

## Subcommand Details

### `push`

Push a notification for the current tmux pane. Fires a macOS `terminal-notifier` alert and records the entry in the log.

```bash
h notify push "Build finished"
h notify push -t success "Tests passed"
h notify push -t error "Deploy failed"
```

### `ls`

List all current notifications with index, type prefix, session/pane, command, message, and timestamp.

```bash
h notify ls
#   0) [OK]   [main/%12] rails: Tests passed (14:35:02)
#   1) [ERR]  [work/%8]  jest: Build failed (14:32:11)
```

### `menu`

Open a `tmux display-menu` showing up to 10 pending notifications. Selecting one switches to that pane and removes the notification from the log. A "Clear all" option is also provided.

```bash
h notify menu
# Or bind to a key: bind-key N run-shell "h notify menu"
```

### `jump`

Navigate to the pane associated with a notification by its index (from `ls`), and remove it from the log.

```bash
h notify jump 0
h notify jump 2
```

### `clear`

Remove all notifications from the log.

```bash
h notify clear
```

### `remove_pane` / `remove_window` / `remove_session`

Remove all notifications associated with a pane, window, or session. Called automatically by tmux hooks — not typically invoked manually.

```bash
h notify remove_pane %12
h notify remove_session mywork
```

### `tmux`

Manage tmux hook configuration for automatic notification cleanup:

| Sub-subcommand | Description |
|----------------|-------------|
| `h notify tmux setup` | Write `~/.config/tmux/h-notify.tmux.conf` with hooks and `prefix+N` keybinding |
| `h notify tmux add_hooks` | Source the conf file from `~/.tmux.conf` and reload |
| `h notify tmux reset_hooks` | Unset the managed tmux hooks |
| `h notify tmux load_hooks` | Reload `~/.tmux.conf` via `tmux source-file` |

```bash
h notify tmux setup
h notify tmux add_hooks
```

### `claude`

Manage Claude Code hook integration in `~/.claude/settings.json`:

| Sub-subcommand | Description |
|----------------|-------------|
| `h notify claude setup` | Write fresh `Notification` and `Stop` hooks calling `h alert` + `h notify push` |
| `h notify claude add_hooks` | Inject `h notify push` into existing hooks without overwriting |
| `h notify claude reset_hooks` | Strip `h notify push` from existing hooks |
| `h notify claude load_hooks` | Print restart reminder (Claude Code loads settings at startup) |

```bash
h notify claude setup
h notify claude add_hooks
```

## Examples

```bash
# Initial setup (run once)
h notify tmux setup
h notify tmux add_hooks
h notify claude setup

# Use at end of long-running commands
bundle exec rails test; h notify push -t success "Tests done"
./deploy.sh; h notify push -t success "Deployed"

# Check pending notifications
h notify ls

# Open notification menu in tmux (after setup, press prefix+N)
h notify menu
```
