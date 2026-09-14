# t command reference

Reference for the `t` executable, the `tt` todo shortcut, and `h task`, which is a symlink to `t`.

`t` manages task records, next actions, todos, waiting-on information, documents, resource references, git worktrees, and task-associated Herdr terminals. `exe/t` and `exe/tt` are gem executables that call `Hiiro::TaskCli.setup` and `Hiiro::TaskCli.setup_todo` from `Hiiro.run`; the commands and `Hiiro::TaskCli::Commands` helpers live in `lib/hiiro/task_cli.rb`. Expected failures raise `Hiiro::Error` and print only `ERROR: message` on stderr with exit status 1.

## Syntax and task selection

```text
t                                  list tasks
t COMMAND [TASK] [ARGS...]         run a command, optionally naming the task first
t GROUP SUBCOMMAND [TASK] [ARGS...]
tt [SUBCOMMAND] [TASK] [ARGS...]   same as t todo ...
```

The command comes first. Commands that act on a task take it from the first positional argument using the old `h task` rule:

1. If the first positional word names a task, exactly or by a unique case-sensitive prefix, it is the task and is removed from the arguments.
2. Otherwise the current task is used and the word stays in the payload. So `t todo add fix build` adds to the current task and `t todo add prez fix build` adds to `prez`.
3. An ambiguous prefix opens the fuzzy finder over the matching tasks when stdin is a terminal, and is an error otherwise.

`-t TASK` / `--task TASK` forces a task and fails if it does not exist. `-f` / `--find` picks one with `sk` or `fzf`. `.` is the current task, useful when a payload could be mistaken for a name: `t next . Finish slides`. `-` selects orphan todos in todo commands only. Words starting with `-` are never treated as task names. Passthrough commands (`todo add`, `sh`, `pane run`, and the AI launchers) accept `-t`, `--task=NAME`, and `-f` only as their leading arguments.

The current task is resolved by `Hiiro::CurrentTask`: the calling Herdr workspace when `HERDR_*` variables identify one, then the working directory inside a task home, primary directory, worktree, or registered directory, then the task saved by `t use`. With no context at all, a terminal gets the fuzzy finder over every task; non-interactive runs fail. Ambiguous directory or workspace matches and stale or conflicting Herdr IDs are always errors. Commands that only list, create, or show help never resolve the current task.

Task names may be `parent/child` for subtasks. `t new NAME` creates exactly `NAME`; nothing else creates tasks. Only `help`, `ls`, and `list` are reserved words; a task literally named `show` or `new` is reachable with `-t show`.

## Task record commands

| Command | Behavior |
|---|---|
| `t`, `t ls`, `t list` | Lists all tasks alphabetically with open todo counts, e.g. `prez (3)`, plus `next:` and `waiting:` text. When Herdr is running, tasks whose workspace is open get an `@` marker, every open workspace lists its panes as `ID  ~/dir  agent (status)  command` (from `herdr pane process-info`), and live workspaces that belong to no task are listed afterwards with their IDs |
| `t show [TASK]` | Status, home, next action, waiting text, code directory, workspace label, resources, documents, and todos |
| `t current [TASK]` | Prints the resolved task name; never saves |
| `t use TASK` (alias `pin`) | Saves TASK as the fallback for when no workspace or directory identifies a task |
| `t new NAME` | Creates an active task and its notes home under `~/notes/work/NAME`; an existing exact name is preserved |
| `t next [TASK] [TEXT...] [--clear]` | Stores, prints, or clears the next action |
| `t waiting [TASK] [TEXT...] [--clear]` | Stores blocking text and sets `waiting`; clearing returns a waiting task to `active` |
| `t status [TASK] [STATE]` | Prints or sets `active`, `waiting`, `done`, or `archived` |
| `t done [TASK]`, `t archive [TASK]` | Sets the status, recording `completed_at` or `archived_at` |

`done` and `archived` preserve todos, resources, and documents. Setting a status other than done or archived clears those timestamps.

## Todos and tt

| Command | Behavior |
|---|---|
| `t todo [TASK]`, `t todo ls [TASK] [--plain]` | Lists todos as `Todo ID [STATUS]: TEXT`; `--plain` prints text only |
| `t todo add [TASK] TEXT...` | Adds a todo; every word after the task is literal text, including flags and `--` |
| `t todo show [TASK] ID` | Prints only the text of one todo |
| `t todo rm [TASK] ID` | Deletes one todo by exact decimal ID |
| `t todo add - TEXT...`, `t todo -` | Orphan todos with no task |
| `tt ...` | Identical to `t todo ...`; bare `tt` lists the current task's todos |

`todo add -h` or `--help`, before or immediately after the task, prints help instead of adding. Empty text fails. IDs must belong to the selected task or the orphan scope. Todos share the `todos` table with `h todo`; `t` never rewrites `todo.yml`.

## Directory, link, PR, and file references

```text
t directory add [TASK] PATH [--primary] [--label LABEL]
t directory ls [TASK]
t directory open [TASK] [ID|PATH|LABEL]
t link add [TASK] URL [--kind general|issue|thread] [--label LABEL]
t link ls [TASK] [--kind KIND]
t link open [TASK] [ID|URL|LABEL]
t pr add [TASK] URL [--label LABEL]
t pr ls [TASK]
t pr open [TASK] [ID|URL|LABEL]
t file add [TASK] PATH [--label LABEL]
t file ls [TASK]
t file open [TASK] [ID|PATH|LABEL]
```

