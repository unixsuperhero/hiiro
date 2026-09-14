# Why t belongs in your daily workflow

The best reason to use `t` is the time between deciding to return to a task and actually doing useful work.

You already have the code, the issue, the PR, the notes, and a terminal somewhere. The hard part is remembering which ones belong together and what you meant to do next. That gets harder when you switch between projects, wait for reviews, or hand work to an agent.

**`t` gives each task a named record you can return to.** It keeps the next action and supporting references together, and connects that record to a Herdr workspace when you need terminals.

This is the case for using the current tool, with examples of what it already does. For every command and option, see the [complete t reference](t.md).

## Your next action survives an interruption

A task name tells you the subject. A useful next action tells you how to resume.

Compare these two descriptions of the same work:

```js
// Enough to remember that work exists.
{ task: "fix-checkout" }

// Enough to start doing something useful.
{
  task: "fix-checkout",
  status: "active",
  next: "Reproduce the timeout with the saved checkout payload"
}
```

The second version takes one command:

```bash
t fix-checkout next 'Reproduce the timeout with the saved checkout payload'
```

When a meeting interrupts you, or another bug takes priority, that instruction stays with the task. Tomorrow, `t fix-checkout` tells you where to pick up.

**The habit that makes this useful is updating `next` before you switch away.** It can be one sentence. It does not need to become a project plan.

`next` is one current action, not an accumulating checklist. Replace it as you make progress. Separate todos can hold the other steps without replacing that next action:

```bash
t fix-checkout todo add Compare the retry settings
tt fix-checkout add Inspect --help output
t fix-checkout todo
```

Task display and todo listing show every todo with its ID, status, and text. To remove one, use its displayed ID, such as `t todo rm fix-checkout 42`, or print just its text with `t todo show 42`. The ID must belong to that scope. Adding or removing todos does not change the task's next action or status, and `t` does not choose the next todo for you.

Task references prefer an exact name, then a unique case-sensitive prefix. Ambiguous prefixes fail. A first word that names no task is treated as payload for the current task, so `t todo add fix build` never creates a task named `fix`. Only `t new NAME` creates tasks, and it creates that exact name rather than resolving a prefix.

`tt ...` is `t todo ...`. Bare `tt` lists current-task todos, and `tt help` shows todo help. Use `t todo -` or `tt add - TEXT` for orphan todos. `-` is not a task and works only for todos.

Every word after the task in `add` is literal text, including flags and `--`, except a leading `-h` or `--help`, which shows help. Empty text fails.

Todos share the existing database table with `h todo`. `t` does not rewrite `todo.yml` or change `h task` behavior. Keep the longer investigation in a document.

## Waiting becomes visible instead of forgotten

Some unfinished work is actionable. Some is waiting on someone else. Treating both as the same pile makes it harder to decide what deserves your attention.

```bash
t fix-checkout waiting 'Payments team to confirm the retry behavior'
```

That saves the explanation and changes the task's status to `waiting`. The next action remains available, so you can retain what you intend to do after the blocker clears.

```js
{
  task: "fix-checkout",
  status: "waiting",
  waiting_on: "Payments team to confirm the retry behavior",
  next: "Add a regression case once the expected behavior is confirmed"
}
```

Bare `t` (or `t ls` / `t list`) lists every task and status, including done and archived work. Each name carries its open todo count, such as `prez (3)`, and active and waiting rows show their next-action and blocker text, so you can review what needs attention without opening every terminal.

When the answer arrives:

```bash
t fix-checkout waiting --clear
```

A waiting task becomes active again. There is no automatic reminder or follow-up scheduler; the benefit is having the blocker written down where you review the work.

## The issue, PR, code, and notes stay together

You should not need to remember whether the useful link is in a browser tab, a chat message, or a terminal's scrollback.

A task can hold references to each of those pieces:

```js
{
  task: "fix-checkout",
  code: "the existing store checkout directory",
  issue: "the original failure report",
  pr: "the proposed fix",
  notes: "what we tried and what we learned"
}
```

For example, using an existing local directory and illustrative URLs:

