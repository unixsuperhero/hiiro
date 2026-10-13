# h schedule

Run existing one-shot workers (reminders, the queue, the PR monitor, loop recipes, or a command) on a recurrence, through launchd, with every run's outcome recorded. Nothing is registered until you run `h schedule enable NAME`.

## Synopsis

```bash
h schedule ls
h schedule plan NAME [--plist]
h schedule enable NAME
h schedule disable NAME
h schedule run NAME [--scheduled]
h schedule status [NAME | PREFIX:] [-n N]
h schedule ui [PREFIX]
h schedule path
```

## Definitions

Definitions live in `~/.config/hiiro/schedules.yml` (a definitions file: Hiiro reads it and never rewrites it). Each loop recipe in `~/ai/loops/NAME/config.yml` is also the definition `loop-NAME` (see [h loop](h-loop.md)).

```yaml
reminders:              # h remind check
  job: reminders
  every: 1m
pr-watch:               # h pr-monitor --once ARGS
  job: pr-monitor
  every: 5m
  args: [--queue-fixes, -t, mine]
queue:                  # h queue tick --max N; launches agents, so agent: true is required
  job: queue
  every: 1m
  agent: true
  max_running: 2
nightly:                # any argv; the executable is resolved to an absolute path
  job: command
  command: [backup, --quick]
  at: "02:30"
  timezone: America/New_York
  missed: run_once
  timeout: 30m
  cwd: ~/work
  env: { PATH: /usr/local/bin:/usr/bin:/bin }
  notify: failures
  artifacts: [out/report.txt]
```

Loaded, a definition is:

```js
{ name: "nightly", job: "command", recurrence: "wall_clock", every: null, at: [2, 30],
  timezone: "America/New_York", missed: "run_once", grace: 3600, max_concurrent: 1, timeout: 1800,
  program: ["/usr/local/bin/backup", "--quick"], cwd: "/Users/me/work", env: { PATH: "…" },
  notify: "failures", keep_logs: false, artifacts: ["out/report.txt"], agent: false }
// enabled lives in the schedule_checkpoints row, set only by enable/disable
```

| Field | Meaning | Default |
|---|---|---|
| `job` | `reminders`, `queue`, `pr-monitor`, `command`, `loop` | required |
| `every` / `at` | exactly one: an interval (`30s`, `5m`, `1h`, `1d`) or a wall-clock `HH:MM` | required |
| `timezone` | `local` or an IANA name, for `at` | `local` |
| `missed` | `run_once` (run the latest missed occurrence once) or `skip` (skip it when later than `grace`) | `run_once` |
| `grace` | how late an occurrence may start under `missed: skip` | the interval, or 1h |
| `max_concurrent` | runs of this schedule at once; more are `skipped-overlap` | 1 |
| `timeout` | a run longer than this is stopped (TERM, then KILL) and recorded `interrupted` | 10m |
| `command` / `args` / `max_running` | per job, see above | |
| `cwd`, `env` | the run's directory and extra environment | `~`, none |
| `notify` | `never`, `failures`, `always` | `never` |
| `keep_logs` | keep the log of a completed run too | false (true for loops) |
| `artifacts` | paths (relative to `cwd`) recorded on the outcome when present | none |
| `agent` | required `true` for `queue`; a loop's `agent:` argv | |

An invalid definition is listed by `h schedule ls` with its reason and never runs. Permission-bypass flags (`--dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`, `--yolo`, `bypassPermissions`) are refused in any recurring command.

## Occurrences, claims, and outcomes

An occurrence is the latest scheduled time at or before now:

- **Interval:** epoch-aligned slots, keyed by their UTC start (`every: 15m` at 12:14:59 → `2026-10-13T12:00:00Z`).
- **Wall clock:** keyed by the configured local date and time (`2026-11-01 01:30 America/New_York`). A time that repeats when clocks fall back is one occurrence (its first instant); a time skipped when clocks spring forward still runs once that day, after the gap. Interval schedules are unaffected by DST.
- **Missed runs** (the Mac was asleep or off): only the latest occurrence is considered; earlier ones are never backfilled. `run_once` runs it; `skip` records it as skipped in the checkpoint when it is later than `grace`.
- **Restart:** nothing is kept in memory. Each run reads the checkpoint, so a reboot or reload neither repeats a finished occurrence nor forgets one.

