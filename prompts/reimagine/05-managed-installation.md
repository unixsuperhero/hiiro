# 05. Managed assets and installation provenance

Work ONLY in `/Users/unixsuperhero/proj/rehiiro`. Read [the shared contract](00-start-here.md) and [the proposal](proposal.md#make-one-command-catalog-explain-what-actually-runs) first. Verify the dependency's implemented outputs below, inspect current source before editing, and execute only step 05. This is planned implementation, not evidence that installation has already changed.

## Goal

Replace competing copy/update paths with one managed installer and provenance manifest. Show a read-only drift plan, require explicit apply, and preserve user overrides. Install gems for each compatible Ruby, but install shared commands, plugins, and supporting assets once from a clearly identified source.

## Inputs

- [exe/h](../../exe/h), [exe/hiiro](../../exe/hiiro), and [hiiro.gemspec](../../hiiro.gemspec).
- [script/install](../../script/install), [script/sync](../../script/sync), [script/compare](../../script/compare), [script/publish](../../script/publish), [script/available](../../script/available), and [script/update](../../script/update).
- [Config](../../lib/hiiro/config.rb), [Rbenv](../../lib/hiiro/rbenv.rb), [command documentation](../../docs/h.md), [README](../../README.md), and [CHANGELOG](../../CHANGELOG.md).

Both setup entrypoints copy plugins and immediate `h-*` files. `h update -a` and publishing run setup inside each Ruby's worker. `Config.plugin_files` gives user basenames precedence over gem fallback plugins. These are source findings to reproduce safely, not observed runtime failures.

## Dependencies

Requires [04. Read-only catalog and lazy startup](04-command-catalog-and-lazy-boot.md). Verify one candidate inventory drives dispatch and editing, exposes winning/shadowed paths, and supports read-only discovery. Reuse its implemented contract without prescribing a new Ruby signature. Missing outputs block this step.

## Work

1. Trace every setup, update, comparison, and publish-to-install caller. Identify executable aliases, prefix renaming, modes, symlinks, plugin fallbacks, and supporting files. Inspect the actual gem contents rather than assuming every dependency matches `h-*`.
2. Define one manifest of managed destinations with source/package version, source identity, installed content fingerprint, and relevant mode or link information. Derive command provenance from step 04. Treat pre-existing unowned files as user-owned, even when their bytes match a packaged command, unless the user explicitly adopts them.
3. Implement planning without directory creation or writes. Distinguish missing assets, unchanged assets, safely updatable managed assets, user-modified assets, collisions, and obsolete managed destinations. Never infer permission to overwrite from a basename. Preserve the current native user-plugin precedence.
4. Implement explicit application of selected plan entries. Recheck destination fingerprints before replacement so edits made after planning survive. Record ownership only for successful writes. Make a repeated apply converge without replacing user changes. Retire obsolete assets only when ownership and unchanged content are proven and removal is explicitly selected.
5. Route both setup entrypoints and install/sync/compare scripts through this implementation. Preserve useful comparison/editor operations, but remove duplicate copy algorithms after their callers migrate. Use shell-safe argument arrays and report partial failures accurately.
6. Separate per-Ruby gem installation from the single shared-assets apply phase. Select and report the package version supplying shared assets. Consolidate availability polling and update handoffs in `script/publish`, `script/available`, `script/update`, and `delayed_update`; keep publishing itself an explicit operation. Do not add another background updater.
7. Add deterministic preservation regressions and update installation docs/changelog with provenance, adoption, drift review, and failure behavior.

## Acceptance criteria

- Dispatch/edit provenance identifies the installed winner and its package or user origin.
- Planning leaves HOME, manifests, files, and plugin directories unchanged.
- Applying an owned update preserves unrelated files, modified overrides, and edits made after planning.
- Compatible Ruby versions receive their gem independently; shared assets have one application phase and one reported source.
- Supporting assets ship with their consumers, and failed writes never appear successfully owned.

## Verification

Use a temporary HOME, isolated DB/config/data roots, and sandbox bin/plugin destinations. Run the actual plan/apply CLI on missing, owned-unchanged, modified, unowned-collision, and obsolete fixtures. Expect modified/unowned files to remain byte-identical, selected owned files to update, and a second plan to show no remaining selected drift. Exercise both setup names and the multi-Ruby orchestration with controlled RubyGems/rbenv adapters. Inspect destination bytes, modes, provenance, and exit statuses. Never run a real publish or install into live directories.

## Non-goals and safety

No Git worktrees. The original repository and installed local files are reference-only. No live account mutations, live `~/bin` or plugin writes, publishing, or automatic override adoption. Keep Ruby, existing values, native plugin behavior, and the current in-process TUI design. Do not introduce a universal installation/workflow engine. MCP source ownership belongs to step 06.

## Completion and handoff

After smoke proof, remove throwaway fixtures, update only step 05's checkbox in [the index](README.md), and commit the complete step in the clone. Report the installer interface, migrated callers, preserved overrides, retired paths, exact commands/outcomes, and commit. If blocked, leave the checkbox unchecked and name the missing prerequisite. The next eligible step is [06](06-mcp-package-ownership.md) after its dependencies are verified; do not start it automatically.

