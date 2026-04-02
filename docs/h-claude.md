# h-claude

Launch Claude Code sessions in tmux splits/windows, search `.claude` directories, and run inline prompts.

## Usage

```
h claude <subcommand> [options] [args]
```

## Global Options

These flags apply to `split`, `vsplit`, `hsplit`, and `window` subcommands:

| Flag | Short | Description | Default |
|---|---|---|---|
| `--danger` | `-d` | Pass `--dangerously-skip-permissions` | false |
| `--horizontal` | `-h` | Split horizontally instead of vertically | false |
| `--percent` | `-p` | Interpret size as a percentage | false |
| `--bottom` | `-b` | Place new pane at the bottom | false |
| `--left` | `-l` | Place new pane on the left | false |
| `--ignore` | `-i` | Use fire-and-forget mode (`claude -p`, window closes when done) | false |
| `--size` | `-s` | Pane size | `40` |

## Subcommands

### `split`

Split the current tmux pane and start a Claude session in the new pane.

**Args:** `[args passed to claude...]`

### `vsplit`

Create a vertical split and start Claude.

**Args:** `[args passed to claude...]`

### `hsplit`

Create a horizontal split and start Claude.

**Args:** `[args passed to claude...]`

### `window`

Open a new tmux window and start Claude.

**Args:** `[args passed to claude...]`

### `inline`

Send a prompt directly to `claude -p` and print the response. Reads from stdin, positional args, or opens your editor if neither is provided.

**Args:** `[prompt...]`

### `new`

Open your editor to write a prompt, then exec `claude` with it as the initial message.

### `loop`

Interactive prompt loop: open editor, send to `claude -p`, display response, repeat. Leave the editor empty to exit.

### `all`

List all agents, commands, and skills found in `.claude` directories walking up from `$PWD`.

**Options (tool flags):**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--full` | `-f` | Full-text search (grep) rather than name match | false |
| `--verbose` | `-v` | Show `.claude` dir paths on stderr | false |
| `--veryverbose` | `-V` | Show all stderr debug output | false |

**Args:** `[filter...]`

### `agents`

List agents from `.claude/agents/` directories.

**Args:** `[filter...]`

### `commands`

List commands from `.claude/commands/` directories.

**Args:** `[filter...]`

### `skills`

List skills from `.claude/skills/` directories.

**Args:** `[filter...]`

### `vim`

Open matching agents, commands, or skill SKILL.md files in vim.

**Args:** `[filter...]`
