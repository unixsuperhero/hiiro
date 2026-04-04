# h-branch

Manage, tag, search, and inspect git branches with task and PR associations stored in SQLite.

## Synopsis

```bash
h branch <subcommand> [options] [args]
```

Branch records are stored in `~/.config/hiiro/hiiro.db` (table: `branches`). Each record captures the branch name, associated task, worktree, tmux context, and HEAD SHA at save time.

## Subcommands

| Subcommand | Aliases | Description |
|------------|---------|-------------|
| `save` | — | Save current branch with task/worktree context |
| `saved` | — | List saved branches |
| `current` | — | Print current git branch name |
| `info` | — | Show detailed info about current branch |
| `ls` | — | List branches with tags and task info |
| `search` | — | Search branches by name or tag |
| `tag` | — | Add tags to a branch |
| `untag` | — | Remove tags from a branch |
| `tags` | — | Show branches grouped by tag |
| `select` | — | Fuzzy-select a branch name |
| `copy` | — | Fuzzy-select a branch and copy name to clipboard |
| `co` | `checkout` | Checkout a branch |
| `rm` | `remove` | Delete a branch |
| `rename` | — | Rename branch locally and on remote |
| `status` | — | Show ahead/behind and PR state |
| `merged` | — | List merged branches |
| `clean` | — | Delete merged branches interactively |
| `recent` | — | Show N most recently visited branches from reflog |
| `note` | — | Get or set a freeform note on a branch |
| `for-task` | — | List branches for a given task |
| `for-pr` | `pr` | Print head branch for a tracked PR |
| `duplicate` | — | Create a copy of current branch |
| `push` | — | Push branch with options |
| `diff` | — | Show commit log between two refs |
| `changed` | — | List files changed since upstream fork point |
| `ahead` | — | Show how many commits ahead of a base |
| `behind` | — | Show how many commits behind a base |
| `log` | — | Show commits since upstream fork point |
| `q` | `query` | Query branches SQLite table directly |
| `forkpoint` | — | Print merge-base SHA |
| `ancestor` | — | Check if one ref is ancestor of another |

## Options

### `save`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--tag` | `-t` | Tag to apply (repeatable) | — |

### `ls`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--tag` | `-t` | Filter by tag (OR when multiple, repeatable) | — |
| `--all` | `-a` | Show all local branches instead of just saved | false |

### `search`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--all` | `-a` | Search all local branches | false |

### `tag`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--edit` | `-e` | Open YAML editor for bulk tagging | false |

### `select` / `copy` / `co` / `rm`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--all` | `-a` | Include all local branches | false |

### `status`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--all` | `-a` | Show all local branches | false |

### `merged`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--all` | `-a` | Show all merged, not just saved | false |

### `clean`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--all` | `-a` | Include all merged branches | false |
| `--force` | `-f` | Delete all without confirmation | false |

### `push`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--remote` | `-r` | Remote name | `origin` |
| `--from` | `-f` | Local branch or commit | current branch |
| `--to` | `-t` | Remote branch name | same as `--from` |
| `--force` | `-F` | Force push | false |
| `--set-upstream` | `-u` | Set upstream tracking | false |

### `note`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--clear` | — | Clear the note | false |

### `q` / `query`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--all` | `-a` | Show all rows (no 50-row limit) | false |

## Subcommand Details

### `save`

Save the current (or named) branch to the branch store, capturing current task, worktree, tmux session/window/pane, and HEAD SHA. Updates the record if the branch is already saved.

```bash
h branch save
h branch save feature/my-branch
h branch save -t my-task -t experiment
```

### `info`

Show full details for the current branch: SHA, task, worktree, tmux context, ahead/behind vs main, note, and associated PR (if tracked).

```bash
h branch info
```

### `ls`

List saved branches (or all local with `-a`), with task annotation and tag badges. Filter by tag with `-t`.

```bash
h branch ls
h branch ls -a
h branch ls -t my-task
h branch ls -t feature -t experiment
```

### `tag`

Add tags to a branch. With `-e`, opens a YAML editor for bulk tagging multiple branches at once.

```bash
h branch tag my-feature-branch experiment
h branch tag -t feature               # tag current branch
h branch tag -e                       # bulk edit mode
```

### `push`

Push a branch with fine-grained control over remote, refs, force, and upstream tracking.

```bash
h branch push
h branch push -F                      # force push current branch
h branch push -r upstream -t main     # push current to upstream/main
h branch push -u                      # push and set upstream
```

### `q` / `query`

Query the branches table directly. Accepts a table name, `key=value` filters, or raw SQL.

```bash
h branch q
h branch q task=my-task
h branch q "SELECT name, task FROM branches WHERE name LIKE '%feat%'"
```

## Examples

```bash
# Save current branch when starting work
h branch save -t my-new-feature

# Check status of all saved branches
h branch status

# Find branches for current task
h branch for-task

# Clean up merged branches interactively
h branch clean

# Push with force and set upstream
h branch push -F -u

# Get the branch for PR #42
h branch for-pr 42
```
