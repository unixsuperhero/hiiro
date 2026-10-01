## Project Overview

Hiiro is a lightweight CLI framework for Ruby that enables building multi-command tools similar to `git` or `docker`. It provides subcommand dispatch, abbreviation matching (e.g., `h ex hel` matches `h example hello`), and a plugin system.

## Development Commands

```bash
# Edit the main h script
h edit

# List available subcommands
h

# Syntax check Ruby files
ruby -c bin/h
ruby -c plugins/*.rb
```


Tests are organized under `test/`:
- `test/hiiro/` - Core library tests (Matcher, Options, Shell, Fuzzyfind, Todo, etc.)
- `test/plugins/` - Plugin tests (Pins, Tasks, Notify, Project)
- `test/bin/` - Bin file tests using `Hiiro::TestHarness`

The `Hiiro::TestHarness` class (in `test/test_helper.rb`) enables testing bin files by capturing the block passed to `Hiiro.run` and evaluating it in a test context with stubbed `system` calls.

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
- `fuzzyfind_from_map(hash)` - Interactive selection returning mapped value
- `pins` - Key-value storage per command
- `todo_manager` - Todo item management
- `attach_method(name, &block)` - Add methods to hiiro instance dynamically
- `make_child(subcmd, *args)` - Create nested Hiiro for sub-subcommands (returns instance, must call `.run` manually)
- `run_child(subcmd, *args)` - Create a nested Hiiro instance AND immediately run it (preferred over `make_child(...).run`)

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

`Result` and `PathResult` share their cardinality/resolution answers through `Hiiro::Matcher::ResultQueries` (`count`, `one?`, `ambiguous?`, `match?`, `exact_match`, `exact?`, `match`, `resolved`, `first`); both expose the original query as `query`.

Note: `Hiiro::PrefixMatcher` is aliased to `Hiiro::Matcher` for backward compatibility.

### Hiiro::Git (lib/hiiro/git.rb)

Git operations wrapper with submodules for branches, worktrees, remotes, and PRs:

```ruby
git = hiiro.git
git.root                          # Repository root path
git.branch                        # Current branch name
git.branches                      # List all branches
git.worktrees                     # List all worktrees (Git::Worktree: path, head, branch, bare?, detached?, name, to_line)
Hiiro::Git::Worktrees.fetch       # Porcelain-backed collection; bins should use this instead of splitting `git worktree list`
git.add_worktree(path, branch:)   # Create worktree
git.move_worktree(from, to)       # Rename worktree
git.current_pr                    # Get current PR info
```

### Hiiro::DB (lib/hiiro/db.rb)

SQLite persistence layer backed by Sequel. All data is stored in `~/.config/hiiro/hiiro.db`.

**Setup:** `Hiiro::DB.setup!` is called at startup — creates any missing tables, then runs a one-time YAML→SQLite migration if the DB is new.

**Model registration:** Each Sequel model calls `Hiiro::DB.register(self)` so `setup!` can create its table:

```ruby
class Hiiro::MyModel < Sequel::Model(:my_table)
  Hiiro::DB.register(self)

  def self.create_table!(db)
    db.create_table?(:my_table) do
      primary_key :id
      String :name, null: false
    end
  end
end
```

**Dual-write:** During rollout, models write to both SQLite and YAML. Once migration is stable, call `Hiiro::DB.disable_dual_write!` to stop YAML writes.

**Test isolation:** Set `ENV['HIIRO_TEST_DB'] = 'sqlite::memory:'` before requiring `hiiro` to get a clean in-memory DB per test run. Call `Hiiro::DB.setup!` after require.

**`h db` subcommand:** Inspect and manage the database:
- `h db status` — show connection info and migration state
- `h db tables` — list all tables with row counts
- `h db q <sql>` — run raw SQL and print results
- `h db migrate` — re-run YAML import (if not yet migrated)
- `h db restore` — restore YAML files from SQLite data

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

### Invocation Tracking (lib/hiiro/invocation.rb)

Every CLI invocation is automatically recorded to SQLite via `Hiiro::Invocation` and `Hiiro::InvocationResolution`. This happens in `Hiiro.init` — no extra setup needed.

**Schema:**
- `Hiiro::Invocation` — records `bin_name`, `argv_json`, `cwd`, `invoked_at`
- `Hiiro::InvocationResolution` — linked to an invocation; records `resolved_name`, `resolution_type` (exact/prefix/abbreviated), `subcmd`

