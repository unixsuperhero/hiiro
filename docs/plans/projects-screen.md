# Projects screen plan (PR 6 of the Hiiro TUI plan)

`h project ui` opens one flat list of every directory you work in, one row per git worktree, with a detail pane for the row under the cursor and keys to open it, inspect it, and add or drop worktrees. One PR, one new screen class, one catalog class, one new `h project` subcommand. Decided 2026-10-12 after a read-only survey of `~/proj` and three row layouts rendered on the toolkit (Appendix A).

## How to read this

One box is one unit of work with the evidence that checks it. Unit tests drive the screen through `handle_key` and assert `frame` literally against git repos built in a tmpdir under the in-memory DB. The live check launches `h project ui` in a tuios window, drives it with `tuios send-keys`, and keeps the captures. Tests alone do not verify the PR.

## What the survey found

- `~/proj` holds 126 directories: 93 git repos, 5 extra worktree directories belonging to 3 of them (`hiiro`, `demo-tool`, `portfolio`), and about 30 plain directories with no `.git` of their own. The home directory is itself a git repo, so `git` run inside a plain directory answers for the home repo. The loader must test for a `.git` entry in the directory before calling git.
- Task worktrees live under `Hiiro::WORK_DIR` (`~/work`), all trees of one bare repo at `~/work/.bare` (`main/main`, `claude/main`, `refactor/main`, ...). They are the task scope.
- Table `project` holds 2 aliases, one with a stale path.
- Timings over all 126 directories, read only: one `git worktree list --porcelain` sweep 1.5 s, `git branch --show-current` 1.4 s, `git branch` 1.8 s, `git status --porcelain` 116 s cold and 7 s warm, `gh pr list` 0.5 s per repo. Status, branches, and PRs therefore load per row on request, never at open.
- Usage from `invocation_resolutions`: `h wtree ls` 85, `h project open` 22 plus abbreviations, `h wtree add` 5, `h wtree prune` 3. `h pr` and `h branch` have no recorded runs. Worktrees are the daily unit; PRs and branches are detail.
- Herdr is not running in this tuios session (`herdr status server` says `not running`), so `h project open` and `h wtree switch` cannot open anything here. `tuios new-window NAME -s SESSION --cwd DIR` can.

## Vocabulary

- **project**. One row. A directory you can open: a git worktree, a plain directory under a root, or an alias from table `project`. `{ name, path, kind: :tree | :dir | :alias, repo: Repo | nil, branch, head }`.
- **repo**. One git repository and its worktrees, grouped by the first entry of `git worktree list --porcelain`. `{ name, path, trees: [Tree] }`. The row for a repo's extra tree reads `repo ▸ tree`.
- **root**. A directory whose children are candidate projects. Defaults: `~/proj` and `Hiiro::WORK_DIR`. `--root DIR` replaces them.
- **scope**. `:global` lists every row. `:task` lists the trees of the current task's repo with the cursor on the task's tree, resolved through `Hiiro::CurrentTask` and `TaskLocation#worktree_path`. `g` toggles.
- **facts**. Per-row data fetched on a key and cached for the session: status `{ dirty, ahead, behind }` per tree, `branches` and `prs` per repo.

```ruby
row    = { name: 'hiiro ▸ h2', path: '~/proj/h2', kind: :tree, repo: hiiro, branch: 'task-cli', head: '9c8c9fd' }
repo   = { name: 'hiiro', path: '~/proj/hiiro', trees: [hiiro, h2, hiiro_config] }
facts  = { '~/proj/h2' => { dirty: 3, ahead: 1, behind: 0 }, hiiro => { branches: [...], prs: [{ number: 2, title: '...', state: 'OPEN' }] } }
```

## PR 6. `h project ui`

**Files.** Create `lib/hiiro/project_catalog.rb`, `lib/hiiro/project_screen.rb`, `test/hiiro/project_catalog_test.rb`, `test/hiiro/project_screen_test.rb`. Edit `bin/h-project` (one `add_subcmd(:ui)`), `lib/hiiro.rb` (requires), `docs/h-project.md`, `README.md`, `AGENTS.md`.

