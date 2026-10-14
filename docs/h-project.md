# h-project

Manage project directories and open Herdr workspaces for them.

## Synopsis

```bash
h project <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `open <name>` | Open a project and focus/create its Herdr workspace |
| `list` / `ls` | List all known projects |
| `add <name> <path>` | Save or update a project alias |
| `rm <name>` / `remove <name>` | Remove a saved project alias |
| `config` | Print saved project aliases as YAML (`name: path`) |
| `edit` | Edit the saved project aliases as a YAML buffer |
| `select` | Choose a project with the shared picker and print its path |
| `copy` | Choose a project with the shared picker and copy its path to the clipboard |
| `sh <name> [cmd]` | Open a shell or run unchanged native arguments in a project directory |
| `path [name]` / `abspath [name]` | Print the absolute project path without a newline |
| `cd [name]` | Send `cd` to the explicit calling Herdr pane |
| `ui [--root DIR ...]` | TUI over every git worktree, plain directory, and alias, with a detail pane and worktree add/remove |
| `help` | Show usage |

Projects are discovered from two sources:

1. Directories in `~/proj/`
2. Aliases saved in registry table `project`, which take precedence over directories with the same name

The default subcommand runs `help`. Project operations construct a taskless context and never create or require a task. Resolved paths are absolute real paths; stored alias values remain unchanged. Missing directories are errors. `cd` validates captured workspace/tab/pane IDs and does not act on whichever pane has focus.

### config

Print the saved project aliases as YAML (`name: path` per line, sorted by name), or `No project aliases saved.` when there are none.

**Examples**

```bash
h project config
```

### copy

Choose a project with the [shared picker](picker.md) and copy its path to the clipboard.

**Examples**

```bash
h project copy
```

### edit

Open the saved project aliases as a YAML buffer in your editor. On save, changed paths are updated, new names are added, and removed names are deleted from table `project`. An invalid or empty buffer changes nothing and prints `No changes applied.`.

**Examples**

```bash
h project edit
```

### list / ls

List all projects with their source (`[config]` for SQLite aliases or `[dir]` for discovered directories) and path.

**Examples**

```bash
h project list
h project ls
```

### open

Open a project and focus or create its Herdr workspace at the resolved directory. Exact case-sensitive names win, followed by unique prefixes. A terminal disambiguates through the [shared picker](picker.md) (`projects`, identity = project name); non-interactive ambiguity and missing explicit names fail. An unnamed target means `~/proj`, not a fallback for an unknown name.

**Examples**

```bash
h project open hiiro
h project open my-app
```

### select

Choose a project with the [shared picker](picker.md) and print its absolute path. The picker is named `projects`. Its rows are identified by project name, with fields `name` and `path`, so a rule such as `{mode: glob, field: path, pattern: "**/archive/*"}` hides archived checkouts in every later `select`, `copy`, `open`, and ambiguous lookup. `Ctrl-X` lists hidden projects and `u` restores one; no project or directory is changed.

**Examples**

```bash
h project select
cd $(h project select)
```

### sh

Open a shell in a project directory, or run a command there.

**Examples**

```bash
h project sh hiiro
h project sh hiiro bundle exec rake test
```

### add

Save a named project alias. An existing name updates only its path and keeps its database ID.

```bash
h project add my-app ~/work/my-app
```

### rm / remove

Delete only the saved alias with the exact name. This does not delete its directory or exclude it from `~/proj/` discovery.

```bash
h project rm my-app
```

### ui

Open the projects screen: one flat list with a row per git worktree found under the roots, a row per plain directory with no `.git` of its own, and a row per alias from table `project`. A repo's extra worktrees read `repo ▸ tree` under the repo's main row, so `~/proj/h2` checked out from `~/proj/hiiro` is `hiiro ▸ h2`. Each row shows `NAME  BRANCH  HEAD`; plain directories and aliases show `-` for the branch. The detail pane lists the row's path, repo, branch, head, and the repo's worktrees, then `status`, `branches`, and `prs` lines that read `-` until fetched.

**Roots.** `~/proj` and `~/work` (`Hiiro::WORK_DIR`) by default. `--root DIR` replaces them and may repeat. A root that is itself a repo (`~/work`, whose `.git` points at `~/work/.bare`) is one repo named after the root; its bare entry is dropped. Git runs once per repo directory at open; status, branches, and PRs load per row on request.

| Key | Action |
|-----|--------|
| `enter` / `o` | Open the row (see below) and quit |
| `/` | Search name, branch, and path |
| `g` | Toggle scope between `global` (every row) and `task(@NAME)` (the current task's repo, cursor on its tree) |
| `s` | Fetch `git status --porcelain -b` for the tree; the row gains ` *N ↑A ↓B` after the branch (zero parts omitted) |
| `b` | Fetch the repo's local branches into the pane |
| `p` | Fetch the repo's open PRs (`gh pr list`) into the pane |
| `a` | Prompt `branch` then `path` (prefilled `<repo parent>/<branch basename>`) and run `git worktree add`, with `-b` when the branch is new; the new tree is selected |
| `d` | On an extra worktree, prompt `remove PATH? (y/n)` and run `git worktree remove`; the main tree, plain dirs, and aliases answer `not a removable worktree` |
| `y` | Copy the row path with `pbcopy` |
| `q` / `Esc` | Quit |

**Editing in a prompt.** Left, Right, Home, End, Delete, and Ctrl-U (clear) edit the text; while choices show after `▸`, Up and Down move the `[ ]` selection, Tab accepts it, and Enter accepts it before a second Enter submits. The `branch` prompt of `a` completes the row repo's local branches; `path` and the `y/n` confirmation do not complete.

**Scope.** The current task is resolved like `t` does (Herdr workspace, working directory, then the `t use` pin). `g` scopes to it only when its tree (`TaskLocation#worktree_path`) is a row in the catalog; otherwise the status line says `no current task to scope to`.

**Open backend.** With `TUIOS_ENV=1` the row opens as `tuios new-window NAME -s $TUIOS_SESSION --cwd PATH`; otherwise it opens the Herdr workspace `NAME` rooted at the path, the same call `h project open` makes. NAME is the row name with `.` and spaces replaced by `_` and the `▸` marker dropped. A failed open shows in the status line and the screen stays open. Fetch errors (`gh` not logged in, a directory that is not a repo) show the same way.

**Examples**

```bash
h project ui
h project ui --root ~/proj --root ~/work
h project ui --root /tmp/scratch
```

## Configuration

Project aliases live in registry table `project` of `~/.config/hiiro/hiiro.db` (name = alias, value = path), the same rows `h table project` shows. `h project config` and `h project edit` show them in this YAML shape:

```yaml
- id: 1
  name: my-app
  path: /Users/me/work/my-app
- id: 2
  name: hiiro
  path: /Users/me/proj/hiiro
```

The retired `projects` SQLite table is copied into table `project` once at setup. Legacy `projects.yml` is an explicit import input for `h db plan --only projects` and `h db migrate --only projects`; project commands do not read or rewrite it. See [h-db](h-db.md) for source selection and recovery. Directory discovery in `~/proj/` remains file-based.
