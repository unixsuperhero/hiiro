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

Values passed to `Hiiro.run()` are available in subcommand handlers:

```ruby
Hiiro.run(*ARGV, cwd: Dir.pwd) do
  add_subcmd(:pwd) { |*args|
    cwd = get_value(:cwd)
    puts cwd
  }
end
```

## Creating Subcommands

There are two ways to add subcommands to Hiiro:

### 1. External Bin File (Preferred)

Create a new executable `bin/h-<name>` that uses `Hiiro.run`:

```ruby
#!/usr/bin/env ruby
require 'hiiro'

Hiiro.run(*ARGV, plugins: [:Tasks]) {
  add_subcmd(:list) {
    puts "Listing items..."
  }

  add_subcmd(:add) { |name, path=nil|
    puts "Adding #{name} at #{path}"
  }

  add_subcmd(:remove) { |name=nil|
    if name.nil?
      puts "Usage: h mycommand remove <name>"
      next
    end
    puts "Removed #{name}"
  }
}
```

This creates commands like `h mycommand list`, `h mycommand add foo /path`.

### 2. Nested Subcommands via build_hiiro

For complex command hierarchies with shared state, create a nested Hiiro instance:

```ruby
def self.add_subcommands(hiiro)
  hiiro.add_subcmd(:task) do |*args|
    tm = TaskManager.new(hiiro, scope: :task)
    build_hiiro(hiiro, tm).run
  end
end

def self.build_hiiro(parent_hiiro, tm)
  bin_name = [parent_hiiro.bin, parent_hiiro.subcmd || ''].join('-')

  Hiiro.run(bin_name:, args: parent_hiiro.args) do
    add_subcmd(:list) { tm.list }
    add_subcmd(:start) { |name| tm.start_task(name) }
    add_subcmd(:switch) { |name=nil|
      name ||= tm.select_task_interactive
      tm.switch_to_task(tm.task_by_name(name))
    }
  end
end
```

This pattern:
- Passes remaining args from parent to child via `args: parent_hiiro.args`
- Allows shared state (like `tm`) across all nested subcommands
- Creates commands like `h task list`, `h task start foo`

## Library Components (lib/)

The `lib/hiiro.rb` file and `lib/hiiro/` directory contain the core framework classes:

### Hiiro (lib/hiiro.rb)

Main entry point with class methods:
- `Hiiro.run(*ARGV, plugins: [...]) { ... }` - Initialize and run immediately
- `Hiiro.init(*ARGV, plugins: [...]) { ... }` - Initialize without running (returns hiiro instance).  **NEVER USE THIS** without a good reason, always favor `Hiiro.run`

Instance methods available in subcommand blocks:
- `git` - Returns `Hiiro::Git` instance for git operations
- `fuzzyfind(lines)` - Interactive selection via skim
- `pins` - Key-value storage per command
- `todo_manager` - Todo item management
- `history` - Command history tracking
- `attach_method(name, &block)` - Add methods to hiiro instance dynamically
- `make_child(subcmd, *args)` - Create nested Hiiro for sub-subcommands

### Hiiro::Matcher (lib/hiiro/matcher.rb)

Handles pattern matching for commands and items with prefix and substring matching:

```ruby
matcher = Hiiro::Matcher.new(items, :name)

# Prefix matching - find items where name starts with pattern
result = matcher.by_prefix("pre")
result.match?                     # Any matches?
result.one?                       # Exactly one match?
result.ambiguous?                 # Multiple matches?
result.first&.item                # Get first matching item
result.resolved&.item             # Get exact or single match

# Substring matching - find items where name contains pattern anywhere
result = matcher.by_substring("abc")
result.matches.map(&:item)        # All matching items

# Path-based matching for hierarchical names (e.g., "task/subtask")
result = matcher.resolve_path("t/s")

# Class methods for one-off matching
Hiiro::Matcher.by_prefix(items, "pre", key: :name)
Hiiro::Matcher.by_substring(items, "abc", key: :name)
```

Note: `Hiiro::PrefixMatcher` is aliased to `Hiiro::Matcher` for backward compatibility.

### Hiiro::Git (lib/hiiro/git.rb)

Git operations wrapper with submodules for branches, worktrees, remotes, and PRs:

```ruby
git = hiiro.git
git.root                          # Repository root path
git.branch                        # Current branch name
git.branches                      # List all branches
git.worktrees                     # List all worktrees
git.add_worktree(path, branch:)   # Create worktree
git.move_worktree(from, to)       # Rename worktree
git.current_pr                    # Get current PR info
```

### Hiiro::Fuzzyfind (lib/hiiro/fuzzyfind.rb)

Integration with `sk` (skim) or `fzf` fuzzy finders:

```ruby
selected = Hiiro::Fuzzyfind.select(["option1", "option2", "option3"])
# Returns selected string or nil if cancelled

value = Hiiro::Fuzzyfind.map_select({ "Display 1" => "value1", "Display 2" => "value2" })
# Shows keys, returns corresponding value
```

### Hiiro::TodoManager (lib/hiiro/todo.rb)

Todo item management with task association:

```ruby
tm = Hiiro::TodoManager.new
tm.add("Fix bug", tags: "urgent", task_info: { task_name: "feature" })
tm.start(0)                       # Mark item as started
tm.done(0)                        # Mark item as done
tm.active                         # Items not done/skipped
tm.filter_by_task("feature")      # Items for specific task
```

### Hiiro::History (lib/hiiro/history.rb)

Command history tracking with tmux/git/task context:

```ruby
History.track(cmd: full_command, hiiro: self)  # Auto-called after commands
History.by_task("feature")                      # Filter by task
History.by_branch("main")                       # Filter by git branch
History.by_session("work")                      # Filter by tmux session
```

## Key Files

- `bin/h` - Core framework (~420 lines)
- `bin/h-*` - External subcommands (tmux wrappers, video operations)
- `plugins/*.rb` - Reusable plugin modules (Pins, Project, Task, Tmux, Notify)
- `lib/hiiro.rb` - Main Hiiro class and Runners
- `lib/hiiro/*.rb` - Supporting classes (Git, Matcher, Fuzzyfind, Todo, History)

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
