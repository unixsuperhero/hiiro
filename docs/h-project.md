# h-project

Manage project directories and start tmux sessions for them.

## Synopsis

```bash
h project <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `open <name>` | Open a project and start/attach tmux session |
| `list` / `ls` | List all known projects |
| `config` | Show the config file contents |
| `edit` | Edit the config file |
| `select` | Fuzzy-select a project and print its path |
| `copy` | Fuzzy-select a project and copy path to clipboard |
| `sh <name> [cmd]` | Open shell (or run command) in a project directory |
| `help` | Show usage |

Projects are discovered from two sources:

1. Directories in `~/proj/`
2. Entries in `~/.config/hiiro/projects.yml`

The default subcommand (no subcommand) runs `help`.

### config

Print the contents of `~/.config/hiiro/projects.yml`.

**Examples**

```bash
h project config
```

### copy

Fuzzy-select a project and copy its path to the clipboard.

**Examples**

```bash
h project copy
```

### edit

Open `~/.config/hiiro/projects.yml` in your editor. Creates the file with a template comment if it doesn't exist.

**Examples**

```bash
h project edit
```

### list / ls

List all projects with their source (`[config]` or `[dir]`) and path.

**Examples**

```bash
h project list
h project ls
```

### open

Open a project by name and start (or attach to) a tmux session for it. Project names are matched with case-insensitive regex; if exactly one match is found, it's used. If multiple matches are found, an exact match is preferred.

**Examples**

```bash
h project open hiiro
h project open my-app
```

### select

Fuzzy-select a project and print its absolute path.

**Examples**

```bash
h project select
cd $(h project select)
```

### sh

Open a shell in a project directory, or run a command there.

**Examples**

```bash
h project sh hiiro
h project sh hiiro bundle exec rake test
```

## Configuration

`~/.config/hiiro/projects.yml`:

```yaml
my-app: /Users/me/work/my-app
hiiro: /Users/me/proj/hiiro
```
