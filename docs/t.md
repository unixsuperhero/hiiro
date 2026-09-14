# t command reference

Reference for the repository's `bin/t` executable.

`t` manages task records, next actions, waiting-on information, documents, resource references, and task-associated Herdr terminals. **It does not create Git worktrees or configure sparse checkout.** Those operations belong to the separate `h task` commands.

`bin/t` is the canonical source for the command declarations and `TaskCommands` helpers. `~/bin/t` is a symlink to that executable. The launcher resolves its real path to load the repository's `lib/hiiro`, including when invoked through the symlink. Installing the Hiiro gem does not install this launcher.

## Task data and storage

A task can represent coding work, an investigation, or administrative work. It does not require a Git repository.

Illustrative data, using simplified JavaScript notation:

```js
{
  id: 42,
  name: "fix-checkout",
  status: "waiting",
  next_action: "Reproduce the payment failure",
  waiting_on: "Payments review",
  primary_directory: "/Users/me/proj/store",
  tree: null,
  session: "fix-checkout",
  home: "/Users/me/notes/work/fix-checkout",
  resources: [
    { id: 17, kind: "directory", label: "code", target: "/Users/me/proj/store" },
    { id: 18, kind: "issue", label: "ticket", target: "https://example.com/issues/123" },
    { id: 19, kind: "pr", label: "implementation", target: "https://example.com/pulls/456" }
  ]
}
```

`home` is computed, and `resources` are separate database rows. The example is not an export format.

| Data | Location or meaning |
|---|---|
| Task records | `tasks` table in `~/.config/hiiro/hiiro.db` |
| Resource references | `task_resources` table in the same database |
| Task home | `~/notes/work/TASK` for names created by `t new` |
| Documents and other home files | Files on disk beneath the task home |
| `primary_directory` | Explicit default code directory for `t` terminal creation |
| `tree` | Existing `h task` worktree association; `t new` leaves it unset |
| `session` | Existing workspace label source; `t new` sets it to the task name |
| Herdr tab and pane IDs | Looked up live; not saved as durable task identity by `t` |
| Saved task | `PinRecord` with `command='t'`, `key='current_task'`, and a JSON integer task ID in `value_json` |

`t` and `h task` share task records. `h task` also maintains a YAML backup through its configuration code; `t` writes the database directly and does not refresh that backup itself.

New names must be 1–120 ASCII letters, digits, dots, underscores, or hyphens, starting with a letter or digit. `t new` does not accept slash-separated subtask names. Existing records with other characters can still be selected by their exact name; their computed home directory percent-encodes those characters.

## Syntax and task selection

```text
t COMMAND [TASK] [PAYLOAD...] [OPTIONS]
t GROUP COMMAND [TASK] [PAYLOAD...] [OPTIONS]
```

In this reference, uppercase words are values to supply. Square brackets indicate optional arguments, and `...` means multiple words or arguments.

### Selecting a task

The task is the first positional argument after the leaf command, before any payload. Names match exactly, not by prefix or fuzzy search. An unknown explicit name is an error.

```bash
t show fix-checkout
t next fix-checkout 'Inspect the failing request'
t directory add fix-checkout ~/proj/store --primary
t doc new fix-checkout investigation 'Checkout findings'
t pane run fix-checkout PANE_ID -- git status --short
```

Task selection has no flag. A task name cannot appear before the root command or between a group and its child command.

Omit `TASK` only when there are no payload positionals. `t next` reads the selected task's next action, and `t next --clear` clears it. To set text, supply the task first: `t next fix-checkout 'Inspect the request'`. A lone positional argument is always a task name, never guessed to be text, a resource selector, or another payload for the current task.

Selection uses the first matching priority:

1. The explicit exact task name.
2. A task whose normalized workspace label matches the calling Herdr workspace.
3. A task whose home, primary code directory, fallback worktree, or registered directory contains the current working directory. Paths are resolved through symlinks.
4. The saved task.

Workspace context overrides a conflicting current directory. Multiple task matches at the same priority are errors. In Herdr, selection uses `HERDR_WORKSPACE_ID`, the workspace of `HERDR_PANE_ID`, or the current workspace when only `HERDR_ENV=1` is available. Invalid, stale, or conflicting Herdr IDs are errors rather than reasons to fall back to a different task. Outside Herdr, an unrelated focused workspace does not affect selection. An explicit task name bypasses implicit context lookup.

