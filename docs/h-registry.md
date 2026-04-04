# h-registry

Store and look up named resources by type with optional short aliases.

## Synopsis

```bash
h registry <subcommand> [args]
```

Registry entries are stored in SQLite (`~/.config/hiiro/hiiro.db`, table `registry_entries`). Each entry has a resource type, canonical name, optional short alias, and optional description.

## Subcommands

| Subcommand | Aliases | Description |
|------------|---------|-------------|
| `ls` | `list` | List all registry entries grouped by type |
| `types` | — | List all known resource types |
| `add` | — | Add a new entry |
| `rm` | `remove` | Remove an entry |
| `get` | — | Print canonical name for an entry (scriptable) |
| `show` | — | Print human-readable detail for an entry |
| `select` | — | Fuzzy-select an entry and print its name |
| `set-alias` | — | Update the short alias for an entry |

## Options

### `add`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--alias` | `-a` | Short alias | — |
| `--desc` | `-d` | Description | — |

## Subcommand Details

### `ls` / `list`

List all registry entries grouped by type, with short name and description columns. Optionally filter to a specific type.

```bash
h registry ls
h registry ls service
```

### `types`

List all known resource types in the registry.

```bash
h registry types
```

### `add`

Add a new entry to the registry. Skips silently if the entry already exists.

```bash
h registry add service my-api
h registry add service my-api --alias api --desc "Main API service"
h registry add jira-project PLAT --alias plat
```

### `rm` / `remove`

Remove an entry by name or alias. Optionally scope to a specific type.

```bash
h registry rm api
h registry rm api service
```

### `get`

Print the canonical name for a registry entry. Exits 1 if not found. Useful in scripts.

```bash
h registry get api
name=$(h registry get api service)
```

### `show`

Print human-readable detail for a registry entry.

```bash
h registry show api
h registry show api service
```

### `select`

Fuzzy-select an entry and print its canonical name. Optionally filter by type.

```bash
h registry select
h registry select service
```

### `set-alias`

Update the short alias for an entry.

```bash
h registry set-alias my-api apiv2
h registry set-alias my-api apiv2 service
```

## Examples

```bash
# Track team services
h registry add service payments-api --alias pay --desc "Payments microservice"
h registry add service auth-service --alias auth

# List all services
h registry ls service

# Get canonical name from alias (in scripts)
svc=$(h registry get pay)

# Update an alias
h registry set-alias auth-service oauth service

# Remove a stale entry
h registry rm old-service
```
