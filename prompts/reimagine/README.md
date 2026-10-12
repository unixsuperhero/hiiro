# Reimagining Hiiro: implementation prompt index

This prompt set describes how to implement the design in [the proposal snapshot](proposal.md). It lives in the independent clone at `/Users/unixsuperhero/proj/rehiiro`; the original Hiiro checkout and installed commands remain unchanged.

## Current status

- Workspace and prompt set prepared.
- Step 01 is implemented and verified. Steps 02–16 remain unchecked and have not started.
- Clone baseline: `139aa0143644d73c257edb810bd8afef88ba39a8`, source branch `main`.
- The clone's `origin` is the local original repository. Do not push, publish, install, or change that remote automatically.

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

- [ ] [02. Consistent task, app, and directory context](02-command-context.md). Requires [01](01-data-ownership-and-migration.md).
- [ ] [03. Owned process and terminal execution](03-owned-execution.md). Requires [01](01-data-ownership-and-migration.md), [02](02-command-context.md).

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

Keep Ruby, native tools, TaskCli, Herdr adoption, useful value objects, and native AI session behavior. Do not rename the gem merely because this checkout is named rehiiro. Do not create Git worktrees, install into the live home, mutate real GitHub/provider data, or let picker pruning delete resources.

The proposal includes installed-local extensions that are not in the clone. Step 06 names the existing MCP source locations; steps 12, 14, and 15 name other optional external evidence. Those files are read-only. If a required source is unavailable, report the precise prerequisite rather than fabricating a replacement.

After implementing a step, update only its checkbox and commit its code/docs/evidence together in the clone. Never mark a prompt complete during prompt authoring. See [the handoff rules](00-start-here.md#handoff).
