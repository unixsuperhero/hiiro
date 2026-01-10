# h-plugin

Hiiro plugin management and exploration.

[← Back to docs](README.md) | [← Back to main README](../README.md)

## Usage

```sh
h plugin <subcommand> [args...]
```

## Subcommands

| Command | Description |
|---------|-------------|
| `path` | Print the plugins directory path |
| `ls` | List all plugin files |
| `edit` | Edit plugin file(s) in your editor |
| `rg` | Search plugin code (smart-case) |
| `rgall` | Search plugin code (include VCS-ignored files) |

## Examples

```sh
# Get the plugins directory
h plugin path
# => ~/.config/hiiro/plugins

# List all plugins
h plugin ls

# Edit the h-plugin script itself
h plugin edit

# Edit specific plugin(s) by prefix
h plugin edit pins          # Edit pins.rb
h plugin edit task project  # Edit task.rb and project.rb

# Search for a method across all plugins
h plugin rg "def load"

# Search with regex
h plugin rg "add_subcmd.*:session"

# Include normally-ignored files
h plugin rgall "TODO"
```

## Plugin Location

Plugins are stored in `~/.config/hiiro/plugins/`. Files in this directory are automatically loaded by Hiiro.

## Notes

- The `rg` command uses ripgrep with smart-case matching (`-S`)
- The `edit` command uses `$EDITOR` or falls back to `safe_nvim`
- Plugin names are matched by prefix, so `h plugin edit pi` would match `pins.rb`
