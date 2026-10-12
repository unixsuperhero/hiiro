# 12. Managed recurring work and status outcomes

Work ONLY in `/Users/unixsuperhero/proj/rehiiro`. Read [the shared contract](00-start-here.md) and [the proposal](proposal.md#automate-specific-manual-handoffs) first. Verify the implemented dependencies below, inspect current source before editing, and execute only step 12. These are planned changes, not an instruction to enable live schedules.

## Goal

Use platform scheduling for existing reminder, queue, and periodic recipes. Persist their real checkpoints and completion outcomes so views and notifications consume records instead of requiring agents to regenerate dashboards. Keep activation and agent interpretation explicit.

## Inputs

- `bin/h-remind` contains interval/absolute/relative time parsing, one-time disabling, and a `check` worker. `lib/hiiro/reminder.rb` supplies the persisted model. Read the post-step-01 owner rather than reviving the inspected inline YAML manager.
- `lib/hiiro/queue.rb` owns queue entries and its foreground watcher. Scheduling must reuse the post-step-03 claim, launch, and completion contract.
- `bin/h-loop` stores loop config/status, starts tmux-based Claude loops, and asks each producer to write `status.json` and run `h-loop render`. Its inspected launch command includes a permission-bypass flag.
- `bin/h-notify` stores notifications and installs Claude hooks by replacing event arrays. `lib/hiiro/tuios.rb` documents native integration ownership and bounded managed changes.
- Read [queue docs](../../docs/h-queue.md), [notification docs](../../docs/h-notify.md), [PR monitoring docs](../../docs/h-pr-monitor.md), [project instructions](../../AGENTS.md), and `test/hiiro/queue_entry_test.rb`.
- Optional external reference-only sources are [`/Users/unixsuperhero/bin/h-yt`](file:///Users/unixsuperhero/bin/h-yt) and [`/Users/unixsuperhero/bin/h-activity-viewer`](file:///Users/unixsuperhero/bin/h-activity-viewer). The former uses bounded history fetching, video-ID deduplication, and a lock; `cron` only prints instructions. The latter provides app-specific sync/lifecycle. Inspect if available; do not edit, execute, or require them for core completion.

## Dependencies

Verify implemented outputs from [01. Data ownership](01-data-ownership-and-migration.md), [03. Owned execution](03-owned-execution.md), [09. PR actions and monitoring](09-pr-actions-and-monitoring.md), [10. Validation recipes](10-validation-recipes.md), and [11. Clipboard artifacts](11-clipboard-artifacts-and-context.md).

Require canonical reminder/checkpoint writers, atomic queue ownership, qualified polling snapshots, real recipe failures/logs, and artifact/context handoff. Reuse actual interfaces, not invented signatures. Missing contracts block this step.

## Work

1. Inventory current recurring recipes and user configuration. Preserve reminder IDs, intervals, trigger timestamps, sound, enabled/once values, last-triggered state, and useful loop prompts. Separate deterministic native/API polling from explicitly requested agent interpretation.
2. Extend existing worker entrypoints for bounded one-shot execution. Reuse the PR monitor for PR polling and the existing queue for agent handoff. Do not schedule a second watcher or rebuild polling inside agent prompts. Keep personal history/activity behavior in adapters if those references inform configured recipes.
3. Implement macOS launchd schedule management with inspectable plans, explicit enable/disable, stable owned labels, absolute executable/cwd/env references, and bounded concurrency. Preserve unrelated LaunchAgents. Configuration or import alone must not activate anything. Report scheduler-registration failures without claiming enablement.
4. Define interval versus wall-clock recurrence, timezone/DST behavior, missed-run handling, and restart semantics. Persist next-due/checkpoint updates through the canonical owner. Ensure overlapping invocations cannot claim the same occurrence or queue entry. Distinguish notification delivery failure from successful reminder completion, and document the unavoidable delivery/crash boundary without promising exactly-once external delivery.
5. Write completion records using owned-run results, context, timestamps, outcome, and artifact references. Failed startup, nonzero exit, interruption, stale ownership, and skipped overlap must remain distinguishable. Never infer success from a living terminal pane or mark a task done because a worker finished.
6. Cut `h loop` and relevant status/notification consumers over to recorded outcomes. Remove producer instructions to rewrite status files and regenerate dashboards after each cycle. Preserve explicit rendering as a view operation where useful. Background refresh must retain query, focus, scroll, and selections. Keep agent interpretation opt-in and remove automatic permission bypass from recurring launch recipes.
7. Install/remove only Hiiro-owned hook entries, preserving unrelated event hooks and settings. Reuse native TUIOS ownership conventions. Finish caller migration before deleting obsolete producers. Add deterministic recurrence/concurrency/failure regressions and update README, command docs, and CHANGELOG.

## Acceptance criteria

- Schedules remain inactive until explicitly enabled and affect only owned definitions.
- Reload/restart preserves recurrence and checkpoints; overlapping workers obey configured bounds.
- Completion records show real process outcomes and retained evidence.
- Views refresh without losing interaction state; hooks preserve unrelated settings.
- Deterministic polling requires no agent, and agent runs require explicit configuration.

## Verification

Run focused queue/reminder/outcome regressions with controlled clocks and isolated stores. Execute real one-shot reminder, queue, and periodic fixture commands in temporary HOME/DB/config/data roots. Start overlapping fixture workers and observe one claim, bounded execution, persisted completion, and correct failure status. Reload and exercise a due one-time reminder and recurring reminder without duplicate local claims. Use a disposable, uniquely named launchd fixture job pointing only to sandbox paths; observe explicit enable, execution, status, disable, and removal of that owned job. Never install into live LaunchAgents. Exercise hook setup twice against fixture settings. Drive the actual status UI through refresh and confirm query/scroll/selection remain. Capture failed logs and artifact references. Do not fetch browser cookies, contact providers, or start real agents.

## Non-goals and safety

No generic scheduler daemon, new language/framework, Git worktrees, live account mutations, destructive automation, automatic merging, or permission bypass. Original and installed files are reference-only. Native filesystem pickers are required if new UI asks for paths. Never stop unrelated processes or overwrite unrelated schedules/hooks.

## Completion and handoff

After real worker, scheduler, and view proof, mark only step 12 in [the index](README.md) and commit the complete step. Report preserved schedules/data, owned labels/hooks, exact checks and observed outcomes, removed producer paths, and commit ID. Leave blocked work unchecked with the precise missing contract. Identify [step 13](13-editable-fuzzy-picker-pruning.md) as next eligible after verification; do not start it.

