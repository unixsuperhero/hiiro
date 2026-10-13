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
| `open [refs]` | Open PRs in the browser (`gh pr view --web`) |
| `number` | Print PR number for current branch |
| `link [ref]` | Print PR URL |
| `select` | Fuzzy-select from your open PRs |
| `copy` | Fuzzy-select and copy PR number to clipboard |
| `diff [ref]` | Show PR diff |
| `checkout [ref]` | Checkout a PR's branch |
| `merge [ref] [--merge\|--squash\|--rebase] [-d]` | Merge a PR |
| `sync [ref]` | Sync PR with its base branch (rebase, fallback to merge) |
| `ready [ref]` | Mark a PR as ready for review |
| `to-draft [ref]` | Convert a PR to draft |
| `fix [refs]` | Queue a revision-specific `/pr:fix` job for PRs |
| `comment [ref] [-b TEXT]` | Post a comment (editor when `-b` is omitted) |
| `templates` | List comment templates |
| `new-template <name>` | Create a comment template |
| `from-template [ref]` | Post a comment from a template |
| `rm [ref]` | Stop tracking a PR |
| `prune` | Remove all merged/closed PRs from tracking |
| `check [ref]` | Run `gh pr checks` in the foreground, notify the result |
| `watch [ref]` | Watch PR checks (keeps polling until done) |
| `fwatch [ref]` | Watch PR checks with `--fail-fast` |
| `tag <ref> <tags>` | Tag a tracked PR |
| `untag <ref> [tags]` | Remove tags from a tracked PR |
| `for-task [task]` | List tracked PRs for a task |
| `branch [ref]` | Get the head branch for a tracked PR |
| `attach [ref]` | Open a tab in the PR's task directory and Herdr workspace (no Git changes) |
| `assigned` | List PRs assigned to you |
| `created` | List PRs authored by you |
| `missing` | List your untracked PRs |
| `amissing` | Interactively add untracked PRs to tracking |
| `green` | List PRs with all checks passing |
| `red` | List PRs with failing checks |
| `old` | List merged/closed tracked PRs |
| `draft` | List draft PRs |
| `edit` | Edit the `h-pr` bin file |
| `mopen`, `mmerge`, `mready`, `mto-draft`, `mcomment`, `msync`, `mfix`, `mrm` | The same action for PRs chosen in a YAML selection |
| `dep add <ref> <dependencies>` | Add dependencies to a tracked PR |
| `dep rm <ref> [dependencies]` | Remove dependencies or clear them all |
| `dep ls [ref]` | List dependencies with their qualified references |
| `dep edit` / `config vim` | Edit tracked PR metadata in a temporary YAML document |
| `config path` | Print the canonical database location |
| `q [conditions]` | Query the canonical `prs` table |

