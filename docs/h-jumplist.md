# h-jumplist

Vim-style tmux navigation history — jump backward and forward through pane/window/session focus history.

## Synopsis

```bash
h jumplist <subcommand>
```

History is stored per tmux client in `~/.config/hiiro/jumplist/`. Each client gets two files: `<client>-entries` (the history stack) and `<client>-position` (current index). The list holds up to 50 entries. Dead panes are automatically pruned. Duplicate consecutive entries are deduplicated. Forward history is truncated when you navigate to a new location (like vim's jumplist).

## Subcommands

| Subcommand | Aliases | Description |
|------------|---------|-------------|
| `setup` | — | Write tmux conf and install hooks/keybindings |
| `record` | — | Record current pane/window/session (called by tmux hooks) |
| `back` | — | Navigate to previous (older) position |
| `forward` | — | Navigate to next (newer) position |
| `to` | — | Navigate directly to a history entry by index |
| `ls` | `list` | Print the full jumplist with current position marker |
| `clear` | — | Clear history and reset to current pane |
| `path` | — | Print the jumplist file path for the current client |

## Subcommand Details

### `setup`

Write `~/.config/tmux/h-jumplist.tmux.conf` with:

- tmux hooks to call `h jumplist record` on pane/window/session changes
- Key bindings: `Ctrl-B` = back, `Ctrl-F` = forward

Also appends a `source-file` line to `~/.tmux.conf` if not already present. Reload tmux after setup: `tmux source-file ~/.tmux.conf`.

```bash
h jumplist setup
```

### `record`

Record the current pane/window/session as a new jumplist entry. Normally called automatically by tmux hooks; not needed manually. Suppresses itself if the tmux environment variable `TMUX_JUMPLIST_SUPPRESS=1` is set (used internally to prevent recording during jumplist navigation).

```bash
h jumplist record
```

### `back`

Navigate to the previous (older) position. If already at the oldest entry, shows a tmux message instead of navigating.

```bash
h jumplist back
# Or use the keybinding: Ctrl-B (after setup)
```

### `forward`

Navigate to the next (newer) position. If already at the newest entry, shows a tmux message.

```bash
h jumplist forward
# Or use the keybinding: Ctrl-F (after setup)
```

### `to`

Navigate directly to a specific history entry by its index (0-based, from `ls` output).

```bash
h jumplist to 3
```

### `ls` / `list`

Print the full jumplist. Each line shows: `index | session | window | pane | command | time`. A `<--` marker indicates the current position.

```bash
h jumplist ls
#   0) main | @5 | %12 | zsh | 14:32:01
#   1) work | @3 | %8  | nvim | 14:30:45 <--
#   2) work | @2 | %5  | ruby | 14:28:12
```

### `clear`

Clear the history list and reset position to the current pane.

```bash
h jumplist clear
```

### `path`

Print the jumplist file path for the current tmux client.

```bash
h jumplist path
# => /Users/josh/.config/hiiro/jumplist/client_name-entries
```

## Examples

```bash
# Initial setup (run once)
h jumplist setup
tmux source-file ~/.tmux.conf

# Navigate back through recent panes
# Press Ctrl-B repeatedly (after setup)

# Navigate forward
# Press Ctrl-F (after setup)

# See where you've been
h jumplist ls

# Jump directly to a specific entry
h jumplist to 5

# Start fresh
h jumplist clear
```
