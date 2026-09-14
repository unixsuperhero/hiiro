# t command reference

Reference for the repository's `bin/t` executable and `bin/tt` todo shortcut.

`t` manages task records, next actions, todos, waiting-on information, documents, resource references, and task-associated Herdr terminals. It does not create Git worktrees or configure sparse checkout. Those operations belong to the separate `h task` commands.

`bin/t` contains the command declarations and `TaskCommands` helpers. `~/bin/t` and `~/bin/tt` are symlinks to the repository launchers. Both resolve their real paths and put the repository library first on Ruby's load path. Installing the Hiiro gem does not install these launchers.

## Syntax and task selection

```text
t
t help
t TASK [COMMAND...]
t TASK GROUP [COMMAND...]
tt TASK [COMMAND...]
```

Uppercase words are values to supply. Square brackets indicate optional arguments, and `...` means multiple words or arguments.

Bare `t` lists every task, including active, waiting, done, and archived records. It does not select from context. `t TASK` shows the selected task. Only exact root `t help` displays generic usage and native scoped help without task lookup. Other first words are task references, including `new`, `show`, `edit`, `pry`, and `he`. There are no root `add`, `rm`, `list`, `ls`, `new`, or `show` actions.

Named references prefer an exact task name, then a unique case-sensitive prefix. Ambiguous prefixes fail. Unknown names fail except for `t NAME new` and `t NAME todo add TEXT...`. Explicit `new` creates exactly `NAME`, without resolving it as a prefix of another task. Help never creates a task.

```bash
t fix-checkout new
t fix-checkout
t fix-checkout next 'Inspect the failing request'
t fix-checkout directory add ~/proj/store --primary
t fix-checkout doc new investigation 'Checkout findings'
t fix-checkout pane run PANE_ID -- git status --short
```

### Current and orphan references

Use `.` for the current task, including commands with payload arguments:

```bash
t . current
t . next 'Inspect the request'
t . todo add Compare retry settings
```

Current-task selection uses the first matching priority:

1. A task whose normalized workspace label matches the calling Herdr workspace.
2. A task whose home, primary code directory, fallback worktree, or registered directory contains the current working directory. Paths resolve through symlinks.
3. The saved task.

Workspace context overrides a conflicting current directory. Multiple matches at the same priority are errors. In Herdr, selection uses `HERDR_WORKSPACE_ID`, the workspace of `HERDR_PANE_ID`, or the current workspace when only `HERDR_ENV=1` is available. Invalid, stale, or conflicting Herdr IDs are errors, not reasons to fall back. Herdr context requires a running server. Outside Herdr, an unrelated focused workspace does not affect selection. A named reference bypasses context lookup.

`t TASK current` prints the resolved name and saves a named selection's ID without focusing a terminal. `t . current` only prints the name. A successful named `t TASK workspace` or `t TASK switch` also saves the selection. Reads, `--show` inspection, and opens through `.` do not replace the saved fallback. A stale saved ID or unresolved `.` is an error.

`-` selects orphan todos only: `t - todo`, `t - todo add TEXT...`, or `t - todo rm ID`. It is invalid outside the todo scope and never creates a task.

### Options and literal arguments

For ordinary task commands, place options after the leaf command. Use `--` to stop option parsing:

```bash
t . next -- --flag-is-literal-text
t fix-checkout pane run PANE_ID -- git status --short
```

The current parser silently ignores unknown long options. Unknown short options may remain positional or be partially interpreted if a character matches a known short option. Do not rely on misspelled options producing an error. Leaf help lists accepted flags.

Todo `add` and AI commands have different argument handling. Every argument after `todo add` is literal text, except that leading `add -h` or `add --help` displays help. Flags later in the text, including `--help`, `--clear`, and `--`, remain literal:

```bash
t fix-checkout todo add Check --help and --clear handling
```

AI arguments pass unchanged to the native CLI, apart from a first-argument resume selector described below. `--help` and `--` are tool arguments, not `t` options.

## Task data and storage

A task can represent coding work, an investigation, or administrative work. It does not require a Git repository.

