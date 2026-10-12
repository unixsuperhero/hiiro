# 03. Owned process and terminal execution

Work ONLY in `/Users/unixsuperhero/proj/rehiiro`. Read [the shared contract](00-start-here.md), [the execution proposal](proposal.md#share-execution-ownership-not-a-universal-workflow-engine), and [the index](README.md) first. Verify the implemented dependencies below, then execute only step 03. This is planned implementation work. Inspect current source and reuse earlier ownership/context contracts without inventing their Ruby signatures.

## Goal

Make launches and outcomes truthful across queue, services, background work, task sessions, and capture. A terminal allocation is not process startup, readiness, completion, or authority to stop another process.

## Inputs

- Execution values/adapters: [shell.rb](../../lib/hiiro/shell.rb), [effects.rb](../../lib/hiiro/effects.rb), [Herdr](../../lib/hiiro/herdr.rb), and [Tuios](../../lib/hiiro/tuios.rb).
- Consumers: [Queue](../../lib/hiiro/queue.rb), [ServiceManager](../../lib/hiiro/service_manager.rb), [Background](../../lib/hiiro/background.rb), [TaskSessions](../../lib/hiiro/task_sessions.rb), and [h-capture](../../bin/h-capture). Follow [h-bg](../../bin/h-bg) and root/app mounts too.
- Tests: `test/hiiro/command_specification_test.rb`, `test/hiiro/shell_test.rb`, `test/hiiro/queue_herdr_test.rb`, `test/hiiro/service_manager_herdr_test.rb`, `test/hiiro/background_test.rb`, `test/hiiro/herdr_location_test.rb`, and `test/bin/t_test.rb`.
- Docs: [queue](../../docs/h-queue.md), [services](../../docs/h-service.md), [background](../../docs/h-bg.md), [tasks](../../docs/t.md), and [project instructions](../../AGENTS.md).
- Optional external sources: native Herdr/TUIOS documentation and binaries may clarify existing capabilities. Do not modify installed-local support or launch its live inbox server.

## Dependencies

Verify [01](01-data-ownership-and-migration.md)'s canonical runtime ownership/preservation policy and [02](02-command-context.md)'s resolved context, provenance, and explicit terminal targets. Require actual interfaces and smoke evidence. Missing outputs block this step.

## Work

1. Trace launch, observation, completion, and stop paths. In isolated fixtures, investigate queue's move-before-launch and shell `HQ_EXIT` handoff, services keyed only by definition name, unchecked terminal responses, Background's idle-pane race/rescue, and capture status propagation. Treat source risks as unverified until reproduced.
2. Reuse CommandSpecification/Result and Herdr::Location/TabCreation for the smallest shared launch request/result and owned-run contract. Carry owner identity, resolved cwd/environment, command kind, I/O mode, placement, native handles, and observed outcome. Keep argv distinct from authored shell text. Distinguish allocated, started, ready, completed, and failed; signal termination is not exit zero. Do not require service readiness for ordinary background commands.
3. Give durable run records a stable identity under step 01's authority. Record enough native process identity to reject PID reuse and unrelated targets before stop. Keep task, todo, queue, and process completion separate. A completed agent must not mark its task done.
4. Make queue claims atomic across competing launchers. Associate a claim with its run; handle allocation/start failure and interrupted launch without leaving a false running entry. Pass the actual child status to completion, including nonzero exits. Preserve markdown/frontmatter ownership and recoverable prompt files. Avoid multiple competing status authorities.
5. Identify service instances by definition plus resolved task/directory and relevant variation, with separate run IDs and per-instance scripts. Preserve init/env/start ordering and surface preparation failures. Report readiness only from a configured observable condition. Stop the identified instance, observe termination before cleanup/removal, and retain truthful state on failure. Do not kill by label, stale pane, or PID alone.
6. Reserve reusable background panes atomically before dispatch and release ownership on failure/completion. Return observable launch failures instead of swallowing exceptions. Preserve detached native spawning outside Herdr. Keep TaskSessions' native omp/codex/claude resume flags, existing-session focus, ambiguous-session errors, and native conversation history.
7. Preserve inherited interactive I/O, process replacement where required, piped stdin, binary bytes, and bounded disk streaming in capture. The current Shell chunk collector buffers everything and prints additionally; do not route capture through it unchanged. Migrate all affected callers, including any touched Tuios server lifecycle path, without weakening its process/port checks. Delete obsolete launch/state paths only after cutover. Update README, docs, and CHANGELOG.

## Acceptance criteria

- Allocation and startup failures never report a running process.
- Queue entries have one claimant and terminal outcomes reflect actual child status.
- Same-definition services in different contexts remain independent; stop refuses unrelated/reused identities and waits for exit.
- Concurrent launches cannot share a reserved pane. Capture preserves bytes/stdin and propagates failure without unbounded buffering.

## Verification

Use temporary HOME/config/data, a file-backed isolated DB, and harmless local Ruby/shell children, never providers. Run scoped transition/race regressions with synchronization rather than sleeps. Smoke actual queue current-mode success and exit 7, launch failure recovery, two service instances, observed stop, and detached background completion. Pipe binary input through `h capture file` into a child that echoes bytes and exits 7; compare the saved bytes, terminal bytes, capture row, and CLI exit. Exercise actual Herdr allocation, startup, failure, and pane reuse in dedicated sandbox terminal targets. Native resume can be tested with a controlled argument-recording executable, but it is not proof of a live provider session. Missing safe native terminal access leaves that acceptance criterion blocked.

## Non-goals and safety

No Git worktrees, live account mutations, installed-file edits, generic workflow engine, scheduler, speculative terminal backend, or new language/framework. Reuse Hiiro::Tui::Screen/State/Pane for screens. Do not rewrite Herdr/TUIOS or mutate real harness setup.

## Completion and handoff

After smoke proof, mark only step 03 complete in [the index](README.md) and commit the complete step in the clone. Report interfaces, state transitions, migrated callers, exact checks/outcomes, and commit. Blocked criteria remain unchecked. Next eligible step: [04](04-command-catalog-and-lazy-boot.md).

