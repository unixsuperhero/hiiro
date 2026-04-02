# h-db

Inspect and manage the hiiro SQLite database (`~/.config/hiiro/hiiro.db`).

## Usage

```
h db <subcommand> [args]
```

## Subcommands

### `status`

Show connection info (path, file size), migration state, dual-write status, table row counts, and available backup archives.

### `tables`

List all table names in the database.

### `q` [alias: `query`]

Query the database. Accepts a table name with optional `key=value` filters, or raw SQL.

**Args:** `<table|sql> [key=value...]`

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Show all rows (no 50-row limit) | false |

**Examples:**
```
h db q branches
h db q branches task=my-task
h db q "SELECT * FROM branches WHERE name LIKE '%feat%'"
```

### `migrate`

Archive all YAML files to a timestamped `.tar.gz` and disable dual-write mode. Prompts for confirmation before deleting YAML files.

### `remigrate`

Re-import data from YAML sources into SQLite. Optionally limit to specific tables.

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--only` | — | Comma-separated list of tables to remigrate | all |

### `cleanup`

Scan all tables for duplicate rows (using natural unique keys), generate a SQL file with `DELETE` statements to fix them, open it in your editor, and print instructions for applying it. The SQL file is saved to `~/notes/files/`.

### `restore`

Restore YAML files from the most recent backup archive in `~/.config/hiiro/`.
