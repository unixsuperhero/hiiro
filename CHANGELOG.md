# Changelog

## [Unreleased]

### Fixed
- `h capture path <num>` now prints the path of the Nth most recent capture (was always printing the captures dir regardless of args)
- `h capture new` / `h capture file` now record to the DB even when interrupted (Ctrl-C, exception) so partial captures show up in `h capture ls`. Interrupted captures display with the existing `?` glyph and `(exit interrupted)` message.

## [0.1.350] - 2026-04-18

### Added
- `h-capture` command and `Hiiro::Capture` module for clipboard/selection capture

### Changed
- Optimize `Hiiro::Shell::Result#plain_text` and `#lines` with instance-level caching
- Refactor `Shell::Result#lines` to use `String#lines(chomp: true)` for improved line handling
- Reduce Claude API effort to `low` in publish script for faster changelog generation

## [0.1.349] - 2026-04-17

### Removed
- `h task branches` and `h task wtrees` convenience subcommands; use `h branch` and `h wtree` directly instead

## [0.1.348] - 2026-04-17

### Added
- `h task path|tree|branch|session` now accept `-a/--all` to print one value per task; trailing positional args act as prefix filters (OR'd together)
- `h task name` — new subcommand; prints current task name (or selects via fuzzyfind), supports `-a` like the others
- `h task prune` — drops task records whose worktree dir is missing; dry-run by default, requires `-f` to actually delete
- `TaskManager#filter_tasks(prefixes)` helper for sorted, prefix-filtered task lists

## [0.1.347] - 2026-04-12

### Added
- `h pr tags` now supports flags: `--update/-u` (refresh PR status before listing), `--verbose/-v` (multi-line output per PR), `--checks/-C` (show individual check run details)

## [0.1.346] - 2026-04-12

### Added
- `h pr tags` now accepts optional tag names to filter output to only those tags

## [0.1.345] - 2026-04-12

### Fixed
- ANSI escape sequence pattern now uses hex escapes (`\x20-\x2f`) instead of literal space-to-slash to avoid ambiguity with the `/` regex delimiter

## [0.1.343] - 2026-04-12

### Added
- Task subcommands now fall back to `~/proj/*` directories when no task matches
  - `h task path hiiro` → resolves to `~/proj/hiiro` if no task named "hiiro" exists
  - Works for: `cd`, `path`, `sh`, `branch`, `tree`, `session`, and any subcommand using `-t` flag
  - `FallbackTarget` class duck-types as `Task` for seamless integration
  - Ambiguous project matches print a warning to stderr

### Fixed
- `Hiiro::Git::Pr.is_link?` is now a class method (was instance method)

## [0.1.342] - 2026-04-08

### Added
- `h pr review` / `h pr cr` — code review workflow for managing PR sessions in ~/work/codereviews worktree
- `Hiiro::Git::Pr.from_link(url)` — parse PR number, owner, and repo from GitHub PR links
- `Hiiro::Git::Pr.from_number(number)` — create PR instances from PR numbers
- `Hiiro::Git::Pr.is_link?(link)` — validate GitHub PR links

## [0.1.341] - 2026-04-07

### Fixed
- `h pr view` now defaults to current branch's PR when no PR number is specified

### Changed
- Update publish script to use `claude-haiku-4-5` model identifier

## [0.1.340] - 2026-04-07

### Fixed
- `h notify jump` now runs `switch-client` before `select-window`/`select-pane` so jumping to a pane in a different session actually works
- `h notify ls` and `h notify menu` now auto-prune stale entries for panes that no longer exist

### Added
- `h notify prune` — explicitly remove all notifications for dead panes

## [0.1.339] - 2026-04-07

### Added
- `h ps byport <port> [port2 ...]` — find processes listening on specified port(s)
- `PsProcess.by_port(*ports)` — query processes by listening port numbers
- `h task switch` now matches ~/proj/* directories by prefix as fallback when task name doesn't match

## [0.1.338] - 2026-04-07

### Changed
- `h pr watch`, `h pr fwatch`, `h pr check` now default to current branch's PR (use `-s` to select via fuzzyfinder)
- Renamed `registry_entries` table to `registry` (auto-migrates existing data)

## [0.1.337] - 2026-04-06

### Changed
- Refactor `PsProcess#files` and `PsProcess#ports` to use `filter_map` instead of `map + compact` for cleaner code

## [0.1.336] - 2026-04-06

### Fixed
- `PsProcess#ports` now uses `lsof -a` to AND conditions (was showing all system ports)

## [0.1.335] - 2026-04-07

### Added
- New `Hiiro::PsProcess` class (`lib/hiiro/ps_process.rb`) for encapsulated process info:
  - `PsProcess.from_line(line)` - parse `ps awwux` output
  - `PsProcess.all`, `.search(pattern)`, `.find(pid)`, `.in_dirs(*paths)`
  - Instance methods: `#files`, `#ports`, `#dir`, `#parent`, `#children`
  - Simple `#to_s` output: PID + CMD
- New `h ps` subcommands: `info`, `files`, `ports`
- Smart argument resolution in `h ps`: accepts PID, search pattern, or directory path

### Changed
- Refactored `h-ps` to use `PsProcess` class instead of raw `ps` parsing

## [0.1.334] - 2026-04-07

### Added
- New `h-ps` bin file for process utilities:
  - `search <pattern>` - find processes matching a substring
  - `indir <path> [path2 ...]` - list processes with files open in specified paths
  - `getdir <pattern>` - list working directories of processes matching pattern

## [0.1.333] - 2026-04-04

### Changed
- Display hiiro version in queue watch output for better visibility during task monitoring

## [0.1.332] - 2026-04-04

### Changed
- Extract `hiiro_version` helper method in queue watcher to reduce duplication and improve version detection reliability

## [0.1.331] - 2026-04-04

### Fixed
- Strip whitespace from gem version output in queue watcher to prevent version comparison failures

## [0.1.330] - 2026-04-04

### Added
- `h queue add` now supports tmux session name prefix matching as fallback when task name doesn't match
- Queue editor now opens from the session's active pane directory when adding tasks via session reference

### Changed
- Extract `session_info_for()` helper to resolve tmux sessions by prefix in queue prompt resolver

## [0.1.329] - 2026-04-03

### Changed
- Add debug output and temporary JSON logging to publish script for troubleshooting Claude API responses

## [0.1.328] - 2026-04-02

### Changed
- Update command documentation

## [0.1.327] - 2026-04-02

### Added
- `h branch save --tag <tag>` (repeatable) — apply tags to branches during save operation

## [0.1.326] - 2026-04-02

### Changed
- Improve tag display formatting in link output by mapping individual tags to colored badges
- Refactor `h link tags` filtering logic to use `Hiiro::Tag` helpers for cleaner code
- Relocate `taggable` accessor method in `Hiiro::Tag` model

### Added
- `Hiiro::Tag.tagged_by_type` helper method to query tagged objects by tag name and type

## [0.1.325] - 2026-04-02

### Fixed
- Allow custom primary keys in `Hiiro::Invocation` model via `unrestrict_primary_key` for SQLite compatibility

## [0.1.324] - 2026-04-02

### Added
- `h pr status [ref...]` — query multiple PRs or pinned PRs; outputs number, title, state, check summary, and URL for each
- `h wtree branch [paths...]` — show branch for each worktree, or query specific worktree paths; resolves relative paths using task context

### Changed
- Pass `cwd` context to `h-wtree` via `Hiiro.run` for proper path resolution in nested environments

## [0.1.323] - 2026-04-01

### Changed
- Simplify `h pr ls` status refresh logic: always call `refresh_all_status` with `force:` parameter instead of conditional block
- Add optional `verbose:` parameter to `refresh_all_status` to control "already checked" message output
- Update `h pr update` to pass `verbose: true` when refreshing active PR status

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