`t current TASK` prints the exact task name and saves its ID without focusing a terminal. `t current` only prints the selected name. `t workspace TASK` saves the task only after a successful explicit workspace switch. Reads, `t workspace --show TASK`, and implicit workspace opens do not replace the saved fallback.

If selection reaches a saved ID that no longer names a task, the command fails. If neither context nor a saved task matches, supply an explicit task name.

`t list` without a task lists all eligible tasks rather than selecting from context or the saved fallback. `t list TASK` restricts the list to that exact task. `t new TASK` creates the named task and does not use current-task detection.

### Option placement and literal arguments

Place options after the leaf command. Options do not change the order of positional arguments.

Use `--` to stop option parsing. This matters when passing another command's flags:

```bash
t next fix-checkout -- --flag-is-literal-text
t pane run fix-checkout PANE_ID -- git status --short
```

The current parser silently ignores unknown long options. Unknown short options may remain positional or be partially interpreted if a character matches a known short option. Do not rely on misspelled options producing an error; leaf help is the authority for accepted flags.

## Complete option catalog

Options are scoped to commands, not universally available.

| Long option | Short | Value and default | Used by | Effect |
|---|---|---|---|---|
| `--help` | `-h` | Boolean | Leaf action commands | Prints selected command options without running its action |
| `--all` | `-a` | Boolean, false | `t list`, `t ls` | Includes `done` and `archived` records |
| `--clear` | `-c` | Boolean, false | `t next`, `t waiting` | Clears the corresponding text; cannot be combined with text |
| `--primary` | `-p` | Boolean, false | `t directory add` | Makes this directory the task's default code directory |
| `--label` | None | String, unset | `t directory add`, `t link add`, `t pr add`, `t file add` | Sets a resource label used for display and exact selection |
| `--kind` | None | `general`, `issue`, or `thread`; add defaults to `general` | `t link add`, `t link list`, `t link ls`, `t link open` | Chooses the stored link kind or filters existing links |
| `--directory` | None | Existing directory; otherwise start-directory precedence below | `t workspace`, `t tab new`, `t pane split` | Sets the new terminal's starting directory for this operation only |
| `--command` | None | Shell command string, unset | `t tab new`, `t pane split` | Sends a command to the newly created terminal |
| `--direction` | None | `right` or `down`; default `right` | `t pane split` | Chooses the split direction |
| `--show` | `-s` | Boolean, false | `t workspace` only | Inspects the task workspace without creating, focusing, or saving it |

In particular, `--command` has no `-c` alias, and neither `--directory` nor `--direction` has a `-d` alias. The automatic boolean flags do not take `true` or `false` values.

## Task record commands

All commands support leaf `-h` and `--help`. In every signature below, `TASK` can be omitted only when no payload positional follows.

| Command | Alias | Additional options | Behavior |
|---|---|---|---|
| `t list [TASK]` | `t ls [TASK]` | `--all`, `-a` | Lists tasks alphabetically by name, or restricts the list to the exact task; normally includes only active and waiting tasks |
| `t show [TASK]` | None | None | Shows status, home, next action, waiting text, code directory, workspace label, resources, and home Markdown documents |
| `t current [TASK]` | None | None | Prints the resolved task name; an explicit name also saves the task as the fallback without changing terminal focus |
| `t new TASK` | None | None | Creates an active task record and its notes home; an existing name preserves its record and ensures the home exists |
| `t next [TASK] [TEXT...]` | None | `--clear`, `-c` | With text, stores the next action; with no text, prints it; with `--clear`, removes it |
| `t waiting [TASK] [TEXT...]` | None | `--clear`, `-c` | With text, records what is blocking the task and sets status to waiting; with no text, prints the current text |
| `t status [TASK] [STATE]` | None | None | Prints status or sets it to `active`, `waiting`, `done`, or `archived` |
| `t done [TASK]` | None | None | Sets status to done |
| `t archive [TASK]` | None | None | Sets status to archived |

List rows contain tab-separated name, status, next action, and waiting text. Unset fields are omitted rather than emitted as empty columns, so this is not a fixed-width TSV export schema. The CLI has no JSON output option.

### State transitions

