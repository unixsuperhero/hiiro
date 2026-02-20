# h-pane

Tmux pane management.

[← Back to docs](README.md) | [← Back to main README](../README.md)

## Usage

```sh
h pane <subcommand> [args...]
```

## Subcommands

| Command | Description | Tmux equivalent |
|---------|-------------|-----------------|
| `ls` | List panes in current window | `tmux list-panes` |
| `lsa` | List all panes in all sessions | `tmux list-panes -a` |
| `split` | Split pane (default: vertical) | `tmux split-window` |
| `splitv` | Split pane vertically | `tmux split-window -v` |
| `splith` | Split pane horizontally | `tmux split-window -h` |
| `kill` | Kill a pane (fuzzy select if no target) | `tmux kill-pane` |
| `swap` | Swap panes | `tmux swap-pane` |
| `zoom` | Toggle pane zoom | `tmux resize-pane -Z` |
| `capture` | Capture pane contents | `tmux capture-pane` |
| `select` | Select a pane with fuzzy finder | - |
| `copy` | Copy pane identifier to clipboard | `pbcopy` |
| `sw`, `switch` | Switch to a pane | `tmux switch-client` |
| `move` | Move pane to another window | `tmux move-pane` |
| `break` | Break pane into new window | `tmux break-pane` |
| `join` | Join pane from another window | `tmux join-pane` |
| `resize` | Resize pane | `tmux resize-pane` |
| `width` | Set pane width | `tmux resize-pane -x` |
| `height` | Set pane height | `tmux resize-pane -y` |
| `info` | Show pane information | - |

## Examples

```sh
# List panes in current window
h pane ls

# Split horizontally (side by side)
h pane splith

# Split vertically (top/bottom)
h pane splitv

# Toggle zoom on current pane
h pane zoom

# Kill current pane (or select one)
h pane kill

# Select a pane interactively
h pane select

# Copy pane identifier to clipboard
h pane copy

# Switch to a different pane
h pane switch

# Swap with the next pane
h pane swap -D

# Set pane width/height
h pane width 80
h pane height 20

# Resize current pane
h pane resize -D 10    # Grow down by 10 lines
h pane resize -R 20    # Grow right by 20 columns

# Show info about current pane
h pane info

# Break current pane into a new window
h pane break

# Join pane from window 3 into current window
h pane join -s :3
```

## Notes

- Pane indices start at 0
- Use `-t` to target specific panes (e.g., `-t 0`, `-t :.1`)
- All subcommands pass additional arguments directly to the underlying tmux command
- The `select`, `copy`, `kill`, and `switch` commands use fuzzy finding when no target is specified
