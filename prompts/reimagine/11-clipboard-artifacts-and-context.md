# 11. Shared clipboard artifacts and context handoff

Work ONLY in `/Users/unixsuperhero/proj/rehiiro`. Read [the shared contract](00-start-here.md) and [the proposal](proposal.md#automate-specific-manual-handoffs) first. Verify the implemented dependencies below, inspect current source before editing, and execute only step 11. Everything requested here is planned implementation work.

## Goal

Read clipboard content and create a real artifact once, returning its path and type for explicit bundle or task attachment. Preserve the different purposes of the saved inbox, named notes, and context manifests. Make saved-information selection, opening, and copying consistent without replacing native indexes or URI schemes.

## Inputs

- `bin/h-save` handles image-first clipboard detection, collision-safe text/image inbox files, and `HIIRO_SAVED_DIR`. `bin/h-img` handles PNG capture and MIME/base64 output.
- `bin/h-context` owns ordinary path manifests, named bundles, text/image capture, and `@path` context copying. `bin/h-note` has a separate named-note destination policy.
- `lib/hiiro/input_file.rb` already supplies `InputFile` and `EditedDocument`, including original/result text, parsed content, and parse errors.
- `lib/hiiro/task_record.rb` and `lib/hiiro/task_cli.rb` contain task resources and deduplicated attachment. `lib/hiiro/extractor.rb` supplies existing extraction behavior.
- `lib/hiiro/link.rb` and `bin/h-link` handle bookmarks and URL templates. `bin/h-obsidian` preserves vault-relative paths and `obsidian://` links. `bin/h-docs` reads Portfolio items through its API and separates source paths from document URLs.
- Read [save docs](../../docs/h-save.md), [image docs](../../docs/h-img.md), [link docs](../../docs/h-link.md), [task docs](../../docs/t.md), and [project instructions](../../AGENTS.md). Inspect `test/bin/save_test.rb`, `test/bin/link_test.rb`, and `test/hiiro/input_file_test.rb`.

## Dependencies

- [01. Data ownership](01-data-ownership-and-migration.md) must establish authoritative resource/bookmark writers and preserve existing IDs and associations.
- [02. Command context](02-command-context.md) must resolve explicit destination task and directory without first-match guesses.
- [03. Owned execution](03-owned-execution.md) must expose truthful adapter outcomes and preserve stdin and native interaction.

Read their implemented contracts. Missing outputs block this step; checkbox state alone is insufficient.

## Work

1. Trace capture and attachment callers before choosing a small shared artifact operation. Keep destination policy in the inbox, note, and bundle commands. Return an existing absolute path and accurate content type only after a successful write; do not mandate a new Ruby signature from the proposal.
2. Consolidate clipboard text/image adapters and temporary-file ownership. Preserve explicit text arguments, image-first inbox behavior, text bytes, image bytes, MIME output, and collision protection. Distinguish an empty clipboard, missing image tool, adapter failure, and failed destination write. Do not silently capture text when an explicitly requested image fails.
3. Migrate `h save`, `h img`, `h context`, and `h note` to that operation. Preserve named-note roots and context-manifest intent instead of routing all commands into one folder. Define overwrite behavior explicitly and avoid accidental replacement of existing files.
4. Add an explicit capture-and-attach flow using the returned artifact, not a second clipboard read. Reuse canonical task resource mutation and context path normalization. Repeating the attachment must create one association per destination. Report capture success separately from attachment failure and retain the artifact for recovery. Missing or ambiguous task context must not select another task.
5. Reuse `InputFile` and `EditedDocument` wherever these flows edit metadata or manifests. Reject invalid edits without replacing saved data. Preserve edited text and the parse/write error for recovery rather than deleting the only copy or treating invalid input as an empty document.
6. Share selection/action conventions across bookmarks, Obsidian, and Portfolio. Return original records using stable identities, never parse decorated labels. Preserve exact/unique resolution, cancellation, explicit multi-target actions, URL templates, vault-native URIs, and Portfolio API identity. Add or align select/open/copy behavior through existing adapters without a common datastore or Portfolio reindexer.
7. Migrate affected callers, then remove duplicate capture and attachment implementations. Cover uncertain boundaries with deterministic behavior tests. Update README, affected command docs, and CHANGELOG.

## Acceptance criteria

- A capture produces one readable artifact with the correct bytes, path, and type.
- Explicit bundle/task attachment occurs once and does not change task completion state.
- Inbox, named-note, and context destinations retain their existing meanings.
- Invalid edits and failed attachments preserve recoverable content.
- Selection opens/copies the intended original item despite duplicate display titles.

## Verification

Run focused save, link, and input-file tests with isolated stores. Launch actual capture commands under temporary HOME/DB/config/data roots using controlled clipboard executables, not the personal clipboard. Save text and PNG fixtures, inspect bytes and returned paths, attach twice, reload the manifest and task resources, and observe one association. Exercise empty clipboard, failed write, invalid edit, and failed attachment. Drive a real saved-information picker with duplicate titles and cancellation. Use a local Portfolio fixture API and an opener/copy recorder to verify exact HTTP and Obsidian targets without launching accounts. If a UI asks for a file/folder/output path, exercise the native OS picker or save dialog, including cancellation.

## Non-goals and safety

No Git worktrees, new language/framework, universal artifact store, live account mutations, or native-index replacement. Original repository and installed files are reference-only. Sandbox HOME, DB, config, and data roots. Never mutate the personal clipboard, vault, Portfolio service, or task store during smoke checks. Do not turn capture or selection into deletion or automatic agent execution.

## Completion and handoff

Record actual CLI/picker output and persisted artifact/association proof. Mark only step 11 in [the index](README.md) and commit the complete step after smoke verification. Report preserved destinations, migrated consumers, removed duplicate paths, exact checks/outcomes, and commit ID. Missing prerequisites leave the box unchecked. Name [step 12](12-recurring-job-outcomes.md) as next eligible only after all its required outputs exist; do not execute it.

