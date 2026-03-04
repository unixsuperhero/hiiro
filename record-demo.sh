#!/usr/bin/env bash
#
# Record a Hiiro demo typescript
#
# Usage:
#   bash record-demo.sh
#
# This records a terminal session to 'demo.typescript' that can be
# played back with:
#   script -p demo.typescript
#
# The recording simulates typing commands and showing their output.

TYPESCRIPT_FILE="demo.typescript"

# If called without the __INNER flag, wrap ourselves in `script -r`
if [[ -z "$__HIIRO_DEMO_INNER" ]]; then
  export __HIIRO_DEMO_INNER=1
  echo "Recording demo to $TYPESCRIPT_FILE ..."
  echo "Play back with: script -p $TYPESCRIPT_FILE"
  echo ""
  script -r "$TYPESCRIPT_FILE" bash "$0"
  exit $?
fi

# ── Helpers ──

BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
WHITE="\033[37m"
RESET="\033[0m"

# Simulate typing a command character by character
typecmd() {
  local cmd="$1"
  echo -ne "${GREEN}\$ ${BOLD}${WHITE}"
  for (( i=0; i<${#cmd}; i++ )); do
    echo -n "${cmd:$i:1}"
    sleep 0.08
  done
  echo -e "${RESET}"
  sleep 1.5  # pause after typing so viewer can read the command
}

# Print a section header
header() {
  echo ""
  echo -e "${BOLD}${CYAN}━━━ $1 ━━━${RESET}"
  echo ""
  sleep 2.5  # time to read the section heading
}

# Pause after output so viewer can read what happened
pause() {
  sleep "${1:-3}"
}

# Run a command with simulated typing
run() {
  typecmd "$1"
  eval "$1"
  echo ""
  pause
}

# ── Banner ──

clear
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║         Hiiro Quick Demo             ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════╝${RESET}"
echo ""
echo -e "Hiiro is a lightweight CLI framework for Ruby."
echo -e "It gives you subcommand dispatch, abbreviation"
echo -e "matching, and a plugin system."
echo ""
sleep 4

# ── Abbreviations ──

header "Top-level commands"
run "h || true"

header "Abbreviation matching"
echo -e "${DIM}h to  →  resolves to  →  h todo${RESET}"
echo ""
sleep 2
run "h to || true"

header "Deep abbreviations"
echo -e "${DIM}h to ls  →  resolves to  →  h todo ls${RESET}"
echo ""
sleep 2
run "h to ls || true"

header "Ambiguous abbreviations"
echo -e "${DIM}h s  →  matches multiple commands${RESET}"
echo ""
sleep 2
run "h s || true"

header "Narrowing down"
echo -e "${DIM}h se  →  narrows the match${RESET}"
echo ""
sleep 2
run "h se || true"

header "Chained abbreviations"
echo -e "${DIM}h wi ls  →  resolves to  →  h window ls${RESET}"
echo ""
sleep 2
run "h wi ls || true"

echo -e "${DIM}h br  →  resolves to  →  h branch${RESET}"
echo ""
sleep 2
run "h br || true"

# ── h task ──

header "h task — worktree-based task management"
run "h task || true"

run "h task ls || true"

echo -e "${DIM}h ta ls  →  resolves to  →  h task ls${RESET}"
echo ""
sleep 2
run "h ta ls || true"

# ── h subtask ──

header "h subtask — scoped subtask management"
run "h subtask || true"

run "h subtask ls || true"

echo -e "${DIM}h su ls  →  resolves to  →  h subtask ls${RESET}"
echo ""
sleep 2
run "h su ls || true"

# ── h queue ──

header "h queue — background job queue"
run "h queue || true"

run "h queue ls || true"

run "h queue status || true"

echo -e "${DIM}h q ls  →  resolves to  →  h queue ls${RESET}"
echo ""
sleep 2
run "h q ls || true"

# ── Wrap up ──

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║           Demo Complete!             ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════╝${RESET}"
echo ""
echo -e "Key takeaways:"
echo -e "  ${CYAN}•${RESET} Type just enough letters to be unambiguous"
echo -e "  ${CYAN}•${RESET} Abbreviations work at every level"
echo -e "  ${CYAN}•${RESET} ${WHITE}h task${RESET} / ${WHITE}h subtask${RESET} manage worktree-based workflows"
echo -e "  ${CYAN}•${RESET} ${WHITE}h queue${RESET} manages background jobs"
echo ""
sleep 4

exit 0
