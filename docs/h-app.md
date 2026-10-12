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
| `cd [name]` | Send a `cd` to the current Herdr pane |
| `path [name]` | Print relative path to app (from cwd) |
| `abspath [name]` | Print absolute path to app |
| `fd <name> [args]` | Run `fd` scoped to an app directory |
| `rg <name> [args]` | Run `rg` scoped to an app directory |
| `vim <name> [args]` | Open vim scoped to an app directory |
| `sh <name> [cmd]` | Open a shell (or run a command) in an app directory |
| `config` / `edit` | Edit a temporary projection of saved app aliases |
| `show` | Print saved app aliases as YAML |
| `service` | Manage services (delegates to `h service`) |
| `run` | Run tools against changed files (delegates to `h run`) |
| `file` | Manage tracked app files (delegates to `h file`) |

### abspath

Print the absolute path to the app.

**Examples**

```bash
h app abspath api
```

### add

Register an app with a name and relative path from the repo root.

**Examples**

```bash
h app add api backend/api
h app add web frontend/web
```

### cd

Send a `cd` command to the current Herdr pane to navigate to an app directory. Resolves the app path relative to the git repo root or current task tree. With no name, `cd`s to the repo root.

**Examples**

```bash
h app cd
h app cd api
```

### config

Alias for `edit`. Open a temporary YAML projection of canonical SQLite app records in your editor, not `apps.yml`.

**Examples**

```bash
h app config
```

### edit

Edit saved app aliases through `InputFile`. The temporary document contains an array of records with `id`, `name`, and `path`, as shown under Configuration.

Keep an existing row's `id` unchanged. Omit `id` on a new row. Add `delete: true` to an existing row to delete it; omitting a row leaves it unchanged. Only changed fields are written, so edits preserve unrelated rows and concurrent changes to other fields. A conflicting concurrent change, invalid document, or failed editor leaves the database unchanged.

```bash
h app edit
```

### show

Print the YAML projection without opening an editor. An empty registry prints `--- []`.

```bash
h app show
```

### fd

Run `fd` in the app's directory. All extra arguments are forwarded to `fd`.

**Examples**

```bash
h app fd api '*.rb'
h app fd web --type f
```

### file

Delegate to the app file tracking system.

**Examples**

```bash
h app file ls
h app file add myapp src/main.rb
```

### ls

List all configured apps with their relative paths.

**Examples**

```bash
h app ls
```

### path

Print the relative path (from current directory) to the app. With no name, prints the repo root path.

**Examples**

```bash
h app path api
h app path
```

### rg

Run `rg` (ripgrep) in the app's directory. All extra arguments are forwarded to `rg`.

**Examples**

```bash
h app rg api 'def foo'
```

### rm / remove

Remove a registered app.

**Examples**

```bash
h app rm api
```

### run

Delegate to the runner tool system for running linters/tests against changed files.

**Examples**

```bash
h app run
h app run lint ruby
```

### service

Delegate to the `h service` subcommand system, scoped to the current app context. All `h service` subcommands (`ls`, `start`, `stop`, `attach`, `open`, `url`, `port`, `status`, `add`, `rm`, `config`, `groups`, `env`) are available.

**Examples**

```bash
h app service ls
h app service start my-rails
```

### sh

Open a shell in the app's directory. If additional arguments are provided, run them as a command instead.

**Examples**

```bash
h app sh api
h app sh api bundle exec rails console
```

### vim

Open vim in the app's directory. Extra arguments are forwarded.

**Examples**

```bash
h app vim api
h app vim api src/main.rb
```

## Configuration

App aliases live in the `apps` table of `~/.config/hiiro/hiiro.db`, owned by `Hiiro::AppRecord`. `h app show` prints this projection:

```yaml
- id: 1
  name: api
  path: backend/api
- id: 2
  name: web
  path: frontend/web
- id: 3
  name: workers
  path: backend/workers
```

Paths are relative to the git repo root or current task tree path.

Legacy `apps.yml` is an explicit import input for `h db plan --only apps` and `h db migrate --only apps`. App commands do not read or rewrite it. See [h-db](h-db.md) for source selection and recovery. App-file definitions in `app_files.yml`, services, tools, and sparse definitions remain ordinary configuration files.