| Data | Location or meaning |
|---|---|
| Task records | `tasks` table in `~/.config/hiiro/hiiro.db` |
| Resource references | `task_resources` table in the same database |
| Task and orphan todos | Existing `todos` table, shared with `h todo` |
| Task home | `~/notes/work/NAME` for names created by `t NAME new` or an unmatched named `todo add` |
| Documents and other home files | Files on disk beneath the task home |
| `primary_directory` | Explicit default code directory for terminal creation |
| `tree` | Existing `h task` worktree association; `t NAME new` leaves it unset |
| `session` | Existing workspace label source; task creation sets it to the task name |
| Herdr tab and pane IDs | Looked up live, not saved as durable task identity by `t` |
| Saved task | `PinRecord` with `command='t'`, `key='current_task'`, and a JSON integer task ID in `value_json` |

The task home is computed, and resources are separate database rows. `t` and `h task` share task records. `h task` also maintains a YAML backup through its configuration code. `t` writes directly to the database and does not refresh that backup or `todo.yml`.

New names must be 1–120 ASCII letters, digits, dots, underscores, or hyphens, starting with a letter or digit. `t NAME new` does not accept slash-separated subtask names. Existing records with other characters remain selectable by exact name; their computed home directory percent-encodes those characters.

## Option catalog

Options are scoped to commands, not universally available. `TASK` may be a name, prefix, or `.` unless stated otherwise.

| Long option | Short | Value and default | Used by | Effect |
|---|---|---|---|---|
| `--help` | `-h` | Boolean | Ordinary leaf actions; leading todo `add` argument only | Prints selected options without running the action; AI commands instead forward it to the tool |
| `--clear` | `-c` | Boolean, false | `t TASK next`, `t TASK waiting` | Clears the corresponding text; cannot be combined with text |
| `--primary` | `-p` | Boolean, false | `t TASK directory add` | Makes this directory the default code directory |
| `--label` | None | String, unset | Directory, link, PR, and file `add` | Sets a resource label for display and exact selection |
| `--kind` | None | `general`, `issue`, or `thread`; add defaults to `general` | `t TASK link add`, `list`, `ls`, `open` | Chooses the stored link kind or filters links |
| `--directory` | None | Existing directory; otherwise precedence below | `t TASK workspace`, `switch`, `tab new`, `pane split` | Overrides the new terminal's start directory for this operation |
| `--command` | None | Shell command string, unset | `t TASK tab new`, `t TASK pane split` | Sends a command to the new terminal |
| `--direction` | None | `right` or `down`; default `right` | `t TASK pane split` | Chooses split direction |
| `--show` | `-s` | Boolean, false | `t TASK workspace`, `t TASK switch` | Inspects without creating, focusing, or saving |

`--command` has no `-c` alias, and neither `--directory` nor `--direction` has a `-d` alias. Boolean flags do not take `true` or `false` values. Bare `t` includes all statuses without an `--all` option.

## Task record commands

| Command | Behavior |
|---|---|
| `t` | Lists all tasks alphabetically, regardless of status or context |
| `t TASK` or `t TASK show` | Shows status, home, next action, todos, waiting text, code directory, workspace label, resources, and home Markdown documents |
| `t TASK current` | Prints the resolved name; named references also save the fallback without changing focus |
| `t NAME new` | Creates an active task and notes home; an exact existing name preserves its record and ensures the home exists |
| `t TASK next [TEXT...]` | Stores text, prints it with no text, or removes it with `--clear` |
| `t TASK waiting [TEXT...]` | Stores blocking text and sets waiting status; prints with no text; clears with `--clear` |
| `t TASK status [STATE]` | Prints status or sets `active`, `waiting`, `done`, or `archived` |
| `t TASK done` | Sets status to done |
| `t TASK archive` | Sets status to archived |

List rows contain tab-separated name, status, next action, and waiting text. Unset fields are omitted rather than emitted as empty columns, so this is not a fixed-width TSV export schema. There is no JSON output option.

### State transitions

