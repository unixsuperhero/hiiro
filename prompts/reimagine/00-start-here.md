# Shared execution contract

These are implementation prompts for the independent rehiiro clone. Authoring this prompt set did not execute any redesign step.

## Workspace and source

- Work only in `/Users/unixsuperhero/proj/rehiiro`. The original `/Users/unixsuperhero/proj/hiiro` and installed `~/bin` commands are reference-only unless the user separately authorizes changes there.
- The initial clone contains committed source at `139aa0143644d73c257edb810bd8afef88ba39a8`, from source branch `main`. It is an independent Git clone, not a worktree or shared object store.
- Keep the cloned project/gem name Hiiro unless the user explicitly asks to rename it. The directory name rehiiro identifies the redesign workspace, not a new product name.
- Read [the proposal snapshot](proposal.md), [the prompt index](README.md), and applicable project instructions before implementing. Source findings are a snapshot; inspect the current code before each edit.
- Existing behavior and the user's data are the baseline. Keep Ruby, TaskCli, Herdr adoption, useful domain values, native tools, native agent history, and deliberately useful shortcuts.
- The historical proposal predates some current table/TUI work. Preserve the existing `Table`, `RegistryEntry` task IDs/tags, `TableScope`, and `TableActions`. Reuse the existing `Hiiro::Tui::Screen`, `State`, and `Pane` engine for in-process screens; do not introduce curses or shell out to a fuzzy finder for a screen. Consult the cloned project instructions and [the TUI plan](../../docs/plans/hiiro-tui.md), but do not execute its unrelated future PRs as part of these prompts.

## Execution and dependency rules

Execute one numbered prompt at a time in index order. Read its prerequisite prompts and verify their implemented contracts before starting; a checked box alone is not proof. If a prerequisite is absent, report the exact missing contract rather than inventing a substitute or silently executing other steps.

For a multi-file implementation, settle module interfaces and shared state ownership, then delegate genuinely independent slices. Keep each slice end-to-end and verifiable. Do not build empty infrastructure for a later step. Reuse the current symbols and files where possible; the proposal's example hashes are explanatory data, not mandated Ruby APIs.

Read external installed-local sources only when a prompt names them. Missing MCP support belongs to step 06. Do not claim a missing upstream file is absent everywhere, or fabricate its implementation. If external sources cannot be reached, finish reachable work and state the exact blocker.

## Safe development

- Never create Git worktrees. Temporary disposable repositories are acceptable for Git behavior checks; they are not linked worktrees.
- Never reset, amend, clean, force-push, publish, or overwrite user-owned files as part of these prompts. Do not change remotes or install into live bins/plugins automatically.
- Keep commits in the clone's integration branch. Commit only the current step's intended files with a normal change-description message. Do not push without a separate request.
- Do not run Hiiro against the live home for smoke checks. Hiiro can initialize/migrate stores and record invocations before dispatch. Use a temporary HOME, isolated database and config/data roots, and controlled external adapters.
- Do not read private credentials, migrate live data, merge PRs, launch providers, truncate databases, or run recurring jobs against real accounts during verification.
- Navigation, selection, capture, monitoring, and pruning must not silently create worktrees or mutate Git state. Destructive domain operations remain explicit.
- Any UI requesting a local file/folder/output path must use the appropriate native OS picker or save dialog. A text field alone is insufficient.
- Background refresh must preserve the user's query, focus, scroll, and selections. It must not reset the current page or picker.

## Verification and complete cutovers

Reproduce source-reported risks in isolated fixtures before fixing them, rather than presenting source inference as observed failure. Permanent regression tests should cover consumer-visible behavior, state transitions, boundaries, and data preservation. Do not add source-text, registration-only, forwarding, or mock-echo tests.

Run the actual changed CLI/workflow in a sandbox, and inspect its output and persistent state. Use a real interactive picker for picker changes. Unit tests and Ruby syntax checks are necessary where appropriate, but are not the whole proof. Preserve piped stdin, binary data, exit status, streamed output, and native interactive behavior.

Migrate every affected caller to the selected contract, then delete the implementation made obsolete by that cutover. Deliberate aliases can remain over one canonical implementation. Do not leave indefinite fallback stores, compatibility engines, stubs, empty handlers, or deferred work that belongs to this step. Retain unrelated code and any still-required legacy importer until its data-preservation contract is proved.

Update README/command docs and the changelog when behavior changes. Do not claim a smoke run happened unless its actual output was observed. Remove throwaway verification scripts after recording evidence unless the smallest rerunnable checker belongs in the maintained project.

## Handoff

After completing and verifying a numbered step, mark only that step complete in [the index](README.md) and include that update in the step's commit. Report:

1. The implemented interface and affected consumers.
2. Data/config preserved and obsolete paths removed.
3. Exact checks run and observed outcomes.
4. The commit and any concrete blocker.
5. The next eligible prompt, without starting it automatically.

If the step is blocked or incomplete, leave its box unchecked. Do not label a scaffold or a narrowed subset complete.
