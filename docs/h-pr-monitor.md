# h-pr-monitor

Poll `gh pr status` in a loop and send macOS notifications when PR check status or approval counts change.

## Synopsis

```bash
h pr-monitor [options]
```

## Description

Runs in a loop (default: every 60 seconds, configurable via `SLEEP_FOR` env var), fetching PR status for your open PRs. Sends macOS notifications via external scripts (`pr_approved`, `pr_passing`, `pr_failing`, `pr_pending`, `pr_publishing`) when status or approval counts change.

With `--mark-ready`, automatically calls `gh pr ready` and opens the PR in the browser when checks pass.

## Options

| Flag | Long | Description | Default |
|------|------|-------------|---------|
| `-a` | `--no-notify-approvals` | Disable approval notifications | notify enabled |
| `-s` | `--no-notify-status` | Disable status change notifications | notify enabled |
| `-u` | `--no-notify-publishing` | Disable "publishing as ready" notifications | notify enabled |
| `-r` | `--mark-ready` | Auto-mark PR as ready when checks pass | disabled |
| `-h` | `--help` | Print help | — |

## Environment

| Variable | Description | Default |
|----------|-------------|---------|
| `SLEEP_FOR` | Polling interval in seconds | `60` |

## Examples

```bash
h pr-monitor
h pr-monitor --mark-ready
h pr-monitor --no-notify-approvals -s
SLEEP_FOR=30 h pr-monitor
```
