# Tasks screen plan (PR 5 of the Hiiro TUI plan)

`t ui` opens a tree of tasks, subtasks, and todos on `Hiiro::Tui::Screen`, with a detail pane for the selected node and prompts for the edits `t` already supports. One PR, one new screen class, one new `t` command. Decided 2026-10-12 after prototyping two layouts on the real database (Appendix A).

## How to read this

One box is one unit of work with the evidence that checks it. Unit tests drive the screen through `handle_key` and assert `frame` literally under the in-memory DB. The live check launches `t ui` in a tuios window against a copy of `~/.config/hiiro/hiiro.db` through `HIIRO_TEST_DB`, drives it with `tuios send-keys`, and keeps the captures. Tests alone do not verify the PR.

## Vocabulary

- **node**. One row of the tree. `{ kind: :task | :subtask | :todo, depth, task: TaskRecord, todo: TodoItem | nil }`. Subtasks are tasks whose name contains `/`, listed under their parent (`TaskRecord.subtasks_of`).
- **expanded**. The Set of task names whose children are shown. Starts with the current task when one resolves.
- **scope**. `:global` lists every task. `:task` lists only the current task's subtree, expanded. `g` toggles, through `Hiiro::CurrentTask.new(pin: true).resolve`.
- **closed**. Tasks with status `done` or `archived`. Hidden by default; `A` shows them.

```ruby
state   = { expanded: Set['tcli'], scope: :global, show_closed: false }   # beside Tui::State
node    = { kind: :todo, depth: 1, task: tcli, todo: TodoItem(5, 'make herdr actions...', 'not_started') }
```

## PR 5. `t ui`

**Files.** Create `lib/hiiro/task_screen.rb`, `test/hiiro/task_screen_test.rb`. Edit `lib/hiiro/task_cli.rb` (one `add_cmd(:ui)`), `lib/hiiro.rb` (require), `docs/t.md`, `README.md`, `AGENTS.md`.

**Build.**
- [x] `Hiiro::TaskScreen < Tui::Screen`. `items` is rebuilt from the DB by `reload!` as a flat Array of nodes in display order: top-level tasks sorted by name, each followed when expanded by its todos (`TodoItem` where `task_name` is the task and `subtask_name` nil, ordered by id) and then its subtasks recursively. Row text: tasks as `"#{▸|▾} #{name}  #{status}  (#{open})  next: #{next_action}"` with empty parts dropped, todos as `"[#{x| }] #{text}"`, indented two spaces per depth. Search matches task names and todo text and expands every task that has a match.
- [x] Detail pane. For a task node: `name`, `status`, `next`, `waiting`, `tree`, `session`, `code dir` (`TaskLocation.for(task).code_directory`), `home`, then `todos (n)` with one line each, then `resources (n)` with `kind  target` lines. For a todo node: `task`, `id`, `status`, `text`, `tags`, `created`.
- [x] Keys, through the class key map. `Enter` and `l` expand or collapse a task node; `h` collapses, or moves to the parent when already collapsed. `g` toggles scope. `A` toggles closed tasks. `x` on a todo flips `done` and `not_started`; on a task it opens the todo-add prompt. `t` prompts `todo` and adds one to the node's task. `n` prompts `next action` (prefilled); empty clears. `w` prompts `waiting on` (prefilled); empty clears and returns the task to `active`. `D` prompts `mark NAME done? (y/n)`. `N` prompts `new task` and creates it through the same path as `t new` (record plus notes home). `u` saves the task as the pinned current task. `s` opens or focuses the task workspace and quits the screen. `q` quits.
- [x] Operations go through the code `t` uses, not a copy. `TaskScreen::Ops` is a small object that `extend`s `Hiiro::TaskCli::Commands` and supplies `client` (Herdr) and a nil `opts`, exposing `create(name)`, `save_current(task)`, `set_status(task, state)`, `metadata(task, field, args)`, and `open_workspace(task, save: true)`. Todo flips use `TodoItem#update_status`. A `Hiiro::Error` from any operation becomes the status message.
- [x] `t ui` in `TaskCli.setup` as `add_cmd(:ui, args: [], opts: [])`, which never resolves a task itself. `h task ui` follows through the existing symlink.
- [x] Docs. `docs/t.md` gains a `t ui` section with the key table and the scope rule. `README.md` names `t ui` in the `h task` row. `AGENTS.md` gets one line under Library Components pointing at `Hiiro::TaskScreen` as the second screen on the toolkit.

