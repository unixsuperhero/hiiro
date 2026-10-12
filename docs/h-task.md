# Task commands

`t` manages durable tasks. A task can be a coding project, an investigation, or administrative work. It does not need Git or Herdr.

Task records and resource references live in `~/.config/hiiro/hiiro.db`, in the existing `tasks` and `task_resources` tables. `h task` uses the same records. Legacy task YAML is an explicit migration/recovery input; commands do not read it as a fallback or write backup copies.

Task todos use the existing `todos` table shared with `h todo`. Task mutations update only the requested fields and retain database IDs. Detaching a worktree keeps the task metadata and resource references, and saves its current directory as a resource.

## t

`h task` is a symlink to `t`, so `h task ARGS...` is `t ARGS...`. The grammar is `t COMMAND [TASK] [ARGS...]`: the command comes first, and commands that act on a task take it from the first positional argument when that word names a task (exact or unique prefix); otherwise the current task is used and the word stays in the payload. `-t TASK` forces a task, `-f` picks one with a fuzzy finder, `.` is the current task, and `-` selects orphan todos. See [t](t.md) for every command.

## h task

`h task` is the same program as `t`: `bin/h-task` is a symlink to `exe/t`, so `h task ARGS...` behaves exactly like `t ARGS...` with the task-first grammar above. `h subtask` is gone; a subtask is a task named `parent/child`, and `t tree new parent/child` creates its worktree under `~/work/parent/child`.

Worktree operations that used to live only under `h task` are now task commands:

| Old | Now |
|---|---|
| `h task start NAME [APP] [-s GROUP]` | `t start NAME [APP] [--sparse GROUP]` or `t tree new NAME [APP] [--sparse GROUP]` |
| `h task switch NAME [APP]` | `t switch NAME [APP] [--directory DIR]` |
| `h task stop NAME` | `t tree rm NAME` (detaches the worktree, keeps the directory, registers it as a directory resource) |
| `h task resume [TREE]` | `t tree resume NAME [TREE]` |
| `h task path`, `h task branch`, `h task tree` | `t path [TASK] [APP]`, `t branch [TASK]`, `t tree [TASK]` |
| `h task sh [CMD...]` | `t sh [TASK] [CMD...]` |
| `h task cd [APP]` | `t cd [TASK] [APP]` |
| `h task todo ...` | `t todo ... [TASK]` or `tt ...` |
| `h task ls` | `t ls` |
| `h task current` | `t current` |
| `h task queue`, `service`, `run` | `t queue/service/run [TASK] [--app APP] ...`; these pass the selected context to the shared workflows |
| `h task file` | `h file ...` for tracked editor files; `t file ...` manages task file resources instead |

`h task tag`, `untag`, `tags`, `sparse`, `from`, `prune`, `apps`, `save`, `status`, and `prs` were not carried over. Tag branches with `h branch tag`, inspect worktrees with `h wtree`, and register an existing directory with `t directory add [TASK] PATH --primary`.

`Hiiro::TaskManager` retains useful worktree/domain operations. `Hiiro::CurrentTask#context` resolves the canonical task once into `TaskLocation`, and `Environment` delegates that value rather than choosing the first matching task/app/tree. Root, task, and app queue/service/runner mounts share the selected root and effective directory. Root workflows disable the saved task pin; `t` permits it as the final fallback.

## Legacy task persistence

The in-repo `h-otask` manager uses the same `TaskRecord`, `TaskResource`, and `Assignment` owners. Assignments change one worktree row at a time. Task detail saves merge supplied fields into the current row; saved window arrays, `saved_at`, and additional detail keys live in `tasks.metadata_json`. Changing a tree or session does not erase those details. Apps come from `AppRecord`; add or edit aliases with `h app`.

`h-otask` requires the external `Tmux` plugin. `h-osubtask` and `h-zosubtask` delegate to external task plugins whose implementations are not included here. Their external persistence behavior is not implemented or verified by this repository.
