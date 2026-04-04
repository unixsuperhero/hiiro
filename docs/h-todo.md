# h-todo

Manage a personal todo list with statuses, tags, and task associations.

## Synopsis

```bash
h todo <subcommand> [args]
```

Todo items are stored in SQLite (`~/.config/hiiro/hiiro.db`, table `todos`) with a YAML backup at `~/.config/hiiro/todos.yml`.

## Subcommands

| Subcommand | Aliases | Description |
|------------|---------|-------------|
| `ls` | `list` | List todo items |
| `add` | — | Add one or more todo items |
| `rm` | `remove` | Remove a todo item |
| `change` | — | Modify a todo item |
| `start` | — | Mark item as started |
| `done` | — | Mark item as done |
| `skip` | — | Mark item as skipped |
| `reset` | — | Reset item to not started |
| `search` | — | Search items by text, tags, or task |
| `path` | — | Print path to the todo YAML file |
| `editall` | — | Open the raw todo YAML in editor |
| `help` | — | Print usage and status icon legend |

## Status Icons

| Icon | Status |
|------|--------|
| `[ ]` | not_started |
| `[>]` | started |
| `[x]` | done |
| `[-]` | skip |

## Subcommand Details

### `ls` / `list`

List todo items. Defaults to active (not done/skip) items.

**Inline flags:**

| Flag | Description |
|------|-------------|
| `-a`, `--all` | Show all items including done/skip |
| `-s STATUS`, `--status STATUS` | Filter by status (comma-separated: `not_started`, `started`, `done`, `skip`) |
| `-t TAG`, `--tag TAG` | Filter by tag |
| `--task TASK` | Filter by task name |

```bash
h todo ls
h todo ls -a
h todo ls -s done
h todo ls -s not_started,started
h todo ls -t urgent
h todo ls --task my-feature
```

### `add`

Add one or more todo items. With no args, opens a YAML editor for bulk input. With text, adds directly. Use `-t` for tags.

```bash
h todo add
h todo add "Fix the login bug"
h todo add "Write docs" -t writing
h todo add "Review PR #123" -t pr
```

### `rm` / `remove`

Remove a todo item by ID or index. Fuzzy-selects from active items if no ID given.

```bash
h todo rm
h todo rm 42
h todo rm 5
```

### `change`

Modify a todo item's text, tags, or status.

```bash
h todo change 42 "Updated task description"
h todo change 42 --tags "urgent,blocked"
h todo change 42 --status started
```

### `start` / `done` / `skip` / `reset`

Change a todo item's status. Fuzzy-selects if no ID given.

```bash
h todo start           # fuzzy select and start
h todo start 42
h todo done 42
h todo skip 42
h todo reset 42        # back to not_started
```

### `search`

Search items by text, tags, or task name. All terms are matched (AND logic).

```bash
h todo search login
h todo search pr review
```

### `path`

Print the path to the todo YAML backup file.

```bash
h todo path
```

### `editall`

Open the raw todo YAML file in your editor.

```bash
h todo editall
```

## Examples

```bash
# Add items for today's work
h todo add "Review PR #123" -t pr
h todo add "Fix flaky test" -t test
h todo add "Update changelog"

# Start working on an item
h todo start

# Check off completed work
h todo done 42

# See everything in progress
h todo ls -s started

# Skip a blocked item
h todo skip 15

# Review all items for a task
h todo ls --task my-feature
```
