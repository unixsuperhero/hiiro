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
| `add <name> <path>` | Save or update a project alias |
| `rm <name>` / `remove <name>` | Remove a saved project alias |
| `config` | Print saved project aliases as YAML |
| `edit` | Edit a temporary projection of saved project aliases |
| `select` | Fuzzy-select a project and print its path |
| `copy` | Fuzzy-select a project and copy path to clipboard |
| `sh <name> [cmd]` | Open shell (or run command) in a project directory |
| `help` | Show usage |

Projects are discovered from two sources:

1. Directories in `~/proj/`
2. Saved aliases in SQLite, which take precedence over directories with the same name

The default subcommand (no subcommand) runs `help`.

### config

Print a YAML projection of saved SQLite project aliases, with `id`, `name`, and `path` for each row. Directory discovery is not included. With no saved aliases, prints `--- []`.

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

Open a temporary YAML projection of saved SQLite project aliases through `InputFile`, not `projects.yml`.

Keep an existing row's `id` unchanged. Omit `id` on a new row. Add `delete: true` to an existing row to delete it; omitting a row leaves it unchanged. Only changed fields are written. Unrelated rows and concurrent changes to other fields survive. A conflicting concurrent change, invalid document, or failed editor leaves the database unchanged.

**Examples**

```bash
h project edit
```

### list / ls

List all projects with their source (`[config]` for SQLite aliases or `[dir]` for discovered directories) and path.

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

### add

Save a named project alias. An existing name updates only its path and keeps its database ID.

```bash
h project add my-app ~/work/my-app
```

### rm / remove

Delete only the saved alias with the exact name. This does not delete its directory or exclude it from `~/proj/` discovery.

```bash
h project rm my-app
```

## Configuration

Project aliases live in the `projects` table of `~/.config/hiiro/hiiro.db`, owned by `Hiiro::Project`. `h project config` prints this projection:

```yaml
- id: 1
  name: my-app
  path: /Users/me/work/my-app
- id: 2
  name: hiiro
  path: /Users/me/proj/hiiro
```

Legacy `projects.yml` is an explicit import input for `h db plan --only projects` and `h db migrate --only projects`. Project commands do not read or rewrite it. See [h-db](h-db.md) for source selection and recovery. Directory discovery in `~/proj/` remains file-based.
