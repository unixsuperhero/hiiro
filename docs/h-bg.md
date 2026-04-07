# h-bg

Run commands in background tmux windows with command history tracking.

## Synopsis

```bash
h bg <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `run <cmd>` | Run a command in a new background tmux window |
| `popup` | Open an editor to write and launch a background command |
| `attach` / `a` | Switch to the background tmux session |
| `history` / `hist` | Show recent background command history |
| `setup` | Print tmux.conf snippet for a keybinding |

Background commands run in the `hbg` tmux session (created if it doesn't exist). Each command opens in a new window named after the first word of the command. History is stored in `~/.config/hiiro/bg-history.txt` (last 50 commands).

### attach / a

Switch the current tmux client to the `hbg` background session.

**Examples**

```bash
h bg attach
h bg a
```

### history / hist

Print recent background command history, one per line with index.

**Examples**

```bash
h bg history
h bg hist
```

### popup

Open your `$EDITOR` with a template pre-populated from recent history (commented out). Write your command, save, and quit — it runs in the background. Empty or all-comment files are a no-op.

**Examples**

```bash
h bg popup
```

### run

Run a shell command in a new detached background tmux window. The command is appended to the history file.

**Examples**

```bash
h bg run bundle exec rake test
h bg run sleep 60
h bg run ./scripts/long_job.sh
```

### setup

Print the tmux.conf snippet needed to bind `h bg popup` to a key (prefix + b by default). Add the output to your `~/.tmux.conf`.

**Examples**

```bash
h bg setup >> ~/.tmux.conf
tmux source-file ~/.tmux.conf
```
