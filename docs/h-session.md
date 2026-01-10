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
| `ls` | List all sessions | `tmux list-sessions` |
| `new` | Create a new session | `tmux new-session` |
| `kill` | Kill a session | `tmux kill-session` |
| `attach` | Attach to a session | `tmux attach-session` |
| `rename` | Rename a session | `tmux rename-session` |
| `switch` | Switch to another session | `tmux switch-client` |
| `detach` | Detach from current session | `tmux detach-client` |
| `has` | Check if session exists | `tmux has-session` |
| `info` | Show current session info | `tmux display-message` |

## Examples

```sh
# List all sessions
h session ls

# Create a new session named "work"
h session new -s work

# Create detached session
h session new -d -s background

# Attach to a session
h session attach -t work

# Kill a session
h session kill -t old-session

# Rename current session
h session rename newname

# Switch to another session
h session switch -t other

# Check if session exists (useful in scripts)
h session has -t mysession && echo "exists"

# Show current session info
h session info
# => mysession: 5 windows, 1 attached
```

## Notes

- Use `-t` to target specific sessions
- All subcommands pass additional arguments directly to the underlying tmux command
- The `info` command shows session name, window count, and attach count