Directories and files must exist and are stored as real paths. `--primary` sets the task's code directory and applies only to directories. URLs must be absolute http or https. `file ls` also lists unregistered files in the task home. `open` accepts an ID, full target, or label, then a unique prefix of any of them; with no reference and several candidates it opens a fuzzy finder. Opening uses `open` on macOS and `xdg-open` elsewhere.

## Documents

```text
t doc new [TASK] NAME [TITLE...]
t doc ls [TASK]
t doc open [TASK] [NAME]
```

`doc new` creates `task-ID-NAME.md` in the task home with a heading and never overwrites. `doc open` runs `mdoc` on the matched file; NAME may be the short name, file name, or path.

## Worktrees, paths, and shells

| Command | Behavior |
|---|---|
| `t tree [TASK]` | Prints the worktree name and path |
| `t tree new [NAME] [--app APP] [--sparse GROUP]` | NAME may be an existing task, a new task to create, or omitted for the current task. Creates or reuses a worktree under `~/work/NAME/main` (or `~/work/parent/child`), records it, and opens the workspace when Herdr is running |
| `t tree rm [TASK]` | Detaches the worktree from the task and its subtasks; the directory stays and is registered as a directory resource |
| `t tree resume [TASK] [TREE]` | Attaches an unassigned worktree by name, or via fuzzy finder |
| `t path [TASK]` | Start directory: primary directory, worktree, or task home |
| `t branch [TASK]` | Worktree branch or `(detached)` |
| `t sh [TASK] [CMD...]` | Changes to the start directory and execs a shell or CMD |
| `t cd [TASK]` | Sends `cd` to the calling Herdr pane |

Worktree creation is `Hiiro::TaskManager#create_tree`, shared with the legacy `h task start` code path.

## Herdr workspaces, tabs, and panes

```text
t switch [TASK] [--directory PATH] [--show]      alias: workspace
t tab ls [TASK]
t tab new [TASK] [LABEL] [--directory PATH] [--command COMMAND]
t tab open [TASK] [ID|LABEL]
t pane ls [TASK]
t pane open [TASK] [ID|LABEL]
t pane read [TASK] [ID|LABEL]
t pane run [TASK] ID|LABEL [--] COMMAND...
t pane split [TASK] ID|LABEL [--direction right|down] [--directory PATH] [--command COMMAND]
```

These require a running Herdr server. The workspace label is the task session or name with `.` replaced by `_`. `switch` also accepts the name of a live Herdr workspace that belongs to no task, exactly or by unique prefix, and focuses it; a task with the same name wins. An exact pane ID such as `w6:p2` focuses that pane, and the picker lists every live pane with its directory and foreground command. When the name is ambiguous, or no task or context is given, a terminal gets a fuzzy finder over tasks and loose workspaces, with duplicate workspace names numbered in the label only. `switch` focuses the existing task workspace or creates it in the start directory (`--directory`, else primary directory, worktree, or home), and saves the task as the fallback when it was named explicitly. `--show` only prints the workspace, tabs, and panes. Tab and pane references match a live ID or label, then a unique prefix; with no reference and several candidates a fuzzy finder opens.

## Native AI sessions

`t omp [TASK] [ARGS...]`, `t codex` / `cdx`, and `t claude` / `cld` create a new focused tab in the task workspace, creating the workspace if needed, and run the native tool with ARGS forwarded verbatim. A leading argument that is a prefix of `resume` turns into the tool's native resume flag; bare `resume` with exactly one running pane of that tool focuses it instead.

## Help

`t help` and `t GROUP help` print Hiiro's generated command list with argument names and options. `t COMMAND --help` prints that command's options. Help never resolves a task or writes anything.

## Storage and side effects

Task rows live in the `tasks` table (`Hiiro::TaskRecord`), resources in `task_resources`, todos in `todos`, and the saved fallback in `pins` as `command='t'`, `key='current_task'`. Task homes are `~/notes/work/NAME` with `/` escaped. Hiiro also records every invocation. Only `new`, `tree new`, `doc new`, and `use` write outside their named target; reads never write.

## Source map

| Source | Responsibility |
|---|---|
| `exe/t`, `exe/tt`, `bin/h-task` | Launchers (`bin/t`, `bin/tt`, `bin/h-task` are symlinks) |
| `lib/hiiro/task_cli.rb` | `Hiiro::TaskCli` and the `Commands` module: task resolution rule, all commands |
| `lib/hiiro/current_task.rb` | Current-task resolution shared with `Environment#task` |
| `lib/hiiro/task_sessions.rb` | Native AI launch and resume |
| `lib/hiiro/task_record.rb` | Task and resource models, home naming |
| `lib/hiiro/tasks.rb` | `TaskManager#create_tree`, `Tree`, `Environment` |
| `lib/hiiro/todo.rb` | `TodoItem` rows |
| `lib/hiiro/herdr.rb` | Herdr adapter |