| Operation | Status effect | Other data changes |
|---|---|---|
| `t NAME new` for a new name | `active` | Initializes timestamps; no worktree association |
| `t TASK next TEXT...` or `t TASK next --clear` | Unchanged | Updates or clears next-action text |
| `t TASK waiting TEXT...` | `waiting` | Stores waiting text and clears completion/archive timestamps |
| `t TASK waiting --clear` | `waiting` becomes `active`; other statuses unchanged | Clears waiting text |
| `t TASK status active` | `active` | Clears completion/archive timestamps; preserves next-action and waiting text |
| `t TASK status waiting` | `waiting` | Clears completion/archive timestamps; does not create waiting text |
| `t TASK done` or `t TASK status done` | `done` | Sets completion time if missing and clears archive time |
| `t TASK archive` or `t TASK status archived` | `archived` | Sets archive time if missing; preserves completion time |

Mutations update `updated_at`. Legacy records with no stored status are treated as active. Reading a field does not update task metadata.

Completion and archival do not delete todos or files, remove resources, stop commands, close terminals, detach worktrees, or alter Git state. Next-action and waiting text remain unless explicitly cleared. Completed and archived records remain in bare `t` output.

## Task todos and tt

A task can have multiple todos and one independent `next_action`. Adding or removing a todo does not change the next action, task status, or saved selection. There is no todo-completion command or automatic promotion to `next_action`.

| Command | Behavior |
|---|---|
| `t TASK todo` | Lists todos in the selected scope |
| `t TASK todo list` or `t TASK todo ls` | Same as the default todo action |
| `t TASK todo add TEXT...` | Adds one `not_started` todo; creates an unknown named task if needed |
| `t TASK todo rm ID` | Deletes that exact decimal database ID from the selected scope |
| `tt TASK ...` | Delegates to `t TASK todo ...` |
| `tt` | Delegates to `t . todo` |
| `tt help` | Shows todo help without task lookup |
| `t - todo` or `tt -` | Lists orphan todos; the same `add` and `rm` commands apply |

```bash
t fix-checkout todo add Reproduce the payment failure
t fix-check todo add Inspect --help output
t fix-checkout todo
tt fix-checkout rm 42
tt - add Buy printer paper
```

The prefix example assumes `fix-checkout` is the only match. `42` must be an ID printed by task display or todo listing, not a list position.

`add` joins its text arguments with spaces. Missing, empty, or whitespace-only text fails before task creation. An unmatched named task follows the same validation and home rules as `t NAME new`. Task and todo database writes use one immediate SQLite transaction, so failed insertion does not leave a new task record.

New task todos store the resolved task's full name in `task_name`, with `subtask_name` unset. Orphan todos leave both unset. Association uses `TodoItem.full_task_name` exactly, including legacy rows that combine `task_name` and `subtask_name`. A parent task does not include its subtasks' todos.

`rm` requires exactly one decimal ID. Missing, invalid, or extra arguments fail. IDs are not suffix matches. An ID belonging to another task or the orphan scope cannot be removed through the wrong scope. Listing prints IDs, statuses, and text in ID order. `show` prints items as `Todo ID [STATUS]: TEXT`.

These commands share the existing `todos` table with `h todo`. They insert or delete only the requested row and do not refresh `todo.yml`. Completion and archival preserve every todo. The separate `h task` and `h todo` commands are unchanged.

## Directory references

| Command | Alias | Options | Behavior |
|---|---|---|---|
| `t TASK directory add PATH` | None | `--label LABEL`, `--primary`, `-p` | Registers an existing directory; optionally makes it the default code directory |
| `t TASK directory list` | `t TASK directory ls` | None | Lists directory references |
| `t TASK directory open [REFERENCE]` | None | None | Opens the selected directory in the OS default application |

Attaching a directory does not create, move, or copy it, create a worktree, or change sparse checkout. Its canonical absolute path is stored. `directory open` does not change the invoking shell's directory or open a terminal. Replacing the primary directory preserves previous references. No command removes a directory reference or clears `primary_directory`.

## Links and pull requests

