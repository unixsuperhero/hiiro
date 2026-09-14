# Task commands

`t` manages durable tasks. A task can be a coding project, an investigation, or administrative work. It does not need Git or Herdr.

Task records and resource references live in `~/.config/hiiro/hiiro.db`, in the existing `tasks` table and the `task_resources` table. `h task` uses the same records. Its YAML file is a backup, not a separate task store.

Task todos use the existing `todos` table shared with `h todo`. `t` writes to the database directly and does not rewrite the task YAML backup or `todo.yml`.

## t

The command implementation lives in the repository's `bin/t`, not a `Hiiro::TaskCLI` library class. `~/bin/t` is a symlink to that executable, which loads the repository library. Installing the gem does not install this launcher. `bin/tt` delegates to its todo scope. `t` does not run `h task` or discover legacy `t-*` executables.

The grammar is `t TASK COMMAND...`. Bare `t` lists all tasks, including done and archived tasks. `t TASK` shows the task. Only exact root `t help` displays generic usage and native scoped help without looking up a task. First words such as `new`, `show`, `edit`, `pry`, and `he` are task references, not root commands or help abbreviations.

Named references match an exact name first, then a unique case-sensitive prefix. Ambiguous prefixes are errors. Unknown names fail except with `t NAME new` or `t NAME todo add TEXT...`. Explicit `new` creates exactly `NAME` without prefix resolution. `t TASK help` shows task commands, and `t TASK todo help` shows todo commands. Native command abbreviations apply inside these scopes.

Use `.` to select the current task, including when supplying a payload: `t . next 'Compare the export'`. Selection checks the calling Herdr workspace, then the current directory inside a task home, code directory, or registered directory, then the saved task. Workspace context wins over a conflicting directory. Ambiguous matches and invalid, stale, or conflicting Herdr IDs are errors. Outside Herdr, an unrelated focused workspace does not affect selection. An explicit name bypasses context lookup.

`t TASK current` prints the resolved name and saves a named selection without changing terminal focus. `t . current` only prints it. The fallback is a `PinRecord` with `command='t'`, `key='current_task'`, and the task ID as a JSON integer in `value_json`. A missing saved task is an error when selection reaches that fallback. Reads and workspace opens through `.` do not replace it.

### Task records

```text
t
t TASK
t TASK show
t TASK current
t NAME new
t TASK next [TEXT...] [--clear]
t TASK status [active|waiting|done|archived]
t TASK waiting [TEXT...] [--clear]
t TASK done
t TASK archive
```

Bare `t` lists tasks regardless of context or the saved task. There is no root `list`, `ls`, `new`, or `show` action. `next`, `waiting`, and `status` without a payload display the selected task's current value.

`t NAME new` creates a record and `~/notes/work/NAME`. It never creates a Git worktree, moves code, or launches Herdr. Repeating `new` keeps the exact existing record and ensures its home exists. Names contain 1-120 ASCII letters, digits, dots, underscores, or hyphens and start with a letter or digit. Existing names that contain other characters remain usable, with those characters percent-encoded in the computed home directory name.

Setting waiting text changes status to `waiting`. Clearing that text changes a waiting task back to `active`. `done` and `archive` change status and record timestamps. They never remove todos, a task home, a file, a directory, a link, or a workspace. `t TASK status active` reopens a task.

```bash
t audit-invoices new
t audit-invoices next 'Compare the September export'
t audit-invoices waiting 'Finance approval'
t audit-invoices waiting --clear
t audit-invoices done
t audit-invoices
```

### Task todos

```text
t TASK todo
t TASK todo list
t TASK todo ls
t TASK todo add TEXT...
t TASK todo rm ID
tt TASK [COMMAND...]
tt
tt help
```

`tt TASK ...` delegates to `t TASK todo ...`. Bare `tt` means `t . todo`, and `tt help` shows todo help without task lookup. The default todo action is listing. `t - todo` and `tt -` select orphan todos, with `add` and `rm` available in that scope. `-` is invalid outside todo commands and never creates a task.

If a named `todo add` finds no match, it creates the task using `new` validation and home rules, then adds one todo with status `not_started`. Task and todo database writes use one immediate SQLite transaction. Other todo actions never create tasks.

Every token after `add` is literal text, including flags and `--`, except that leading `add -h` or `add --help` displays native option help. The tokens are joined with spaces. Missing, empty, or whitespace-only text fails before task creation.

```bash
t audit-invoices todo add Compare the September export
tt audit-invoices add Inspect --help output
t audit-invoices todo
t audit-invoices todo rm 42
tt - add Buy printer paper
```

Use an ID printed by `show` or todo listing in place of `42`. `rm` accepts exactly one decimal database ID belonging to the selected scope, not a list position or suffix. Missing, invalid, or extra arguments fail.

Task display and todo listing print each matching item's ID, status, and text in ID order. Matching uses the full task name exactly, including legacy rows with both `task_name` and `subtask_name`. A parent task does not include its subtasks' todos. New task todos store the full task name in `task_name` and leave `subtask_name` unset. Orphan rows leave both unset.

