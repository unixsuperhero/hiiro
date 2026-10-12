# 09. Shared PR actions and snapshot monitoring

Work ONLY in `/Users/unixsuperhero/proj/rehiiro`. Read [the shared contract](00-start-here.md) and [the PR workflow proposal](proposal.md#rebuild-pr-workflows-around-one-qualified-snapshot) first. Verify the implemented dependencies below, inspect current source before editing, and execute only step 09. These are planned action/monitor changes, not implemented behavior.

## Goal

Make single and bulk PR commands use one target-set action implementation. Replace human-output polling with qualified snapshot transitions, retain the YAML editor, and separate foreground check waiting from continuous monitoring. Fix queueing stays opt-in, and navigation never mutates Git.

## Inputs

- [bin/h-pr](../../bin/h-pr), [bin/h-pr-monitor](../../bin/h-pr-monitor), [bin/h-cpr](../../bin/h-cpr), and [PinnedPRManager](../../lib/hiiro/pinned_pr_manager.rb).
- [Queue](../../lib/hiiro/queue.rb), [Notification](../../lib/hiiro/notification.rb), [Notify plugin](../../plugins/notify.rb), and [EditedDocument/InputFile](../../lib/hiiro/input_file.rb).
- [current TUI](../../lib/hiiro/tui.rb), [Table](../../lib/hiiro/table.rb), [TableScope](../../lib/hiiro/table_scope.rb), [TableActions](../../lib/hiiro/table_actions.rb), and [RegistryEntry](../../lib/hiiro/registry.rb).
- [PR docs](../../docs/h-pr.md), [monitor docs](../../docs/h-pr-monitor.md), [current-PR docs](../../docs/h-cpr.md), and [CHANGELOG](../../CHANGELOG.md).

Single and `m*` actions currently duplicate orchestration. The monitor parses `gh pr status`, uses number-only state and personal URLs, and can open a browser on passing transitions. `h-cpr` injects a number after the first positional token. `attach` implicitly stages/commits WIP and checks out a branch.

## Dependencies

Requires [03. Owned execution](03-owned-execution.md) and [08. Qualified snapshots](08-pr-snapshots.md). Verify real process outcomes and cancellation, qualified target resolution, shared batched refresh, head revision, completeness, freshness, targeted writes, and preserved local preferences. Reuse those actual interfaces. Missing outputs block this step.

## Work

1. Inventory single/bulk operations and parameters, including open/view, checks, merge, ready/draft, comments, untrack, sync, and fix queueing. Resolve a target set of qualified references separately from action parameters and execution. Keep existing useful aliases over one implementation.
2. Route single targets and edited multi-target sets through the same operation. Preserve YAML selection and parameters through `EditedDocument`; distinguish editor cancellation, invalid YAML, and intentional empty selection. Validate qualified targets and action-specific fields before mutation, then report actual per-target outcomes and aggregate failure status.
3. Replace positional `h-cpr` injection with the shared current-branch PR resolver in the selected repository/directory. Preserve argv boundaries and flags through nested commands. Missing or ambiguous current PRs must fail clearly without selecting another repository's same-number PR.
4. Preserve foreground `check`, `watch`, and `fwatch` as native `gh pr checks` operations with qualified repository context, streaming, interruption, and real exit status. Do not reinterpret foreground waiting as the continuous monitor or collapse unknown/network failure into failing checks.
5. Build continuous monitoring from step 08 snapshots and the existing notification adapters. Establish a baseline, then detect check, review, and dependency transitions. Persist deduplication checkpoints keyed by qualified identity, head revision, and relevant event state. Repeated observations and restart must not replay notifications; a new revision must remain distinguishable. Failed/stale/incomplete observations must not create passing or approval-complete events.
6. Add explicit opt-in fix queueing through the existing Queue contract. Include qualified URL, head revision, failing evidence/completeness, and retained task/context associations. Deduplicate successful queue additions per revision; a failed addition must not mark the event delivered. Queueing does not launch an agent unless explicitly requested. Dependency transitions notify, never automatically merge.
7. Remove hidden Git mutation from navigation/attach. Open the existing task directory/terminal without staging, WIP commits, checkout, or worktree creation. Keep explicit checkout/merge/comment commands explicit. If retaining `--mark-ready`, preserve its explicit opt-in and require fresh complete revision-specific evidence; never enable it by default.
8. Delete migrated action duplicates, status-text parsing, and obsolete notification helpers. Preserve current `Tui::Screen/State/Pane`, table scoping, `task_id`, tags, and selection state. Update docs/changelog and add deterministic transition, cancellation, failure, and preservation regressions.

## Acceptance criteria

- Single and YAML-selected bulk operations have identical targeting, parameter validation, and failure behavior.
- Current-PR commands preserve nested grammar, flags, and repository identity.
- Foreground waiting preserves native behavior; monitoring uses snapshots and survives restart without duplicate effects.
- Fix queueing is opt-in, revision-qualified, and does not accidentally launch work.
- Dependency completion only notifies. Navigation leaves HEAD, index, working files, and branches unchanged.

## Verification

Use temporary HOME/DB/config/data roots, disposable repositories, and controlled `gh`, notifier, terminal, and queue adapters. Run actual single/bulk commands, edit the YAML selection, cancel it, and inject a target failure. Exercise the real picker or existing in-process screen, preserving query/focus/scroll/selection during refresh; do not substitute registration-only tests. Run foreground wait success, failure, and interruption. Run several monitor cycles plus restart across pending/failing/passing, partial fetch, approval, dependency, and new-head transitions. Inspect notifications and queue files: repeated snapshots produce no duplicates, disabled queueing produces no jobs, and opted-in queueing creates one qualified revision-specific job. Compare Git state before/after attach/navigation.

## Non-goals and safety

No Git worktrees, live account mutations, real merges, provider launches, or live notifications/jobs. Original and installed-local files are reference-only. Keep Ruby and useful values. No curses, external fuzzy-finder replacement for in-process screens, universal workflow engine, or scheduler daemon. Scheduling belongs to step 12.

## Completion and handoff

After actual smoke proof, update only step 09 in [the index](README.md) and commit the complete step. Report shared actions, monitoring checkpoints, queue/notification outcomes, preserved state, removed duplicates, exact checks, and commit. Leave incomplete work unchecked with its precise blocker. Next is [10](10-validation-recipes.md) after dependency verification; do not start it automatically.

