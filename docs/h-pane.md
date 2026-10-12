# h-pane

Manage Herdr panes: list, split, close, move, resize, inspect, and configure named home panes.

## Synopsis

```bash
h pane <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ls [args]` | List panes in the current workspace |
| `lsa [args]` | List panes across all workspaces |
| `split [right\|down] [args]` | Split the current pane |
| `hsplit` / `splith` | Split down |
| `vsplit` / `splitv` | Split right |
| `kill [pane]` | Close a pane |
| `swap <direction>` | Swap the current pane left, right, up, or down |
| `swap <source> <target>` | Swap two panes by ID |
| `zoom [pane]` | Toggle pane zoom |
| `capture [pane] [lines]` | Print recent pane output |
| `select [pane]` | Resolve and print a pane ID |
| `copy [pane]` | Copy a pane ID to the clipboard |
| `sw` / `switch [pane]` | Focus the pane's workspace and tab |
| `move <pane> <tab> [right\|down]` | Move a pane into a tab |
| `break [pane]` | Move a pane into a new tab |
| `join <source> <target> [right\|down]` | Move a pane beside another pane |
| `resize <direction> [amount] [pane]` | Resize a split |
| `info [pane]` | Show pane size, agent, path, and status |
| `home` | Manage named home panes |

When an extra argument is passed to `ls`, `lsa`, or a split command, it is forwarded to the corresponding Herdr CLI command.

Herdr 0.8.2 focuses tabs rather than arbitrary pane IDs. `h pane switch` therefore focuses the pane's workspace and tab.

## Home panes

Home panes save a workspace label and optional path:

| Subcommand | Description |
|------------|-------------|
| `home ls` | List saved homes |
| `home add <name> <workspace> [path]` | Save a home |
| `home rm <name>` | Remove a home |
| `home switch [name]` | Open or focus the home's workspace and tab |

Homes live only in SQLite, in the `pane_homes` table of `~/.config/hiiro/hiiro.db`. `home add` updates the named row in place and preserves its ID, existing path when omitted, legacy session, and other saved fields. `home rm` deletes only the exact name. Listing prefers `workspace` over the legacy `session` field.

Legacy `pane_homes.yml` is an explicit migration source, not a live configuration file. Home commands neither read nor rewrite it.

The mounted `pin` command also uses SQLite only. `h pane pin set <key> <value>` stores CLI text as text, so `42`, `false`, and JSON-looking text do not become numbers, booleans, or collections. `pin all`, `pin get <key>`, and `pin rm <key>` read or mutate the command-specific pins without replacing other keys. Legacy pin files remain recovery sources.

```bash
h pane home add work development ~/work
h pane home switch work
h pane capture w1:p1 100
h pane resize right 0.1 w1:p1
```