Every run claims its occurrence in `job_claims` (unique per definition and occurrence) before starting. A second worker for the same occurrence, or one past `max_concurrent`, records `skipped-overlap` and starts nothing. A claim whose worker and process are both gone is settled by the next worker: with the run's real outcome when the supervisor recorded one, else `stale-owner`, after which the occurrence is claimed again (attempt 2). The command runs under the owned-run supervisor ([owned runs](owned-runs.md)) in its own process group, with stdout and stderr in `~/.local/share/hiiro/jobs/NAME/RUN_ID.log`.

Each run ends in one `job_outcomes` row:

```js
{ run_id: "run-20261013120000-ab12cd34", definition: "nightly", occurrence: "2026-10-13 02:30 America/New_York", attempt: 1,
  context: { trigger: "launchd", job: "command", late_seconds: 12, cwd: "/Users/me/work", command: "/usr/local/bin/backup --quick" },
  started_at: "…", finished_at: "…", outcome: "failed", exit_code: 3, signal: null, detail: "exit 3",
  log_path: "~/.local/share/hiiro/jobs/nightly/run-….log", artifacts: [{ path: "/Users/me/work/out/report.txt", bytes: 120 }],
  notification: "delivered" }
```

| Outcome | When |
|---|---|
| `completed` | exit 0 (its log is deleted unless `keep_logs`) |
| `failed` | nonzero exit |
| `interrupted` | a signal, the timeout, or the worker itself was stopped |
| `startup-failed` | the command never started (missing executable, bad cwd) |
| `stale-owner` | the worker and its process disappeared before recording an outcome |
| `skipped-overlap` | the occurrence was held by another worker, or `max_concurrent` were running |

The checkpoint (`schedule_checkpoints`) then records the occurrence and its outcome. Success is only ever an observed exit 0; a live terminal or a finished worker never marks a task or queue entry done.

Notifications (`notify: failures|always`) are sent after the outcome is recorded; whether delivery worked is stored in `notification` (`delivered` or `failed`) and never changes the outcome. A crash between a run's end and its record is reconciled by the next run; a crash between a notification and its record can repeat that notification. Delivery is at least once, not exactly once.

## launchd

`enable` writes `~/Library/LaunchAgents/LABEL.plist` and runs `launchctl bootstrap gui/UID PLIST`; the label is `com.hiiro.schedule.NAME` (`HIIRO_LAUNCHD_PREFIX` changes the prefix). The plist runs `ruby -I LIB …/bin/h-schedule run NAME --scheduled` with absolute paths, the definition's `cwd`, and only `HOME`, `LANG`, `PATH` plus the definition's `env`. launchd wakes it every `every` seconds (every 60 seconds for wall-clock schedules, which then run only when an occurrence is due); its own output goes to `~/.local/share/hiiro/schedules/NAME.launchd.log`. If bootstrap fails the plist is removed, the error is printed, and the schedule stays disabled. `disable` runs `launchctl bootout gui/UID/LABEL` and removes that plist. No other file in LaunchAgents and no other label is read or changed.

`run NAME --scheduled` does nothing unless the schedule is enabled, so a leftover plist cannot run a disabled schedule. `run NAME` without it is a manual run of the current occurrence.

```text
$ h schedule plan reminders
label:     com.hiiro.schedule.reminders
plist:     /Users/me/Library/LaunchAgents/com.hiiro.schedule.reminders.plist
program:   /…/ruby -I /…/lib /…/bin/h-schedule run reminders --scheduled
runs:      /…/ruby -I /…/lib /…/bin/h-remind check
…
$ h schedule enable reminders
Enabled reminders as com.hiiro.schedule.reminders (/Users/me/Library/LaunchAgents/com.hiiro.schedule.reminders.plist)
$ h schedule status reminders
reminders: enabled; launchd state=not running, runs=3, last exit code=0
```

## Viewing outcomes

`h schedule status [NAME]` lists recorded outcomes, newest first, with failed logs and artifacts; with a schedule name it also shows its launchd registration and checkpoint. A prefix such as `reminder:` or `loop-` selects a group.

`h schedule ui [PREFIX]` is the same records on the TUI toolkit: one row per outcome and a detail pane with the log tail. It re-reads the records every `HIIRO_UI_REFRESH` seconds (default 5) while no key is pressed; the search query, the selected row, and the scroll position stay as they were (`r` reloads at once).

## See also

[h remind](h-remind.md), [h loop](h-loop.md), [h queue](h-queue.md) (`tick`), [h pr-monitor](h-pr-monitor.md), [owned runs](owned-runs.md)
