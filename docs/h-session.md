# h-session

Manage tmux sessions — list, create, kill, attach, rename, switch, and detect orphans.

## Synopsis

```bash
h session <subcommand> [args]
```

## Subcommands

| Subcommand | Aliases | Description |
|------------|---------|-------------|
| `ls` | `list` | List all tmux sessions |
| `new` | — | Create a new tmux session |
| `kill` | — | Kill a session |
| `attach` | — | Attach to a session |
| `rename` | — | Rename a session |
| `switch` | — | Switch the current client to a session |
| `detach` | — | Detach the current client |
| `has` | — | Check whether a session exists |
| `info` | — | Show basic info about a session |
| `open` | — | Switch to or attach to a named session |
| `sh` | — | Open a new window in a session and switch to it |
| `select` | — | Fuzzy-select a session name and print it |
| `copy` | — | Fuzzy-select a session name and copy to clipboard |
| `orphans` | — | List sessions with no associated hiiro task |
| `okill` | — | Interactively kill orphan sessions |

## Subcommand Details

### `ls` / `list`

List all tmux sessions. Extra args are passed to `tmux list-sessions`.

```bash
h session ls
h session ls -F '#{session_name}: #{session_windows} windows'
```

### `new`

Create a new tmux session with an optional name. Extra args are forwarded to `tmux new-session`.

```bash
h session new
h session new my-work
h session new my-work -d    # detached
```

### `kill`

Kill a session. Fuzzy-selects if no name given.

```bash
h session kill
h session kill my-work
```

### `attach`

Attach to a session. Fuzzy-selects if no name given.

```bash
h session attach
h session attach my-work
```

### `rename`

Rename a session.

```bash
h session rename old-name new-name
```

### `switch`

Switch the current tmux client to a session. Fuzzy-selects if no name given.

```bash
h session switch
h session switch my-work
```

### `detach`

Detach the current client from its session.

```bash
h session detach
```

### `has`

Check whether a session exists. Exits 0 if it does, 1 if not.

```bash
h session has my-work && echo "exists"
```

### `info`

Show basic info about the current (or named) session: name, window count, attached status.

```bash
h session info
h session info my-work
```

### `open`

Switch to (or attach to) a named session.

```bash
h session open my-work
```

### `sh`

Open a new tmux window in a session and switch to it. Optionally run a command in the new window.

```bash
h session sh my-work
h session sh my-work bundle exec rails console
```

### `select` / `copy`

Fuzzy-select a session name and print it or copy to clipboard.

```bash
name=$(h session select)
h session copy
```

### `orphans`

List sessions that have no associated hiiro task (comparing against `tasks.yml`).

```bash
h session orphans
```

### `okill`

Open a YAML editor pre-filled with orphan session names. Delete the sessions you leave in the file when you save.

```bash
h session okill
```

## Examples

```bash
# Create a session for a new project
h session new my-feature

# Switch to a session interactively
h session switch

# Clean up stale sessions
h session orphans
h session okill

# Check if a session exists before creating
h session has my-feature || h session new my-feature
```
