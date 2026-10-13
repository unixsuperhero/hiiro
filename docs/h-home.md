# h home, h dotfiles, h vim (directory profiles)

`h home`, `h dotfiles`, `h vim`, and [`h plugin`](h-plugin.md) are one registration,
`Hiiro::DirectoryProfile` (lib/hiiro/directory_profile.rb). A profile is a name, a
root, and the actions it offers; an action two profiles share is one method, so it
behaves the same in both.

```js
// Hiiro::DirectoryProfile::PROFILES
{
  home:     { root: "~",                       actions: ["edit", "path", "abspath", "open", "cd", "sh", "skf", "rg", "rgall", "ebin (glob in ROOT/bin)"] },
  dotfiles: { root: "~/proj/home",             actions: ["edit", "path", "skf", "rg", "rgall", "ebin (arguments as given)"] },
  vim:      { root: "~/.config/nvim",          actions: ["edit", "path", "init|config", "skf", "rg", "rgall", "session|tmux"] },
  plugin:   { root: "~/.config/hiiro/plugins", actions: ["path", "ls", "edit (by prefix)", "rg", "rgall"] },
}
```

Actions that run in the root resolve it as context (`Hiiro::TaskLocation` with
`root_source` set to the profile name and no task, so a task whose directory is the
current directory never changes it) and fail with
`ERROR: Directory does not exist: PATH` (exit 1) before running anything when the root
is missing. They run the native tool in the root.

## Actions

| Action | Profiles | Behavior |
|---|---|---|
| `path` | all | Print the root as configured (`~` expanded, symlinks kept), with no trailing newline. Works when the root does not exist |
| `abspath` | home | Print the resolved root (its real path; it must exist), with no trailing newline |
| `edit` | home, dotfiles, vim | Open the bin's own source in the editor (`h plugin edit` with no arguments does the same) |
| `skf ARGS` | home, dotfiles, vim | Run `skf ARGS` in the root |
| `rg ARGS` | all | Run `rg -S ARGS` in the root |
| `rgall ARGS` | all | Run `rg -S --no-ignore-vcs ARGS` in the root |
| `open` | home | Open the root with `open` (`xdg-open` off macOS) |
| `cd` | home | `cd` the calling Herdr pane to the root (`Not running inside a Herdr pane` otherwise) |
| `sh [CMD...]` | home | Replace this process with `$SHELL` (or `CMD`) in the root |
| `ebin PATTERN...` | home | Edit files in `~/bin` matching each pattern (`*PATTERN*`, or the pattern as is when it ends in `*`) |
| `ebin FILE...` | dotfiles | Edit the files as given, relative to the current directory |
| `init`, `config` | vim | Edit `init.lua` in `~/.config/nvim` |
| `session`, `tmux` | vim | Optional tmux adapter: create a detached `vim` session started in `~/.config/nvim` unless one exists, then `tmux switch-client` inside tmux, or `tmux attach-session` outside it (inside a Neovim terminal it prints `Can't attach to tmux inside a vim terminal`). Without tmux on `PATH`: `ERROR: tmux not found` |
| `ls` | plugin | Print every file and directory under the root, one per line |

The editor is `$EDITOR` (default `nvim`). An unknown or missing subcommand prints
the subcommand list and exits 1 in every profile.

```bash
h home path            # /Users/me
cd "$(h dotfiles path)"
h vim rg 'vim.keymap'
h home ebin h-          # edit ~/bin/*h-*
h vim session
```
