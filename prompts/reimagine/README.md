# Reimagining Hiiro: implementation prompt index

This prompt set describes how to implement the design in [the proposal snapshot](proposal.md). It lives in the independent clone at `/Users/unixsuperhero/proj/rehiiro`; the original Hiiro checkout and installed commands remain unchanged.

## Current status

- Workspace and prompt set prepared.
- Steps 01–03 are implemented and verified. Steps 04–16 remain unchecked and have not started.
- User authorization: finish the remaining numbered steps sequentially; after final acceptance, package and publish the new `rehiiro` gem.
- Clone baseline: `139aa0143644d73c257edb810bd8afef88ba39a8`, source branch `main`.
- The clone’s `origin` is the local original repository. Do not push or change that remote, modify the original checkout, or replace installed commands.

### Authoring checks

- Parsed all 19 Markdown files and checked 425 local links/anchors, prerequisite ordering, and required prompt sections.
- The cloned CLI returned `pong` from `ruby -Ilib exe/h ping` with a temporary HOME and in-memory test database. This is a startup smoke check, not redesign acceptance.
- At authoring, `bundle check` reported missing `mcp` 1.7.0, `sequel` 5.109.0, `io-console` 0.9.4, and `regexp_parser` 2.13.1. The Bundler test suite was not run. Prepare an isolated gem environment before implementation verification; do not alter live gem installations automatically.

### Step 01 implementation verification

- Step 01 is implemented in the clone. SQLite owns mutable domain records; definitions, preferences, runtime files, prompts, notes, and ordinary artifacts retain their documented file owners. See [data authority and recovery](../../docs/h-db.md).
- Stabilized isolated aggregate: **639 runs, 2,605 assertions, zero failures or errors**. All 54 changed Ruby files passed `ruby -c`. Existing constant-reload and Minitest deprecation warnings remain.
- The aggregate loaded `test/**/*_test.rb` with Ruby 3.3.10, an allowlisted environment, temporary HOME, and isolated gems. Its exact exclusion filter was:

  ```text
  /test_tree_commands_create_detach_and_resume_worktrees_without_herdr|test_current_task_detects_external_absolute_tree|test_directory_commands_resolve_optional_app_by_exact_or_unique_prefix|test_all_lists_all_executables_on_path|test_glob_finds_executables_from_path/
  ```

- These five exclusions cover real worktree creation, an unmocked live Herdr query, and observed unrelated task-context/command-discovery failures. This is not an unqualified full-suite pass.
- `test/hiiro/db_migration_test.rb`: **16 runs, 134 assertions, zero failures or errors**. Actual `h-db` plan/import/replay/export/restore/reexport fixtures preserved IDs, types, relationships, allocators, source/definition bytes, and later canonical writes/deletions. Failed or interrupted imports and failed fresh verification retained truthful completion state.
- `test/bin/data_ownership_test.rb`: **5 runs, 101 assertions, zero failures or errors**. Actual `t`, `tt`, `h-todo`, `h-link`, and `h-remind` subprocesses proved targeted writes, task/orphan scope, string pins versus integer task IDs, link/tag identity, pause/resume, and recurrence.
- Additional isolated CLI proofs covered project/app aliases, pane homes, task metadata/resources, branch tags, qualified PRs/check owners, editor failure/conflicts, and retained legacy SQL. PR and notification adapters were controlled; clone Pins was explicitly preloaded where baseline discovery required it.
- Native legacy `h-otask` dispatch remains unverified because its external Tmux plugin is unavailable. Its in-repo persistence methods passed isolated adapter regressions; unavailable external Task/OldTask implementations were not fabricated.
- The original checkout, installed commands, remotes, and live user data were not modified. No redesign step after 01 was started. The next eligible prompt is [02](02-command-context.md).

### Step 02 implementation verification

