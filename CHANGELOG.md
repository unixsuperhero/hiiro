## [Unreleased]

### Added
- `bin/h-title`: new command that updates the terminal (Ghostty/iTerm2) tab title to the hiiro task name when switching tmux sessions. Run `h title setup` to install the tmux hooks (`client-session-changed`, `after-new-session`). The `h title update` subcommand looks up the task associated with the current tmux session and emits OSC 0 to the client TTY.
- `Hiiro#run_child` instance method: creates a child Hiiro and immediately runs it, equivalent to `make_child(...).run`. Mirrors the `Hiiro.run` / `Hiiro.init` relationship at the instance level.
- CLAUDE.md: added "Coding Rules and Conventions" section with rules for `Hiiro.run` in bin files, append-only CHANGELOG, and keeping docs current.
- CLAUDE.md: documented `run_child` with usage example.

Done.