| Command | Alias | Options | Behavior |
|---|---|---|---|
| `t TASK link add URL` | None | `--label LABEL`, `--kind KIND` | Stores a general, issue, or thread link; defaults to general |
| `t TASK link list` | `t TASK link ls` | `--kind KIND` | Lists general, issue, thread, and PR resources when unfiltered |
| `t TASK link open [REFERENCE]` | None | `--kind KIND` | Opens the uniquely selected link |
| `t TASK pr add URL` | None | `--label LABEL` | Stores a PR resource |
| `t TASK pr list` | `t TASK pr ls` | None | Lists PR resources |
| `t TASK pr open [REFERENCE]` | None | None | Opens the uniquely selected PR URL |

URLs must be absolute HTTP or HTTPS URLs with a host. PR registration does not validate a provider-specific URL, contact GitHub, inspect review status, or create a pull request. `--kind pr` is not accepted by link commands. Use `t TASK pr list` or `t TASK pr open` for a PR-only view. Unfiltered link listing and opening include PRs.

## File references

| Command | Alias | Options | Behavior |
|---|---|---|---|
| `t TASK file add PATH` | None | `--label LABEL` | Registers an existing file by canonical absolute path |
| `t TASK file list` | `t TASK file ls` | None | Lists registered files and recursively discovers task-home files |
| `t TASK file open [REFERENCE]` | None | None | Opens a registered or discovered file in the OS default application |

Adding a file does not copy or move it. Home discovery includes hidden files and Markdown documents. Files discovered only through the home do not acquire database resource IDs; their list output begins with `home`.

### Resource identity and opening

- A stored resource is unique by task ID, kind, and target. Adding it again reuses the row. Supplying a label updates that row's label.
- Printed IDs are database IDs, not list positions.
- A registered `REFERENCE` can be its exact ID, stored target, or label. Relative attachment paths are not automatically equivalent to canonical stored paths when selecting a resource to open.
- Home files also accept full paths, paths relative to the home, or an unambiguous basename.
- Omitting `REFERENCE` succeeds only for one distinct target. Duplicate labels or basenames require a more specific selector.
- Files and directories must still exist when opened. Completion and archival preserve references.

Opening uses `open` on macOS or `xdg-open` elsewhere. There are no resource remove, unlink, or dedicated rename commands. Repeat `add` with `--label` to change a label.

## Documents

| Command | Alias | Behavior |
|---|---|---|
| `t TASK doc new NAME [TITLE...]` | None | Creates a Markdown file in the task home with a heading |
| `t TASK doc list` | `t TASK doc ls` | Lists Markdown files recursively under the home |
| `t TASK doc open [NAME]` | None | Resolves a document and invokes `mdoc` to render/open it |

Document names follow task-name character rules. One trailing `.md` is accepted and removed before constructing the filename. The title defaults to the name with underscores and hyphens replaced by spaces.

For task ID 42, `t fix-checkout doc new investigation 'Checkout findings'` creates `~/notes/work/fix-checkout/task-42-investigation.md` with the heading `# Checkout findings`. Creation refuses to overwrite a file and does not open it automatically. The task-ID prefix reduces basename collisions in `mdoc` output.

`doc open` accepts an exact absolute path, relative path, filename with or without `.md`, or short name without the task-ID prefix. An omitted name requires exactly one document. Existing home Markdown files are included without registration. An external Markdown file registered with `file add` does not become a `doc list` entry.

`t TASK file open` uses the OS default application. `t TASK doc open` requires `mdoc` and its configuration; rendering may create HTML and update the `mdoc` index.

## Herdr workspaces

A running Herdr server is required for workspace, tab, pane, and AI actions. `t` does not launch the server. Named non-Herdr data commands work independently of Herdr.

| Command | Options | Behavior |
|---|---|---|
| `t TASK workspace` or `t TASK switch` | `--directory PATH` | Focuses the task workspace or creates and focuses it; saves a named selection only after success |
| `t TASK workspace --show` or `t TASK switch --show` | None | Prints the workspace, tabs, and panes with directories without creating, focusing, or saving |

`workspace` and `switch` are direct commands, not groups. Native abbreviation matching accepts `t TASK wor`. Workspace identity is an exact label match:

