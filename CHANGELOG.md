# Changelog

## [0.1.322] - 2026-04-01

### Changed
- Refactor `h link tags` filtering logic to use new `Hiiro::Tag.tags_by_type` helper
- Simplify tag query to use `Hiiro::Link.where(id:)` instead of manual filtering
- Extract `tags_by_type(type)` singleton method to `Hiiro::Tag` for code reuse

## [0.1.321] - 2026-04-01

### Changed
- Extract `open_config` to `Hiiro::Config.open` singleton method; simplify parameter order from `dir:, file:` to positional `file, dir: nil`
- Update all config subcommands to use new `Hiiro::Config.open` interface

## [0.1.320] - 2026-04-01

### Changed
- Extract `open_config` helper to Hiiro instance method for reuse across config subcommands
- Refactor `h version --all` to use `Hiiro::Rbenv.capture` with clearer output formatting
- Add `to_s` method to `Hiiro::Tmux::Session` for string representation; rename existing `display` method for consistency
- Extract `project_dirs` and `projects_from_config` to singleton methods in Project plugin for testability

## [0.1.319] - 2026-04-01

### Added
- `h queue ls [STATUS]` — filter by status with prefix matching (e.g. `h queue ls run` → running tasks); composable with existing `-s` flag
- `h session sh <session> [cmd...]` — open a new window in another tmux session (runs shell or given command there, then switches)
- `h task sh -s SESSION [cmd...]` — run task shell/command in a new window in a specific tmux session
- `h link tags` — list all known link tags; `h link tags tag1 tag2...` filters links by tags (prefix matching)
- `h link ls` now shows tags inline with colored badges
- `h link rm` / `h link remove` subcommand — remove links by number, shorthand, or fuzzy select

### Fixed
- `h pr update` and `h pr ls -u` skip closed/merged PRs — only active PRs are refreshed
- `h link add -h` now shows help instead of adding `-h` as a URL
- `h db remigrate` no longer imports duplicate links — skips rows with an already-existing URL
- Add unique constraint on `links.url` to prevent duplicates at database level

## [0.1.318] - 2026-04-01

### Added
- `registry_pick` helper method for interactive registry entry selection via fuzzyfinder

### Changed
- Simplify gem installation logic: always use `gem install -u` instead of checking installation state and branching between `gem install` and `gem update`
- Remove `--clear-sources` and `--source` flags in favor of gem's built-in source cache handling
- Improve gem version regex in publish script to match only the first (latest) version from `gem list` output

### Fixed
- Ensure gem installation works reliably across all rbenv Ruby versions by using `-u` flag for consistent update behavior

## [0.1.317] - 2026-04-01

### Changed
- Parallelize gem installation across all rbenv Ruby versions using thread pool for faster multi-version deployment
- Refactor publish script to install/update hiiro gem across all Ruby versions instead of just current version

### Fixed
- Handle both gem install and update cases based on existing installation state
- Run `h setup` after installation in each Ruby version to initialize version-specific configuration
- Suppress gem installation output to reduce log noise during parallel installs

## [0.1.316] - 2026-04-01

### Added
- Parallelize hiiro gem updates across Ruby versions with thread pool for faster multi-version updates
- Optional `dir:` parameter to `Hiiro::Background.run` for working directory support

### Changed
- Improve gem version regex pattern in publish script for more reliable version matching

### Fixed
- Bypass rubygems local cache with `--clear-sources --source https://rubygems.org` flags in `install_gem` to ensure fresh gem installation
- Add debug output for version polling in publish script
- Convert `sa` symlink from absolute to relative path

## [0.1.315] - 2026-04-01

### Fixed
- Remove redundant `exit 0` statement from publish script

## [0.1.314] - 2026-04-01

### Fixed
- Rename `Gem` class to `RubyGem` in publish script to avoid conflict with Ruby stdlib

## [0.1.313] - 2026-04-01

### Fixed
- Remove `awesome_print` dependency
- Do not splice values into subcommand constructor; pass them as keyword arguments to prevent arg leakage

## [0.1.312] - 2026-04-01

