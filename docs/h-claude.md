# h-claude

Launch Claude Code sessions in tmux splits/windows, search `.claude` directories, run inline prompts, and manage the Claude prompt queue.

## Synopsis

```bash
h claude <subcommand> [options] [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `split [opts] [args]` | Open claude in a tmux split pane |
| `vsplit [opts] [args]` | Open claude in a vertical split pane |
| `hsplit [opts] [args]` | Open claude in a horizontal split pane |
| `window [opts] [args]` | Open claude in a new tmux window |
| `inline [prompt]` | Run a one-shot prompt via `claude -p` |
| `loop` | Multi-turn interactive prompt loop in editor |
| `new` | Write a prompt in editor and launch as a new claude session |
| `all [filters]` | List all agents, commands, and skills |
| `agents [filters]` | List Claude agents in `.claude/agents/` |
| `commands [filters]` | List Claude commands in `.claude/commands/` |
| `skills [filters]` | List Claude skills in `.claude/skills/` |
| `vim [filters]` | Open matching agents/commands/skill files in editor |
| `ls` / `list` | List all prompt queue tasks |
| `status` | Show detailed queue status |
| `add` | Add a new prompt to the queue |
| `hadd` | Add and launch in a horizontal tmux split |
| `vadd` | Add and launch in a vertical tmux split |
| `cadd` | Add and run in the current tmux pane |
| `sadd` | Add scoped to current tmux session |
| `wip [name]` | Create or edit a work-in-progress prompt |
| `ready [name]` | Move wip prompt to pending |
| `run [name]` | Launch pending task(s) in tmux windows |
| `watch` | Continuously poll and launch pending tasks |
| `attach [name]` | Switch to a running task's tmux window |
| `session` | Open the queue tmux session |
| `kill [name]` | Kill a running task |
| `retry [name]` | Move failed/done task back to pending |
| `clean` | Remove all done/failed task files |
| `dir` | Print queue directory path |
| `pane-dir` | Resolve working directory for a pane-launched prompt (internal) |

### split

Open a new tmux split pane running `claude`. Arguments are forwarded to `claude`. With `-i`, runs `claude -p` (no persistent shell).

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--danger` | `-d` | Use `--dangerously-skip-permissions` | false |
| `--horizontal` | `-h` | Split horizontally | false |
| `--percent` | `-p` | Treat size as percentage | false |
| `--ignore` | `-i` | Fire-and-forget (no shell after claude) | false |
| `--size` | `-s` | Pane size | `40` |

**Examples**

```bash
h claude split
h claude split -s 40% my-prompt
h claude split -d
```

### vsplit

Open a vertical split (side by side). With `-l`, places it on the left.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--danger` | `-d` | Use `--dangerously-skip-permissions` | false |
| `--left` | `-l` | Place split on left | false |
| `--percent` | `-p` | Treat size as percentage | false |
| `--ignore` | `-i` | Fire-and-forget (no shell after claude) | false |
| `--size` | `-s` | Pane size | — |

**Examples**

```bash
h claude vsplit
h claude vsplit -s 50%
```

### hsplit

Open a horizontal split (top/bottom). With `-b`, places it at the bottom.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--danger` | `-d` | Use `--dangerously-skip-permissions` | false |
| `--bottom` | `-b` | Place split at bottom | false |
| `--percent` | `-p` | Treat size as percentage | false |
| `--ignore` | `-i` | Fire-and-forget (no shell after claude) | false |
| `--size` | `-s` | Pane size | — |

**Examples**

```bash
h claude hsplit
h claude hsplit -s 30%
```

### window

Open a new tmux window running `claude`.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--danger` | `-d` | Use `--dangerously-skip-permissions` | false |
| `--ignore` | `-i` | Fire-and-forget (no shell after claude) | false |

**Examples**

```bash
h claude window
h claude window -i
```

### inline

Run a single prompt via `claude -p` and print the output. Reads from stdin if no args and stdin is a pipe. With no args and a TTY, opens an editor.

**Examples**

```bash
h claude inline "summarize this code"
echo "explain this" | h claude inline
h claude inline
```

### loop

Multi-turn conversational loop. Opens an editor for each prompt; previous prompts and responses are shown as context. Empty save quits.

**Examples**

```bash
h claude loop
```

### new

Write a prompt in your editor and launch it as a full claude session (`claude --allow-dangerously-skip-permissions <prompt>`).

**Examples**

```bash
h claude new
```

### all / agents / commands / skills

List agent, command, and skill files found in `.claude/` directories from the current directory up (but not past `$HOME`). Filters by filename pattern if args provided.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--full` | `-f` | Full text search (grep inside files) |
| `--verbose` | `-v` | Show `.claude` paths being searched |
| `--veryverbose` | `-V` | Show all paths including skipped |

