# h-pm

Queue `/project-manager` skill prompts in the `h queue` pending queue.

## Synopsis

```bash
h pm [subcommand] [args]
```

## Description

`h pm SUBCMD ARGS...` writes the prompt `/project-manager SUBCMD ARGS...` to the pending queue (`~/.local/share/hiiro/queue/pending/`) in process, through the same queue code as `h queue add` (no `h` on `PATH` is needed), and prints `Created: PATH`. As with piped `h queue add`, a current task is recorded in the prompt's frontmatter (`task_name`).

Each prompt is named after its command: `pm-SUBCMD` plus the arguments, slugged (lowercase, runs of other characters become `-`, at most 60 characters). `h pm status proj` writes `pm-status-proj.md`; while that file is still pending, the next one is `pm-status-proj-2.md`, then `-3`, and so on.

With no subcommand, `h pm` opens the `pm-commands` picker ([picker](picker.md)) of the subcommands with their descriptions and queues `/project-manager SUBCMD` for the chosen one (named `pm-SUBCMD`). Items are saved-family items `["saved", "pm", SUBCMD]`, so Ctrl-E can hide subcommands you never use. Off a terminal it fails with `ERROR: Choosing from pm-commands needs a terminal`.

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

### add

Queue a prompt to add a new task to a project.

**Examples**

```bash
h pm add my-project new-task
```

### archive / unarchive

Queue prompts to archive or restore a project.

**Examples**

```bash
h pm archive old-project
h pm unarchive old-project
```
### complete

Queue a prompt to mark a task as complete.

**Examples**

```bash
h pm complete my-project my-task
```

### discover

Queue a prompt to auto-discover untracked work from PRs, worktrees, and olive runs.

**Examples**

```bash
h pm discover
h pm discover my-project
```

### impact

Queue a prompt to analyze the cascading impact of deviating from a task plan.

**Examples**

```bash
h pm impact my-project my-task
```

### plan

Queue a prompt to generate or update the proposal doc for a task.

**Examples**

```bash
h pm plan my-project my-task
```

### ref

Queue a prompt to add a reference document to a project.

**Examples**

```bash
h pm ref my-project https://docs.example.com/spec
```

### resume

Queue a "where was I?" briefing prompt for a project.

**Examples**

```bash
h pm resume my-project
```

### start

Queue a prompt to load context and begin working on a task.

**Examples**

```bash
h pm start my-project my-task
```

### status

Queue a project status overview prompt.

**Examples**

```bash
h pm status my-project
```

