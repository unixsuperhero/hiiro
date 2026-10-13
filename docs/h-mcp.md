# h-mcp local registry and direct calls

`h mcp` stores local MCP registrations and discovered tool schemas in Hiiro's main SQLite database. Discovery and calls use the official Ruby MCP SDK, not an AI model.

There are no default servers or automatic registrations. There is no HTTP registry service, registry UI, `--endpoint` option, or AI fallback for unknown sync targets. Example server names, URLs, and tools below are illustrative.

## Register and remove servers

```sh
h mcp list
h mcp ls
h mcp list --json
h mcp info SERVER
h mcp add SERVER --url http://localhost:8000/mcp
h mcp add SERVER --config /path/to/mcp.json
h mcp add SERVER --agent codex
h mcp import --config /path/to/mcp.json
h mcp import --agent codex
h mcp import
h mcp remove SERVER
```

`list` includes disabled and undiscovered registrations. Its table shows the name, transport, enabled state, tool count, and safe address. `list --json` and `info` return public records without connecting or resolving credentials.

`add` requires an explicit URL, config, or agent. Config and agent selections require the exact configured name, not an alias. Registration does not connect or load credential values. A registered server can be called before discovery.

`import` registers the selected inventory without connecting. Without selection flags, it reads all supported current client configurations. Duplicate names fail before any registration is written. Import is atomic. Select one config or agent to disambiguate duplicates.

Registering the same source identity preserves its saved catalog and scoped header-variable reference. Changing its source, transport, URL, or executable invalidates the old catalog and credential scope. `remove` deletes the registration and catalog, not the source configuration. Missing names are errors.

## Configured inventory and live sources

```sh
h mcp configured
h mcp configured --json
h mcp configured --agent codex
h mcp configured --config /path/to/mcp.json
h mcp agents
```

`configured` reads client inventory without registering or connecting. Codex inventory uses `codex mcp list --json`, including effective plugin servers. Explicit JSON configs accept `mcpServers`, `servers`, or `mcp` containers. `agents` lists known targets and config paths.

A registration retains the exact config path, container, server name, and workspace, or the Codex name and captured working directory. Connection commands resolve that source again, so updated settings and credentials take effect without copying them into SQLite. Missing references fail rather than selecting a same-named server elsewhere.

Resolution uses an explicit `--url` first, then an explicitly selected `--config` or `--agent`. Otherwise, the name must be registered locally. An unregistered name never triggers a search of other client configs.

Disabled entries remain visible. Bulk discovery skips them. Individual discovery, connection tests, and calls reject a disabled source. Editing a source config does not refresh its saved schemas.

## Discover and inspect schemas

```sh
h mcp discover SERVER
h mcp discover SERVER --config /path/to/mcp.json
h mcp discover SERVER --agent codex
h mcp discover SERVER --url http://localhost:8000/mcp
h mcp discover --all
h mcp discover --all --agent codex
h mcp discover --all --config /path/to/mcp.json --json
h mcp saved --json
h mcp tools SERVER
h mcp tools SERVER --json
h mcp tool SERVER TOOL
h mcp tool SERVER TOOL --json
h mcp guide
```

Discovery initializes the connection and retrieves every page of `tools/list`, without invoking tools. Success registers the source and atomically replaces its snapshot. Failure preserves the previous snapshot. A zero-tool response still creates a saved catalog.

Snapshots contain the discovery time, initialization metadata, tool descriptions, input and output JSON schemas, and annotations. `saved`, `tools`, and `tool` read SQLite only. They remain available offline even when the source config or credentials are unavailable. An undiscovered registration has no catalog.

`discover --all` uses enabled local registrations unless a config or agent is selected. Each server resolves independently. The batch continues after failures and exits nonzero if any server failed. Batch JSON is `{ "servers": [...], "errors": [...] }`. Duplicate names in selected inventory require a narrower source selection.

## SQLite storage and legacy migration

