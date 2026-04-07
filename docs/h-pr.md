# h-pr

Track, update, view, and act on GitHub pull requests with pinned PR management and multi-PR batch operations.

## Synopsis

```bash
h pr <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `track [ref]` | Start tracking a PR |
| `ls [filters]` | List tracked PRs |
| `update [filters]` | Refresh PR statuses and list |
| `status [refs]` | Show check status for a PR |
| `view [ref]` | Show PR details via `gh pr view` |
| `open [refs]` | Open PR URL in browser |
| `number` | Print PR number for current branch |
| `link [ref]` | Print PR URL |
| `select` | Fuzzy-select from your open PRs |
| `copy` | Fuzzy-select and copy PR number to clipboard |
| `diff [ref]` | Show PR diff |
| `checkout [ref]` | Checkout a PR's branch |
| `merge [ref]` | Merge a PR |
| `sync [ref]` | Sync PR with its base branch (rebase, fallback to merge) |
| `ready [ref]` | Mark a PR as ready for review |
| `to-draft [ref]` | Convert a PR to draft |
| `fix [refs]` | Queue `/pr:fix` prompt for failing PRs |
| `comment [ref]` | Write and post a comment |
| `templates` | List comment templates |
| `new-template <name>` | Create a comment template |
| `from-template [ref]` | Post a comment from a template |
| `rm [ref]` | Stop tracking a PR |
| `prune` | Remove all merged/closed PRs from tracking |
| `check [ref]` | Run `gh pr checks` with notification on completion |
| `watch [ref]` | Watch PR checks (keeps polling until done) |
| `fwatch [ref]` | Watch PR checks with `--fail-fast` |
| `tag <ref> <tags>` | Tag a tracked PR |
| `untag <ref> [tags]` | Remove tags from a tracked PR |
| `for-task [task]` | List tracked PRs for a task |
| `branch [ref]` | Get the head branch for a tracked PR |
| `attach [ref]` | Checkout a PR's branch in its task's tmux session |
| `assigned` | List PRs assigned to you |
| `created` | List PRs authored by you |
| `missing` | List your untracked PRs |
| `amissing` | Interactively add untracked PRs to tracking |
| `green` | List PRs with all checks passing |
| `red` | List PRs with failing checks |
| `old` | List merged/closed tracked PRs |
| `draft` | List draft PRs |
| `edit` | Edit the `h-pr` bin file |

PR references (`ref`) can be a PR number, a URL containing `/pull/<number>`, or omitted to fuzzy-select from tracked PRs.

### attach

Checkout a PR's branch inside its associated task's tmux session. Creates a WIP commit if there are uncommitted changes before switching.

**Examples**

```bash
h pr attach
h pr attach 1234
```

### check / watch / fwatch

Run `gh pr checks` for a PR. `watch` keeps polling until checks complete. `fwatch` adds `--fail-fast`. On completion, speaks "pr good" or "pr bad" and sends a macOS notification.

**Examples**

```bash
h pr check
h pr watch 1234
h pr fwatch 1234
```

### fix

Queue a `/pr:fix` skill prompt for failing PRs via `h queue add`. With `-r`, launches tasks immediately.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--red` | `-r` | Fix all PRs with failing checks |
| `--run` | `-R` | Launch queue tasks immediately |

**Examples**

```bash
h pr fix
h pr fix 1234
h pr fix --red --run
```

### for-task

List tracked PRs associated with a task.

**Examples**

```bash
h pr for-task
h pr for-task my-task
```

### ls

List all tracked PRs with check status, review counts, and tags. Supports filter flags to narrow output.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--update` | `-u` | Refresh status before listing |
| `--verbose` | `-v` | Multi-line output per PR |
| `--checks` | `-C` | Show individual check run details |
| `--diff` | `-d` | Open diff for fuzzy-selected PR |
| `--all` | `-a` | Show all tracked PRs (no filters) |
| `--active` | | Only active (open) PRs |
| `--merged` | | Only merged PRs |
| `--drafts` | | Only draft PRs |
| `--red` | | Only PRs with failing checks |
| `--green` | | Only PRs with all checks passing |
| `--pending` | | Only PRs with pending checks |
| `--conflicts` | | Only PRs with merge conflicts |
| `--numbers` | | Print PR numbers only |

**Examples**

```bash
h pr ls
h pr ls --update
h pr ls --red
h pr ls --verbose --checks
```

### rm / prune

`rm` stops tracking a specific PR (fuzzy-select if no ref given). `prune` removes all merged/closed PRs from tracking at once.

**Examples**

```bash
h pr rm
h pr rm 1234
h pr prune
```
### status

Show check status counts for a PR.

**Examples**

```bash
h pr status
h pr status 1234
```

### tag / untag

Tag or untag a tracked PR. With `-e` on `tag`, opens a YAML editor for bulk-tagging multiple PRs.

**Examples**

```bash
h pr tag 1234 urgent needs-rebase
h pr tag -e
h pr untag 1234 urgent
h pr untag 1234           # clear all tags
```

### templates / new-template / from-template

Manage and use PR comment templates stored in `~/.config/hiiro/pr_templates/`.

**Examples**

```bash
h pr templates
h pr new-template lgtm
h pr from-template 1234
```

### track

Start tracking a PR. Automatically associates it with the current task/worktree/session if in a task context.

**Examples**

```bash
h pr track          # track current branch's PR (or fuzzy-select)
h pr track 1234     # track by number
```

### update

Refresh statuses for all active tracked PRs, then display the list.

**Options**

Same filters as `ls`, plus `--force-update` / `-u` to force refresh even if recently checked.

**Examples**

```bash
h pr update
h pr update --red
h pr update -U
```

