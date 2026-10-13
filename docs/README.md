# Hiiro Bin Reference

Quick-reference index of all `h-*` executables and the main `h` entry point.

## Main entry point

| Command | Description |
|---------|-------------|
| [h](h.md) | Install, update, setup, and dispatch to all subcommands |

## Git

| Command | Description |
|---------|-------------|
| [h-branch](h-branch.md) | Manage, tag, search, and inspect git branches with task and PR associations |
| [h-commit](h-commit.md) | Choose a git commit SHA from the recent log (shared `commits` picker); `h git commit` plans and makes logical commits |
| [h-sha](h-sha.md) | Choose, show, and copy git commit SHAs (shared `commits` picker) |
| [h-sparse](h-sparse.md) | Manage named git sparse-checkout path groups |
| [h-wtree](h-wtree.md) | Manage git worktrees with fuzzy selection and Herdr workspace switching |

## GitHub

| Command | Description |
|---------|-------------|
| [h-cpr](h-cpr.md) | Proxy `h pr` subcommands to the PR for the current branch |
| [h-pr](h-pr.md) | Track, update, view, and act on GitHub pull requests |
| [h-pr-monitor](h-pr-monitor.md) | Notify once per check, review, or dependency change of tracked PRs; opt-in fix queueing |

## Herdr

| Command | Description |
|---------|-------------|
| [h-notify](h-notify.md) | Send Herdr notifications and navigate their workspace/tab locations |
| [h-pane](h-pane.md) | Manage Herdr panes — split, close, zoom, resize, home panes |
| [h-session](h-session.md) | Compatibility commands for Herdr workspaces |
| [h-title](h-title.md) | Rename the current Herdr pane from its Hiiro task |
| [h-window](h-window.md) | Compatibility commands for Herdr tabs |

## Claude / AI

| Command | Description |
|---------|-------------|
| [h-claude](h-claude.md) | Launch Claude sessions in Herdr splits, search `.claude` dirs, run inline prompts |
| [h-pm](h-pm.md) | Queue named `/project-manager` skill prompts (`pm-SUBCMD[-ARGS]`) in the prompt queue |

## App / Project Management

| Command | Description |
|---------|-------------|
| [h-app](h-app.md) | Manage named application subdirectories within a git repo |
| [h-project](h-project.md) | Manage project directories and open Herdr workspaces |

## Data / Config

| Command | Description |
|---------|-------------|
| [h-bin](h-bin.md) | List and edit hiiro bin scripts in PATH |
| [h-config](h-config.md) | Open common configuration files in your editor |
| [h-db](h-db.md) | Inspect and manage the hiiro SQLite database |
| [h-link](h-link.md) | Store, search, tag, and open saved URLs |
| [h-plugin](h-plugin.md) | List, edit, and search hiiro plugin files |
| [h-home](h-home.md) | `h home`, `h dotfiles`, `h vim`: directory profiles (path, search, edit, specialised actions) |
| [h-registry](h-registry.md) | Store and look up named resources by type with short aliases |
| [h-tags](h-tags.md) | Query tags grouped by taggable type |
| [h-todo](h-todo.md) | Manage a personal todo list with statuses, tags, and task associations |

## Utilities

| Command | Description |
|---------|-------------|
| [h-bg](h-bg.md) | Run commands in background Herdr tabs with history tracking |
| [h-extract](../README.md#extract-files-directories-and-links) | Extract file paths, directories, and HTTP(S) links from text |
| [h-img](h-img.md) | Save or base64-encode images from clipboard or file |
| [h-save](h-save.md) | Save clipboard text or images to ~/saved |
| [h-misc](h-misc.md) | Miscellaneous utilities (symlink destination reporting) |
| [h-sha](h-sha.md) | Choose, show, and copy git commit SHAs (shared `commits` picker) |
| [h-encode](h-encode.md) | `h encode`, `h decode`: Base64, Base64url, hex, percent, form, HTML, JSON-string, ROT13 byte filters |
| [h-env](h-env.md) | `h env add`, `h export add`: append literal `export NAME="VALUE"` lines to a shell file |
| [h-ruby](h-ruby.md) | `h ruby iface`, `h iface rb`: Ruby declaration lines by pattern group |
| [h-time](h-time.md) | `h date`, `h time`: unix timestamps, formatting, durations, differences |
| [h-video](h-video.md) | `h video` FFmpeg presets and `h audio` clips, length, transcription adapter |
| [h-media-capture](h-media-capture.md) | `h screencap` window recording, `h crop` amber-border crop, `h asciinema` dated casts |
| [h-mermaid](h-mermaid.md) | Render Mermaid files to PNG or SVG with `mmdc` |
| [profile.yml](#personal-profile) | Personal recipe policy for casts, screen capture, and transcription |

## Personal profile

Machine- and person-specific recipe policy lives in one optional YAML file,
`~/.config/hiiro/profile.yml` (`Hiiro::Profile`), one section per recipe. A key
in the file wins over the command's portable default; a String argv is split
into words and never run through a shell. Discovery and help never read it; a
recipe reads its section only when it runs.

| Section | Keys and defaults | Used by |
|---|---|---|
| `casts` | `dir` (`~/casts`), `editor` (`$EDITOR`, else `vi`), `resume_args` (`['+norm! g`"']`) | [h asciinema](h-media-capture.md) |
| `screencap` | `out_dir` (`~/Movies/h-screencap`), `apps` (`NAME: {open, process, wait}`, none) | [h screencap](h-media-capture.md) |
| `transcribe` | `command` (`mlx_whisper`), `model` (`$WHISPER_MODEL`) | [h audio transcribe](h-video.md) |

The values the installed personal commands hard-coded, to keep them:

```yaml
casts:
  dir: ~/notes/yt/casts
  editor: safe_nvim
screencap:
  apps:
    codehiiro: { open: release/CodeHiiro.app, process: CodeHiiro, wait: 1 }
transcribe:
  command: ~/proj/vc/VoxCPM/.venv/bin/mlx_whisper
```

## Abbreviations

All commands support prefix abbreviation:

```sh
h ses ls      # h session ls
h win new     # h window new
h br save     # h branch save
```
