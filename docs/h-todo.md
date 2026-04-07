# h-todo

Manage a personal todo list with statuses, tags, and task associations.

## Synopsis

```bash
h todo <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ls [filters]` | List todo items (active by default) |
| `list [filters]` | Alias for `ls` |
| `add [text]` | Add a todo item |
| `rm [id]` | Remove an item |
| `remove [id]` | Alias for `rm` |
| `change [id]` | Modify an item's text, tags, or status |
| `start [id]` | Mark an item as started |
| `done [id]` | Mark an item as done |
| `skip [id]` | Mark an item as skipped |
| `reset [id]` | Reset an item to not_started |
| `search <query>` | Search items by text, tags, or task |
| `path` | Print path to the todo file |
| `editall` | Open the todo file in editor |
| `help` | Print usage |

Items have a permanent numeric ID (never reused). Statuses: `not_started` (`[ ]`), `started` (`[>]`), `done` (`[x]`), `skip` (`[-]`).

All `id` arguments accept either the item's ID or its index in the current list. Fuzzy-select is used when no ID is provided.

### add

Add a todo item. With no arguments, opens an editor for YAML input (supports adding multiple items at once). With text, creates the item directly.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--tags` | `-t` | Comma-separated tags |

**Examples**

```bash
h todo add
h todo add "Fix the login bug"
h todo add "Write tests" -t urgent,backend
```

### change

Modify an item. Fuzzy-selects from active items if no ID given.

**Options**

| Flag | Description |
|------|-------------|
| `--text TEXT` | New text |
| `--tags TAGS` | New tags |
| `--status STATUS` | New status |

**Examples**

```bash
h todo change 5 --text "Updated description"
h todo change 5 --status done
h todo change 5 --tags urgent,critical
h todo change 5 "Quick inline text change"
```

### ls / list

List todo items. Default: active (not done or skipped) items.

**Options**

| Flag | Description |
|------|-------------|
| `-a` / `--all` | Show all items including done/skip |
| `-s STATUS` / `--status STATUS` | Filter by status (comma-separated) |
| `-t TAG` / `--tag TAG` | Filter by tag |
| `--task TASK` | Filter by task name |

**Examples**

```bash
h todo ls
h todo ls -a
h todo ls -s done
h todo ls -s not_started,started
h todo ls -t urgent
h todo ls --task my-task
```

### path / editall

`path` prints the todo file path. `editall` opens it directly in your editor.

**Examples**

```bash
h todo path
h todo editall
```
### rm / remove

Remove an item. Fuzzy-selects from active items if no ID given.

**Examples**

```bash
h todo rm
h todo rm 5
```

### search

Search items by text, tags, or task name (case-insensitive substring match).

**Examples**

```bash
h todo search login
h todo search urgent
```

### start / done / skip / reset

Change item status. Fuzzy-select if no ID given. `reset` moves items back to `not_started` (fuzzy-selects from completed items).

**Examples**

```bash
h todo start
h todo start 5
h todo done 5
h todo skip 5
h todo reset 5
```

