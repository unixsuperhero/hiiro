# h-session

Compatibility commands for Herdr workspaces. The `session` command name is retained so existing Hiiro workflows can keep using it.

```js
{
  session: "Herdr workspace",
  window: "Herdr tab",
  pane: "Herdr pane"
}
```

## Synopsis

```bash
h session <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ls` / `list` | List workspaces |
| `new [name] [cwd]` | Create and focus a workspace |
| `kill [workspace]` | Close a workspace |
| `attach` / `switch [workspace]` | Focus a workspace |
| `rename <workspace> <new-name>` | Rename a workspace |
| `has <workspace>` | Print whether a workspace exists |
| `info [workspace]` | Show workspace details |
| `open <name>` | Focus or create a workspace |
| `sh <workspace> [command...]` | Open a tab in a workspace |
| `select` | Fuzzy-select and print a workspace ID |
| `copy` | Copy a selected workspace ID |
| `orphans` | List workspaces not associated with tasks |
| `okill` | Review orphan workspace IDs in an editor, then close the retained IDs |

Workspace names support Hiiro prefix resolution when the match is unambiguous.

```bash
h session new feature ~/work/feature
h session switch feature
h session sh feature bundle exec rake test
h session orphans
```