```js
workspaceLabel = (task.session ?? task.name).replaceAll(".", "_")
```

Tasks named `release.1` and `release_1` can collide. Workspace actions reject labels shared by multiple task records or multiple live workspaces. They do not select a fuzzy workspace match.

Opening an existing workspace only focuses it. `--directory` does not change an existing terminal's directory. Inspection and tab/pane actions require the workspace to be open already. AI commands can create a missing workspace.

### Starting-directory precedence

New workspaces, tabs, and split panes choose the first applicable directory:

1. The operation's `--directory PATH`, where supported.
2. The task's `primary_directory`.
3. Its existing `tree`, absolute as-is or relative to `~/work`.
4. The task home, creating the home if necessary.

The chosen directory must exist. An invalid higher-priority path is an error, not a reason to try a lower-priority fallback. `--directory` is temporary and does not update task data. AI arguments do not supply wrapper directory options; they pass to the native tool.

## Herdr tabs and panes

| Command | Alias | Options | Behavior |
|---|---|---|---|
| `t TASK tab list` | `t TASK tab ls` | None | Lists live tabs in the task workspace |
| `t TASK tab new [LABEL]` | None | `--directory PATH`, `--command COMMAND` | Creates and focuses a tab; prints its ID |
| `t TASK tab open REFERENCE` | None | None | Focuses the workspace and matching tab |
| `t TASK pane list` | `t TASK pane ls` | None | Lists live panes in the task workspace |
| `t TASK pane open REFERENCE` | None | None | Focuses the matching pane |
| `t TASK pane read REFERENCE` | None | None | Prints recent unwrapped terminal text |
| `t TASK pane run REFERENCE -- COMMAND...` | None | None | Shell-escapes arguments and submits them to the existing pane |
| `t TASK pane split REFERENCE` | None | `--direction right\|down`, `--directory PATH`, `--command COMMAND` | Splits the pane and focuses the new pane |

References are exact live IDs or labels within the task workspace, not sidebar positions or prefixes. Duplicate labels require IDs. Do not store these IDs as permanent task identity. Every `tab new` creates another tab, even if the label exists. `pane read` does not expose Herdr's `--lines`, `--source`, or ANSI-format options.

For `--command`, pass a shell command as one quoted string. For `pane run`, pass an executable and arguments; explicitly invoke a shell for shell operators:

```bash
t fix-checkout tab new tests --command 'bundle exec rake test'
t fix-checkout pane split PANE_ID --direction down --command 'git status --short'
t fix-checkout pane run PANE_ID -- git status --short
t fix-checkout pane run PANE_ID -- zsh -lc 'git status --short && printf "finished\n"'
```

These commands do not wait for the submitted job or return its exit status. Creating a terminal does not prove its optional command succeeded. Use `pane read` to inspect output. The foreground program determines how submitted input is interpreted.

Terminals stay open after commands finish and after task completion. There is no `--no-focus`, closing command, automatic cleanup, or process-stop command. `t` does not manage the `h-bg` workspace. Notification helpers run detached processes rather than creating `h-bg` tabs.

## Native AI sessions

| Command | Alias | Native executable |
|---|---|---|
| `t TASK omp [ARGS...]` | None | `omp` |
| `t TASK codex [ARGS...]` | `t TASK cdx` | `codex` |
| `t TASK claude [ARGS...]` | `t TASK cld` | `claude` |

Fresh sessions are the default. Each launch creates a focused tab named for the canonical tool in the task workspace, creating the workspace if needed. Arguments are shell-escaped for launch. Claude runs `claude`, never `omp`.

Only the first tool argument can select resume mode. A nonempty prefix of `resume`, such as `r`, `res`, or `resume`, consumes that token. OMP and Claude then receive `--resume`; Codex receives its `resume` subcommand. No other token is reinterpreted.

With no arguments after the resume selector, the launcher looks for genuinely running instances of that tool in the supplied task workspace, using Herdr's `pane.agent` metadata rather than labels:

- One match: focus that pane.
- Multiple matches: fail and report the IDs rather than choose one.
- No matches: create a tab and launch the native resume picker.

