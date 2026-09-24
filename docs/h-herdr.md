# h herdr

Expose task popups and pane controls inside Herdr. Popup actions use the Hiiro plugin; pane focus, reflow, resize, swap, and zoom commands call Herdr's native pane API directly.

## Install

```bash
h herdr install              # copies herdr-plugin/ to ~/.config/hiiro/herdr-plugin and runs herdr plugin link
h herdr keys                 # prints [[keys.command]] entries to paste into ~/.config/herdr/config.toml
herdr server reload-config
```

`h herdr uninstall` unlinks the plugin and removes the copied directory. Requires Herdr 0.7.4 or newer, and `sk` or `fzf` on `PATH`. Run `h herdr keys` again after upgrading Hiiro, paste the new entries, then reload Herdr's config.

## Actions

| Action | Default key | Popup behavior |
|---|---|---|
| `hiiro.switch` | `prefix+t` | Fuzzy-pick an active or waiting task, then `t NAME switch` |
| `hiiro.todo-add` | `prefix+shift+a` | Fuzzy-pick a task (current task first), type the todo text, then `t NAME todo add TEXT` |
| `hiiro.todos` | `prefix+shift+y` | Fuzzy-pick an open todo of the current task and copy its text to the clipboard |
| `hiiro.shell` | `prefix+shift+s` | 90% popup running `t sh` in the current task's start directory |
| `hiiro.nvim` | `prefix+shift+e` | 90% popup running bare `$EDITOR` (default `nvim`) in the working directory of the pane the key was pressed in |
| Native Herdr focus | `prefix+h/j/k/l` | Focus the neighboring pane using Herdr's default Vim bindings |
| Pane reflow | `prefix+shift+h/j/k/l` | Move the current pane to that edge in a two-pane tab; for example `prefix+shift+l` changes a top/bottom split into full-height left/right columns |
| Pane resize | `prefix+alt+h/j/k/l` | Grow or shrink the current split in that direction |

The current task resolves through `Hiiro::CurrentTask`: the popup's Herdr workspace, then the working directory, then the task saved with `t use TASK`. Errors print in the popup for two seconds before it closes.

Pane reflow intentionally requires exactly two panes in the current tab. This keeps an uppercase movement deterministic: the current pane lands on the requested edge and the other pane occupies the remainder. Use native `h herdr swap DIRECTION` for larger layouts instead of silently rebuilding a multi-pane tree.

## Subcommands

| Command | Behavior |
|---|---|
| `h herdr install` | Copy the manifest from the gem, link it in Herdr, print next steps |
| `h herdr uninstall` | Unlink and remove the copy |
| `h herdr keys` | Print task popup, pane reflow, and pane resize keybindings |
| `h herdr actions` | List popup action ids |
| `h herdr action NAME` | Headless: open the popup for NAME |
| `h herdr popup` | Run the selected action inside the popup |
| `h herdr focus DIRECTION` | Focus the neighboring pane; accepts `h/j/k/l` or `left/down/up/right` |
| `h herdr move DIRECTION [RATIO]` | Reflow a two-pane tab with the current pane on DIRECTION and optionally give it RATIO of the available space; aliases: `layout`, `arrange` |
| `h herdr resize DIRECTION [AMOUNT]` | Resize the current pane split |
| `h herdr swap DIRECTION` | Swap the current pane with its neighbor |
| `h herdr zoom` | Toggle current-pane zoom |

`hh focus`, `hh move`, `hh layout`, `hh arrange`, `hh resize`, `hh swap`, and `hh zoom` delegate to the same `h herdr` commands.

## Files

- `herdr-plugin/herdr-plugin.toml` in the gem: task popup actions and popup entrypoint
- `bin/h-herdr`: popup logic, pane controls, installation, and keybinding output
- `bin/hh`: short aliases for the pane controls
