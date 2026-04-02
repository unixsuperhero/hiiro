# h-registry

Store and look up named resources by type with optional short aliases.

## Usage

```
h registry <subcommand> [args]
```

## Subcommands

### `ls` [alias: `list`]

List all registry entries grouped by type, with short name and description columns.

**Args:** `[type]`

### `types`

List all known resource types in the registry.

### `add`

Add a new entry to the registry.

**Args:** `<type> <name>`

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--alias` | `-a` | Short alias | — |
| `--desc` | `-d` | Description | — |

### `rm` [alias: `remove`]

Remove an entry by name or alias, optionally scoped to a type.

**Args:** `<name_or_alias> [type]`

### `get`

Print the canonical name for a registry entry (scriptable; exits 1 if not found).

**Args:** `<name_or_alias> [type]`

### `show`

Print human-readable detail for a registry entry.

**Args:** `<name_or_alias> [type]`

### `select`

Fuzzy-select an entry and print its canonical name.

**Args:** `[type]`

### `set-alias`

Update the short alias for an entry.

**Args:** `<name_or_alias> <new_alias> [type]`