**Build.**
- [ ] `Hiiro::ProjectCatalog.load(roots:, aliases:)`. For each child of each root that has its own `.git` entry, run `Hiiro::Git::Worktrees.fetch(repo_path:)` once and group by the main worktree path; children without `.git` become `:dir` rows; aliases become `:alias` rows. Rows sort by repo name, then tree path, so a repo's trees sit together. The `(bare)` entry of `~/work` is dropped. Returns `{ rows, repos }`. One git call per repo directory, about 1.6 s for the real roots.
- [ ] `Hiiro::ProjectScreen < Tui::Screen`. `ProjectScreen.new(catalog:, scope:, current:, facts: Facts.new, opener: Opener.new)`. Row text `NAME  BRANCH  HEAD` with the name column sized to the longest name, capped at 28. Header `projects  scope:global|task(@NAME)  N rows` plus the key hint. Search matches name, branch, and path.
- [ ] Detail pane. `name`, `path`, `repo`, `branch`, `head`, then `worktrees (n)` with `  NAME  BRANCH` lines, then `status`, `branches (n)`, `prs (n)` lines that read `-` until fetched and the values after. Aliases and plain dirs show `path` and `kind` only.
- [ ] Facts. `s` fetches `git status --porcelain -b` for the row's tree and stores `{ dirty, ahead, behind }`; the row gains ` *3 ↑1` after the branch. `b` fetches `Hiiro::Git::Branches` for the repo. `p` fetches `gh pr list --json` for the repo through `Hiiro::Git::Pr.list` run in the repo directory. Each fetch runs once per key press, shows `fetching ...` in the status line, and caches in `Facts` until the screen closes. Errors (no remote, `gh` not logged in) become the status message.
- [ ] Open. `Enter` and `o` call `Opener#open(row)` and quit. `Opener` picks the backend from the environment: `TUIOS_ENV=1` runs `tuios new-window NAME -s $TUIOS_SESSION --cwd PATH`; otherwise `Hiiro::Herdr.open_workspace(NAME, start_directory: PATH)`, the same call `h project open` and `h wtree switch` make. NAME is the row name with `.` replaced by `_`. A `Hiiro::Error` or a non-zero exit becomes the status message and the screen stays open.
- [ ] Worktrees. `a` on a repo row prompts `branch` then `path` (prefilled `<root>/<branch basename>`) and runs `git worktree add PATH BRANCH`, adding `-b` when the branch does not exist; the catalog reloads with the cursor on the new tree. `d` on an extra tree prompts `remove PATH? (y/n)` and runs `git worktree remove PATH`; git's refusal on a dirty tree shows in the status line. The main worktree, plain dirs, and aliases refuse `d` with `not a removable worktree`.
- [ ] `y` copies the row path with `pbcopy`. `g` toggles scope, `no current task to scope to` when none resolves. `q` quits.
- [ ] `h project ui [--root DIR]` in `bin/h-project`; `--root` may repeat. Aliases come from `Hiiro::Projects#from_config`.
- [ ] Docs. `docs/h-project.md` gains a `ui` row and a `### ui` section with the key table, the scope rule, and the open backend rule. `README.md` names `h project ui`. `AGENTS.md` gets one line under Library Components for `ProjectCatalog` and `ProjectScreen` as the third screen on the toolkit.

**You see.** The V2 frame from Appendix A: one row per worktree, `hiiro ▸ h2  task-cli  9c8c9fd` under `hiiro  main  2abe155`, the detail pane listing the repo's three trees, `*3 ↑1` appearing on the row after `s`, PR lines after `p`, `scope:task(@tcli)` with only the `~/work` trees after `g`, and a new tuios window on `Enter`.

