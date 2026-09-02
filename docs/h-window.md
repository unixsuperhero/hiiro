# h-window

Compatibility commands for Herdr tabs. The `window` command name remains available, but every operation targets a Herdr tab.

## Synopsis

```bash
h window <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ls [args]` | List tabs in the current workspace |
| `lsa [args]` | List tabs across workspaces |
| `new [name] [cwd]` | Create and focus a tab |
| `kill [tab]` | Close a tab |
| `rename <new-name> [tab]` | Rename a tab |
| `select [tab]` | Resolve and print a tab ID |
| `copy [tab]` | Copy a tab ID to the clipboard |
| `sw` / `switch [tab]` | Focus a tab |
| `next` | Focus the next tab |
| `prev` | Focus the previous tab |
| `last` | Focus the last tab |
| `info [tab]` | Show tab details |

The old layout, link, unlink, move-window, and swap-window commands are unavailable because Herdr 0.8.2 does not expose equivalent tab operations. Use `h pane move`, `h pane join`, and `h pane swap` for pane-level organization.

```bash
h window new tests ~/work/project
h window switch tests
h window next
```
