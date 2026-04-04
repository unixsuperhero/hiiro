# h-claude

Launch Claude Code sessions in tmux splits/windows, search `.claude` directories, and run inline prompts.

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

Global options parsed before subcommands:

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--danger` | `-d` | Use `--dangerously-skip-permissions` | false |
| `--horizontal` | `-h` | Split horizontally | false |
| `--percent` | `-p` | Treat size as percentage | false |
| `--bottom` | `-b` | Place split at bottom | false |
| `--left` | `-l` | Place split on left | false |
| `--ignore` | `-i` | Fire-and-forget (no shell after claude) | false |
| `--size` | `-s` | Pane size | — |

### split

Open a new tmux split pane running `claude`. Arguments are forwarded to `claude`. With `-i`, runs `claude -p` (no persistent shell).

**Examples**

```bash
h claude split
h claude split -s 40% my-prompt
h claude split -d
```

### vsplit

Open a vertical split (side by side). With `-l`, places it on the left.

**Examples**

```bash
h claude vsplit
h claude vsplit -s 50%
```

### hsplit

Open a horizontal split (top/bottom). With `-b`, places it at the bottom.

**Examples**

```bash
h claude hsplit
h claude hsplit -s 30%
```

### window

Open a new tmux window running `claude`.

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

Tool options:

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
