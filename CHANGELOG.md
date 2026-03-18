# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `h task resume [tree_name]` — re-registers an available (stopped) worktree as a task entry without renaming the worktree; fuzzy-selects if no name given, then switches to the task
- `h queue sadd` — shorthand for `h queue add -s` (uses current tmux session)
- `h queue tadd` — shorthand for `h task queue add` (uses current task context)
- `h queue add -T` now includes non-task tmux sessions in the interactive picker; selecting a session sets `session_name` frontmatter

### Changed
- `h pr tags` now includes an `(untagged)` group for PRs with no tags
- `h pr tags` now shows a PR's other tags at the end of each line when listing a group

## [0.1.263] - 2026-03-18

### Fixed
- fix(pr): fix undefined method 'display_pinned' in tags subcommand

## [0.1.262] - 2026-03-17

### Added
- Initial release