### Fixed
- Separate `bin_name` and `args` initialization in `Hiiro.init` to prevent argument confusion in nested Hiiro instances

## [0.1.311] - 2026-04-01

### Changed
- Add `ap()` inspection for bin/args initialization in debug mode

## [0.1.310] - 2026-04-01

### Fixed
- `make_child` now passes `bin_name:` and `args:` as keyword args to `Hiiro.init`, fixing subcommand dispatch for all `h task`, `h queue`, `h service`, and `h run` child hierarchies — previously `child_bin_name` leaked into `oargs` and became the subcmd, so every child hiiro showed help instead of dispatching

## [0.1.309] - 2026-03-31

### Added
- `h link tag` support for tagging links in the link manager

### Fixed
- Correct argument passing in `run_child` to prevent arg dropping in nested Hiiro instances

## [0.1.308] - 2026-03-31

### Added
- `h db cleanup` subcommand to preview and prune duplicate rows from SQLite tables

### Fixed
- Prevent duplicate pinned_prs during import with `insert_conflict` and per-row rescue

## [0.1.308.pre.6] - 2026-03-31

### Fixed
- Prevent duplicate pinned_prs during import with `insert_conflict` and per-row rescue

## [0.1.308.pre.5] - 2026-03-31

### Added
- `h-claude vim` subcommand to open all matched files in `$EDITOR`

### Fixed
- `h branch ls` now sorts oldest-first so most recent branches appear at bottom

## [0.1.308.pre.4] - 2026-03-31

### Fixed
- Don't pass empty string arg to gem when `--pre` is false

## [0.1.308.pre.3] - 2026-03-31

### Changed
- Poll RubyGems in `delayed_update` instead of blind sleep for more reliable version detection

### Fixed
- Per-row rescue in `import_todos` so one bad row doesn't abort the entire batch

## [0.1.308.pre.2] - 2026-03-31

### Added
- `--pre`/`-p` flag to `h install` and `h update` for installing/updating pre-release versions

### Changed
- Merge `prs` and `pinned_prs` tables into single `prs` table in SQLite schema
- Refactor PR storage to use unified table structure

### Fixed
- YAML migration for todos, prs, pinned_prs, and tags to correctly handle merged schema

## [0.1.308.pre.1] - 2026-03-31

### Added
- `Hiiro::Effects` injectable interface for testable file system and command execution
- `null_fs` to `TestHarness` for testing without side effects
- Effects helpers and accessors to `TestHarness` for controlled effect simulation
- `Hiiro::Invocation` and `Hiiro::InvocationResolution` tracking in PaneHome SQLite migration

### Changed
- Refactor effects layer: expose `executor` and `fs` as accessors on `Hiiro::Effects`
- `h-db` command now includes h-pane in SQLite migration
- Gem version handling: treat non-main branches as pre-release in publish script

### Fixed
- `h-branch co` and `h-branch rm` restore extra argument pass-through
- Test suite: add missing `TestHarness` stubs and fix pre-existing test failures
- Test fixtures: anchor `load_bin` path to project root instead of `Dir.pwd`

### Deprecated
- `SystemCallCapture` — use `Hiiro::Effects` helpers in `TestHarness` instead

## [0.1.307]