```bash
t fix-checkout directory add ~/proj/store --primary --label code
t fix-checkout link add https://example.com/issues/123 --kind issue --label ticket
t fix-checkout pr add https://example.com/pulls/456 --label implementation
t fix-checkout doc new investigation 'Checkout investigation'
```

You can then return directly to a named resource:

```bash
t fix-checkout link open ticket
t fix-checkout pr open implementation
t fix-checkout doc open investigation
```

The primary directory also becomes the default code location for terminals you create through `t`.

Directory and file attachments are references. Your files stay where they already live. Links are saved URLs, not a second issue tracker that needs to be kept in sync. `t` does not fetch PR review status or infer whether the linked issue is complete.

## Your working notes remain ordinary files

Each task has a home under `~/notes/work/`. Documents created through `t` are ordinary Markdown files, and existing Markdown documents placed in that home are discoverable without registration.

A task home might look like this:

```text
~/notes/work/fix-checkout/
  task-42-investigation.md
  task-42-handoff.md
  failing-payload.json
  screenshot.png
```

The task ID in generated filenames helps keep document names distinct when `mdoc` renders them.

This gives you room for the details that do not belong in a one-line next action:

- A reproduction and the exact inputs that trigger it.
- Approaches you ruled out, with the reason each one failed.
- A decision and the evidence behind it.
- A handoff note for your next session or another agent.

`t fix-checkout file list` discovers files in the task home. `t fix-checkout doc open` uses `mdoc`, so you can read the notes through the same rendered-document workflow.

The database holds the task metadata and resource references; the notes remain files you can read and edit with your existing tools.

## You can return to the task's terminals by name

Herdr makes terminal work persistent. `t` gives that workspace a relationship to the task you are trying to finish.

```bash
t fix-checkout switch
```

If the task's workspace is already open, this focuses it. If it is missing, `t` creates one using the task's starting-directory rules. Only after the explicit switch succeeds does `t` save the task as your fallback.

`t fix-checkout workspace` is the same operation. Add `--show` to either command to inspect without creating a workspace, focusing it, or changing the saved task. These are direct commands, not groups. Native command abbreviations remain available inside the task scope, such as `t fix-checkout wor`.

Within that workspace, you can create a labelled tab for a particular activity:

```bash
t fix-checkout tab new tests --command 'bundle exec rake test'
```

Later:

```bash
t fix-checkout tab open tests
```

You can also list panes, read their output, split one, or submit a command to an existing pane. That is useful when an agent needs to inspect the same working context rather than start an unrelated terminal elsewhere.

There are important limits. `t` does not restore a closed workspace's old layout or restart all its former processes. Creating a tab creates another terminal; it does not reuse one merely because the label matches. Terminals remain open after their commands finish.

The useful guarantee is narrower: **you can find or open the workspace associated with a task without remembering its position in the sidebar.**

## AI sessions start fresh unless you ask to resume

The tool commands open a new focused tab in the task workspace:

```bash
t fix-checkout omp
t fix-checkout codex
t fix-checkout claude
```

`cdx` is an alias for `codex`, and `cld` is an alias for `claude`. Each command runs its native executable. Claude runs `claude`, never `omp`.

Only the first tool argument can switch to resume mode. It must be a nonempty prefix of `resume`, such as `r`, `res`, or `resume`:

```bash
t fix-checkout cdx r
t fix-checkout cld resume SESSION_ID
t fix-checkout omp resume --help
```

With nothing after the resume selector, `t` focuses the unique running instance of that tool in the task workspace. It checks Herdr's agent metadata, not the tab name. Multiple matches produce an error with IDs. If none is running, a new tab opens the native resume picker.

With a session ID or any other arguments after the selector, `t` always creates a tab and passes those arguments to the native resume command. OMP and Claude receive `--resume`; Codex receives `resume`. All other arguments pass unchanged, including `--help`, `--`, and native tool options. There is no wrapper `--new` or automatic last-session resume.

The workspace identifies running terminals, not a separate persisted-session store. If tasks share a directory, native resume discovery is not necessarily task-isolated. The launcher does not inject model or permission settings or make auth/API requests.

## Context can save typing without making scripts guess

