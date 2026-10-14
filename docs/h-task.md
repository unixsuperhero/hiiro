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
| `h task start NAME [APP] [-s GROUP]` | `t tree new NAME [APP] [--sparse GROUP]` |
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

`Hiiro::TaskManager` keeps the worktree operations `t` uses: `create_tree` (create or reuse an unassigned worktree, optional sparse groups), and `Config#detach_tree`. `Hiiro::CurrentTask#context` resolves the canonical task once into `TaskLocation`, and `Environment` delegates that value rather than choosing the first matching task/app/tree. Root, task, and app queue/service/runner mounts share the selected root and effective directory. Root workflows disable the saved task pin; `t` permits it as the final fallback.

## Removed legacy task commands

`h otask`, `h osubtask`, and `h zosubtask` were removed. They needed the `Tmux`, `OldTask`, and `Task` plugins, which the package stopped shipping (`plugins/old_task.rb`, `plugins/tmux.rb`, and `plugins/tasks.rb` were deleted in February 2026); without them `h osubtask` and `h zosubtask` raised `NoMethodError` and `h otask ls` printed only a worktree list that pointed at the removed `h task start`. The old inline `h task`/`h subtask` grammar (`Hiiro::Tasks`) has had no caller since `h task` became a symlink to `t`, and was removed with them.

| Old | Now |
|---|---|
| `h otask ls`, `h osubtask ls` | `t ls`, `h wtree ls` |
| `h otask start NAME [APP]`, `h osubtask new NAME` | `t tree new NAME [APP]`, `t tree new PARENT/NAME` |
| `h otask switch`, `app`, `cd`, `path` | `t switch`, `t cd [TASK] [APP]`, `t path [TASK] [APP]` |
| `h otask stop` | `t tree rm [TASK]` |
| `h otask apps` | `h app ls` |
| `h otask current` | `t current` |
| `h otask save`, `status` | not carried over: Herdr owns tabs and panes (`t tab ls`, `t pane ls`) |
| `h otask migrate` | not carried over: a one-time tmux-era worktree layout move |

Nothing was deleted from the database. Window arrays, `saved_at`, and other keys that `h otask save` wrote stay in `tasks.metadata_json`; assignments stay in `assignments`. `t` reads tasks, resources, and worktree references from the same rows.
