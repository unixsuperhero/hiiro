# h-plugin

List, edit, and search hiiro plugin files in `~/.config/hiiro/plugins/`.

## Synopsis

```bash
h plugin <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ls` | List all plugin files |
| `path` | Print the plugins directory path |
| `edit [names]` | Open matching plugin files in editor |
| `rg [args]` | Run `rg` in the plugins directory |
| `rgall [args]` | Run `rg` (ignoring .gitignore) in the plugins directory |

### edit

Open matching plugin files in your editor. With no args, opens the `h-plugin` bin itself. Names are prefix-matched against plugin file basenames.

**Examples**

```bash
h plugin edit
h plugin edit pins
h plugin edit task notify
```

### ls

List all files in `~/.config/hiiro/plugins/`.

**Examples**

```bash
h plugin ls
```

### path

Print the path to the plugins directory.

**Examples**

```bash
h plugin path
```

### rg

Run `rg` with case-insensitive smart-case matching in the plugins directory.

**Examples**

```bash
h plugin rg "def load"
h plugin rg "add_subcmd"
```

### rgall

Same as `rg` but also searches files ignored by `.gitignore`.

**Examples**

```bash
h plugin rgall "TODO"
```
