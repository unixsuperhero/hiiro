## [Unreleased]

### Fixed
- `add_default` runner now receives all args including the first positional arg (which was previously consumed as `subcmd`). The block now receives `[subcmd, *args].compact` instead of just `args`.

### Added
- `bin/h-title`: new command that updates the terminal (Ghostty/iTerm2) tab title to the hiiro task name when switching tmux sessions. Run `h title setup` to install the tmux hooks (`client-session-changed`, `after-new-session`). The `h title update` subcommand looks up the task associated with the current tmux session and emits OSC 0 to the client TTY.
- `Hiiro#run_child` instance method: creates a child Hiiro and immediately runs it, equivalent to `make_child(...).run`. Mirrors the `Hiiro.run` / `Hiiro.init` relationship at the instance level.
- CLAUDE.md: added "Coding Rules and Conventions" section with rules for `Hiiro.run` in bin files, append-only CHANGELOG, and keeping docs current.
- CLAUDE.md: documented `run_child` with usage example.
- Persistent per-task tmux color themes: each task session gets a unique `status-bg`/`status-fg` color pair from a 12-color palette. The assigned `color_index` is stored in `tasks.yml` so the same color survives restarts. Colors are applied automatically when a session is created (`h task start`) or switched to (`h task switch`). `h task color` re-applies the current task's colors manually.

Done.

### Refactored
- Editor/tempfile input logic moved out of inline subcommand blocks and into `Hiiro::InputFile`. The `add` subcommands in `Queue`, `ServiceManager`, and `RunnerTool`, and the bulk-tag editor in `Tasks`, now use `InputFile.yaml_file` / `InputFile.md_file` instead of raw `Tempfile` + `edit_files` + `File.read` + `unlink`.
- `InputFile#parsed_file` now accepts a `permitted_classes:` keyword argument (forwarded to `YAML.safe_load_file`).
- Deleted unused `Hiiro::EditorInput` class (`lib/hiiro/editor_input.rb`).
