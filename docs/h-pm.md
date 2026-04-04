# h-pm

Queue `/project-manager` skill prompts via `h queue add`.

## Synopsis

```bash
h pm [subcommand] [args]
```

## Description

`h pm` is a launcher that builds `/project-manager` prompts and queues them via `h queue add`. With no subcommand, opens a fuzzy picker of all available commands.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `discover [project]` | Auto-discover projects/tasks from PRs, worktrees, olive runs |
| `resume <project>` | Show a "where was I?" session briefing |
| `status <project>` | Show project status overview |
| `add <project> <task>` | Add a new task to a project |
| `start <project> <task>` | Load context and begin working on a task |
| `plan <project> <task>` | Generate/update proposal doc for a task |
| `complete <project> <task>` | Mark a task as complete |
| `ref <project> [url-or-path]` | Add a reference document (PRD, spec, Figma, etc.) |
| `impact <project> <task>` | Analyze cascading impact of task deviation |
| `archive <project>` | Archive a completed/stale project |
| `unarchive <project>` | Restore an archived project |
| `help` | Print usage |

### discover

Queue a prompt to auto-discover untracked work from PRs, worktrees, and olive runs.

**Examples**

```bash
h pm discover
h pm discover my-project
```

### resume

Queue a "where was I?" briefing prompt for a project.

**Examples**

```bash
h pm resume my-project
```

### status

Queue a project status overview prompt.

**Examples**

```bash
h pm status my-project
```

### add

Queue a prompt to add a new task to a project.

**Examples**

```bash
h pm add my-project new-task
```

### start

Queue a prompt to load context and begin working on a task.

**Examples**

```bash
h pm start my-project my-task
```

### plan

Queue a prompt to generate or update the proposal doc for a task.

**Examples**

```bash
h pm plan my-project my-task
```

### complete

Queue a prompt to mark a task as complete.

**Examples**

```bash
h pm complete my-project my-task
```

### ref

Queue a prompt to add a reference document to a project.

**Examples**

```bash
h pm ref my-project https://docs.example.com/spec
```

### impact

Queue a prompt to analyze the cascading impact of deviating from a task plan.

**Examples**

```bash
h pm impact my-project my-task
```

### archive / unarchive

Queue prompts to archive or restore a project.

**Examples**

```bash
h pm archive old-project
h pm unarchive old-project
```
