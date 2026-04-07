# h-session

Manage tmux sessions — list, create, kill, attach, rename, switch, and detect orphans.

## Synopsis

```bash
h session <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ls` / `list [args]` | List all sessions |
| `new [name]` | Create a new session |
| `kill [name]` | Kill a session |
| `attach [name]` | Attach to a session |
| `rename [old] <new>` | Rename a session |
| `switch [name]` | Switch to a session |
| `detach [args]` | Detach the current client |
| `has [name]` | Check if a session exists |
| `info [name]` | Show session info |
| `open [name]` | Open a session (switch if in tmux, attach if not) |
| `sh <session> [cmd]` | Open a new window in a session (or run a command) |
| `select` | Fuzzy-select and print a session name |
| `copy` | Fuzzy-select and copy session name to clipboard |
| `orphans` | List sessions not associated with any task |
| `okill` | Interactively kill orphan sessions |

Session names are resolved interactively when not provided. Extra arguments to passthrough subcommands are forwarded to `tmux`.

### attach

Attach to a session. Fuzzy-select if no name given.

**Examples**

```bash
h session attach
h session attach my-project
```

### kill

Kill a session. Fuzzy-select if no name given.

**Examples**

```bash
h session kill
h session kill my-project
```

### ls / list

List all sessions. Extra arguments are forwarded to `tmux list-sessions`.

**Examples**

```bash
h session ls
h session list
```

### new

Create a new session, optionally named.

**Examples**

```bash
h session new
h session new my-project
```

### open

Open a session: switches if already in tmux, attaches if not. Creates the session if it doesn't exist.

**Examples**

```bash
h session open my-project
```

### orphans / okill

`orphans` lists sessions that have no associated task. `okill` shows those sessions in an editor for you to review, then kills those that remain in the YAML list when you save.

**Examples**

```bash
h session orphans
h session okill
```
### rename

Rename a session. Fuzzy-selects the old name if not provided.

**Examples**

```bash
h session rename my-project new-name
h session rename new-name   # fuzzy-select old session
```

### select / copy

Fuzzy-select a session name and print it or copy to clipboard.

**Examples**

```bash
h session select
sess=$(h session select)
h session copy
```

### sh

Open a new window in a session and optionally run a command. Switches to the session.

**Examples**

```bash
h session sh my-project
h session sh my-project bundle exec rails console
```

### switch

Switch to a session (stays within tmux). Fuzzy-select if no name given.

**Examples**

```bash
h session switch
h session switch my-project
```