- One immutable `TaskLocation` carries canonical optional task/app/project identity, invocation/root/effective directories, task/directory provenance, and explicit calling terminal. Strict selectors preserve mapped objects; missing, blank, ambiguous, stale, overlapping, and conflicting inputs fail instead of launching in a fallback context.
- Root/task/app queue, service, runner, and tracked-file mounts share the selected context. Project/home contexts remain taskless; TableScope preserves global/task toggle behavior. Native flags, resume/session values, empty payload arguments, binary streams, and actual child exit codes remain intact.
- Final isolated aggregate: **681 runs, 3,069 assertions, zero failures or errors**. All 33 changed Ruby files passed `ruby -c`. The aggregate includes actual subprocess regressions in `test/bin/command_context_test.rb` (15 cases / 260 assertions) and repaired formerly excluded task-context cases.
- Exact remaining exclusions:

  ```text
  /test_tree_commands_create_detach_and_resume_worktrees_without_herdr|test_all_lists_all_executables_on_path|test_glob_finds_executables_from_path/
  ```

  Real worktree creation remains forbidden; the two observed baseline executable-discovery defects belong to step 04. This is not an unqualified full-suite pass. Removed an obsolete Git command-echo test rather than re-pinning its argv; actual disposable Git comparisons proved nested-cwd relative and repository-wide paths, including newline, apostrophe/space, and leading-dash filenames.
- Actual isolated Herdr 0.8.2 proof: task/app `cd` changed the calling pane while another pane remained focused; real `sk` and `fzf` chose original mapped task/app/project objects, and Escape cancelled without launch or terminal mutation. Native editor/split queue proof rejected invalid edited context before provider invocation. Read-only native `t ls`, outside active Herdr context and with stale caller IDs, retained task pane rows and duplicate-name loose workspaces without changing native state; mutations still rejected stale IDs.
- Review corrections exercised after repair: inherited child/legacy workflow context, blank selectors/directories, stale-pane home creation, dangling tracked symlink escapes, quoted native filenames, and live-inventory suppression. Native proof sessions, sockets, editors, and sentinel scripts were cleaned; evidence remains under `/tmp/rehiiro-step02-native.3RY9e3`. No live provider/account or original installation was used.
- All 139 local links/anchors across the 13 affected Markdown files resolved before the completion record was added. Next: [03](03-owned-execution.md).

### Step 03 implementation verification

