# h remind

Reminders stored in SQLite (`reminders`), delivered through `terminal-notifier` by the one-shot `h remind check`.

## Synopsis

```bash
h remind add 'message' <time> [sound]     # one-time when <time> is 15m / 2h / YYYYmmddHHMM
h remind once 'message' <time> [sound]
h remind every 'message' <interval> [sound]
h remind ls
h remind pause|resume|remove [ID]
h remind check [-v]
h remind clean
h remind add | editall                    # edit through a temporary YAML document
h remind howto
```

IDs are stable database IDs. A reminder keeps its message, interval, sound, enabled/once flags, trigger time, and last-triggered checkpoint across edits and restarts.

## Checking

`h remind check` delivers every due reminder once and records each attempt:

- A one-time reminder is due at its `trigger_at`; it is disabled once delivered.
- A recurring reminder is due on its first check, then `interval` after its last delivery.
- Each due reminder's occurrence is claimed (`reminder:ID`, keyed by the trigger time, the end of the current interval, or `first:CREATED_AT`), so two overlapping checks deliver it once; the other check records `skipped-overlap`.
- The checkpoint (`last_triggered`) advances only after `terminal-notifier` succeeded. A failed delivery is recorded as `failed` (`notification delivery failed; retried on the next check`), the reminder stays due, the next check retries it (attempt 2), and `check` exits 1.

```js
// h remind check -v with the notifier failing, then working
{ definition: "reminder:3", occurrence: "2026-01-01T13:00:00+00:00", attempt: 1, outcome: "failed" }
{ definition: "reminder:3", occurrence: "2026-01-01T13:00:00+00:00", attempt: 2, outcome: "completed", detail: "delivered" }
```

A crash after a notification is shown but before its checkpoint is written can show it again on the next check: delivery is at least once, not exactly once. `h schedule status reminder:` lists every attempt.

## Scheduling

Nothing runs by itself. Define the check as a schedule and enable it explicitly:

```yaml
# ~/.config/hiiro/schedules.yml
reminders:
  job: reminders
  every: 1m
```

```bash
h schedule plan reminders
h schedule enable reminders
h schedule disable reminders
```

The former crontab line (`* * * * * h remind check`) is no longer suggested; an existing crontab entry still works but records nothing about the check itself.

## See also

[h schedule](h-schedule.md), [h db](h-db.md) (reminder ownership and migration)
