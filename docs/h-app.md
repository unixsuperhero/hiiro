# h-app

Manage named application subdirectories within a git repo, with shortcuts to cd, search, and run tools scoped to each app.

## Usage

```
h app <subcommand> [args]
```

## Subcommands

### `config`

Open `~/.config/hiiro/apps.yml` in your editor.

### `cd` [alias: none]

Send a `cd` command to the current tmux pane to switch into an app directory (or the repo root if no name given).

**Args:** `[app_name]`

### `ls`

List all configured apps and their relative paths from the repo root.

### `path`

Print the relative path from the current directory to the app (or repo root).

**Args:** `[app_name]`

### `abspath`

Print the absolute filesystem path of the app directory (or repo root).

**Args:** `[app_name]`

### `add`

Register a new app name with a path relative to the repo root.

**Args:** `<app_name>` `<relative_path>`

### `rm` [alias: `remove`]

Remove a registered app by name.

**Args:** `<app_name>`

### `fd`

Run `fd` inside the named app's directory, passing all extra arguments to `fd`.

**Args:** `<app_name>` `[fd_args...]`

### `rg`

Run `rg` (ripgrep) inside the named app's directory.

**Args:** `<app_name>` `[rg_args...]`

### `vim`

Open vim inside the named app's directory.

**Args:** `<app_name>` `[vim_args...]`

### `sh`

Open a shell (or run a command) inside the named app's directory.

**Args:** `<app_name>` `[cmd...]`

### `service`

Delegate to `Hiiro::ServiceManager` subcommands scoped to the current app context. See `h service` for subcommand details.

### `run`

Delegate to `Hiiro::RunnerTool` subcommands. See `h run` for subcommand details.

### `file`

Delegate to `Hiiro::AppFiles` subcommands. See `h file` for subcommand details.