Each task still has one independent `next_action`. Adding or removing todos does not change that field, task status, or saved selection. `t` has no todo-completion command or automatic next-action promotion. The separate `h task` and `h todo` commands keep their existing behavior.

### Directory, link, PR, and file references

```text
t TASK directory add PATH [--primary] [--label LABEL]
t TASK directory list
t TASK directory open [ID|PATH|LABEL]
t TASK link add URL [--kind general|issue|thread] [--label LABEL]
t TASK link list [--kind general|issue|thread]
t TASK link open [ID|URL|LABEL]
t TASK pr add URL [--label LABEL]
t TASK pr list
t TASK pr open [ID|URL|LABEL]
t TASK file add PATH [--label LABEL]
t TASK file list
t TASK file open [ID|PATH|LABEL]
```

Directory and file attachments must already exist. `add` stores their canonical paths without moving or copying anything. Repeating an identical attachment does not create another reference. `--primary` marks an attached directory as the default code directory for new workspace tabs and panes. An existing directory can be a Git worktree. Registering it does not create a worktree or alter sparse checkout.

Links must be absolute HTTP or HTTPS URLs. `link list` includes PR references unless a kind filter is present. PRs use the same resource storage as other links and do not require a Git repository or provider API.

`file list` also discovers files in the task home, including documents, without registration. Home files can be opened by a relative path or an unambiguous basename. An omitted open selector works only when exactly one resource matches. Otherwise, the command requires an ID, path, URL, or unique label.

`open` uses the operating system's default application. Attachments remain references even after task completion. List commands also accept `ls`. Leaf help, such as `t audit-invoices directory add --help`, lists options without running the action.

### Documents

```text
t TASK doc new NAME [TITLE...]
t TASK doc list
t TASK doc open [NAME]
```

`doc new` creates a Markdown file in the task home with an initial heading. It never overwrites an existing file. Documents have a stable task-ID prefix, such as `task-42-investigation.md`, to avoid collisions in `mdoc`'s shared HTML output directory. `t TASK doc open investigation` accepts the short name and invokes `mdoc`. Existing Markdown files in the task home also appear without registration.

Task creation, metadata, references, and document creation/listing work without Git or Herdr when a named task is supplied. Document reading requires `mdoc` on `PATH` and its existing configuration.

### Herdr workspaces, tabs, and panes

```text
t TASK workspace [--directory PATH]
t TASK switch [--directory PATH]
t TASK workspace --show
t TASK switch --show
t TASK tab list
t TASK tab new [LABEL] [--directory PATH] [--command COMMAND]
t TASK tab open ID|LABEL
t TASK pane list
t TASK pane open ID|LABEL
t TASK pane read ID|LABEL
t TASK pane run ID|LABEL -- COMMAND...
t TASK pane split ID|LABEL [--direction right|down] [--directory PATH] [--command COMMAND]
```

These commands require a running Herdr server. `t TASK workspace` and its `switch` alias focus the workspace with the task's label or create one. They save a named task only after a successful switch. `t . workspace` leaves the saved fallback unchanged. A new workspace starts in the explicit directory, the primary code directory, the legacy worktree, or the task home, in that order. `--directory` changes that operation's start directory without changing stored attachments.

`--show` queries the current tabs and panes without saving, focusing, or creating a workspace. `workspace` and `switch` are direct commands, not groups. Native Hiiro abbreviation matching accepts `t TASK wor`.

Tab and pane selectors must belong to the selected task's workspace. Duplicate labels require a live ID. No pane or tab ID is stored as durable task identity. Task workspace labels follow Herdr's dot-to-underscore normalization. Colliding task or workspace labels are errors rather than fuzzy matches.

Use `--` before literal command arguments that begin with a dash:

```bash
t audit-invoices pane run PANE_ID -- printf '%s\n' --example
```

### Native AI sessions

`t TASK omp`, `t TASK codex` or `cdx`, and `t TASK claude` or `cld` create new focused tabs in the task workspace. They launch the native `omp`, `codex`, and `claude` executables, respectively. The workspace is created if needed. Fresh sessions are the default.

Only the first tool argument can select resume mode. A nonempty prefix of `resume`, such as `r`, `res`, or `resume`, consumes that token. OMP and Claude receive `--resume`; Codex receives its `resume` subcommand.

With no remaining arguments, resume focuses the unique genuinely running tool in that workspace, using Herdr's agent metadata rather than the tab label. Multiple running matches are an error that reports their IDs. If none is running, a new tab launches the native resume picker.

With any remaining arguments, resume always opens a new tab and forwards those arguments unchanged. Session IDs and options belong to the native CLI. Other arguments, including `--help` and `--`, also pass through unchanged. `t` does not inject model, permission, continue, or fresh-session flags.

```bash
t audit-invoices omp
t audit-invoices cdx r
t audit-invoices cld resume SESSION_ID
t audit-invoices codex resume --help
t audit-invoices claude --help
```

The launcher scopes live-pane lookup to the task workspace. Persisted session discovery remains native CLI behavior and is not necessarily task-isolated when tasks share a directory. `t` performs no auth or API requests and makes no automatic Git changes.

## h task

