# h-config

Open common configuration files in your editor.

## Synopsis

```bash
h config <subcommand>
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `vim` | Open Neovim/Vim config (`init.lua` or `init.vim`) |
| `git` | Git config subcommands |
| `tmux` | Open `~/.tmux.conf` |
| `zsh` | Open `~/.zshrc` |
| `profile` | Open `~/.zprofile` |
| `starship` | Open `~/.config/starship/starship.toml` |
| `claude` | Open `~/.claude/settings.json` |

### claude

Open `~/.claude/settings.json`.

**Examples**

```bash
h config claude
```
### git

Open git config files. Nested subcommands:

| Subcommand | Description |
|------------|-------------|
| `global` | Open `~/.gitconfig` |
| `ignore` | Open `~/.config/git/ignore` |
| `local` | Open `.git/config` in the current repo |

**Examples**

```bash
h config git global
h config git ignore
h config git local
```

### profile

Open `~/.zprofile`.

**Examples**

```bash
h config profile
```

### starship

Open `~/.config/starship/starship.toml`.

**Examples**

```bash
h config starship
```

### tmux

Open `~/.tmux.conf`.

**Examples**

```bash
h config tmux
```

### vim

Open `~/.config/nvim/init.lua` (or `init.vim` if lua file doesn't exist).

**Examples**

```bash
h config vim
```

### zsh

Open `~/.zshrc`.

**Examples**

```bash
h config zsh
```

