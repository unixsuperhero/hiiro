# Changelog

## Unreleased

### Added
- `h herdr` and `hh` pane controls for Vim-style focus, two-pane reflow, resize, swap, and zoom
- `prefix+shift+h/j/k/l` reflows a two-pane tab toward an edge; `prefix+alt+h/j/k/l` resizes the current pane

## [0.1.384] - 2026-09-23

### Added
- `h plist` command for working with property lists

### Fixed
- publish script now requires hiiro unconditionally at startup instead of only when falling back to local version

## [0.1.381] - 2026-09-20

### Added
- `Hiiro::Options` now includes file/directory filtering methods: `files`, `dirs`, `file_or_dirs`, `not_files`, and `not_file_or_dirs` for convenient argument classification

## [0.1.377] - 2026-09-17

### Changed
- `h save` redesigned with slug-based filenames (`<timestamp>-<slug>.txt` / `<timestamp>-image.png`), image handling via `pngpaste`, and environment-configurable destination via `HIIRO_SAVED_DIR`

### Added
- `h save` subcommands: `ls`/`list`, `dir`, `show`/`cat`, `copy`, `open`, `edit`, `rm`/`remove` for managing saved files
- `t path`, `t cd`, `t start`, and `t switch` accept optional `APP` argument to select a configured relative directory beneath the task root
- APP resolves by exact name or unique case-sensitive prefix; fails when ambiguous or missing
- `t switch` / `t workspace` and `t cd` accept an optional APP positional (or `--app`) resolving through the apps registry by exact name or unique prefix; the workspace or pane cd targets the app directory under the task worktree, e.g. `t switch aldi cpm` opens `~/work/aldi/main/retailer-tools/content-page-migrator`

## [0.1.376] - 2026-09-14

### Changed
- Herdr `hiiro.nvim` action opens bare `nvim` in the calling pane's working directory instead of the task notes home

## [0.1.375] - 2026-09-14

### Changed
- `t switch`, `t tab open`, and `t pane open` no longer default to the current task; with no destination they open the picker (tasks, workspaces, panes, or tabs) and fail non-interactively. `.` still means the current task

## [0.1.374] - 2026-09-14

### Changed
- `h alert` plays sounds through terminal-notifier's `-sound` (macOS system sound names, `none` for silent, `-S` accepted as an alias for `-s`) instead of a separate `afplay` process

### Removed
- Support for custom sound files in `~/.config/hiiro/sounds/`

## [0.1.372] - 2026-09-14

### Changed
- `h bg run` reuses an idle shell pane in the `h-bg` workspace and opens a new tab only when every pane is busy, instead of one tab per command

## [0.1.371] - 2026-09-14

### Added
- `t ls` lists the panes under every open workspace with directory, agent state, and foreground command via `herdr pane process-info`; `t switch` accepts an exact pane ID and its picker includes panes
- `Hiiro::Herdr#process_info` and `Pane#foreground_command`

## [0.1.370] - 2026-09-14

### Added
- `t ls` marks tasks with an open Herdr workspace with `@` and lists workspaces that belong to no task

## [0.1.369] - 2026-09-14

### Added
- `t switch NAME` matches live Herdr workspaces that belong to no task, and the fuzzy finder for `switch` lists tasks plus those workspaces, numbering duplicate workspace names
- `t` opens the fuzzy finder instead of failing when a task prefix is ambiguous or no current task can be resolved, when stdin is a terminal

## [0.1.368] - 2026-09-14

### Added
- `h herdr`: Herdr plugin exposing `t` through keybound popups for fuzzy task switching, todo capture, todo copying, task shell, and nvim access; `h herdr install` copies and links the plugin, `h herdr keys` prints keybindings

### Changed
- Task CLI grammar converted to command-first: `t COMMAND [TASK] [ARGS...]` matching the legacy `h task` rule where the first positional word is the task when it names one (exact or unique prefix), otherwise the current task is used and the word stays in the payload

### Removed
- `Hiiro::TaskScope` class; task resolution logic integrated into `Hiiro::TaskCli`

## [0.1.367] - 2026-09-14

### Added
- `t use TASK` (alias `pin`) saves the fallback task; `t current` now only prints
- `-t TASK` / `-f` task options on every `t` command that acts on a task
- `h herdr`: a Herdr plugin (`herdr-plugin/herdr-plugin.toml`) with actions `hiiro.switch`, `hiiro.todo-add`, `hiiro.todos`, `hiiro.shell`, and `hiiro.nvim` that open a popup running `t`; `h herdr install` copies and links it, `h herdr keys` prints keybindings
- `Hiiro::TestHarness` understands `add_cmd`, `add_option`, `add_flag`, and `opts`
- `t TASK todo show ID` and `tt TASK show ID` print one todo's text; `todo ls --plain` prints text only
- Add `h env add NAME VALUE` and `h alias add NAME COMMAND...` to append safely quoted shell definitions, preferring existing zsh module files and falling back to the root dotfiles. Use native Hiiro options, including `opts.global` and `--`.
- Add `h bin add NAME [COMMAND ...]` to generate executable `Hiiro.run` templates with optional empty `add_cmd` blocks. Serialize command names as Ruby symbols and refuse existing files or symlinks.
- `t ls` and `t list` root commands list tasks like bare `t`
- `Hiiro::Error`: `Hiiro#run` prints only `ERROR: message` for it, no backtrace
- `builtin_commands: false` option for `Hiiro.run`/`run_child` to skip the automatic `pry` and `edit` commands
- `Hiiro#open_default(target)` opens a path or URL with `open`/`xdg-open`
- `t` and `tt` are gem executables (`exe/t`, `exe/tt`) installed with Hiiro
- `t TASK tree new|rm|resume`, `t TASK tree`, `t TASK path`, `t TASK branch`, `t TASK sh`, and `t TASK cd` bring worktree and shell commands from `h task` into `t`; subtasks are `parent/child` names
- `Hiiro::CurrentTask`: one resolver for the current task (Herdr workspace, working directory, saved pin) used by `t` and by `Environment#task`
- `Hiiro::Git.repo_dir` so worktree commands work when `~/work/.git` is a gitfile pointing at the bare repo

