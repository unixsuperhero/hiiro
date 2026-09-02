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

Homes are stored in `~/.config/hiiro/pane_homes.yml` and mirrored in SQLite.

```bash
h pane home add work development ~/work
h pane home switch work
h pane capture w1:p1 100
h pane resize right 0.1 w1:p1
```
