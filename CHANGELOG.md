```markdown
# Changelog

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
```