**Query recent invocations:**
```ruby
Hiiro::Invocation.order(Sequel.desc(:invoked_at)).limit(20).each do |inv|
  puts "#{inv.invoked_at}  #{inv.bin_name} #{JSON.parse(inv.argv_json).join(' ')}"
end
```

Or via `h db q`:
```bash
h db q "SELECT bin_name, argv_json, invoked_at FROM invocations ORDER BY invoked_at DESC LIMIT 10"
```

### Hiiro::InputFile / Hiiro::EditedDocument (lib/hiiro/input_file.rb)

Tempfile + editor lifecycle for YAML/markdown input. After `edit`, the result is retained as an `EditedDocument`:

```ruby
input = yaml_input_file(content: yaml, prefix: 'todo-edit-')   # or InputFile.yaml_file(hiiro:, ...) / .md_file
doc   = input.edit.document        # EditedDocument: original, result (alias contents), parsed (alias data), error
doc.changed? / doc.empty? / doc.valid?
input.parsed_file                  # still available; nil on YAML parse error
input.cleanup                      # unlink the tempfile when done
```

Use this instead of a hand-rolled Tempfile/system/YAML.load/unlink cycle (TodoManager#edit_items now does).

### Hiiro::CheckSummary / Hiiro::CheckContext (lib/hiiro/check_summary.rb)

One interpretation of a PR's `statusCheckRollup`, shared by `Git::Pr`, `PinnedPr`, `PinnedPRManager` display, `CheckRun` persistence, and `h pr status`:

```ruby
s = Hiiro::CheckSummary.from_rollup(rollup, truncated: false)   # nil when rollup nil/empty
s = pr.check_summary                                             # from stored counts (+ raw contexts when present)
s.total / s.success / s.pending / s.failed / s.frozen / s.complete?
s.red? / s.green? / s.pending?        # the -r / -g / -p filter predicates (pr.red? etc. delegate here)
s.any_pending? / s.only_frozen?       # display distinctions
s.counts_by_outcome                   # { 'SUCCESS' => 12, 'FAILURE' => 1 } (missing keys read 0)
s.contexts.each { |c| c.kind (:check_run|:status_context) ; c.name ; c.url ; c.outcome ; c.raw }
s.to_h                                # the stored { 'total','success','pending','failed','frozen'[,'truncated'] } hash
```

### Hiiro::PullRequestReference / Hiiro::RepositoryIdentity (lib/hiiro/pull_request_reference.rb)

```ruby
ref = Hiiro::PullRequestReference.parse(input)   # URL | '#123' | '123' | 123 → ref, else nil
ref.number / ref.number_string / ref.repo        # repo: RepositoryIdentity or nil for a bare number
ref.key            # [number, 'owner/name'] — the key PinnedPRManager batches by
ref.repo_args      # ['-R', 'owner/name'] or []
ref.matches?(pr)   # same number; same repo when both sides know it
pr.reference       # Git::Pr / PinnedPr → reference
Hiiro::PinnedPr.find_by_reference(ref)           # repo-qualified lookup; legacy rows without repo still match
Hiiro::RepositoryIdentity.parse('owner/name' | github URL)  # .host .owner .name .path .url
```

### Hiiro::Git::BranchComparison (lib/hiiro/git/branch_comparison.rb)

Two refs plus an explicit base policy. Used by `h branch diff/changed/ahead/behind/log/forkpoint/ancestor`:

```ruby
cmp = git.compare(source: 'HEAD', target: nil, base_policy: :local_main, fallback: 'HEAD~1')
# base_policy :local_main → main, master ; :remote_first → origin/master, master, origin/main, main
cmp.target / cmp.target_source (:explicit|:policy|:fallback|:none) / cmp.resolved?
cmp.ahead / cmp.behind / cmp.ancestor? / cmp.merge_base / cmp.fork_point (--fork-point, then merge-base)
cmp.two_dot_range / cmp.three_dot_range / cmp.fork_range / cmp.changed_paths(relative: true)
```

`Hiiro::Git` gained the underlying queries: `ref_exists?`, `rev_list_count`, `merge_base`, `ancestor?`, `changed_files`.

### Hiiro::TaskLocation (lib/hiiro/task_location.rb)

Where a task's directories are. `CurrentTask` and `TaskCli` delegate `code_directory`, `workspace_label`, `tree_path`, `start_directory`, and `app_directory` to it:

```ruby
loc = Hiiro::TaskLocation.for(task, override: opts[:directory], app: Hiiro::App.new(name:, path:))
loc.home             # TaskRecord.home_for(task.name); never creates it
loc.worktree_path    # task.tree, absolute or under WORK_DIR; nil without a tree
loc.code_directory   # task.primary_directory || worktree_path
loc.app_directory    # app.resolve(code_directory); nil unless both known
loc.start_directory  # override || app_directory || code_directory || home
loc.source           # :override | :app | :primary | :tree | :home  (callers run ensure_home only for :home)
loc.workspace_label  # (task.session || task.name).tr('.', '_')
Hiiro::TaskLocation.contains?(root, path)   # realpath containment
```

### Hiiro::Herdr::TabCreation / Hiiro::Herdr::Location (lib/hiiro/herdr.rb)

`tab create` responses are read through one value instead of `result.dig('tab','tab_id')` at every call site:

```ruby
created = Hiiro::Herdr::TabCreation.create(client, name:, workspace:, start_directory:, command:, focus:)  # or herdr.create_tab(**req)
created.tab_id / created.pane_id / created.tab / created.root_pane
created.created?   # tab id present          created.complete?  # tab + root pane present
created.errors     # [] | ['no tab'] | ['no root pane']
created.location(workspace_id: ws.id)       # Herdr::Location
loc = Hiiro::Herdr::Location.from_meta(meta)  # reads herdr_workspace / herdr_tab / herdr_pane
loc.target                                    # pane_id || tab_id || workspace_id
loc.to_meta                                   # inverse of from_meta (queue/service metadata)
```

### Hiiro::Link / Hiiro::URLTemplate (lib/hiiro/link.rb)

`bin/h-link` uses `Hiiro::Link` directly (its inline `LinkManager::Link` copy is gone). `Link.from_hash(yaml_row)` builds an unsaved instance; `to_h` / `to_yaml` give the links.yml shape.

```ruby
t = Hiiro::URLTemplate.new('https://x/{org}/{repo}', values: { 'org' => 'a b' })
t.placeholders     # ['org', 'repo']     t.placeholders?   # true
t.missing_values   # ['repo']            t.complete?       # false
t.url              # 'https://x/a+b/{repo}'  (spaces → '+', nothing else is encoded)
```

### Hiiro::PsProcess::Snapshot / OpenFiles (lib/hiiro/ps_process.rb)

```ruby
snap = Hiiro::PsProcess::Snapshot.capture      # one `ps awwux`; .processes .captured_at
snap.by_pid(pid) / snap.with_pids(set) / snap.matching(pattern) / snap.parent_of(pid) / snap.children_of(pid)
of = Hiiro::PsProcess::OpenFiles.for_pid(pid)  # one lsof; also .for_port(port), .in_dir(path), for_pid(pid, network_only: true)
of.pids / of.cwd / of.files / of.sockets / of.failed   # failed = lsof exited non-zero (not the same as empty)
```

`PsProcess.by_port`, `.in_dirs`, `#files`, `#ports`, `#dir`, `#parent`, `#children` keep their shapes and read through these.

### Hiiro::Duration / Hiiro::TimeInput (lib/hiiro/duration.rb, lib/hiiro/time_input.rb)

Value objects behind `h date`, `h time`, and `h remind` (formerly duplicated helpers in each bin):

```ruby
Hiiro::Duration.parse('15m')            # => Duration(900s); nil when not <digits><s|m|h|d|w>
Hiiro::Duration.seconds(90_061).compact # => "1d1h1m1s"   (.clock => "25:01:01", .components => {days:,hours:,...})
Hiiro::Duration.milliseconds(1500)      # Rational-precise seconds

t = Hiiro::TimeInput.parse('1726000000123')   # digits → unix; ms auto-detected past 11 digits (or ms: true)
t.unit / t.time / t.unix_seconds / t.unix_milliseconds / t.utc / t.iso8601(3)
Hiiro::TimeInput.parse('now') ; Hiiro::TimeInput.parse('2026-09-22 10:00')   # 'now'/blank → now ; else Time.parse
a.difference(b)                          # => Duration
```

### Hiiro::Shell (lib/hiiro/shell.rb)

Utility for piping content to external commands:

```ruby
Hiiro::Shell.pipe("content", "pbcopy")           # Pipe string to command
Hiiro::Shell.pipe_lines(["a", "b"], "command")   # Join array with newlines and pipe
result = Hiiro::Shell.run('cmd', 'arg', SOME_ENV: 'x')   # Result: stdout, stderr, status, success?, lines, plain_text
result.spec      # Hiiro::CommandSpecification — argv, env (normalized to strings), cwd, preview, open3_args
result.command   # spec.preview, e.g. "cmd arg"
content = Hiiro::Shell.read_input(*args)          # files named in args ('-' = stdin), else piped stdin
```

`read_input` keeps only args that are readable paths (regular files, `/dev/fd/N`, `<(cmd)`) or `-`, concatenates them, and falls back to stdin when none remain. A named file wins over piped stdin unless `-` places it. At a terminal with no input it aborts with `no input: pipe data in or pass a file`.

`run`, `run_combined`, `run3`, `stream`, and `stream_combined` all build one `CommandSpecification` and attach it to the `Result`.

### Hiiro::Options (lib/hiiro/options.rb)

Argument parsing with flag and option support:

```ruby
opts = Hiiro::Options.parse(args) do
  option(:output, short: :o, desc: "Output file")
  option(:verbose, short: :v, type: :flag, desc: "Verbose output")
end
opts.output    # Value of --output or -o
opts.verbose   # true if --verbose or -v was passed
opts.args      # Remaining non-option arguments
```

The declared options live in a `Hiiro::OptionSet` (`options.option_set`), which both `Options` and the parsed `Args` use for `help_text`, `hint`, `definition_for('--out' | '-o' | :out)`, `defaults`, `subset(names)`, and `conflicts_for(name)` (mutual-exclusion star topology).

### Hiiro::Notification (lib/hiiro/notification.rb)

macOS notification wrapper using terminal-notifier:

```ruby
Hiiro::Notification.show(hiiro)   # Show notification based on hiiro.args
# Supports: -m message, -t title, -l link, -c command, -s sound (macOS system sound name via terminal-notifier -sound; none for silent)
```

### Hiiro::Queue (lib/hiiro/queue.rb)

Task queue that pipes prompts to `claude` via tmux. Tasks are markdown files with optional YAML frontmatter (`task_name`, `tree_name`, `session_name`) that flow through statuses: `wip` -> `pending` -> `running` -> `done`/`failed`.

Subcommands (`h queue <subcmd>`):
- `ls`/`list` - List all tasks with status, elapsed time, and preview
- `status` - Detailed status with working directory info
- `add` - Create a new prompt (opens editor or accepts stdin/args, supports `-t <task>` flag)
- `wip` - Create/edit a work-in-progress prompt
- `ready` - Move wip task to pending
- `run [name]` - Launch pending task(s) in tmux windows
- `watch` - Continuously poll and launch pending tasks
- `attach [name]` - Switch to running task's tmux window (fuzzy select if no name)
- `kill [name]` - Kill running task's tmux window, move to failed
- `retry [name]` - Move failed/done task back to pending
- `clean` - Remove all done/failed task files
- `dir` - Print queue directory path

Config: `~/.config/hiiro/queue/{wip,pending,running,done,failed}/`

Key internals:
- `Queue::Entry` - `Entry.find(dirs, name)` / `Entry.in(dirs, status)`; answers `prompt_path`, `meta_path`, `launcher_path`, `body_path`, `companion_files`, `modified_at`, `meta`, `preview`, `prompt`, `execution`, `moved_to(status)`, `to_h` ({ name:, status: }). `Queue#entry_for(name, status)` builds one; `tasks_in`, `all_tasks`, `meta_for`, `task_preview`, `find_task` are thin wrappers over it.
- `Queue::Execution` - snapshot of a running entry's `.meta`: `started_at`, `elapsed` (Duration), `elapsed_minutes`, `working_directory`, `location` (Herdr::Location), `attach_target`
- `Queue::Prompt` - Parses frontmatter to resolve task/tree/session for working directory; retains `path`; `body` strips frontmatter; `Prompt.frontmatter_lines(task_info:, ignore:, hints:)` is the editor template shared by add/wip
- Tasks launch in tmux windows within the task's session (from frontmatter) or default `hq` session
- Launcher script runs `cat prompt | claude`, then moves files to done/failed based on exit code

### Hiiro::ServiceManager (lib/hiiro/service_manager.rb)

Manages background development services with tmux integration, env file management, and service groups.

Subcommands (`h service <subcmd>`):
- `ls`/`list` - List all services with running status, port, and base_dir
- `start <name> [--use VAR=variation ...]` - Start a service or group; prepares env file first
- `stop <name>` - Stop a running service (sends C-c to tmux pane or runs stop command)
- `attach <name>` - Switch to service's tmux pane
- `open <name>` - Open service URL in browser
- `url <name>` / `port <name>` - Print service URL or port
- `status <name>` - Show detailed service info (pid, pane, task, started_at)
- `add` - Add new service via editor template
- `rm`/`remove <name>` - Remove a service
- `config` - Edit services.yml
- `groups` - List all service groups and their members
- `env <name>` - Show env_vars, their variation options, and base_env/env_file config

Service config (`~/.config/hiiro/services.yml`):
```yaml
my-rails:
  base_dir: apps/myapp
  host: localhost
  port: 3000
  init: ["bundle install"]
  start: bundle exec rails s -p 3000
  stop: ""
  cleanup: []
  env_file: .env.development          # destination in base_dir
  base_env: my-rails.env              # template in ~/.config/hiiro/env_templates/
  env_vars:
    GRAPHQL_URL:
      variations:
        local: http://localhost:4000/graphql
        staging: https://graphql.staging.example.com/graphql
```

Service group config (same file, distinguished by `services:` key):
```yaml
my-stack:
  services:
    - name: my-rails
      use:
        GRAPHQL_URL: staging
    - name: my-graphql
```

Key internals:
- `Hiiro::ServiceDefinition` (lib/hiiro/service_definition.rb) - `sm.definition_for(name)`; answers `base_directory`, `host`, `port`, `url`, `init_commands`, `start_command`, `stop_command`, `cleanup_commands`, `environment_files`
- `Hiiro::EnvironmentFile` - one env file of a service: `template_path`, `destination_path`, `variables` ({ VAR => { variation => value } }), `selected_variation(var, overrides)` (default `local`), `effective_values(overrides)`, `desired_content(existing_lines, overrides)`. `h service env` displays it and `prepare_env` writes it; both read the same object.
- `Hiiro::ServiceGroup` - `sm.group_definition_for(name)` / `ServiceGroup.from_config(name, cfg)`; `service_names`, `overrides_for(service_name)`
- `prepare_env(svc_name, variation_overrides:)` - Copies base_env template from `~/.config/hiiro/env_templates/` to `base_dir/env_file`, then injects variation values
- `find_group(name)` / `start_group(name, ...)` - Detect and start service groups, applying per-member `use:` overrides
- Default variation is `local` when not specified
- State tracked in `~/.config/hiiro/services/running.yml`

### Hiiro::RunnerTool (lib/hiiro/runner_tool.rb)

Run dev tools (linters, formatters, test suites) against changed files.

Subcommands (`h run [change_set] [tool_type] [file_group]`):
- Default (no subcmd) - Run matching tools with positional filters
- `ls` - List configured tools with type, group, extensions, and variations
- `add` - Add new tool via editor template
- `rm <name>` - Remove a tool
- `config` - Edit tools.yml

Arguments (positional, any order):
- **change_set**: `dirty` (default, git status), `branch` (diff from main), `all`
- **tool_type**: `lint`, `test`, `format`
- **file_type_group**: custom group identifier (e.g., `ruby`, `frontend`)
- `--variation`/`-v <name>` - Use a named tool variation

Config (`~/.config/hiiro/tools.yml`):
```yaml
rubocop:
  tool_type: lint
  command: "rubocop [FILENAMES]"
  file_type_group: ruby
  file_extensions: "rb"
  variations:
    quick: "rubocop --only Style [FILENAMES]"
    fix: "rubocop -A [FILENAMES]"
```

`[FILENAMES]` is replaced with the space-joined list of matching files.

### Hiiro::AppFiles (lib/hiiro/app_files.rb)

Track frequently-used files per application, open them together in your editor.

Subcommands (`h file <subcmd>`):
- `ls [app_name]` - List tracked files (all apps or specific app)
- `add <app> <file1> [file2 ...]` - Add files to an app's file list
- `rm <app> <file1> [file2 ...]` - Remove files
- `edit <app>` - Open all tracked files in editor (vim uses `-O` for vertical splits)

Config: `~/.config/hiiro/app_files.yml`

Files are resolved relative to the current task's tree root when an environment is available.

### Jumplist (bin/h-jumplist)

Vim-style navigation history for tmux. Records pane/window/session changes and lets you jump backward/forward through your navigation history.

Subcommands (`h jumplist <subcmd>`):
- `setup` - Install tmux hooks and keybindings (`Ctrl-B` back, `Ctrl-F` forward)
- `record` - Record current position (called automatically by tmux hooks)
- `back` - Navigate to previous position
- `forward` - Navigate to next position
- `ls`/`list` - Show history with timestamps and current position marker
- `clear` - Clear history
- `path` - Print jumplist file path

Config: `~/.config/hiiro/jumplist/` (per-client entries and position files, max 50 entries)

Dead panes are automatically pruned. Duplicate consecutive entries are deduplicated. Forward history is truncated when navigating to a new location (like vim).

### Using `run_child`

`run_child` is the instance-level equivalent of `Hiiro.run` — it creates a child Hiiro instance scoped to a subcommand and immediately dispatches it. Use it instead of `make_child(...).run`:

```ruby
# Inside a subcommand handler or plugin:
hiiro.add_subcmd(:service) do |*args|
  sm = ServiceManager.new
  hiiro.run_child(:service) do |h|
    h.add_subcmd(:list) { sm.list }
    h.add_subcmd(:start) { |name| sm.start(name) }
  end
end
```

This is equivalent to `hiiro.make_child(:service) { ... }.run`, but cleaner and mirrors the `Hiiro.run` / `Hiiro.init` relationship.

## Coding Rules and Conventions

### `Hiiro.run` vs `h = Hiiro.init` then `h.run`

If the code sets up new classes to be used within the Hiiro set of subcommands
or options/flags, inside the bin that calls them, then use the `init` version.

Structure it like this:

```ruby
h = Hiiro.init(*ARGV) do
  # ...
end

# setup classes here

h.run
```
If the bin uses classes that are already defined, then use `Hiiro.run`

### Keep docs current

ALWAYS update `README.md` and any files in `docs/` or other markdown files that describe how to use hiiro, its bins, or how it works whenever you change behavior. Never let these go stale.

## Key Files

- `exe/h` - Entry point that loads lib/hiiro.rb
- `exe/t`, `exe/tt` - Task CLI launchers over `Hiiro::TaskCli` (`lib/hiiro/task_cli.rb`)
- `bin/h-*` - External subcommands (tmux wrappers, git helpers, jumplist, etc.)
- `lib/hiiro.rb` - Main Hiiro class and Runners
- `lib/hiiro/*.rb` - Supporting classes (Git, Matcher, Fuzzyfind, Todo, Shell, Options, Notification, Tmux, Queue, ServiceManager, RunnerTool, AppFiles)

### not used anymore
- `plugins/*.rb` - Reusable plugin modules (Pins, Project, Tasks, Notify)

## External Dependencies

- Ruby with `pry` gem
- `tmux` for session/window/pane management
- `sk` (skim) or `fzf` for fuzzy finding
- `gh` CLI for GitHub operations (h-pr)
- `terminal-notifier` for macOS notifications (notify plugin)
- `claude` CLI for queue task execution

## Configuration Locations

All config lives in `~/.config/hiiro/`:
- `plugins/` - Auto-loaded plugin files
- `pins/` - Per-command YAML key-value storage
- `tasks/` - Task metadata for worktree management
- `queue/` - Prompt queue (wip, pending, running, done, failed)
- `services/` - Service runtime state
- `jumplist/` - Per-client tmux navigation history
- `env_templates/` - Base .env template files for services
- `projects.yml` - Project directory aliases
- `apps.yml` - App directory mappings for task plugin
- `services.yml` - Service and service group definitions
- `tools.yml` - Runner tool definitions
- `app_files.yml` - Per-app tracked file lists


# Groups of files

## tmux-related files

- bin/h-buffer
- bin/h-pane
- bin/h-window
- bin/h-session
- lib/hiiro/tmux.rb
- lib/hiiro/tmux/*

