# h-project

Manage project directories and start tmux sessions for them.

## Usage

```
h project <subcommand> [args]
```

Projects are discovered from two sources:
- Directories in `~/proj/`
- Entries in `~/.config/hiiro/projects.yml`

## Subcommands

### `open`

Open a project by name (regex match, case-insensitive) and start or switch to its tmux session. Falls back to `~/proj/` if no match.

**Args:** `<project_name>`

### `list` [alias: `ls`]

List all known projects with source tag (`[config]` or `[dir]`) and path.

### `config`

Print the contents of `~/.config/hiiro/projects.yml`.

### `edit`

Open `~/.config/hiiro/projects.yml` in your editor (creates the file if it does not exist).

### `select`

Fuzzy-select a project and print its path.

### `copy`

Fuzzy-select a project and copy its path to clipboard.

### `sh`

Open a shell (or run a command) inside a project directory.

**Args:** `<project_name> [cmd...]`

### `help`

Print usage information.
