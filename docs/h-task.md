# h task

Manage top-level tasks. Each task is a worktree + tmux session pair. Tasks enable parallel development across multiple features — each with an isolated checkout and its own tmux session.

Tasks are stored in `~/.config/hiiro/tasks/tasks.yml` (SQLite-backed with YAML backup).

## Synopsis

```bash
h task <subcommand> [args]
```

## Subcommands

### app

Open a named app in a new tmux window within the current task session. With no argument, opens a fuzzyfind selector over configured apps.

**Examples**

```bash
h task app
h task app api
```

---

### apps

List all configured apps and their relative paths.

**Examples**

```bash
h task apps
```

---

### branch

Print the git branch for a task. With no argument, opens a fuzzyfind selector. Outputs nothing if the tree is detached.

**Examples**

```bash
h task branch
h task branch my-feature
```

---

### branches

List branches for the current task. Delegates to `h branch`.

---

### cbranch

Print the git branch of the **current** task. Exits with an error if not in a task.

**Examples**

```bash
h task cbranch
```

---

### cd

Send a `cd` command to the current tmux pane, navigating to a task's worktree or app subdirectory.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--task` | `-t` | Task name | current task |
| `--find` | `-f` | Choose task interactively | false |

**Examples**

```bash
h task cd
h task cd my-feature
h task cd my-feature api
h task cd -t my-feature
```

---

### color

Apply the current task's color theme to its tmux session.

**Examples**

```bash
h task color
```

---

### csession

Print the tmux session name of the **current** task.

**Examples**

```bash
h task csession
```

---

### ctree

Print the worktree name of the **current** task.

**Examples**

```bash
h task ctree
```

---

### current

Print the name of the current task (based on tmux session or worktree match). Exits with an error if not in a task.

**Examples**

```bash
h task current
```

---

### edit

Open the `tasks.rb` source file in your editor.
### file

Manage tracked app files for the current task. Delegates to the app files system.

**Examples**

```bash
h task file ls
h task file add myapp path/to/file.rb
```

---

### ls / list

List all tasks with their worktree, branch, and session. Also shows available (unassigned) worktrees and extra tmux sessions.

A `*` prefix marks the current task. An `@` prefix indicates the session has an active tmux client attached.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--tag` | `-t` | Filter by tag (OR logic; repeatable) | all |

**Examples**

```bash
h task ls
h task ls -t urgent
h task ls -t api -t frontend
```

---

### path

Print the absolute path to a task's worktree or app subdirectory. With glob patterns, lists matching files.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--task` | `-t` | Task name | current task |
| `--find` | `-f` | Choose task interactively | false |

**Examples**

```bash
h task path
h task path my-feature
h task path my-feature api
h task path my-feature api "**/*.rb"
```

---

### prs

List PRs for the current task. Delegates to `h pr`.

---

### queue

Run the Claude prompt queue scoped to the current task. All `h queue` subcommands are available. See [h-queue](h-queue.md).

**Examples**

```bash
h task queue ls
h task queue add "Fix the login bug"
h task queue hadd
```

---

### resume

Re-register an available (unassigned) worktree as a new task and switch to it. With no argument, opens a fuzzyfind selector over available worktrees.

**Examples**

```bash
h task resume
h task resume my-feature/main
```

---

### run

Run linters, tests, or formatters against changed files for the current task. Delegates to the runner tool system.

**Examples**

```bash
h task run
h task run lint
h task run test ruby
```

---

### save

Save the current task's tmux window state.

**Examples**

```bash
h task save
```

---

### service

Manage dev services scoped to the current task. All `h service` subcommands are available. See [h-service](h-service.md).

**Examples**

```bash
h task service ls
h task service start my-rails
```

---

### session

Print the tmux session name for a task. With no argument, opens a fuzzyfind selector.

**Examples**

```bash
h task session
h task session my-feature
```

---

### sh

Open a shell (or run a command) in the current task's worktree. With `--session`, creates a new tmux window in the specified session.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--task` | `-t` | Task name | current task |
| `--find` | `-f` | Choose task interactively | false |
| `--session` | `-s` | Run in a new window in this tmux session | none |

**Examples**

```bash
h task sh
h task sh -t my-feature
h task sh my-feature bundle exec rails s
h task sh -s my-session
```

---

### sparse

Manage sparse checkout for the current task's worktree.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--list` | `-l` | List all configured sparse groups |
| `--disable` | `-d` | Disable sparse checkout on current task |

**Examples**

```bash
h task sparse              # show active sparse checkout
h task sparse default      # apply 'default' group
h task sparse -l           # list all groups
h task sparse -d           # disable sparse checkout
```

---

### start

Create a new task (worktree + tmux session) and switch to it. If the task already exists, switches to it instead. Reuses an available unassigned worktree when possible; otherwise creates a new one.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--sparse` | `-s` | Apply a sparse checkout group (repeatable) | none |

**Examples**

```bash
h task start my-feature
h task start my-feature api        # open in app subdirectory
h task start my-feature -s default
```

---

### status / st

Show detailed info about the current task: name, worktree, path, session, and parent (if subtask).

**Examples**

```bash
h task status
h task st
```

---

### stop

Remove a task from the task list (preserves the worktree for future reuse via `resume`). With no arguments, opens a fuzzyfind selector.

**Examples**

```bash
h task stop my-feature
h task stop
```

---

### switch

Switch to an existing task's tmux session. With no arguments, opens an interactive fuzzyfind selector over tasks and sessions. If the task name matches a tmux session (not a task), switches to that session directly.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--force` | `-f` | Switch even if the session is already attached | false |

**Examples**

```bash
h task switch
h task switch my-feature
h task switch my-feature api
h task switch my-session -f
```

---

### tag

Add tags to a task. With `--edit`, opens a YAML editor for bulk tagging.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--edit` | `-e` | Open YAML editor to bulk-tag tasks |

**Examples**

```bash
h task tag my-feature urgent
h task tag my-feature api backend
h task tag -e
```

---

### tags

List all tagged tasks, grouped by tag.

**Examples**

```bash
h task tags
```

---

### todo

Manage todo items scoped to the current task. See [h-todo](h-todo.md) for the full todo system.

**Subcommands:** `ls`, `add`, `rm`, `start`, `done`, `skip`, `search`

**Examples**

```bash
h task todo
h task todo add "Fix the login bug"
h task todo add -t urgent "Refactor auth"
h task todo done 0
```

---

### tree

Print the worktree name for a task. With no argument, opens a fuzzyfind selector.

**Examples**

```bash
h task tree
h task tree my-feature
```

---

### untag

Remove tags from a task. With no tags, removes all tags.

**Examples**

```bash
h task untag my-feature urgent
h task untag my-feature          # remove all tags
```

---

### wtrees

List worktrees for the current task. Delegates to `h wtree`.

---