The existing `h task` commands below retain their coding-worktree operations. Unlike `t NAME new`, `h task start` can create a worktree for a new task. For a task without a worktree, path resolution uses its task home. Starting an existing noncoding task switches to that home without creating a worktree.

## Synopsis

```bash
h task <subcommand> [args]
```

## Subcommands

### app

Open a named app in a new Herdr tab within the current task workspace. With no argument, opens a fuzzyfind selector over configured apps.

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

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--task` | `-t` | Task name | current task |
| `--find` | `-f` | Choose task interactively | false |
| `--all` | `-a` | Print branch for every task; positional args become prefix filters (OR'd) | false |

**Examples**

```bash
h task branch
h task branch my-feature
h task branch -a               # print branch for every task
h task branch -a feat bug      # tasks whose name starts with "feat" or "bug"
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

Send a `cd` command to the current Herdr pane, navigating to a task's worktree or app subdirectory.

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

### csession

Print the Herdr workspace label stored for the **current** task.

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

Print the name of the current task based on the Herdr workspace or worktree match. Exits with an error if not in a task.

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

### from

Register an existing git worktree as a Hiiro task and switch to it. The path is normalized to the worktree root with `git rev-parse --show-toplevel`, then stored as the task's tree path.

**Examples**

```bash
h task from ~/ic_repos/other_repo_base_dir other-task
h task path other-task
h task switch other-task
```

Stored task shape:

```js
{
  name: "other-task",
  tree: "/Users/josh/ic_repos/other_repo_base_dir",
  session: "other-task"
}
```

---

### ls / list

List all tasks with their worktree, branch, and workspace label. It also shows available worktrees and extra Herdr workspaces.

A `*` prefix marks the current task. An `@` prefix indicates the Herdr workspace is focused.

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
| `--all` | `-a` | Print path for every task; positional args become prefix filters (OR'd). App / glob args are ignored in this mode. | false |

**Examples**

```bash
h task path
h task path my-feature
h task path my-feature api
h task path my-feature api "**/*.rb"
h task path -a                 # print worktree path for every task
h task path -a feat bug        # tasks whose name starts with "feat" or "bug"
```

---

### prune

Detach worktree associations whose directories are missing. The task record, metadata, and resource references remain. Tasks without worktrees are not pruned. Defaults to a dry-run.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--force` | `-f` | Detach missing worktrees | false |

**Examples**

```bash
h task prune        # show what would be pruned
h task prune -f     # detach missing worktrees, retaining task records
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

Associate an available worktree with a new task or an existing task whose worktree was detached, then switch to it. Existing task metadata is preserved. With no argument, opens a fuzzyfind selector over available worktrees.

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

Read and report the current task's Herdr tab state.

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

### name

Print the full task name. With no argument, opens a fuzzyfind selector. Useful for scripting alongside `tree -a`, `branch -a`, and `path -a` (results are sorted by name across all four, so they line up).

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--task` | `-t` | Task name | current task |
| `--find` | `-f` | Choose task interactively | false |
| `--all` | `-a` | Print every task's name; positional args become prefix filters (OR'd) | false |

**Examples**

```bash
h task name -a                            # list every task name
h task name -a feat                       # only tasks starting with "feat"
paste <(h task name -a) <(h task path -a) # name <-> path mapping
```

---

### session

Print the stored Herdr workspace label for a task. The `session` command name remains for compatibility. With no argument, it opens a fuzzyfind selector.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--task` | `-t` | Task name | current task |
| `--find` | `-f` | Choose task interactively | false |
| `--all` | `-a` | Print workspace label for every task; positional args become prefix filters (OR'd) | false |

**Examples**

```bash
h task session
h task session my-feature
h task session -a
```

---

### sh

Open a shell (or run a command) in the current task's worktree. With `--session`, create a new Herdr tab in the specified workspace.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--task` | `-t` | Task name | current task |
| `--find` | `-f` | Choose task interactively | false |
| `--session` | `-s` | Run in a new tab in this Herdr workspace | none |

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

Create a new task (worktree + Herdr workspace) and switch to it. If the task already exists, switch to it instead. Reuse an available unassigned worktree when possible; otherwise create a new one.

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

Show detailed info about the current task: name, worktree, path, workspace, and parent (if subtask).

**Examples**

```bash
h task status
h task st
```

---

### stop

Detach a task's worktree association and those of its subtasks. The task records, metadata, workspace labels, and resources remain. The former worktree path becomes a directory reference, and the worktree is available for reuse through `resume`. With no arguments, opens a fuzzyfind selector.

**Examples**

```bash
h task stop my-feature
h task stop
```

---

### switch

Switch to an existing task's Herdr workspace. With no arguments, open a fuzzyfind selector over tasks and workspaces. If the name matches a Herdr workspace rather than a task, focus it directly.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--force` | `-f` | Accepted for compatibility; Herdr workspace focus does not require it | false |

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

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--task` | `-t` | Task name | current task |
| `--find` | `-f` | Choose task interactively | false |
| `--all` | `-a` | Print tree name for every task; positional args become prefix filters (OR'd) | false |

**Examples**

```bash
h task tree
h task tree my-feature
h task tree -a
h task tree -a feat bug
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
