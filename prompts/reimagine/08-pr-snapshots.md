# 08. Repository-qualified PR snapshots

Work ONLY in `/Users/unixsuperhero/proj/rehiiro`. Read [the shared contract](00-start-here.md) and [the PR snapshot proposal](proposal.md#rebuild-pr-workflows-around-one-qualified-snapshot) first. Verify the implemented dependencies below, inspect current source before editing, and execute only step 08. The proposed snapshot contract is planned work, not an existing Ruby API.

## Goal

Finish repository-qualified PR identity throughout persistence, checks, dependencies, and refresh. Provide one batched refresh contract with head revision, fetch time, check/review completeness, and stale/unknown state. Keep remote observations separate from local tracking preferences.

## Inputs

- [PullRequestReference and RepositoryIdentity](../../lib/hiiro/pull_request_reference.rb), [CheckSummary](../../lib/hiiro/check_summary.rb), [PinnedPr](../../lib/hiiro/pinned_pr.rb), [PinnedPRManager](../../lib/hiiro/pinned_pr_manager.rb), [CheckRun](../../lib/hiiro/check_run.rb), and [Git::Pr](../../lib/hiiro/git/pr.rb).
- [bin/h-pr](../../bin/h-pr), [DB import callers](../../lib/hiiro/db.rb), and [tag storage](../../lib/hiiro/tags.rb).
- [reference tests](../../test/hiiro/pull_request_reference_test.rb), [check-summary tests](../../test/hiiro/check_summary_test.rb), [PR tests](../../test/hiiro/git/pr_test.rb), [PR docs](../../docs/h-pr.md), and [CHANGELOG](../../CHANGELOG.md).

Batch fetch already groups repositories and paginates checks backward beyond 100 nodes. Other paths still find/delete by number, allow nil-repository matches, store checks by number, and coerce dependencies to integers. Reviews fetch only the last 50 nodes. Freeze overrides currently change raw observed contexts.

## Dependencies

Requires [01. Data ownership and migration](01-data-ownership-and-migration.md) and [03. Owned execution](03-owned-execution.md). Verify authoritative targeted mutations, safe migration/recovery, qualified identity preservation, and argv/status-aware remote execution. Reuse their implemented contracts; missing outputs block this step.

## Work

1. Census identity use in models, import/export, resolvers, tracking/untracking, checks, tags, filters, editors, and dependency commands. Preserve slot versus PR-number semantics. Qualify bare numbers through explicit repository context; reject ambiguity instead of guessing a personal default repository.
2. Extend existing identity values rather than adding equivalents. Migrate persistent keys, check associations, and dependency references with step 01's migration contract. Derive legacy identity from trustworthy repo/URL evidence. Preserve unresolved rows and report conflicts rather than attaching them to an arbitrary same-number PR. Preserve IDs, tags, task associations, slots, and recovery inputs.
3. Define a remote snapshot containing the qualified reference, `headSha`, successful fetch time, raw checks/reviews, completeness for each, and refresh outcome/freshness. Distinguish known-empty results from unknown or incomplete results. Keep local tags, task preferences, monitoring preferences, and dependencies under separate mutation ownership.
4. Consolidate single/bulk refresh on the repository-batched fetch path. Fetch head revision and paginate reviews as well as checks, retaining existing check pagination. Handle repeated cursors, failed pages, malformed output, and partial GraphQL errors without claiming completeness. Do not combine pages from different head revisions into a passing snapshot.
5. Preserve the last successful observation after refresh failure and expose stale/unknown explicitly. Apply remote fields through targeted updates only. An older loaded collection must not erase a concurrent local tag/task change, unrelated PR, or newer snapshot. Remove whole-collection replacement callers after migration.
6. Preserve the ISC freeze policy as a derived assessment. Keep GitHub's raw observed contexts unchanged and distinguish policy evaluation from remote evidence. Incomplete, stale, or unknown checks/reviews must never become merge-ready evidence, even when fetched successes have no failures.
7. Migrate all consumers, including `CheckRun` and DB import callers, dependency add/remove/list, and `h-pr` display/filter paths. Correct obsolete table/query paths encountered in this cutover. Remove superseded number-only internal APIs once callers migrate. Add deterministic data-preservation/completeness regressions and update PR docs, README, and changelog.

## Acceptance criteria

- Two repositories containing PR 42 remain distinct through pin, refresh, tags, checks, dependencies, and unpin.
- Snapshots retain head revision, fetch time, complete versus partial reviews/checks, and failure freshness.
- Failed/partial refresh cannot become passing eligibility or erase local preferences.
- Raw remote data remains unchanged by freeze policy.
- Legacy ambiguity is retained and reported without destructive guessing.

## Verification

Use temporary HOME and isolated DB/config/data roots with a controlled `gh` executable. Run actual track/update/list/check-detail/dependency/unpin commands for same-number PRs in two repositories. Supply more than 100 checks and 50 reviews, then fail a later page and change a head between pages. Expect qualified isolation, complete successful pagination, explicit incomplete/stale output, and no passing eligibility from partial evidence. Change a local tag/task association between refresh read and write; inspect persistence to prove it survives. Reload migrated legacy fixtures and compare identities, links, and raw freeze contexts. Run scoped regressions as additional proof.

## Non-goals and safety

No Git worktrees, live GitHub mutations, real merges, live DB migration, or original/installed-file edits. Keep Ruby, existing value objects, native tools, and the current TUI/table design. Do not replace an in-process screen with curses or a fuzzy-finder subprocess. Actions and continuous monitoring belong to step 09; no universal remote-state engine.

## Completion and handoff

After smoke proof, update only step 08 in [the index](README.md) and commit the complete cutover. Report snapshot/persistence contracts, migrated callers, retained ambiguous data, removed paths, exact observed checks, and commit. Missing contracts leave the checkbox unchecked. Next is [09](09-pr-actions-and-monitoring.md) after dependency verification; do not start it automatically.