The database is `~/.config/hiiro/hiiro.db`. MCP storage uses the existing `Hiiro::DB.connection`; `Hiiro::DB.setup!` creates the `mcps` table with the other schemas. There is no separate MCP database. Inspect records with the existing database command:

```sh
h db q mcps
```

```sql
CREATE TABLE mcps (
	name TEXT PRIMARY KEY,
	record_json TEXT NOT NULL,
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL
);
```

`record_json` holds the public registration and current discovered snapshot, not a version history. Local JSON output also includes the row's creation and update timestamps. Updates preserve the creation timestamp. Before discovery, `discovered_at`, `initialize`, and `tools` are absent.

Records retain safe URL or executable metadata and environment or header names. Private resolved `connection` settings, imported command arguments, and credential values are not stored in `mcps`. This does not guarantee that the whole mainDB is secret-free. Hiiro's separate invocation log can contain CLI arguments.

On first use, legacy catalogs from `~/.local/share/hiiro/mcp` migrate in one transaction. All files are read and validated before import. Malformed records or duplicate logical names abort without partial records or a migration marker. Existing SQLite registrations take precedence. Migration does not connect or load source credentials.

Migration preserves saved tools, initialization data, source references, scoped header-variable metadata, and other public metadata. Historical `registry` sources use their saved server URL directly, without fetching a registry service. Their original references and scopes remain intact.

Success records `mcp_json_catalogs_to_sqlite` in `schema_migrations`, including when the directory is empty. Original JSON files remain as backups and are not read or written again. Removing a SQLite registration cannot resurrect it from those files. `H_MCP_CATALOG_DIR` is no longer active storage.

`h db manifest` lists `mcps` (owner `MCPRegistry`, identity `name`). `h db export` includes its rows, and `h db restore` merges them by name like other canonical records: an absent registration is inserted, an identical one is kept, and a conflicting one aborts the restore. Sync ownership rows are ordinary `registry` rows and travel with them.

## Call a tool and test a connection

```sh
h mcp add slack --config /path/to/mcp.json
h mcp discover slack
h mcp tools slack
h mcp tool slack search_messages
h mcp call slack search_messages --args '{"query":"in:engineering deployment"}'
printf '%s\n' '{"query":"in:engineering deployment"}' |
	h mcp call slack search_messages --args-file - --data
h mcp test slack
h mcp url slack
```

Use the actual tool name and input schema shown by `tool`. Calls can mutate external data. They do not choose tools, interpret natural language, or invoke additional tools.

Arguments must be a JSON object. `--args-file FILE` reads a file, and `--args-file -` reads stdin. For sensitive payloads, avoid inline `--args`: shell history and Hiiro's invocation log can retain argv. Stdin payloads are not added to the command's argument list.

`call` prints the complete MCP result as JSON without the JSON-RPC envelope. `--data` selects `structuredContent` when present, otherwise parses exactly one text block as JSON. Plain prose, multiple blocks, and mixed content fail extraction. Omit `--data` to inspect the full result.

A tool result with `isError: true` prints the complete error result and exits `1`, even with `--data`. Transport, protocol, config, and parsing failures also exit nonzero. Diagnostics and progress go to stderr, not JSON stdout.

Tool-list pagination is automatic. Pagination within a tool result is tool-specific and belongs in the caller or wrapper. `test` performs initialization without calling tools. `url` prints the resolved HTTP URL and fails for stdio servers. These commands share discovery's source-resolution rules.

## Authentication and connection transports

Connections support stdio and Streamable HTTP. Legacy HTTP+SSE-only endpoints require an upgrade or a Streamable HTTP proxy. They are not silently treated as Streamable HTTP.

HTTP configuration accepts `headers`, `http_headers`, `env_http_headers`, and `bearer_token_env_var`. Connections resolve credentials from the current source and environment. Authentication is not borrowed from another application's login. OAuth-only servers require an authorized proxy or supported credential configuration.

