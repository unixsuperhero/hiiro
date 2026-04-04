# h-app

Manage named application subdirectories within a git repo or task worktree. Provides shortcuts to navigate, search, and run tools scoped to each app.

## Synopsis

```bash
h app <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ls` | List all configured apps |
| `add <name> <path>` | Register a new app |
| `rm <name>` | Remove an app |
| `cd [name]` | Send a `cd` to the current tmux pane |
| `path [name]` | Print relative path to app (from cwd) |
| `abspath [name]` | Print absolute path to app |
| `fd <name> [args]` | Run `fd` scoped to an app directory |
| `rg <name> [args]` | Run `rg` scoped to an app directory |
| `vim <name> [args]` | Open vim scoped to an app directory |
| `sh <name> [cmd]` | Open a shell (or run a command) in an app directory |
| `config` | Edit `~/.config/hiiro/apps.yml` |
| `service` | Manage services (delegates to `h service`) |
| `run` | Run tools against changed files (delegates to `h run`) |
| `file` | Manage tracked app files (delegates to `h file`) |

### ls

List all configured apps with their relative paths.

**Examples**

```bash
h app ls
```

### add

Register an app with a name and relative path from the repo root.

**Examples**

```bash
h app add api backend/api
h app add web frontend/web
```

### rm / remove

Remove a registered app.

**Examples**

```bash
h app rm api
```

### cd

Send a `cd` command to the current tmux pane to navigate to an app directory. Resolves the app path relative to the git repo root or current task tree. With no name, `cd`s to the repo root.

**Examples**

```bash
h app cd
h app cd api
```

### path

Print the relative path (from current directory) to the app. With no name, prints the repo root path.

**Examples**

```bash
h app path api
h app path
```

### abspath

Print the absolute path to the app.

**Examples**

```bash
h app abspath api
```

### fd

Run `fd` in the app's directory. All extra arguments are forwarded to `fd`.

**Examples**

```bash
h app fd api '*.rb'
h app fd web --type f
```

### rg

Run `rg` (ripgrep) in the app's directory. All extra arguments are forwarded to `rg`.

**Examples**

```bash
h app rg api 'def foo'
```

### vim

Open vim in the app's directory. Extra arguments are forwarded.

**Examples**

```bash
h app vim api
h app vim api src/main.rb
```

### sh

Open a shell in the app's directory. If additional arguments are provided, run them as a command instead.

**Examples**

```bash
h app sh api
h app sh api bundle exec rails console
```

### config

Edit the apps config file (`~/.config/hiiro/apps.yml`) in your editor.

**Examples**

```bash
h app config
```

### service

Delegate to the `h service` subcommand system, scoped to the current app context. See [h-app.md](h-app.md) service section and `h service` docs.

**Examples**

```bash
h app service ls
h app service start my-rails
```

### run

Delegate to the runner tool system for running linters/tests against changed files.

**Examples**

```bash
h app run
h app run lint ruby
```

### file

Delegate to the app file tracking system.

**Examples**

```bash
h app file ls
h app file add myapp src/main.rb
```

## Configuration

Apps are stored in `~/.config/hiiro/apps.yml`:

```yaml
api: backend/api
web: frontend/web
workers: backend/workers
```

Paths are relative to the git repo root (or current task tree path).
