# h

The main entry point for the hiiro CLI framework. Hiiro provides multi-command dispatch similar to `git` or `docker`, with abbreviation matching, a plugin system, and built-in tools for task management, Herdr integration, and developer workflow automation.

## Synopsis

```bash
h <subcommand> [args]
```

Subcommands support prefix matching — `h ver` matches `h version`, `h br s` matches `h branch save`. Ambiguous prefixes list all matching options and run nothing.

Dispatch, this help, `h edit NAME`, and `h bin list|edit|complete|docs` share one command catalog. An external `h-NAME` executable (first in `PATH`; executable regular files or links to them only) beats an inline `NAME`, which beats an inline alias; losers are listed as shadowed. An exact name or alias wins over a unique prefix, and a child such as `pr-monitor` yields to its parent `pr`. See [the command catalog](../README.md#command-catalog).

Help, completion, and docs open no database and create no config directories. Persistence, invocation history, and branch auto-tagging start when an operation first uses persistence ([lazy startup](../README.md#lazy-startup)).

Workflow/directory commands share a resolved `TaskLocation` context rather than reselecting a task/app for each action. Explicit task selection wins over calling workspace, realpath directory, and (for `t` only) the saved pin. Root queue/service/run/file mounts disable that pin. Project/home commands use taskless roots. Native payload argv remains unchanged, and `cd` uses captured calling-pane IDs instead of focus. See [shared context](../README.md#shared-command-context).

## Inline subcommands

These subcommands are registered by `Hiiro::RootCommands` (`lib/hiiro/root_commands.rb`, run by `exe/h` and by `exe/hiiro`, the long name of `h`) or loaded from `lib/`:

| Subcommand | Description | Source |
|------------|-------------|--------|
| `h alert` | Send a macOS notification | `lib/hiiro/root_commands.rb` |
| `h check_version [VERSION]` | Show the installed hiiro in the current Ruby (`-a` every rbenv Ruby); exits 1 when one differs from VERSION | `lib/hiiro/root_commands.rb` |
| `h delayed_update VERSION` | In the background, run `h update -a --wait VERSION --notify` | `lib/hiiro/root_commands.rb` |
| `h edit [NAME...]` | Open the `h` bin file, or the source each `NAME` dispatches to; ambiguous or unknown names open nothing | `lib/hiiro.rb` |
| [`h file`](h-file.md) | Track frequently-used files per app and open them in your editor | `lib/hiiro/app_files.rb` |
| `h install` / `h update` | Install the gem per Ruby (`-a` every compatible rbenv Ruby, `-p` pre-release, `-w VERSION` wait for RubyGems first, `-n` notify), then apply shared assets once from the newest install; exits 1 if any Ruby failed | `lib/hiiro/root_commands.rb` |
| `h ping` | Health check — prints `pong` | `lib/hiiro/root_commands.rb` |
| `h pry` | Open a pry REPL in the hiiro context | `lib/hiiro.rb` |
| [`h queue`](h-queue.md) | Native `omp` prompt queue with shared task/app/directory context and explicit Herdr placement | `lib/hiiro/queue.rb` |
| `h rnext` | Run `git rnext` (rebase next) | `lib/hiiro/root_commands.rb` |
| [`h run`](h-run.md) | Run dev tools (linters, formatters, tests) against changed files | `lib/hiiro/runner_tool.rb` |
| [`h service`](h-service.md) / `h svc` | Dev service management with Herdr, env files, and service groups | `lib/hiiro/service_manager.rb` |
| `h setup [NAME...]` | Read-only drift plan of shared commands, their `bin/lib` files, and plugins. `--apply` installs missing and updates unmodified managed assets, `--retire` removes unmodified obsolete ones, `--adopt NAME` takes ownership of existing files; user-modified and unowned files are never written. Same for `hiiro setup` (installs `hiiro-NAME`). See [managed installation](../README.md#managed-installation) | `lib/hiiro/root_commands.rb` |
| [`h task`](h-task.md) | Symlink to `t`: task records, todos, worktrees, and Herdr workspaces | `lib/hiiro/task_cli.rb` |
| [`h herdr`](h-herdr.md) | Herdr plugin exposing `t` as keybound popups: switch task, add/copy todos, task shell, nvim | `bin/h-herdr`, `herdr-plugin/` |
| `h version` | Print installed hiiro version (`-a` for all rbenv versions) | `lib/hiiro/root_commands.rb` |

## External subcommands

These are separate `bin/h-*` executables dispatched by `h`:

| Command | Description |
|---------|-------------|
| [`h app`](h-app.md) | App directory and sub-tool management |
| [`h bg`](h-bg.md) | Run commands in background Herdr tabs |
| [`h bin`](h-bin.md) | List and edit bin executables |
| [`h branch`](h-branch.md) | Git branch management |
| [`h claude`](h-claude.md) | Claude CLI integration and queue |
| [`h commit`](h-commit.md) | Interactive commit selection |
| [`h config`](h-config.md) | Open config files in editor |
| [`h cpr`](h-cpr.md) | Shortcut to current branch's PR |
| [`h db`](h-db.md) | SQLite database inspection and management |
| [`h dotenv`](h-dotenv.md) | Compare `.env` files (read-only; `copy_to` only reports) |
| [`h extract`](../README.md#extract-files-directories-and-links) | Extract file paths, directories, and HTTP(S) links from text |
| [`h img`](h-img.md) | Image clipboard utilities |
| [`h link`](h-link.md) | URL bookmark management |
| [`h misc`](h-misc.md) | Miscellaneous utilities |
| [`h notify`](h-notify.md) | Herdr notification system |
| [`h pane`](h-pane.md) | Herdr pane management |
| [`h plugin`](h-plugin.md) | Plugin management |
| [`h pm`](h-pm.md) | Project manager skill launcher |
| [`h pr`](h-pr.md) | GitHub PR management |
| [`h pr-monitor`](h-pr-monitor.md) | Notify tracked PR check, review, and dependency changes |
| [`h project`](h-project.md) | Project directory and Herdr workspace manager |
| [`h registry`](h-registry.md) | Generic resource registry |
| [`h session`](h-session.md) | Compatibility commands for Herdr workspaces |
| [`h sign`](h-sign.md) | Inspect and verify an app bundle's code signature (never signs) |
| [`h sha`](h-sha.md) | Interactive git SHA selection |
| [`h sparse`](h-sparse.md) | Git sparse checkout group management |
| [`h title`](h-title.md) | Terminal tab title management |
| [`h todo`](h-todo.md) | Todo item management |
| [`h window`](h-window.md) | Compatibility commands for Herdr tabs |
| [`h wtree`](h-wtree.md) | Git worktree management |
