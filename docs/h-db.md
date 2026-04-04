# h-db

Inspect and manage the hiiro SQLite database (`~/.config/hiiro/hiiro.db`).

## Synopsis

```bash
h db <subcommand> [args]
```

## Subcommands

| Subcommand | Aliases | Description |
|------------|---------|-------------|
| `status` | — | Show DB connection info, migration state, and table row counts |
| `tables` | — | List all table names |
| `q` | `query` | Query the database |
| `migrate` | — | Archive YAML files and disable dual-write |
| `remigrate` | — | Re-import data from YAML into SQLite |
| `cleanup` | — | Find and generate SQL to remove duplicate rows |
| `restore` | — | Restore YAML files from most recent backup archive |

## Options

### `q` / `query`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--all` | `-a` | Show all rows (no 50-row limit) | false |

### `remigrate`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--only` | — | Comma-separated list of tables to remigrate | all |

## Subcommand Details

### `status`

Show connection info (path, file size), migration state (complete/not run and timestamp), dual-write status, table row counts, and available backup archives.

```bash
h db status
```

### `tables`

List all table names in the database, sorted alphabetically.

```bash
h db tables
```

### `q` / `query`

Query the database in three modes:

1. **Table name only** — show all rows from the table (up to 50 by default)
2. **Table name + `key=value` filters** — filter rows by column value
3. **Raw SQL** — execute a SQL statement directly

```bash
h db q branches
h db q branches task=my-task
h db q "SELECT * FROM branches WHERE name LIKE '%feat%'"
h db q branches -a       # show all rows, no limit
```

### `migrate`

Archive all `~/.config/hiiro/**/*.yml` files to a timestamped `.tar.gz` backup, then disable dual-write mode so hiiro writes only to SQLite. Prompts for confirmation before proceeding.

```bash
h db migrate
```

### `remigrate`

Re-import data from YAML sources into SQLite. Useful if the database becomes out of sync. With `--only`, limit to specific tables.

```bash
h db remigrate
h db remigrate --only todos,branches
```

### `cleanup`

Scan all tables for duplicate rows (using natural unique keys such as `name`, `url`, `number`), generate a SQL file with `DELETE` statements, open it in your editor, and print instructions for applying it. The SQL file is saved to `~/notes/files/`.

```bash
h db cleanup
```

### `restore`

Restore YAML files from the most recent backup archive found in `~/.config/hiiro/`.

```bash
h db restore
```

## Examples

```bash
# Check database health
h db status

# Look up branches for a task
h db q branches task=my-feature

# Run a custom query
h db q "SELECT name, task FROM branches ORDER BY created_at DESC LIMIT 10"

# Find and clean up duplicate rows
h db cleanup

# Re-sync after a data issue
h db remigrate --only branches,prs
```
