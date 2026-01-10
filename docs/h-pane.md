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
| `kill` | Kill current pane | `tmux kill-pane` |
| `swap` | Swap panes | `tmux swap-pane` |
| `zoom` | Toggle pane zoom | `tmux resize-pane -Z` |
| `capture` | Capture pane contents | `tmux capture-pane` |
| `select` | Select a pane | `tmux select-pane` |
| `move` | Move pane to another window | `tmux move-pane` |
| `break` | Break pane into new window | `tmux break-pane` |
| `join` | Join pane from another window | `tmux join-pane` |
| `resize` | Resize pane | `tmux resize-pane` |

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

# Kill current pane
h pane kill

# Swap with the next pane
h pane swap -D

# Select pane by index
h pane select -t 2

# Resize current pane
h pane resize -D 10    # Grow down by 10 lines
h pane resize -R 20    # Grow right by 20 columns

# Break current pane into a new window
h pane break

# Join pane from window 3 into current window
h pane join -s :3
```

## Notes

- Pane indices start at 0
- Use `-t` to target specific panes (e.g., `-t 0`, `-t :.1`)
- All subcommands pass additional arguments directly to the underlying tmux command
