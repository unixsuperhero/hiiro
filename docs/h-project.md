# h-project

Manage project directories and open Herdr workspaces for them.

## Synopsis

```bash
h project <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `open <name>` | Open a project and focus/create its Herdr workspace |
| `list` / `ls` | List all known projects |
| `config` | Show the config file contents |
| `edit` | Edit the config file |
| `select` | Fuzzy-select a project and print its path |
| `copy` | Fuzzy-select a project and copy path to clipboard |
| `sh <name> [cmd]` | Open shell (or run command) in a project directory |
| `help` | Show usage |

Projects are discovered from two sources:

1. Directories in `~/proj/`
2. Aliases saved in registry table `project`

The default subcommand (no subcommand) runs `help`.

### config

Print the saved project aliases as YAML (`name: path` per line, sorted by name), or `No project aliases saved.` when there are none.

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

Open the saved project aliases as a YAML buffer in your editor. On save, changed paths are updated, new names are added, and removed names are deleted from table `project`. An invalid or empty buffer changes nothing and prints `No changes applied.`.

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

Open a project by name and focus (or create) a Herdr workspace rooted at its directory. Project names are matched with case-insensitive regex; if exactly one match is found, it is used. If multiple matches are found, an exact match is preferred.

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

Project aliases live in registry table `project` (name = alias, value = path). `h project config` and `h project edit` show them in this YAML shape:

```yaml
my-app: /Users/me/work/my-app
hiiro: /Users/me/proj/hiiro
```

A legacy `~/.config/hiiro/projects.yml` (and the old `projects` SQLite table) is imported into table `project` once at startup; the YAML file is then renamed `projects.yml.bak`.
