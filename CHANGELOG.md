# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `h app sh <app> [cmd...]` — chdir to the app's resolved path and exec the command, or open `$SHELL` if no args given
- `h project sh <project> [cmd...]` — chdir to the project's resolved path (from `~/proj/` or `projects.yml`) and exec the command, or open `$SHELL` if no args given
- `h pr sync [ref]` — update a PR's branch with the base branch server-side via `gh pr update-branch`: tries rebase first, falls back to merge on conflict. No local checkout required.
- `h app fd <app> [args...]`, `h app rg <app> [args...]`, `h app vim <app> [args...]` — run fd/rg/vim scoped to an app's resolved path
- `h bg` — background task management subcommand
- `h sparse set GROUP` — set sparse-checkout group
- `h config git ignore` — add patterns to git ignore
- `h claude` now includes plugin skills in the skills listing
- Auto-tag the current git branch with the active task name on every hiiro command execution
- `Git.add_resolvers(hiiro)`, `ServiceManager.add_resolvers(hiiro)` — lib classes register their own named resolvers on any Hiiro instance

### Changed

- `Hiiro::PinnedPRManager` extracted from `bin/h-pr` to `lib/hiiro/pinned_pr_manager.rb`; adds `PinnedPRManager.add_resolvers(hiiro)` class method
- `h pr ls` now accepts `-d`/`--diff` to fuzzy-select a PR from the filtered list and open `gh pr diff`; the `--drafts` short flag moved from `-d` to `-D`
- Strip ANSI escape codes from PR display strings used as fuzzyfinder keys
- `h pr tags` now includes an `(untagged)` group for PRs with no tags
- `h pr tags` now shows a PR's other tags at the end of each line when listing a group
- `h pr ls` default display is now one-line (verbose with `-v`)

### Fixed

- `h task resume` — re-registers an available (stopped) worktree as a task entry

## [0.1.278] - 2026-03-24

### Added

- `h queue cadd` — add a prompt and immediately run it in the current tmux pane (exec)
- `h queue hadd` — add a prompt and immediately run it in a horizontal split (pane below)
- `h queue vadd` — add a prompt and immediately run it in a vertical split (pane to the right)

### Changed

- `h queue kill` now uses `kill-pane` for pane-launched tasks (those started with `cadd`/`hadd`/`vadd`)
- `h queue ls` and `h queue status` now display `[pane %N]` instead of `[session:window]` for pane-launched tasks

## [0.1.277] - 2026-03-24

### Added

- `Hiiro#add_resolver(name, current, &lookup)` — register a named resolver on any Hiiro instance. `current` is a callable returning the default value when no ref is given; the block resolves an explicit ref to a value.
- `Hiiro#resolve(name, ref = nil)` — dispatch to a registered resolver: calls `current` when `ref` is nil, calls the lookup block otherwise.
- `Hiiro#make_child` propagates parent resolvers to child instances so nested subcommands can call `resolve` without re-registration.

### Changed

- `h pr`: refactored PR resolution to use `Hiiro#add_resolver` / `resolve`

## [0.1.263] - 2026-03-18

### Fixed
- fix(pr): fix undefined method 'display_pinned' in tags subcommand

## [0.1.262] - 2026-03-17

### Added
- Initial release
