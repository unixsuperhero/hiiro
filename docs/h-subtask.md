# h subtask

`h subtask` was removed when `h task` became a symlink to `t`. A subtask is a task whose name is `parent/child`:

```bash
t my-feature/auth tree new    # worktree at ~/work/my-feature/auth, workspace "my-feature/auth"
t my-feature/auth todo add Wire the login form
t my-feature/auth tree rm
```

See [t](t.md) and [h task](h-task.md).
