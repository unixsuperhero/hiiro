# h-plugin

List, edit, and search hiiro plugin files in `~/.config/hiiro/plugins/`.

## Usage

```
h plugin <subcommand> [args]
```

## Subcommands

### `path`

Print the plugin directory path (`~/.config/hiiro/plugins`).

### `ls`

Print the paths of all files in the plugin directory.

### `edit`

Open plugin files in your editor. With no args, opens `h-plugin` itself. With name args, prefix-matches plugin filenames and opens the matches.

**Args:** `[plugin_name...]`

### `rg`

Run `rg -S` (case-smart ripgrep) inside the plugin directory.

**Args:** `[rg_args...]`

### `rgall`

Run `rg -S --no-ignore-vcs` inside the plugin directory (includes VCS-ignored files).

**Args:** `[rg_args...]`
