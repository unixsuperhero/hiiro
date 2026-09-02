# h-title

Rename the current Herdr pane from its associated Hiiro task or workspace.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `update` | Rename the pane to the current task name, falling back to the workspace label |
| `setup` | Explain that Herdr requires no title hooks |

`update` is a silent no-op outside a Herdr pane. Herdr tracks pane and agent titles natively, so Hiiro no longer installs terminal focus hooks.

```bash
h title update
h title setup
```
