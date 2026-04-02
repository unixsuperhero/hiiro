# h-pr-monitor

Poll `gh pr status` in a loop and send macOS notifications when PR check status or approval counts change.

## Usage

```
h pr-monitor [options]
```

This command runs indefinitely, polling every 60 seconds (or `$sleep_for` env var).

## Options

| Flag | Description | Default |
|---|---|---|
| `-a`, `--no-notify-approvals` | Disable notifications for new approvals | notify enabled |
| `-s`, `--no-notify-status` | Disable notifications for check status changes | notify enabled |
| `-u`, `--no-notify-publishing` | Disable notification when marking PR ready | notify enabled |
| `-r`, `--mark-ready` | Automatically mark PR as ready when checks pass | false |
| `-h`, `--help` | Print help | — |

## Notes

Notifications are sent via shell scripts `pr_approved`, `pr_passing`, `pr_failing`, `pr_pending`, and `pr_publishing` — these must exist in PATH. When `--mark-ready` is enabled and checks pass, `gh pr ready <number>` is called automatically.
