# h

The main entry point for the hiiro CLI framework. Provides self-management commands and dispatches to external subcommands (`h-*` binaries in PATH).

## Synopsis

```bash
h <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `version` | Print current hiiro version |
| `ping` | Health check — prints `pong` |
| `install` / `update` | Install or update hiiro across rbenv versions |
| `setup` | Install plugins and bin scripts to `~/bin` |
| `alert` | Send a macOS notification |
| `queue` | Manage the Claude prompt queue (delegates to `h queue`) |
| `service` / `svc` | Manage dev services (delegates to `h service`) |
| `run` | Run tools against changed files (delegates to `h run`) |
| `file` | Manage tracked app files (delegates to `h file`) |
| `task` | Manage tasks and worktrees |
| `subtask` | Manage subtasks within the current task |
| `check_version` | Verify installed hiiro version across rbenv versions |
| `delayed_update` | Poll RubyGems for a new version and install when available |
| `rnext` | Run `git rnext` (rebase next) |
| `edit` | Open the `h` bin file in your editor |
| `pry` | Open a pry REPL in the hiiro context |

All `h-*` executables found in PATH are also available as subcommands. For example, `h branch` dispatches to `h-branch`.

## Subcommand resolution

Hiiro supports prefix matching. If a prefix uniquely identifies a subcommand, it runs it:

```bash
h ver     # matches h version
h br s    # matches h branch save
```

If a prefix is ambiguous, hiiro lists all matching subcommands.

### version

Print the installed hiiro gem version. With `-a`, check all rbenv Ruby versions.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--all` | `-a` | Show version for all rbenv Ruby versions | false |

**Examples**

```bash
h version
h version --all
```

### install / update

