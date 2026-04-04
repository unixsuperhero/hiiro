# h-wtree

Manage git worktrees with fuzzy selection, tmux session switching, and disk usage reporting.

## Synopsis

```bash
h wtree <subcommand> [args]
```

All git-native subcommands (`ls`, `add`, `lock`, etc.) are thin wrappers over `git worktree <subcmd>` and pass all args through directly.

## Subcommands

| Subcommand | Aliases | Description |
|------------|---------|-------------|
| `ls` | `list` | Run `git worktree list` |
| `add` | — | Run `git worktree add` |
| `lock` | — | Run `git worktree lock` |
| `move` | — | Run `git worktree move` |
| `prune` | — | Run `git worktree prune` |
| `remove` | — | Run `git worktree remove` |
| `repair` | — | Run `git worktree repair` |
| `unlock` | — | Run `git worktree unlock` |
| `switch` | — | Fuzzy-select a worktree and open/create a tmux session |
| `select` | — | Fuzzy-select a worktree and print its path |
| `size` | — | List worktrees with disk usage |
| `branch` | — | Print the branch for each worktree |
| `copy` | — | Fuzzy-select a worktree and copy path to clipboard |

## Subcommand Details

### `ls` / `list`

Run `git worktree list`. Extra args forwarded to git.

```bash
h wtree ls
h wtree ls --porcelain
```

### `add`

Add a new worktree. Args forwarded to `git worktree add`.

```bash
h wtree add ../my-feature my-feature
h wtree add ../hotfix -b hotfix/urgent main
```

### `switch`

Fuzzy-select a worktree and open (or create) a tmux session named after the worktree's directory basename, starting in that directory.

```bash
h wtree switch
h wtree switch /Users/josh/work/.bare/my-feature
```

### `select`

Fuzzy-select a worktree and print its path.

```bash
path=$(h wtree select)
cd "$path"
```

### `size`

List all worktrees with their disk usage from `du -sh`.

```bash
h wtree size
# 1.2G   /Users/josh/work/.bare/main  [main]
# 456M   /Users/josh/work/.bare/feature  [feature/new-thing]
```

### `branch`

Print the branch for each worktree, or for specific paths.

```bash
h wtree branch
h wtree branch /path/to/worktree1 /path/to/worktree2
```

### `copy`

Fuzzy-select a worktree and copy its path to clipboard.

```bash
h wtree copy
```

### `prune`

Remove stale worktree records (for worktrees that no longer exist on disk).

```bash
h wtree prune
```

## Examples

```bash
# Create a new worktree for a branch
h wtree add ../feature/new-thing feature/new-thing

# Switch to a worktree's tmux session
h wtree switch

# Check disk usage of all worktrees
h wtree size

# Copy a worktree path to clipboard
h wtree copy

# Clean up stale entries
h wtree prune
```
