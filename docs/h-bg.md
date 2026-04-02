# h-bg

Run commands in background tmux windows with history tracking.

## Usage

```
h bg <subcommand> [args]
```

## Subcommands

### `popup`

Open your `$EDITOR` with recent command history as comments, then run whatever you type in a background tmux window. History is stored in `~/.config/hiiro/bg-history.txt` (max 50 entries).

### `run`

Run a command immediately in a new background tmux window.

**Args:** `<cmd...>`

### `attach` [alias: `a`]

Switch the current tmux client to the background session.

### `history` [alias: `hist`]

Print the recent background command history (up to 50 entries), newest last.

### `setup`

Print the tmux.conf line needed to bind `prefix + b` to open the popup. Does not modify any config files automatically.
