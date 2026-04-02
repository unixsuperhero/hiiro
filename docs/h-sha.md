# h-sha

Fuzzy-select, show, and copy git commit SHAs.

## Usage

```
h sha <subcommand> [args]
```

## Subcommands

### `select`

Show the last 100 commits via `git log --oneline`, fuzzy-select one, and print its SHA.

**Args:** `[git_log_args...]`

### `ls`

List recent commits via `git log --oneline`.

**Args:** `[git_log_args...]`

### `show`

Run `git show` on a SHA. If no SHA is given, runs `h sha select` interactively.

**Args:** `[sha] [git_show_args...]`

### `copy`

Copy a SHA to clipboard. If no SHA is given, runs `h sha select` interactively.

**Args:** `[sha]`