Install or update the hiiro gem. With `-a`, updates all rbenv Ruby versions in parallel.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--all` | `-a` | Update all rbenv Ruby versions | false |
| `--pre` | `-p` | Install pre-release version | false |

**Examples**

```bash
h install
h update --all
h update --pre
```

### setup

Install hiiro plugins and bin scripts to `~/bin`. Renames `h-*` scripts to match the current prefix (e.g. `h-branch` stays `h-branch` for the `h` prefix). Warns if `~/bin` is not in PATH.

**Examples**

```bash
h setup
```

### alert

Send a macOS notification via `terminal-notifier`. See [h-notify](h-notify.md) for the full notification system.

**Options**

| Flag | Description |
|------|-------------|
| `-m` | Notification message |
| `-t` | Notification title |
| `-l` | URL to open when clicked |
| `-c` | Shell command to run when clicked |
| `-s` | Sound name |

**Examples**

```bash
h alert -t "Done" -m "Build finished" -s Glass
```

### check_version

Verify the installed hiiro version matches an expected version across rbenv Ruby versions. Exits non-zero if any version mismatches.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Check all rbenv versions |

**Examples**

```bash
h check_version 0.1.312
h check_version 0.1.312 --all
```

### delayed_update

Polls RubyGems until a specific version appears (up to ~10 minutes), then installs it via `h update -a`. Runs in a background tmux window via `h bg run`. Sends a macOS notification when complete.

**Examples**

```bash
h delayed_update 0.1.313
```

## h task and h subtask

`h task` manages top-level tasks (worktree + tmux session pairs). `h subtask` manages subtasks scoped to the current parent task. Both share the same subcommands.

### task / subtask subcommands

| Subcommand | Description |
|------------|-------------|
| `ls` / `list` | List tasks (and subtasks) |
| `start <name> [app]` | Create or switch to a task |
| `switch [name] [app]` | Switch to a task's tmux session |
| `stop [name]` | Stop a task (preserves worktree) |
| `resume [tree]` | Resume a task from an available worktree |
| `current` | Print current task name |
| `status` / `st` | Show current task details |
| `branch [task]` | Print branch name for a task |
| `tree [task]` | Print worktree name for a task |
| `session [task]` | Print session name for a task |
| `cd [task] [app]` | Send `cd` to current pane |
| `path [task] [app]` | Print path to task/app directory |
| `app [name]` | Open an app in a new tmux window |
| `apps` | List configured apps |
| `tag [task] <tags>` | Tag a task |
| `untag [task] [tags]` | Remove tags |
| `tags` | List tagged tasks |
| `sparse [groups]` | Apply sparse checkout groups to current task |
| `color` | Set or pick a display color for the current task |
| `save` | Save current task's tmux window state |
| `edit` | Open the tasks YAML file |
| `todo [args]` | Manage todos for the current task |
| `queue [args]` | Claude queue scoped to current task (see `h queue`) |
| `service [args]` | Service manager scoped to current task |
| `run [args]` | Run tools for current task |
| `file [args]` | App file tracking for current task |
| `prs [args]` | List PRs for current task |
| `branches [args]` | List branches for current task |
| `wtrees [args]` | List worktrees for current task |

**Examples**

```bash
h task ls
h task start my-feature
h task start my-feature api
h task switch
h task switch my-feature
h task current
h task cd
h task cd my-feature api
h task path my-feature
h task branch
h task stop my-feature
h subtask ls
h subtask start auth
h subtask switch
```

## h queue

`h queue` manages the Claude prompt queue — a directory-based task system that runs prompts through the `claude` CLI in tmux windows.

Queue directories live in `~/.config/hiiro/data/queue/{wip,pending,running,done,failed}/`.

| Subcommand | Description |
|------------|-------------|
| `ls` / `list` | List all tasks with status and elapsed time |
| `status` | Detailed status with working directory info |
| `add [args]` | Create a new pending prompt |
| `hadd [args]` | Add and launch in a horizontal tmux split |
| `vadd [args]` | Add and launch in a vertical tmux split |
| `cadd [args]` | Add and run in current tmux split |
| `sadd [args]` | Add scoped to current tmux session |
| `wip [name]` | Create or edit a work-in-progress prompt |
| `ready [name]` | Move wip prompt to pending |
| `run [name]` | Launch pending task(s) in tmux windows |
| `watch` | Continuously poll and launch pending tasks |
| `attach [name]` | Switch to a running task's tmux window |
| `session` | Open the queue tmux session |
| `kill [name]` | Kill a running task |
| `retry [name]` | Move failed/done task back to pending |
| `clean` | Remove all done/failed task files |
| `dir` | Print queue directory path |

**add options**

| Flag | Short | Description |
|------|-------|-------------|
| `--task` | `-t` | Task name to associate |
| `--name` | `-n` | Base filename for the task |
| `--find` | `-f` | Choose task interactively |
| `--horizontal` | `-h` | Launch in horizontal split |
| `--vertical` | `-v` | Launch in vertical split |
| `--session` | `-s` | Use current tmux session |
| `--ignore` | `-i` | Fire-and-forget (no persistent shell) |

**ls options**

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Show all tasks (with pager if needed) |
| `--status` | `-s` | Filter by status (repeatable) |

**Prompt frontmatter**

Prompts are Markdown files with optional YAML frontmatter:

```markdown
---
task_name: my-task
tree_name: my-task/main
session_name: my-task
app: api
dir: packages/api
ignore: true
---
Your prompt text here.
```

**Examples**

```bash
h queue ls
h queue add
h queue add "Fix the login bug"
h queue add -t my-task "Refactor the auth module"
h queue hadd
h queue wip my-draft
h queue ready
h queue run
h queue watch
h queue attach
h queue kill my-task
h queue retry failed-task
h queue clean
```

## External subcommands

These are separate bin files dispatched by `h`:

| Command | Description |
|---------|-------------|
| [`h app`](h-app.md) | App directory and sub-tool management |
| [`h bg`](h-bg.md) | Run commands in background tmux windows |
| [`h bin`](h-bin.md) | List and edit bin executables |
| [`h branch`](h-branch.md) | Git branch management |
| [`h buffer`](h-buffer.md) | tmux buffer management |
| [`h claude`](h-claude.md) | Claude CLI integration and queue |
| [`h commit`](h-commit.md) | Interactive commit selection |
| [`h config`](h-config.md) | Open config files in editor |
| [`h cpr`](h-cpr.md) | Shortcut to current branch's PR |
| [`h db`](h-db.md) | SQLite database inspection and management |
| [`h img`](h-img.md) | Image clipboard utilities |
| [`h jumplist`](h-jumplist.md) | Vim-style tmux navigation history |
| [`h link`](h-link.md) | URL bookmark management |
| [`h misc`](h-misc.md) | Miscellaneous utilities |
| [`h notify`](h-notify.md) | tmux notification system |
| [`h pane`](h-pane.md) | tmux pane management |
| [`h pm`](h-pm.md) | Project manager skill launcher |
| [`h plugin`](h-plugin.md) | Plugin management |
| [`h pr`](h-pr.md) | GitHub PR management |
| [`h pr-monitor`](h-pr-monitor.md) | PR monitoring dashboard |
| [`h project`](h-project.md) | Project directory and tmux session manager |
| [`h registry`](h-registry.md) | Generic resource registry |
| [`h session`](h-session.md) | tmux session management |
| [`h sha`](h-sha.md) | Interactive git SHA selection |
| [`h sparse`](h-sparse.md) | Git sparse checkout group management |
| [`h tags`](h-tags.md) | Tag management |
| [`h title`](h-title.md) | Terminal tab title management |
| [`h todo`](h-todo.md) | Todo item management |
| [`h window`](h-window.md) | tmux window management |
| [`h wtree`](h-wtree.md) | Git worktree management |
