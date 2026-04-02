# h-config

Open common configuration files in your editor.

## Usage

```
h config <subcommand>
```

## Subcommands

### `vim`

Open `~/.config/nvim/init.lua` (or `init.vim` if lua not found).

### `git`

Open git config files. This subcommand has nested sub-subcommands:

- `h config git global` — Open `~/.gitconfig`
- `h config git ignore` — Open `~/.config/git/ignore`
- `h config git local` — Open `.git/config` in the current repository

### `tmux`

Open `~/.tmux.conf`.

### `zsh`

Open `~/.zshrc`.

### `profile`

Open `~/.zprofile`.

### `starship`

Open `~/.config/starship/starship.toml`.

### `claude`

Open `~/.claude/settings.json`.