| Operation | Status effect | Other data changes |
|---|---|---|
| `t new TASK` for a new name | `active` | Initializes creation/update timestamps; no worktree association |
| `t next TASK TEXT...` or `t next [TASK] --clear` | Unchanged | Updates or clears next-action text |
| `t waiting TASK TEXT...` | `waiting` | Stores waiting text and clears completion/archive timestamps |
| `t waiting [TASK] --clear` | `waiting` becomes `active`; other statuses remain unchanged | Clears waiting text |
| `t status TASK active` | `active` | Clears completion/archive timestamps; preserves next-action and waiting text |
| `t status TASK waiting` | `waiting` | Clears completion/archive timestamps; does not create waiting text |
| `t done [TASK]` or `t status TASK done` | `done` | Sets completion time if missing and clears archive time |
| `t archive [TASK]` or `t status TASK archived` | `archived` | Sets archive time if missing; preserves any completion time |

Mutations above update `updated_at`. Legacy records with no stored status are treated as active. Reading a field does not update its task metadata.

Completion and archival are metadata changes only. They do not delete files, remove resources, stop commands, close Herdr terminals, detach worktrees, or alter Git state. Next-action and waiting text remain unless explicitly cleared.

## Directory references

| Command | Alias | Additional options | Behavior |
|---|---|---|---|
| `t directory add TASK PATH` | None | `--label LABEL`, `--primary`, `-p` | Registers an existing directory; optionally makes it the default code directory |
| `t directory list [TASK]` | `t directory ls [TASK]` | None | Lists registered directory references |
| `t directory open [TASK] [REFERENCE]` | None | None | Opens the selected directory in the OS default application; Finder on macOS |

These commands support leaf help. Attaching a directory does not create it, move it, copy it, create a worktree, or change sparse checkout. Its canonical absolute path is stored. `directory open` does not change the invoking shell's working directory or open a Herdr terminal.

Replacing the primary directory preserves previous directory references. There is currently no command to remove a directory reference or clear `primary_directory`.

## Links and pull requests

| Command | Alias | Additional options | Behavior |
|---|---|---|---|
| `t link add TASK URL` | None | `--label LABEL`, `--kind KIND` | Stores a `general`, `issue`, or `thread` link; defaults to general |
| `t link list [TASK]` | `t link ls [TASK]` | `--kind KIND` | Lists general, issue, thread, and PR resources when unfiltered |
| `t link open [TASK] [REFERENCE]` | None | `--kind KIND` | Opens the uniquely selected link in the OS default application |
| `t pr add TASK URL` | None | `--label LABEL` | Stores a resource with kind `pr` |
| `t pr list [TASK]` | `t pr ls [TASK]` | None | Lists only PR resources |
| `t pr open [TASK] [REFERENCE]` | None | None | Opens the uniquely selected PR URL |

These commands support leaf help. URLs must be absolute HTTP or HTTPS URLs with a host. PR registration does not validate a provider-specific PR URL, contact GitHub, inspect review status, or create a pull request. It is a saved URL reference.

`--kind pr` is not accepted by the link commands. Use `t pr list` or `t pr open` for a PR-only view. Unfiltered `t link list` and `t link open` include PRs.

## File references

| Command | Alias | Additional options | Behavior |
|---|---|---|---|
| `t file add TASK PATH` | None | `--label LABEL` | Registers an existing file by canonical absolute path |
| `t file list [TASK]` | `t file ls [TASK]` | None | Lists registered files and recursively discovers files in the task home |
| `t file open [TASK] [REFERENCE]` | None | None | Opens a registered or discovered home file in the OS default application |

These commands support leaf help. Adding a file does not copy or move it. Home-file discovery includes hidden files and Markdown documents. Files discovered only through the home directory do not acquire database resource IDs; their list output begins with `home`.

### Resource identity and opening

The directory, link, PR, and file groups use these rules:

- A stored resource is unique by task ID, kind, and target. Adding the same resource again reuses it. Supplying a label updates that existing row's label.
- Printed resource IDs are database IDs, not positions in the displayed list.
- A registered resource's `REFERENCE` can be its exact ID, stored target, or label. Because file/directory targets are stored canonically, a relative attachment path is not automatically an equivalent open selector.
- Home files additionally accept their full path, path relative to the task home, or an unambiguous basename.
- Omitting `REFERENCE` succeeds only when exactly one distinct target matches. Duplicate labels or basenames require a more specific selector.
- Files and directories must still exist when opened. Completion and archival do not remove their references.

