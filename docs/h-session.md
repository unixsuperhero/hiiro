# h-session

Tmux session management.

[← Back to docs](README.md) | [← Back to main README](../README.md)

## Usage

```sh
h session <subcommand> [args...]
```

## Subcommands

| Command | Description | Tmux equivalent |
|---------|-------------|-----------------|
| `ls`, `list` | List all sessions | `tmux list-sessions` |
| `new` | Create a new session | `tmux new-session` |
| `kill` | Kill a session (fuzzy select if no name) | `tmux kill-session` |
| `attach` | Attach to a session (fuzzy select if no name) | `tmux attach-session` |
| `rename` | Rename a session | `tmux rename-session` |
| `switch` | Switch to another session (fuzzy select) | `tmux switch-client` |
| `detach` | Detach from current session | `tmux detach-client` |
| `has` | Check if session exists | `tmux has-session` |
| `info` | Show current session info | `tmux display-message` |
| `open` | Open/switch to a session by name | - |
| `select` | Select a session with fuzzy finder | - |
| `copy` | Copy session name to clipboard | `pbcopy` |

## Examples

```sh
# List all sessions
h session ls

# Create a new session named "work"
h session new work

# Create detached session
h session new -d -s background

# Attach to a session (select if no name given)
h session attach
h session attach work

# Kill a session (select if no name given)
h session kill
h session kill old-session

# Rename current session
h session rename newname

# Switch to another session (interactive)
h session switch

# Select a session and print its name
h session select

# Copy session name to clipboard
h session copy

# Open a session (create if doesn't exist)
h session open myproject

# Check if session exists (useful in scripts)
h session has mysession && echo "exists"

# Show current session info
h session info
# => mysession: 5 windows, attached
```

## Notes

- Use `-t` to target specific sessions
- All subcommands pass additional arguments directly to the underlying tmux command
- The `info` command shows session name, window count, and attach status
- The `kill`, `attach`, `switch`, `select`, and `copy` commands use fuzzy finding when no name is provided
