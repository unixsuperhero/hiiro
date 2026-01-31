# Hiiro Documentation

This directory contains detailed documentation for all Hiiro subcommands.

[← Back to main README](../README.md)

## Subcommands

| Command | Description |
|---------|-------------|
| [h-buffer](h-buffer.md) | Tmux paste buffer management |
| h-branch | Record and manage git branch history for tasks |
| h-dot | Compare directories and generate symlink/diff commands |
| h-dotfiles | Manage dotfiles in ~/proj/home |
| h-home | Manage home directory files with edit and search |
| h-html | Generate an HTML index of MP4 videos in current directory |
| h-link | Manage saved links with URL, description, and shorthand |
| h-mic | Control macOS microphone input volume |
| h-note | Create, edit, list, and display notes |
| [h-pane](h-pane.md) | Tmux pane management |
| [h-plugin](h-plugin.md) | Manage hiiro plugins (list, edit, search) |
| h-pr | Record PR information linked to tasks |
| h-pr-monitor | Monitor pull requests |
| h-pr-watch | Watch pull requests for updates |
| h-project | Open projects with tmux session management |
| h-runtask | Run templated task scripts |
| h-serve | Start a miniserve HTTP server on port 1111 |
| [h-session](h-session.md) | Tmux session management |
| h-sha | Extract short SHA from git log |
| h-subtask | Shorthand for task subtask management |
| h-task | Comprehensive task manager for git worktrees |
| [h-video](h-video.md) | Video inspection and operations via ffprobe/ffmpeg |
| h-vim | Manage nvim configuration with edit and search |
| [h-window](h-window.md) | Tmux window management |
| h-wtree | Git worktree management |

## Base Commands

The main `h` command includes these built-in subcommands:

| Command | Description |
|---------|-------------|
| `h version` | Display the Hiiro version |
| `h ping` | Simple test command (returns "pong") |
| `h setup` | Install plugins and subcommands to system paths |
| `h edit` | Open the h script in your editor |
| `h path` | Print the current directory |
| `h ppath` | Print project path (git root + relative dir) |
| `h rpath` | Print relative path from git root |
| `h pin` | Per-command key-value storage (via Pins plugin) |
| `h project` | Project navigation with tmux integration (via Project plugin) |
| `h task` | Task management across git worktrees (via Task plugin) |
| `h notify` | macOS desktop notifications via terminal-notifier (via Notify plugin) |

## Plugins

| Plugin | Description |
|--------|-------------|
| Pins | Per-command YAML key-value storage |
| Project | Project directory navigation with tmux session management |
| Task | Task lifecycle management across git worktrees with subtask support |
| Tmux | Tmux session helpers used by Project and Task |
| Notify | macOS desktop notifications via terminal-notifier |

## Abbreviations

All commands support prefix abbreviation:

```sh
h buf ls      # h buffer ls
h ses ls      # h session ls
h vid info    # h video info
```
