# h-wtree

Manage git worktrees with fuzzy selection, tmux session switching, and disk usage reporting.

## Synopsis

```bash
h wtree <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ls [args]` | List all worktrees |
| `list [args]` | Alias for `ls` |
| `add [args]` | Add a worktree |
| `lock [args]` | Lock a worktree |
| `unlock [args]` | Unlock a worktree |
| `move [args]` | Move a worktree |
| `prune [args]` | Prune stale worktree references |
| `remove [args]` | Remove a worktree |
| `repair [args]` | Repair worktree references |
| `switch [path]` | Switch to a worktree's tmux session |
| `select` | Fuzzy-select a worktree and print its path |
| `copy` | Fuzzy-select a worktree and copy path to clipboard |
| `branch [paths]` | Print branch name(s) for worktree path(s) |
| `size` | Show disk usage for each worktree |

All passthrough subcommands (`ls`, `add`, `lock`, etc.) forward extra arguments to `git worktree`.

### ls / list

List all worktrees via `git worktree list`.

**Examples**

```bash
h wtree ls
h wtree list
```

### switch

Fuzzy-select a worktree and open/create a tmux session named after its directory, starting from that directory.

**Examples**

```bash
h wtree switch
h wtree switch /path/to/worktree
```

### select

Fuzzy-select a worktree and print its absolute path.

**Examples**

```bash
h wtree select
path=$(h wtree select)
```

### copy

Fuzzy-select a worktree and copy its path to the clipboard.

**Examples**

```bash
h wtree copy
```

### branch

Print branch names for worktree paths. With no arguments, lists all worktrees with their branch. With paths, prints the branch for each given path.

**Examples**

```bash
h wtree branch
h wtree branch /path/to/worktree
```

### size

Show disk usage for each worktree using `du -sh`.

**Examples**

```bash
h wtree size
```

### add

Add a new worktree. Arguments are forwarded to `git worktree add`.

**Examples**

```bash
h wtree add /path/to/new-worktree my-feature-branch
h wtree add -b new-branch /path/to/new-worktree
```

### remove / prune

Remove or prune worktrees. Arguments forwarded to `git worktree`.

**Examples**

```bash
h wtree remove /path/to/worktree
h wtree prune
```
