# Changelog

## [Unreleased]

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

### Fixed
- Strip the desktop notifier executable path and run notifications and sounds as detached processes instead of creating persistent Herdr tabs.
- Preserve `add_cmd` declaration locations and argument metadata in generated help; allow command groups to pass arguments and help through to child commands.
- Make undeclared `add_cmd opts:` entries boolean flags without consuming positional arguments; preserve explicit options and reserve conflicting short aliases.
- Show selected command options for `add_cmd -h`/`--help` without executing the command block.
- Focus the exact Herdr pane through the socket API and read the CLI's plain-text pane output without JSON parsing.
- Restore the missing `Hiiro::Bins` helper so `require "hiiro"` boots and commands like `h jumplist record` dispatch correctly.
- Make Hiiro's Ruby requirement explicit as Ruby 3.2+ and have rbenv-wide gem installs skip incompatible Ruby versions.
- Update the publish script to preserve the Ruby support constant, run only on supported Ruby, and install releases only into compatible rbenv versions.