# 10. Reliable validation recipes and captured failures

Work ONLY in `/Users/unixsuperhero/proj/rehiiro`. Read [the shared contract](00-start-here.md) and [the proposal](proposal.md#automate-specific-manual-handoffs) first. Verify the implemented dependencies below, inspect current source before editing, and execute only step 10. This prompt describes planned work, not completed functionality.

## Goal

Make existing changed-file tools and configured validation recipes report their actual outcomes. Retain failure logs with the resolved task and directory context so an explicit queue handoff does not require copying terminal text. Extend `RunnerTool`, not a new task runner.

## Inputs

- `lib/hiiro/runner_tool.rb` owns tool configuration, change sets, extension filters, and variations. Its inspected implementation parses line-oriented Git output, substitutes space-joined `[FILENAMES]`, and returns true after ignoring child failures.
- `bin/h-js` runs four commands under `all` and saves failed buffered output. `bin/h-ch` contains personal build, migration-compatibility, signing, and application-home policy.
- `bin/h-capture`, `lib/hiiro/capture.rb`, and `lib/hiiro/shell.rb` contain capture records and execution values. Capture streams combined output to disk and forwards piped stdin. The inspected shell stream helper buffers all output and also prints chunks after teeing them.
- `lib/hiiro/queue.rb` supplies the queue handoff. Inspect its current entry and prompt contracts after step 03.
- Read [run documentation](../../docs/h-run.md), [queue documentation](../../docs/h-queue.md), [project instructions](../../AGENTS.md), and `test/hiiro/shell_test.rb`.

## Dependencies

- [02. Command context](02-command-context.md) must provide explicit task/app/cwd selection, provenance, and ambiguity errors.
- [03. Owned execution](03-owned-execution.md) must provide real launch, exit, interruption, and ownership outcomes, with bounded streaming and stdin handling.

Verify these outputs through current callers. Do not infer interfaces from proposal examples or accept index checkboxes as proof. Missing contracts block this step.

## Work

1. Trace every `RunnerTool` and stream/capture consumer. Reproduce the source risks with disposable repositories and fixture commands before changing behavior. Keep existing tool names, filters, variations, and user-authored definitions.
2. Resolve the operation context once. Use its explicit cwd for Git enumeration and each tool invocation, including calls from another directory. Parse filename-safe Git output with NUL delimiters and handle rename destinations and deleted paths deliberately. A Git failure must not become an empty successful change set.
3. Build argv commands using the implemented execution contract. Keep deliberately authored shell recipes distinct. Never interpolate unescaped filenames into shell text. Define safe `[FILENAMES]` expansion, option termination, and unsupported-template errors. Preserve existing configured recipes through an explicit configuration cutover rather than silently changing their meaning.
4. Define recipe ordering, continuation after failure, and aggregation in the existing configuration and runner. Report succeeded, failed, interrupted, and skipped commands distinctly. No matching tools, no matching files, invalid variation, and failed startup need documented outcomes. The CLI must exit nonzero when a selected command fails, even if a later command succeeds.
5. Reuse the step-03 disk-streaming path for capture and validation. Retain failed log artifacts plus command, cwd, run identity, timestamps, exit outcome, task association, and context provenance. Preserve binary/piped stdin and early child closure. Do not buffer unbounded output or print each chunk twice.
6. Migrate `h run`, `h js all`, relevant `h ch` execution, and `h capture` callers. Keep signing, migration compatibility, package changes, and build-product checks in personal adapters. Offer an explicit handoff that creates an existing queue prompt referring to the retained evidence. Recording a failure must not start an agent.
7. Remove replaced execution/log-writing paths after callers migrate. Add deterministic consumer-visible regressions and update README, command documentation, and CHANGELOG.

## Acceptance criteria

- Unusual filenames arrive as exact arguments in the correct cwd without shell execution.
- Mixed success/failure recipes expose per-command results and a truthful aggregate exit.
- Failed logs survive reload with their context; explicit queue handoff preserves that association.
- Capture keeps streaming, stdin, interruption evidence, and actual child status.

## Verification

Run relevant focused tests, including `ruby -Ilib -Itest test/hiiro/shell_test.rb`, plus the added runner/capture regressions. In sandboxed HOME, DB, and config/data roots, run the actual `h run`, `h js all`, and `h capture` entrypoints against fixture executables. Exercise filenames containing spaces, quotes, newlines, leading hyphens, and shell metacharacters. Observe exact argv/cwd, an early nonzero command followed by success, retained failure logs, and an explicit queue entry. Pipe a binary fixture through capture and compare bytes. Exercise a large stream and interruption; observe bounded retention and no duplicated output. Use a fixture application/build adapter, not real signing or migration.

## Non-goals and safety

No Git worktrees, new language/framework, universal runner, permission bypass, live migrations, or provider/account mutations. The original repository and installed local files are reference-only. Never run against live HOME/DB/config or invoke an agent automatically. Any new UI requesting a filesystem path must use a native OS picker or save dialog.

## Completion and handoff

Require actual CLI and artifact proof, not only tests. Mark only step 10 in [the index](README.md), then commit the complete code/docs/index change in the clone. Report exact commands, observed exits and log/queue state, preserved configuration, removed paths, and commit ID. If blocked, leave the checkbox unchecked and name the missing prerequisite. Identify [step 11](11-clipboard-artifacts-and-context.md) as next eligible after its prerequisites are verified; do not start it.

