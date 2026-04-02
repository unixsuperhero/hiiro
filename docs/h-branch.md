# h-branch

Manage, tag, search, and inspect git branches with task and PR associations stored in SQLite.

## Usage

```
h branch <subcommand> [options] [args]
```

## Subcommands

### `save`

Save the current (or named) branch to the branch store with current task, worktree, and tmux context.

**Args:** `[branch_name]`

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--tag` | `-t` | Tag to apply (repeatable) | — |

### `saved`

List saved branches, with optional filter string.

**Args:** `[filter]`

### `current`

Print the current git branch name.

### `info`

Show detailed info about the current branch: SHA, task, worktree, tmux context, ahead/behind vs main, associated PR, and note.

### `ls`

List branches (saved by default, or all local with `-a`).

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--tag` | `-t` | Filter by tag (OR when multiple, repeatable) | — |
| `--all` | `-a` | Show all local branches instead of just saved | false |

### `search`

Search saved (or all) branches by name or tag substring.

**Args:** `<term> [term2...]`

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Search all local branches | false |

### `tag`

Add tags to a branch. With `-e`, opens a YAML editor for bulk tagging.

**Args:** `[branch] <tag> [tag2...]`

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--edit` | `-e` | Open YAML editor for bulk tagging | false |

### `untag`

Remove one or more tags from a branch, or clear all tags if none specified.

**Args:** `[branch] [tag...]`

### `tags`

Show all tagged branches grouped by tag.

### `select`

Fuzzy-select a branch name from saved (or all) branches and print it.

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Select from all local branches | false |

### `copy`

Fuzzy-select a branch and copy its name to clipboard.

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Select from all local branches | false |

### `co` [alias: `checkout`]

Checkout a branch, fuzzy-selecting if no name given.

**Args:** `[branch]`

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Select from all local branches | false |

### `rm` [alias: `remove`]

Delete a branch (`git branch -d`), fuzzy-selecting if no name given.

**Args:** `[branch]`

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Select from all local branches | false |

### `rename`

Rename a branch locally and on the remote, then update the saved record.

**Args:** `<new_name> [old_name]`

### `status`

Show ahead/behind counts and associated PR state for each branch.

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Show all local branches | false |

### `merged`

List branches that have been merged into main/master.

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Show all merged branches, not just saved | false |

### `clean`

Interactively delete merged branches. With `-f`, delete all without prompting.

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Include all merged branches | false |
| `--force` | `-f` | Delete all without confirmation | false |

### `recent`

Show the N most recently visited branches from reflog.

**Args:** `[n]` (default: 10)

### `note`

Get or set a freeform note on a branch.

**Args:** `[text...]`

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--clear` | — | Clear the note | false |

### `for-task`

List saved branches associated with a given task name (or current task).

**Args:** `[task_name]`

### `for-pr` [alias: `pr`]

Print the head branch name for a tracked PR (fuzzy-select if no arg).

**Args:** `[pr_number_or_url]`

### `duplicate`

Create a new branch as a copy of the current (or specified) branch.

**Args:** `<new_name> [source_branch]`

### `push`

Push a branch to a remote with optional force and upstream tracking.

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--remote` | `-r` | Remote name | `origin` |
| `--from` | `-f` | Local branch or commit | current branch |
| `--to` | `-t` | Remote branch name | same as from |
| `--force` | `-F` | Force push | false |
| `--set-upstream` | `-u` | Set upstream tracking | false |

### `diff`

Show commit log between two refs (defaults to `main..HEAD`).

**Args:** `[from] [to]`

### `changed`

List files changed between the current branch and its upstream fork point.

**Args:** `[upstream]`

### `ahead`

Show how many commits the branch is ahead of a base.

**Args:** `[base] [branch]`

### `behind`

Show how many commits the branch is behind a base.

**Args:** `[base] [branch]`

### `log`

Show the commit log for changes since the upstream fork point.

**Args:** `[upstream]`

### `q` [alias: `query`]

Query the branches SQLite table directly. Pass a table name, `key=value` filters, or raw SQL.

**Args:** `[table|sql|key=value...]`

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Show all rows (no 50-row limit) | false |

### `forkpoint`

Print the merge-base SHA between the current branch and an upstream.

**Args:** `[upstream] [branch]`

### `ancestor`

Check whether one ref is an ancestor of another.

**Args:** `[ancestor] [descendant]`
