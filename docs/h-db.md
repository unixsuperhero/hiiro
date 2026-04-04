# h-db

Inspect and manage the hiiro SQLite database (`~/.config/hiiro/hiiro.db`).

## Synopsis

```bash
h db <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `status` | Show DB path, size, migration state, table counts, and backups |
| `tables` | List all table names |
| `q` / `query <args>` | Run a SQL query or table lookup |
| `migrate` | Archive YAML files and disable dual-write |
| `remigrate [--only tables]` | Re-run YAML import |
| `cleanup` | Generate a SQL file to remove duplicate rows |
| `restore` | Restore YAML files from the latest backup archive |

### status

Show DB file path, size, migration state (complete or not), dual-write status, row counts per table, and any backup archives.

**Examples**

```bash
h db status
```

### tables

List all table names in the database.

**Examples**

```bash
h db tables
```

### q / query

Query the database. Three modes:

- Pass a SQL string starting with SELECT/INSERT/UPDATE/DELETE/WITH to run it directly.
- Pass a table name with optional `key=value` filters to query that table.
- Pass no args to print usage.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Show all rows (default limit: 50) |

**Examples**

```bash
h db q tasks
h db q branches task=my-task
h db q "SELECT name, task FROM branches WHERE task IS NOT NULL"
h db q branches --all
```

### migrate

Complete the YAML-to-SQLite migration:

1. Archives all YAML files in `~/.config/hiiro/` to a `.tar.gz` backup.
2. Deletes the YAML files.
3. Disables dual-write mode.

Prompts for confirmation before proceeding.

**Examples**

```bash
h db migrate
```

### remigrate

Re-run the YAML import into SQLite. Useful if data was added to YAML files after initial migration. With `--only`, limits to specific tables.

**Options**

| Flag | Description |
|------|-------------|
| `--only <tables>` | Comma-separated table names to remigrate |

**Examples**

```bash
h db remigrate
h db remigrate --only todos,tags
```

### cleanup

Scan all tracked tables for duplicate rows (by natural unique keys). Generates a `.sql` file in `~/notes/files/` with `DELETE` statements and opens it in your editor for review. Apply with:

```bash
sqlite3 ~/.config/hiiro/hiiro.db < ~/notes/files/hiiro-cleanup-<timestamp>.sql
```

**Examples**

```bash
h db cleanup
```

### restore

Restore YAML files from the most recent `.tar.gz` backup in `~/.config/hiiro/`.

**Examples**

```bash
h db restore
```
