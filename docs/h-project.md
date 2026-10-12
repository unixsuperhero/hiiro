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
| `config` | Show the config file contents |
| `edit` | Edit the config file |
| `select` | Fuzzy-select a project and print its path |
| `copy` | Fuzzy-select a project and copy path to clipboard |
| `sh <name> [cmd]` | Open shell (or run command) in a project directory |
| `ui [--root DIR ...]` | TUI over every git worktree, plain directory, and alias, with a detail pane and worktree add/remove |
| `help` | Show usage |

Projects are discovered from two sources:

1. Directories in `~/proj/`
2. Aliases saved in registry table `project`

The default subcommand (no subcommand) runs `help`.

### config

Print the saved project aliases as YAML (`name: path` per line, sorted by name), or `No project aliases saved.` when there are none.

**Examples**

```bash
h project config
```

### copy

Fuzzy-select a project and copy its path to the clipboard.

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

List all projects with their source (`[config]` or `[dir]`) and path.

**Examples**

```bash
h project list
h project ls
```

### open

Open a project by name and focus (or create) a Herdr workspace rooted at its directory. Project names are matched with case-insensitive regex; if exactly one match is found, it is used. If multiple matches are found, an exact match is preferred.

**Examples**

```bash
h project open hiiro
h project open my-app
```

### select

Fuzzy-select a project and print its absolute path.

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

**Scope.** The current task is resolved like `t` does (Herdr workspace, working directory, then the `t use` pin). `g` scopes to it only when its tree (`TaskLocation#worktree_path`) is a row in the catalog; otherwise the status line says `no current task to scope to`.

**Open backend.** With `TUIOS_ENV=1` the row opens as `tuios new-window NAME -s $TUIOS_SESSION --cwd PATH`; otherwise it opens the Herdr workspace `NAME` rooted at the path, the same call `h project open` makes. NAME is the row name with `.` and spaces replaced by `_` and the `▸` marker dropped. A failed open shows in the status line and the screen stays open. Fetch errors (`gh` not logged in, a directory that is not a repo) show the same way.

**Examples**

```bash
h project ui
h project ui --root ~/proj --root ~/work
h project ui --root /tmp/scratch
```

## Configuration

Project aliases live in registry table `project` (name = alias, value = path). `h project config` and `h project edit` show them in this YAML shape:

```yaml
my-app: /Users/me/work/my-app
hiiro: /Users/me/proj/hiiro
```

A legacy `~/.config/hiiro/projects.yml` (and the old `projects` SQLite table) is imported into table `project` once at startup; the YAML file is then renamed `projects.yml.bak`.
