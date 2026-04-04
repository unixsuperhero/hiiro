# h-pr

Track, update, view, and act on GitHub pull requests with pinned PR management and multi-PR batch operations.

## Synopsis

```bash
h pr <subcommand> [options] [args]
```

PRs are tracked in SQLite (`~/.config/hiiro/hiiro.db`, table `prs`) with YAML backup at `~/.config/hiiro/pinned_prs.yml`. Each tracked PR stores its number, title, URL, head branch, state, check status, and review counts.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `check` | Run `gh pr checks` and send macOS notification |
| `watch` | Run `gh pr checks --watch` and notify |
| `fwatch` | Run `gh pr checks --watch --fail-fast` and notify |
| `number` | Print PR number for current branch |
| `link` | Print PR URL |
| `open` | Open PR in browser |
| `view` | Run `gh pr view` |
| `select` | Fuzzy-select from open PRs and print number |
| `copy` | Fuzzy-select and copy PR number to clipboard |
| `track` | Start tracking a PR |
| `ls` | List tracked PRs |
| `status` | Show check status summary |
| `update` | Refresh status for all tracked PRs |
| `green` | List PRs with all checks passing |
| `red` | List PRs with failing checks |
| `old` | List merged/closed tracked PRs |
| `prune` | Remove merged and closed PRs from tracking |
| `draft` | List draft PRs |
| `assigned` | List open PRs assigned to you |
| `created` | List open PRs created by you |
| `missing` | List your open/assigned PRs not yet tracked |
| `amissing` | Interactively add untracked PRs |
| `attach` | Open tmux window for PR's task session |
| `rm` | Remove a PR from tracking |
| `ready` | Mark PR as ready for review |
| `to-draft` | Convert PR to draft |
| `diff` | Show PR diff |
| `checkout` | Checkout PR branch |
| `merge` | Merge a PR |
| `sync` | Sync PR with base branch |
| `fix` | Queue `/pr:fix` for failing PRs |
| `comment` | Add a comment to a PR |
| `templates` | List comment templates |
| `new-template` | Create a comment template |
| `from-template` | Post a template comment to a PR |
| `branch` | Print head branch for a tracked PR |
| `for-task` | List PRs for a given task |
| `tag` | Add tags to a tracked PR |
| `untag` | Remove tags from a PR |
| `tags` | Show PRs grouped by tag |
| `mfix` | Batch fix: YAML editor to queue fix tasks |
| `mopen` | Batch open PRs in browser |
| `mmerge` | Batch merge PRs |
| `mready` | Batch mark PRs as ready |
| `mto-draft` | Batch convert to draft |
| `mrm` | Batch remove from tracking |
| `mcomment` | Batch comment on PRs |
| `dep` | Manage PR dependency relationships |
| `config` | Show or edit pinned PRs config |
| `q` | Query `pinned_prs` SQLite table |

## Options

### `ls`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--update` | `-u` | Refresh status before listing | false |
| `--verbose` | `-v` | Multi-line output per PR | false |
| `--checks` | `-C` | Show individual check run details | false |
| `--diff` | `-d` | Open diff for fuzzy-selected PR | false |
| `--all` | `-a` | Show all tracked PRs | false |

### `update`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--force-update` | `-u` | Force refresh even if recently checked | false |
| `--all` | `-a` | Show all tracked PRs | false |

### `fix`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--red` | `-r` | Fix all PRs with failing checks | false |
| `--run` | `-R` | Launch queue tasks immediately | false |

### `tag`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--edit` | `-e` | Open YAML editor for bulk tagging | false |

### `q` / `query`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--all` | `-a` | Show all rows (no 50-row limit) | false |

## Subcommand Details

### `track`

Start tracking a PR. Fetches PR info, tags it with current task/worktree context, and adds it to the pinned store. Pass `-` to read the PR number from stdin.

```bash
h pr track          # detect from current branch
h pr track 1234
h pr track -        # read from stdin
```

After tracking, always run:

```bash
h pr tag $(h pr number) my-task
h branch save
```

### `ls`

List tracked PRs with status indicators. Output includes PR number, title, check status, and review counts.

```bash
h pr ls
h pr ls -u          # refresh first
h pr ls -v          # verbose multi-line format
```

### `fix`

Queue a `/pr:fix` skill task for failing PRs. Fuzzy-selects from failing PRs by default; `-r` queues all at once.

```bash
h pr fix
h pr fix -r         # fix all failing
h pr fix -r -R      # fix all and launch immediately
```

### `dep`

Manage PR dependency relationships:

- `h pr dep add <pr> <dep1> [dep2...]` — Add dependency PRs
- `h pr dep rm <pr> [dep1 dep2...]` — Remove dependencies (omit deps to clear all)
- `h pr dep ls [pr]` — List dependencies for a PR or all PRs with dependencies

```bash
h pr dep add 100 99 98
h pr dep ls 100
h pr dep rm 100 99
```

### Batch operations (`m*`)

All batch operations open a YAML editor pre-filled with relevant PRs. Edit the list and save to apply the action.

```bash
h pr mfix           # queue fix tasks for selected PRs
h pr mopen          # open selected PRs in browser
h pr mmerge         # merge selected PRs with chosen strategy
h pr mready         # mark selected PRs as ready
```

## Examples

```bash
# Track the current branch's PR
h pr track

# Check status and open on passing
h pr check

# Monitor checks continuously
h pr watch

# Update all tracked PRs and list
h pr update

# Find PRs that need attention
h pr red
h pr fix -r

# Open current PR's diff
h pr diff

# Merge after checks pass
h pr merge --squash

# Tag a PR for organization
h pr tag 1234 my-feature
```
