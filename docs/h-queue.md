# h queue

Manage the Claude prompt queue — a directory-based task system that pipes prompts through the `claude` CLI in tmux windows or panes.

Queue directories live in `~/.config/hiiro/data/queue/{wip,pending,running,done,failed}/`. Each task is a Markdown file with optional YAML frontmatter.

## Synopsis

```bash
h queue <subcommand> [args]
```

## Subcommands

### ls / list

List all queue tasks across all statuses, showing status, timestamp, elapsed time (for running tasks), and a preview of the prompt content. Defaults to the 10 most recent tasks per status.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--all` | `-a` | Show all tasks without limit; uses pager if output exceeds terminal height | false |
| `--status` | `-s` | Filter by status (`wip`, `pending`, `running`, `done`, `failed`); repeatable | all |

**Examples**

```bash
h queue ls
h queue ls -a
h queue ls -s running
h queue ls -s pending -s failed
h queue ls pending        # positional status filter (prefix-matched)
```

---

### status

Show detailed status for all tasks, including elapsed time for running tasks, tmux pane/window info, and working directory.

**Examples**

```bash
h queue status
```

---

### watch

Poll the pending queue every 2 seconds and launch any pending tasks as new tmux windows. Automatically restarts itself if a new hiiro version is detected.

**Examples**

```bash
h queue watch
```

---

### run

Launch one or all pending tasks in tmux windows. If a task name is provided, launches that specific task (must be in `pending` status). Without a name, launches all pending tasks.

**Examples**

```bash
h queue run
h queue run my-task-name
```

---

### add

Create a new pending queue task. Adds the task to the `pending` directory immediately.

With no arguments (and a TTY), opens your editor with frontmatter pre-filled from the current task context. With arguments, uses the argument text as the prompt. From stdin, reads the prompt from stdin.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--task` | `-t` | Task name to associate (prefix-matched against tasks and sessions) | auto-detected |
| `--name` | `-n` | Base filename for the queue task | derived from prompt content |
| `--find` | `-f` | Choose task/session interactively via fuzzyfind | false |
| `--horizontal` | `-h` | Open editor in a horizontal split pane and run claude there | false |
| `--vertical` | `-v` | Open editor in a vertical split pane and run claude there | false |
| `--session` | `-s` | Associate with the current tmux session | false |
| `--ignore` | `-i` | Fire-and-forget: run `claude -p` (no persistent shell after) | false |

**Examples**

```bash
h queue add
h queue add "Fix the login bug"
h queue add -t my-task "Refactor the auth module"
h queue add -f
h queue add -n my-task-name "Prompt text"
echo "Do something" | h queue add
```

---

### hadd

Shortcut for `h queue add --horizontal`. Opens the editor in a horizontal tmux split pane; when saved, runs `claude` in that pane.

**Examples**

```bash
h queue hadd
h queue hadd -t my-task
```

---

### vadd

Shortcut for `h queue add --vertical`. Opens the editor in a vertical tmux split pane.

**Examples**

```bash
h queue vadd
h queue vadd "Fix the login bug"
```

---

### cadd

Shortcut for `h queue add` that runs claude in the current tmux pane (via `exec`).

**Examples**

```bash
h queue cadd
h queue cadd "Run the migration"
```

---

### sadd

Add a task scoped to the current tmux session. Equivalent to `h queue add --session`, but also launches the task immediately in the current session.

**Examples**

```bash
h queue sadd
h queue sadd "Run the test suite"
```

---

### wip

Create or edit a work-in-progress prompt in the `wip` directory. Unlike `add`, tasks in `wip` are not queued — they must be moved to `pending` via `ready`. With no name and existing wip tasks, opens a fuzzyfind selector.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--task` | `-t` | Task name | auto-detected |
| `--find` | `-f` | Choose task/session interactively | false |
| `--session` | `-s` | Associate with current tmux session | false |

**Examples**

```bash
h queue wip my-draft
h queue wip          # fuzzy-select from existing wip tasks
```

---

### ready

Move a wip task to `pending`, making it eligible for `run`/`watch`. With no name and exactly one wip task, moves it automatically. With multiple wip tasks, opens a fuzzyfind selector.

**Examples**

```bash
h queue ready
h queue ready my-draft
```

---

### attach

Switch to a running task's tmux window. With no name, opens a fuzzyfind selector over running tasks.

**Examples**

```bash
h queue attach
h queue attach my-task
```

---

### session

Open (or create) the default queue tmux session (`hq`).

**Examples**

```bash
h queue session
```

---

### kill

Kill a running task's tmux window/pane and move it to `failed`. With no name and exactly one running task, kills it automatically.

**Examples**

```bash
h queue kill
h queue kill my-task
```

---

### retry

Move a failed or done task back to `pending` for re-execution.

**Examples**

```bash
h queue retry
h queue retry my-failed-task
```

---

### clean

Remove all files from the `done` and `failed` directories.

**Examples**

```bash
h queue clean
```

---

### dir

Print the queue root directory path (`~/.config/hiiro/data/queue`).

**Examples**

```bash
h queue dir
```

---

### pane-dir

Internal subcommand. Resolves the working directory for a pane-launched prompt after editing, accounting for `app:` and `dir:` frontmatter fields. Used by the `hadd`/`vadd`/`cadd` shell scripts.

```bash
cd $(h queue pane-dir /path/to/prompt.md /base/dir)
```

---

## Prompt frontmatter

Prompts are Markdown files with optional YAML frontmatter. The frontmatter controls where claude runs (task/tree/session/app/dir resolution):

```yaml
---
task_name: my-task           # associate with a hiiro task
tree_name: my-task/main      # worktree to use as working dir
session_name: my-task        # tmux session (overrides task lookup)
app: api                     # app name to cd into (resolved via apps.yml)
dir: packages/api            # subdirectory within app or tree root
ignore: true                 # fire-and-forget: close window when done
---
Your prompt text here.
```

The resolution order for working directory is:

1. `session_name` (from the active pane's CWD if no tree)
2. `tree_name` (sets working dir to the worktree path)
3. `app` + `dir` (resolved relative to tree root)