### Fixed
- `h task start` and worktree listing failed with "Not a directory" when `~/work/.git` is a gitfile; git now runs in the parent directory

### Changed
- `t` grammar is now command-first, `t COMMAND [TASK] [ARGS...]`, matching the old `h task` rule: the first positional word is the task when it names one (exact or unique prefix), otherwise the current task is used and the word stays in the payload. `.` is the current task, `-` selects orphan todos. `tt ...` is `t todo ...`. `Hiiro::TaskScope` is removed
- `t todo add` no longer creates tasks; only `t new NAME` does
- Move the task CLI into `lib/hiiro/task_cli.rb` (`Hiiro::TaskCli`); `exe/t` and `exe/tt` are thin `Hiiro.run` launchers and `bin/t`, `bin/tt` are symlinks
- `t` requires `hiiro` like other bins instead of editing the load path; `task_scope` and `task_sessions` load with `hiiro`
- `t` errors print without a backtrace; task, scope, and session errors subclass `Hiiro::Error`
- `t` saves the current task through the `PinRecord` model and resolves resources, documents, tabs, and panes with `Hiiro::Matcher`, accepting unique prefixes and offering fuzzyfind when no reference is given
- `tt` runs the todo scope in-process instead of exec'ing `t`
- `h task` is now a symlink to `t` (`bin/h-task` -> `exe/t`); the inline `h task` and `h subtask` subcommands are gone, and `h task start|stop|resume|switch|sh|cd|path|branch|todo` map to `t` commands (see docs/h-task.md)
- `Environment#task` also matches the working directory against task homes, primary directories, and registered directories
- `TaskManager#start_task` uses the extracted `create_tree`
- Task listing prints aligned columns with the open todo count after each name, e.g. `prez (3)`, plus `next:`/`waiting:` text
- `ls` and `list` are now reserved root words in `t`; tasks with those exact names need a unique prefix

## [0.1.366] - 2026-09-14

### Changed
- Implement task-first CLI syntax: `t TASK COMMAND...` replaces `t COMMAND [TASK]...`
- Task names now precede commands, appearing immediately after `t` or after a group
- Task resolution prefers exact names, then unique case-sensitive prefixes; ambiguous prefixes fail
- Move workspace command from `t workspace TASK` to `t TASK switch` (keep `workspace` as alias)
- Rename implicit task selection to explicit `.` reference; bare `t` lists all tasks without selecting
- Update `t current TASK` to `t TASK current`; explicit named selections save fallback after success
- Context resolution checks calling Herdr workspace, then current directory, then saved task; reject ambiguous matches

### Added
- Task todo management under `t TASK todo` with `add`, `rm`, `list`/`ls` subcommands; todos share existing database with `h todo`
- `tt TASK ...` shortcut delegates to `t TASK todo ...`; bare `tt` uses current task via `.` selection
- Orphan todo scope with `t - todo` and `tt -` for unassigned todos; `-` invalid outside todo commands
- Native AI session launches via `t TASK omp`, `codex`/`cdx`, and `claude`/`cld` for fresh tool instances
- Resume mode with first-argument prefix matching (e.g., `r`, `res`, `resume`); focuses unique running instance or launches native picker
- `Hiiro::TaskScope` library for named/current/orphan task reference resolution with cached context
- `Hiiro::TaskSessions` library for AI tool launch/resume dispatch with Herdr workspace integration
- New `lib/hiiro/task_scope.rb` and `lib/hiiro/task_sessions.rb` support libraries
- New `bin/tt` executable for todo shortcut

## [0.1.365] - 2026-09-13

### Added
- Add the `t` task CLI with `--task`/`-t` selection, durable task status and next actions, document homes, resource references, and Herdr workspace/tab/pane commands.
- Allow block-only command dispatch with `external_commands: false`, keeping legacy `t-*` executables out of the task CLI.
- Add `Hiiro::Herdr`, a JSON-backed adapter for Herdr workspaces, tabs, panes, notifications, and command execution.
- Persist Herdr workspace/tab/pane IDs for invocations, branches, queued prompts, services, and tracked PRs, with read fallbacks for legacy metadata.

### Changed
- Keep task command definitions and helpers in `~/bin/t`, using `add_cmd` and native Hiiro help instead of a library-level TaskCLI and custom help template.
- Preserve task records and resource references when detaching or pruning worktrees.
- Move task, project, queue, service, background, Claude, app navigation, PR attach, title, and notification workflows from tmux to Herdr.
- Keep `h session` and `h window` as compatibility commands for Herdr workspaces and tabs.

### Removed
- Remove tmux paste-buffer, jumplist, task-color, focus-hook, and arbitrary-layout features that Herdr 0.8.2 does not support.
- Remove the old `Hiiro::Tmux` adapter and tmux-specific command tests.