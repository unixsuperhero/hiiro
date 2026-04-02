# h-session

Manage tmux sessions — list, create, kill, attach, rename, switch, and detect orphans.

## Usage

```
h session <subcommand> [args]
```

## Subcommands

### `ls` [alias: `list`]

List all tmux sessions. Extra args passed to `tmux list-sessions`.

**Args:** `[tmux_args...]`

### `new`

Create a new tmux session.

**Args:** `[name] [tmux_args...]`

### `kill`

Kill a session (fuzzy-select if no name given).

**Args:** `[name]`

### `attach`

Attach to a session (fuzzy-select if no name given).

**Args:** `[name]`

### `rename`

Rename a session.

**Args:** `[old_name] <new_name>`

### `switch`

Switch the current client to a session (fuzzy-select if no name).

**Args:** `[name]`

### `detach`

Detach the current client from its session.

**Args:** `[tmux_args...]`

### `has`

Check whether a session exists (exits 0 or 1).

**Args:** `[name]`

### `info`

Show basic info about the current (or named) session: name, window count, attached status.

**Args:** `[name]`

### `open`

Switch to or attach to a named session.

**Args:** `<name>`

### `sh`

Open a new window in a session and switch to it. Optionally run a command in the new window.

**Args:** `<session_name> [cmd...]`

### `select`

Fuzzy-select a session name and print it.

### `copy`

Fuzzy-select a session name and copy it to clipboard.

### `orphans`

List sessions that have no associated hiiro task.

### `okill`

Open a YAML editor pre-filled with orphan session names; delete all sessions you leave in the file.
