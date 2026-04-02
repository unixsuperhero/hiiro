# h-pr

Track, update, view, and act on GitHub pull requests with pinned PR management and multi-PR batch operations.

## Usage

```
h pr <subcommand> [options] [args]
```

## Subcommands

### `check`

Run `gh pr checks` on a PR and send a macOS notification when done.

**Args:** `[pr_number]`

### `watch`

Run `gh pr checks --watch` on a PR and notify when complete.

**Args:** `[pr_number]`

### `fwatch`

Run `gh pr checks --watch --fail-fast` and notify.

**Args:** `[pr_number]`

### `number`

Print the PR number for the current branch.

### `link`

Print the URL for a PR (from pinned store or `gh pr view`).

**Args:** `[pr_number_or_ref]`

### `open`

Open a PR in the browser. With no arg, opens the current branch's PR.

**Args:** `[pr_number_or_ref...]`

### `view`

Run `gh pr view` on a PR.

**Args:** `[pr_number_or_ref]`

### `select`

Fuzzy-select from your open PRs and print the PR number.

### `copy`

Fuzzy-select from your open PRs and copy the number to clipboard.

### `track`

Start tracking a PR: fetch its info, tag it with current task/worktree context, and add it to the pinned store.

**Args:** `[pr_number|-]`

### `ls`

List tracked PRs with check status, review counts, and state.

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--update` | `-u` | Refresh status before listing | false |
| `--verbose` | `-v` | Multi-line output per PR | false |
| `--checks` | `-C` | Show individual check run details | false |
| `--diff` | `-d` | Open diff for fuzzy-selected PR | false |
| `--all` | `-a` | Show all tracked PRs without filter | false |

### `status`

Show check status summary for a PR (or the current branch's PR).

**Args:** `[pr_number_or_ref...]`

### `update`

Refresh check status and reviews for all active tracked PRs, then display the list.

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--force-update` | `-u` | Force refresh even if recently checked | false |
| `--all` | `-a` | Show all tracked PRs | false |

### `green`

List tracked PRs with all checks passing.

### `red`

List tracked PRs with failing checks.

### `old`

List merged/closed tracked PRs.

### `prune`

Remove all merged and closed PRs from tracking.

### `draft`

List tracked PRs that are in draft state.

### `assigned`

List open PRs assigned to you, indicating which are already tracked.

### `created`

List open PRs created by you, indicating which are already tracked.

### `missing`

List your open/assigned PRs that are not yet tracked.

### `amissing`

Interactively add untracked PRs: opens a YAML editor pre-filled with untracked PR numbers; save to track selected ones.

### `attach`

Open a new tmux window in the PR's task session, checkout the PR branch (committing any WIP first).

**Args:** `[pr_number_or_ref]`

### `rm`

Remove a PR from tracking (fuzzy-select if no arg).

**Args:** `[pr_number]`

### `ready`

Mark a PR as ready for review (`gh pr ready`).

**Args:** `[pr_number_or_ref]`

### `to-draft`

Convert a PR to draft (`gh pr ready --draft`).

**Args:** `[pr_number_or_ref]`

### `diff`

Show the PR diff via `gh pr diff`.

**Args:** `[pr_number_or_ref]`

### `checkout`

Checkout the PR branch via `gh pr checkout`.

**Args:** `[pr_number_or_ref]`

### `merge`

Merge a PR via `gh pr merge`.

**Args:** `[pr_number_or_ref] [merge_args...]`

### `sync`

Sync the PR with its base branch via rebase (falls back to merge on conflict).

**Args:** `[pr_number_or_ref]`

### `fix`

Queue a `/pr:fix` task for failing PRs. Fuzzy-selects from failing PRs by default; `-r` fixes all failing at once.

**Args:** `[pr_number_or_ref...]`

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--red` | `-r` | Fix all PRs with failing checks | false |
| `--run` | `-R` | Launch queue tasks immediately | false |

### `comment`

Add a comment to a PR by opening your editor.

**Args:** `[pr_number_or_ref]`

### `templates`

List available comment templates from `~/.config/hiiro/pr_templates/`.

### `new-template`

Create a new comment template.

**Args:** `<name>`

### `from-template`

Fuzzy-select a comment template and post it to a PR.

**Args:** `[pr_number_or_ref]`

### `branch`

Print the head branch name for a tracked PR.

**Args:** `[pr_number_or_url]`

### `for-task`

List tracked PRs associated with a task name (or current task).

**Args:** `[task_name]`

### `tag`

Add tags to a tracked PR. With `-e`, opens a YAML bulk-tag editor.

**Args:** `[pr_ref] <tag> [tag2...]`

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--edit` | `-e` | Open YAML editor for bulk tagging | false |

### `untag`

Remove tags from a PR, or clear all if none specified.

**Args:** `<pr_ref> [tag...]`

### `tags`

Show all tracked PRs grouped by tag.

### `mfix`

Batch fix: YAML editor to select PRs to queue `/pr:fix` tasks for.

### `mopen`

Batch open: YAML editor to select PRs to open in browser.

### `mmerge`

Batch merge: YAML editor to select PRs and merge strategy.

### `mready`

Batch ready: YAML editor to mark selected PRs as ready for review.

### `mto-draft`

Batch draft: YAML editor to convert selected PRs to draft.

### `mrm`

Batch remove: YAML editor to remove selected PRs from tracking.

### `mcomment`

Batch comment: YAML editor to select PRs and write a comment to post on all of them.

### `dep`

Manage PR dependency relationships. Nested subcommands:

- `h pr dep add <pr> <dep1> [dep2...]` — Add dependency PRs
- `h pr dep rm <pr> [dep1 dep2...]` — Remove dependencies (omit deps to clear all)
- `h pr dep ls [pr]` — List dependencies for a PR or all PRs with dependencies

### `config`

Show or edit the pinned PRs config file. Nested subcommands:

- `h pr config path` — Print path to pinned PRs file
- `h pr config vim` — Open pinned PRs file in editor

### `q` [alias: `query`]

Query the `pinned_prs` SQLite table directly.

**Args:** `[table|sql|key=value...]`

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Show all rows (no 50-row limit) | false |
