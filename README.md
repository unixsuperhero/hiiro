# Hiiro

A lightweight, extensible CLI framework for Ruby. Build your own multi-command tools similar to `git` or `docker`.

## Features

- **Subcommand dispatch** - Route commands to executables or Ruby blocks
- **Abbreviation matching** - Type `h ex hel` instead of `h example hello`
- **Plugin system** - Extend functionality with reusable modules
- **Per-command storage** - Each command gets its own pin/config namespace

See [docs/](docs/) for detailed documentation on all subcommands.

## Installation

### Via RubyGems

```sh
gem install hiiro

# Install plugins and subcommands
h setup
```

This installs:
- Plugins to `~/.config/hiiro/plugins/`
- Subcommands (`h-buffer`, `h-todo`, etc.) to `~/bin/`

Ensure `~/bin` is in your `$PATH`.


### Dependencies

```sh
# For notify plugin (macOS)
brew install terminal-notifier

# For fuzzy-finder
brew install sk # (or fzf)

# For GitHub PR management
brew install gh
```

## Quick Start

```sh
# List available subcommands
h

# Simple test
h ping
# => pong
```

## Subcommands

### Base Commands

| Command | Description |
|---------|-------------|
| `h version` | Display the Hiiro version |
| `h ping` | Simple test command (returns "pong") |
| `h setup` | Install plugins and subcommands to system paths |
| `h edit` | Open the h script in your editor |
| `h alert` | macOS desktop notifications via terminal-notifier |
| `h task` | Task management across git worktrees (via Tasks plugin) |
| `h subtask` | Subtask management within tasks (via Tasks plugin) |

### External Subcommands

| Command | Description |
|---------|-------------|
| `h app` | Manage app directories within tasks/projects |
| `h branch` | Git branch management with fuzzy selection and copy |
| `h buffer` | Tmux paste buffer management |
| `h claude` | Claude CLI wrapper with tmux split support |
| `h commit` | Select commits using fuzzy finder |
| `h config` | Open config files (vim, git, tmux, zsh, starship, claude) |
| `h link` | Manage saved links with URL, description, and shorthand |
| `h pane` | Tmux pane management |
| `h plugin` | Manage hiiro plugins (list, edit, search) |
| `h pr` | GitHub PR management via gh CLI |
| `h project` | Project navigation with tmux session management |
| `h session` | Tmux session management |
| `h sha` | Extract short SHA from git log |
| `h todo` | Todo list management with tags and task association |
| `h window` | Tmux window management |
| `h wtree` | Git worktree management |

## Abbreviations

Any subcommand can be abbreviated as long as the prefix uniquely matches:

```sh
h buf ls      # matches h buffer ls
h ses ls      # matches h session ls
h win         # matches h window
```

If multiple commands match, the first match wins and a warning is logged (when logging is enabled).

## Plugins

Plugins are Ruby modules loaded from `~/.config/hiiro/plugins/`:

| Plugin | Description |
|--------|-------------|
| Pins | Per-command YAML key-value storage |
| Project | Project directory navigation with tmux session management |
| Tasks | Task lifecycle management across git worktrees with subtask support |
| Notify | macOS desktop notifications via terminal-notifier |

## Adding Subcommands

### Method 1: External Executables

Create an executable named `h-<subcommand>` anywhere in your `$PATH`:

```sh
# ~/bin/h-greet
#!/bin/bash
echo "Hello, $1!"
```

```sh
h greet World
# => Hello, World!
```

For nested subcommands, use hiiro in your script:

```ruby
#!/usr/bin/env ruby
# ~/bin/h-example

require 'hiiro'

Hiiro.run(*ARGV) do
  add_subcmd(:hello) { puts "Hi!" }
  add_subcmd(:bye)   { puts "Goodbye!" }
end
```

```sh
h example hello  # => Hi!
h example bye    # => Goodbye!
```

### Method 2: Inline Subcommands

Modify `exe/h` directly to add subcommands to the base `h` command:

```ruby
Hiiro.run(*ARGV, plugins: [Tasks], cwd: Dir.pwd) do
  add_subcmd(:hello) do |*args|
    puts "Hello, #{args.first || 'World'}!"
  end
end
```

Global values (like `cwd`) are accessible via `get_value`:

```ruby
add_subcmd(:pwd) do |*args|
  puts get_value(:cwd)
end
```

## Writing Plugins

Plugins are Ruby modules that extend Hiiro instances:

```ruby
# ~/.config/hiiro/plugins/myplugin.rb

module MyPlugin
  def self.load(hiiro)
    attach_methods(hiiro)
    add_subcommands(hiiro)
  end

  def self.add_subcommands(hiiro)
    hiiro.add_subcmd(:mycmd) do |*args|
      # command logic
    end
  end

  def self.attach_methods(hiiro)
    hiiro.instance_eval do
      def my_helper
        # helper method available to other plugins
      end
    end
  end
end
```

Load plugins in your command:

```ruby
Hiiro.run(*ARGV, plugins: [MyPlugin]) do
  # ...
end
```

## Configuration

All configuration lives in `~/.config/hiiro/`:

```
~/.config/hiiro/
  plugins/        # Plugin files (auto-loaded)
  pins/           # Pin storage (per command)
  tasks/          # Task metadata
  projects.yml    # Project aliases
  apps.yml        # App directory mappings
  todo.yml        # Todo items
```

## Testing

Run the test suite:

```sh
bundle exec rake test
```

## License

MIT
