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
t next fix-checkout 'Reproduce the timeout with the saved checkout payload'
```

When a meeting interrupts you, or another bug takes priority, that instruction stays with the task. Tomorrow, `t show fix-checkout` tells you where to pick up.

**The habit that makes this useful is updating `next` before you switch away.** It can be one sentence. It does not need to become a project plan.

`next` is one current action, not an accumulating checklist. Replace it as you make progress. Keep the longer investigation in a document.

## Waiting becomes visible instead of forgotten

Some unfinished work is actionable. Some is waiting on someone else. Treating both as the same pile makes it harder to decide what deserves your attention.

```bash
t waiting fix-checkout 'Payments team to confirm the retry behavior'
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

`t list` includes both active and waiting work, with the corresponding text. You can review what to work on and what needs a follow-up without opening every terminal.

When the answer arrives:

```bash
t waiting fix-checkout --clear
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
t directory add fix-checkout ~/proj/store --primary --label code
t link add fix-checkout https://example.com/issues/123 --kind issue --label ticket
t pr add fix-checkout https://example.com/pulls/456 --label implementation
t doc new fix-checkout investigation 'Checkout investigation'
```

You can then return directly to a named resource:

```bash
t link open fix-checkout ticket
t pr open fix-checkout implementation
t doc open fix-checkout investigation
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

`t file list` discovers files in the task home. `t doc open` uses `mdoc`, so the notes can be read in the same rendered-document workflow you already use.

The database holds the task metadata and resource references; the notes remain files you can read and edit with your existing tools.

## You can return to the task's terminals by name

Herdr makes terminal work persistent. `t` gives that workspace a relationship to the task you are trying to finish.

```bash
t workspace fix-checkout
```

If the task's workspace is already open, this focuses it. If it is missing, `t` creates one using the task's starting-directory rules. Only after the explicit switch succeeds does `t` save the task as your fallback.

`t workspace --show fix-checkout` inspects the workspace without creating it, focusing it, or changing the saved task. Workspace navigation is a direct command, not a group of child commands. You can also use Hiiro's native abbreviation, `t wor fix-checkout`.

Within that workspace, you can create a labelled tab for a particular activity:

```bash
t tab new fix-checkout tests --command 'bundle exec rake test'
```

Later:

```bash
t tab open fix-checkout tests
```

You can also list panes, read their output, split one, or submit a command to an existing pane. That is useful when an agent needs to inspect the same working context rather than start an unrelated terminal elsewhere.

There are important limits. `t` does not restore a closed workspace's old layout or restart all its former processes. Creating a tab creates another terminal; it does not reuse one merely because the label matches. Terminals remain open after their commands finish.

The useful guarantee is narrower: **you can find or open the workspace associated with a task without remembering its position in the sidebar.**

## Context can save typing without making scripts guess

When a calling Herdr workspace, directory, or saved fallback identifies a task, you can omit its name from commands with no payload positionals:

```bash
t current
t show
t next
```

To write text or pass any other payload positional, put the exact task name immediately after the leaf command:

```bash
t next fix-checkout 'Check the new test against the original failing payload'
```

The CLI never guesses that a lone argument is text for an implicit task. `t next 'Check the test'` looks for a task named `Check the test` and fails if that task does not exist.

An explicit task name takes priority. Otherwise, a matching calling Herdr workspace wins over a conflicting current directory. The directory is next, followed by the saved task. Ambiguous matches at the same priority and invalid, stale, or conflicting Herdr IDs are errors.

You can set that fallback without moving terminal focus:

```bash
t current fix-checkout
```

`t current` only prints the selected name. Reads and implicit workspace opens leave the saved fallback unchanged, and a deleted saved task causes an error if selection reaches it. `t list` remains a list of all eligible tasks when no task name is supplied.

## An agent can leave you a useful place to resume

An agent's final chat message can be hard to find later. A task's next action and document home are predictable places to leave the result.

For example, an agent working on a selected task can create a handoff document and update what remains:

```bash
t doc new fix-checkout handoff 'Checkout handoff'
t next fix-checkout 'Review the retry test and decide whether to merge'
```

The agent still needs to write its findings into the document. `doc new` creates the file and heading; it does not generate the handoff content.

This is a shared convention, not an agent orchestration system. `t` does not launch an autonomous workflow, merge competing updates, or guarantee that an agent's claims are correct. It gives you both the same named task and the same place to record the result.

## Organization does not require changing your checkout

You can start tracking work immediately:

```bash
t new fix-checkout
```

That creates a record and notes directory. It does not create a worktree, switch branches, modify sparse checkout, or open Herdr.

You can attach an existing repository or worktree afterward. If that directory already uses sparse checkout, `t` leaves the configuration alone.

This matters for small investigations and noncoding tasks. You can track an invoice review or a design decision without pretending it needs a branch and a terminal workspace.

The separate `h task` commands still own their coding-worktree operations. The [reference explains that boundary](t.md#worktrees-branches-and-sparse-checkout), including the different behavior of `h task start` and `h task switch`.

## Completing work reduces the daily list without deleting the context

```bash
t done fix-checkout
```

Completed work disappears from the default `t list`, but its record, notes, links, and directory references remain available.

```bash
t list --all
t show fix-checkout
```

If the problem returns, you can reopen the task:

```bash
t status fix-checkout active
```

Completion does not close terminals or clean up Git worktrees. It means the task is complete, not that every resource associated with it should be destroyed.

## The smallest routine worth adopting

You do not need to use every command for this to pay off.

| Moment | Useful command | What it gives you |
|---|---|---|
| You capture a new piece of work | `t new TASK` | A named record and notes home |
| You decide what to work on | `t list` | Active and waiting tasks with their next-action/blocker text |
| You resume a task | `t show TASK` | The context you recorded for it |
| You want a fallback outside task directories and Herdr | `t current TASK` | Saved selection without moving terminal focus |
| You need its terminals | `t workspace TASK` | The associated workspace, focused or newly created, and a saved fallback after success |
| You are about to switch away | `t next TASK 'The next concrete action'` | An instruction for your next session |
| Someone else is blocking progress | `t waiting TASK 'Who or what I need'` | A visible waiting state and explanation |
| The work is complete | `t done TASK` | A shorter default list without deleting the supporting context |

Start with task names and useful next actions. Add documents, links, and terminal organization when they make a particular task easier to resume.

`t` will not choose your priorities or keep itself accurate. Its value comes from making a small update at the moment you know the answer, so you do not have to reconstruct it later.

**The strongest feature is the combination: a named task, a concrete next action, and direct access to the material you need to act on it.**

## Read next

[The complete t command reference](t.md) covers every subcommand, option, alias, state transition, storage location, and Herdr/worktree side effect. The canonical implementation is the repository's `bin/t`, with `~/bin/t` as its symlink. Gem installation does not install the launcher.
