# h

The main entry point for the hiiro CLI framework. Provides self-management commands and dispatches to external subcommands (`h-*` binaries in PATH).

## Synopsis

```bash
h <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `version` | Print current hiiro version |
| `ping` | Health check — prints `pong` |
| `install` / `update` | Install or update hiiro across rbenv versions |
| `setup` | Install plugins and bin scripts to `~/bin` |
| `alert` | Send a macOS notification |
| `queue` | Manage the Claude prompt queue (delegates to `h queue`) |
| `service` / `svc` | Manage dev services (delegates to `h service`) |
| `run` | Run tools against changed files (delegates to `h run`) |
| `file` | Manage tracked app files (delegates to `h file`) |
| `task` | Manage tasks and worktrees |
| `subtask` | Manage subtasks within the current task |
| `check_version` | Verify installed hiiro version across rbenv versions |
| `delayed_update` | Poll RubyGems for a new version and install when available |
| `rnext` | Run `git rnext` (rebase next) |
| `edit` | Open the `h` bin file in your editor |
| `pry` | Open a pry REPL in the hiiro context |

All `h-*` executables found in PATH are also available as subcommands. For example, `h branch` dispatches to `h-branch`.

## Subcommand resolution

Hiiro supports prefix matching. If a prefix uniquely identifies a subcommand, it runs it:

```bash
h ver     # matches h version
h br s    # matches h branch save
```

If a prefix is ambiguous, hiiro lists all matching subcommands.

### version

Print the installed hiiro gem version. With `-a`, check all rbenv Ruby versions.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--all` | `-a` | Show version for all rbenv Ruby versions | false |

**Examples**

```bash
h version
h version --all
```

### install / update

Install or update the hiiro gem. With `-a`, updates all rbenv Ruby versions in parallel.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--all` | `-a` | Update all rbenv Ruby versions | false |
| `--pre` | `-p` | Install pre-release version | false |

**Examples**

```bash
h install
h update --all
h update --pre
```

### setup

Install hiiro plugins and bin scripts to `~/bin`. Renames `h-*` scripts to match the current prefix (e.g. `h-branch` stays `h-branch` for the `h` prefix). Warns if `~/bin` is not in PATH.

**Examples**

```bash
h setup
```

### alert

Send a macOS notification via `terminal-notifier`. See [h-notify](h-notify.md) for the full notification system.

**Options**

| Flag | Description |
|------|-------------|
| `-m` | Notification message |
| `-t` | Notification title |
| `-l` | URL to open when clicked |
| `-c` | Shell command to run when clicked |
| `-s` | Sound name |

**Examples**

```bash
h alert -t "Done" -m "Build finished" -s Glass
```

### check_version

Verify the installed hiiro version matches an expected version across rbenv Ruby versions. Exits non-zero if any version mismatches.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Check all rbenv versions |

**Examples**

```bash
h check_version 0.1.312
h check_version 0.1.312 --all
```

### delayed_update

Polls RubyGems until a specific version appears (up to ~10 minutes), then installs it via `h update -a`. Runs in a background tmux window via `h bg run`. Sends a macOS notification when complete.

**Examples**

```bash
h delayed_update 0.1.313
```

## External subcommands

These are separate bin files dispatched by `h`:

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
| [`h pm`](h-pm.md) | Project manager skill launcher |
| [`h plugin`](h-plugin.md) | Plugin management |
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