Resource opening uses `open` on macOS or `xdg-open` elsewhere. There are no resource remove, unlink, or dedicated rename commands. Labels can be changed by repeating `add` with `--label`.

## Documents

| Command | Alias | Additional options | Behavior |
|---|---|---|---|
| `t doc new TASK NAME [TITLE...]` | None | None | Creates a new Markdown file in the task home, containing a heading |
| `t doc list [TASK]` | `t doc ls [TASK]` | None | Lists Markdown files recursively under the task home |
| `t doc open [TASK] [NAME]` | None | None | Resolves a document and invokes `mdoc` to render/open it |

These commands support leaf help. `NAME` follows the task-name character rules; one trailing `.md` is accepted and removed before constructing the filename. The title defaults to the name with underscores and hyphens replaced by spaces.

For task ID 42:

```bash
t doc new fix-checkout investigation 'Checkout findings'
```

creates:

```text
~/notes/work/fix-checkout/task-42-investigation.md
```

with:

```markdown
# Checkout findings
```

Creation refuses to overwrite an existing file. The task-ID prefix reduces basename collisions in `mdoc` output. `doc new` does not automatically open the document.

`doc open` accepts an exact absolute path, relative path, filename with or without `.md`, or the short name without the task-ID prefix. An omitted name requires exactly one document. Existing Markdown files under the task home are included without registration; registering an external Markdown file with `file add` does not make it a `doc list` entry.

`t file open` uses the OS default application, while `t doc open` uses `mdoc`. Rendering may create HTML and update the `mdoc` index according to its configuration.

## Herdr workspaces

A running Herdr server is required for workspace, tab, and pane actions. `t` does not launch the server. An explicit task name lets non-Herdr data commands work independently of Herdr.

| Command | Additional options | Behavior |
|---|---|---|
| `t workspace [TASK]` | `--directory PATH` | Focuses the existing task workspace, or creates and focuses one; saves an explicit task only after success |
| `t workspace --show [TASK]` | None | Prints the task workspace, its tabs, and its panes with their working directories; does not create, focus, or save |

`workspace` is a root leaf command, not a group. It supports leaf help, and native Hiiro abbreviation matching accepts `t wor [TASK]`. `--show` applies only to this command. Workspace identity is an exact label match:

```js
workspaceLabel = (task.session ?? task.name).replaceAll(".", "_")
```

Tasks named `release.1` and `release_1` can therefore collide. Workspace actions reject labels shared by multiple task records or multiple live workspaces. They do not silently select a prefix match.

`t workspace` is reusable: when the workspace already exists, it only focuses it. `--directory` then does not change an existing terminal's directory. An explicit successful switch also saves the task; an implicit open leaves the saved fallback unchanged. Inspection and the tab and pane actions require the task workspace to be open already.

### Starting-directory precedence

For a newly created workspace, tab, or split pane:

1. This command's `--directory PATH`, if supplied.
2. The task's `primary_directory`, if set.
3. Its existing `tree`: an absolute path as-is, or relative to `~/work`.
4. The task home, creating that home if necessary.

The chosen directory must exist. An invalid higher-priority path is an error, not a reason to try a lower-priority fallback. `--directory` is temporary and does not update stored task data.

## Herdr tabs

| Command | Alias | Additional options | Behavior |
|---|---|---|---|
| `t tab list [TASK]` | `t tab ls [TASK]` | None | Lists live tabs in the selected task workspace |
| `t tab new [TASK] [LABEL]` | None | `--directory PATH`, `--command COMMAND` | Creates and focuses a new tab, optionally sending a shell command; prints its ID |
| `t tab open TASK REFERENCE` | None | None | Focuses the task workspace and the matching tab |

These commands support leaf help. A reference is an exact live tab ID or label within the task workspace. Duplicate labels require an ID. There is no prefix matching.

Every `tab new` creates another tab, even if its label already exists. There is no reuse-by-label behavior and no `t tab close` command.

## Herdr panes

| Command | Alias | Additional options | Behavior |
|---|---|---|---|
| `t pane list [TASK]` | `t pane ls [TASK]` | None | Lists live panes in the selected task workspace |
| `t pane open TASK REFERENCE` | None | None | Focuses the exact matching pane |
| `t pane read TASK REFERENCE` | None | None | Prints the pane's recent unwrapped terminal text |
| `t pane run TASK REFERENCE -- COMMAND...` | None | None | Shell-escapes the command arguments and submits them to the existing pane |
| `t pane split TASK REFERENCE` | None | `--direction right\|down`, `--directory PATH`, `--command COMMAND` | Splits the target pane, focuses the new pane, and optionally sends a command |

