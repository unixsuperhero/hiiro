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
- [ ] `Tui::Screen` owns `{ mode: :list | :search | :pick, cursor, top, query, message }` as one state object. No scattered booleans.
- [ ] `Tui::Pane` renders a rectangle of lines. A screen composes a list pane, an optional detail pane, a header, and a status line.
- [ ] Modal input. `/` enters search and edits `query` until Enter or Escape. A trigger character (default `@`) enters pick mode and filters a candidate list in the status line.
- [ ] A key map is a table `{ 'j' => :down, 'k' => :up, ... }` on the screen class, not a `case` in `handle_key`.
- [ ] `ListScreen` keeps its current public shape and becomes a `Screen` with no detail pane. `bin/h-obsidian` keeps working unchanged.

**You see.** A screen with a list on the left, a detail pane on the right, a search prompt in the status line, and the `@` candidates in the status line.

**Verify, unit.** Render to a string with `LINES` and `COLUMNS` set and feed keys from an array. Assert the rendered lines literally. Run `ruby -Ilib -Itest test/hiiro/tui_test.rb`.

**Verify, live.** A scratch script that renders twenty fake rows in a tuios window. Capture after open, after `j` three times, after `/jel` Enter, after `@so` Enter. Each capture shows the expected row highlighted.

## PR 2. Table model and scope

**Files.** Edit `lib/hiiro/registry.rb`, `lib/hiiro/tags.rb`. Create `lib/hiiro/table.rb`, `lib/hiiro/table_scope.rb`, `test/hiiro/table_test.rb`.

**Build.**
- [ ] Add nullable `task_id` to `registry` with a migration in `RegistryEntry.migrate!`.
- [ ] `Hiiro::Table` wraps one `resource_type`. `Table.all`, `Table.named(name)`, `table.entries(scope:)`, `table.rename(new_name)`, `table.add(name, value, ...)`.
- [ ] `RegistryEntry` gains `tags` through `Hiiro::Tag` with `taggable_type 'RegistryEntry'`, plus `tag(name)` and `untag(name)`.
- [ ] `Hiiro::TableScope.current` resolves through `CurrentTask`. `toggle` flips mode. The value object is the only place that knows what task scope means.
- [ ] `Hiiro::TableActions` loads `tables.yml`, merges defaults, and answers `for(entry)` as `{ letter => command }` and `run(letter, entry)`.

**Verify, unit.** Add two entries in two tables, tag one, set a task on one. Assert `entries(scope: task)` returns exactly one and `entries(scope: global)` returns both. Assert `rename` moves every row.

**Verify, live.** `h db q "select resource_type, name, task_id from registry"` after `h table add link gh https://github.com` shows the row.

## PR 3. Migrate the YAML stores into registry

**Files.** Edit `lib/hiiro/db.rb`, `bin/h-link`, `lib/hiiro/link.rb`, `bin/h-notify` (sounds), `lib/hiiro/projects.rb`, `bin/h-sha` (pins). Create `test/hiiro/table_migration_test.rb`.

**Build.**
- [ ] One idempotent import in `DB.setup!`, beside the existing YAML to SQLite import. `links.yml` becomes table `link`. `sounds.yml` becomes `sound`. `projects.yml` becomes `project`. Each `pins/<command>` file becomes a table named after the command. `yt.yml` becomes `yt`.
- [ ] Rewrite each reader to go through `Hiiro::Table`. Keep every CLI's output shape.
- [ ] Delete the YAML readers and the `pins` table in the same PR. Rename the YAML files to `.bak` on import, matching the existing migration.

**Verify, unit.** Import a fixture set of the five files into the in-memory DB and assert the row count per table.

**Verify, live.** Record `h link ls` before the change. Run it after. `diff` is empty. `h db q "select resource_type, count(*) from registry group by 1"` lists five tables with the expected counts.

## PR 4. `h table`

**Files.** Create `bin/h-table`, `docs/h-table.md`, `test/bin/h-table_test.rb`. Edit `README.md`.

**Build.**
- [ ] `h table` with no arguments opens the TUI across all tables in the current scope. `h table <name>` opens one table.
- [ ] Keys. `j k` move. `/` search. `@` pick a table. `g` toggle scope. `o y` and any letter from the table's actions. `a` add. `r` rename entry or, on the header, the table. `e` edit value. `d` delete. `T` tag. Space marks. A marked set receives `d`, `T`, and `m` (move to another table) as bulk actions.
- [ ] CLI twins for scripts. `ls [table]`, `add <table> <name> <value>`, `rm`, `mv <table> <new>`, `set`, `tag`, `untag`.
- [ ] `h registry` keeps working and is documented as the same data under the old name.

**You see.** The screen from PR 1 filled with real tables, a status line reading `scope:task(@NAME)` after `g`, and `would run` replaced by the real command.

**Verify, unit.** `Hiiro::TestHarness` tests for every CLI twin with literal expected output.

**Verify, live.** Drive the seven steps from the prototype (open, move, search, toggle scope, pick table, run action, quit) in a tuios window and keep the captures. Then drive add, rename, bulk tag, and bulk delete, and confirm each with `h db q`.

## PR 5. Tasks screen

Sketch only until PR 4 ships. `t ui` renders the task tree with subtasks, a detail pane with todos and next action, and keys for start, switch, and open in tuios. Reuses `Tui::Screen`, `TableScope`, and the key map pattern. Planned in its own one page document after PR 4.

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
