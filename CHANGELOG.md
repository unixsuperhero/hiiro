```markdown
## v0.1.291 (2026-03-26)

### Added
- `Options#mutual_exclusion(*names)` — star-topology mutual exclusion: first flag is the hub (clears all others when set); any other flag only clears the hub (spokes can coexist freely); last encountered in argv wins
- `h pr ls`: new `--all`/`-a` flag (show all tracked PRs, no filter); all filter flags are declared mutually exclusive so `-oa`, `-ao`, `--all --active` etc. do the right thing

## v0.1.290 (2026-03-26)

### Fixed
- `h pr ls`/`h pr update`: revert `statusCheckRollup` contexts limit to 100 and add pagination to retrieve all checks beyond the first 100; GitHub's GraphQL API silently returns null when limit is exceeded, causing all checks to vanish

## v0.1.289 (2026-03-26)

### Fixed
- `h queue run`/`watch`: frontmatter `session_name` now directly controls which tmux session the task launches in; working directory seeded from that session's active pane when no tree is specified
- `h queue sadd`: now immediately launches a new tmux window in the target session after adding to queue, consistent with `hadd`/`vadd` behavior (previously just added to pending with no launch)
- `h pr ls`: revert `statusCheckRollup` contexts limit from 250 back to 100; GitHub's GraphQL API caps connections at 100 — exceeding it silently returns null for the entire field, causing all checks to vanish from the list
- `h pr update`: paginate beyond the first 100 checks for PRs that hit the limit; show `❓` status for PRs where pagination still couldn't retrieve all checks

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
