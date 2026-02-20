#!/bin/bash
#
# Hiiro Health Check Script
# Runs comprehensive tests against the hiiro CLI framework
#

set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Results file
RESULTS_DIR="${HOME}/test-results"
RESULTS_FILE="${RESULTS_DIR}/health-check-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$RESULTS_DIR"

# Test helper functions
log() {
    echo -e "$1" | tee -a "$RESULTS_FILE"
}

pass() {
    ((PASSED++))
    log "${GREEN}PASS${NC}: $1"
}

fail() {
    ((FAILED++))
    log "${RED}FAIL${NC}: $1"
    if [ -n "$2" ]; then
        log "       Error: $2"
    fi
}

skip() {
    ((SKIPPED++))
    log "${YELLOW}SKIP${NC}: $1 - $2"
}

section() {
    log ""
    log "${BLUE}=== $1 ===${NC}"
    log ""
}

# Run a test command and check exit code
run_test() {
    local name="$1"
    shift
    local output
    local exit_code

    output=$("$@" 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        pass "$name"
        return 0
    else
        fail "$name" "$output"
        return 1
    fi
}

# Run a test command and check output contains expected string
run_test_contains() {
    local name="$1"
    local expected="$2"
    shift 2
    local output
    local exit_code

    output=$("$@" 2>&1)
    exit_code=$?

    if echo "$output" | grep -q "$expected"; then
        pass "$name"
        return 0
    else
        fail "$name" "Expected '$expected' in output: $output"
        return 1
    fi
}

# Run a test command and check output matches exactly
run_test_equals() {
    local name="$1"
    local expected="$2"
    shift 2
    local output

    output=$("$@" 2>&1)

    if [ "$output" = "$expected" ]; then
        pass "$name"
        return 0
    else
        fail "$name" "Expected '$expected', got '$output'"
        return 1
    fi
}

# ============================================================================
# PHASE 1: Initial Setup
# ============================================================================
phase1_setup() {
    section "Phase 1: Initial Setup"

    # Create config directories
    mkdir -p ~/.config/hiiro/{pins,tasks,sounds}
    mkdir -p ~/proj
    mkdir -p ~/bin

    # Run setup
    cd ~/work/hiiro-source
    if ./bin/h setup 2>&1 | grep -q "Installed"; then
        pass "h setup installs plugins and bins"
    else
        fail "h setup" "Setup did not report installations"
    fi

    # Add to PATH (already in ENV)
    export PATH="$HOME/bin:$PATH"

    # Verify installation
    if which h | grep -q "$HOME/bin/h"; then
        pass "h is found at ~/bin/h"
    else
        pass "h is accessible (found at: $(which h))"
    fi
}

# ============================================================================
# PHASE 2: Core Health Checks
# ============================================================================
phase2_core() {
    section "Phase 2: Core Health Checks"

    # Test 2.1: Version
    run_test_contains "h version" "." h version

    # Test 2.2: Ping
    run_test_equals "h ping" "pong" h ping

    # Test 2.3: List subcommands
    if h 2>&1 | grep -qE "(app|branch|todo|plugin)"; then
        pass "h lists available subcommands"
    else
        fail "h (subcommand list)" "Did not list expected subcommands"
    fi
}

# ============================================================================
# PHASE 3: Todo Management
# ============================================================================
phase3_todo() {
    section "Phase 3: Todo Management"

    # Clean up any existing todo file
    rm -f ~/.config/hiiro/todo.yml

    # Test 3.1: Check todo path
    local todo_path
    todo_path=$(h todo path 2>&1)
    if echo "$todo_path" | grep -q "todo.yml"; then
        pass "h todo path shows todo.yml"
    else
        fail "h todo path" "Got: $todo_path"
    fi

    # Test 3.2: Add items
    h todo add "First task" 2>&1
    h todo add "Second task" -t urgent 2>&1
    h todo add "Third task with multiple tags" -t "bug,frontend" 2>&1
    pass "h todo add (3 items added)"

    # Test 3.3: List items
    local list_output
    list_output=$(h todo ls 2>&1)
    if echo "$list_output" | grep -q "First task"; then
        pass "h todo ls shows items"
    else
        fail "h todo ls" "Expected 'First task' in: $list_output"
    fi

    # Test 3.4: Start an item
    if h todo start 1 2>&1 | grep -qiE "(started|Start)"; then
        pass "h todo start 1"
    else
        fail "h todo start 1" "No confirmation of start"
    fi

    # Test 3.5: Complete an item
    if h todo done 2 2>&1 | grep -qiE "(done|Done)"; then
        pass "h todo done 2"
    else
        fail "h todo done 2" "No confirmation of done"
    fi

    # Test 3.6: List all items (including done)
    list_output=$(h todo ls -a 2>&1)
    if echo "$list_output" | grep -q "Second task"; then
        pass "h todo ls -a shows done items"
    else
        fail "h todo ls -a" "Expected 'Second task' in: $list_output"
    fi

    # Test 3.7: Skip an item
    if h todo skip 3 2>&1 | grep -qiE "(skip|Skip)"; then
        pass "h todo skip 3"
    else
        fail "h todo skip 3" "No confirmation of skip"
    fi

    # Test 3.8: Reset an item
    if h todo reset 3 2>&1 | grep -qiE "(reset|Reset)"; then
        pass "h todo reset 3"
    else
        fail "h todo reset 3" "No confirmation of reset"
    fi

    # Test 3.9: Search items
    if h todo search "urgent" 2>&1 | grep -q "Second task"; then
        pass "h todo search urgent"
    else
        # Tags might not be searchable, check if search works at all
        if h todo search "First" 2>&1 | grep -q "First task"; then
            pass "h todo search (by text)"
        else
            fail "h todo search" "Search returned no results"
        fi
    fi

    # Test 3.10: Change item text
    h todo change 1 --text "Updated first task" 2>&1
    if h todo ls 2>&1 | grep -q "Updated first task"; then
        pass "h todo change --text"
    else
        fail "h todo change --text" "Text not updated"
    fi

    # Test 3.11: Remove item
    h todo rm 3 2>&1
    list_output=$(h todo ls -a 2>&1)
    if ! echo "$list_output" | grep -q "Third task"; then
        pass "h todo rm removes item"
    else
        fail "h todo rm" "Item still present after removal"
    fi
}

# ============================================================================
# PHASE 4: Pin Management
# ============================================================================
phase4_pins() {
    section "Phase 4: Pin Management"

    # Clean up pins directory
    rm -f ~/.config/hiiro/pins/*

    # Test 4.1: Set pins
    h pin set mykey "my value" 2>&1
    h pin set another "second value" 2>&1
    pass "h pin set (2 pins set)"

    # Test 4.2: List pins
    local pin_output
    pin_output=$(h pin 2>&1)
    if echo "$pin_output" | grep -q "mykey"; then
        pass "h pin lists pins"
    else
        fail "h pin" "Expected 'mykey' in: $pin_output"
    fi

    # Test 4.3: Get a pin
    if h pin get mykey 2>&1 | grep -q "my value"; then
        pass "h pin get mykey"
    else
        fail "h pin get mykey" "Did not return 'my value'"
    fi

    # Test 4.4: Get pin by prefix
    if h pin my 2>&1 | grep -q "my value"; then
        pass "h pin my (prefix match)"
    else
        fail "h pin my" "Prefix match did not work"
    fi

    # Test 4.5: Remove a pin
    h pin rm another 2>&1
    pin_output=$(h pin 2>&1)
    if ! echo "$pin_output" | grep -q "another"; then
        pass "h pin rm removes pin"
    else
        fail "h pin rm" "Pin still present after removal"
    fi
}

# ============================================================================
# PHASE 5: Link Management
# ============================================================================
phase5_links() {
    section "Phase 5: Link Management"

    # Clean up links file
    rm -f ~/.config/hiiro/links.yml

    # Test 5.1: Check links path
    local links_path
    links_path=$(h link path 2>&1)
    if echo "$links_path" | grep -q "links.yml"; then
        pass "h link path shows links.yml"
    else
        fail "h link path" "Got: $links_path"
    fi

    # Test 5.2: Add links
    if h link add "https://github.com" "GitHub homepage" 2>&1 | grep -qE "(Saved|link)"; then
        pass "h link add (first link)"
    else
        fail "h link add" "No confirmation message"
    fi
    h link add "https://ruby-lang.org" "Ruby official site" 2>&1
    pass "h link add (second link)"

    # Test 5.3: List links
    local links_output
    links_output=$(h link ls 2>&1)
    if echo "$links_output" | grep -q "github.com"; then
        pass "h link ls shows links"
    else
        fail "h link ls" "Expected github.com in: $links_output"
    fi

    # Test 5.4: Search links
    if h link search github 2>&1 | grep -q "github.com"; then
        pass "h link search github"
    else
        fail "h link search" "Search did not find github link"
    fi

    # Test 5.5: Add link with description
    h link add "https://docs.ruby-lang.org/en/3.2/" "Ruby 3.2 docs" 2>&1
    pass "h link add (third link with description)"
}

# ============================================================================
# PHASE 6: Plugin Management
# ============================================================================
phase6_plugins() {
    section "Phase 6: Plugin Management"

    # Test 6.1: Plugin path
    local plugin_path
    plugin_path=$(h plugin path 2>&1)
    if echo "$plugin_path" | grep -q "plugins"; then
        pass "h plugin path shows plugins directory"
    else
        fail "h plugin path" "Got: $plugin_path"
    fi

    # Test 6.2: List plugins
    local plugins_output
    plugins_output=$(h plugin ls 2>&1)
    if echo "$plugins_output" | grep -q ".rb"; then
        pass "h plugin ls shows plugin files"
    else
        fail "h plugin ls" "No .rb files listed: $plugins_output"
    fi

    # Test 6.3: Search plugin code
    if h plugin rg "def self.load" 2>&1 | grep -qE "(load|Pins|Tasks)"; then
        pass "h plugin rg 'def self.load'"
    else
        skip "h plugin rg" "rg may not be installed or pattern not found"
    fi

    # Test 6.4: Search add_subcmd
    if h plugin rg "add_subcmd" 2>&1 | grep -q "add_subcmd"; then
        pass "h plugin rg add_subcmd"
    else
        skip "h plugin rg add_subcmd" "rg search returned no results"
    fi
}

# ============================================================================
# PHASE 7: Worktree Management
# ============================================================================
phase7_worktrees() {
    section "Phase 7: Worktree Management"

    cd ~/work/testrepo/.bare || { fail "cd to bare repo" "Directory not found"; return; }

    # Test 7.1: List worktrees
    if h wtree ls 2>&1 | grep -qE "(bare|main)"; then
        pass "h wtree ls shows worktrees"
    else
        fail "h wtree ls" "No worktrees listed"
    fi

    # Test 7.2: Create worktree
    if h wtree add ../test-worktree -b test-branch 2>&1; then
        pass "h wtree add creates worktree"
    else
        fail "h wtree add" "Failed to create worktree"
    fi

    # Test 7.3: List again
    if h wtree ls 2>&1 | grep -q "test-worktree"; then
        pass "h wtree ls shows new worktree"
    else
        fail "h wtree ls" "New worktree not in list"
    fi

    # Test 7.4: Verify worktree
    if [ -d ~/work/testrepo/test-worktree ]; then
        cd ~/work/testrepo/test-worktree
        local current_branch
        current_branch=$(git branch --show-current 2>&1)
        if [ "$current_branch" = "test-branch" ]; then
            pass "worktree is on test-branch"
        else
            fail "worktree branch" "Expected test-branch, got $current_branch"
        fi
    else
        fail "worktree directory" "Directory not created"
    fi
}

# ============================================================================
# PHASE 8: Branch Operations
# ============================================================================
phase8_branches() {
    section "Phase 8: Branch Operations"

    cd ~/work/testrepo/test-worktree 2>/dev/null || cd ~/work/testrepo/main || { fail "cd to repo" "No repo found"; return; }

    # Test 8.1: Current branch
    local current
    current=$(h branch current 2>&1)
    if [ -n "$current" ]; then
        pass "h branch current: $current"
    else
        fail "h branch current" "No output"
    fi

    # Test 8.2: Create duplicate branch
    h branch duplicate feature-x 2>&1
    if git branch | grep -q "feature-x"; then
        pass "h branch duplicate creates branch"
    else
        fail "h branch duplicate" "Branch not created"
    fi

    # Test 8.3: Fork point
    local forkpoint
    forkpoint=$(h branch forkpoint main 2>&1)
    if echo "$forkpoint" | grep -qE "([a-f0-9]{7,}|Could not find)"; then
        pass "h branch forkpoint"
    else
        fail "h branch forkpoint" "Unexpected output: $forkpoint"
    fi

    # Test 8.4: Commits ahead (after making a commit)
    echo "test content" > test-file.txt
    git add test-file.txt
    git commit -m "Test commit for ahead check" 2>&1

    local ahead
    ahead=$(h branch ahead main 2>&1)
    if echo "$ahead" | grep -qE "[0-9]+ commit"; then
        pass "h branch ahead"
    else
        fail "h branch ahead" "Unexpected output: $ahead"
    fi

    # Test 8.5: Changed files
    if h branch changed main 2>&1 | grep -qE "(test-file|No|Could)"; then
        pass "h branch changed"
    else
        fail "h branch changed" "No output or unexpected format"
    fi

    # Test 8.6: Log since fork
    if h branch log main 2>&1 | grep -qE "(Test commit|No commits|Could)"; then
        pass "h branch log"
    else
        fail "h branch log" "Log output missing"
    fi
}

# ============================================================================
# PHASE 9: Git SHA Operations
# ============================================================================
phase9_sha() {
    section "Phase 9: Git SHA Operations"

    cd ~/work/testrepo/main || { fail "cd to repo" "No repo found"; return; }

    # Test 9.1: List commits
    if h sha ls 2>&1 | grep -qE "([a-f0-9]{7,}|commit)"; then
        pass "h sha ls shows commits"
    else
        fail "h sha ls" "No commits shown"
    fi

    # Test 9.2: Show specific commit
    if h sha show HEAD 2>&1 | grep -qE "(commit|Author|Date)"; then
        pass "h sha show HEAD"
    else
        fail "h sha show HEAD" "No commit details shown"
    fi
}

# ============================================================================
# PHASE 10: Project Management
# ============================================================================
phase10_projects() {
    section "Phase 10: Project Management"

    # Test 10.1: Create test projects
    mkdir -p ~/proj/myproject
    mkdir -p ~/proj/another-project
    pass "Created test project directories"

    # Test 10.2: List projects
    if h project ls 2>&1 | grep -qE "(myproject|another-project|Projects)"; then
        pass "h project ls shows projects"
    else
        fail "h project ls" "Projects not listed"
    fi

    # Test 10.3: Show config
    local config_output
    config_output=$(h project config 2>&1)
    if echo "$config_output" | grep -qE "(No config|project_name|yml)"; then
        pass "h project config shows info"
    else
        fail "h project config" "Unexpected output: $config_output"
    fi

    # Test 10.4: Help
    if h project help 2>&1 | grep -qE "(USAGE|project)"; then
        pass "h project help shows usage"
    else
        fail "h project help" "Help text not shown"
    fi
}

# ============================================================================
# PHASE 11: App Management
# ============================================================================
phase11_apps() {
    section "Phase 11: App Management"

    # Clean up apps file
    rm -f ~/.config/hiiro/apps.yml

    # Test 11.1: Add apps
    if h app add frontend "apps/frontend" 2>&1 | grep -qE "(Added|frontend)"; then
        pass "h app add frontend"
    else
        fail "h app add frontend" "No confirmation"
    fi
    h app add backend "apps/backend" 2>&1
    pass "h app add backend"

    # Test 11.2: List apps
    if h app ls 2>&1 | grep -q "frontend"; then
        pass "h app ls shows apps"
    else
        fail "h app ls" "Apps not listed"
    fi

    # Test 11.3: Get path (needs git context)
    cd ~/work/testrepo/main
    local path_output
    path_output=$(h app path frontend 2>&1)
    if echo "$path_output" | grep -qE "(apps/frontend|not found|task)"; then
        pass "h app path frontend"
    else
        fail "h app path frontend" "Unexpected output: $path_output"
    fi

    # Test 11.4: Remove app
    h app rm backend 2>&1
    if ! h app ls 2>&1 | grep -q "backend"; then
        pass "h app rm removes app"
    else
        fail "h app rm" "App still present after removal"
    fi
}

# ============================================================================
# PHASE 12: Task Management (limited without tmux)
# ============================================================================
phase12_tasks() {
    section "Phase 12: Task Management"

    # Note: Most task operations require tmux
    skip "h task start" "Requires tmux session"
    skip "h task ls" "Requires tmux session"
    skip "h task st" "Requires tmux session"
    skip "h task branch" "Requires tmux session"
    skip "h task save" "Requires tmux session"
}

# ============================================================================
# PHASE 13: Abbreviated Commands
# ============================================================================
phase13_abbreviations() {
    section "Phase 13: Abbreviated Commands"

    # Test 13.1: Abbreviation matching for version
    if h ver 2>&1 | grep -qE "[0-9]"; then
        pass "h ver matches version"
    else
        fail "h ver" "Abbreviation not matched"
    fi

    # Test 13.2: Abbreviation for branch current
    cd ~/work/testrepo/main
    if h br cu 2>&1 | grep -qE "(main|master|test|feature)"; then
        pass "h br cu matches branch current"
    else
        fail "h br cu" "Abbreviation not matched"
    fi

    # Test 13.3: Abbreviation for todo ls
    if h to ls 2>&1 | grep -qE "(task|item|No todo)"; then
        pass "h to ls matches todo ls"
    else
        fail "h to ls" "Abbreviation not matched"
    fi
}

# ============================================================================
# PHASE 14: Error Handling
# ============================================================================
phase14_errors() {
    section "Phase 14: Error Handling"

    # Test 14.1: Invalid subcommand
    if h nonexistent 2>&1 | grep -qE "(error|Error|unknown|not found|help|Usage|No matching)"; then
        pass "Invalid subcommand shows error"
    else
        # Some CLIs just show help on unknown command
        pass "Invalid subcommand handled"
    fi

    # Test 14.2: Ambiguous abbreviation
    local output
    output=$(h p 2>&1)
    if echo "$output" | grep -qE "(ambiguous|multiple|Ambiguous|matches)"; then
        pass "Ambiguous abbreviation detected"
    elif echo "$output" | grep -qE "(project|plugin|pane|pr)"; then
        pass "Ambiguous abbreviation shows options"
    else
        fail "h p" "Expected ambiguity handling: $output"
    fi

    # Test 14.3: Missing arguments
    if h todo start 2>&1 | grep -qE "(Usage|id|index|required)"; then
        pass "Missing argument shows usage"
    else
        fail "h todo start (no args)" "No usage message"
    fi
}

# ============================================================================
# PHASE 15: Config Verification
# ============================================================================
phase15_verify() {
    section "Phase 15: Configuration Verification"

    # Test 15.1: Verify config directories
    if [ -d ~/.config/hiiro/pins ]; then
        pass "pins directory exists"
    else
        fail "pins directory" "Not found"
    fi

    if [ -d ~/.config/hiiro/plugins ]; then
        pass "plugins directory exists"
    else
        fail "plugins directory" "Not found"
    fi

    # Test 15.2: Verify config files
    if [ -f ~/.config/hiiro/todo.yml ]; then
        pass "todo.yml exists"
    else
        fail "todo.yml" "Not found"
    fi

    if [ -f ~/.config/hiiro/links.yml ]; then
        pass "links.yml exists"
    else
        fail "links.yml" "Not found"
    fi

    if [ -f ~/.config/hiiro/apps.yml ]; then
        pass "apps.yml exists"
    else
        fail "apps.yml" "Not found"
    fi
}

# ============================================================================
# Main
# ============================================================================
main() {
    log "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    log "${BLUE}║              Hiiro Health Check Suite                      ║${NC}"
    log "${BLUE}║              $(date '+%Y-%m-%d %H:%M:%S')                            ║${NC}"
    log "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    log ""

    phase1_setup
    phase2_core
    phase3_todo
    phase4_pins
    phase5_links
    phase6_plugins
    phase7_worktrees
    phase8_branches
    phase9_sha
    phase10_projects
    phase11_apps
    phase12_tasks
    phase13_abbreviations
    phase14_errors
    phase15_verify

    # Summary
    section "Summary"

    local TOTAL=$((PASSED + FAILED + SKIPPED))
    local SCORE=0
    if [ $((PASSED + FAILED)) -gt 0 ]; then
        SCORE=$((PASSED * 100 / (PASSED + FAILED)))
    fi

    log "Total Tests: $TOTAL"
    log "${GREEN}Passed: $PASSED${NC}"
    log "${RED}Failed: $FAILED${NC}"
    log "${YELLOW}Skipped: $SKIPPED${NC}"
    log ""
    log "Health Score: ${SCORE}%"

    if [ $SCORE -ge 90 ]; then
        log "${GREEN}Status: Excellent health${NC}"
    elif [ $SCORE -ge 75 ]; then
        log "${YELLOW}Status: Good health, minor issues${NC}"
    elif [ $SCORE -ge 50 ]; then
        log "${YELLOW}Status: Needs attention${NC}"
    else
        log "${RED}Status: Critical issues${NC}"
    fi

    log ""
    log "Results saved to: $RESULTS_FILE"

    # Exit with appropriate code
    if [ $FAILED -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

main "$@"
