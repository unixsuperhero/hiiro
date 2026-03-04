#!/bin/bash
# h-tmux-plugins.tmux -- Main entry point (sourced by TPM)
# Provides: Jumplist navigation + Notification tracker via Hiiro bin commands

# Helper to read tmux option with default
get_option() {
  local option="$1"
  local default="$2"
  local value
  value=$(tmux show-option -gqv "$option" 2>/dev/null || true)
  echo "${value:-$default}"
}

# --- Configuration ---
JUMPLIST_BACK_KEY=$(get_option "@jumplist-back-key" "C-b")
JUMPLIST_FORWARD_KEY=$(get_option "@jumplist-forward-key" "C-f")
NOTIFY_MENU_KEY=$(get_option "@notify-menu-key" "C-n")
NOTIFY_CLEAR_KEY=$(get_option "@notify-clear-key" "M-n")

# --- Jumplist hooks ---
tmux set-hook -g after-select-pane "run-shell -b 'h jumplist record'"
tmux set-hook -g after-select-window "run-shell -b 'h jumplist record'"

# --- Jumplist keybindings ---
tmux bind-key -r "$JUMPLIST_BACK_KEY" run-shell "h jumplist back"
tmux bind-key -r "$JUMPLIST_FORWARD_KEY" run-shell "h jumplist forward"

# --- Notification keybindings ---
tmux bind-key "$NOTIFY_MENU_KEY" run-shell "h notify menu"
tmux bind-key "$NOTIFY_CLEAR_KEY" run-shell "h notify clear"
