# h-buffer

Manage tmux paste buffers — list, show, copy to clipboard, save, load, paste, and delete.

## Synopsis

```bash
h buffer <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ls [args]` | List all tmux buffers |
| `show [name]` | Show contents of a buffer |
| `copy [name]` | Copy buffer contents to clipboard |
| `save <path> [name]` | Save buffer to a file |
| `load <path>` | Load a file into a buffer |
| `set [args]` | Set buffer contents (`tmux set-buffer`) |
| `paste [name]` | Paste buffer into current pane |
| `delete [name]` | Delete a buffer |
| `choose` | Open tmux choose-buffer UI |
| `clear` | Delete all buffers |
| `select` | Fuzzy-select a buffer and print its name |

Buffer names are resolved interactively via fuzzy select when not provided. Extra arguments are forwarded to the underlying `tmux` command.

### choose

Open the tmux `choose-buffer` interactive UI.

**Examples**

```bash
h buffer choose
```

### clear

Delete all tmux buffers.

**Examples**

```bash
h buffer clear
```

### copy

Copy a buffer's contents to the macOS clipboard via `pbcopy`. Fuzzy-select if no name given.

**Examples**

```bash
h buffer copy
h buffer copy buffer0
```

### delete

Delete a buffer. Fuzzy-select if no name given.

**Examples**

```bash
h buffer delete
h buffer delete buffer0
```

### load

Load a file's contents into a new tmux buffer.

**Examples**

```bash
h buffer load ~/notes/snippet.txt
```

### ls

List all tmux buffers. Extra arguments are passed to `tmux list-buffers`.

**Examples**

```bash
h buffer ls
```

### paste

Paste a buffer into the current pane. Fuzzy-select if no name given.

**Examples**

```bash
h buffer paste
h buffer paste buffer0
```

### save

Save a buffer to a file. Fuzzy-select buffer if no name given.

**Examples**

```bash
h buffer save ~/notes/snippet.txt
h buffer save ~/notes/snippet.txt buffer0
```

### select

Fuzzy-select a buffer and print its name (useful for scripting).

**Examples**

```bash
h buffer select
name=$(h buffer select)
```
### show

Print the contents of a buffer. Fuzzy-select if no name given.

**Examples**

```bash
h buffer show
h buffer show buffer0
```

