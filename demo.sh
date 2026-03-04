#!/usr/bin/env bash
#
# Hiiro Quick Demo
#
# Usage: bash demo.sh
#
# Walks through key Hiiro features with commentary.
# Each step pauses so you can see the output.

set -e

BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

step=0

demo() {
  step=$((step + 1))
  echo ""
  echo -e "${BOLD}${CYAN}── Step $step: $1${RESET}"
  echo -e "${DIM}$ $2${RESET}"
  echo ""
  eval "$2"
  echo ""
  echo -e "${DIM}(press enter to continue)${RESET}"
  read -r
}

echo -e "${BOLD}${GREEN}"
echo "╔══════════════════════════════════════╗"
echo "║         Hiiro Quick Demo             ║"
echo "╚══════════════════════════════════════╝"
echo -e "${RESET}"
echo "Hiiro is a lightweight CLI framework for Ruby."
echo "It gives you subcommand dispatch, abbreviation"
echo "matching, and a plugin system."
echo ""
echo -e "${DIM}(press enter to start)${RESET}"
read -r

# ─── Abbreviations ───

demo "List all top-level commands" \
     "h || true"

demo "Abbreviation matching: 'h to' resolves to 'h todo'" \
     "h to || true"

demo "Abbreviations work at every level: 'h to ls' = 'h todo ls'" \
     "h to ls || true"

demo "Ambiguous abbreviations show candidates: 'h s' matches multiple commands" \
     "h s || true"

demo "More specific prefix resolves: 'h se' narrows to 'h serve' (if unambiguous) or shows remaining matches" \
     "h se || true"

demo "Abbreviations chain: 'h wi ls' = 'h window ls'" \
     "h wi ls || true"

demo "Even shorter: 'h br' = 'h branch'" \
     "h br || true"

# ─── h task ───

demo "h task - manage worktree-based tasks (via Tasks plugin)" \
     "h task || true"

demo "h task ls - list current tasks" \
     "h task ls || true"

demo "Abbreviation: 'h ta ls' = 'h task ls'" \
     "h ta ls || true"

# ─── h subtask ───

demo "h subtask - same interface as task, scoped to subtasks" \
     "h subtask || true"

demo "h subtask ls - list current subtasks" \
     "h subtask ls || true"

demo "Abbreviation: 'h su ls' = 'h subtask ls'" \
     "h su ls || true"

# ─── h queue ───

demo "h queue - background job queue management" \
     "h queue || true"

demo "h queue ls - list queued jobs" \
     "h queue ls || true"

demo "h queue status - show queue status" \
     "h queue status || true"

demo "Abbreviation: 'h q ls' = 'h queue ls'" \
     "h q ls || true"

# ─── Wrap up ───

echo -e "${BOLD}${GREEN}"
echo "╔══════════════════════════════════════╗"
echo "║           Demo Complete!             ║"
echo "╚══════════════════════════════════════╝"
echo -e "${RESET}"
echo "Key takeaways:"
echo "  - Type just enough letters to be unambiguous"
echo "  - Abbreviations work at every level (command + subcommand)"
echo "  - 'h task' / 'h subtask' manage worktree-based workflows"
echo "  - 'h queue' manages background jobs"
echo ""
