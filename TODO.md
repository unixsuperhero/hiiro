
# To do...

- [ ] move task/subtask back into a plugin
  - [ ] have it add :task and :subtask subcommands to the instance of Hiiro
    - [ ] they should init another hiiro instance with a `scope` value set
    - [ ] if scope is :task, it looks at the whole world
    - [ ] if the scope is :subtask, it scopes behavior to the current task
    - [ ] redesign the yml structure for managing tasks

```yml
tasks:
- name: some_name
  parent_task: parent_task_name (if included it's a subtask)
  tree: tree_name
  root: repo_root/tree_name
```
- [ ] refactor plugin to not be procedural AI slop
- [ ] convert to js and using node
- [ ] 
- [ ] 
