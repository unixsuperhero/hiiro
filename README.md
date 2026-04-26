# Hiiro

A lightweight, extensible CLI framework for Ruby. Build your own multi-command tools similar to `git` or `docker`.

## Features

- **Subcommand dispatch** - Route commands to executables or Ruby blocks
- **Abbreviation matching** - Type `h ex hel` instead of `h example hello`
- **Plugin system** - Extend functionality with reusable modules
- **Per-command storage** - Each command gets its own pin/config namespace
- **TUI helpers** - Build keyboard-driven list screens with `Hiiro::Tui::ListScreen`

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
| `h queue` | Claude prompt queue with tmux-based task execution |
| `h jumplist` | Vim-style tmux navigation history (back/forward through panes) |
| `h service` | Manage background dev services with env variations and groups |
| `h file` | Track and open frequently-used files per app |
| `h run` | Run dev tools (lint/test/format) against changed files |
| `h session` | Tmux session management |
| `h sha` | Extract short SHA from git log |
| `h todo` | Todo list management with tags and task association |
| `h window` | Tmux window management |
| `h wtree` | Git worktree management |

`h claude agents|commands|skills -a` prints the absolute file path for each matching `.claude` tool, including `SKILL.md` for skills.

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

### Building TUIs

Use `Hiiro::Tui::ListScreen` for simple full-screen list interfaces. Subclass it, override `header_lines`, `format_row`, and `handle_key`, then run it from a normal `Hiiro.run` subcommand.

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
  queue/          # Prompt queue (wip, pending, running, done, failed)
  services/       # Service runtime state
  jumplist/       # Per-client tmux navigation history
  env_templates/  # Base .env templates for services
  tasks/          # Task metadata
  projects.yml    # Project aliases
  apps.yml        # App directory mappings
  services.yml    # Service and service group definitions
  tools.yml       # Runner tool definitions
  app_files.yml   # Per-app tracked file lists
  todo.yml        # Todo items
```

## Testing

Run the test suite:

```sh
bundle exec rake test
```

## License

MIT


# COMPLEX SERVICES

```sh

❯ in this setup...can you configure a couple complex services that use variations, etc.  i need examples of how to configure it. and then can you show me how to run it for different variations

⏺ Here's an example ~/.config/hiiro/services.yml:

  # Individual services
  api-rails:
    base_dir: ~/work/api
    host: localhost
    port: 3000
    init:
      - bundle install
    start:
      - bin/rails s -p 3000
    cleanup: []
    env_file: .env.development
    base_env: api-rails.env
    env_vars:
      DATABASE_URL:
        variations:
          local: postgres://localhost:5432/api_dev
          docker: postgres://db:5432/api_dev
      REDIS_URL:
        variations:
          local: redis://localhost:6379
          docker: redis://redis:6379

  graphql:
    base_dir: ~/work/graphql
    host: localhost
    port: 4000
    init:
      - npm install
    start:
      - npm run dev
    env_file: .env.local
    base_env: graphql.env
    env_vars:
      API_URL:
        variations:
          local: http://localhost:3000
          staging: https://api.staging.example.com
      AUTH_PROVIDER:
        variations:
          local: http://localhost:8080/auth
          staging: https://auth.staging.example.com

  frontend:
    base_dir: ~/work/frontend
    host: localhost
    port: 8080
    start:
      - npm run dev
    env_file: .env.local
    base_env: frontend.env
    env_vars:
      GRAPHQL_URL:
        variations:
          local: http://localhost:4000/graphql
          staging: https://graphql.staging.example.com/graphql

  # Service groups
  full-stack:
    services:
      - name: api-rails
        use:
          DATABASE_URL: local
          REDIS_URL: local
      - name: graphql
        use:
          API_URL: local
          AUTH_PROVIDER: local
      - name: frontend
        use:
          GRAPHQL_URL: local

  staging-fe:
    services:
      - name: graphql
        use:
          API_URL: staging
          AUTH_PROVIDER: staging
      - name: frontend
        use:
          GRAPHQL_URL: local

  Usage:

  # Start a single service (defaults to "local" variations)
  h service start api-rails

  # Start with specific variations
  h service start api-rails --use DATABASE_URL=docker --use REDIS_URL=docker

  # Start the full local stack (one window, 3 split panes)
  h service start full-stack

  # Start frontend pointing at staging backends
  h service start staging-fe

  # No args — fuzzy select from all services + groups
  h service start

  The key ideas:
  - local is the default variation — if you don't pass --use, each env var gets its local value
  - Groups let you pre-bake variation combos — full-stack vs staging-fe are just different use: presets for the same services
  - Base env templates live in ~/.config/hiiro/env_templates/ (e.g., api-rails.env) — they get copied to base_dir/env_file first, then variations are injected on top


```

# Development

Testing locally:

```sh
ruby -I lib bin/h-ps search ruby
```
