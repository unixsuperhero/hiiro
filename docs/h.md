# h

The main hiiro entry point — dispatch to all subcommands, install, update, and configure the framework.

## Synopsis

```bash
h <subcommand> [options] [args]
h version [-a]
h install [-a] [-p]
h setup
```

## Subcommands

| Subcommand | Aliases | Description |
|------------|---------|-------------|
| `version` | — | Print the installed hiiro version |
| `install` | `update` | Install or update the hiiro gem |
| `setup` | — | Copy bin scripts and plugins to `~/bin/` |
| `ping` | — | Print `pong` (smoke test) |
| `alert` | — | Send a macOS notification |
| `queue` | — | Manage Claude prompt queue |
| `service` | `svc` | Manage background services |
| `run` | — | Run linters/formatters on changed files |
| `file` | — | Manage tracked file lists per app |
| `check_version` | — | Verify installed hiiro version |
| `delayed_update` | — | Poll RubyGems and auto-install when a version appears |
| `rnext` | — | Run `git rnext` |

## External Subcommands

hiiro dispatches to external executables matching `h-*` in PATH. All of these are separate docs:

- [h-app](h-app.md) — Named app directories within a git repo
- [h-bg](h-bg.md) — Background tmux windows with history
- [h-bin](h-bin.md) — List and edit hiiro bin scripts
- [h-branch](h-branch.md) — Git branch management with task associations
- [h-buffer](h-buffer.md) — tmux paste buffer management
- [h-claude](h-claude.md) — Launch Claude Code sessions in tmux
- [h-commit](h-commit.md) — Fuzzy-select git commit SHAs
- [h-config](h-config.md) — Open config files in editor
- [h-cpr](h-cpr.md) — Proxy `h pr` commands to current branch's PR
- [h-db](h-db.md) — Inspect and manage the hiiro SQLite database
- [h-img](h-img.md) — Save/encode clipboard images
- [h-jumplist](h-jumplist.md) — Vim-style tmux navigation history
- [h-link](h-link.md) — Store, search, tag, and open URLs
- [h-misc](h-misc.md) — Miscellaneous utilities
- [h-notify](h-notify.md) — In-pane notifications with macOS alerts
- [h-pane](h-pane.md) — tmux pane management
- [h-plugin](h-plugin.md) — List, edit, and search plugin files
- [h-pm](h-pm.md) — Queue project-manager skill prompts
- [h-pr](h-pr.md) — GitHub PR tracking and management
- [h-pr-monitor](h-pr-monitor.md) — Poll PR checks and notify on status changes
- [h-project](h-project.md) — Project directory and tmux session management
- [h-registry](h-registry.md) — Named resource registry
- [h-session](h-session.md) — tmux session management
- [h-sha](h-sha.md) — Fuzzy-select and copy git SHAs
- [h-sparse](h-sparse.md) — Manage git sparse-checkout path groups
- [h-tags](h-tags.md) — Query tags by taggable type
- [h-title](h-title.md) — Update terminal tab title from tmux session
- [h-todo](h-todo.md) — Personal todo list management
- [h-window](h-window.md) — tmux window management
- [h-wtree](h-wtree.md) — Git worktree management

## Options

### `version`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--all` | `-a` | Show version for all rbenv Ruby versions | false |

### `install` / `update`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--all` | `-a` | Update all rbenv Ruby versions in parallel | false |
| `--pre` | `-p` | Install pre-release version | false |

### `check_version`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--all` | `-a` | Check all rbenv versions | false |

## Subcommand Details

### `version`

Print the installed hiiro version. With `--all`, prints the version for every rbenv-managed Ruby installation in parallel.

```bash
h version
h version -a
```

### `install` / `update`

Install or update the hiiro gem. Without `--all`, updates only the current rbenv Ruby. With `--all`, updates all rbenv Rubies in parallel threads, printing each result as it completes.

```bash
h install
h update -a
h install --pre
```

### `setup`

Copy hiiro bin scripts (`bin/h-*`) and plugin files (`plugins/*.rb`) to `~/bin/` and `~/.config/hiiro/plugins/`. Scripts are renamed from `h-*` to match the prefix of the binary that invoked setup (e.g., `hiiro-` if invoked as `hiiro setup`). Warns if `~/bin` is not in `$PATH`.

```bash
h setup
```

### `ping`

Basic smoke test — prints `pong`.

```bash
h ping
# => pong
```

### `alert`

Send a macOS notification via `terminal-notifier`. Options are passed as inline flags:

| Flag | Description |
|------|-------------|
| `-m` | Message text |
| `-t` | Notification title |
| `-l` | URL to open on click |
| `-c` | Shell command to run on click |
| `-s` | Sound name |

```bash
h alert -m "Build finished" -t "CI" -l "https://github.com/..."
```

### `check_version`

Verify that the installed hiiro version matches an expected version string. Exits 0 if all checked versions match, 1 otherwise.

```bash
h check_version 0.1.42
h check_version 0.1.42 -a
```

### `delayed_update`

Poll RubyGems until a specified version appears (up to ~10 minutes), then run `h install -a` in a background tmux window via `h bg run`. Sends a macOS notification when complete.

```bash
h delayed_update 0.1.50
```

## Examples

```bash
# Check current version
h version

# Update hiiro across all Ruby versions
h update -a

# Install a prerelease version
h install --pre

# Set up after gem install
h setup

# Verify version on CI
h check_version 0.1.42 && echo "OK"

# Fire-and-forget update after publishing
h delayed_update 0.1.50
```