- Interfaces: `Hiiro::OwnedRun` (lib/hiiro/owned_run.rb) with `LaunchRequest` (`id`, `owner`, `command`, `placement`, `process_group`, `ready`), durable JSON run records under `~/.local/share/hiiro/runs/` (runtime files per step 01's ownership policy, not domain rows), one transition table (`allocated -> started -> ready -> completed|failed`, `allocated -> failed`), `ProcessIdentity` (pid + `ps` lstart), `Store` (locked read-modify-write), `Supervisor` (spawns the child, records pid/start time, optional ready probe, actual exit/signal, then owner settlement), and `Launcher` (`current` exec, `detached`, `herdr_tab`, `herdr_split`, `herdr_pane`; waits for an observed start, else a failed record and `LaunchError`). `CommandSpecification.shell` keeps authored shell text distinct from argv; `ProcessOutcome` separates signals from exit codes. `Hiiro::QueueClaim` (atomic pending->running rename, outcome-based settle) and `Hiiro::PaneReservations` (lock-held pane choice). See [owned runs](../../docs/owned-runs.md).
- Migrated callers: queue window/current/split launch, `kill`, and `ls`; service start/stop/status/ls/clean/reset/attach (instances keyed by definition + directory + task + variations, per-instance scripts, init -> env -> exec start, `ready:`/`stop_timeout:`); `Background.run` and `h bg` (new `ls`); `h capture` through `Capture.stream`/`.record`; Herdr `new_tab`/`split_pane` now raise on an undelivered command; `Shell.stream` no longer prints chunks twice. Deleted: per-entry queue `.sh` launchers with the `HQ_EXIT` handoff, `Queue#strip_frontmatter`, `Entry#launcher_path`, the service `trap 'h service reset'` launcher, name-keyed service state, Background's `rescue nil`, and h-capture's popen2e copy loop. TaskSessions is unchanged (native tool runs directly so Herdr agent detection, resume flags, focus, ambiguity errors, and history stay native); TUIOS server lifecycle was not touched.
- Reproduced before fixing (HEAD copies in scratch `repro-03/`): queue handoff read `ENV["HQ_EXIT"]` as nil and filed a failed agent as done; old `h capture` exited 1 for a child exiting 7; `Shell.stream` emitted each chunk twice; `Background.run` returned nil when Herdr raised; two concurrent old `Background.run` calls both typed into idle pane `wC:p1`; the same service definition in a second directory was refused as "already running".
- Tests (Ruby 3.3.10, temp HOME, `LANG=en_US.UTF-8`, `BUNDLE_PATH` of the step 01 gem set): command_specification 5/26, shell 16/18, queue_herdr 14/85, service_manager_herdr 6/49, background 5/22, herdr_location 5/28, t_test 47/730 with only the excluded worktree case failing, new owned_run 8/32, new bin/capture 2/10, queue_entry 2/19, workflow_context 4/35. Race regressions synchronize on pipes, queues, and run-state polling rather than fixed sleeps.
- Aggregate (all `test/**/*_test.rb` in one process) with the same exclusions as step 02: **708 runs, 3,223 assertions, zero failures or errors**.

  ```text
  /test_tree_commands_create_detach_and_resume_worktrees_without_herdr|test_all_lists_all_executables_on_path|test_glob_finds_executables_from_path/
  ```

  The per-file loop (710 runs) additionally shows 30 `NameError: uninitialized constant Pins` errors in commit/pane/plugin/session/sha/window tests; an exported HEAD copy gives the identical per-file errors, because only the aggregate preloads the Pins plugin. All 23 changed Ruby files passed `ruby -c`.
- Smokes (temp HOME, file-backed `HIIRO_TEST_DB`, a fake `omp` script, PATH without real providers; isolated headless Herdr 0.8.2 session `rehiiro-s03` with its own XDG/config/socket): `h queue cadd` exited 0 and 7 with entries in `done/` and `failed/` and runs `completed exit 0` / `failed exit 7`; launch failures (no agent: exit 127; Herdr socket absent: `Herdr did not create workspace hq`; Herdr pane without the agent: `No such file or directory - omp`) all left `failed/` entries with run errors, and `retry` + `h queue run` in the sandbox moved both to `done/`; four concurrent launchers produced one `Launched`, one agent invocation, and one run record; two `web` instances (sandbox Herdr tab and detached) both reached `ready`, a bare `stop web` outside either directory failed as ambiguous, stopping beta left alpha's pid alive, each stop observed `completed exit 0` after the service's TERM handler ran, then cleanup ran in its own directory; a preparation failure in the Herdr pane surfaced as `failed exit 1`; detached `h bg` runs recorded `completed exit 0` and `failed exit 4`; sandbox `h bg` reused idle pane `w2:p1` sequentially, and three concurrent launches took `w2:p1`, `w2:p2`, `w2:p3` with distinct reservations released afterwards; 1,030 binary bytes piped through `h capture file` into a child exiting 7 matched in saved file and terminal output (same SHA-256), the CLI exited 7, and the row stored `exit_status` 7; 300 MB and 1.2 GB captures peaked at the same ~120 MB RSS. Evidence: session scratchpad `rehiiro/smoke-03/`.
- Blockers: none for the acceptance criteria. Herdr evidence is from a headless isolated server, not an interactive client. `h bg run 'a; b'` (one quoted argument) is shell-escaped into a single word, as before this step; argv form works.
- The original checkout, installed commands, remotes, and live user data were not modified. One unit-test run briefly spawned the installed `omp` binary (stdin and output `/dev/null`, exited 1) before test PATHs were restricted to the fixture directory and system paths. Next: [04](04-command-catalog-and-lazy-boot.md).

## Start here

Read [the shared execution contract](00-start-here.md), then the relevant section of [the proposal](proposal.md), then one numbered prompt. Run the steps in numeric order. Each step lists required earlier contracts; verify those contracts in the code instead of trusting its checkbox.

To start the first step, give your coding agent this request while working in the clone:

```text
Read prompts/reimagine/00-start-here.md and prompts/reimagine/01-data-ownership-and-migration.md.
Implement and verify only step 01 in /Users/unixsuperhero/proj/rehiiro.
Do not modify /Users/unixsuperhero/proj/hiiro or installed commands.
```

For subsequent steps, replace the numbered filename. These prompts are instructions for future implementation, not an automatic execution queue. Nothing in this index starts a process, scheduler, migration, or provider.

## Ordered steps

### Phase 1: Canonical data ownership

- [x] [01. Canonical data ownership and safe migration](01-data-ownership-and-migration.md). No implementation prerequisite.

### Phase 2: Context and execution

- [x] [02. Consistent task, app, and directory context](02-command-context.md). Requires [01](01-data-ownership-and-migration.md).
- [x] [03. Owned process and terminal execution](03-owned-execution.md). Requires [01](01-data-ownership-and-migration.md), [02](02-command-context.md).

### Phase 3: Discovery and installation

- [ ] [04. Read-only catalog and lazy command startup](04-command-catalog-and-lazy-boot.md). Requires [01](01-data-ownership-and-migration.md), [02](02-command-context.md).
- [ ] [05. Managed assets and installation provenance](05-managed-installation.md). Requires [04](04-command-catalog-and-lazy-boot.md).
- [ ] [06. Package the existing MCP implementation](06-mcp-package-ownership.md). Requires [01](01-data-ownership-and-migration.md), [05](05-managed-installation.md).

### Phase 4: Git and PR workflows

- [ ] [07. Index-preserving commit planning](07-safe-commit-planning.md). Requires [03](03-owned-execution.md).
- [ ] [08. Repository-qualified PR snapshots](08-pr-snapshots.md). Requires [01](01-data-ownership-and-migration.md), [03](03-owned-execution.md).
- [ ] [09. Shared PR actions and snapshot monitoring](09-pr-actions-and-monitoring.md). Requires [03](03-owned-execution.md), [08](08-pr-snapshots.md).

### Phase 5: Reusable workflows and picker UX

- [ ] [10. Reliable validation recipes and captured failures](10-validation-recipes.md). Requires [02](02-command-context.md), [03](03-owned-execution.md).
- [ ] [11. Shared clipboard artifacts and context handoff](11-clipboard-artifacts-and-context.md). Requires [01](01-data-ownership-and-migration.md), [02](02-command-context.md), [03](03-owned-execution.md).
- [ ] [12. Managed recurring work and status outcomes](12-recurring-job-outcomes.md). Requires [01](01-data-ownership-and-migration.md), [03](03-owned-execution.md), [09](09-pr-actions-and-monitoring.md), [10](10-validation-recipes.md), [11](11-clipboard-artifacts-and-context.md).
- [ ] [13. Editable fuzzy picker and persistent pruning](13-editable-fuzzy-picker-pruning.md). Requires [01](01-data-ownership-and-migration.md), [02](02-command-context.md), [04](04-command-catalog-and-lazy-boot.md).

### Phase 6: Consolidation and final proof

- [ ] [14. Shared utility registrations and personal profiles](14-utility-and-profile-consolidation.md). Requires [02](02-command-context.md), [03](03-owned-execution.md), [04](04-command-catalog-and-lazy-boot.md), [10](10-validation-recipes.md), [11](11-clipboard-artifacts-and-context.md), [13](13-editable-fuzzy-picker-pruning.md).
- [ ] [15. Complete legacy cutovers and product scope](15-legacy-cutover-and-product-scope.md). Requires [01](01-data-ownership-and-migration.md), [02](02-command-context.md), [03](03-owned-execution.md), [04](04-command-catalog-and-lazy-boot.md), [05](05-managed-installation.md), [06](06-mcp-package-ownership.md), [07](07-safe-commit-planning.md), [08](08-pr-snapshots.md), [09](09-pr-actions-and-monitoring.md), [10](10-validation-recipes.md), [11](11-clipboard-artifacts-and-context.md), [12](12-recurring-job-outcomes.md), [13](13-editable-fuzzy-picker-pruning.md), [14](14-utility-and-profile-consolidation.md).
- [ ] [16. Prove the redesigned workflows end to end](16-end-to-end-acceptance.md). Requires [01](01-data-ownership-and-migration.md), [02](02-command-context.md), [03](03-owned-execution.md), [04](04-command-catalog-and-lazy-boot.md), [05](05-managed-installation.md), [06](06-mcp-package-ownership.md), [07](07-safe-commit-planning.md), [08](08-pr-snapshots.md), [09](09-pr-actions-and-monitoring.md), [10](10-validation-recipes.md), [11](11-clipboard-artifacts-and-context.md), [12](12-recurring-job-outcomes.md), [13](13-editable-fuzzy-picker-pruning.md), [14](14-utility-and-profile-consolidation.md), [15](15-legacy-cutover-and-product-scope.md).

## Coverage and cutover checkpoints

| Original proposal priority | Prompt coverage | Required outcome |
|---|---|---|
| 1. Data authority and safe migration | 01 | Every affected writer uses its canonical owner; reload preserves IDs, relationships, and recurrence; definition YAML is not retired |
| 2. Shared context and owned runs | 02–03 | Consistent directory/task decisions and accurate launch/exit/stop ownership |
| 3. Catalog, lazy startup, installation | 04–06 | Side-effect-free discovery, deterministic executable provenance, managed assets, existing MCP modules packaged |
| 4. Git/PR workflow rewrites | 07–09 | Planning preserves the Git index; shared qualified snapshots and single/bulk actions |
| 5. Manual handoffs and recurring work | 10–12 | Reliable validation/log evidence, artifact/context handoff, opt-in scheduled outcomes |
| Added picker-edit/prune requirement | 13 | Persistent literal, substring, regex, glob, and extglob exclusions with preview and restoration |
| 6. Utility/legacy consolidation | 14–16 | Real behavior preserved, superseded paths removed, complete isolated end-to-end verification |

Run a coherent checkpoint after each phase. Do not advance past failed acceptance criteria. The ordered prompts are intentionally separate so the current cutover cannot be called done merely because later scaffolding exists. Step 16 exercises the final workflows and fixes in-scope gaps; it does not introduce another architecture.

## Shared contracts between steps

```js
const contracts = {
	data: "one authoritative writer per kind of data",
	context: "selected task/app/directory with provenance and exact calling terminal",
	execution: "CommandSpecification and real result plus owned launch identity",
	commands: "one read-only candidate inventory used by dispatch and editing",
	pr: "repo-qualified snapshots with head revision, freshness, and completeness",
	picker: "stable item identities plus explicit persistent exclusion rules"
};
```

These describe responsibilities, not compulsory Ruby class names or signatures. Reuse existing types before adding anything. Later prompts consume the implemented earlier contracts, not parallel alternatives.

## Scope and safety

Keep Ruby, native tools, TaskCli, Herdr adoption, useful value objects, and native AI session behavior. The user has explicitly authorized completing steps 02–16, then renaming and publishing the new gem as `rehiiro` after final acceptance. This does not authorize Git pushes, changing the original checkout or installed commands, new worktrees, live-home installation, real GitHub/provider mutations, or destructive picker pruning.

The proposal includes installed-local extensions that are not in the clone. Step 06 names the existing MCP source locations; steps 12, 14, and 15 name other optional external evidence. Those files are read-only. If a required source is unavailable, report the precise prerequisite rather than fabricating a replacement.

After implementing a step, update only its checkbox and commit its code/docs/evidence together in the clone. Never mark a prompt complete during prompt authoring. See [the handoff rules](00-start-here.md#handoff).
