```markdown
## v0.1.289 (2026-03-26)

### Fixed
- `h queue run`/`watch`: frontmatter `session_name` now directly controls which tmux session the task launches in; working directory seeded from that session's active pane when no tree is specified
- `h queue sadd`: now immediately launches a new tmux window in the target session after adding to queue, consistent with `hadd`/`vadd` behavior (previously just added to pending with no launch)

## v0.1.288 (2026-03-26)

### Fixed
- `h pr ls` / `h pr update`: PRs with >100 checks now show accurate status. GraphQL query was using `contexts(last: 100)`, truncating check runs for PRs with 100+ checks and silently dropping failures that happened to fall outside the window. Increased limit to 250.

## v0.1.287 (2026-03-26)

### Added
- `h pr status`: show current branch PR checks summary (failures, pending, success counts)
- `h todo`: fuzzyfinder fallback for item selection when no exact match

### Changed
- PR list now shows pending indicator alongside failures
```
