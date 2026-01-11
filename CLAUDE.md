# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hiiro is a lightweight CLI framework for Ruby that enables building multi-command tools similar to `git` or `docker`. It provides subcommand dispatch, abbreviation matching (e.g., `h ex hel` matches `h example hello`), and a plugin system.

## Development Commands

```bash
# Edit the main h script
h edit

# List available subcommands
h

# Search plugin code
h plugin rg "pattern"

# Edit a specific plugin
h plugin edit pins

# Syntax check Ruby files
ruby -c bin/h
ruby -c plugins/*.rb
```

There is no build step or test suite. This is a pure Ruby CLI tool.

## Architecture

### Core Components (bin/h)

The `Hiiro` class is the main entry point with these nested classes:

- **`Runners`** - Discovers executables matching `h-*` in PATH and manages inline subcommands. Implements exact and prefix-based matching.
- **`Runners::Bin`** - Represents external executables found in PATH
- **`Runners::Subcommand`** - Represents inline subcommands registered via blocks
- **`Args`** - Parses single-dash flags (`-abc` becomes flags `a`, `b`, `c`)
- **`Config`** - Manages `~/.config/hiiro/` directory structure

### Subcommand Resolution Flow

1. `Hiiro.init()` parses first arg as subcommand name
2. `Runners` searches for exact match in subcommands and PATH executables
3. If no exact match, tries prefix matching (abbreviations)
4. Ambiguous matches show help with possible options

### Plugin System

Plugins are Ruby modules with a `self.load(hiiro)` method:

```ruby
module MyPlugin
  def self.load(hiiro)
    # Add methods to hiiro instance
    hiiro.instance_eval do
      def my_helper; end
    end

    # Register subcommands
    hiiro.add_subcmd(:mycmd) { |*args| ... }
  end
end
```

Plugins auto-load from `~/.config/hiiro/plugins/`. Load order matters when plugins depend on each other (e.g., Task and Project depend on Tmux).

### Global Values Pattern

Values passed to `Hiiro.init()` are available in subcommand handlers:

```ruby
hiiro = Hiiro.init(*ARGV, cwd: Dir.pwd)
hiiro.add_subcmd(:pwd) do |*args, **values|
  puts values[:cwd]
end
```

## Key Files

- `bin/h` - Core framework (~420 lines)
- `bin/h-*` - External subcommands (tmux wrappers, video operations)
- `plugins/*.rb` - Reusable plugin modules (Pins, Project, Task, Tmux, Notify)

## External Dependencies

- Ruby with `pry` gem
- `tmux` for session/window/pane management
- `ffmpeg`/`ffprobe` for video operations (h-video)
- `terminal-notifier` for macOS notifications (notify plugin)

## Configuration Locations

All config lives in `~/.config/hiiro/`:
- `plugins/` - Auto-loaded plugin files
- `pins/` - Per-command YAML key-value storage
- `tasks/` - Task metadata for worktree management
- `projects.yml` - Project directory aliases
- `apps.yml` - App directory mappings for task plugin
