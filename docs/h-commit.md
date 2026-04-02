# h-commit

Fuzzy-select a git commit SHA from the recent log.

## Usage

```
h commit <subcommand> [git-log-args]
```

## Subcommands

### `select` [alias: `sk`]

Show the last 50 commits via `git log --oneline --decorate`, open them in `sk` for fuzzy selection, and print the selected SHA. Any extra args are forwarded to `git log`.

**Args:** `[git_log_args...]`
