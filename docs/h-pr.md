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
| `attach [ref]` | Checkout a PR's branch in its task's Herdr workspace |
| `assigned` | List PRs assigned to you |
| `created` | List PRs authored by you |
| `missing` | List your untracked PRs |
| `amissing` | Interactively add untracked PRs to tracking |
| `green` | List PRs with all checks passing |
| `red` | List PRs with failing checks |
| `old` | List merged/closed tracked PRs |
| `draft` | List draft PRs |
| `edit` | Edit the `h-pr` bin file |
| `dep add <ref> <dependencies>` | Add dependencies to a tracked PR |
| `dep rm <ref> [dependencies]` | Remove dependencies or clear them all |
| `dep edit` / `config vim` | Edit tracked PR metadata in a temporary YAML document |
| `config path` | Print the canonical database location |
| `q [conditions]` | Query the canonical `prs` table |

PR references can be a PR number, a GitHub pull-request URL, or omitted to select a tracked PR. When two repositories have the same number, a bare number is an error. Use the full URL to choose the repository. Stored rows keep their database ID, slot, and pin time across metadata changes and status refreshes.

### Data ownership and record editing

SQLite owns tracked and pinned PR records in `prs`. Check rows use `check_runs.pr_id` to identify the owning PR row, so refreshes never replace another repository's checks. Legacy number-only checks remain unowned when their repository cannot be established. Each PR's raw cached check JSON can rebuild its owned check rows.

`pinned_prs.yml` is a legacy import source, not a live store. Normal PR commands neither read nor write that file. PR templates remain ordinary files.

`h pr config vim` and `h pr dep edit` edit a temporary document containing original row IDs and editable metadata. A missing field keeps its current value. An explicit null clears a field. Changed fields use the original values to detect concurrent edits, and conflicts roll back the operation. Removing a record from this document unpins only that original row, provided it has not changed concurrently. New PRs added while the editor is open remain untouched. Add a new PR with `track`, not by inventing an ID in the editor.

Cleared workspace associations stay cleared across restarts. An old `tmux_session` value seeds `herdr_workspace` only when the canonical column is first introduced; it remains available for recovery but is not a reader fallback.

The `tag -e` and `mrm` selection documents use stable row IDs with repository comments. Failed, blank, or unchanged editors do not mutate PR records. Refresh writes only fetched status, check, review, and last-check fields. It leaves local tags, dependencies, task associations, worktrees, slots, and pin times unchanged.

### attach

Checkout a PR's branch in a new tab inside its associated task's Herdr workspace. Creates a WIP commit if there are uncommitted changes before switching.

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
h pr track https://github.com/team/repo/pull/1234
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
