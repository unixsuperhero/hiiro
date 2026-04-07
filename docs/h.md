# h

The main entry point for the hiiro CLI framework. Hiiro provides multi-command dispatch similar to `git` or `docker`, with abbreviation matching, a plugin system, and a rich set of built-in tools for task management, tmux integration, and developer workflow automation.

## Synopsis

```bash
h <subcommand> [args]
```

Subcommands support prefix matching — `h ver` matches `h version`, `h br s` matches `h branch save`. Ambiguous prefixes list all matching options.

## Inline subcommands

These subcommands are defined directly in `exe/h` or loaded from `lib/`:

| Subcommand | Description | Source |
|------------|-------------|--------|
| `h alert` | Send a macOS notification | `exe/h` |
| `h check_version` | Verify installed hiiro version across rbenv versions | `exe/h` |
| `h delayed_update` | Poll RubyGems for a new version and install when available | `exe/h` |
| `h edit` | Open the `h` bin file in your editor | `exe/h` |
| [`h file`](h-file.md) | Track frequently-used files per app and open them in your editor | `lib/hiiro/app_files.rb` |
| `h install` / `h update` | Install or update the hiiro gem (`-a` all rbenv versions, `-p` pre-release) | `exe/h` |
| `h ping` | Health check — prints `pong` | `exe/h` |
| `h pry` | Open a pry REPL in the hiiro context | `exe/h` |
| [`h queue`](h-queue.md) | Claude prompt queue — create, watch, and run AI prompts in tmux | `lib/hiiro/queue.rb` |
| `h rnext` | Run `git rnext` (rebase next) | `exe/h` |
| [`h run`](h-run.md) | Run dev tools (linters, formatters, tests) against changed files | `lib/hiiro/runner_tool.rb` |
| [`h service`](h-service.md) | Dev service management with tmux, env files, and service groups | `lib/hiiro/service_manager.rb` |
| `h setup` | Install plugins and bin scripts to `~/bin` | `exe/h` |
| [`h subtask`](h-subtask.md) | Subtask management scoped to the current parent task | `lib/hiiro/tasks.rb` |
| [`h task`](h-task.md) | Task management — worktree + tmux session pairs for parallel development | `lib/hiiro/tasks.rb` |
| `h version` | Print installed hiiro version (`-a` for all rbenv versions) | `exe/h` |

## External subcommands

These are separate `bin/h-*` executables dispatched by `h`:

| Command | Description |
|---------|-------------|
| [`h app`](h-app.md) | App directory and sub-tool management |
| [`h bg`](h-bg.md) | Run commands in background tmux windows |
| [`h bin`](h-bin.md) | List and edit bin executables |
| [`h branch`](h-branch.md) | Git branch management |
| [`h buffer`](h-buffer.md) | tmux buffer management |
| [`h claude`](h-claude.md) | Claude CLI integration and queue |
| [`h commit`](h-commit.md) | Interactive commit selection |
| [`h config`](h-config.md) | Open config files in editor |
| [`h cpr`](h-cpr.md) | Shortcut to current branch's PR |
| [`h db`](h-db.md) | SQLite database inspection and management |
| [`h img`](h-img.md) | Image clipboard utilities |
| [`h jumplist`](h-jumplist.md) | Vim-style tmux navigation history |
| [`h link`](h-link.md) | URL bookmark management |
| [`h misc`](h-misc.md) | Miscellaneous utilities |
| [`h notify`](h-notify.md) | tmux notification system |
| [`h pane`](h-pane.md) | tmux pane management |
| [`h plugin`](h-plugin.md) | Plugin management |
| [`h pm`](h-pm.md) | Project manager skill launcher |
| [`h pr`](h-pr.md) | GitHub PR management |
| [`h pr-monitor`](h-pr-monitor.md) | PR monitoring dashboard |
| [`h project`](h-project.md) | Project directory and tmux session manager |
| [`h registry`](h-registry.md) | Generic resource registry |
| [`h session`](h-session.md) | tmux session management |
| [`h sha`](h-sha.md) | Interactive git SHA selection |
| [`h sparse`](h-sparse.md) | Git sparse checkout group management |
| [`h tags`](h-tags.md) | Tag management |
| [`h title`](h-title.md) | Terminal tab title management |
| [`h todo`](h-todo.md) | Todo item management |
| [`h window`](h-window.md) | tmux window management |
| [`h wtree`](h-wtree.md) | Git worktree management |
