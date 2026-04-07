# h-branch

Manage, tag, search, and inspect git branches with task and PR associations stored in SQLite.

## Synopsis

```bash
h branch <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `save [branch]` | Save branch with task/worktree/tmux metadata |
| `saved [filter]` | List saved branches |
| `ls [filter]` | List saved branches with tags |
| `current` | Print current branch name |
| `info` | Show full info for current branch |
| `search <term>` | Search saved branches by name or tag |
| `status` | Show ahead/behind and PR status for branches |
| `recent [n]` | Show recently visited branches from reflog |
| `tag [branch] <tags>` | Tag a branch |
| `untag [branch] [tags]` | Remove tags from a branch |
| `tags` | List all tagged branches grouped by tag |
| `select` | Fuzzy-select a branch and print its name |
| `copy` | Fuzzy-select a branch and copy to clipboard |
| `co` / `checkout [branch]` | Fuzzy-select and checkout a branch |
| `rm` / `remove [branch]` | Delete a branch |
| `rename <new> [old]` | Rename branch (locally and on remote) |
| `push [args]` | Push branch to remote |
| `diff [from] [to]` | Show commits between branches |
| `changed [upstream]` | Show files changed since fork point |
| `ahead [base] [branch]` | Show how many commits ahead of base |
| `behind [base] [branch]` | Show how many commits behind base |
| `log [upstream]` | Show commits since fork point |
| `forkpoint [upstream] [branch]` | Print fork point SHA |
| `ancestor [ancestor] [descendant]` | Test if one commit is an ancestor of another |
| `merged` | List merged branches |
| `clean` | Delete merged branches |
| `duplicate <new> [source]` | Create a copy of a branch |
| `for-task [task]` | List branches saved for a task |
| `for-pr` / `pr [ref]` | Get branch name for a PR |
| `note [text]` | Get or set a note on the current branch |
| `q` / `query [args]` | Query the branches SQLite table |
| `edit` | Edit the `h-branch` bin file |

### changed

Show files changed since the fork point from main/master.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Show all changed files (not just relative to cwd) |

**Examples**

```bash
h branch changed
h branch changed main
h branch changed --all
```

### clean

Interactively select merged branches to delete. With `-f`, deletes all without prompting.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Include all merged (not just saved) |
| `--force` | `-f` | Delete all without confirmation |

**Examples**

```bash
h branch clean
h branch clean --all --force
```

### co / checkout

Fuzzy-select and checkout a branch. Pass a branch name to skip the picker.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Select from all local branches |

**Examples**

```bash
h branch co
h branch co my-feature
```

### copy

Fuzzy-select a branch and copy its name to the clipboard.

**Examples**

```bash
h branch copy
```

### diff

Show commits between two branches. With no arguments, diffs from main/master to HEAD.

**Examples**

```bash
h branch diff
h branch diff main
h branch diff main my-feature
```

### for-pr / pr

Get the branch name for a tracked PR. With no arg, uses fuzzy select.

**Examples**

```bash
h branch for-pr 1234
h branch pr
```

### for-task

List saved branches associated with a task.

**Examples**

```bash
h branch for-task my-task
h branch for-task   # uses current task
```

### info

Show full metadata for the current branch: SHA, task, worktree, tmux context, commits ahead/behind base, any associated PR, and note.

**Examples**

```bash
h branch info
```

### ls

List saved branches with task and tag info. With `-a`, shows all local git branches instead.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Show all local branches |
| `--tag` | `-t` | Filter by tag (repeatable, OR logic) |

**Examples**

```bash
h branch ls
h branch ls --all
h branch ls -t urgent
```

### merged

List branches that have been merged into main/master.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Show all merged branches (not just saved) |

**Examples**

```bash
h branch merged
h branch merged --all
```

### note

Get or set a short note on the current branch. With `--clear`, removes the note.

**Options**

| Flag | Description |
|------|-------------|
| `--clear` | Remove the note |

**Examples**

```bash
h branch note
h branch note "waiting for review"
h branch note --clear
```

### push

Push a branch to a remote.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--remote` | `-r` | Remote name | `origin` |
| `--from` | `-f` | Local branch or commit to push | current branch |
| `--to` | `-t` | Remote branch name | same as local |
| `--force` | `-F` | Force push | false |
| `--set-upstream` | `-u` | Set upstream tracking | false |

**Examples**

```bash
h branch push
h branch push -r origin -F
h branch push --from my-branch --to feature/my-branch
```

### q / query

Query the `branches` SQLite table directly. Pass a SQL string or `key=value` filters.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Show all rows (no 50-row limit) |

**Examples**

```bash
h branch q
h branch q task=my-task
h branch q "SELECT name, task FROM branches WHERE task IS NOT NULL"
```
### recent

Show recently visited branches from `git reflog`. Marks saved branches and shows tags.

**Examples**

```bash
h branch recent
h branch recent 20
```

### rename

Rename a branch locally and on the remote (if configured). Also updates any saved branch record.

**Examples**

```bash
h branch rename new-name
h branch rename new-name old-name
```

### save

Save the current (or named) branch with metadata: task name, worktree, tmux session/window/pane, HEAD SHA. Creates or updates a record in the branches table.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--tag` | `-t` | Tag to apply (repeatable) |

**Examples**

```bash
h branch save
h branch save my-feature-branch
h branch save -t important -t wip
```

### search

Search saved branches (or all local branches with `-a`) by name substring or tag.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Search all local branches |

**Examples**

```bash
h branch search my-feature
h branch search -a refactor
```

### select

Fuzzy-select from saved branches (or all with `-a`) and print the name.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Select from all local branches |

**Examples**

```bash
h branch select
branch=$(h branch select)
```

### status

Show ahead/behind counts (vs main/master) and associated PR status for saved branches.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Show all local branches |

**Examples**

```bash
h branch status
h branch status --all
```

### tag

Tag a branch. With no branch name, uses the current branch. With `-e`, opens a YAML editor for bulk tagging.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--edit` | `-e` | Bulk-tag mode via YAML editor |

**Examples**

```bash
h branch tag my-branch important wip
h branch tag urgent
h branch tag -e
```

### untag

Remove tags from a branch. With no tags, clears all tags.

**Examples**

```bash
h branch untag my-branch urgent
h branch untag
```

