# h-pm

Queue `/project-manager` skill prompts via `h queue add`.

## Usage

```
h pm [subcommand] [args]
```

With no subcommand, fuzzy-selects a project-manager command interactively.

## Subcommands

Each subcommand builds a `/project-manager <subcmd> [args]` prompt and queues it via `h queue add`.

### `discover`

Auto-discover projects and tasks from PRs, worktrees, and olive runs.

**Args:** `[project]`

### `resume`

Show a "where was I?" session briefing for a project.

**Args:** `<project>`

### `status`

Show a project status overview.

**Args:** `<project>`

### `add`

Add a new task to a project.

**Args:** `<project> <task>`

### `start`

Load context and begin working on a task.

**Args:** `<project> <task>`

### `plan`

Generate or update a proposal document for a task.

**Args:** `<project> <task>`

### `complete`

Mark a task as complete.

**Args:** `<project> <task>`

### `ref`

Add a reference document (PRD, spec, Figma link, etc.) to a project.

**Args:** `<project> [url-or-path]`

### `impact`

Analyze cascading impact of a task deviation on child tasks.

**Args:** `<project> <task>`

### `archive`

Archive a completed or stale project.

**Args:** `<project>`

### `unarchive`

Restore an archived project.

**Args:** `<project>`

### `help`

Print usage information.