**Examples**

```bash
h claude all
h claude agents fetch
h claude commands refactor
h claude skills -f "pull request"
```

### vim

Open matching agent, command, and skill files in your editor. Uses the same filter logic as `all`.

**Examples**

```bash
h claude vim fetch
h claude vim
```

### ls / list

List all prompt queue tasks with status, elapsed time, and a content preview. Shows all statuses by default (up to a terminal-height limit).

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Show all tasks without limit; use pager if output exceeds terminal height |
| `--status` | `-s` | Filter by status (`wip`, `pending`, `running`, `done`, `failed`); repeatable |

**Examples**

```bash
h claude ls
h claude ls -s pending
h claude ls -s running -s failed
h claude list --all
```

### status

Show detailed queue status for all tasks, including elapsed time for running tasks and tmux pane/window info.

**Examples**

```bash
h claude status
```

### add

Add a new prompt to the queue. With no arguments and a TTY, opens an editor pre-populated with YAML frontmatter. With arguments, uses them as the prompt text. Reads from stdin if not a TTY.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--task` | `-t` | Task name to associate |
| `--name` | `-n` | Base filename for the task |
| `--find` | `-f` | Choose task/session interactively (fuzzyfind) |
| `--horizontal` | `-h` | Launch in horizontal tmux split |
| `--vertical` | `-v` | Launch in vertical tmux split |
| `--session` | `-s` | Use current tmux session |
| `--ignore` | `-i` | Fire-and-forget (close window when done, no shell) |

**Examples**

```bash
h claude add
h claude add "Fix the login bug"
h claude add -t my-task "Refactor the auth module"
h claude add -f
```

### hadd

Add a prompt and immediately launch it in a horizontal tmux split. Same options as `add`.

**Examples**

```bash
h claude hadd
h claude hadd "Run the test suite"
```

### vadd

Add a prompt and immediately launch it in a vertical tmux split. Same options as `add`.

**Examples**

```bash
h claude vadd
h claude vadd "Write tests for foo"
```

### cadd

Add a prompt and run it in the current pane (splits the current tmux window). Same options as `add`.

**Examples**

```bash
h claude cadd
```

### sadd

Add a prompt scoped to the current tmux session. Same options as `add`.

**Examples**

```bash
h claude sadd "Deploy to staging"
```

### wip

Create or edit a work-in-progress prompt (stored in the `wip/` status directory). If no name is given and wip tasks exist, fuzzy-selects from them.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--task` | `-t` | Task name to associate |
| `--find` | `-f` | Choose task/session interactively (fuzzyfind) |
| `--session` | `-s` | Use current tmux session |

**Examples**

```bash
h claude wip my-draft
h claude wip
```

### ready

Move a wip prompt to the pending queue. With no name, fuzzy-selects from wip tasks (auto-picks if only one exists).

**Examples**

```bash
h claude ready
h claude ready my-draft
```

### run

Launch pending task(s) in tmux windows. With a name, launches that specific task. With no name, launches all pending tasks.

**Examples**

```bash
h claude run
h claude run my-task
```

### watch

Continuously poll the pending queue and launch tasks as they appear. Polls every 2 seconds. Automatically restarts if a new hiiro version is detected.

**Examples**

```bash
h claude watch
```

### attach

Switch to a running task's tmux window. Fuzzy-selects if no name given.

**Examples**

```bash
h claude attach
h claude attach my-task
```

### session

Open (or create) the `hq` queue tmux session.

**Examples**

```bash
h claude session
```

### kill

Kill a running task's tmux window/pane and move the task to `failed`. Fuzzy-selects if no name given.

**Examples**

```bash
h claude kill
h claude kill my-task
```

### retry

Move a failed or done task back to pending. Fuzzy-selects if no name given.

**Examples**

```bash
h claude retry
h claude retry my-task
```

### clean

Remove all done and failed task files from the queue.

**Examples**

```bash
h claude clean
```

### dir

Print the queue base directory path.

**Examples**

```bash
h claude dir
```

### pane-dir

Internal subcommand used by `hadd`/`vadd`/`cadd` shell scripts. Resolves the working directory for a prompt file given a base directory. Not intended for direct use.

**Examples**

```bash
h claude pane-dir /path/to/prompt.md /path/to/base
```

## Prompt frontmatter

Queue prompts are Markdown files with optional YAML frontmatter:

```markdown
---
task_name: my-task
tree_name: my-task/main
session_name: my-task
app: api
dir: packages/api
ignore: true
---
Your prompt text here.
```
