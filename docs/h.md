# h

The main hiiro entry point — install, update, setup, and dispatch to all subcommands.

## Usage

```
h <subcommand> [options] [args]
h version [-a]
```

## Subcommands

### `version`

Print the installed hiiro version. With `-a`, print the version for every rbenv-managed Ruby.

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Show version for all rbenv Ruby versions | false |

### `install` [alias: `update`]

Install or update the hiiro gem via rbenv. With `-a`, updates across all rbenv Ruby versions in parallel.

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Update all rbenv Ruby versions | false |
| `--pre` | `-p` | Install pre-release version | false |

### `setup`

Copy hiiro bin scripts and plugins to `~/bin/` and `~/.config/hiiro/plugins/`. Renames `h-*` scripts to match the invocation prefix. Warns if `~/bin` is not in `$PATH`.

### `ping`

Print `pong`. Useful for testing that `h` is working.

### `alert`

Send a macOS notification via `terminal-notifier`. See `Hiiro::Notification` for option details.

**Options (passed via args):**
| Flag | Short | Description |
|---|---|---|
| `-m` | — | Message text |
| `-t` | — | Notification title |
| `-l` | — | Link to open on click |
| `-c` | — | Shell command to run on click |
| `-s` | — | Sound name |

### `queue`

Delegate to the `Hiiro::Queue` subcommands (`add`, `ls`, `run`, `watch`, `attach`, etc.). See the Queue section of CLAUDE.md for full details.

### `service` [alias: `svc`]

Delegate to `Hiiro::ServiceManager` subcommands (`ls`, `start`, `stop`, `attach`, `open`, etc.).

### `run`

Delegate to `Hiiro::RunnerTool` subcommands (`ls`, `add`, `rm`, `config`, and default run).

### `file`

Delegate to `Hiiro::AppFiles` subcommands (`ls`, `add`, `rm`, `edit`).

### `check_version`

Verify that the installed hiiro version matches an expected version string.

**Args:** `[expected_version]`

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Check all rbenv versions | false |

### `delayed_update`

Poll RubyGems until an expected version appears, then run `h install -a`. Runs as a background task via `h bg run`. Sends a macOS notification when complete.

**Args:** `<expected_version>`

### `rnext`

Run `git rnext` (custom git alias for rebasing to the next commit).

**Args:** `[git_args...]`
