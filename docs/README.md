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
| [h-commit](h-commit.md) | Fuzzy-select a git commit SHA from the recent log |
| [h-sha](h-sha.md) | Fuzzy-select, show, and copy git commit SHAs |
| [h-sparse](h-sparse.md) | Manage named git sparse-checkout path groups |
| [h-wtree](h-wtree.md) | Manage git worktrees with fuzzy selection and Herdr workspace switching |

## GitHub

| Command | Description |
|---------|-------------|
| [h-cpr](h-cpr.md) | Proxy `h pr` subcommands to the PR for the current branch |
| [h-pr](h-pr.md) | Track, update, view, and act on GitHub pull requests |
| [h-pr-monitor](h-pr-monitor.md) | Poll `gh pr status` and send notifications on status changes |

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
| [h-pm](h-pm.md) | Queue `/project-manager` skill prompts via `h queue add` |

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
| [h-registry](h-registry.md) | Store and look up named resources by type with short aliases |
| [h-tags](h-tags.md) | Query tags grouped by taggable type |
| [h-todo](h-todo.md) | Manage a personal todo list with statuses, tags, and task associations |

## Utilities

| Command | Description |
|---------|-------------|
| [h-bg](h-bg.md) | Run commands in background Herdr tabs with history tracking |
| [h-img](h-img.md) | Save or base64-encode images from clipboard or file |
| [h-save](h-save.md) | Save clipboard text or images to ~/saved |
| [h-misc](h-misc.md) | Miscellaneous utilities (symlink destination reporting) |
| [h-sha](h-sha.md) | Fuzzy-select, show, and copy git commit SHAs |

## Abbreviations

All commands support prefix abbreviation:

```sh
h ses ls      # h session ls
h win new     # h window new
h br save     # h branch save
```
