# h-todo

Manage a personal todo list with statuses, tags, and task associations.

## Usage

```
h todo <subcommand> [args]
```

## Subcommands

### `ls` [alias: `list`]

List todo items. Defaults to active (not done/skip) items.

**Args (inline flags):**
- `-a`, `--all` — Show all items including done/skip
- `-s STATUS`, `--status STATUS` — Filter by status (comma-separated: `not_started`, `started`, `done`, `skip`)
- `-t TAG`, `--tag TAG` — Filter by tag
- `--task TASK` — Filter by task name

### `add`

Add one or more todo items. With no args, opens an editor for YAML bulk input. With text, adds directly. Use `-t` for tags.

**Args:** `[text...] [-t tags]`

### `rm` [alias: `remove`]

Remove a todo item by ID. Fuzzy-selects from active items if no ID given.

**Args:** `[id_or_index]`

### `change`

Modify a todo item's text, tags, or status.

**Args:** `<id_or_index> [new_text] [--text TEXT] [--tags TAGS] [--status STATUS]`

### `start`

Mark a todo item as started (`[>]`). Fuzzy-selects if no ID given.

**Args:** `[id_or_index]`

### `done`

Mark a todo item as done (`[x]`). Fuzzy-selects if no ID given.

**Args:** `[id_or_index]`

### `skip`

Mark a todo item as skipped (`[-]`). Fuzzy-selects if no ID given.

**Args:** `[id_or_index]`

### `reset`

Reset a todo item to `not_started` (`[ ]`). Fuzzy-selects from completed items if no ID given.

**Args:** `[id_or_index]`

### `search`

Search items by text, tags, or task name.

**Args:** `<query...>`

### `path`

Print the path to the todo YAML file.

### `editall`

Open the raw todo YAML file in your editor.

### `help`

Print usage information and status icon legend.

## Status Icons

| Icon | Status |
|---|---|
| `[ ]` | not_started |
| `[>]` | started |
| `[x]` | done |
| `[-]` | skip |
