# h-bg

Run commands in unfocused Herdr tabs with command history tracking.

Inside Herdr, commands run in the `h-bg` workspace, with one tab per command. Outside Herdr, Hiiro falls back to a detached local process. History is stored at `~/.config/hiiro/bg-history.txt`.

## Synopsis

```bash
h bg <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `run <command>` | Run a background command |
| `popup` | Edit and launch a command |
| `attach` / `a` | Focus the `h-bg` workspace |
| `history` / `hist` | Show recent commands |
| `setup` | Explain optional Herdr shortcut setup |

```bash
h bg run bundle exec rake test
h bg popup
h bg history
h bg attach
```
