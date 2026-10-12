# 07. Index-preserving commit planning

Work ONLY in `/Users/unixsuperhero/proj/rehiiro`. Read [the shared contract](00-start-here.md) and [the commit-safety proposal](proposal.md#rebuild-pr-workflows-around-one-qualified-snapshot) first. Verify the implemented dependency below, inspect current source before editing, and execute only step 07. The work below is planned; source inspection does not prove the index-loss risk has been reproduced.

## Goal

Make commit inspection, AI planning, and dry-run leave the original Git index untouched. Validate complete, nonduplicated file assignment before mutation, preserve meaningful grouping, and stop immediately when staging or committing fails.

## Inputs

- [bin/h-git](../../bin/h-git), especially `snapshot_diff`, `changed_files`, `plan_commits`, `parse_plan`, and the commit handler.
- [Git](../../lib/hiiro/git.rb), [command execution values](../../lib/hiiro/shell.rb), [bin/h-commit](../../bin/h-commit), and [bin/h-sha](../../bin/h-sha).
- Existing conventions in [Git effects tests](../../test/hiiro/git_effects_test.rb) and [commit command tests](../../test/bin/commit_test.rb).
- [commit selector documentation](../../docs/h-commit.md), [README](../../README.md), and [CHANGELOG](../../CHANGELOG.md).

The snapshot helper stages all files and resets the real index before the dry-run branch. Coverage currently produces warnings, duplicate assignments are unchecked, staging failures are ignored, and commit failures do not stop subsequent groups. Preserve the existing concern-based grouping prompt and diff-truncation disclosure.

## Dependencies

Requires [03. Owned execution](03-owned-execution.md). Verify shell-safe argv, explicit cwd/environment, actual child exit status, stdin handling, and failure propagation. Reuse the implemented execution contract, not an independently invented executor or prescribed future Ruby signature.

## Work

1. Reproduce the planning risk in a disposable fixture repository containing staged and unstaged changes to the same file, another staged file, deletion, rename, and an untracked file. Record original index bytes and staged diff before and after the existing dry-run using a controlled planner executable.
2. Replace real-index snapshot mutation with read-only inspection or a disposable alternate index using `GIT_INDEX_FILE`. Seed it appropriately, capture tracked/untracked/deleted changes, and clean it on every outcome. Resolve the repository's actual index path rather than assuming `.git/index`. Never create a Git worktree.
3. Obtain exact paths through NUL-delimited Git output. Handle rename source/destination, whitespace, quotes, newlines, and option-like filenames without human-output parsing or shell interpolation. Preserve binary/deletion evidence and explain any intentional diff truncation.
4. Validate the planner's exit status, JSON shape, nonempty commit messages, file arrays, unknown paths, missing coverage, and repeated assignment both within and across groups. An invalid plan must fail before staging, not warn and skip files. Preserve logical-concern grouping and prerequisite ordering rather than substituting directory grouping.
5. Show the validated plan and honor existing confirmation/`--yes` behavior. Define execution's whole-file semantics explicitly, including partially staged files. Never silently consume unrelated staged content or discard a user's partial selection. Require explicit reviewed consent for whole-file inclusion, or stop when the staging intent cannot be preserved safely.
6. Execute each selected group with the step 03 contract and isolated staging where needed. Commit only the group, then reconcile only successfully consumed paths while preserving remaining user staging. Stop on the first add/commit failure. Report completed groups and the real failed operation without resetting, rollback commits, fallback catch-all commits, or continuing later groups. Detect relevant repository changes after planning before applying a stale plan.
7. Migrate all affected planning/execution callers, remove obsolete reset-based helpers and duplicate dry-run branches, and add deterministic consumer-visible regressions. Update command docs, README, and changelog with dry-run, confirmation, whole-file staging, and partial-failure guarantees.

## Acceptance criteria

- Planning, cancellation, malformed output, planner failure, and dry-run preserve original index bytes, staged selection, HEAD, and working files.
- Valid plans cover every changed file exactly once and retain useful concern-based groups.
- Execution never commits unrelated staged files; successful groups preserve remaining staging intent.
- Staging/commit failures return nonzero and prevent every later group from executing.
- Arguments and exact filenames survive without shell interpretation.

## Verification

Use only temporary standalone repositories and temporary HOME/DB/config/data roots. Run the real `h-git commit -n` with a deterministic planner process, then compare index bytes, staged diffs, HEAD, and working files. Run explicit execution on a valid two-group fixture and inspect actual commit contents. Reject missing/duplicate/unknown plans without mutation. Inject an add failure and a failing commit hook; expect nonzero status, accurate partial progress, and no later commits. Exercise unusual filenames and planner subprocess failure. Run scoped behavioral regressions in addition to these CLI/process smokes. No live AI provider is needed.

## Non-goals and safety

No Git worktrees, destructive Git commands, original-repository mutation, or installed-file edits. No live account operations. Keep Ruby and existing values. Do not redesign commit/SHA selectors here; their consolidation belongs to [14](14-utility-and-profile-consolidation.md). Preserve the existing in-process TUI design rather than adding curses or external fuzzy-finder delegation.

## Completion and handoff

After smoke proof, update only step 07 in [the index](README.md) and commit the complete step normally in the clone. Report staging policy, migrated callers, removed helpers, preserved state, exact observed checks, and commit. Leave the box unchecked for missing contracts or failed criteria. Next is [08](08-pr-snapshots.md) after its dependencies are verified; do not execute it automatically.

