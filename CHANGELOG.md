## Unreleased

### Fixed
- `h pr ls` / `h pr update`: PRs with >100 checks now show accurate status. GraphQL query was using `contexts(last: 100)`, truncating check runs for PRs with 100+ checks and silently dropping failures that happened to fall outside the window. Increased limit to 250.

## v0.1.287 (2026-03-26)

### Added
- `h pr status`: show current branch PR checks summary (failures, pending, success counts)
- `h todo`: fuzzyfinder fallback for item selection when no exact match

### Changed
- PR list now shows pending indicator alongside failures
