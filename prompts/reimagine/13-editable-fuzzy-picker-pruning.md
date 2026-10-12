# 13. Editable fuzzy picker and persistent pruning

Work ONLY in `/Users/unixsuperhero/proj/rehiiro`. Read [the shared contract](00-start-here.md) and [the proposal](proposal.md#edit-and-permanently-prune-lists-from-the-fuzzy-picker) first. Verify the implemented dependencies below, inspect current source before editing, and execute only step 13. This is planned work. Current project instructions take precedence over older proposal implementation assumptions.

## Goal

Let users edit picker choices and save reversible exclusions across searches and invocations. Removing an edited row excludes that stable item, never the underlying resource. Reuse the existing in-process TUI engine for edit/action keys and interaction state.

## Inputs

- Read [project instructions](../../AGENTS.md) and [the TUI plan](../../docs/plans/hiiro-tui.md). `lib/hiiro/tui.rb` already provides `Tui::Screen`, `State`, `Pane`, class key maps, search/pick modes, and `ListScreen`. Do not introduce another engine or parallel mode booleans.
- `lib/hiiro/fuzzyfind.rb` has standalone `sk`/`fzf` selectors; `lib/hiiro.rb` exposes picker helpers. These may remain for simple selectors, not as a screen engine.
- `lib/hiiro/input_file.rb` supplies `EditedDocument`. `lib/hiiro/matcher.rb` supplies existing resolution behavior.
- `lib/hiiro/registry.rb`, `lib/hiiro/table.rb`, `lib/hiiro/table_scope.rb`, and `lib/hiiro/table_actions.rb` already preserve table identity, nullable task association, tags, task/global scope, and configured actions. Registry picker helpers currently parse decorated columns.
- Inspect `bin/h-registry`, `bin/h-link`, `bin/h-project`, `lib/hiiro/task_cli.rb`, `bin/h-branch`, and `bin/h-pr`. Trace file selectors and saved-information consumers through task resources, `bin/h-save`, `bin/h-obsidian`, and `bin/h-docs`.
- Read [registry docs](../../docs/h-registry.md), [project docs](../../docs/h-project.md), and tests in `test/hiiro/tui_test.rb`, `test/hiiro/table_test.rb`, `test/hiiro/fuzzyfind_test.rb`, and `test/hiiro/input_file_test.rb`.

## Dependencies

- [01. Data ownership](01-data-ownership-and-migration.md) must provide an authoritative persistence owner that preserves existing records and relationships.
- [02. Command context](02-command-context.md) must identify explicit task/project scope and retain ambiguity semantics.
- [04. Command catalog](04-command-catalog-and-lazy-boot.md) must provide stable read-only command candidates and provenance.

Verify required outputs, not checkboxes. Reuse implemented contracts without prescribing future Ruby signatures. Missing prerequisites block this step.

## Work

1. Inventory picker consumers and stable identities. Keep records separate from labels. Qualify branch identities by repository and PR identities by repository plus number. Commands use catalog provenance; files use defined path bases; tasks use durable IDs. Preserve public scalar outputs where commands promise them, but obtain them from selected records.
2. Implement an edit-capable picker through `Tui::Screen` and its key map/state. Show a discoverable configurable binding such as Ctrl-E. Suspend and restore terminal/editor interaction safely. Reuse `InputFile` and `EditedDocument` to edit an explicit list of identities and exclusion rules.
3. Give each picker a stable name and persist exclusions through one owner. Make picker-local, task, project, and global applicability explicit. Global scope must require deliberate selection. Preserve `TableScope` for table visibility; do not confuse its scope toggle with permission to save global pruning rules.
4. Translate deleted edited rows into exact identity exclusions. Treat the editor list as its original snapshot: hidden, paginated, or newly arrived items must not become exclusions. Preserve labels as presentation, not editable identity authority. Group rules require explicit literal, substring, regex, glob, or extglob mode and field.
5. Define available identity/name/path fields, case sensitivity, path-base/separator normalization, regex dialect, glob wildcards, and extglob operators. Implement matching in Ruby, never through shell execution. Support examples such as `**/*.bak` and `**/*.@(bak|tmp)` with documented semantics. Any applicable matching exclusion hides a choice across subsequent searches and invocations.
6. Preview excluded items and the matching rule before confirmation. Reject invalid documents, fields, scopes, and patterns without changing saved rules. Retain edited text/errors for recovery. Provide show-excluded and rule-edit/removal restoration. Preserve query, cursor anchor, scroll, and still-visible selections across editing/refresh; move predictably when the current item becomes excluded.
7. Migrate command, file, task, project, branch, PR, and saved-information pickers to the shared pruning behavior. Preserve existing table values, task IDs, tags, and `TableActions`. Remove obsolete row parsing and duplicate picker-edit implementations only after cutover. Add deterministic behavioral regressions and update README, affected docs, and CHANGELOG.

## Acceptance criteria

- Exact deletions and all five explicit group modes persist with correct scope and identity.
- Invalid edits leave saved exclusions unchanged; restoration makes resources selectable again.
- Duplicate labels do not select or exclude the wrong item.
- Editing/refresh preserves interaction state and visible selections.
- Every named consumer family uses shared pruning without deleting resources or changing Git state.

## Verification

Run focused TUI, table, editor, and new exclusion tests. Assert literal rendered states and matching outcomes, not source wiring. Test scope isolation, duplicate labels, renamed display text, future matching items, path/case semantics, malformed regex/extglob, and snapshot-only deletion. In sandboxed HOME/DB/config/data roots, drive the real interactive picker through search, selection, Ctrl-E, deletion, preview, save, reload, show-excluded, and restoration. Capture query/position/selection before and after editing. Exercise actual entrypoints from every consumer family with disposable repositories and local PR/Portfolio adapters. Inspect unchanged files, task resources, table tags/values, branches, and PR records. Unavailable terminal/editor prerequisites block interactive completion; unit tests alone do not replace proof.

## Non-goals and safety

No Git worktrees, curses, second screen engine, new language/framework, universal datastore, shell-evaluated patterns, or live account mutations. Original and installed files are reference-only. Sandbox all roots. Pruning must never invoke resource deletion or configured destructive actions. Any UI requesting filesystem paths must use native OS pickers/save dialogs.

## Completion and handoff

After actual interactive proof, mark only step 13 in [the index](README.md) and commit the complete step. Report rule semantics and storage, migrated consumers, preserved data/state, exact tests and picker captures, removed paths, and commit ID. Missing prerequisites leave the checkbox unchecked. Identify [step 14](14-utility-and-profile-consolidation.md) as next eligible after its contracts are verified; do not begin it.

