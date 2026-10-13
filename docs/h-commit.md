# h-commit

Fuzzy-select a git commit SHA from the recent log. `h git commit` (below) plans and makes logical commits.

## Synopsis

```bash
h commit <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `select` / `sk` | Fuzzy-select a commit and print its SHA |

### select / sk

Show the last 50 commits via `sk` and print the SHA of the selected commit. Extra arguments are forwarded to `git log`.

**Examples**

```bash
h commit select
h commit sk
h commit select -- path/to/file
sha=$(h commit select)
git show $(h commit select)
```

## h git commit

Group every pending change (staged, unstaged, deleted, renamed, untracked) into logical commits planned by `claude -p --model MODEL`, then make them.

```bash
h git commit -n            # show the plan; nothing is staged or committed
h git commit               # show the plan, ask "Create N commit(s)? [y/N]"
h git commit -y            # skip the question
h git commit -y -w         # also accept whole-file commits of partially staged files
h git commit -m opus -n    # another model
```

| Flag | Meaning |
|------|---------|
| `-n`, `--dry-run` | Print the validated plan and stop |
| `-y`, `--yes` | Do not ask for confirmation |
| `-w`, `--whole-files` | Allow committing files that have both staged and unstaged changes |
| `-m`, `--model M` | Planner model (default `sonnet`) |

### What the planner sees

One JSON line per changed path (`{"path":"new.txt","status":"R","from":"old.txt"}`, plus `"binary":true` for binary files) and the unified diff of all changes. The diff is cut at 120,000 bytes; the prompt says `TRUNCATED` and the command prints the full size when that happens. Binary files appear as `Binary files ... differ`, deletions as deleted-file hunks.

The change list and diff come from disposable copies of the index (`GIT_INDEX_FILE`) in a temporary directory that is removed afterwards, with `GIT_OPTIONAL_LOCKS=0`. The real index file is never written while inspecting or planning, so its bytes, your staged selection, `HEAD`, and working files are unchanged by planning, a dry run, a cancelled confirmation, an invalid plan, or a failing planner. (`git add` on the copy does write blob objects to the object store; no ref or index changes.) Paths are read from NUL-delimited git output and passed as argv after `--` with `--literal-pathspecs`, so whitespace, quotes, newlines, leading dashes, and glob characters survive exactly.

### Plan validation

Before anything is staged, the planner must exit 0 and print a JSON array of `{ "message": "...", "files": [...] }` (Markdown fences and surrounding prose are tolerated). The command lists every problem, exits 1, and changes nothing if any commit has no message or no string `files`, if a path is unknown (a rename's old path counts as unknown; list the new path), if a path is assigned more than once, or if any changed path is left out.

### Whole-file staging

Each commit takes the complete working-tree content of its paths (a rename takes both its old and new path). A file with both staged and unstaged changes is marked `staged+unstaged: whole file` in the plan; without `--whole-files` the command stops before committing, because the commit would include the unstaged part. Stage or commit such files yourself first if you want only the staged part committed.

Each group is committed from its own temporary index seeded with `HEAD`, so nothing outside the group is included. After a group's commit, only that group's paths are set to `HEAD` in the real index; every other path keeps the staging you had. If `HEAD`, the index, or any working file changed between planning and confirmation, the command stops without committing.

### Failures

Commits run in plan order and stop at the first failing `git add`, `git commit` (including a rejecting hook), or index update. Earlier commits stay; nothing is reset or rolled back, no catch-all commit is made, and later groups do not run. The output names the failed operation and its git error, then `Stopped: K of N commit(s) made.`, and the exit status is 1.
