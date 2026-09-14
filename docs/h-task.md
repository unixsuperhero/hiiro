# Task commands

`t` manages durable tasks. A task can be a coding project, an investigation, or administrative work. It does not need Git or Herdr.

Task records and resource references live in `~/.config/hiiro/hiiro.db`, in the existing `tasks` table and the `task_resources` table. `h task` uses the same records. Its YAML file is a backup, not a separate task store.

Task todos use the existing `todos` table shared with `h todo`. `t` writes to the database directly and does not rewrite the task YAML backup or `todo.yml`.

## t

The command implementation is `Hiiro::TaskCli` in `lib/hiiro/task_cli.rb`; `exe/t` and `exe/tt` are gem executables that call `Hiiro::TaskCli.setup` and `Hiiro::TaskCli.setup_todo` from `Hiiro.run`. Installing the gem installs both. `tt` runs the todo scope in-process. `t` does not run `h task` or discover legacy `t-*` executables.

The grammar is `t TASK COMMAND...`. Bare `t`, `t ls`, or `t list` lists all tasks, including done and archived tasks, with open todo counts. `t TASK` shows the task. Only exact root `t help` displays generic usage and native scoped help without looking up a task. First words such as `new`, `show`, `edit`, `pry`, and `he` are task references, not root commands or help abbreviations.

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

Bare `t`, `t ls`, and `t list` list tasks regardless of context or the saved task, showing each name with its open todo count, e.g. `prez (3)`. There is no root `new` or `show` action. `next`, `waiting`, and `status` without a payload display the selected task's current value.

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

`h task` is the same program as `t`: `bin/h-task` is a symlink to `exe/t`, so `h task ARGS...` behaves exactly like `t ARGS...` with the task-first grammar above. `h subtask` is gone; a subtask is a task named `parent/child`, and `t parent/child tree new` creates its worktree under `~/work/parent/child`.

Worktree operations that used to live only under `h task` are now task commands:

| Old | Now |
|---|---|
| `h task start NAME [APP] [-s GROUP]` | `t NAME tree new [--app APP] [--sparse GROUP]` (creates the task record if needed, then the worktree, then the Herdr workspace) |
| `h task switch NAME [APP]` | `t NAME switch [--directory DIR]` |
| `h task stop NAME` | `t NAME tree rm` (detaches the worktree, keeps the directory, registers it as a directory resource) |
| `h task resume [TREE]` | `t NAME tree resume [TREE]` |
| `h task path`, `h task branch`, `h task tree` | `t TASK path`, `t TASK branch`, `t TASK tree` |
| `h task sh [CMD...]` | `t TASK sh [CMD...]` |
| `h task cd` | `t TASK cd` |
| `h task todo ...` | `t TASK todo ...` or `tt TASK ...` |
| `h task ls` | `t ls` |
| `h task current` | `t . current` |
| `h task queue`, `service`, `run`, `file` | `h queue`, `h service`, `h run`, `h file` |

`h task tag`, `untag`, `tags`, `sparse`, `from`, `prune`, `apps`, `save`, `status`, and `prs` were not carried over. Tag branches with `h branch tag`, inspect worktrees with `h wtree`, and register an existing directory with `t TASK directory add PATH --primary`.

`Hiiro::TaskManager` still holds the worktree creation code that `t TASK tree new` and the shared `Hiiro::CurrentTask` resolver use; `h service`, `h run`, and `h file` keep using it for the current task through `Environment#task`, which now also recognizes a task by its home, primary directory, or registered directories.
