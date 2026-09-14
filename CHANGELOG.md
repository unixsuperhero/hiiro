# Changelog

## [Unreleased]

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
