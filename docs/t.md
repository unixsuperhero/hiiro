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

The current task is resolved by `Hiiro::CurrentTask`: explicit selection, then the calling Herdr workspace, realpath directory containment, and the task saved by `t use`. With no context, a terminal gets a mapped task picker; non-interactive runs fail. Ambiguous directory/workspace matches, stale pins, conflicting IDs, and a Herdr context without calling IDs remain visible errors. Explicit task data commands bypass inference; terminal operations still validate their supplied IDs. List, create, and help commands do not resolve the current task.

`Hiiro::TaskLocation` records `task_source` separately from directory `source`, keeps the root distinct from the effective app/override directory, and carries captured workspace/tab/pane IDs. Directory overrides win over app selection. Native command payload words, flags, empty arguments, and resume/session values are not context selectors after task selection.

Task names may be `parent/child` for subtasks. `t new NAME` creates exactly `NAME`; nothing else creates tasks. `help`, `ls`, `list`, and `start` are reserved words; a task with one of those names is reachable with `-t NAME`.

## Task record commands

| Command | Behavior |
|---|---|
| `t`, `t ls`, `t list` | List all tasks alphabetically with open todo counts, e.g. `prez (3)`, plus `next:` and `waiting:` text. When Herdr is running, open task workspaces get `@`, their panes show `ID  ~/dir  agent (status)  command`, and loose workspaces follow with IDs. This read-only inventory does not select a current task or validate mutation caller IDs; stale caller IDs never silently hide live rows |
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

`todo add -h` or `--help`, before or immediately after the task, prints help instead of adding. Empty text fails. IDs must belong to the selected task or the orphan scope. `t`, `tt`, and `h todo` share canonical SQLite rows in `todos`. The database allocates IDs; updating or removing one todo preserves unrelated rows and their IDs. None of these commands reads or rewrites `todo.yml`.

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
| `t tree new [NAME] [APP] [--app APP] [--sparse GROUP]` | NAME may be an existing task, a new task to create, or omitted for the current task. Creates or reuses a worktree under `~/work/NAME/main` (or `~/work/parent/child`), records it, and opens the workspace when Herdr is running |
| `t start NAME [APP] [--app APP] [--sparse GROUP]` | Direct alias for `t tree new`; creates the task when needed |
| `t tree rm [TASK]` | Detaches the worktree from the task and its subtasks; the directory stays and is registered as a directory resource |
| `t tree resume [TASK] [TREE]` | Attaches an unassigned worktree by name, or via fuzzy finder |
| `t path [TASK] [APP] [--directory PATH]`, `t abspath ...` | Print the absolute effective directory from the resolved context |
| `t branch [TASK]` | Worktree branch or `(detached)` |
| `t sh [TASK] [CMD...]` | Changes to the start directory and execs a shell or CMD |
| `t cd [TASK] [APP] [--directory PATH]` | Send `cd` to the captured calling Herdr pane after validating its IDs |

Worktree creation is `Hiiro::TaskManager#create_tree`, shared with the legacy `h task start` code path.

APP resolves by exact case-sensitive name or unique prefix, with mapped terminal disambiguation and non-interactive ambiguity errors. Its relative path must exist beneath the task root and cannot escape through traversal or symlinks. Explicit directory overrides must exist and resolve relative to the captured invocation directory. Positional APP and `--app APP` are alternative spellings.

### Contextual workflows

```text
t queue [TASK] [--app APP] COMMAND...
t service [TASK] [--app APP] COMMAND...
t run [TASK] [--app APP] ARGS...
```

The optional app selector precedes the child command. These mounts pass the selected task/root/effective directory into the same queue, service, and runner implementations used by `h`. For example, `t run build --app api all test` runs tools in the build task’s api directory. Native task selection flags retain their leading-argument grammar.

Queue and service launches from these mounts are owned runs ([owned runs](owned-runs.md)). Their completion is process completion only: a queue agent that exits 0 moves its entry to `done/`, never the task; `t done` remains the only way to complete a task.

## Herdr workspaces, tabs, and panes

```text
t switch [TASK] [APP] [--directory PATH] [--show]   alias: workspace
t tab ls [TASK]
t tab new [TASK] [LABEL] [--directory PATH] [--command COMMAND]
t tab open [TASK] [ID|LABEL]
t pane ls [TASK]
t pane open [TASK] [ID|LABEL]
t pane read [TASK] [ID|LABEL]
t pane run [TASK] ID|LABEL [--] COMMAND...
t pane split [TASK] ID|LABEL [--direction right|down] [--directory PATH] [--command COMMAND]
```

These require a running Herdr server. The workspace label is the task session or name with `.` replaced by `_`. `switch` focuses the selected task workspace; an app or directory override sends `cd` to that destination workspace’s focused pane. This placement is distinct from `t cd`, which always targets the calling pane. A directory override wins over the selected app directory.

`switch` also accepts an exact or unique-prefix name of a live workspace without a task, or an exact pane ID such as `w6:p2`. APP is invalid for loose workspaces and panes. A task with the same name wins. The picker maps displayed pane/workspace rows to their original objects; ambiguous targets or absent context open it on a terminal and fail otherwise.

### App directories

`t path TASK APP`, `t switch TASK APP`, and `t cd TASK APP` select APP through the canonical app registry; `--app APP` is the flag form. The app directory is beneath the selected task code directory or home, not an unrelated invocation Git repository. A terminal can disambiguate prefixes with a mapped picker; non-interactive ambiguity and missing targets fail. APP applies only to task workspaces, not loose workspaces or panes.

## Native AI sessions

`t omp [TASK] [ARGS...]`, `t codex` / `cdx`, and `t claude` / `cld` create a new focused tab in the task workspace, creating the workspace if needed, and run the native tool with ARGS forwarded verbatim. A leading argument that is a prefix of `resume` turns into the tool's native resume flag; bare `resume` with exactly one running pane of that tool focuses it instead. These sessions are not owned runs: the native tool runs directly in the new tab so Herdr can detect the agent and the tool keeps its own conversation history. The command fails when Herdr does not create the tab, return its pane, or run the tool there.

## Help

`t help` and `t GROUP help` print Hiiro's generated command list with argument names and options. `t COMMAND --help` prints that command's options. Help never resolves a task or writes anything.

## Storage and side effects

Task rows live in `~/.config/hiiro/hiiro.db`, in `tasks` owned by `Hiiro::TaskRecord`. Resource references live in `task_resources` owned by `Hiiro::TaskResource`, and todos live in `todos`. Mutations update the requested row or fields without replacing a saved collection. IDs, unrelated resources, and task metadata survive these updates. Additional task details, including saved window arrays and timestamps, live in `tasks.metadata_json`.

`t use` stores the fallback task ID as an integer in `pins`, scoped by `command='t'` and `key='current_task'`. Typed pin storage distinguishes strings such as `"42"`, `"false"`, and JSON-looking text from numbers, booleans, and collections. Updating the fallback preserves other pins.

Task homes are `~/notes/work/NAME` with `/` escaped. Document bodies and registered directory/file contents remain ordinary files, not database projections. App aliases resolve through `Hiiro::AppRecord`; app-file, service, tool, and sparse definitions remain files. Legacy task YAML and `todo.yml` are retained explicit import inputs, not fallbacks or newly written backups. See [h-db](h-db.md) for import planning and recovery.

Hiiro records every invocation and initializes database schemas at startup. Startup does not import legacy domain YAML. Reads do not rewrite domain records or legacy sources.

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
