# 15. Complete legacy cutovers and product scope

Work ONLY in `/Users/unixsuperhero/proj/rehiiro`. Read [the shared contract](00-start-here.md), [the proposal](proposal.md), and applicable project instructions first. Verify the implemented dependency outputs below, then execute only this planned step. Inspect current source before edits; historical inventory is not the current product inventory.

## Goal

Finish proven legacy cutovers and state the product's actual capabilities. Remove superseded implementations without deleting unmatched behavior, recovery data, personal integrations, or current table/screen functionality.

## Inputs

- Legacy task ownership: `lib/hiiro/tasks.rb`, `lib/hiiro/task_cli.rb`, `exe/hiiro`, `bin/h-otask`, `bin/h-osubtask`, `bin/h-zosubtask`.
- Classification candidates: `bin/h-.config`, `bin/h-dsstore`, `bin/h-demo`, `bin/h-tags`, `bin/h-uri`.
- Native/integration boundaries: `bin/h-session`, `bin/h-buffer`, `bin/h-jumplist`, `bin/h-title`, `bin/h-bg`, `bin/h-notify`, `bin/h-dotenv`, `bin/h-sign`.
- Current tables: `bin/h-registry`, `lib/hiiro/registry.rb`, `lib/hiiro/table.rb`, `lib/hiiro/table_scope.rb`, `lib/hiiro/table_actions.rb`, `lib/hiiro/tui.rb`. Inspect any now-present table commands too. Read [AGENTS.md](../../AGENTS.md) and [the TUI plan](../../docs/plans/hiiro-tui.md).
- Packaging/callers: `hiiro.gemspec`, `script/install`, `script/update`, `script/sync`, `plugins/`, `examples/`, `test/bin/`, and `test/hiiro/`.
- [README](../../README.md), [command docs](../../docs/README.md), [task reference](../../docs/t.md), and [CHANGELOG](../../CHANGELOG.md).
- Optional read-only external comparisons: `/Users/unixsuperhero/bin/h-tts`, `/Users/unixsuperhero/bin/h-skill`, `/Users/unixsuperhero/bin/h-t3redo`. These are evidence, not permission to modify installed originals or invoke providers.

## Dependencies

Require outputs from [01](01-data-ownership-and-migration.md), [02](02-command-context.md), [03](03-owned-execution.md), [04](04-command-catalog-and-lazy-boot.md), [05](05-managed-installation.md), [06](06-mcp-package-ownership.md), [07](07-safe-commit-planning.md), [08](08-pr-snapshots.md), [09](09-pr-actions-and-monitoring.md), [10](10-validation-recipes.md), [11](11-clipboard-artifacts-and-context.md), [12](12-recurring-job-outcomes.md), [13](13-editable-fuzzy-picker-pruning.md), and [14](14-utility-and-profile-consolidation.md). Check concrete contracts, caller cutovers, preservation evidence, and smoke outcomes, not only checkboxes. Missing prerequisites block this step.

## Work

1. Build a source-grounded disposition map of entrypoints, aliases/symlinks, requires, registrations, plugins, installation assets, shell glue, tests, and docs. Use the implemented catalog to inspect controlled external override compatibility. Classify each candidate as maintained native wrapper, personal adapter, example/diagnostic, unfinished capability, or superseded legacy code. Record retained behavior and the replacement evidence for each deletion.
2. Compare `otask`, `osubtask`, and `zosubtask` actions with the completed TaskCli/data/context/execution contracts. Migrate remaining legitimate callers before removal. Do not delete all of `tasks.rb`: current TaskCli uses `TaskManager` tree operations and configuration, and `Environment` has other consumers. Preserve still-used responsibilities, existing tree references, and unmatched legacy import/recovery material under step 01's ownership rules.
3. Retain one canonical implementation for intentional aliases. Remove obsolete registration trees, writers, loaders, re-exports, comments, tests, and assets only after their consumers switch. Finish residual root setup/install duplication using step 05, without introducing another installer or silently replacing external overrides.
4. Preserve current `Table`, `RegistryEntry.task_id`, tags, `TableScope`, and `TableActions` semantics and their actual command consumers. Keep the in-process `Tui::Screen/State/Pane` engine and one state object. Do not implement unchecked future table-plan PRs or impose a new registry/storage model during cleanup.
5. Evaluate empty `dsstore`, non-acting `.config`, debugger-oriented tags commands, the URI recipe printer, and demo distribution individually. Use step 14's real decoder where replacement is justified. Keep useful demonstrations in `examples/`, outside production dispatch/install inventory. Empty TTS handlers and unfinished skill/rebuild experiments must not appear as working capabilities; do not invent provider implementations.
6. Preserve Herdr session/title/background/notification behavior and native agent history. Treat tmux buffer/jumplist integration as optional if its implementation remains available. Do not delete it merely because Herdr is preferred, or promise support when prerequisites are absent.
7. Correct misleading descriptions. `dotenv copy_to` reports differences without copying; `sign` inspects/verifies signatures, not signing. Document deliberate aliases and non-mutating behavior rather than adding unexpected writes. Correct stale task launcher/symlink and backend claims from actual current source.
8. Update README, command docs, examples, packaging inventory, and changelog. Add deterministic regression tests only for uncertain behavior, data preservation, or command transitions. Delete implementation/wording tests made obsolete by the cutover instead of re-pinning them.

## Acceptance criteria

- Every removal has replacement/reachability evidence; retained exceptions have an explicit reason.
- All affected callers and assets use completed contracts, with no parallel superseded implementation.
- Useful TaskManager/configuration behavior, unmatched data, optional integrations, and current table behavior survive.
- Discovery, installation, and documentation distinguish real capabilities from experiments and examples.

## Verification

Run scoped behavioral tests. In disposable HOME/config/database roots, launch the actual root and representative retained commands, checking exact/prefix dispatch, deliberate aliases, exit statuses, and missing-prerequisite errors. Exercise task listing/context and existing-directory/tree-reference behavior without creating worktrees. Verify table values, task scope, tags, and configured harmless actions survive reload. Install managed assets into a disposable destination; compare its production inventory with the catalog, preserve a controlled user override, and confirm examples are not dispatched. Observe actual native wrappers only in isolated backends; source inspection alone cannot prove backend support.

## Non-goals and safety

No Git worktrees, broad filesystem cleanup, live migrations, provider completion, new framework, or private-plugin/history census. Original repository and installed local files remain reference-only unless separately authorized. Sandbox HOME, DB, config, and external adapters. Never mutate live accounts or delete unmatched data to make the inventory look clean.

## Completion and handoff

After complete smoke proof, mark only step 15 in [the index](README.md) and commit the complete step in the clone. Report the disposition map, migrated consumers, retained exceptions/data, removed paths, exact checks and observed outcomes, limitations, and commit SHA. A blocked step stays unchecked. Hand off to [16](16-end-to-end-acceptance.md) when all dependencies are proved.
