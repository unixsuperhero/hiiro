# h-registry

Store and look up named resources by type with optional short aliases.

## Synopsis

```bash
h registry <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ls` / `list [type]` | List all entries (or entries of a specific type) |
| `types` | List all known resource types |
| `add <type> <name>` | Register a new entry |
| `rm` / `remove <ref> [type]` | Remove an entry |
| `get <ref> [type]` | Print canonical name (scriptable) |
| `show <ref> [type]` | Print human-readable entry detail |
| `select [type]` | Fuzzy-select an entry and print canonical name |
| `set-alias <ref> <alias> [type]` | Update an entry's short alias |

References (`ref`) can be the canonical name or the short alias. `type` is optional when names are unique across types.

### ls / list

List all entries grouped by type, showing short alias and description. Optionally filter to a single type.

**Examples**

```bash
h registry ls
h registry list service
```

### types

Print all known resource types.

**Examples**

```bash
h registry types
```

### add

Register a new entry with type and canonical name. Optionally add a short alias and description.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--alias` | `-a` | Short alias |
| `--desc` | `-d` | Description |

**Examples**

```bash
h registry add service my-rails-app
h registry add service my-rails-app --alias rails --desc "Main Rails API"
h registry add jira IC-12345 --desc "Fix login bug"
```

### rm / remove

Remove an entry by name or alias.

**Examples**

```bash
h registry rm my-rails-app
h registry rm rails service
```

### get

Print the canonical name for a ref. Exits non-zero if not found. Useful for scripting.

**Examples**

```bash
h registry get rails
name=$(h registry get rails service)
```

### show

Print full entry details (type, name, alias, description).

**Examples**

```bash
h registry show rails
h registry show my-rails-app service
```

### select

Fuzzy-select an entry and print its canonical name. Optionally filter to a type.

**Examples**

```bash
h registry select
h registry select service
name=$(h registry select)
```

### set-alias

Update the short alias for an existing entry.

**Examples**

```bash
h registry set-alias my-rails-app rails
h registry set-alias my-rails-app rails service
```
