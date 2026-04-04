# h-pr-monitor

Poll `gh pr status` in a loop and send macOS notifications when PR check status or approval counts change.

## Synopsis

```bash
h pr-monitor [options]
```

This command runs indefinitely, polling every 60 seconds (or the value of the `$sleep_for` environment variable). It parses the output of `gh pr status` to track PRs created by you, watching for changes in check status (`pending`, `passing`, `failing`) and approval counts.

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `-a`, `--no-notify-approvals` | Disable notifications for new approvals | notify enabled |
| `-s`, `--no-notify-status` | Disable notifications for check status changes | notify enabled |
| `-u`, `--no-notify-publishing` | Disable notification when marking PR ready | notify enabled |
| `-r`, `--mark-ready` | Automatically mark PR as ready when checks pass | false |
| `-h`, `--help` | Print help | — |

## Behavior

On each poll cycle:

1. Runs `gh pr status` and parses PRs created by you
2. Compares current check statuses and approval counts against the previous poll
3. Fires shell scripts for status transitions:
   - `pr_passing` — checks just turned green
   - `pr_failing` — checks just failed
   - `pr_pending` — checks went back to pending
   - `pr_approved` — approval count increased
   - `pr_publishing` — about to mark PR as ready (with `--mark-ready`)
4. With `--mark-ready`: automatically calls `gh pr ready <number>` when checks pass

The notification scripts (`pr_approved`, `pr_passing`, etc.) must exist in your `$PATH`.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `$sleep_for` | Poll interval in seconds | `60` |

## Examples

```bash
# Monitor PRs with all notifications (default)
h pr-monitor

# Only notify on check status changes, not approvals
h pr-monitor -a

# Auto-mark PR ready when checks pass
h pr-monitor -r

# Faster polling for active development
sleep_for=15 h pr-monitor

# Run in background
h bg run h pr-monitor
```
