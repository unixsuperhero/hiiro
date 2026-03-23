Done. CHANGELOG.md updated with v0.1.272.

## Unreleased

### Added
- `Hiiro::Background` module: runs shell commands asynchronously in a hidden `h-bg` tmux session; falls back to detached spawn outside tmux
- `terminal-notifier`, `afplay`, and `TaskColors` tmux set-option calls now use `Background.run` (non-blocking)
- `bin/h-bg`: new subcommand with `popup` (nvim tempfile → run in bg), `run`, `attach`, `history`, `setup`; persists command history to `~/.config/hiiro/bg-history.txt`
- Auto-tag current git branch with task name whenever a hiiro command runs from within a task worktree (skips master/main, idempotent)
