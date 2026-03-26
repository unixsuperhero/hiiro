```markdown
## Unreleased

### Fixed
- **h queue**: When a raw tmux session is selected via fuzzyfinder (`-f`), the task now launches in that session instead of falling back to the default `hq` session. Previously `target_session` was only set when the session was tracked in hiiro's environment model.

## [0.1.285] - 2026-03-26

### Fixed
- **h notify**: Resolve terminal-notifier path dynamically instead of hardcoding, improving portability across different system configurations
- **h queue sadd**: Auto-detect current task from environment when no explicit `-f`/`-t` flag given, so frontmatter is populated without needing to pass a flag when already in a task session
- **h queue sadd**: Fixed task context being lost — was using `exec` which replaced the process; now calls `do_add` directly so `task_info` closure is preserved

## [0.1.284] - 2026-03-25

### Added
- **h-pm bin**: Queue `/project-manager` skill prompts via `h queue add`; subcommands map to all project-manager slash commands (discover, resume, status, add, start, plan, complete, ref, impact, archive, unarchive); interactive default uses fuzzyfind to pick a command

## [0.1.283] - 2026-03-25

### Fixed
- **h queue cadd/vadd/hadd**: Now `Dir.chdir` to the selected task's base directory (or active pane CWD for session selections) in the Ruby process before spawning the tmux pane, so the editor and `claude` session start in the correct directory
- **h queue cadd/vadd/hadd**: Added `h queue pane-dir` internal helper that resolves the working directory post-edit (accounting for `app:` and `dir:` frontmatter), used by the generated shell script to `cd` before running `claude`

## [0.1.282] - 2026-03-25

### Changed
- **h task path/cd/sh**: Reworked to accept `-f`/`-t` flags for task selection
- **h task path**: Enhanced to support multi-argument glob patterns for file listing within task apps
- **h task cd/sh**: Now use the same task selection mechanism as `h task path`
- **TaskManager#send_cd**: Promoted from private to public method

## [0.1.281] - Previous release
```
