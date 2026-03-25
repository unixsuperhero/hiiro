## Unreleased

### Fixed
- **h queue cadd/vadd/hadd**: Now `Dir.chdir` to the selected task's base directory in the Ruby process before spawning the tmux pane, so the editor and `claude` session start in the correct worktree root
- **h queue cadd/vadd/hadd**: Added `h queue pane-dir` internal helper that resolves the working directory post-edit (accounting for `app:` and `dir:` frontmatter), used by the generated shell script to `cd` before running `claude`

## [0.1.282] - 2026-03-25

### Changed
- **h task path/cd/sh**: Reworked to accept `-f`/`-t` flags for task selection
- **h task path**: Enhanced to support multi-argument glob patterns for file listing within task apps
- **h task cd/sh**: Now use the same task selection mechanism as `h task path`
- **TaskManager#send_cd**: Promoted from private to public method

## [0.1.281] - Previous release