For an explicit URL, `--headers-env` names an environment variable containing a JSON object of string headers, not the header JSON itself.

```sh
# Load MCP_HEADERS through your shell or existing secrets loader.
# Its value is a JSON object, such as {"Authorization":"Bearer ..."}.
h mcp add slack --url http://localhost:8000/mcp --headers-env MCP_HEADERS
h mcp discover slack
h mcp call slack search_messages --args-file -
```

On `add`, `--headers-env` requires `--url`. Registration saves the variable name and credential scope without reading its value. Explicit URL discovery can also select `--headers-env`. Connections use the variable's current value only for the same source and destination. A changed destination does not inherit the old reference.

Never put credentials in CLI URLs or inline arguments, even if validation rejects them. Hiiro can log argv before validation. URLs with user credentials or query parameters must be referenced through `--config`, not explicit URL registration. Public records expose safe addresses.

Stdio configs accept `command`, `args`, `env`, and `cwd`, including OpenCode command arrays and `environment`. Connections retain the captured workspace. Relative `cwd` uses the config directory for explicit JSON configs, or the captured workspace for known VS Code and OpenCode formats.

String references support `${VAR}`, `${env:VAR}`, `{env:VAR}`, `${VAR:-default}`, and `${workspaceFolder}`. Interactive client-only inputs require literal values or environment references. Numeric stdio environment values become strings, and null removes a variable.

Stdio connections use a `/bin/sh` wrapper to change directories and execute the command with separate arguments. This is connection behavior, not stdio export support. `--timeout SECONDS` changes the default 30-second request timeout.

## Sync HTTP registrations to a client

Sync retains the legacy HTTP-URL-only scope. It resolves enabled local registrations without connecting. Stdio export is unsupported and fails before writing the target config.

```sh
h mcp agents
h mcp sync omp --dry-run
h mcp sync omp
h mcp sync omp --profile work
h mcp sync cursor --project
h mcp sync codex --prune
h mcp status
```

Targets are `omp`, `codex`, `claude`, `cursor`, `vscode`, `gemini`, `windsurf`, and `opencode`. Unknown targets fail without a model fallback. VS Code uses its project config.

Sync accepts `--project` or `-P`, `--profile NAME` for OMP, `--dry-run` or `-n`, and `--prune` or `-p`. Project paths are under the current working directory. `agents` shows known user config paths.

JSON targets retain their existing URL field formats and export resolved HTTP headers in `headers`. This includes values resolved from source header fields, bearer-token environment variables, and scoped header-variable references. Sync can copy active credentials into the target. Dry-run output can reveal them too. Review that output privately.

Codex sync edits supported `mcp_servers` URL blocks in place rather than reserializing the TOML file. HTTP header authentication and unsupported update shapes fail before writing instead of losing settings. It does not export stdio commands or add a general TOML conversion framework.

Sync preserves unrelated config settings and server entries. Dry-run writes neither the target config nor ownership metadata. Status compares supported URL and header definitions, not just server names, without initializing connections or calling tools.

Prune removes a stale entry only when this command previously synced it and its current definition matches the saved export fingerprint. User-modified and unrelated entries remain. Without prune, stale ownership remains available for a later prune.

Known limits, unchanged by packaging:

- An active registration replaces a target entry with the same name, including a hand-written one, and records it as exported. Rename one side to keep both.
- Sync replaces the config file first and saves ownership afterwards in a separate database write. They are not one transaction. If the ownership save fails, the new config stays and the previous ownership record remains, so entries that save would have recorded are not pruned later.
- Replacing an existing file first copies it to `PATH.bak-YYYYmmddHHMMSSffffff` (mode 0600) beside the selected path. Every write adds one backup; none are removed. A symlinked config keeps its link and the link target is replaced atomically through a temporary file in the target directory.
- A rejected export (stdio, SSE, a Codex server needing headers, or an unsupported Codex shape) fails before writing, so the config, backups, and ownership are unchanged. Dry-run writes none of them.

