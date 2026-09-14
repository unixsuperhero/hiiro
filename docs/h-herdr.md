# h herdr

Expose the `t` task CLI inside Herdr as keybound actions. Each action opens a session-modal popup that runs `h herdr popup`, so fuzzy pickers and editors get a real TTY without disturbing the tiled layout.

## Install

```bash
h herdr install              # copies herdr-plugin/ to ~/.config/hiiro/herdr-plugin and runs herdr plugin link
h herdr keys                 # prints [[keys.command]] entries to paste into ~/.config/herdr/config.toml
herdr server reload-config
```

`h herdr uninstall` unlinks the plugin and removes the copied directory. Requires Herdr 0.7.4 or newer, and `sk` or `fzf` on `PATH`.

## Actions

| Action | Default key | Popup behavior |
|---|---|---|
| `hiiro.switch` | `prefix+t` | Fuzzy-pick an active or waiting task, then `t NAME switch` |
| `hiiro.todo-add` | `prefix+shift+a` | Fuzzy-pick a task (current task first), type the todo text, then `t NAME todo add TEXT` |
| `hiiro.todos` | `prefix+shift+y` | Fuzzy-pick an open todo of the current task and copy its text to the clipboard |
| `hiiro.shell` | `prefix+shift+s` | 90% popup running `t sh` in the current task's start directory |
| `hiiro.nvim` | `prefix+shift+e` | 90% popup running `$EDITOR` (default `nvim`) in the current task's notes home |

The current task resolves through `Hiiro::CurrentTask`: the popup's Herdr workspace, then the working directory, then the task saved with `t use TASK`. Errors print in the popup for two seconds before it closes.

## Subcommands

| Command | Behavior |
|---|---|
| `h herdr install` | Copy the manifest from the gem, link it in Herdr, print next steps |
| `h herdr uninstall` | Unlink and remove the copy |
| `h herdr keys` | Print the keybinding snippet |
| `h herdr actions` | List action ids |
| `h herdr action NAME` | Headless: open the popup for NAME (what the manifest binds) |
| `h herdr popup` | Runs inside the popup; reads `HIIRO_HERDR_ACTION` |

## Files

- `herdr-plugin/herdr-plugin.toml` in the gem: manifest with five `[[actions]]` and one `[[panes]]` popup entrypoint
- `bin/h-herdr`: actions, popup logic, install and keys helpers