If any arguments remain after the selector, always create a new tab and pass them to the native resume command. An explicit session ID or options never cause an existing pane to be focused or their arguments to be discarded.

```bash
t fix-checkout omp
t fix-checkout codex 'Inspect the failing checkout test'
t fix-checkout cld r
t fix-checkout omp resume SESSION_ID
t fix-checkout codex resume SESSION_ID --help
t fix-checkout claude --help
```

All other arguments, including `--help`, `--`, and native tool flags, pass unchanged. There is no wrapper `--new` or automatic last-session resume. `t` does not inject a model, permission flags, or continue flags. Native tools handle authentication, session IDs, and resume discovery; the launcher makes no auth or API requests.

Live-pane lookup is workspace-scoped. Persisted sessions follow the native CLI's discovery rules and are not necessarily task-isolated when tasks share a directory. A chosen directory can be an existing worktree. The launcher does not create worktrees or change Git state, though the tool you launch can modify files or run commands.

## Help and command dispatch

| Invocation | Behavior |
|---|---|
| `t` | Lists all tasks and statuses |
| Exact root `t help` | Prints generic usage and native scoped help without task lookup |
| `t TASK` | Shows the selected task |
| `t TASK help` | Prints the task command table |
| `t TASK GROUP help` | Prints that group's command table |
| `t TASK COMMAND --help` | Prints ordinary leaf options without running the action |
| `t TASK GROUP COMMAND --help` | Prints nested leaf options, subject to the todo `add` rule |
| `tt help` | Prints todo help without task lookup |
| `t TASK omp --help`, `codex --help`, or `claude --help` | Launches the native tool with its own help argument |

Root `edit` and `pry` registrations are not exposed; those words remain task names. Native Hiiro command abbreviations apply inside task and todo scopes, not to root help. Each documented group `list` command has an `ls` alias. Use full names in scripts. Task-prefix selection is separate from command abbreviation matching.

The launcher uses `run_child` to dispatch nested command scopes. This is the convenience form of `make_child(...).run`. `make_child` returns an unrun child; module-level `build_hiiro` methods are builders that return a child for their caller to run. An inline group does not need a separate builder. Child scopes inherit the bound `task_scope` resolver, so nested commands do not parse the task name again.

`t` disables external-command discovery. Legacy `t-*` executables are not part of this command set, and `t` does not delegate to `h task`. Command errors produce a nonzero exit; successful terminal delivery does not report the remote job's exit status.

Native Hiiro command-table help currently exits with status 1; ordinary leaf `--help` exits with status 0. This also applies to `t help` and `tt help`.

## Worktrees, branches, and sparse checkout

Built-in task operations do not create, remove, move, or switch Git worktrees or branches. They do not enable, disable, or update sparse checkout.

| Operation | Git/worktree effect |
|---|---|
| `t NAME new` | None; creates a record and notes home |
| `t TASK todo add` or `rm` | None; unmatched named add also creates a task and home |
| `t TASK directory add PATH --primary` | Stores an existing path; does not populate `tree` |
| `t TASK workspace`, `switch`, `tab new`, `pane split` | Starts terminals in an existing directory; does not check out code |
| `t TASK done` or `archive` | No checkout, worktree, file, or terminal changes |
| `t TASK pr add URL` | Saves a URL; no GitHub or Git operation |
| `t TASK pane run`, `--command`, or AI tools | The explicitly launched command or tool can change Git, files, or external systems |

An existing sparse worktree retains its configuration. New terminals see the files already checked out there.

### Separate h task commands

`h task` is registered by the Hiiro launcher and implemented in `lib/hiiro/tasks.rb`. It shares records with `t` but has a different command set and resolver.

