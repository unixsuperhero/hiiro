# h-bg

Run commands in background tmux windows with command history tracking.

## Synopsis

```bash
h bg <subcommand> [args]
```

Commands run in a dedicated tmux session named `bg` (managed by `Hiiro::Background`). History is stored in `~/.config/hiiro/bg-history.txt` (max 50 entries).

## Subcommands

| Subcommand | Aliases | Description |
|------------|---------|-------------|
| `popup` | — | Open editor with history, run typed command in background window |
| `run` | — | Run a command immediately in a new background window |
| `attach` | `a` | Switch to the background tmux session |
| `history` | `hist` | Print recent background command history |
| `setup` | — | Print tmux.conf line for keybinding |

## Subcommand Details

### `popup`

Opens your `$EDITOR` with recent command history as comments. Whatever you type (non-comment, non-blank lines) is run in a new background tmux window. History comments are prefixed with `#` so you can uncomment or rewrite them.

```bash
h bg popup
```

### `run`

Run a command immediately in a new background tmux window. The window is named after the first word of the command. The command is appended to history.

```bash
h bg run bundle exec rails db:migrate
h bg run npm run build
h bg run ./scripts/long_running_job.sh
```

### `attach` / `a`

Switch the current tmux client to the background session.

```bash
h bg attach
h bg a
```

### `history` / `hist`

Print the recent background command history (up to 50 entries), numbered oldest-first.

```bash
h bg history
# 1  bundle exec rails db:migrate
# 2  npm run build
```

### `setup`

Print the `tmux.conf` line needed to bind `prefix + b` to open the popup. Does not modify any config file automatically.

```bash
h bg setup
# bind-key b display-popup -E -w 80% -h 40% "h bg popup"
```

Add the printed line to `~/.tmux.conf` and reload: `tmux source-file ~/.tmux.conf`.

## Examples

```bash
# Run a long database migration in background
h bg run bundle exec rails db:migrate

# Run a build in background
h bg run npm run build -- --production

# Open interactive popup to pick from history
h bg popup

# Check what's running in background
h bg attach

# Review recent commands
h bg hist
```