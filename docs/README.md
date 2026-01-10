# Hiiro Documentation

This directory contains detailed documentation for all Hiiro subcommands.

[← Back to main README](../README.md)

## Subcommands

| Command | Description |
|---------|-------------|
| [h-buffer](h-buffer.md) | Tmux paste buffer management |
| [h-pane](h-pane.md) | Tmux pane management |
| [h-plugin](h-plugin.md) | Hiiro plugin management |
| [h-session](h-session.md) | Tmux session management |
| [h-video](h-video.md) | FFmpeg wrapper for video operations |
| [h-window](h-window.md) | Tmux window management |

## Base Commands

The main `h` command includes these built-in subcommands:

| Command | Description |
|---------|-------------|
| `h edit` | Open the h script in your editor |
| `h path` | Print the current directory |
| `h ppath` | Print project path (git root + relative dir) |
| `h rpath` | Print relative path from git root |
| `h ping` | Simple test command (returns "pong") |
| `h pin` | Key-value storage (via Pins plugin) |
| `h project` | Project navigation (via Project plugin) |
| `h task` | Task management (via Task plugin) |

## Abbreviations

All commands support prefix abbreviation:

```sh
h buf ls      # h buffer ls
h ses ls      # h session ls
h vid info    # h video info
```
