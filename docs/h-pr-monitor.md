# h-pr-monitor

Watch tracked PRs and notify once per check, review, or dependency change, from the same snapshots `h pr` stores.

## Synopsis

```bash
h pr-monitor [options]
```

## Description

Each cycle refreshes every tracked open PR (`h pr track`) through the snapshot path that `h pr update -u` uses, then compares what it observed with the monitor's checkpoints:

```js
const observation = { ref: "team/one#42", headSha: "bbbb…", checks: "failing", review: "approved", dependencies: "waiting" };
const checkpoint  = { ref: "team/one#42", channel: "checks", headSha: "aaaa…", state: "pending", deliveredAt: "2026-10-13T18:00:58Z" };
// → event { channel: "checks", from: "pending", to: "failing", headSha: "bbbb…" } → one notification
```

- **Baseline.** The first time a PR (or a channel) is seen, its state is recorded and nothing is sent.
- **Channels.** `checks` (`pending`, `failing`, `passing`, `none`), `review` (`review_required`, `approved`, `changes_requested`), `dependencies` (`waiting`, `satisfied`; only PRs with dependencies), plus `fix` and `ready` when enabled. A check state belongs to one head revision, so a new head is a new event even in the same state; a review decision or dependency state is compared by state alone.
- **Evidence.** A stale or never-observed snapshot is `unknown` everywhere. An incomplete check list is `failing` when a failure was seen and `unknown` otherwise; reviews count only when every review page was fetched. `unknown` never produces an event, so a partial list of successes is never `passing` and a partial review list is never `approved`.
- **Delivery.** A checkpoint is written only after its effect succeeded, so a failed notification or queue addition is tried again next cycle and a repeated observation, or a restart, sends nothing. Checkpoints live in the `pr_monitor_checkpoints` table (`repo`, `number`, `channel`, `head_sha`, `state`, `observed_at`, `delivered_at`, `detail`).
- **Dependencies** become `satisfied` when every `owner/name#N` dependency is tracked and observed merged. That only notifies; nothing is merged.
- **Fix queueing** (`--queue-fixes`) adds one `h queue` job per failing head revision (`pr-fix-team-one-42-bbbbbbb`), the same job `h pr fix` writes. Jobs are only queued; run them with `h queue run`.
- **Mark ready** (`--mark-ready`) runs `gh pr ready` once for a draft whose head has a fresh, complete, passing check list.

Notifications use the `h alert` adapter (`terminal-notifier -title … -message … -open URL`). Each cycle prints its events:

```text
--- 2026-10-13 14:01:10
team/one#42 checks baseline pending at aaaaaaa: baseline
team/one#42 checks pending → failing at aaaaaaa: notified
team/one#42 fix pending → failing at aaaaaaa: queued pr-fix-team-one-42-aaaaaaa
team/two#5 dependencies waiting → satisfied at bbbbbbb: notified
```

## Options

| Flag | Long | Description | Default |
|------|------|-------------|---------|
| `-a` | `--no-notify-approvals` | No review notifications | notify |
| `-s` | `--no-notify-status` | No check notifications | notify |
| `-D` | `--no-notify-dependencies` | No dependency notifications | notify |
| `-u` | `--no-notify-publishing` | No notification when marking ready | notify |
| `-r` | `--mark-ready` | Mark a draft ready when its head passes | off |
| `-q` | `--queue-fixes` | Queue one fix job per failing head | off |
| `-t` | `--tag TAG` | Only tracked PRs with this tag (repeatable) | all |
| `-1` | `--once` | One cycle, then exit | loop |
| `-i` | `--interval SECONDS` | Seconds between cycles | `SLEEP_FOR` or 60 |
| `-h` | `--help` | Print help | — |

Ctrl-C exits with status 130.

## Examples

```bash
h pr-monitor
h pr-monitor --queue-fixes -t mine
h pr-monitor --once
SLEEP_FOR=30 h pr-monitor --mark-ready
```

## See also

[h-pr](h-pr.md) (`track`, `update`, `fix`, `check`/`watch` for waiting in the foreground)
