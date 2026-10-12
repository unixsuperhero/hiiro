# 06. Package the existing MCP implementation

Work ONLY in `/Users/unixsuperhero/proj/rehiiro`. Read [the shared contract](00-start-here.md) and [the MCP proposal](proposal.md#preserve-the-existing-mcp-implementation-and-fix-its-ownership) first. Verify the implemented dependencies below, inspect current source before editing, and execute only step 06. This is a planned packaging cutover, not a new MCP implementation.

## Goal

Make the Hiiro gem own the real catalog, registry, and behavioral tests currently outside the checkout. Preserve their protocols and data. Make external command copies consumers of the packaged implementation through a documented, sandbox-proven cutover without modifying live copies.

## Inputs

- [bin/h-mcp](../../bin/h-mcp), [hiiro.gemspec](../../hiiro.gemspec), [exe/h](../../exe/h), [DB](../../lib/hiiro/db.rb), and [registry records](../../lib/hiiro/registry.rb).
- [README](../../README.md), [CHANGELOG](../../CHANGELOG.md), and the linked proposal.
- External, read-only source candidates: `/Users/unixsuperhero/bin/lib/h_mcp_catalog.rb`, `/Users/unixsuperhero/bin/lib/h_mcp_registry.rb`, `/Users/unixsuperhero/proj/phome/bin/lib/h_mcp_catalog.rb`, and `/Users/unixsuperhero/proj/phome/bin/lib/h_mcp_registry.rb`.
- External behavioral baseline: `/Users/unixsuperhero/proj/phome/scripts/test-h-mcp.rb`.

Either reachable module pair can supply the implementation after comparison. Additional duplicate copies are optional comparison evidence, not permission to edit them. The real modules and behavioral baseline are required inputs; report exact missing sources rather than fabricate replacements. `bin/h-mcp` currently requires adjacent support files that the checkout lacks.

## Dependencies

Requires [01. Data ownership and migration](01-data-ownership-and-migration.md) and [05. Managed installation](05-managed-installation.md). Verify the canonical DB/migration contract and managed supporting-asset provenance. Reuse those implemented contracts, including their current paths, rather than creating another DB or installer.

## Work

1. Compare all reachable module copies before selecting canonical bodies. Record meaningful differences and retained behavior. Trace `MCPCatalog`, `MCPCommands`, and `MCPRegistry`, including command-level constants and registry loading, so moving files does not break their dependencies.
2. Move the actual implementation into gem-owned libraries. Preserve useful existing public names for consumers. Migrate every clone-owned require/caller and remove obsolete clone-owned duplicate bodies after cutover. Update the gemspec to package support files and declare actual SDK/HTTP dependencies compatible with the implementation's `mcp ~> 1.5` requirement.
3. Integrate registry initialization and its once-only JSON import with step 01. Preserve the shared `mcps` rows, discovery metadata, migration marker, recovery JSON, and `mcp-sync` ownership records. Keep exact source path/container/name/directory identity. Missing saved sources must fail, never resolve a same-name server elsewhere.
4. Preserve paginated SDK discovery, stdio and Streamable HTTP transports, tool input/output schemas, annotations, zero-tool catalogs, and previous snapshots after failed discovery. Preserve environment expansion and credential-scope fingerprints. Registration/inventory must not connect or persist credential values; explicit calls remain potentially mutating operations.
5. Preserve HTTP-only legacy export and unsupported-connection rejection. Keep unrelated settings, restrictive backups, symlink-aware atomic replacement, fingerprint-guarded stale pruning, and surgical Codex URL-table editing. Document the actual limits: active same-name exports overwrite entries, and config replacement precedes a separate ownership-record save. Do not describe the pair as transactional or silently change overwrite policy in this packaging step.
6. Bring the existing behavioral tests into the project's maintained test convention. Adapt their paths and isolation to the packaged code. Add only uncovered consumer-visible regressions, especially packaged loading and supported Codex edits versus unsupported shapes.
7. Use step 05's manifest to describe external consumer deployment. Prove sandbox copies can load the canonical gem libraries without adjacent duplicate implementations. Document exact consumer changes for separately authorized deployment; leave live phome/local files untouched. Update guide storage/dependency text, README, and changelog.

## Acceptance criteria

- The built gem runs MCP commands without installed-local support libraries.
- Exact source identity, schema-rich catalogs, credential scoping, shared DB records, and recovery inputs survive packaging.
- Failed discovery retains the previous catalog; failed unsupported exports change neither target config nor ownership.
- Dry-run, stale pruning, same-name overwrite, backups, and sequential ownership behavior are accurately documented and proved.

## Verification

Install a locally built gem into temporary GEM_HOME/HOME with isolated DB/config/data roots. Remove installed-local library paths from resolution. Run actual `list`, `add`, `discover`, `tools`, `tool`, stdin-based `call`, `sync --dry-run`, and explicit sandbox sync/prune against a loopback SDK fixture and harmless stdio fixture. Expect complete schemas, literal JSON values, nonzero tool-error status, preserved catalogs after cursor failure, protected edited stale exports, and preserved unrelated Codex text. Inspect config bytes, backup permissions, DB rows, and loaded library origins. Run the migrated behavioral tests as additional proof.

## Non-goals and safety

No Git worktrees, live credentials, providers, client-config writes, or account mutations. Original and installed-local sources are reference-only. Keep Ruby, existing values, SDK protocols, and native TUI/table design. No replacement protocol stack, universal registry, or invented absent source.

## Completion and handoff

After smoke proof, update only step 06 in [the index](README.md) and commit the complete clone-owned cutover, tests, and docs. Report source differences, canonical loading, preserved data, external deployment boundary, exact observed checks, and commit. Missing required sources/contracts leave the box unchecked. Next is [07](07-safe-commit-planning.md), once step 03's outputs are verified; do not start it automatically.

