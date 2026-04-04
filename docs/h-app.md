# h-app

Manage named application subdirectories within a git repo, with shortcuts to cd, search, and run tools scoped to each app.

## Synopsis

```bash
h app <subcommand> [args]
```

Apps are stored in SQLite (`~/.config/hiiro/hiiro.db`) and referenced by name. Paths are relative to the repository root. When resolving paths, `h-app` first checks the current git root, then falls back to the current task's tree path.

## Subcommands

| Subcommand | Aliases | Description |
|------------|---------|-------------|
| `config` | — | Open `apps.yml` in editor |
| `cd` | — | Send `cd <app_dir>` to current tmux pane |
| `ls` | — | List all configured apps |
| `path` | — | Print relative path to app from current directory |
| `abspath` | — | Print absolute filesystem path of app |
| `add` | — | Register a new app name with its path |
| `rm` | `remove` | Remove a registered app by name |
| `fd` | — | Run `fd` inside the app directory |
| `rg` | — | Run `rg` (ripgrep) inside the app directory |
| `vim` | — | Open vim inside the app directory |
| `sh` | — | Open a shell (or run a command) inside the app directory |
| `service` | — | Delegate to [h service](h.md) subcommands |
| `run` | — | Delegate to [h run](h.md) subcommands |
| `file` | — | Delegate to [h file](h.md) subcommands |

## Subcommand Details

### `config`

Open the `~/.config/hiiro/apps.yml` file in your editor.

```bash
h app config
```

### `cd`

Send a `cd` command to the current tmux pane using `tmux send-keys`. If no app name is given, cd's to the repo root. Uses relative paths.

```bash
h app cd             # cd to repo root
h app cd backend     # cd to backend app directory
```

### `ls`

List all configured apps with their relative paths from the repo root.

```bash
h app ls
# Configured apps:
#   backend              => services/backend
#   frontend             => apps/web
```

### `path`

Print the relative path from the current directory to the named app (or repo root if no name given).

```bash
h app path backend
```

### `abspath`

Print the absolute filesystem path of the named app directory.

```bash
h app abspath backend
# => /Users/josh/work/myrepo/services/backend
```

### `add`

Register a new app name mapped to a path relative to the repo root.

```bash
h app add backend services/backend
h app add frontend apps/web
```

### `rm` / `remove`

Remove a registered app by name.

```bash
h app rm backend
```

### `fd`

Run `fd` inside the named app's directory. Extra arguments are forwarded to `fd`.

```bash
h app fd backend "*.rb"
h app fd frontend --type f --extension ts
```

### `rg`

Run `rg` (ripgrep) inside the named app's directory. Extra arguments are forwarded to `rg`.

```bash
h app rg backend "def process_payment"
h app rg frontend "useState" --type ts
```

### `vim`

Open vim inside the named app's directory. Extra arguments are forwarded to vim.

```bash
h app vim backend
h app vim frontend src/index.tsx
```

### `sh`

Open a shell (using `$SHELL` or `zsh`) inside the app directory. If extra args are given, runs them as a command instead.

```bash
h app sh backend
h app sh backend bundle exec rails console
```

### `service`

Delegate to `Hiiro::ServiceManager` subcommands. See [h service subcommands](h.md) for full details.

### `run`

Delegate to `Hiiro::RunnerTool` subcommands. See [h run subcommands](h.md) for full details.

### `file`

Delegate to `Hiiro::AppFiles` subcommands. See [h file subcommands](h.md) for full details.

## Examples

```bash
# Register apps for a monorepo
h app add api services/api
h app add web apps/frontend
h app add workers jobs/workers

# Navigate to an app
h app cd api

# Search for a pattern in the api app
h app rg api "class.*Controller"

# Open a shell in the web app
h app sh web

# Run tests for the api app
h app run api test
```
