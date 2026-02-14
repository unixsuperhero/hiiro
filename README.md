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
- Subcommands (`h-video`, `h-buffer`, etc.) to `~/bin/`

Ensure `~/bin` is in your `$PATH`.


### Dependencies

```sh
# For notify plugin (macOS)
brew install terminal-notifier

# For fuzzy-finder
brew install sk # (or fzf)
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
| `h path` | Print the current directory |
| `h ppath` | Print project path (git root + relative dir) |
| `h rpath` | Print relative path from git root |
| `h pin` | Per-command key-value storage (via Pins plugin) |
| `h project` | Project navigation with tmux integration (via Project plugin) |
| `h task` | Task management across git worktrees (via Task plugin) |
| `h notify` | macOS desktop notifications via terminal-notifier (via Notify plugin) |

### External Subcommands

| Command | Description |
|---------|-------------|
| `h branch` | Record and manage git branch history for tasks |
| `h buffer` | Tmux paste buffer management |
| `h dot` | Compare directories and generate symlink/diff commands |
| `h dotfiles` | Manage dotfiles in ~/proj/home |
| `h home` | Manage home directory files with edit and search |
| `h html` | Generate an HTML index of MP4 videos in current directory |
| `h link` | Manage saved links with URL, description, and shorthand |
| `h mic` | Control macOS microphone input volume |
| `h note` | Create, edit, list, and display notes |
| `h pane` | Tmux pane management |
| `h plugin` | Manage hiiro plugins (list, edit, search) |
| `h pr` | Record PR information linked to tasks |
| `h pr-monitor` | Monitor pull requests |
| `h pr-watch` | Watch pull requests for updates |
| `h project` | Open projects with tmux session management |
| `h runtask` | Run templated task scripts |
| `h serve` | Start a miniserve HTTP server on port 1111 |
| `h session` | Tmux session management |
| `h sha` | Extract short SHA from git log |
| `h subtask` | Shorthand for task subtask management |
| `h task` | Comprehensive task manager for git worktrees |
| `h video` | Video inspection and operations via ffprobe/ffmpeg |
| `h vim` | Manage nvim configuration with edit and search |
| `h window` | Tmux window management |
| `h wtree` | Git worktree management |

## Abbreviations

Any subcommand can be abbreviated as long as the prefix uniquely matches:

```sh
h ex hel    # matches h example hello
h te        # matches h test (if unique)
h pp        # matches h ppath
```

If multiple commands match, the first match wins and a warning is logged (when logging is enabled).

## Plugins

Plugins are Ruby modules loaded from `~/.config/hiiro/plugins/`:

| Plugin | Description |
|--------|-------------|
| Pins | Per-command YAML key-value storage |
| Project | Project directory navigation with tmux session management |
| Task | Task lifecycle management across git worktrees with subtask support |
| Tmux | Tmux session helpers used by Project and Task |
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
hiiro = Hiiro.init(*ARGV, plugins: [Pins, Project, Task], cwd: Dir.pwd)

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
