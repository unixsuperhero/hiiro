# h-pane

Manage tmux panes — list, split, kill, zoom, capture, resize, and configure named home panes.

## Synopsis

```bash
h pane <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ls [args]` | List panes in current window |
| `lsa [args]` | List all panes across all sessions |
| `split [args]` | Split window |
| `splitv [args]` | Vertical split (side by side) |
| `splith [args]` | Horizontal split (top/bottom) |
| `kill [target]` | Kill a pane |
| `swap [args]` | Swap panes |
| `zoom [target]` | Toggle pane zoom |
| `capture [args]` | Capture pane contents |
| `select [target]` | Print target pane ID (fuzzy-select if needed) |
| `copy [target]` | Copy pane target to clipboard |
| `sw` / `switch [target]` | Switch to a pane's session |
| `move [args]` | Move a pane |
| `break [args]` | Break pane into a new window |
| `join [args]` | Join a pane from another window |
| `resize [args]` | Resize a pane |
| `width <size> [target]` | Set pane width |
| `height <size> [target]` | Set pane height |
| `info [target]` | Show pane info (size, command, path) |
| `home` | Named home pane management |

### ls / lsa

List panes in the current window (`ls`) or all panes across all sessions (`lsa`). Extra arguments are forwarded to `tmux list-panes`.

**Examples**

```bash
h pane ls
h pane lsa
```

### split / splitv / splith

Split the current window. `splitv` splits vertically (side by side), `splith` splits horizontally (top/bottom). Extra args forwarded to `tmux split-window`.

**Examples**

```bash
h pane split
h pane splitv
h pane splith
```

### kill

Kill a pane. Fuzzy-select if no target given.

**Examples**

```bash
h pane kill
h pane kill %3
```

### zoom

Toggle zoom on a pane. Extra args forwarded to `tmux resize-pane -Z`.

**Examples**

```bash
h pane zoom
h pane zoom %3
```

### capture

Capture and print the contents of the current pane. Extra args forwarded to `tmux capture-pane`.

**Examples**

```bash
h pane capture
```

### select

Fuzzy-select a pane and print its ID. Useful for scripting.

**Examples**

```bash
h pane select
pane=$(h pane select)
```

### copy

Fuzzy-select a pane and copy its ID to the clipboard.

**Examples**

```bash
h pane copy
```

### sw / switch

Switch to the session associated with a pane. Fuzzy-select if no target given.

**Examples**

```bash
h pane sw
h pane switch %3
```

### width / height

Set pane width or height in characters. Fuzzy-select target if not provided.

**Examples**

```bash
h pane width 80
h pane height 20
```

### info

Show pane details: size, current command, working path.

**Examples**

```bash
h pane info
h pane info %3
```

### home

Manage named "home" panes — saved session+path combos that can be quickly switched to.

#### home subcommands

| Subcommand | Description |
|------------|-------------|
| `ls` | List all home panes |
| `add <name> <session> [path]` | Add a named home pane |
| `rm <name>` | Remove a named home pane |
| `switch [name]` | Switch to a named home pane (fuzzy-select if no name) |

Home panes are stored in `~/.config/hiiro/pane_homes.yml`. When switching, creates the session and/or window if they don't exist.

**Examples**

```bash
h pane home ls
h pane home add work main ~/work
h pane home add devserver main
h pane home switch work
h pane home switch
h pane home rm work
```
