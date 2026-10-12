# 04. Read-only catalog and lazy command startup

Work ONLY in `/Users/unixsuperhero/proj/rehiiro`. Read [the shared contract](00-start-here.md), [the catalog proposal](proposal.md#make-one-command-catalog-explain-what-actually-runs), [the framework proposal](proposal.md#separate-the-framework-from-the-workstation-application), and [the index](README.md) first. Verify the dependencies below, then execute only step 04. This is planned implementation work. Inspect current source, including newer Table/Tui contracts, before editing.

## Goal

Use one derived command catalog for resolution and command information. Make framework import, help, and discovery read-only and independent of workstation database initialization, migration, invocation tracking, and task auto-tagging.

## Inputs

- Framework: [lib/hiiro.rb](../../lib/hiiro.rb), [Bins](../../lib/hiiro/bins.rb), [Options/OptionSet](../../lib/hiiro/options.rb), [Matcher](../../lib/hiiro/matcher.rb), [Config](../../lib/hiiro/config.rb), and [Invocation](../../lib/hiiro/invocation.rb).
- Entry points/consumers: [exe/h](../../exe/h), [exe/hiiro](../../exe/hiiro), [h-bin](../../bin/h-bin), [h-plugin](../../bin/h-plugin), [h-config](../../bin/h-config), and [h-registry](../../bin/h-registry).
- Current table/runtime contracts: [RegistryEntry](../../lib/hiiro/registry.rb), [Table](../../lib/hiiro/table.rb), [TableScope](../../lib/hiiro/table_scope.rb), [TableActions](../../lib/hiiro/table_actions.rb), [Tui](../../lib/hiiro/tui.rb), and [AGENTS.md](../../AGENTS.md). Discover any current table entrypoints rather than treating unchecked TUI-plan items as implemented commands.
- Tests/docs: `test/hiiro_test.rb`, `test/hiiro/bins_test.rb`, `test/hiiro/require_paths_test.rb`, `test/hiiro/option_set_test.rb`, `test/hiiro/table_test.rb`, [root docs](../../docs/h.md), [bin docs](../../docs/h-bin.md), and [plugin docs](../../docs/h-plugin.md).
- Optional external sources: installed PATH directories may supply reference-only collision examples. Do not execute unknown scripts or inspect private credentials.

## Dependencies

Verify [01](01-data-ownership-and-migration.md)'s canonical persistence/import contract and [02](02-command-context.md)'s resolved-context contract. Require working outputs and evidence, not checkboxes. Step 03 is not a dependency; do not couple this step to its APIs.

## Work

1. Trace registration, discovery, exact/prefix resolution, help, source editing, and runtime startup. Compare Runners' unfiltered glob with Bins' executable checks and captured PATH. Find every caller, including editor selection, nested mounts, plugins, and current resource/table commands.
2. Define executable eligibility and ordering explicitly: executable regular files or valid file symlinks, not executable directories, nonexecutables, or broken links. Respect PATH order, duplicates, relative/empty entries, and later environment changes. Document inline-versus-external collisions, canonical names, aliases, exact precedence, unique-prefix ambiguity, and parent/child names. Preserve useful existing spellings. Keep losing paths visible as shadowed candidates without making same-name PATH copies falsely ambiguous.
3. Build the catalog from executable candidates and existing add_cmd/add_subcmd/OptionSet metadata. Capture alias relationships and source locations during registration. Unknown external grammar remains unknown. Discovery must never execute arbitrary programs to obtain metadata. Use one selection policy for dispatch, help, searchable command selection, edit targets, completion, and generated command documentation. Complete these consumers rather than adding an unused inventory class.
4. Separate framework loading and registration from runtime activation. Remove eager DB connection/model loading from framework import and remove unconditional setup/history work from Hiiro.init. Make Config plugin enumeration read-only instead of creating directories. Keep registration safe during help, and do not execute arbitrary user-plugin initialization merely to discover commands. Provide an explicit runtime load path for selected domain operations and intentional runtime plugins.
5. Activate persistence, context, invocation tracking, and task auto-tagging only when the selected operation requires runtime. Preserve one root invocation and nested/external resolution tracking across process boundaries. Handle help before domain setup, including add_cmd option-help wrappers and passthrough task commands. Update every bin that previously depended on eager constants, especially `t`/`tt`, registry/table commands, and root/app builders.
6. Keep the command catalog separate from SQL RegistryEntry/Table saved data. Actual table queries, tags, scopes, and TableActions still activate runtime; their help must not. Reuse the existing Tui engine for screens and preserve query, focus, scroll, and selection during refresh. Do not create a competing resource registry or picker engine.
7. Migrate scanner/help/edit/completion/documentation callers, then remove obsolete scanners and eager-boot paths. Update README, command docs, CHANGELOG, and test bootstrap assumptions. Expose catalog data for step 05 without implementing installation/provenance management here.

## Acceptance criteria

- Dispatch, help, edit, completion, and generated docs agree on winners, aliases, and ambiguity.
- Framework import/help/discovery create no DB, migration marker, history, tags, or config/plugin directories.
- Runtime commands retain domain behavior and root tracking; generic table data stays distinct from catalog data.

## Verification

Run scoped catalog/options/require/runtime regressions. Use fresh subprocesses because the existing test helper preloads Hiiro and initializes SQLite. With isolated HOME/config/data and a disposable Git repository, smoke framework import, root help, nested help, discovery, completion, and documentation generation. Compare filesystem and database state before/after; legacy YAML must remain untouched. Build two temporary PATH directories with same-name harmless executables, aliases, invalid candidates, and a sentinel script that records execution. Discovery leaves the sentinel absent; dispatch runs only the declared winner; edit selects that same source; ambiguous prefixes launch nothing. Finally execute a real sandbox task/resource/table operation and inspect persisted data plus one root invocation with its resolutions. Exercise changed command selection interactively if present.

## Non-goals and safety

No Git worktrees, live account mutations, arbitrary executable introspection, automatic installation, installed-file edits, new language/framework, or universal registry. Original repo and installed local files are reference-only. Screens use Hiiro::Tui::Screen/State/Pane, never curses or an external fuzzy finder.

## Completion and handoff

After smoke proof, update only step 04 in [the index](README.md), then commit the complete step in the clone. Report catalog/runtime interfaces, migrated consumers, removed paths, exact checks/outcomes, and commit. Missing prerequisites leave the box unchecked. Next eligible step: [05](05-managed-installation.md).

