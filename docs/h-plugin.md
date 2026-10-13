# h-plugin

List, edit, and search hiiro plugin files in `~/.config/hiiro/plugins/`.

A plugin loads only for a command that names it, e.g. `Hiiro.run(*ARGV, plugins: [:Pins])`: `Pins` requires `pins.rb` from `~/.config/hiiro/plugins/`, else from the gem's `plugins/`. Importing `hiiro` loads no plugin and creates no plugin directory, and `h plugin path` prints the directory without creating it.

`h plugin` is the `plugin` directory profile (`Hiiro::DirectoryProfile`, see [h home](h-home.md)); `path`, `rg`, and `rgall` behave as in `h home`, `h dotfiles`, and `h vim`.

## Synopsis

```bash
h plugin <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ls` | List all plugin files |
| `path` | Print the plugins directory path (no newline) |
| `edit [names]` | Open matching plugin files in editor |
| `rg [args]` | Run `rg` in the plugins directory |
| `rgall [args]` | Run `rg` (ignoring .gitignore) in the plugins directory |

### edit

Open matching plugin files in your editor. With no args, opens the `h-plugin` bin itself. Names are prefix-matched against the basenames of every file under the directory (subdirectories included). With no match it prints `No matching plugins found for: "NAME"`.

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

Run `rg -S ARGS` (smart case) in the plugins directory. A missing directory is an error (`ERROR: Directory does not exist: ...`).

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
