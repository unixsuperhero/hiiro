# h-notify

Send Herdr notifications, keep a pane-aware notification log, and configure Claude Code hooks.

The log is stored at `~/.local/share/hiiro/notify_log.yml`. A new entry replaces the existing entry for the same pane.

## Synopsis

```bash
h notify <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `push [-t type] <message>` | Send and record a Herdr notification |
| `ls` | List live notifications and prune stale pane entries |
| `prune` | Remove entries whose Herdr panes no longer exist |
| `menu` | Choose a notification with the configured fuzzy finder |
| `jump <index>` | Focus its workspace/tab and dismiss it |
| `clear` | Clear the log |
| `remove_pane <pane-id>` | Remove entries for a pane |
| `remove_tab <tab-id>` | Remove entries for a tab |
| `remove_workspace <workspace-id>` | Remove entries for a workspace |
| `herdr setup` | Explain that no Herdr hooks are required |
| `claude <subcommand>` | Manage Claude Code hooks |

`remove_window` and `remove_session` remain aliases for `remove_tab` and `remove_workspace`.

## Notification types

| Type | Prefix | Herdr sound |
|------|--------|-------------|
| `info` | `[INFO]` | `none` |
| `success` | `[OK]` | `done` |
| `error` | `[ERR]` | `request` |
| `warning` | `[WARN]` | `request` |

```bash
h notify push "Build complete"
h notify push -t success "Tests passed"
h notify menu
h notify jump 0
```

## Claude Code hooks

The nested commands edit `~/.claude/settings.json`:

| Subcommand | Description |
|------------|-------------|
| `claude setup` / `claude add_hooks` | Configure `Notification` and `Stop` to call `h notify push` |
| `claude reset_hooks` | Remove Hiiro notification hook entries |
| `claude load_hooks` | Print the restart reminder |

Herdr 0.8.2 can focus the stored workspace and tab but not an arbitrary pane ID, so `jump` lands on the correct tab.
