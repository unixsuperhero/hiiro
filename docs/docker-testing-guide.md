# Hiiro Docker Testing Guide

Manual testing instructions for verifying hiiro functionality in a Docker container.

## Prerequisites

Your Docker container should have:
- Ruby with bundler
- Bare repo at `~/work/.bare`
- `sk` or `fzf` installed
- `gh` CLI
- `tmux` (available but tests run outside tmux)
- No `terminal-notifier` (macOS-only)

---

## Phase 1: Initial Setup

```bash
# Create config directories
mkdir -p ~/.config/hiiro/{pins,tasks,sounds}
mkdir -p ~/proj
mkdir -p ~/bin

# Install hiiro (copies bins to ~/bin, plugins to ~/.config/hiiro/plugins)
cd ~/work/main  # or wherever hiiro is cloned
./bin/h setup

# Add to PATH
export PATH="$HOME/bin:$PATH"

# Verify installation
which h
```

**Expected:** `h` is found at `~/bin/h`

---

## Phase 2: Core Health Checks

### Test 2.1: Version
```bash
h version
```
**Expected:** Prints version string (e.g., `0.1.0`)

### Test 2.2: Ping
```bash
h ping
```
**Expected:** `pong`

### Test 2.3: List subcommands
```bash
h
```
**Expected:** Lists available subcommands (app, branch, buffer, claude, commit, etc.)

---

## Phase 3: Todo Management (h-todo)

### Test 3.1: Check todo path
```bash
h todo path
```
**Expected:** `~/.config/hiiro/todo.yml` (or full path)

### Test 3.2: Add items
```bash
h todo add "First task"
h todo add "Second task" -t urgent
h todo add "Third task with multiple tags" -t "bug,frontend"
```
**Expected:** Items added (confirmation message for each)

### Test 3.3: List items
```bash
h todo ls
```
**Expected:** Shows 3 items with IDs, text, and tags. Items are `not_started`.

### Test 3.4: Start an item
```bash
h todo start 1
h todo ls
```
**Expected:** First item now shows `started` status

### Test 3.5: Complete an item
```bash
h todo done 2
h todo ls
```
**Expected:** Second item shows `done` status, may be hidden from default list

### Test 3.6: List all items (including done)
```bash
h todo ls -a
```
**Expected:** Shows all 3 items including completed ones

### Test 3.7: Skip an item
```bash
h todo skip 3
h todo ls -a
```
**Expected:** Third item shows `skipped` status

### Test 3.8: Reset an item
```bash
h todo reset 3
h todo ls
```
**Expected:** Third item back to `not_started`

### Test 3.9: Search items
```bash
h todo search "urgent"
```
**Expected:** Shows item with urgent tag

### Test 3.10: Change item text
```bash
h todo change 1 --text "Updated first task"
h todo ls
```
**Expected:** Item 1 shows updated text

### Test 3.11: Remove item
```bash
h todo rm 3
h todo ls -a
```
**Expected:** Only 2 items remain

---

## Phase 4: Pin Management

### Test 4.1: Set pins
```bash
h pin set mykey "my value"
h pin set another "second value"
```
**Expected:** Pins saved (silent or confirmation)

### Test 4.2: List pins
```bash
h pin
```
**Expected:** Shows both pins with names and values

### Test 4.3: Get a pin
```bash
h pin get mykey
```
**Expected:** `my value`

### Test 4.4: Get pin by prefix
```bash
h pin my
```
**Expected:** `my value` (prefix matches `mykey`)

### Test 4.5: Remove a pin
```bash
h pin rm another
h pin
```
**Expected:** Only `mykey` remains

---

## Phase 5: Link Management (h-link)

### Test 5.1: Check links path
```bash
h link path
```
**Expected:** `~/.config/hiiro/links.yml` (or full path)

### Test 5.2: Add links
```bash
h link add "https://github.com" "GitHub homepage"
h link add "https://ruby-lang.org" "Ruby official site"
```
**Expected:** Links added with auto-generated IDs

### Test 5.3: List links
```bash
h link ls
```
**Expected:** Shows both links with numbers/IDs, URLs, and descriptions

### Test 5.4: Search links
```bash
h link search github
```
**Expected:** Shows GitHub link

### Test 5.5: Add link with description
```bash
h link add "https://docs.ruby-lang.org/en/3.2/" "Ruby 3.2 docs"
```
**Expected:** Link added

---

## Phase 6: Plugin Management (h-plugin)

### Test 6.1: Plugin path
```bash
h plugin path
```
**Expected:** `~/.config/hiiro/plugins` (or full path)

### Test 6.2: List plugins
```bash
h plugin ls
```
**Expected:** Lists plugin files (pins.rb, tasks.rb, project.rb, notify.rb)

### Test 6.3: Search plugin code
```bash
h plugin rg "def self.load"
```
**Expected:** Shows matches in plugin files for the load method pattern

### Test 6.4: Search with context
```bash
h plugin rg "add_subcmd"
```
**Expected:** Shows all subcommand registrations across plugins

---

## Phase 7: Worktree Management (h-wtree)

### Test 7.1: List worktrees
```bash
h wtree ls
```
**Expected:** Shows bare repo and any existing worktrees

