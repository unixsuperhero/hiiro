# h-config

Open common configuration files in `$EDITOR` (default `vim`), from the file's directory. The directory must exist.

## Synopsis

```bash
h config <subcommand>
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `vim` | Open Neovim/Vim config (`init.lua` or `init.vim`) |
| `git` | Git config subcommands |
| `herdr` | Open `~/.config/herdr/config.toml` |
| `ssh` | Open `~/.ssh/config` |
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
| `local` | Open `.git/config` at the top of the current repository |

**Examples**

```bash
h config git global
h config git ignore
h config git local
```

Arguments after the nested subcommand are ignored (`h config git local extra` opens the local config).

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

### herdr

Open `~/.config/herdr/config.toml`.

**Examples**

```bash
h config herdr
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
