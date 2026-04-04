# h-project

Manage project directories and start tmux sessions for them.

## Synopsis

```bash
h project <subcommand> [args]
```

Projects are discovered from two sources:

- Directories in `~/proj/`
- Entries in `~/.config/hiiro/projects.yml`

Config format (`projects.yml`):

```yaml
my-project: /path/to/my-project
client-work: /Users/josh/clients/acme
```

## Subcommands

| Subcommand | Aliases | Description |
|------------|---------|-------------|
| `open` | — | Open a project by name and start/switch to its tmux session |
| `list` | `ls` | List all known projects with source and path |
| `config` | — | Print the contents of `projects.yml` |
| `edit` | — | Open `projects.yml` in editor (creates if missing) |
| `select` | — | Fuzzy-select a project and print its path |
| `copy` | — | Fuzzy-select a project and copy path to clipboard |
| `sh` | — | Open a shell (or run a command) inside a project directory |
| `help` | — | Print usage information |

## Subcommand Details

### `open`

Open a project by name (case-insensitive regex match) and start or switch to its tmux session. If multiple regex matches are found, prefers an exact name match. Falls back to `~/proj/` if nothing matches.

```bash
h project open hiiro
h project open carrot
```

### `list` / `ls`

List all known projects showing name, source tag (`[config]` or `[dir]`), and path.

```bash
h project ls
# Projects:
#   carrot      [dir]     /Users/josh/work/carrot
#   hiiro       [dir]     /Users/josh/proj/hiiro
#   client-work [config]  /Users/josh/clients/acme
```

### `config`

Print the contents of `~/.config/hiiro/projects.yml`.

```bash
h project config
```

### `edit`

Open `~/.config/hiiro/projects.yml` in your editor. Creates the file with a comment header if it does not exist.

```bash
h project edit
```

### `select`

Fuzzy-select a project and print its path. Useful in scripts.

```bash
path=$(h project select)
cd "$path"
```

### `copy`

Fuzzy-select a project and copy its path to clipboard.

```bash
h project copy
```

### `sh`

Open a shell (using `$SHELL` or `zsh`) inside the project directory. Extra args run as a command.

```bash
h project sh hiiro
h project sh hiiro bundle exec rake test
```

## Examples

```bash
# Open a project and its tmux session
h project open hiiro

# Add a new project to config
h project edit
# add: my-project: /path/to/project

# Run tests in a project
h project sh hiiro bundle exec rake test

# List all projects
h project ls
```
