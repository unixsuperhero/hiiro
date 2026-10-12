# Hiiro TUI plan

One engine, `Hiiro::Tui` in `lib/hiiro/tui.rb`, grown from a list screen into a small screen toolkit. The first product on it is `h table`, a TUI over every arbitrary key/value list hiiro keeps. Tailored screens for tasks, projects, and tuios follow on the same toolkit. Decided 2026-10-12 after a three-engine prototype (Hiiro::Tui, curses, fzf); the prototype and its captures are throwaway and are not in this repo.

## How to read this

One box is one unit of work with the evidence that checks it. Each PR is verified two ways. Unit tests run under `ENV['HIIRO_TEST_DB'] = 'sqlite::memory:'`. The live check launches the real surface in a tuios window, drives it with `tuios send-keys` and `tuios send-text`, and saves `tuios capture-pane` output per step. Tests alone do not verify a PR.

## Vocabulary

- **table**. One named list of entries. Stored as `registry.resource_type`. `h table links` shows the `link` table.
- **entry**. One row. `{ table, name, value, short, desc, meta, tags, task }`.
- **scope**. `{ mode: :global }` or `{ mode: :task, task: TaskRecord }`. Task scope shows entries whose `task_id` is the current task. One key toggles it.
- **action**. A per-table command template keyed by a letter. `{ link: { o: "open {value}", y: "pbcopy <<< {value}" } }`. Lives in `~/.config/hiiro/tables.yml` with a global default of open and copy.

## Prerequisite

- [ ] Fix line 24 of `~/.config/hiiro/sounds.yml` (`tinkbasso: : /System/...`). The file fails YAML parsing until then.

## PR 1. Grow Hiiro::Tui into a screen toolkit

**Files.** Edit `lib/hiiro/tui.rb`. Create `test/hiiro/tui_test.rb`.

**Build.**
- [x] `Tui::Screen` owns `{ mode: :list | :search | :pick, cursor, top, query, message }` as one state object. No scattered booleans.
- [x] `Tui::Pane` renders a rectangle of lines. A screen composes a list pane, an optional detail pane, a header, and a status line.
- [x] Modal input. `/` enters search and edits `query` until Enter or Escape. A trigger character (default `@`) enters pick mode and filters a candidate list in the status line.
- [x] A key map is a table `{ 'j' => :down, 'k' => :up, ... }` on the screen class, not a `case` in `handle_key`.
- [x] `ListScreen` keeps its current public shape and becomes a `Screen` with no detail pane. `bin/h-obsidian` keeps working unchanged.

**You see.** A screen with a list on the left, a detail pane on the right, a search prompt in the status line, and the `@` candidates in the status line.

**Verify, unit.** Done 2026-10-12, 12 runs 41 assertions. Render to a string with `LINES` and `COLUMNS` set and feed keys from an array. Assert the rendered lines literally. Run `ruby -Ilib -Itest test/hiiro/tui_test.rb`.

**Verify, live.** Done 2026-10-12 in a tuios window, captures kept in the session scratch dir. A scratch script that renders twenty fake rows in a tuios window. Capture after open, after `j` three times, after `/jel` Enter, after `@so` Enter. Each capture shows the expected row highlighted.

## PR 2. Table model and scope

**Files.** Edit `lib/hiiro/registry.rb`, `lib/hiiro/tags.rb`. Create `lib/hiiro/table.rb`, `lib/hiiro/table_scope.rb`, `test/hiiro/table_test.rb`.

**Build.**
- [x] Add nullable `task_id` to `registry` with a migration in `RegistryEntry.migrate!`.
- [x] `Hiiro::Table` wraps one `resource_type`. `Table.all`, `Table.named(name)`, `table.entries(scope:)`, `table.rename(new_name)`, `table.add(name, value, ...)`.
- [x] `RegistryEntry` gains `tags` through `Hiiro::Tag` with `taggable_type 'RegistryEntry'`, plus `tag(name)` and `untag(name)`.
- [x] `Hiiro::TableScope.current` resolves through `CurrentTask`. `toggle` flips mode. The value object is the only place that knows what task scope means.
- [x] `Hiiro::TableActions` loads `tables.yml`, merges defaults, and answers `for(entry)` as `{ letter => command }` and `run(letter, entry)`.

**Verify, unit.** Done 2026-10-12, 21 runs 48 assertions. Add two entries in two tables, tag one, set a task on one. Assert `entries(scope: task)` returns exactly one and `entries(scope: global)` returns both. Assert `rename` moves every row.

**Verify, live.** Done 2026-10-12 against a throwaway sqlite file via `HIIRO_TEST_DB`, since `h table add` arrives in PR 4. `h db q "select resource_type, name, task_id from registry"` after `h table add link gh https://github.com` shows the row.

## PR 3. Move the key/value stores into registry tables

Surveyed 2026-10-12 before starting: links and projects already lived in their own SQLite tables (`links`, `projects`) with YAML files kept only as dual-write backups, pins had a `pins` table plus a `pins/h-sha` file the old importer never read, and `yt.yml` is state for `~/bin/h-yt` outside this repo. The PR therefore lands as three slices, each verified and committed on its own, and leaves `yt.yml` alone.

**Files.** Edit `lib/hiiro/db.rb`, `plugins/pins.rb`, `lib/hiiro/task_cli.rb`, `lib/hiiro/current_task.rb`, `bin/h-link`, `lib/hiiro/link.rb`, `lib/hiiro/projects.rb`, `bin/h-project`. Delete `lib/hiiro/pin_record.rb`. Create `test/hiiro/table_import_test.rb`.