**You see.** The tree from Appendix A with a detail pane on the right, the current task expanded on open, `scope:task(@NAME)` in the header after `g`, a todo flipping between `[ ]` and `[x]` on `x`, and `next:` text appearing on the task row after `n`.

**Verify, unit.** Done 2026-10-12: task_screen_test 20 runs 53 assertions, task_record_rules_test 6 runs, t_test unchanged at its two known failures; full suite shows only the six pre-existing failures. `test/hiiro/task_screen_test.rb` seeds two top-level tasks, one subtask, three todos (one done), and asserts `frame(rows: 14, cols: 80)` literally for: the collapsed tree; expand on Enter showing todos then the subtask; collapse on `h`; `h` on a child moving to the parent; search `test` expanding only the matching task; `g` with a resolver returning a task showing only that subtree; `A` revealing a done task; `x` on a todo updating the row and the DB; `t` adding a todo; `n` and `w` writing the fields and clearing on empty; `D` after `y` setting status and `completed_at`; `N` creating the task; `u` writing table `t` entry `current_task`; `s` calling `open_workspace` on a stubbed Ops and returning from `run`. Run `ruby -Ilib -Itest test/hiiro/task_screen_test.rb`.

**Verify, live.** Done 2026-10-12 in tuios windows against a database copy: tree with the current task expanded, `/tcli` search, collapse, `t` add (`added todo 9`), `n` set (`next: ship PR 5` on the row and in the DB), `g` scope to the tcli subtree, `A`, and `x` flipping todo 5 to done, each confirmed with `h db q`. `s` was not exercised live because no Herdr server runs in this tuios session; the fake-Ops unit test is its evidence. In a tuios window against a database copy: open, expand `tcli`, `x` on its first todo, `t` add `from ui`, `n` set `ship PR 5`, `/test` search, `g` toggle, `A` toggle, `q`. Capture after each step and confirm the todo and task rows with `h db q` on the copy. `s` is verified live only when a Herdr server is running; otherwise its captured status message is the evidence and the gap is recorded.

## Alternatives rejected

- **Two-pane task list with the tree flattened** (Appendix A, V1). Names, statuses, and counts truncate at half width and subtasks read as `parent/child` rows with no nesting. Rejected.
- **Tree without a detail pane** (V2 as prototyped). Compact, but next action, waiting text, worktree, and resources have nowhere to go. The detail pane costs nothing on the toolkit, so the plan takes the tree plus the pane.
- **Shelling out to `t`** for each operation. Simpler to write, but every action would re-resolve the current task from the pane's environment and could pick a different task than the one under the cursor. Rejected in favour of `Ops` over `TaskCli::Commands`.

## Risks

- `s` opens workspaces through Herdr (`herdr status server`); nothing in the task code speaks tuios yet. In a tuios-only session `s` reports the Herdr error in the status line. A tuios backend for task workspaces is its own change.
- Long todo text widens rows; the list pane truncates with `…` and the detail pane shows the full text. Acceptable for the first version.
- `TaskCli::Commands` helpers assume `opts` for task selection; `Ops` only calls the helpers that do not touch it. The unit test for `Ops` is the guard.

## Appendix A. Prototype evidence

Two throwaway screens built on `Hiiro::Tui::Screen` against a copy of the real database on 2026-10-12, driven in tuios windows. Scratch dir `scratchpad/tasks-proto/` of the session, not in this repo.

```text
V1 two-pane, cursor on claude                      V2 tree, tcli and refactor expanded
> claude                         (…│name   claude     ▸ claude    (2)
  main                             │status -          ▸ main
  prez                   active    │next   -          ▸ prez  active
  refactor                         │tree   claude/m   ▾ refactor
  refactor/ai-refactor             │todos (2)           ▸ refactor/ai-refactor
  tcli                   active  (…│  [ ] 7  test   > ▾ tcli  active  (2)
                                   │  [ ] 8  that…      [ ] make herdr actions in a plugin…
                                                        [ ] testing
```
