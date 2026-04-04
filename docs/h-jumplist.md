# h-jumplist

Vim-style tmux navigation history — jump backward and forward through pane/window/session focus history.

## Synopsis

```bash
h jumplist <subcommand>
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `setup` | Install tmux hooks and keybindings |
| `record` | Record current pane/window/session position (called by tmux hooks) |
| `back` | Navigate to previous position |
| `forward` | Navigate to next position |
| `to <index>` | Jump to a specific position by index |
| `ls` / `list` | Show history with timestamps and current position marker |
| `clear` | Clear the history |
| `path` | Print the jumplist file path |

History is per-tmux-client (per terminal), stored in `~/.config/hiiro/jumplist/`. Maximum 50 entries. Dead panes are pruned automatically. Duplicate consecutive entries are deduplicated. Forward history is truncated when navigating to a new location.

### setup

Write a tmux config file at `~/.config/tmux/h-jumplist.tmux.conf` with hooks and keybindings, then append a `source-file` line to `~/.tmux.conf`.

Default keybindings after setup:

- `Ctrl-B` — jump back
- `Ctrl-F` — jump forward

**Examples**

```bash
h jumplist setup
tmux source-file ~/.tmux.conf
```

### record

Record the current pane/window/session as the newest history entry. Called automatically by tmux hooks after `setup`. Can be suppressed by setting `TMUX_JUMPLIST_SUPPRESS=1` in the tmux environment.

**Examples**

```bash
h jumplist record
```

### back

Navigate one step back in the jumplist. If at position 0, the current pane is recorded first so `forward` can return to it.

**Examples**

```bash
h jumplist back
```

### forward

Navigate one step forward in the jumplist.

**Examples**

```bash
h jumplist forward
```

### to

Jump to a specific history entry by index.

**Examples**

```bash
h jumplist to 3
```

### ls / list

Show the full jumplist with index, session, window, pane, command, and timestamp. Current position is marked with `<--`.

**Examples**

```bash
h jumplist ls
h jumplist list
```

### clear

Reset the jumplist to a single entry (the current pane).

**Examples**

```bash
h jumplist clear
```

### path

Print the path to the jumplist file for the current tmux client.

**Examples**

```bash
h jumplist path
```
