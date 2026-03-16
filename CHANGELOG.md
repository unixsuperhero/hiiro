# Changelog

## [0.1.259] - 2026-03-16

### Added
- ISC code freeze awareness in `h pr update`: calls `isc codefreeze list` to get the real current freeze state, overrides stale GitHub-cached `ISC code freeze` status check accordingly
- `frozen` count in checks summary to track code-freeze-only failures separately
- Snowflake emoji (❄️) in PR list when a PR is failing exclusively due to code freeze (vs ❌ for other failures)

### Fixed
- Removed `workflowName` from batch GraphQL query — field doesn't exist on GitHub's raw `CheckRun` type, causing `h pr update` to silently fail and never refresh PR data

## [0.1.257] - 2026-03-16

### Added
- Custom name option to queue add command

## [0.1.256] - 2026-03-16

### Added
- Status filtering to queue list command

## [0.1.255] - 2026-03-16

### Added
- Subcommands to list agents, commands, and skills

## [0.1.254] - 2026-03-13

### Changed
- Refactored h-pr to use Pr domain object with method access
- Promoted Pr to full domain object with all pinned attributes

### Fixed
- Removed code duplication in multi-pr pr commands
- Updated all multi-pr commands to use YAML
