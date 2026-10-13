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

The nested commands edit `~/.claude/settings.json`, and only Hiiro's own entries in it. Hiiro owns exactly two hook entries, matched by their exact command:

```js
{ Notification: `MSG=$(cat | jq -r '.message // "Needs input"'); h notify push -t info "$MSG"`,
  Stop:         `h notify push -t success 'Work completed'` }
```

| Subcommand | Description |
|------------|-------------|
| `claude setup` / `claude add_hooks` [`--dry-run`] | Append each owned entry that is missing as its own hook group; report `added` or `already present` per event |
| `claude reset_hooks` / `claude remove_hooks` [`--dry-run`] | Remove the owned entries, then only the groups and event keys that removal left empty |
| `claude load_hooks` | Print the restart reminder |

Every other key, event, matcher group, and hook (including other `Stop` or `Notification` hooks) is kept as it was, so running `setup` twice changes nothing the second time and `setup` followed by `reset_hooks` restores the original document. The file is rewritten (atomically) only when something changed. A settings file that is not a JSON object is refused with an error and left untouched; it is never replaced by an empty one.

```text
$ h notify claude setup
Notification: added
Stop: added
~/.claude/settings.json: updated
$ h notify claude setup
Notification: already present
Stop: already present
~/.claude/settings.json: unchanged
```

Scheduled work does not use this log. A schedule with `notify: failures` or `notify: always` sends its outcome through `terminal-notifier` and records whether that delivery succeeded on the outcome (see [h schedule](h-schedule.md)).

Herdr 0.8.2 can focus the stored workspace and tab but not an arbitrary pane ID, so `jump` lands on the correct tab.
