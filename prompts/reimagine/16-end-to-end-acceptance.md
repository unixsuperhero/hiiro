# 16. Prove the redesigned workflows end to end

Work ONLY in `/Users/unixsuperhero/proj/rehiiro`. Read [the shared contract](00-start-here.md), [the proposal](proposal.md), and applicable project instructions first. Verify every dependency's implemented outputs below, then execute only this planned acceptance step. Inspect current source and commands before running them. Earlier evidence is useful but does not replace integrated artifact proof.

## Goal

Prove the redesigned CLI, persistent data, package, owned processes, and interactive picker work together in isolation. Repair acceptance gaps within steps 01–15 rather than declaring success from tests or expanding the redesign.

## Inputs

- [README](../../README.md), [CHANGELOG](../../CHANGELOG.md), [task reference](../../docs/t.md), [command docs](../../docs/README.md), and [prompt index](README.md).
- `test/test_helper.rb`, `script/test`, `Rakefile`, `hiiro.gemspec`, and the implemented dependency interfaces, migration/installation manifests, recipes, and smoke evidence.
- `lib/hiiro/tui.rb`, `lib/hiiro/table.rb`, `lib/hiiro/table_scope.rb`, `lib/hiiro/table_actions.rb`, `lib/hiiro/registry.rb`, and current table/registry command consumers. Read the Table/Tui sections of [AGENTS.md](../../AGENTS.md) and [the TUI plan](../../docs/plans/hiiro-tui.md). Exercise implemented behavior, not unchecked future PRs.

## Dependencies

Verify [01](01-data-ownership-and-migration.md), [02](02-command-context.md), [03](03-owned-execution.md), [04](04-command-catalog-and-lazy-boot.md), [05](05-managed-installation.md), [06](06-mcp-package-ownership.md), [07](07-safe-commit-planning.md), [08](08-pr-snapshots.md), [09](09-pr-actions-and-monitoring.md), [10](10-validation-recipes.md), [11](11-clipboard-artifacts-and-context.md), [12](12-recurring-job-outcomes.md), [13](13-editable-fuzzy-picker-pruning.md), [14](14-utility-and-profile-consolidation.md), and [15](15-legacy-cutover-and-product-scope.md). Require actual contracts and preservation/smoke evidence. Missing outputs block acceptance; do not invent substitute APIs.

## Work

1. Create a rerunnable isolated acceptance procedure using existing project conventions. Set disposable HOME, config/data roots, file-backed databases, gem home/path, controlled PATH, and synthetic terminal context before loading Hiiro. Route network/provider adapters away from live accounts. Use the implemented migration interface explicitly: `HIIRO_TEST_DB` historically skips automatic import, and an in-memory DB cannot prove restart preservation. Define literal expected outputs/state before each scenario.
2. Import synthetic legacy stores containing stable IDs, relationships, typed pins, resources, tags, recurrence, duplicate/conflicting records, and unknown files. Inspect conflict reporting and recovery material. Repeat migration, restart, and reload; prove exact records and protected definitions survive. Run independent concurrent writers and confirm unrelated updates persist without whole-table replacement. Preserve registry task associations, tags, and table action configuration too.
3. Drive actual task/context commands through explicit task/app, directory inference, calling-pane identity, ambiguity, and no-task cases. Include `t`, `tt`, and `h task` equivalence. Confirm path/execution cwd agree and read-only discovery/help does not create stores, invocation records, plugins, or branch tags. Use existing directories and recorded tree references, never new worktrees.
4. Start real harmless short-lived and long-lived child commands through foreground, queue, service, and background consumers. Observe streamed output, stdin, exit status, launch failure, normal exit, and explicit stop. Prove owned handles/outcomes distinguish a surviving pane from a finished child and cannot stop an unrelated process. Exercise validation failure artifacts, clipboard/context byte preservation, image/file references, and recurring-job outcomes with a controlled clock and local jobs. Refresh status after reload without producer-driven dashboard writes.
5. In disposable Git repositories, exercise commit planning and dry-run with staged/unstaged differences and unusual filenames. Compare index bytes, refs, and worktree content before/after; no commit or staging mutation is allowed in the dry-run. Feed qualified PR snapshots through controlled adapters: identical numbers in two repositories, stale fetch, partial checks, revision change, target-set actions, and monitoring deduplication must remain distinct. Record adapter-limited proof explicitly; do not claim live GitHub mutation was exercised.
6. Launch the actual in-process picker in a real terminal/PTY. Drive navigation, search, candidate selection, editor invocation, literal and group pruning, cancel/error, save, reload, and exclusion removal. Confirm restore reveals the same underlying records. Trigger refresh while query, cursor identity, scroll, focus, and marked selections are active; preserve them unless a removed identity requires the documented nearest-valid selection. Capture terminal output and confirm one `Tui::State`. Exercise current table scope/tags and harmless configured actions. Use native file/folder/save dialogs wherever the implemented UI requests paths.
7. Build the gem and install/setup into disposable gem/home destinations. Run installed entrypoints without checkout load paths or live installed overrides. Prove provenance, protected user overrides, safe repeat installation, and bundled MCP support using a local non-mutating transport. Smoke utility codecs, time/media outputs, root profiles, and retained native wrappers. Inspect concrete generated artifacts, not only argv or registrations.
8. Repair in-scope failures, add deterministic consumer-visible regressions where justified, and rerun the affected scenario. Update docs/changelog and record literal outputs, state comparisons, terminal captures, package identity, and limitations. Confirm superseded APIs have no remaining callers; preserve intentional aliases and supported unmatched behavior.

## Acceptance criteria

- Every dependency's named criterion has integrated command/state/artifact evidence or an explicit blocker.
- Migration/reload/concurrency, index-preserving dry-run, launch/exit/stop, qualified snapshots, and prune/save/restore pass.
- Actual screen interaction preserves state and data; unit tests or source text alone never satisfy this criterion.
- Package, callers, docs, and maintained aliases agree; no superseded duplicate implementation remains.

## Verification

Run scoped tests during repairs. Once integration is stable, run `script/test` once under the sandbox; it invokes `bundle exec rake test` from `Rakefile`. `test/test_helper.rb` uses in-memory SQLite and intercepted command effects, so passing it is supporting evidence only. Execute the scenarios above with real CLI/process/picker/package artifacts and retain exact observed results. If a terminal, native tool, or transport prerequisite is unavailable, state what was attempted and leave acceptance incomplete rather than replacing the requirement with a mock.

## Non-goals and safety

No Git worktrees, publishing, pushing, private credentials/config/history, live account/network mutations, live migrations, or live recurring jobs. Original repository and installed files are reference-only. Keep Ruby and existing native adapters; no new framework, universal engine, or unrelated future table-plan implementation. Stop only owned sandbox processes and remove only verification resources created here.

## Completion and handoff

After all artifact smoke checks pass, update only step 16 in [the index](README.md) and commit the complete acceptance step and in-scope repairs in the clone. Report contracts/callers, preserved data, removed obsolete paths, exact checks and literal outcomes, limitations, and commit SHA. Blockers leave the box unchecked. There is no next numbered step; hand back the completed index and acceptance evidence without claiming unexercised platform/provider behavior.
