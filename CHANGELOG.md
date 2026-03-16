## [0.1.255] - 2026-03-16

### Fixed
- `h pr open` now uses `system('open', pr.url)` for pinned PRs (avoids `gh pr view --web` requiring git context)
- `mopen` similarly uses URL-based open for pinned PRs
- `h pr ls` / `h pr status` no longer missing check data for PRs tracked before checks summary existed — `from_pinned_hash` now falls back to computing `checks` from raw `statusCheckRollup` nodes

### Added
- `h pr ls -C` / `--checks` flag: shows individual check run details (emoji, name, detailsUrl) indented under each PR
- `PinnedPRManager#display_check_runs`: renders per-check-run lines with status emoji, name, and URL; handles both `CheckRun` (GitHub Actions) and `StatusContext` (Commit Status API) node types
- GraphQL batch query now fetches `name`, `detailsUrl`, `workflowName` for `CheckRun` nodes and `context`, `targetUrl` for `StatusContext` nodes
- `Pr#to_pinned_h` now persists raw check run nodes as `statusCheckRollup` so details survive save/load cycles
- `refresh_all_status` and `refresh_status` now populate `pr.check_runs`; `pin` syncs `check_runs` on update

## [0.1.254] - 2026-03-15

### Changed
- `Hiiro::Git::Pr` promoted to full domain object: added all pinned-PR attributes (`slot`, `repo`, `is_draft`, `mergeable`, `review_decision`, `checks`, `reviews`, `last_checked`, `pinned_at`, `updated_at`, `task`, `worktree`, `tmux_session`, `tags`, `assigned`, `authored`) with `attr_accessor`
- Moved `repo_from_url`, `summarize_checks`, `summarize_reviews`, `FAILED_CONCLUSIONS`, and `PINNED_FILE` from `PinnedPRManager` to `Hiiro::Git::Pr`
- Added `Pr.pinned_prs`, `Pr.from_pinned_hash`, `Pr#to_pinned_h`, `Pr#draft?`, `Pr#conflicting?`
- `PinnedPRManager` now delegates to `Pr` for loading/saving; all methods use method access instead of string-keyed hash access
- Converted all `bin/h-pr` subcommands to use `Pr` method access throughout
- Converted `:amissing` and `:tag -e` to use `yaml_input_file` instead of raw `Tempfile`

## [0.1.253] - 2026-03-15

### Changed
- Replace CLI filters with interactive YAML editor in mmerge and mcomment for improved UX

## [0.1.252] - 2026-03-14

### Added
- Persistent per-task tmux color themes
- Wire task_colors into tasks.rb and hiiro.rb

### Changed
- Task runners now receive subcmd prepended to args

## [0.1.251] - 2026-02-15

### Added
- `run_child` method for cleaner nested Hiiro dispatch
- Terminal tab title renaming on tmux session switch

### Changed
- Improved publish script with Claude-based commit planning

## [0.1.250] and earlier

See git history for detailed changes.
