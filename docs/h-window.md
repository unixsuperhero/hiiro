# h-window

Tmux window management.

[← Back to docs](README.md) | [← Back to main README](../README.md)

## Usage

```sh
h window <subcommand> [args...]
```

## Subcommands

| Command | Description | Tmux equivalent |
|---------|-------------|-----------------|
| `ls` | List windows in current session | `tmux list-windows` |
| `lsa` | List all windows in all sessions | `tmux list-windows -a` |
| `new` | Create a new window | `tmux new-window` |
| `kill` | Kill a window (fuzzy select if no target) | `tmux kill-window` |
| `rename` | Rename current window | `tmux rename-window` |
| `swap` | Swap windows | `tmux swap-window` |
| `move` | Move window | `tmux move-window` |
| `select` | Select a window with fuzzy finder | - |
| `copy` | Copy window identifier to clipboard | `pbcopy` |
| `sw`, `switch` | Switch to a window | `tmux select-window` |
| `next` | Go to next window | `tmux next-window` |
| `prev` | Go to previous window | `tmux previous-window` |
| `last` | Go to last active window | `tmux last-window` |
| `link` | Link window to another session | `tmux link-window` |
| `unlink` | Unlink window from session | `tmux unlink-window` |
| `info` | Show window information | - |

## Examples

```sh
# List windows in current session
h window ls

# List all windows across all sessions
h window lsa

# Create a new window
h window new

# Create window with a name
h window new editor

# Kill window (select if no target)
h window kill

# Rename current window
h window rename mywindow

# Select a window interactively
h window select

# Copy window identifier to clipboard
h window copy

# Switch to a window (interactive)
h window switch

# Navigate windows
h window next
h window prev
h window last

# Show info about a window
h window info

# Swap current window with window 1
h window swap -t 1

# Move window to index 5
h window move -t 5

# Link window 2 to session "other"
h window link -s :2 -t other:
```

## Notes

- Window indices typically start at 0 or 1 depending on `base-index` setting
- Use `-t` to target specific windows (e.g., `-t 0`, `-t :2`, `-t session:window`)
- All subcommands pass additional arguments directly to the underlying tmux command
- The `select`, `copy`, `kill`, and `switch` commands use fuzzy finding when no target is specified
