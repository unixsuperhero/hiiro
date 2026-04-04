# h-plugin

List, edit, and search hiiro plugin files in `~/.config/hiiro/plugins/`.

## Synopsis

```bash
h plugin <subcommand> [args]
```

Plugins are Ruby modules auto-loaded from `~/.config/hiiro/plugins/` at startup. They extend the hiiro instance with additional subcommands and helper methods.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `path` | Print the plugin directory path |
| `ls` | Print paths of all files in the plugin directory |
| `edit` | Open plugin files in your editor |
| `rg` | Run `rg -S` (case-smart ripgrep) inside the plugin directory |
| `rgall` | Run `rg -S --no-ignore-vcs` inside the plugin directory |

## Subcommand Details

### `path`

Print the plugin directory path (`~/.config/hiiro/plugins`).

```bash
h plugin path
# => /Users/josh/.config/hiiro/plugins
```

### `ls`

Print the full paths of all files in the plugin directory.

```bash
h plugin ls
```

### `edit`

Open plugin files in your editor. With no args, opens `h-plugin` itself. With name args, prefix-matches plugin filenames and opens the matches.

```bash
h plugin edit                  # edit h-plugin itself
h plugin edit tasks            # edit tasks.rb plugin
h plugin edit not pins         # edit notify.rb and pins.rb
```

### `rg`

Run `rg -S` (case-smart ripgrep) inside the plugin directory. All args are forwarded to `rg`.

```bash
h plugin rg "def add_subcmd"
h plugin rg "class.*Plugin"
```

### `rgall`

Same as `rg` but includes VCS-ignored files (`--no-ignore-vcs`).

```bash
h plugin rgall "TODO"
```

## Examples

```bash
# See what plugins are installed
h plugin ls

# Find a method across all plugins
h plugin rg "def task_path"

# Edit the tasks plugin
h plugin edit tasks

# Edit multiple plugins at once
h plugin edit pins project
```
