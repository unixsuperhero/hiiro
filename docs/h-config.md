# h-config

Open common configuration files in your editor.

## Synopsis

```bash
h config <subcommand>
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `vim` | Open `~/.config/nvim/init.lua` (or `init.vim`) |
| `git` | Open git config files (nested subcommands) |
| `tmux` | Open `~/.tmux.conf` |
| `zsh` | Open `~/.zshrc` |
| `profile` | Open `~/.zprofile` |
| `starship` | Open `~/.config/starship/starship.toml` |
| `claude` | Open `~/.claude/settings.json` |

## Subcommand Details

### `vim`

Opens your Neovim/Vim config. Prefers `~/.config/nvim/init.lua`; falls back to `init.vim` if the lua file does not exist.

```bash
h config vim
```

### `git`

Open git configuration files. Has nested sub-subcommands:

- `h config git global` — Open `~/.gitconfig`
- `h config git ignore` — Open `~/.config/git/ignore`
- `h config git local` — Open `.git/config` in the current repository

```bash
h config git global
h config git ignore
h config git local
```

### `tmux`

Open `~/.tmux.conf`.

```bash
h config tmux
```

### `zsh`

Open `~/.zshrc`.

```bash
h config zsh
```

### `profile`

Open `~/.zprofile`.

```bash
h config profile
```

### `starship`

Open `~/.config/starship/starship.toml`.

```bash
h config starship
```

### `claude`

Open `~/.claude/settings.json`.

```bash
h config claude
```

## Examples

```bash
# Edit vim config
h config vim

# Add a git alias
h config git global

# Edit shell config
h config zsh

# Tweak Claude Code settings
h config claude
```
