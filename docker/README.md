# Hiiro Docker Testing

This directory contains Docker-based testing infrastructure for the Hiiro CLI framework.

## Quick Start

### Build and Run Interactive Container

```bash
cd docker
docker-compose build hiiro-test
docker-compose run --rm hiiro-test
```

This gives you a bash shell inside the container where you can run hiiro commands.

### Run Full Health Check Suite

```bash
cd docker
docker-compose run --rm hiiro-test-runner
```

Results are saved to `docker/test-results/`.

### Run Quick Health Check (Local)

If you have hiiro already installed locally:

```bash
./docker/quick-health-check.sh
```

## Container Environment

The Docker container includes:

- **Ruby 3.2** with bundler
- **Git** configured for testing
- **tmux** (available but tests run outside tmux sessions)
- **sk (skim)** fuzzy finder
- **fzf** as fallback fuzzy finder
- **gh CLI** (GitHub CLI, not authenticated)
- **Bare repo** at `~/work/.bare` for worktree testing

Not included (intentionally):
- **terminal-notifier** (macOS-only)

## Directory Structure

```
~/work/hiiro-source/        # Hiiro source code
~/work/testrepo/.bare/      # Bare git repo for worktree tests
~/work/testrepo/main/       # Main worktree from test repo
~/work/testrepo/test-worktree/  # Created during tests
~/proj/                     # Project directories
~/bin/                      # Installed h commands
~/.config/hiiro/            # Configuration directory
  ├── pins/                 # Pin storage (per-command)
  ├── plugins/              # Plugin files
  ├── tasks/                # Task metadata
  ├── sounds/               # Alert sounds
  ├── todo.yml              # Todo items
  ├── links.yml             # Saved links
  └── apps.yml              # App path mappings
```

## Test Phases

The health check runs through 15 phases:

| Phase | Category | Tests |
|-------|----------|-------|
| 1 | Initial Setup | h setup, PATH verification |
| 2 | Core Health | version, ping, subcommand listing |
| 3 | Todo Management | CRUD operations on todo items |
| 4 | Pin Management | Set, get, list, remove pins |
| 5 | Link Management | Add, list, search links |
| 6 | Plugin Management | Path, list, search plugins |
| 7 | Worktree Management | List, add worktrees |
| 8 | Branch Operations | Current, duplicate, forkpoint, ahead |
| 9 | SHA Operations | List, show commits |
| 10 | Project Management | List, config, help |
| 11 | App Management | Add, list, path, remove apps |
| 12 | Task Management | Skipped (requires tmux) |
| 13 | Abbreviations | Prefix matching for commands |
| 14 | Error Handling | Invalid commands, missing args |
| 15 | Config Verification | Directory/file existence |

## Skipped Tests

These features require interactive terminals or macOS-specific tools:

| Feature | Reason |
|---------|--------|
| `h alert` | Requires terminal-notifier (macOS) |
| `h buffer *` | Requires active tmux session |
| `h claude *` | Requires tmux + claude CLI |
| `h commit select` | Requires interactive sk/fzf |
| `h config *` | Opens editor |
| `h pane *` | Requires active tmux session |
| `h session *` | Requires active tmux session |
| `h window *` | Requires active tmux session |
| `h pr check/watch` | Requires gh authentication |
| Interactive select/copy | Requires sk/fzf |

## Health Score

The test suite calculates a health score based on pass/fail ratios:

| Score | Status |
|-------|--------|
| 90-100% | Excellent health |
| 75-89% | Good health, minor issues |
| 50-74% | Needs attention |
| <50% | Critical issues |

## Development

### Adding Tests

To add new tests, edit `run-health-check.sh` and add a new phase function or extend an existing one. Use the helper functions:

```bash
# Test command runs without error
run_test "test name" h some command

# Test output contains expected string
run_test_contains "test name" "expected" h some command

# Test output equals expected string exactly
run_test_equals "test name" "expected" h some command

# Manual test with pass/fail
if some_condition; then
    pass "test name"
else
    fail "test name" "error details"
fi

# Skip a test
skip "test name" "reason for skipping"
```

### Debugging

Run the container interactively:

```bash
docker-compose run --rm hiiro-test bash
```

Then run individual commands or the health check manually:

```bash
# Inside container
./docker/run-health-check.sh

# Or run individual commands
h version
h todo ls
h pin get somekey
```

### Viewing Results

Test results are saved to `docker/test-results/` with timestamps:

```bash
cat docker/test-results/health-check-*.log
```
