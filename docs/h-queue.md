# h queue

Manage a directory-based prompt queue that launches native `omp` in Herdr tabs, explicit calling-pane splits, or the current process.

Queue directories live in `~/.local/share/hiiro/queue/{wip,pending,running,done,failed}/`. Each task is a Markdown file with optional YAML frontmatter.

## Synopsis

```bash
h queue <subcommand> [args]
```

## Subcommands

### add

Create a new pending queue task. Adds the task to the `pending` directory immediately.

With no arguments (and a TTY), opens your editor with frontmatter pre-filled from the current task context. With arguments, uses the argument text as the prompt. From stdin, reads the prompt from stdin.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--task` | `-t` | Task name to associate (prefix-matched against tasks and workspaces) | auto-detected |
| `--name` | `-n` | Base filename for the queue task | derived from prompt content |
| `--find` | `-f` | Choose task/workspace interactively via fuzzyfind | false |
| `--horizontal` | `-h` | Split below the calling pane and run native `omp` | false |
| `--vertical` | `-v` | Split right of the calling pane and run native `omp` | false |
| `--session` | `-s` | Associate with the calling Herdr workspace | false |
| `--ignore` | `-i` | Run `omp -p` without starting an extra shell afterward | false |

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

### attach

Focus a running task's recorded Herdr tab or workspace. With no name, opens a fuzzyfind selector over running tasks.

**Examples**

```bash
h queue attach
h queue attach my-task
```

---

### cadd

Shortcut for `h queue add` that runs native `omp` in the current process.

**Examples**

```bash
h queue cadd
h queue cadd "Run the migration"
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

Print the queue root directory path (`~/.local/share/hiiro/queue`).

**Examples**

```bash
h queue dir
```

---

### hadd

Shortcut for `h queue add --horizontal`. Open the editor below the calling pane; after valid edited context resolves, run native `omp` there.

**Examples**

```bash
h queue hadd
h queue hadd -t my-task
```

---

### kill

Close a running task's recorded Herdr pane or tab and move it to `failed`. With no name and exactly one running task, closes it automatically.

**Examples**

```bash
h queue kill
h queue kill my-task
```

---

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

### pane-dir

Internal subcommand. Resolve edited task/tree/workspace/app/directory frontmatter through the same context as normal launch. Missing or ambiguous explicit targets fail on stderr instead of returning a fallback directory.

```bash
directory="$(h queue pane-dir /path/to/prompt.md /base/dir)" || exit $?
cd "$directory" || exit $?
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

### retry

Move a failed or done task back to `pending` for re-execution.

**Examples**

```bash
h queue retry
h queue retry my-failed-task
```

---

### run

Launch one or all pending tasks in Herdr tabs. If a task name is provided, launches that specific task (it must be `pending`). Without a name, launches all pending tasks.

**Examples**

```bash
h queue run
h queue run my-task-name
```

---

### sadd

Add a task scoped to the current Herdr workspace. Equivalent to `h queue add --session`, but also launches the task immediately in that workspace.

**Examples**

```bash
h queue sadd
h queue sadd "Run the test suite"
```

---

### session

Open (or create) the default queue Herdr workspace (`hq`).

**Examples**

```bash
h queue session
```

---

### status

Show detailed status for all tasks, including elapsed time, Herdr pane/tab IDs, and working directory.

**Examples**

```bash
h queue status
```

---

### vadd

Shortcut for `h queue add --vertical`. Opens the editor in a new Herdr pane to the right.

**Examples**

```bash
h queue vadd
h queue vadd "Fix the login bug"
```

---

### watch

Poll the pending queue every 2 seconds and launch pending tasks as new Herdr tabs. Automatically restarts itself if a new Hiiro version is detected.

**Examples**

```bash
h queue watch
```

---

### wip

Create or edit a work-in-progress prompt in the `wip` directory. Unlike `add`, tasks in `wip` are not queued — they must be moved to `pending` via `ready`. With no name and existing wip tasks, opens a fuzzyfind selector.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--task` | `-t` | Task name | auto-detected |
| `--find` | `-f` | Choose task/workspace interactively | false |
| `--session` | `-s` | Associate with current Herdr workspace | false |

**Examples**

```bash
h queue wip my-draft
h queue wip          # fuzzy-select from existing wip tasks
```

---

## Prompt frontmatter

Prompts are Markdown files with optional YAML frontmatter. Frontmatter controls the native `omp` launch context:

```yaml
---
task_name: my-task           # associate with a hiiro task
tree_name: my-task/main      # worktree to use as working dir
session_name: my-task        # compatibility field: Herdr workspace label
app: api                     # app name to cd into (resolved via canonical AppRecord)
dir: packages/api            # subdirectory within app or tree root
ignore: true                 # use omp -p; do not start an extra shell
---
Your prompt text here.
```

Normal launch and `h queue pane-dir PROMPT [BASE_DIR]` use the same strict context resolution:

1. An explicit `task_name` selects the canonical task; otherwise retain the injected/current optional context.
2. An explicit `tree_name` overrides the root. Otherwise use the selected task root, then the named workspace’s directory.
3. `session_name` selects placement; without a task/tree, its directory becomes the root. A workspace without a checkout path can use only the explicit calling pane in that workspace, not its first or focused pane.
4. `app` selects a canonical app beneath that root; `dir` selects an existing relative directory beneath the effective app/root.

Exact names win over prefixes. Ambiguity uses mapped terminal selection or fails non-interactively. Missing task/tree/workspace/app/directory, blank explicit selectors, conflicting terminal IDs, and traversal/symlink escapes are errors rather than fallback choices. A directory-resolution failure leaves pending prompt bytes/status unchanged and creates no launcher/body. Emitted shells stop on editor, resolution, or `cd` failure before starting the agent. Cancellation launches nothing.

`t queue TASK [--app APP] ...` injects the selected task/app context. `h queue` keeps resolution lazy so explicit frontmatter can override ambient task inference. `pane-ignore` reads the edited `ignore` value for the pane launcher; true runs `omp -p` without a following shell.
