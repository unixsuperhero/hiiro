# Hiiro

A lightweight, extensible CLI framework for Ruby. Build your own multi-command tools similar to `git` or `docker`.

## Features

- **Subcommand dispatch** - Route commands to executables or Ruby blocks
- **Abbreviation matching** - Type `h ex hel` instead of `h example hello`
- **Plugin system** - Extend functionality with reusable modules
- **Per-command storage** - Each command gets its own pin/config namespace

## Installation

```sh
# Copy the main script
cp bin/h ~/bin/h
chmod +x ~/bin/h

# Copy plugins (optional)
mkdir -p ~/.config/hiiro/plugins
cp plugins/*.rb ~/.config/hiiro/plugins/
```

Ensure `~/bin` is in your `$PATH`.

### Dependencies

```sh
gem install pry
# For notify plugin (macOS)
brew install terminal-notifier
```

## Quick Start

```sh
# List available subcommands
h

# Built-in test command
h test
# => test successful

# Edit the main h script
h edit

# Get paths
h path      # Print current directory
h ppath     # Print project root (git repo root + relative dir)
h rpath     # Print relative directory from git root
```

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

load File.join(Dir.home, 'bin/h')

Hiiro.init(*ARGV) do |hiiro|
  hiiro.add_subcommand(:hello) { puts "Hi!" }
  hiiro.add_subcommand(:bye)   { puts "Goodbye!" }
end.run
```

```sh
h example hello  # => Hi!
h example bye    # => Goodbye!
```

### Method 2: Inline Subcommands

Modify `bin/h` directly to add subcommands to the base `h` command:

```ruby
hiiro = Hiiro.init(*ARGV, plugins: [Tmux, Pins, Project, Task], cwd: Dir.pwd)

hiiro.add_subcommand(:hello) do |*args|
  puts "Hello, #{args.first || 'World'}!"
end

hiiro.run
```

Global values (like `cwd`) are passed to all subcommand handlers via keyword arguments:

```ruby
hiiro.add_subcommand(:pwd) do |*args, **values|
  puts values[:cwd]  # Access the cwd passed during init
end
```

## Abbreviations

Any subcommand can be abbreviated as long as the prefix uniquely matches:

```sh
h ex hel    # matches h example hello
h te        # matches h test (if unique)
h pp        # matches h ppath
```

If multiple commands match, the first match wins and a warning is logged (when logging is enabled).

## Built-in Plugins

### Pins

Key-value storage persisted per command:

```sh
h pin                     # List all pins
h pin mykey               # Get value
h pin mykey myvalue       # Set value
h pin set mykey myvalue   # Set value (explicit)
h pin rm mykey            # Remove pin
```

Pins are stored in `~/.config/hiiro/pins/<command>.yml`.

### Tmux

Session management:

```sh
h session myproject       # Create/attach to tmux session
```

### Project

Quick project navigation with tmux integration:

```sh
h project myproj          # cd to ~/proj/myproj and start tmux session
```

Projects can be configured in `~/.config/hiiro/projects.yml`:

```yaml
myproject: /path/to/project
work: ~/work/main
```

### Task

Manage development tasks across git worktrees in `~/work/`:

```sh
h task list               # Show trees and their active tasks
h task start TICKET-123   # Start working on a task
h task status             # Show current task info
h task app frontend       # Open app directory in new tmux window
h task save               # Save current tmux window state
h task stop               # Release tree for other tasks
```

Configure apps in `~/.config/hiiro/apps.yml`:

```yaml
frontend: apps/frontend
api: services/api
admin: admin_portal/admin
```

### Notify (macOS)

Desktop notifications via `terminal-notifier`:

```sh
h notify "Build complete"
h notify "Click me" "https://example.com"
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
Hiiro.init(*ARGV, plugins: [MyPlugin]) do |hiiro|
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
```

## License

MIT
