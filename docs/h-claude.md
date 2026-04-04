# h-claude

Launch Claude Code sessions in tmux splits/windows, search `.claude` directories, and run inline prompts.

## Synopsis

```bash
h claude <subcommand> [options] [args]
```

`.claude` directories are discovered by walking up from `$PWD` through parent directories (stopping before `$HOME`). Closest directories take precedence.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `split` | Split current pane and start Claude in the new pane |
| `vsplit` | Create a vertical split and start Claude |
| `hsplit` | Create a horizontal split and start Claude |
| `window` | Open a new tmux window and start Claude |
| `inline` | Send a prompt to `claude -p` and print the response |
| `new` | Open editor, then exec `claude` with the prompt |
| `loop` | Interactive prompt loop with history |
| `all` | List all agents, commands, and skills in `.claude` dirs |
| `agents` | List agents from `.claude/agents/` |
| `commands` | List commands from `.claude/commands/` |
| `skills` | List skills from `.claude/skills/` |
| `vim` | Open matching agent/command/skill files in vim |

## Global Options

These flags apply to `split`, `vsplit`, `hsplit`, and `window` subcommands:

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--danger` | `-d` | Pass `--dangerously-skip-permissions` | false |
| `--horizontal` | `-h` | Split horizontally instead of vertically | false |
| `--percent` | `-p` | Interpret size as a percentage | false |
| `--bottom` | `-b` | Place new pane at the bottom (hsplit) | false |
| `--left` | `-l` | Place new pane on the left (vsplit) | false |
| `--ignore` | `-i` | Fire-and-forget mode (`claude -p`, window closes when done) | false |
| `--size` | `-s` | Pane size | `40` |

## Tool Search Options

These flags apply to `all`, `agents`, `commands`, `skills`, and `vim`:

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--full` | `-f` | Full-text search (grep) rather than name match | false |
| `--verbose` | `-v` | Show `.claude` dir paths on stderr | false |
| `--veryverbose` | `-V` | Show all debug output on stderr | false |

## Subcommand Details

### `split`

Split the current tmux pane and start a Claude session in the new pane. By default creates a vertical split of size 40 columns.

```bash
h claude split
h claude split -s 50 -p          # 50% width
h claude split -d                 # with --dangerously-skip-permissions
h claude split -i "fix the tests" # fire-and-forget
```

### `vsplit` / `hsplit`

Same as `split` but explicitly vertical or horizontal.

```bash
h claude vsplit -s 60
h claude hsplit -s 30 -p -b       # 30% at bottom
```

### `window`

Open a new tmux window and start a Claude session in it.

```bash
h claude window
h claude window -d
```

### `inline`

Send a prompt to `claude -p` and print the response. Reads from stdin, positional args, or opens your `$EDITOR` if neither is provided.

```bash
echo "What is 2+2?" | h claude inline
h claude inline "Summarize this error: $(cat log.txt)"
h claude inline          # opens editor
```

### `new`

Open your editor to write a prompt, then exec `claude` with it as the initial message.

```bash
h claude new
```

### `loop`

Interactive prompt loop: opens editor with previous conversation context, sends to `claude -p`, displays response, repeats. Leave the editor empty to exit.

```bash
h claude loop
```

### `all`

List all agents, commands, and skills found in `.claude` directories. Walks up from `$PWD`. Optional filter args match against names (or full text with `-f`).

```bash
h claude all
h claude all pr
h claude all -f "pull request"
```

### `agents` / `commands` / `skills`

List agents, commands, or skills respectively. Same filtering options as `all`.

```bash
h claude agents
h claude commands pr
h claude skills refactor
```

### `vim`

Open matching agent, command, or skill `SKILL.md` files in vim.

```bash
h claude vim pr
h claude vim -f "code review"
```

## Examples

```bash
# Open a Claude split panel for the current task
h claude split -d

# Run a quick inline question
h claude inline "What does git merge-base do?"

# Find available skills matching "review"
h claude skills review

# Open a persistent conversation loop
h claude loop

# Open a new window with Claude
h claude window -d
```
