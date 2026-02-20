# Hiiro Documentation

This directory contains detailed documentation for all Hiiro subcommands.

[← Back to main README](../README.md)

## Subcommands

| Command | Description |
|---------|-------------|
| h-app | Manage app directories within tasks/projects |
| h-branch | Git branch management with fuzzy selection and copy |
| [h-buffer](h-buffer.md) | Tmux paste buffer management |
| h-claude | Claude CLI wrapper with tmux split support |
| h-commit | Select commits using fuzzy finder |
| h-config | Open config files (vim, git, tmux, zsh, starship, claude) |
| h-link | Manage saved links with URL, description, and shorthand |
| [h-pane](h-pane.md) | Tmux pane management |
| [h-plugin](h-plugin.md) | Manage hiiro plugins (list, edit, search) |
| h-pr | GitHub PR management via gh CLI |
| h-project | Project navigation with tmux session management |
| [h-session](h-session.md) | Tmux session management |
| h-sha | Extract short SHA from git log |
| h-todo | Todo list management with tags and task association |
| [h-window](h-window.md) | Tmux window management |
| h-wtree | Git worktree management |

## Base Commands

The main `h` command includes these built-in subcommands:

| Command | Description |
|---------|-------------|
| `h version` | Display the Hiiro version |
| `h ping` | Simple test command (returns "pong") |
| `h setup` | Install plugins and subcommands to system paths |
| `h edit` | Open the h script in your editor |
| `h alert` | macOS desktop notifications via terminal-notifier |
| `h task` | Task management across git worktrees (via Tasks plugin) |
| `h subtask` | Subtask management within tasks (via Tasks plugin) |

## Plugins

| Plugin | Description |
|--------|-------------|
| Pins | Per-command YAML key-value storage |
| Project | Project directory navigation with tmux session management |
| Tasks | Task lifecycle management across git worktrees with subtask support |
| Notify | macOS desktop notifications via terminal-notifier |

## Abbreviations

All commands support prefix abbreviation:

```sh
h buf ls      # h buffer ls
h ses ls      # h session ls
h win         # h window
```