The command comes first, and the task is optional: `t show fix-checkout` names it, `t show` uses the current task. A first word that names a task, exactly or by unique prefix, is the task; anything else is payload for the current task, the same rule the old `h task` commands used. `-t TASK` forces a task, `-f` picks one with a fuzzy finder, and `.` stands for the current task when a payload could look like a name:

```bash
t current
t show
t next
t next . 'Check the new test against the original failing payload'
```

The calling Herdr workspace wins over a conflicting current directory. The directory is next, followed by the saved task. Ambiguous matches and invalid, stale, or conflicting Herdr IDs are errors.

You can set that fallback without moving terminal focus:

```bash
t use fix-checkout
```

`t current` only prints the selected name. Reads leave the saved fallback unchanged; `t switch NAME` saves it after a successful switch. A deleted saved task causes an error if selection reaches it. Bare `t` always lists all tasks rather than selecting one.

## An agent can leave you a useful place to resume

An agent's final chat message can be hard to find later. A task's next action and document home are predictable places to leave the result.

For example, an agent working on a selected task can create a handoff document and update what remains:

```bash
t fix-checkout doc new handoff 'Checkout handoff'
t fix-checkout next 'Review the retry test and decide whether to merge'
```

The agent still needs to write its findings into the document. `doc new` creates the file and heading; it does not generate the handoff content.

This is a shared convention, not an agent orchestration system. `t` does not launch an autonomous workflow, merge competing updates, or guarantee that an agent's claims are correct. It gives you both the same named task and the same place to record the result.

## Organization does not require changing your checkout

You can start tracking work immediately:

```bash
t fix-checkout new
```

That creates a record and notes directory. It does not create a worktree, switch branches, modify sparse checkout, or open Herdr.

You can attach an existing repository or worktree afterward. If that directory already uses sparse checkout, `t` leaves the configuration alone.

This matters for small investigations and noncoding tasks. You can track an invoice review or a design decision without pretending it needs a branch and a terminal workspace.

The separate `h task` commands still own their coding-worktree operations. The [reference explains that boundary](t.md#worktrees-branches-and-sparse-checkout), including the different behavior of `h task start` and `h task switch`.

## Completing work preserves its context

```bash
t fix-checkout done
```

Completed work stays in bare `t` output with its `done` status. Its record, todos, notes, links, and directory references remain available. Archiving also preserves those resources.

```bash
t
t fix-checkout
```

If the problem returns, you can reopen the task:

```bash
t fix-checkout status active
```

Completion does not close terminals or clean up Git worktrees. It means the task is complete, not that every resource associated with it should be destroyed.

## The smallest routine worth adopting

You do not need to use every command for this to pay off.

| Moment | Useful command | What it gives you |
|---|---|---|
| You capture a new piece of work | `t new TASK` | An exact named record and notes home |
| You capture another step | `tt add 'Compare the retry settings'` | A todo on the current task without replacing the next action |
| You decide what to work on | `t` | Every task and status, with next-action and blocker text |
| You resume a task | `t show TASK` | The context you recorded for it |
| You want a fallback outside task directories and Herdr | `t use TASK` | Saved selection without moving terminal focus |
| You need its terminals | `t switch TASK` | The associated workspace and a saved fallback after success |
| You want a fresh AI session | `t omp TASK` | A new focused tab running the native tool |
| You are about to switch away | `t next 'The next concrete action'` | An instruction for your next session |
| Someone else is blocking progress | `t waiting 'Who or what I need'` | A waiting state and explanation |
| The work is complete | `t done TASK` | A done status without deleting the supporting context |

Start with task names and useful next actions. Add documents, links, and terminal organization when they make a particular task easier to resume.

`t` will not choose your priorities or keep itself accurate. Its value comes from making a small update at the moment you know the answer, so you do not have to reconstruct it later.

**The strongest feature is the combination: a named task, a concrete next action, and direct access to the material you need to act on it.**

## Read next

[The complete t command reference](t.md) covers every subcommand, option, alias, state transition, storage location, and Herdr/worktree side effect. The implementation is `Hiiro::TaskCli` in `lib/hiiro/task_cli.rb`, launched by the `t` and `tt` gem executables in `exe/`.