Ownership uses the existing generic `registry` table with `resource_type='mcp-sync'` and the absolute target config path as `name`. `meta_json` maps server names to SHA256 export fingerprints, not plaintext credentials. Other registry namespaces are untouched.

## Deterministic wrappers

A shell wrapper can forward a tool-specific JSON object from stdin:

```sh
#!/bin/sh
exec h-mcp call slack search_messages --args-file - --data
```

A Ruby wrapper can construct JSON without shell interpolation:

```ruby
#!/usr/bin/env ruby
require 'json'
require 'open3'
query = ARGV.join(' ')
abort 'usage: h-slack-search QUERY' if query.empty?
stdout, stderr, status = Open3.capture3(
	'h-mcp', 'call', 'slack', 'search_messages', '--args-file', '-', '--data',
	stdin_data: JSON.generate(query: query)
)
abort(stderr.empty? ? stdout : stderr) unless status.success?
puts JSON.pretty_generate(JSON.parse(stdout))
```

Replace the server, tool, and argument fields with the saved schema. Tool-specific filtering, pagination, deduplication, and storage belong in the wrapper. The Ruby wrapper's own inline query can still enter shell history or invocation logs.

Subcommands use the existing `add_subcmd` convention. Domain wrappers remain separate from MCP transport code.

## Package layout and installed copies

The hiiro gem owns the implementation. `require 'hiiro/mcp'` loads `MCPRegistry` (`lib/hiiro/mcp/registry.rb`: `mcps` rows, the once-only JSON import, and sync ownership), `MCPCatalog` and `MCPCommands` (`lib/hiiro/mcp/catalog.rb`: source resolution, SDK connections, discovery, calls), and `MCPSync` (`lib/hiiro/mcp/sync.rb`: client targets, `sync`, `status`, `agents`). `bin/h-mcp` only registers subcommands over them. It has no adjacent support files, so `h setup` installs `h-mcp` alone.

Copies of `h-mcp` that `require_relative 'lib/h_mcp_catalog'` predate packaging and carry their own catalog and registry bodies. To make such a copy a consumer of the gem (each step needs the owner's separate approval):

1. Replace the copy with the packaged `bin/h-mcp`, or delete it so `h-mcp` from `h setup` is used. For `~/bin/h-mcp`, `h setup` reports it as a `collision`; `h setup --adopt h-mcp` then `h setup --apply` replaces it and records ownership.
2. Delete the adjacent `lib/h_mcp_catalog.rb` and `lib/h_mcp_registry.rb`; nothing loads them afterwards.
3. Replace any copy of this guide (`h-mcp.md`) with a link to this file, and run the gem's `test/bin/mcp_test.rb` instead of a standalone `test-h-mcp.rb`.

The database rows, migration marker, legacy JSON backups, and sync ownership do not change in this cutover.

## Dependencies and verification

Hiiro supplies the existing Sequel SQLite connection. The gem depends on `mcp` (`~> 1.5`), `faraday`, and `event_stream_parser`; the MCP SDK loads the last two for Streamable HTTP and SSE responses without declaring them.

```sh
ruby -Ilib -Itest test/bin/mcp_test.rb
```

Tests use local protocol fixtures, not Slack or an AI model. A local check does not establish that a remote server is running or authenticated.

Runtime tests set `HIIRO_TEST_DB` to an isolated SQLite file per case before loading Hiiro. Subprocesses share that file, not `sqlite::memory:`, which creates a separate database per process. With `HIIRO_TEST_DB` set, automatic migration does not read production legacy catalogs. Migration tests select an isolated `legacy_dir` explicitly. Subprocesses run with `PATH` limited to a directory holding only `ruby` plus `/usr/bin:/bin`, so inventory never runs a real `codex` and no real client starts. The stdio fixture is a small Ruby JSON-RPC server written by the test.