These commands support leaf help. A reference is an exact live pane ID or label belonging to the selected task workspace. Use IDs from `pane list`; they are not sidebar positions and should not be guessed or stored as permanent task identity.

The split direction defaults to `right`; only `right` and `down` are supported. `pane read` does not expose the underlying Herdr `--lines`, `--source`, or ANSI-format options.

### Command execution and terminal lifetime

For `--command`, pass the shell command as one quoted string:

```bash
t tab new fix-checkout tests --command 'bundle exec rake test'
t pane split fix-checkout PANE_ID --direction down --command 'git status --short'
```

For `pane run`, pass an executable and its arguments. For shell operators, explicitly invoke a shell:

```bash
t pane run fix-checkout PANE_ID -- git status --short
t pane run fix-checkout PANE_ID -- zsh -lc 'git status --short && printf "finished\n"'
```

These are interactive-terminal commands, not a background job queue. They do not wait for the submitted job to finish or return its exit status. A successful tab/pane creation does not by itself prove that its optional command ran successfully. Use `pane read` to inspect output. The existing terminal's foreground program determines how submitted input is interpreted.

Created terminals remain open after commands finish. Task completion does not close them. There is no `--no-focus`, tab/pane closing command, automatic cleanup, or process-stop command in `t`.

This is separate from notification helpers: in Hiiro 0.1.365, desktop notifications and notification sounds run as detached processes rather than creating `h-bg` tabs. `t` does not manage the `h-bg` workspace.

## Help, aliases, and inherited commands

| Invocation | Behavior |
|---|---|
| `t` or `t help` | Prints Hiiro's native root command table, including argument declarations and source locations |
| `t GROUP` or `t GROUP help` | Prints the group's command table |
| `t COMMAND --help` | Prints that leaf's selected options without executing its action |
| `t GROUP COMMAND --help` | Prints that nested leaf's selected options without executing its action |
| `t edit` | Hiiro developer utility that opens the executable through its configured editor |
| `t pry` | Hiiro developer utility that opens an interactive Ruby debugger |

Every group listed in this reference includes `help`. Hiiro also injects `edit` and `pry` into the group tables; these are framework/developer commands, not task editing or task inspection operations. Prefer root `t edit` for the actual executable; child command names need not correspond to standalone files.

Each documented `list` command has an `ls` alias. Normal Hiiro abbreviation matching applies to command names, with ambiguous names producing help. For example, `t wor fix-checkout` resolves to `t workspace fix-checkout`. Use full names in scripts. Resource, task, tab, and pane selectors retain their exact-match rules.

Root/group help currently exits with status **1**, even when requested explicitly. Leaf `--help` exits with status **0**. Data and command errors generally produce a nonzero exit; command delivery is not the same as the remote terminal job's result.

`t` disables external-command discovery, so legacy executables named `t-*` are not part of this command set. It does not delegate to `h task`.

## Worktrees, branches, and sparse checkout

### What t does not change

Built-in task operations do not run Git to create, remove, move, or switch a worktree or branch. They do not enable, disable, or update sparse checkout.

| Operation | Git/worktree effect |
|---|---|
| `t new TASK` | None; creates a record and notes directory only |
| `t directory add TASK PATH --primary` | Stores an existing path; does not turn it into a worktree or populate `tree` |
| `t workspace`, `t tab new`, `t pane split` | Starts terminals in an existing chosen directory; does not check out code |
| `t done`, `t archive` | No checkout, worktree, file, or terminal changes |
| `t pr add TASK URL` | Saves a URL; no GitHub or Git operation |
| `t pane run` and `--command` | Whatever command you supply can change Git, files, or external systems; that is an explicit execution request |

If the chosen directory is already a sparse worktree, `t` leaves its sparse configuration intact. New terminals see the files already checked out there.

### Separate h task commands

`h task` is registered by the Hiiro launcher and implemented in `lib/hiiro/tasks.rb`. It shares task records with `t`, but has a different command set and resolver. This section identifies the important boundary; it is not a full `h task` reference.

