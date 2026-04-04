# h-pm

Queue `/project-manager` skill prompts via `h queue add`.

## Synopsis

```bash
h pm [subcommand] [args]
```

With no subcommand, fuzzy-selects a project-manager command interactively and queues it.

Each subcommand builds a `/project-manager <subcmd> [args]` prompt and passes it to `h queue add` via stdin.

## Subcommands

| Subcommand | Args | Description |
|------------|------|-------------|
| `discover` | `[project]` | Auto-discover projects and tasks from PRs, worktrees, olive runs |
| `resume` | `<project>` | Show "where was I?" session briefing |
| `status` | `<project>` | Show project status overview |
| `add` | `<project> <task>` | Add a new task to a project |
| `start` | `<project> <task>` | Load context and begin working on a task |
| `plan` | `<project> <task>` | Generate or update a proposal document |
| `complete` | `<project> <task>` | Mark a task as complete |
| `ref` | `<project> [url-or-path]` | Add a reference document (PRD, spec, Figma, etc.) |
| `impact` | `<project> <task>` | Analyze cascading impact of a task deviation |
| `archive` | `<project>` | Archive a completed or stale project |
| `unarchive` | `<project>` | Restore an archived project |
| `help` | — | Print usage information |

## Examples

```bash
# Fuzzy-select a command interactively
h pm

# Discover untracked work automatically
h pm discover

# Start a specific project session briefing
h pm resume my-project

# Add a new task to a project
h pm add my-project "Implement OAuth login"

# Mark a task complete
h pm complete my-project "Implement OAuth login"

# Archive a finished project
h pm archive my-old-project
```
