# h-buffer

Tmux paste buffer management.

[← Back to docs](README.md) | [← Back to main README](../README.md)

## Usage

```sh
h buffer <subcommand> [args...]
```

## Subcommands

| Command | Description | Tmux equivalent |
|---------|-------------|-----------------|
| `ls` | List all paste buffers | `tmux list-buffers` |
| `show` | Display buffer contents | `tmux show-buffer` |
| `save` | Save buffer to file | `tmux save-buffer` |
| `load` | Load buffer from file | `tmux load-buffer` |
| `set` | Set buffer contents | `tmux set-buffer` |
| `paste` | Paste buffer into pane | `tmux paste-buffer` |
| `delete` | Delete a buffer | `tmux delete-buffer` |
| `choose` | Interactive buffer selection | `tmux choose-buffer` |
| `clear` | Delete all buffers | (loops through all buffers) |
| `select` | Select a buffer with fuzzy finder | - |
| `copy` | Copy buffer contents to clipboard | `pbcopy` |

## Examples

```sh
# List all buffers
h buffer ls

# Show the most recent buffer (or select one)
h buffer show

# Copy buffer to system clipboard
h buffer copy

# Save buffer to a file
h buffer save ~/clipboard.txt

# Load file into buffer
h buffer load ~/mytext.txt

# Paste buffer into current pane
h buffer paste

# Select a buffer interactively
h buffer select

# Clear all buffers
h buffer clear
```

## Notes

- All subcommands pass additional arguments directly to the underlying tmux command
- The `select` and `copy` commands use fuzzy finding (`sk` or `fzf`) when no buffer is specified
- Use `tmux list-buffers -F '#{buffer_name}: #{buffer_sample}'` for more detailed output