### Added
- `Hiiro::DB` — SQLite foundation via Sequel; `DB.setup!` creates all tables, `DB.connection` establishes connection eagerly at load time; supports `HIIRO_TEST_DB=sqlite::memory:` for tests
- `lib/hiiro/db.rb` — one-time YAML→SQLite migration (`migrate_yaml!`) guarded by `schema_migrations` table; dual-write mode (`dual_write?` / `disable_dual_write!`) for gradual cutover
- `lib/hiiro/branch.rb` — `Hiiro::Branch` Sequel model for worktree branch records
- `lib/hiiro/tracked_pr.rb` — `Hiiro::TrackedPr` Sequel model for tracked PR records (`:prs` table)
- `lib/hiiro/link.rb` — `Hiiro::Link` Sequel model with `matches?`, `display_string`, `to_h` helpers
- `lib/hiiro/project.rb` — `Hiiro::Project` Sequel model
- `lib/hiiro/pane_home.rb` — `Hiiro::PaneHome` Sequel model with `data_json` JSON blob
- `lib/hiiro/pin_record.rb` — `Hiiro::PinRecord` Sequel model for per-command key-value pin storage
- `lib/hiiro/task_record.rb` — `Hiiro::TaskRecord` Sequel model for task metadata
- `lib/hiiro/app_record.rb` — `Hiiro::AppRecord` Sequel model for app directory mappings
- `lib/hiiro/assignment.rb` — `Hiiro::Assignment` Sequel model for worktree→branch assignments
- `lib/hiiro/reminder.rb` — `Hiiro::Reminder` Sequel model
- `lib/hiiro/invocation.rb` — `Hiiro::Invocation` and `Hiiro::InvocationResolution` Sequel models; every CLI invocation is recorded to SQLite for history/analytics
- `bin/h-db` — new subcommand: `h db status`, `h db tables`, `h db q <sql>`, `h db migrate`, `h db restore`

### Changed
- `lib/hiiro/todo.rb` — `TodoItem` is now a `Sequel::Model`; `TodoManager` reads/writes via SQLite with YAML dual-write fallback
- `lib/hiiro/tags.rb` — `Tag` is now a `Sequel::Model`; tag operations persist to SQLite with YAML dual-write fallback
- `lib/hiiro/pinned_pr_manager.rb` — `PinnedPR` is now a `Sequel::Model` (`lib/hiiro/pinned_pr.rb`); `PinnedPRManager` reads/writes via SQLite with YAML dual-write
- `lib/hiiro/projects.rb` — `Projects#from_config` reads from `Hiiro::Project` SQLite model with YAML fallback
- `lib/hiiro/tasks.rb` — `TaskManager::Config` reads/writes tasks and apps via `Hiiro::TaskRecord` and `Hiiro::AppRecord` SQLite models
- `bin/h-branch` — `BranchManager` reads/writes via `Hiiro::Branch` and `Hiiro::TrackedPr` SQLite models with YAML dual-write fallback; adds `q`/`query` subcommands for raw SQL inspection
- `bin/h-link` — reads/writes links via `Hiiro::Link` SQLite model with YAML dual-write fallback; adds `q`/`query` subcommands
- `bin/h-pane` — load/save pane homes via `Hiiro::PaneHome` model with YAML dual-write
- `bin/h-pr` — adds `q`/`query` subcommands for inspecting PR records via raw SQL
- `plugins/pins.rb` — `Pin` class reads/writes via `Hiiro::PinRecord` SQLite model with YAML dual-write fallback

## [0.1.306] - 2026-03-30

### Changed
- Increase delayed_update sleep duration from 5s to 15s
- Add logging for delayed_update invocation in publish script

## [0.1.305] - 2026-03-30

### Changed
- Refactor: use delayed_update subcommand instead of direct update call
- Improve gem version matching regex in version check

## [0.1.304] - 2026-03-30

### Changed
- h-notify: use universal log instead of per-session logging
- Todo output simplified

## [0.1.302] - 2026-03-30

### Fixed
- Truncate output lines to terminal width in tasks plugin

## [0.1.301]

### Added
- Check version delayed update functionality

### Changed
- h-claude: add verbose flags and refactor glob_path handling

### Fixed
- Use exact session matching to prevent tmux prefix ambiguity

## [0.1.300]

### Added
- h-claude: fulltext search option for agents/commands/skills

### Changed
- Refactor h-claude directory traversal and file globbing

## [0.1.299]

### Added
- h-pr open: support opening multiple PRs

## [0.1.298]

### Changed
- Use Pathname to walk up directory tree
- h-claude agents/commands/skills walk from pwd up to home

## [0.1.297]

### Added
- h rnext subcommand

## [0.1.296]

### Changed
- Refactor PR filter logic to pinned_pr_manager
- Move PR filter logic to Pr#matches_filters?

## [0.1.295]

### Changed
- Filter logic changes for PR management