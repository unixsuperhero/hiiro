# h-wtree

Manage git worktrees with fuzzy selection, tmux session switching, and size reporting.

## Usage

```
h wtree <subcommand> [args]
```

## Subcommands

### `ls` [alias: `list`]

Run `git worktree list`.

**Args:** `[git_args...]`

### `add`

Run `git worktree add`.

**Args:** `[git_args...]`

### `lock`

Run `git worktree lock`.

**Args:** `[git_args...]`

### `move`

Run `git worktree move`.

**Args:** `[git_args...]`

### `prune`

Run `git worktree prune`.

**Args:** `[git_args...]`

### `remove`

Run `git worktree remove`.

**Args:** `[git_args...]`

### `repair`

Run `git worktree repair`.

**Args:** `[git_args...]`

### `unlock`

Run `git worktree unlock`.

**Args:** `[git_args...]`

### `switch`

Fuzzy-select a worktree and open (or create) a tmux session named after the worktree directory, starting in that directory.

**Args:** `[path]`

### `select`

Fuzzy-select a worktree and print its path.

### `size`

List all worktrees with their disk usage from `du -sh`.

### `branch`

Print the branch for each worktree, or for specific paths.

**Args:** `[path...]`

### `copy`

Fuzzy-select a worktree and copy its path to clipboard.
