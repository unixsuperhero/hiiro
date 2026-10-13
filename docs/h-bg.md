# h-bg

Run commands in unfocused Herdr tabs with command history tracking.

Inside Herdr, commands run in the `h-bg` workspace. Each command reuses the first pane there that is sitting at an idle shell prompt (no agent and no foreground process, as reported by `herdr pane process-info`) and is not reserved by another background run, and only opens a new unfocused tab when every pane is busy or reserved, so the workspace holds at most as many tabs as jobs that ran at the same time. Choosing and reserving a pane happen under one lock (`~/.local/share/hiiro/bg/reservations/`), so concurrent launches never type into the same pane; the reservation is released when the run finishes or fails to start. Outside Herdr, Hiiro spawns a detached supervisor that keeps the command's output on the launching terminal. History is stored at `~/.config/hiiro/bg-history.txt`.

Every command is an owned run (see [owned runs](owned-runs.md)). `h bg run` prints the run ID and state once the command has actually started (`run-20261013120000-1a2b3c4d started pid 4242 [pane w2:p3]`), and exits with an error when Herdr does not create the tab, does not run the command, or the command cannot start. Background runs have no readiness or stop lifecycle.

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
| `ls` | Show background runs with their state and exit status |
| `history` / `hist` | Show recent commands |
| `setup` | Explain optional Herdr shortcut setup |

```bash
h bg run bundle exec rake test
h bg popup
h bg ls
h bg history
h bg attach
```