See [actions](#actions-single-and-bulk) for how every acting subcommand resolves, validates, and reports. `h cpr` runs any of these on the current branch's PR ([h-cpr](h-cpr.md)).

PR references can be a GitHub pull-request URL, `owner/name#N`, a PR number, a slot, or omitted to select a tracked PR. A bare number names a tracked PR first and a slot second. When two repositories track the same number, a bare number is an error (`ERROR: Ambiguous PR #42 (team/one#42, team/two#42); use owner/name#42 or its URL`, exit 1); hiiro never guesses a default repository. `track` and `status` qualify an untracked bare number through `gh`'s current repository. Output names PRs as `owner/name#N`. Stored rows keep their database ID, slot, and pin time across metadata changes and status refreshes.

### Snapshots: what GitHub reported

Each tracked PR holds one remote snapshot, separate from its local preferences:

```js
const local = { ref: "team/one#42", tags: ["review"], task: "work", dependsOn: ["team/two#42"], pinned: true, slot: 1 };
const snapshot = {
  ref: "team/one#42", headSha: "aaaa…", fetchedAt: "2026-10-13T17:26:25.156914Z",
  checks:  { complete: true,  nodes: 250 },   // raw statusCheckRollup contexts
  reviews: { complete: false, nodes: 100 },   // raw review nodes
  outcome: "fresh",                           // fresh | stale | unknown
  error: "reviews: page 2 failed: malformed gh output",
};
```

- One refresh path (`ls -u`, `update`, `tags -u`, `track`, `status`) fetches one GraphQL batch per repository through `gh api graphql`, then pages checks and reviews backward 100 at a time. Each page re-reads the head revision.
- **Incomplete**: a later page failed, returned malformed output or GraphQL errors, repeated a cursor, or the count fell short. What was fetched is stored with `complete: false`, shown as `incomplete` (and `❓`), and its error is kept.
- **Stale**: the refresh produced nothing usable (gh failed, the PR could not be resolved, or the head changed between pages). The last observation is kept unchanged and marked `stale`; a PR never observed is `unknown`. Pages from two heads are never combined.
- `green`, `-g`, and `ls -v` count a PR as passing only when its snapshot is fresh and both checks and reviews are complete. A partial list of successes is never passing evidence.
- A refresh updates only remote columns of each row (title, state, head, checks, reviews, freshness) and only when the stored observation is older. Tags, task, dependencies, and tracking changes made while a refresh runs survive it, and an untracked PR is not recreated.
- Rows with no repository evidence (no `repo`, no URL) are listed but not refreshed: `not refreshed id 35 #50: no repository; track it again by URL`.

The ISC code freeze is a policy over the snapshot, not part of it. GitHub's raw contexts are stored unchanged. The policy input (`isc codefreeze list`: inside a window, outside, or unavailable) is recorded with each observation and applied when checks are counted: inside a window the `ISC code freeze` context counts as failed (`❄️`), outside it as passed, and when `isc` is unavailable GitHub's state stands. `ls -C` prints both, for example `❌  ISC code freeze  (freeze policy: FAILURE; GitHub: SUCCESS)`.

### Dependencies

Dependencies are stored as `owner/name#N`. `dep add` takes tracked PRs (number, slot, URL, `owner/name#N`); an untracked bare number means that number in the depending PR's repository. `dep rm` with a bare number also removes a legacy unqualified entry with that number.

Older records stored bare numbers. At startup, a legacy number is qualified only when exactly one tracked record has that number and it is in the depending PR's repository; otherwise the integer is kept and `dep ls` reports it as `#44 (unresolved legacy number; re-add as owner/name#44 or URL)`. Records with no `repo` gain it from their PR URL.

### Data ownership and record editing

SQLite owns tracked and pinned PR records in `prs`. Check rows use `check_runs.pr_id` to identify the owning PR row, so refreshes never replace another repository's checks. Legacy number-only checks remain unowned when their repository cannot be established. Each PR's raw cached check JSON can rebuild its owned check rows.

`pinned_prs.yml` is a legacy import source, not a live store. Normal PR commands neither read nor write that file. PR templates remain ordinary files.

`h pr config vim` and `h pr dep edit` edit a temporary document containing original row IDs and editable metadata. A missing field keeps its current value. An explicit null clears a field. Changed fields use the original values to detect concurrent edits, and conflicts roll back the operation. Removing a record from this document unpins only that original row, provided it has not changed concurrently. New PRs added while the editor is open remain untouched. Add a new PR with `track`, not by inventing an ID in the editor.

Cleared workspace associations stay cleared across restarts. An old `tmux_session` value seeds `herdr_workspace` only when the canonical column is first introduced; it remains available for recovery but is not a reader fallback.

The `tag -e` and `mrm` selection documents use stable row IDs with repository comments. Failed, blank, or unchanged editors do not mutate PR records. `mrm` and editor deletions untrack each selected row individually and refuse a row whose local fields or tags changed after the document was opened; a refresh in the meantime does not block them. Editor `depends_on` entries must be `owner/name#N` (legacy numbers already on the row may stay).

### Actions: single and bulk

`open`, `view`, `diff`, `checkout`, `merge`, `ready`, `to-draft`, `comment`, `from-template`, `sync`, `fix`, `rm`, `prune`, and every `m*` command run one implementation:

```js
const targets = { references: ["team/one#42", "team/two#5"] };           // resolved first, qualified
const request = { name: "merge", params: { strategy: "squash", delete_branch: false }, targets };
const outcomes = [{ ref: "team/one#42", ok: true }, { ref: "team/two#5", ok: false, detail: "gh failed (exit 1)" }];
```

1. Targets are resolved as for every PR argument (URL, `owner/name#N`, tracked number or slot, pin) and must be distinct.
2. The action's fields are checked for every target before anything runs: `merge` strategy is `merge`, `squash`, `rebase`, or blank; `comment` is not empty; `fix` and `rm` need tracked PRs. A refused request prints `ERROR: …` (single) or `Invalid selection: …` (bulk) and exits 1 without calling `gh`.
3. Each target runs in turn (`gh pr … <URL>` on the terminal, so prompts and output stay native) and prints `✓ team/one#42 merge` or `✗ team/two#5 merge: gh failed (exit 1)`. Several targets end with `merge: 1 succeeded, 1 failed`. Any failure exits 1. Ctrl-C in one target stops the rest (`not attempted (interrupted)`).

The `m*` commands open this selection document with every tracked PR:

```yaml
prs:
- https://github.com/team/one/pull/42  # [branch-42] one
- https://github.com/team/two/pull/5  # [branch-5] two

strategy:   # merge | squash | rebase; blank for GitHub's default

delete_branch: false   # true deletes the head branch after merging
```

Delete the PRs you do not want and set the fields. An editor that exits with an error, an empty file, or an unchanged document prints `Cancelled: …` and exits 0. Invalid YAML, unknown fields, or bad values print `Invalid selection: …` and exit 1. `prs: []` prints `No PRs selected; nothing to do.` `mrm` and editor deletions refuse a row whose local fields or tags changed after the document opened.

### attach

Open a new tab in the PR's task Herdr workspace, in the task's tree directory. Nothing is staged, committed, or checked out; HEAD, the index, working files, and branches are unchanged. Use `h pr checkout` to switch branches explicitly.

**Examples**

```bash
h pr attach
h pr attach 1234
```

### check / watch / fwatch

Foreground waiting: `gh pr checks <URL>` runs on the terminal with the PR's repository in the URL (`watch` adds `--watch`, `fwatch` adds `--fail-fast`; extra arguments pass through). The command exits with gh's own status. Ctrl-C reaches gh, prints `team/one#42: interrupted`, sends nothing, and exits 130. Otherwise one notification goes out through the `h alert` adapter: `passed` (exit 0), `pending` (exit 8), `failing` only when a fresh snapshot shows a failed check, and `unknown` for any other failure (network, auth, unresolvable PR). For continuous monitoring see [h-pr-monitor](h-pr-monitor.md).

**Examples**

```bash
h pr check
h pr watch 1234
h pr fwatch 1234
```

### fix

Queue a `/pr:fix` job for tracked PRs (`fix REF...`, `-r` for every failing PR, or a pick from failing PRs). Each job is named `pr-fix-OWNER-NAME-N-HEAD7` and records the PR URL, head revision, snapshot completeness, failing checks, and the PR's task, tree, and workspace. Jobs are only queued unless `-R` (or `run: true` in `mfix`) asks to launch them.

```text
---
pr: team/two#5
pr_url: https://github.com/team/two/pull/5
head_sha: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
---
/pr:fix https://github.com/team/two/pull/5

PR: team/two#5 https://github.com/team/two/pull/5
Head revision: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
Snapshot: fresh, fetched 2026-10-13T18:01:11.397435Z, checks complete
Failing checks:
- lint FAILURE https://ci.example.test/lint
```

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--red` | `-r` | Fix all PRs with failing checks |
| `--run` | `-R` | Launch the queued jobs now |

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
| `--numbers` | | Print PR numbers only (bare numbers; not unique across repositories) |

Each line names the PR as `owner/name#N`. A non-fresh snapshot is marked `stale`, `unknown`, or `incomplete` after the branch; `-v` adds `snapshot fresh · head aaaaaaa · fetched … · checks complete · reviews complete`.

**Examples**

```bash
h pr ls
h pr ls --update
h pr ls --red
h pr ls --verbose --checks
```

### rm / prune

`rm` stops tracking a specific PR (fuzzy-select if no ref given). `prune` removes all merged/closed PRs from tracking at once. Both are the `untrack` action (`✓ team/one#42 untrack: removed from tracking`); an untracked reference is an error.

**Examples**

```bash
h pr rm
h pr rm 1234
h pr prune
```
### status

Refresh one or more PRs through the snapshot path and print the reference, title, state, check counts by outcome (`checks unknown` when nothing was observed), `checks incomplete` when pages are missing, the refresh error, and the URL. Tracked PRs are stored as by `update`; untracked ones are only printed. Exits 1 when any PR is not fresh.

```text
team/one#42
one
open
250 success
snapshot stale: head changed during refresh (aaaaaaa → bbbbbbb at checks page 2)
https://github.com/team/one/pull/42
```

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
h pr track 1234     # a number in gh's current repository
h pr track team/repo#1234
h pr track https://github.com/team/repo/pull/1234
```

### update

Refresh statuses for all active tracked PRs, then display the list.

**Options**

Same filters as `ls`, plus `--force-update` / `-u` to force refresh even if recently checked. Incomplete and failed refreshes are listed before the PRs:

```text
  incomplete team/one#42: checks: page 3 failed: gh exited 1: HTTP 502: Bad Gateway (https://api.github.com/graphql)
  refresh failed team/two#42: head changed during refresh (bbbbbbb → ccccccc at reviews page 2)
```

**Examples**

```bash
h pr update
h pr update --red
h pr update -U
```