| Command | Existing behavior |
|---|---|
| `h task start TASK [APP] --sparse GROUP` | For a new coding task, reuses/moves an available worktree or creates a detached worktree, then applies sparse groups and opens/focuses Herdr |
| `h task switch TASK [APP]` | Switches to an existing task workspace or creates it using the legacy task path |
| `h task from PATH [TASK]` | Registers an existing worktree and switches to its task |
| `h task sparse --list` or `-l` | Lists configured sparse groups |
| `h task sparse` | Shows sparse-checkout paths for the current task's worktree |
| `h task sparse GROUP...` | Applies configured groups to the current task's worktree |
| `h task sparse --disable` or `-d` | Disables sparse checkout for the current task's worktree |
| `h task stop [TASK]` | Detaches the task and subtasks from worktree associations; preserves records and retains old paths as directory references |
| `h task resume [TREE]` | Associates an available worktree with a task and switches to it |
| `h task prune` | Reports missing associations; default is dry-run |
| `h task prune --force` or `-f` | Detaches missing associations without deleting task records |

Sparse groups come from `~/.config/hiiro/sparse_groups.yml`. `start` accepts repeated `--sparse GROUP` or `-s GROUP`. The separate `sparse` command acts on the current legacy task and does not use `t` selection.

- `h task start` uses the repository at `~/work/.git` and normally places a new top-level worktree at `~/work/TASK/main`. It can move an available worktree instead.
- Starting an existing task with a resolved worktree and no sparse groups calls `disable_sparse_checkout`. Use `h task switch` to return without that `start` behavior.
- Starting an existing task without a worktree switches to its home without automatically attaching a worktree.
- `t TASK directory add PATH --primary` affects `t` terminal directories. The legacy resolver uses `tree` or home, not `primary_directory` as an equivalent worktree association.
- `h task stop` is not `t TASK done`. Stopping detaches worktree associations; completing changes status. Neither closes all task terminals.
- A retained directory reference does not reserve a detached worktree path against later legacy reuse.

## Side-effect summary

| Category | Task database | Filesystem | Herdr or external application |
|---|---|---|---|
| Bare task list, show, metadata reads, `t . current` | Reads data; preserves saved fallback | May inspect home files | `.` selection may query Herdr |
| Named `t TASK current` | Saves resolved task ID | No task file changes | No focus change |
| New task | Creates record if absent | Ensures notes home | No workspace creation |
| Todo add/remove | Inserts/deletes scoped row; unmatched named add creates task; preserves saved selection | New task ensures home; no `todo.yml` rewrite | `.` selection may query Herdr |
| Metadata writes, done, archive | Updates metadata | No task file deletion | No terminal cleanup |
| Resource add | Stores reference; may update label or primary directory | Checks paths; no copy/move | No terminal creation |
| Resource open | Reads references | Checks existence | Launches OS opener |
| Document new | Reads task | Ensures home and creates Markdown file | No terminal creation |
| Document open | Reads task | `mdoc` may write output/index | Runs `mdoc` |
| Workspace/tab/pane actions | Reads identity; successful named workspace/switch saves fallback | May ensure home | Queries, creates, focuses, reads, or sends commands; `--show` only queries |
| AI launch/resume | Reads task identity | Native tool controls its own files | Creates workspace if needed; creates tab or focuses unique running pane |

Hiiro also initializes its database and records CLI invocations. Reading task data does not guarantee that the entire database file remains unchanged.

## Source map

| Source | Responsibility |
|---|---|
| `bin/t` | Task-scoped commands, resources, documents, and Herdr actions; target of `~/bin/t` |
| `bin/tt` | Delegates to the task todo scope |
| `lib/hiiro/task_scope.rb` | Named/current/orphan reference resolution and cached task context |
| `lib/hiiro/task_sessions.rb` | Native AI launch/resume dispatch and running-pane focus |
| `lib/hiiro/task_record.rb` | Shared records, states, home naming, and resource identity |
| `lib/hiiro/todo.rb` | Shared `TodoItem` rows and full-task-name association |
| `lib/hiiro/herdr.rb` | Herdr adapter, terminal creation/focus/read behavior |
| `lib/hiiro/tasks.rb` | Separate `h task` worktree and sparse-checkout operations |
| `lib/hiiro/options.rb` | Option parsing, short aliases, and generated option help |
| `lib/hiiro.rb` | Command registration, child dispatch, resolvers, and generated command tables |
