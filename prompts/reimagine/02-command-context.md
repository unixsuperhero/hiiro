# 02. Consistent task, app, and directory context

Work ONLY in `/Users/unixsuperhero/proj/rehiiro`. Read [the shared contract](00-start-here.md), [the context proposal](proposal.md#resolve-one-context-for-each-operation), and [the index](README.md) first. Verify the implemented dependencies below, then execute only step 02. This is planned implementation work. Inspect current source and reuse earlier contracts rather than assuming the proposal's example hashes are Ruby APIs.

## Goal

Resolve one explicit context per operation, then use it consistently for task, app, project, home, queue, service, runner, and tracked-file commands. Preserve strict selection and native argument handling.

## Inputs

- Values and selectors: [CurrentTask](../../lib/hiiro/current_task.rb), [TaskLocation](../../lib/hiiro/task_location.rb), [tasks.rb](../../lib/hiiro/tasks.rb), and [TaskCli](../../lib/hiiro/task_cli.rb).
- Mounts: [h-app](../../bin/h-app), [h-project](../../bin/h-project), [h-home](../../bin/h-home), and [root registrations](../../exe/h).
- Consumers: [Queue](../../lib/hiiro/queue.rb), [ServiceManager](../../lib/hiiro/service_manager.rb), [RunnerTool](../../lib/hiiro/runner_tool.rb), [AppFiles](../../lib/hiiro/app_files.rb), and [TableScope](../../lib/hiiro/table_scope.rb).
- Existing tests: `test/hiiro/current_task_test.rb`, `test/hiiro/task_location_test.rb`, `test/hiiro/table_test.rb`, `test/bin/t_test.rb`, `test/bin/app_test.rb`, and `test/bin/project_test.rb`.
- Read [task docs](../../docs/t.md), [app docs](../../docs/h-app.md), [project docs](../../docs/h-project.md), [file docs](../../docs/h-file.md), and [current instructions](../../AGENTS.md).
- Optional external sources: none required. Installed profiles are reference-only.

## Dependencies

[01. Canonical data ownership](01-data-ownership-and-migration.md) must provide working canonical task/app/project/pin/resource readers and targeted mutations. Inspect their interfaces and preservation evidence, not only the index checkbox. Block if those outputs are missing.

## Work

1. Trace every selection path and command mount. Compare CurrentTask's calling-workspace, realpath-directory, and pin resolution with Environment's first-match choices, TaskCli argument consumption, app Git-root fallback, queue launch/pane-dir, and service base-directory joins. Record existing intentional differences before choosing one policy.
2. Extend CurrentTask/TaskLocation into a resolved context containing the selected domain identities, effective directory, task-selection provenance, directory provenance, and explicit terminal identifiers. Task identity must be optional for project/home operations. Resolve once and pass the result to consumers. Choose Ruby signatures from current caller needs, not a prescribed new hierarchy.
3. Preserve exact-name precedence, unique-prefix matching, TTY disambiguation, and non-TTY ambiguity errors. Keep workspace/directory conflicts, stale pins, missing explicit targets, and overlapping task-directory errors visible. Never turn an ambiguity into the first match or a broad rescue fallback. Explicit task selection overrides inference. Preserve TableScope's intentional global-without-task behavior and remembered-task toggle without conflating global scope with unassigned entries.
4. Keep TaskCli's `-t`, `-f`, `.`, and orphan-todo `-` grammar. Separate selection inputs from native payload arguments before resolution. Do not consume native resume/session flags, reinterpret payload words, or parse formatted picker rows into identities. Use existing object-mapped fuzzy selection for selection-only pickers.
5. Migrate `path`, `abspath`, `cd`, `open`, shell/editor/search launches, and nested command builders. Preserve existing relative-versus-absolute output contracts while deriving them from one directory. Project/home commands work without creating tasks. A pane-targeted operation uses the explicit calling pane, never whichever pane happens to be focused.
6. Migrate queue frontmatter and pane-dir resolution, service definition-relative directories, runner Git/file discovery, and tracked-file opening at root and app mounts. Preserve valid frontmatter meanings and explain conflicts. An explicitly missing app or directory must fail rather than execute elsewhere. Resolve files from the documented root and ensure app mounts actually carry their selected context.
7. Remove conflicting Environment selection and duplicated joins only after all consumers migrate. Keep still-useful domain operations. Update README, command docs, and CHANGELOG with precedence, provenance, and errors.

## Acceptance criteria

- Equivalent explicit inputs resolve the same identities and directory across mounts.
- Provenance distinguishes explicit selections, calling workspace, directory inference, pins, and directory overrides.
- Ambiguous/stale context never launches work; project/home targets require no fake task.
- Native payload arguments and explicit calling-pane IDs survive unchanged.

## Verification

Run scoped context, task, app, project, and table regressions under isolated HOME/config/database settings. Add deterministic cases for symlink containment, overlapping roots, stale pins, conflicting pane/workspace IDs, app ambiguity, and native arguments. Then run actual clone commands for `t current`, task paths, `h app path`/`abspath`, project selection, queue pane-dir, and a harmless runner that writes its cwd to a sandbox file. Their outputs and recorded cwd must agree with the context policy. Exercise a real ambiguous selection picker and cancellation; cancellation must launch nothing. Verify a directory operation targets the calling pane even when another sandbox pane has focus. Missing native tooling blocks that proof rather than authorizing a fake fallback.

## Non-goals and safety

No Git worktrees, live account mutations, data-root moves, AI provider launches, or new language/framework. Original repo and installed files are reference-only. Use sandbox HOME, DB, config, and terminal targets. Reuse Hiiro::Tui::Screen/State/Pane for screens; do not add curses or shell out to a fuzzy finder for screens. Owned execution belongs to step 03.

## Completion and handoff

After smoke proof, update only step 02 in [the index](README.md), then commit the complete step in the clone. Report the resolved-context interface, migrated callers, preserved grammar, exact checks/outcomes, and commit. Leave incomplete work unchecked. Next eligible step: [03](03-owned-execution.md).

