# h-buffer

Manage tmux paste buffers — list, show, copy to clipboard, save, load, paste, and delete.

## Synopsis

```bash
h buffer <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ls` | List all tmux buffers |
| `show` | Print contents of a buffer |
| `copy` | Copy buffer contents to macOS clipboard |
| `save` | Save buffer contents to a file |
| `load` | Load a file into the tmux buffer stack |
| `set` | Set buffer contents |
| `paste` | Paste a buffer into the current pane |
| `delete` | Delete a buffer |
| `choose` | Open the tmux buffer chooser UI |
| `clear` | Delete all tmux buffers |
| `select` | Fuzzy-select a buffer name and print it |

## Subcommand Details

### `ls`

List all tmux buffers. Extra args are passed directly to `tmux list-buffers`.

```bash
h buffer ls
h buffer ls -F '#{buffer_name}: #{buffer_size} bytes'
```

### `show`

Print the contents of a buffer. Fuzzy-selects if no buffer name is given.

```bash
h buffer show
h buffer show buffer0
```

### `copy`

Copy a buffer's contents to the macOS clipboard via `pbcopy`. Fuzzy-selects if no name given.

```bash
h buffer copy
h buffer copy buffer0
```

### `save`

Save a buffer's contents to a file on disk. Fuzzy-selects the buffer if name is not given.

```bash
h buffer save /tmp/output.txt
h buffer save /tmp/output.txt buffer0
```

### `load`

Load a file into the tmux buffer stack.

```bash
h buffer load /tmp/some-text.txt
```

### `set`

Set buffer contents. All args are passed directly to `tmux set-buffer`.

```bash
h buffer set "hello world"
```

### `paste`

Paste a buffer into the current pane.

```bash
h buffer paste
h buffer paste buffer0
```

### `delete`

Delete a buffer. Fuzzy-selects if no name given.

```bash
h buffer delete
h buffer delete buffer0
```

### `choose`

Open the tmux buffer chooser UI.

```bash
h buffer choose
```

### `clear`

Delete all tmux buffers.

```bash
h buffer clear
```

### `select`

Fuzzy-select a buffer name and print it (useful in scripts).

```bash
h buffer select
selected=$(h buffer select)
```

## Examples

```bash
# See what's in the buffers
h buffer ls

# Show contents of the most recent buffer
h buffer show

# Copy buffer to clipboard for pasting outside tmux
h buffer copy

# Save buffer to file for later use
h buffer save ~/notes/files/output.txt

# Delete old buffers
h buffer clear
```
