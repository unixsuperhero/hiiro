# h subtask

Manage subtasks within the current parent task. Subtasks follow the same worktree + tmux session model as top-level tasks, but are scoped under the current task (e.g. `my-feature/auth`).

All subcommands are identical to [h task](h-task.md) but operate on the subtask scope. Subtask names are relative (e.g. `auth` rather than `my-feature/auth`).

## Synopsis

```bash
h subtask <subcommand> [args]
```

## Scope behavior

When in a task session, `h subtask` lists and operates on subtasks of the current parent task. A synthetic `main` subtask is always shown, representing the parent task's primary worktree.

Subtask names are stored as `parent/child` (e.g. `my-feature/auth`) but displayed as their short name (`auth`) in subtask context.

## Subcommands

All subcommands from [h task](h-task.md) are available. Key ones:

| Subcommand | Description |
|------------|-------------|
| `ls` / `list` | List subtasks of the current task |
| `start <name>` | Create or switch to a subtask |
| `switch [name]` | Switch to a subtask session |
| `stop [name]` | Stop a subtask (preserves worktree) |
| `current` | Print the current subtask name |
| `status` / `st` | Show current subtask details |
| `branch [name]` | Print branch for a subtask |
| `tree [name]` | Print worktree name for a subtask |
| `session [name]` | Print session name for a subtask |
| `cd [name] [app]` | Send `cd` to current pane |
| `path [name] [app]` | Print path to subtask directory |
| `todo [args]` | Manage todos for current subtask |
| `queue [args]` | Claude queue scoped to current subtask |

## Examples

```bash
h subtask ls
h subtask start auth
h subtask switch
h subtask switch auth
h subtask current
h subtask status
h subtask cd auth
h subtask stop auth
```
