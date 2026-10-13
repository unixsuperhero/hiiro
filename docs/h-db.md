# h-db

Inspect and manage the hiiro SQLite database at `~/.config/hiiro/hiiro.db`. Startup creates or upgrades schemas; it does not import legacy domain YAML.

## Synopsis

```bash
h db <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `status` | Show database authority, selected-import verification, table counts, and accepted retained sources |
| `tables` | List all table names |
| `q` / `query <args>` | Run a SQL query or table lookup |
| `manifest` | List durable owners, identities, legacy sources, and export-only records |
| `plan [--only=STORES] [--sources=PATHS]` | Inspect selected sources, checksums, rows, conflicts, and errors without importing records |
| `migrate [--only=STORES] [--sources=PATHS]` | Import selected owned sources and retain their original bytes |
| `export NEW.json` | Create a typed canonical-record export without overwriting a destination |
| `restore EXPORT.json` | Recover absent or identical records; abort on conflicting IDs or identities |
| `cleanup` | Generate a SQL file to remove duplicate rows |

### manifest

The manifest identifies the database owner and identity for each durable domain type. Legacy import stores are `todos`, `links`, `branches`, `prs`, `pinned_prs`, `tasks`, `assignments`, `apps`, `projects`, `pane_homes`, `pins`, `reminders`, and `tags`.

Task resources, generic registry entries, check snapshots, capture metadata, and MCP registrations (`mcps`, identified by name; see [h-mcp](h-mcp.md)) are canonical database records included in export/recovery, not separate legacy YAML import stores. `h mcp` imports its legacy JSON catalogs once by itself; they are not `plan`/`migrate` stores. Registry entries keep stable IDs, aliases, values, metadata, nullable `task_id`, and tags. Their `Table` and `TableScope` behavior is unchanged.

Definitions, preferences, runtime files, prompts, task note bodies, capture bodies, and other ordinary artifacts remain file-owned. They are not domain migration or export targets. Invocation and resolution audit history remain in the original database and are excluded from canonical exports.

```bash
h db manifest
```

### plan and migrate

Both commands accept the same selectors:

| Option | Selection |
|--------|-----------|
| `--only=STORES` | Comma-separated legacy store names from the manifest, not arbitrary SQL tables |
| `--sources=PATHS` | Comma-separated exact owned source paths, relative to the config root or absolute |

Without selectors, the plan includes discoverable original owned sources. Backup variants ending in `.bak` require explicit `--sources` selection. Extensionless command-pin files and their actual `.yml` variants share one logical source identity. Conflicting variants are rejected, not silently preferred.

The retained legacy SQLite `pinned_prs` table is an import input when present and nonempty. Its exact selector is `sqlite:pinned_prs`. The canonical PR owner is `Hiiro::PinnedPr` in `prs`, with qualified `repo/number` identity.

Selecting `tags` also includes its task, link, branch, and PR import dependencies. An exact source selector still limits selected paths; referenced owners must exist or be included.

`plan` reports selected sources, checksums, row counts, validation errors, and canonical conflicts without importing records. Its `available_sources` inventory also lists retained backup inputs without selecting them. Normal startup schema initialization still occurs. `migrate` rechecks source checksums and applies the selected import transactionally. Invalid rows, unresolved relationships, changed accepted sources, and ID or natural-identity conflicts reject the import before commit. Source files remain unchanged.

Uncommitted new imports appear as `ready` in the plan report, or `rolled-back` when another selected source rejects the batch. Only a successful import reports `verified`.

After commit, migration checks persisted rows and accepted-source mappings through a fresh database connection before recording completion. If that reload check fails, the command reports a committed-but-unverified failure. Accepted rows and their ledger remain committed, and retained sources remain recoverable; completion for the new import is not recorded. Repeating the unchanged source verifies the current canonical rows without replaying the old snapshot, then records completion after successful verification.

Accepted imports record source checksums and row mappings. Repeating an unchanged accepted source reports `previously-applied`, including the number of later canonical changes or deletions. It does not replay the snapshot over those changes or recreate deleted rows. A changed previously accepted source is rejected rather than overwriting newer records.

Import preserves explicit IDs, task metadata and resources, tag identities, qualified PR records, typed pin values, and reminder scheduling fields. Legacy unmarked pins retain their historical decoder until an explicit typed source resolves their ambiguity; migration does not guess types from JSON-looking strings. Selecting `pins`, including the default all-store selection, rejects ambiguous legacy values without a reliable typed source and reports their command/key. Selecting another store does not rewrite unrelated legacy pins.

Verification and completion describe the selected import, not every discoverable legacy store. Definitions such as `services.yml`, `tools.yml`, `sparse_groups.yml`, `tables.yml`, `config.yml`, and `app_files.yml` remain untouched. Migration neither archives nor deletes YAML and does not prompt to retire files.

```bash
h db plan
h db plan --only=todos,pins
h db migrate --only=todos,pins
h db plan --only=todos --sources=todo.yml.bak
h db migrate --only=todos --sources=todo.yml.bak
h db plan --only=pinned_prs --sources=sqlite:pinned_prs
```

### export

`export` requires one new destination path in an existing directory. It uses exclusive creation and refuses an existing file or symlink.

The checksummed JSON document contains typed domain rows, IDs, relationships, tags, task resources, RegistryEntry metadata (including `mcp-sync` ownership), MCP registrations and saved catalogs, PR/check snapshots, capture metadata, import verification records, and domain allocator state. Retained legacy PR rows and extra PR columns are included. Definitions, preferences, ordinary files, and invocation/resolution audit history are not included.

```bash
h db export ~/backups/hiiro-records.json
```

### restore

`restore` requires one canonical JSON export, not a YAML file or tar archive. It validates the export checksum, format, rows, and relationships, then merges transactionally.

- An identical existing row is retained.
- An absent exported row is inserted with its original ID.
- A conflicting existing ID or natural identity aborts the whole recovery.
- Rows added after export are not deleted. Allocators do not move backward.

Recovery does not overwrite later writes, including conflicting import-ledger records. An explicit restore can recreate exported rows deleted after export because those IDs are absent. Restore is therefore not a chronological rollback and does not preserve later deletions in the way repeated migration does. No YAML or export source is overwritten.

```bash
h db restore ~/backups/hiiro-records.json
```

### status

Show database path and size, database authority, table counts, accepted retained-source count, and whether selected imports have been verified. A successful partial selection is not proof that all discoverable legacy stores have been imported.

```bash
h db status
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

### cleanup

Scan all tracked tables for duplicate rows (by natural unique keys). Generates a `.sql` file in `~/notes/files/` with `DELETE` statements and opens it in your editor for review. Apply with:

```bash
sqlite3 ~/.config/hiiro/hiiro.db < ~/notes/files/hiiro-cleanup-<timestamp>.sql
```

The generated SQL is an ordinary review artifact, not a canonical export.

**Examples**

```bash
h db cleanup
```

### tables

List all table names in the database.

**Examples**

```bash
h db tables
```