| Command | Existing behavior |
|---|---|
| `h task start TASK [APP] --sparse GROUP` | For a new coding task, reuses/moves an available worktree or creates a detached worktree, then applies configured sparse groups and opens/focuses Herdr |
| `h task switch TASK [APP]` | Switches to an existing task workspace or creates it using the legacy task path |
| `h task from PATH [TASK]` | Registers an existing worktree and switches to its task |
| `h task sparse --list` or `-l` | Lists configured sparse groups |
| `h task sparse` | Shows sparse-checkout paths for the current task's worktree |
| `h task sparse GROUP...` | Applies configured groups to the current task's worktree |
| `h task sparse --disable` or `-d` | Disables sparse checkout for the current task's worktree |
| `h task stop [TASK]` | Detaches the task and its subtasks from their worktree associations, preserving task records and retaining old paths as directory references |
| `h task resume [TREE]` | Associates an available worktree with a task and switches to it |
| `h task prune` | Reports missing worktree associations; default is dry-run |
| `h task prune --force` or `-f` | Detaches missing worktree associations without deleting task records |

Sparse groups are read from `~/.config/hiiro/sparse_groups.yml`. The `start` command accepts repeated `--sparse GROUP` or `-s GROUP`. The separate `sparse` command acts on the current legacy task and does not use `t`'s positional task selection.

Important distinctions:

- `h task start` uses the repository at `~/work/.git` and normally places a new top-level worktree at `~/work/TASK/main`. It can move an available worktree instead of creating one.
- **Starting an existing task with a resolved worktree and no sparse groups calls `disable_sparse_checkout`.** Use `h task switch` when the intention is only to return to existing work without that `start` behavior.
- Starting a task that already exists but has no worktree does not automatically attach a new worktree. It switches to the task's home.
- Setting `primary_directory` with `t directory add TASK PATH --primary` affects `t`'s terminal start-directory selection. The legacy `h task` resolver uses its `tree` association or home, not that field as an equivalent worktree association.
- `h task stop` is not `t done`: stopping detaches worktree associations; completing changes status. Neither operation should be treated as a command to close all task terminals.
- A retained directory reference does not reserve a detached worktree path against later reuse by the legacy task manager.

No worktree or sparse-checkout operation was executed to prepare this reference. The comparison above was traced through the current implementation.

## Side-effect summary

| Category | Task database | Filesystem | Herdr or external application |
|---|---|---|---|
| List/show/current without an explicit task and metadata reads | Reads task data; does not replace the saved fallback | May inspect existing home files | Implicit selection may query Herdr |
| `t current TASK` | Saves the exact task's ID as the fallback | No task file changes | No focus change |
| New task | Creates record if absent | Ensures notes home exists | No Herdr workspace creation |
| Metadata writes, done, archive | Updates task metadata | No task file deletion | No terminal cleanup |
| Resource add | Stores reference; may update label or primary directory | Checks existing file/directory paths; no copy/move | No terminal creation |
| Resource open | Reads references | Checks file/directory existence | Launches OS default opener |
| Document new | Reads task record | Ensures home and creates one Markdown file | No terminal creation |
| Document open | Reads task record | `mdoc` may write render output/index | Runs `mdoc` and opens its output |
| Workspace/tab/pane actions | Reads task identity; only a successful explicit `t workspace TASK` switch saves the fallback | May ensure task home for a new terminal | Queries, creates, focuses, reads, or sends commands as documented; `--show` only queries |

Hiiro also initializes its database and records CLI invocations. “Reads task data” does not mean the entire SQLite file is guaranteed unchanged.

## Source map

The command declarations use native Hiiro help. Run `t` for the root command table, `t doc` for a group table, or `t directory add --help` for leaf options. These help commands do not execute task actions.

| Source | Responsibility |
|---|---|
| `bin/t` | Task selection, all task-specific commands, resource/document behavior, and Herdr actions; canonical target of the `~/bin/t` symlink |
| `lib/hiiro/task_record.rb` | Shared records, states, home naming, and resource identity |
| `lib/hiiro/herdr.rb` | Herdr command execution, terminal creation/focus/read behavior |
| `lib/hiiro/tasks.rb` | Separate `h task` worktree and sparse-checkout operations |
| `lib/hiiro/options.rb` | Option parsing, short aliases, and generated option help |
| `lib/hiiro.rb` | Command registration, inherited developer commands, and generated command tables |
