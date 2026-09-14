# Task commands

`t` manages durable tasks. A task can be a coding project, an investigation, or administrative work. It does not need Git or Herdr.

Task records and resource references live in `~/.config/hiiro/hiiro.db`, in the existing `tasks` table and the `task_resources` table. `h task` uses the same records. Its YAML file is a backup, not a separate task store.

Task todos use the existing `todos` table shared with `h todo`. `t` writes to the database directly and does not rewrite the task YAML backup or `todo.yml`.

## t

`h task` is a symlink to `t`, so `h task ARGS...` is `t ARGS...`. The grammar is `t COMMAND [TASK] [ARGS...]`: the command comes first, and commands that act on a task take it from the first positional argument when that word names a task (exact or unique prefix); otherwise the current task is used and the word stays in the payload. `-t TASK` forces a task, `-f` picks one with a fuzzy finder, `.` is the current task, and `-` selects orphan todos. See [t](t.md) for every command.

## h task

`h task` is the same program as `t`: `bin/h-task` is a symlink to `exe/t`, so `h task ARGS...` behaves exactly like `t ARGS...` with the task-first grammar above. `h subtask` is gone; a subtask is a task named `parent/child`, and `t tree new parent/child` creates its worktree under `~/work/parent/child`.

Worktree operations that used to live only under `h task` are now task commands:

| Old | Now |
|---|---|
| `h task start NAME [APP] [-s GROUP]` | `t tree new NAME [--app APP] [--sparse GROUP]` (creates the task record if needed, then the worktree, then the Herdr workspace) |
| `h task switch NAME [APP]` | `t switch NAME [--directory DIR]` |
| `h task stop NAME` | `t tree rm NAME` (detaches the worktree, keeps the directory, registers it as a directory resource) |
| `h task resume [TREE]` | `t tree resume NAME [TREE]` |
| `h task path`, `h task branch`, `h task tree` | `t path [TASK]`, `t branch [TASK]`, `t tree [TASK]` |
| `h task sh [CMD...]` | `t sh [TASK] [CMD...]` |
| `h task cd` | `t cd [TASK]` |
| `h task todo ...` | `t todo ... [TASK]` or `tt ...` |
| `h task ls` | `t ls` |
| `h task current` | `t current` |
| `h task queue`, `service`, `run`, `file` | `h queue`, `h service`, `h run`, `h file` |

`h task tag`, `untag`, `tags`, `sparse`, `from`, `prune`, `apps`, `save`, `status`, and `prs` were not carried over. Tag branches with `h branch tag`, inspect worktrees with `h wtree`, and register an existing directory with `t directory add [TASK] PATH --primary`.

`Hiiro::TaskManager` still holds the worktree creation code that `t tree new` and the shared `Hiiro::CurrentTask` resolver use; `h service`, `h run`, and `h file` keep using it for the current task through `Environment#task`, which now also recognizes a task by its home, primary directory, or registered directories.