**Build.**
- [x] 3a. `DB.import_tables!` runs at every startup and inserts a row only when its (table, name) is absent. The `pins` table rows, every `pins/*` file (any extension, `h-` prefix stripped), and `sounds.yml` become tables named after the command plus `sound`. Files are renamed `.bak`. The `pins` table itself stays until the installed gem is republished, because the old library recreates and reads it. Drop it afterwards with `h db q "drop table pins"`.
- [x] 3a. `PinRecord` deleted. `t use` and the pinned current task read and write table `t`, entry `current_task`. The Pins plugin (loaded by fifteen bins) stores pins in the table named after its bin and no longer writes YAML.
- [x] 3b. `bin/h-link` reads and writes table `link` (url to value, shorthand to short_name, description, created_at kept for the numbered order). The 10 `links` rows and their tags are imported once; `Hiiro::Link` is deleted and `URLTemplate` stays. `links.yml` dual-write stops.
- [x] 3c. `Hiiro::Projects` reads table `project`. The `projects` row and the `ane` alias still in `projects.yml` are imported once. `h project config` edits the table through the YAML edit helper.

**Verify, unit.** 3a done 2026-10-12: table_import_test 2 runs 13 assertions, pins_test 8 runs, current_task_test 3 runs, all green; full suite shows only the six pre-existing failures.

**Verify, live.** 3a done 2026-10-12 on the real database after backing it up to `hiiro.db.pre-tables-20261012-020244.sqlite`: 17 registry rows across `sha`, `sound`, `t`; `pins/h-sha` and `sounds.yml` renamed `.bak`; `t current` still prints the pinned task. 3b done 2026-10-12 on the real database after backing it up to `hiiro.db.pre-links-20261012-021156.sqlite`: 10 rows in table `link` with created_at kept; `h link ls` and `h link list` byte-identical to the golden output captured before any change. 3c done 2026-10-12 after backing up to `hiiro.db.pre-projects-20261012-021647.sqlite`: `h project ls` identical except for the newly imported `ane` alias and a directory created after the golden was captured.

## PR 4. `h table`

**Files.** Create `bin/h-table`, `docs/h-table.md`, `test/bin/h-table_test.rb`. Edit `README.md`.

**Build.**
- [x] `h table` with no arguments opens the TUI across all tables in the current scope. `h table <name>` opens one table.
- [x] Keys. `j k` move. `/` search. `@` pick a table. `g` toggle scope. `o y` and any letter from the table's actions. `a` add. `r` rename entry or, on the header, the table. `e` edit value. `d` delete. `T` tag. Space marks. A marked set receives `d`, `T`, and `m` (move to another table) as bulk actions.
- [x] CLI twins for scripts. `ls [table]`, `add <table> <name> <value>`, `rm`, `mv <table> <new>`, `set`, `tag`, `untag`.
- [x] `h registry` keeps working and is documented as the same data under the old name.

**You see.** The screen from PR 1 filled with real tables, a status line reading `scope:task(@NAME)` after `g`, and `would run` replaced by the real command.

**Verify, unit.** Done 2026-10-12: table_screen_test 16 runs, bin table_test 13 runs, tui_test 18 runs, all green; full suite shows only the six pre-existing failures. `Hiiro::TestHarness` tests for every CLI twin with literal expected output.

**Verify, live.** Done 2026-10-12 in tuios windows: the seven read-only steps on the real database, then add, rename, mark two, bulk tag, bulk delete, and a custom `x` action on a database copy with a throwaway HOME, each confirmed in the status line and with `h db q`. Pressing `g` with no resolvable task now reports `no current task to scope to`. Drive the seven steps from the prototype (open, move, search, toggle scope, pick table, run action, quit) in a tuios window and keep the captures. Then drive add, rename, bulk tag, and bulk delete, and confirm each with `h db q`.

## PR 5. Tasks screen

Built 2026-10-12 per `docs/plans/tasks-screen.md`. `t ui` renders the task tree with subtasks, a detail pane with todos and next action, and keys for start, switch, and open in tuios. Reuses `Tui::Screen`, `TableScope`, and the key map pattern. Planned in its own one page document after PR 4.

## PR 6 and 7. Projects screen and tuios screen

Same rule as PR 5. Each gets its own one page plan after PR 4 ships.

## PR 8. Trigger-character autocomplete

`Tui::LineEditor` with a table of trigger characters to candidate sources, so `@` offers projects and worktrees and `#` offers tags inside any text input. Planned after PR 4, when the real inputs exist.

## Alternatives rejected

- **fzf as the engine.** Best search and picker for the least code, and the nested `@` picker worked. Rejected for the flat single-list model, ctrl-only keys, and state that lives in a file between keypresses, which raced once during the prototype.
- **curses gem.** Easiest two-pane layout. Rejected as a native dependency that was missing for Ruby 3.3.10 and needed `TERM` set under a daemon-spawned window.
- **skim anywhere action keys matter.** skim 2.0.2 never reported `--expect` keys in the prototype. `Hiiro::Fuzzyfind` prefers sk today; any picker that needs action keys should use fzf or Hiiro::Tui.

## Risks

- `CurrentTask` resolves through Herdr env, directory, or the pinned task. It does not read `TUIOS_*` variables yet. PR 2 uses it as is and notes the gap. A tuios pane to task mapping is its own change.
- The live checks need the tuios daemon. In CI they are skipped and the PR is not considered verified until someone runs them locally.
