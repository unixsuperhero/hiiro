#!/bin/bash
#
# Quick Hiiro Health Check
# A minimal test to verify core functionality
#

set -o pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASSED=0
FAILED=0

pass() {
    ((PASSED++))
    echo -e "${GREEN}PASS${NC}: $1"
}

fail() {
    ((FAILED++))
    echo -e "${RED}FAIL${NC}: $1"
}

echo "=== Hiiro Quick Health Check ==="
echo ""

# Core
h version >/dev/null 2>&1 && pass "version" || fail "version"
[ "$(h ping 2>&1)" = "pong" ] && pass "ping" || fail "ping"

# Todo
rm -f ~/.config/hiiro/todo.yml 2>/dev/null
h todo add "Test item" >/dev/null 2>&1 && pass "todo add" || fail "todo add"
h todo ls 2>&1 | grep -q "Test item" && pass "todo ls" || fail "todo ls"
h todo start 1 >/dev/null 2>&1 && pass "todo start" || fail "todo start"
h todo done 1 >/dev/null 2>&1 && pass "todo done" || fail "todo done"

# Pins
rm -f ~/.config/hiiro/pins/h 2>/dev/null
h pin set testkey testvalue >/dev/null 2>&1 && pass "pin set" || fail "pin set"
h pin get testkey 2>&1 | grep -q "testvalue" && pass "pin get" || fail "pin get"

# Plugin
h plugin ls 2>&1 | grep -q ".rb" && pass "plugin ls" || fail "plugin ls"

# Git (if in repo)
if git rev-parse --git-dir > /dev/null 2>&1; then
    h branch current >/dev/null 2>&1 && pass "branch current" || fail "branch current"
    h sha ls >/dev/null 2>&1 && pass "sha ls" || fail "sha ls"
fi

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
