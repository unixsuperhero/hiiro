# 01. Canonical data ownership and safe migration

Work ONLY in `/Users/unixsuperhero/proj/rehiiro`. Read [the shared contract](00-start-here.md), [the proposal](proposal.md#rewrite-data-ownership-before-adding-unattended-automation), and [the index](README.md) first. Verify the dependencies below, then execute only step 01. This is planned implementation work. Inspect current source before edits because the proposal predates some Table and Tui work.

## Goal

Give every durable data type one authority. Replace snapshot-wide mutations with targeted operations and make legacy imports explicit, ownership-aware, repeatable, and reversible without losing existing values.

## Inputs

- Persistence: [db.rb](../../lib/hiiro/db.rb), [todo.rb](../../lib/hiiro/todo.rb), [task_cli.rb](../../lib/hiiro/task_cli.rb), [tasks.rb](../../lib/hiiro/tasks.rb), [pin_record.rb](../../lib/hiiro/pin_record.rb), and [pins plugin](../../plugins/pins.rb).
- Consumers: [h-link](../../bin/h-link), [h-branch](../../bin/h-branch), [h-pane](../../bin/h-pane), [h-remind](../../bin/h-remind), [reminder.rb](../../lib/hiiro/reminder.rb), and [h-db](../../bin/h-db).
- Current contracts: [AGENTS.md](../../AGENTS.md), [RegistryEntry](../../lib/hiiro/registry.rb), [Table](../../lib/hiiro/table.rb), [TableScope](../../lib/hiiro/table_scope.rb), [TableActions](../../lib/hiiro/table_actions.rb), and [the TUI plan](../../docs/plans/hiiro-tui.md). The plan's unchecked items are not implemented APIs.
- Tests and docs: `test/hiiro/todo_test.rb`, `test/hiiro/table_test.rb`, `test/plugins/pins_test.rb`, `test/bin/t_test.rb`, [database docs](../../docs/h-db.md), [todo docs](../../docs/h-todo.md), and [task docs](../../docs/t.md).
- Optional external sources: none required. Original and installed-local files remain reference-only.

## Dependencies

None. Verify sandbox isolation and the actual clone state before starting.

## Work

1. Census durable readers and writers across `lib/`, `bin/`, and `plugins/`. Record each store's owner, identities, relations, configuration, and recovery inputs. Include `projects.rb`, `tags.rb`, `pinned_pr_manager.rb`, legacy task entrypoints, queue artifacts, and runtime files. Inventory unrelated artifact writers without redesigning their workflows.
2. Choose authority per type. Use SQLite for mutable domain records and existing RegistryEntry/Table for generic saved entries where appropriate. Preserve its `task_id`, tags, aliases, metadata, rename behavior, and TableScope semantics. Do not create another registry. Keep `services.yml`, `tools.yml`, sparse definitions, preferences, `tables.yml`, and ordinary prompt/artifact files as files.
3. Replace `TodoManager#save` table deletion/recreation and local ID allocation with database-owned IDs and targeted mutations. Migrate `t`, `tt`, and `h todo` together. Apply equivalent targeted operations to pins, pane homes, saved resources, and pinned-PR snapshots. A stale collection must not delete another writer's records.
4. Cut over reminder CRUD, bulk editing, pause/resume, recurrence checks, and cleanup together. Preserve interval, `once`, `trigger_at`, `last_triggered`, enabled state, and sound. Reuse Duration/TimeInput. Fix pin serialization so strings such as `"42"`, `"false"`, and JSON-looking text remain strings, distinct from numbers, booleans, and collections. Import both extensionless command-pin files and actual legacy `.yml` variants without guessing their types.
5. Replace broad YAML deletion in `h db migrate` with an explicit owned-store manifest and inspectable migration plan. Validate imports transactionally, report conflicts and rejected rows, verify semantic reloads, and record completion only after success. Repeated imports must neither duplicate nor overwrite newer canonical data silently. Preserve IDs, relationships, tags, task resources, and existing qualified PR identity. Keep recovery copies until verification; provide explicit export/recovery that refuses accidental overwrite and documents treatment of later writes.
6. Migrate configuration/edit commands that still present obsolete data YAML as authoritative. Delete dual-writers, silent database-error fallbacks, and obsolete snapshot APIs only after every affected caller uses the chosen owner. Update README, affected command docs, and CHANGELOG.

## Acceptance criteria

- Each durable type has a documented authority and no competing live writer.
- Interleaved targeted updates preserve unrelated records and stable IDs.
- Failed or conflicting imports leave recoverable sources and truthful completion state.
- Definitions, ordinary files, RegistryEntry relationships, pin types, and reminder recurrence survive reload and recovery.

## Verification

Use temporary HOME, config/data roots, and a file-backed `HIIRO_TEST_DB`; the existing test helper forces an in-memory DB and does not exercise real YAML migration. Add deterministic preservation regressions, including stale snapshots and interrupted/conflicting imports. Run scoped tests, then actual clone CLIs: create/list/update todos through both task and todo commands, mutate pins and links, and pause/resume reminders. Exercise migration, repeated import, and explicit recovery against disposable fixtures. Compare exact IDs, relations, typed values, and untouched definition-file bytes. Disable real notifications and never run providers.

## Non-goals and safety

No Git worktrees, live migrations, live account mutations, automatic installation, new language/framework, or universal storage engine. Do not move data roots to conceal ownership problems. Screens must reuse Hiiro::Tui::Screen/State/Pane, not curses or an external fuzzy finder.

## Completion and handoff

After real smoke proof, mark only step 01 complete in [the index](README.md) and commit the complete step in the clone. Report interfaces, migrated callers, preservation/recovery evidence, removed paths, exact checks and outcomes, and commit. Missing prerequisites leave the box unchecked. Next eligible step: [02](02-command-context.md); do not start it automatically.