**Verify, unit.** `test/hiiro/project_catalog_test.rb` builds a tmpdir root with one repo that has two worktrees, one plain dir, and a nested plain dir inside a repo, plus one alias, and asserts the rows literally (names, kinds, order, the plain dir not inheriting the enclosing repo). `test/hiiro/project_screen_test.rb` seeds the same root under `HIIRO_TEST_DB` and asserts `frame(rows: 14, cols: 90)` literally for: the list; search `feat`; `s` adding ` *1` after a file is dirtied; `b` listing branches in the pane with a fake fetcher; `p` listing PRs from a fake fetcher; `g` with a resolver returning a task whose tree is in the root; `a` creating a worktree on disk and a new row; `d` after `y` removing it; `d` on the main tree refusing; `Enter` calling a fake opener with the row and returning from `run`; `Opener` choosing tuios when `TUIOS_ENV=1` and Herdr otherwise, with the command captured. Run `ruby -Ilib -Itest test/hiiro/project_screen_test.rb`.

**Verify, live.** In a tuios window: `ruby -Ilib bin/h-project ui` on the real roots, read only: open, `/hiiro`, `s` on `hiiro ▸ h2`, `b`, `p` (two open PRs on `unixsuperhero/hiiro`), `g`, `q`; then `Enter` on `hiiro` and confirm the new window with `tuios list-windows`. Then against a throwaway root in the scratch dir with `--root`: `a` adding a worktree, `d` removing it, each confirmed with `git worktree list`. Keep the captures. Herdr opening is covered by the unit test only, as in PR 5.

## Alternatives rejected

- **Repo rows with worktrees under an expand toggle** (Appendix A, V1 and V3). Only 3 of 93 repos have more than one tree, so the toggle adds an `expanded` Set and a marker column that 90 rows never use. The flat list shows the same information in 5 more rows and no state.
- **Loading status for every row on open.** 116 s cold, 7 s warm over the real roots. Per-row fetch on `s` keeps open at about 1.6 s.
- **Pinned PR management in this screen.** `h pr` has no recorded runs and one pinned row. The screen lists a repo's open PRs on `p` and leaves pinning, refresh, and merge to `h pr`.
- **`cd` into the row.** The toolkit draws on stdout, so `cd "$(h project ui)"` would capture the frames. `y` copies the path instead; rendering to `/dev/tty` is a toolkit change for a later PR if the need shows up.
- **Herdr first, tuios as fallback.** Would need a status probe on every open. The environment already says which multiplexer the pane runs in, so the backend is a table keyed on `TUIOS_ENV`.

## Risks

- The open backend for tuios makes a window, not a workspace. `tuios list-workspaces` and `move-window` exist, so a workspace-per-project rule can follow in PR 7 when the tuios screen owns that vocabulary.
- Open costs one git call per repo directory; a cold disk makes it slower. If it grows past a few seconds, cache the catalog in a table and refresh on `R`.
- `a` writes to disk and `d` removes a directory. Both are confirmed by a prompt and go through git, which refuses to remove a dirty tree without `--force`, and the screen never passes `--force`.
- Rows from `~/work` are task trees whose names (`main/main`) do not say which task owns them. The detail pane shows the path; mapping tree to task name is `TaskRecord` data and can join in a later change.

## Appendix A. Prototype evidence

Throwaway scripts on `Hiiro::Tui::Screen` run read-only against the real `~/proj` and `~/work` on 2026-10-12, scratch dir `scratchpad/projects-proto/` of the session, not in this repo. Loader: 93 repos from one worktree-list sweep in 1.57 s.

```text
V1 repo rows, hiiro expanded (96 rows)          V2 one row per worktree (103 rows)
     herdr                   master              │     herdr                 master           81ddf…
> ▾  hiiro                   main  (3 trees)     │     hiiro                 main             2abe1…
     h2                 task-cli   9c8c9fd       │     hiiro ▸ h2            task-cli         9c8c9…
     hiiro-config       h-config-yaml  5f2d42c   │   > hiiro ▸ hiiro-config  h-config-yaml    5f2d4…
                                                 │
V3 is V1 with multi-tree repos always expanded (101 rows); identical to V1 for 90 of 93 repos.

V2 at 80 columns, cursor on a task tree
  work ▸ claude/main          publish-…│name      work
  work ▸ main/main            main    …│path      /Users/unixsuperhero/work/ref…
> work ▸ refactor/main        refactor…│branch    refactor
100/103
```