### Test 7.2: Create worktree
```bash
cd ~/work/.bare
h wtree add ../test-worktree -b test-branch
```
**Expected:** Creates worktree at `~/work/test-worktree` with branch `test-branch`

### Test 7.3: List again
```bash
h wtree ls
```
**Expected:** Now shows 2 entries (bare + test-worktree)

### Test 7.4: Verify worktree
```bash
cd ~/work/test-worktree
git branch
```
**Expected:** Shows `test-branch` as current branch

---

## Phase 8: Branch Operations (h-branch)

### Test 8.1: Current branch
```bash
cd ~/work/test-worktree
h branch current
```
**Expected:** `test-branch`

### Test 8.2: Create duplicate branch
```bash
h branch duplicate feature-x test-branch
h branch current
```
**Expected:** Shows `test-branch` (duplicate creates branch but doesn't switch)

### Test 8.3: Fork point
```bash
h branch forkpoint main
```
**Expected:** Shows commit SHA (fork point from main)

### Test 8.4: Commits ahead
```bash
# Make a commit first
echo "test" > test.txt
git add test.txt
git commit -m "Test commit"

h branch ahead main
```
**Expected:** Shows commits ahead of main (e.g., `1 commit(s) ahead`)

### Test 8.5: Changed files
```bash
h branch changed main
```
**Expected:** Shows `test.txt`

### Test 8.6: Log since fork
```bash
h branch log main
```
**Expected:** Shows the "Test commit" entry

---

## Phase 9: Git SHA Operations (h-sha)

### Test 9.1: List commits
```bash
cd ~/work/test-worktree
h sha ls
```
**Expected:** Shows recent commits in oneline format

### Test 9.2: Show specific commit
```bash
h sha show HEAD
```
**Expected:** Shows full commit details for HEAD

---

## Phase 10: Project Management (h-project)

### Test 10.1: Create test projects
```bash
mkdir -p ~/proj/myproject
mkdir -p ~/proj/another-project
```

### Test 10.2: List projects
```bash
h project ls
```
**Expected:** Shows `myproject` and `another-project`

### Test 10.3: Show config
```bash
h project config
```
**Expected:** Shows projects.yml contents (may be empty or not exist yet)

### Test 10.4: Help
```bash
h project help
```
**Expected:** Shows usage information

---

## Phase 11: App Management (h-app)

### Test 11.1: Add apps
```bash
h app add frontend "apps/frontend"
h app add backend "apps/backend"
```
**Expected:** Apps saved to apps.yml

### Test 11.2: List apps
```bash
h app ls
```
**Expected:** Shows frontend and backend with paths

### Test 11.3: Get path
```bash
h app path frontend
```
**Expected:** `apps/frontend` (or error about git/task context)

### Test 11.4: Remove app
```bash
h app rm backend
h app ls
```
**Expected:** Only frontend remains

---

## Phase 12: Abbreviated Commands

### Test 12.1: Abbreviation matching
```bash
h ver
```
**Expected:** Same as `h version`

### Test 12.2: Branch abbreviation
```bash
h br cu
```
**Expected:** Same as `h branch current`

### Test 12.3: Todo abbreviation
```bash
h to ls
```
**Expected:** Same as `h todo ls`

---

## Phase 13: Error Handling

### Test 13.1: Invalid subcommand
```bash
h nonexistent
```
**Expected:** Error message or help with available commands

### Test 13.2: Ambiguous abbreviation
```bash
h p
```
**Expected:** Shows ambiguous matches (pr, project, plugin, pane, etc.)

### Test 13.3: Missing arguments
```bash
h todo start
```
**Expected:** Error or usage message requesting ID

---

## Phase 14: Cleanup Verification

### Test 14.1: Verify config files created
```bash
ls ~/.config/hiiro/
ls ~/.config/hiiro/pins/
cat ~/.config/hiiro/todo.yml
cat ~/.config/hiiro/links.yml
cat ~/.config/hiiro/apps.yml
```
**Expected:** All config files exist with data from tests

---

## Commands NOT Tested (require interactive tools or unavailable deps)

| Command | Reason |
|---------|--------|
| `h alert` | Requires terminal-notifier |
| `h buffer *` | Requires active tmux |
| `h claude *` | Requires tmux + claude CLI |
| `h commit select` | Requires sk/fzf interactive |
| `h config *` | Opens editor |
| `h pane *` | Requires active tmux |
| `h session *` | Requires active tmux |
| `h window *` | Requires active tmux |
| `h pr check/watch` | Requires gh auth + real PR |
| Interactive select/copy | Requires sk/fzf |
| `h task *` | Requires tmux session |

---

## Health Score Assessment

After running all tests, score based on:

| Category | Weight | Tests |
|----------|--------|-------|
| Core (version, ping, setup) | 15% | 3 tests |
| Todo CRUD | 20% | 11 tests |
| Pin management | 10% | 5 tests |
| Link management | 10% | 5 tests |
| Plugin ops | 10% | 4 tests |
| Git worktree | 10% | 4 tests |
| Branch ops | 10% | 6 tests |
| SHA ops | 5% | 2 tests |
| Project/App | 5% | 6 tests |
| Abbreviations | 5% | 3 tests |

**Scoring:**
- 90-100%: Excellent health
- 75-89%: Good health, minor issues
- 50-74%: Needs attention
- <50%: Critical issues
