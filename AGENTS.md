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


## Making Changes

Hiiro is extensible, and when working on a bin or subcommand, there could be
multiple variations of a bun and which one the user assumes is latest might not
be accurate.  The common places for these bins are:

- ~/bin/
- ~/proj/phome/bin/
- ~/proj/hiiro/bin/
- any version of the gem installed via rbenv

## Architecture

### Core Components (bin/h)

The `Hiiro` class is the main entry point with these nested classes:

- **`Runners`** - Holds inline registrations (name, aliases, handler, args/opts metadata) and resolves the first argument through `Hiiro::Catalog`.
- **`Runners::Bin`** - An external executable candidate found in PATH
- **`Runners::Subcommand`** - An inline subcommand registered via `add_subcmd` / `add_cmd`; extra names are aliases
- **`Catalog`** (lib/hiiro/catalog.rb) - The one command table used by dispatch, help, `edit`, `h bin list/edit/complete/docs`
- **`Runtime`** (lib/hiiro/runtime.rb) - Starts persistence, invocation history, and task auto-tagging on first persistent use
- **`Args`** - Parses single-dash flags (`-abc` becomes flags `a`, `b`, `c`)
- **`Config`** - Manages `~/.config/hiiro/` directory structure

### Subcommand Resolution Flow

1. `Hiiro.init()` parses first arg as subcommand name and registers commands; it opens nothing.
2. `Hiiro::Catalog` builds entries from inline registrations plus eligible `BIN-*` executables (regular executable files or links to them, PATH order, read at lookup time).
3. Token ownership: external executable > inline name > inline alias. Losing claims stay visible as `shadowed`; same-name PATH copies are never ambiguous.
4. Exact token wins; otherwise a unique prefix (a child `pr-monitor` yields to its parent `pr`). Ambiguous or missing names show help and launch nothing.

```js
const entry = { name: "service", kind: "inline", source: "lib/hiiro/root_commands.rb:171",
  aliases: ["svc"], arguments: "[*svc_args]", shadowed: [] };
const external = { name: "pr", kind: "external", source: "/home/me/bin/h-pr", aliases: [],
  shadowed: [{ name: "pr", kind: "external", source: "/home/me/proj/hiiro/bin/h-pr" }] };
const resolution = { query: "s", status: "ambiguous", candidates: ["save", "service", "session"] };
```

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

Plugins load only when a command names them: `Hiiro.run(*ARGV, plugins: [:Pins])` requires `pins.rb` from `~/.config/hiiro/plugins/`, else from the gem's `plugins/`. Importing `hiiro` loads no plugin. Load order matters when plugins depend on each other (e.g., Task and Project depend on Tmux).

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

SQLite persistence uses Sequel at `~/.config/hiiro/hiiro.db`. Mutable domain records are database-owned; definitions, preferences, runtime state, and ordinary artifacts keep their existing file owners. The complete owner/table map is in [README persistence ownership](README.md#persistence-ownership).

`require 'hiiro'` loads only the framework; domain constants autoload, and `Hiiro::DB` or any model autoloads `hiiro/persistence`, which connects, defines every model, runs `Hiiro::DB.setup!` (create missing tables, model schema upgrades), and starts `Hiiro::Runtime`. Help, completion, and discovery never reach it. It does not import domain YAML. Legacy sources are explicit retained import inputs, never live fallbacks or dual-write destinations.

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

Domain operations mutate selected rows rather than saving a stale collection. Temporary YAML editor documents project database records; failed editors and conflicting changes do not apply partial batches.

`TaskRecord` owns task identity, tree/session/app/color fields, `status`, `next_action`, `waiting_on`, `primary_directory`, and created/updated/completed/archived timestamps. Its `metadata_json` retains additional task detail keys, including window metadata. `TaskResource` owns task-linked directory, issue, PR, and note references; note bodies remain ordinary files.

Pins use explicit JSON encoding with a format marker. New string pins remain strings even when their text resembles JSON. Preexisting unmarked pins retain their historical decoder until an explicit typed source resolves ambiguity. Reminders store `interval`, `once`, `trigger_at`, `last_triggered`, `enabled`, and `sound` in SQLite.

Tag identities remain namespace-specific. `Branch` and `Task` tags use names; `Link`, `TaskRecord`, `RegistryEntry`, and `PinnedPr` tags use model IDs.

**Test isolation:** Set `ENV['HIIRO_TEST_DB'] = 'sqlite::memory:'` before requiring `hiiro` for an in-memory DB. Call `Hiiro::DB.setup!` after require. Migration smoke fixtures use a disposable file-backed database and temporary HOME.

See [h-db](docs/h-db.md) for exact manifest, plan, import, export, restore, status, and query syntax.

### Hiiro::Table / Hiiro::TableScope / Hiiro::TableActions (lib/hiiro/table*.rb)

A **table** is one named key/value list, stored as `registry.resource_type`; an **entry** is one `RegistryEntry` row. `RegistryEntry` has a nullable `task_id` and `tags` / `tag(*names)` / `untag(*names)` through `Hiiro::Tag` (taggable_type `RegistryEntry`).

```ruby
Hiiro::Table.all                       # every table, sorted by name
t = Hiiro::Table.named('link')         # exists? is false until a row is added
t.add('gh', value: 'https://github.com', short: 'g', desc: '', meta: {}, task_id: nil)
t.entries(scope: Hiiro::TableScope.global)   # rows ordered by name; count(scope:) ; find(ref)
t.rename('links')                      # moves every row; raises Hiiro::Error if the target exists

scope = Hiiro::TableScope.current      # task scope when CurrentTask resolves one, else global
scope.task? / scope.global? / scope.label   # "task(@NAME)" | "global"
scope.toggle                           # task -> global keeps the task; global -> task re-uses or resolves it
scope.apply(dataset)                   # the only place that knows task scope means where(task_id:)

acts = Hiiro::TableActions.load        # ~/.config/hiiro/tables.yml: { 'link' => { 'c' => 'cd {value}' } }
acts.for(entry)                        # DEFAULTS (o open, y pbcopy) merged with the table's letters
acts.command('o', entry)               # {value} {name} {table} shell-escaped; nil when no action
acts.run('o', entry)                   # system('/bin/sh', '-c', cmd); returns cmd
```

### Hiiro::Tui (lib/hiiro/tui.rb)

Screen toolkit for in-process TUIs. One engine for every hiiro TUI; do not add curses or shell out to a fuzzy finder for a screen (see `docs/plans/hiiro-tui.md`).

```ruby
class MyScreen < Hiiro::Tui::Screen
  key 'o', :open_item                 # key map is a table; subclasses add or override bindings
  def header_lines = ["title  #{state.query}"]
  def detail_lines(item) = ["name  #{item.name}"]   # nil (default) means no detail pane
  def pick_candidates = %w[link sound]              # '@' opens a prefix-filtered picker in the status line
  def picked(candidate) = (self.message = candidate)
  def open_item = (self.message = "open #{current_item}")
end
MyScreen.new(items: rows).run        # j/k/h/l move, '/' searches, '@' picks, q/Esc/Ctrl-C quit
```

- `state` is one `Tui::State` (`mode` :list|:search|:pick, `cursor`, `top`, `horizontal_offset`, `query`, `pick_query`, `message`). Read it; never keep a parallel boolean.
- `frame(rows:, cols:)` returns plain strings with no ANSI, one per row, which is what tests assert against literally. `render` adds the highlight.
- `Tui::Pane.new(width:, height:).lines(texts)` pads and truncates to an exact rectangle.
- `ListScreen` is `Screen` without a detail pane and keeps the `Showing a-b of n` footer.

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

Each `Hiiro.init` adds a frame `{ id, bin, subcmd, args, pwd }` to `HIIRO_INVOCATION_FRAMES` (the first allocates `HIIRO_INVOCATION_ID`); both are environment variables, so external commands inherit them. When an operation first uses persistence, `Hiiro::Runtime` writes one invocation for that ID and each pending frame as an ordered resolution (frames a child already wrote are skipped by `frame_id`). Help, completion, docs, and operations that never touch persistence record nothing.

**Schema:**
- `Hiiro::Invocation` — `id`, `command` (root `bin subcmd args`), `pwd`, `task`, `worktree`, `git_branch`, Herdr IDs, `entered_at`
- `Hiiro::InvocationResolution` — `invocation_id`, `frame_id`, `depth`, `bin`, `subcmd`, `args_json`, `created_at`

**Query recent invocations:**
```bash
h db q "SELECT i.command, r.depth, r.bin, r.subcmd FROM invocations i JOIN invocation_resolutions r ON r.invocation_id = i.id ORDER BY i.entered_at DESC, r.depth LIMIT 20"
```

### Hiiro::InputFile / Hiiro::EditedDocument (lib/hiiro/input_file.rb)

Tempfile + editor lifecycle for YAML/markdown input. After `edit`, the result is retained as an `EditedDocument`:

```ruby
input = yaml_input_file(content: yaml, prefix: 'todo-edit-')   # or InputFile.yaml_file(hiiro:, ...) / .md_file
doc   = input.edit.document        # EditedDocument: original, result (alias contents), parsed (alias data), error
doc.changed? / doc.empty? / doc.valid? / doc.editor_succeeded?
input.parsed_file                  # nil on YAML parse error or failed editor
input.cleanup                      # unlink the tempfile when done
```

`TodoManager#edit_items` uses this lifecycle for a temporary database projection. A nonzero editor exit makes the document invalid, retains its original/result text, and exposes no parsed data.

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

### Hiiro::CurrentTask / Hiiro::TaskLocation (lib/hiiro/current_task.rb, lib/hiiro/task_location.rb)

`CurrentTask#context` resolves once to the existing `TaskLocation` value. Explicit task selection wins over calling workspace, realpath directory inference, and enabled pins. Optional `resolve` returns nil only when absent; ambiguity, stale pins, and terminal conflicts remain errors. Root workflows and `TableScope` disable pins. Project/home contexts use `TaskLocation.for(nil, root:, root_source:, project:)` without task inference.

```ruby
loc = Hiiro::CurrentTask.new(task: "build", cwd: Dir.pwd, pin: false).context(app: "api")
[loc.task, loc.app, loc.project]
[loc.invocation_directory, loc.root_directory, loc.start_directory]
loc.task_source       # :explicit | :workspace | :directory | :pin | nil
loc.source           # directory provenance: :override, :app, :primary, :tree, :home, :project, :git, :cwd, :frontmatter
loc.terminal         # Herdr::Location with captured calling IDs
loc.for_app("api")   # derives without selecting the task again
loc.with_directory(path, source: :override).validate!
[loc.home, loc.worktree_path, loc.code_directory, loc.app_directory, loc.workspace_label]
Hiiro::TaskLocation.contains?(root, path) # canonical realpath containment
```

`Hiiro#context` and `Environment` share this value; children inherit it. Queue/service/runner/tracked-file builders accept `context:` and selector-stripped `args:`. App paths resolve beneath the context root; directory overrides win. Explicit missing directories fail. A task home may be computed before creation; only an operation that needs it runs `ensure_home`.

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

`bin/h-link` reads and mutates canonical `Hiiro::Link` rows. Editing uses a temporary database projection with the selected stable ID; `links.yml` is only an explicit legacy import input.

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

`run`, `run_combined`, `run3`, `stream`, and `stream_combined` all build one `CommandSpecification` and attach it to the `Result`. `stream` writes each chunk to `tee` once.

`CommandSpecification.shell(text, cwd:, env:)` keeps authored shell text (`kind` `:shell`, `preview` is the text, argv `/bin/bash -c text`) distinct from argv specs; `to_h` / `from_h` round-trip both, and `spawn_args(**opts)` feeds `Process.spawn`. `Hiiro::ProcessOutcome.from_status(status)` answers `exit_code`, `signal` (`'TERM'`), `success?` (exit 0 only), and `shell_code` (exit code or 128 + signal).

### Hiiro::OwnedRun (lib/hiiro/owned_run.rb)

The launch contract for queue, services, and background commands. See `docs/owned-runs.md`.

```ruby
request = Hiiro::OwnedRun::LaunchRequest.new(owner: { kind: 'service', instance: 'web@1a2b3c4d' },
  command: Hiiro::CommandSpecification.new('/bin/bash', script, cwd: dir), process_group: true,
  ready: Hiiro::CommandSpecification.shell('curl -sf localhost:3000', cwd: dir))   # id pre-generated
launcher = Hiiro::OwnedRun::Launcher.new(store: Hiiro::OwnedRun::Store.default, herdr: client, start_timeout: 10)
run = launcher.herdr_tab(request, workspace:, name:, on_allocated: ->(run) { ... })  # also current / detached / herdr_split / herdr_pane
run.state        # allocated | started | ready | completed | failed (transitions only via #transition)
run.process      # ProcessIdentity pid + ps lstart; #alive? rejects a reused pid
run.outcome      # ProcessOutcome ; run.summary  # "failed exit 7"
store.update(id) { |run| run.fail('...') if run.allocated? }   # locked read-modify-write
```

Launch failures (no tab, undelivered command, unspawnable child, start not observed) leave a `failed` record and raise `OwnedRun::LaunchError` (`#run`). `OwnedRun::Supervisor` runs in the allocated place without the rest of Hiiro; after the outcome it settles `queue` owners through `Hiiro::QueueClaim` and `background` owners through `Hiiro::PaneReservations`.

`Hiiro::Capture.stream(spec, path:)` / `.record(spec, path:, name:)` run a command with the caller's stdin and stream combined output in bounded chunks to the terminal and the file; `h capture` exits with the outcome's `shell_code`.

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

Task queue for native `omp` prompts, launched in Herdr tabs/panes or the current process. Markdown prompts carry optional YAML frontmatter (`task_name`, `tree_name`, `session_name`, `app`, `dir`); file statuses are `wip` -> `pending` -> `running` -> `done`/`failed`.

Subcommands (`h queue <subcmd>`):
- `ls`/`list` - List all tasks with status, elapsed time, and preview
- `status` - Detailed status with working directory info
- `add` - Create a new prompt (opens editor or accepts stdin/args, supports `-t <task>` flag)
- `wip` - Create/edit a work-in-progress prompt
- `ready` - Move wip task to pending
- `run [name]` - Launch pending task(s) in Herdr tabs
- `watch` - Continuously poll and launch pending tasks
- `attach [name]` - Switch to a running task’s Herdr pane/tab (fuzzy select if no name)
- `kill [name]` - Signal the run's verified process, wait for its exit, and move it to failed
- `retry [name]` - Move failed/done task back to pending
- `clean` - Remove all done/failed task files
- `dir` - Print queue directory path

Runtime files: `~/.local/share/hiiro/queue/{wip,pending,running,done,failed}/`.

Key internals:
- `Queue::Entry` - `Entry.find(dirs, name)` / `Entry.in(dirs, status)`; answers `prompt_path`, `meta_path`, `body_path`, `companion_files`, `modified_at`, `meta`, `preview`, `prompt`, `execution`, `moved_to(status)`, `to_h` ({ name:, status: }). `Queue#entry_for(name, status)` builds one; `tasks_in`, `all_tasks`, `meta_for`, `task_preview`, `find_task` are thin wrappers over it.
- `Queue::Execution` - snapshot of a running entry's `.meta`: `run_id`, `started_at`, `elapsed` (Duration), `elapsed_minutes`, `working_directory`, `location` (Herdr::Location), `attach_target`
- `Queue::Prompt` - Parses frontmatter to resolve task/tree/session for working directory; retains `path`; `body` strips frontmatter; `Prompt.frontmatter_lines(task_info:, ignore:, hints:)` is the editor template shared by add/wip
- `resolve_prompt_context` handles normal launch and `pane-dir`: explicit task/tree/workspace/app/dir selectors are strict, provenance and calling terminal are retained, and invalid edited context stops before native `omp`.
- Queue launch placement uses Herdr tabs or explicit calling-pane splits, not whichever pane is focused.
- `Hiiro::QueueClaim.claim(root, name)` atomically renames `pending/NAME.md` into `running/` (nil when another launcher won); `QueueClaim.settle(run)` moves `.md`/`.meta` to `done/` (exit 0) or `failed/`. `Queue#launch_task` returns the started `OwnedRun`; `Queue#kill(name)` signals only a verified process and waits. Queue completion never changes a task's status.

### Hiiro::ServiceManager (lib/hiiro/service_manager.rb)

Manages background development services with Herdr integration, env file management, and service groups. Service definitions resolve `base_dir` against the selected context root; absent `base_dir` uses its effective directory. Environment preparation and launch share that resolution, and stop/cleanup retain the saved launch directory.

Subcommands (`h service <subcmd>`):
- `ls`/`list` - List services with their instances (key, run state, directory, task)
- `start <name> [--use VAR=variation ...]` - Start a service or group as an owned run (init -> env -> start)
- `stop <name|instance>` - Signal the verified process (or run `stop` with `$PID`), wait for the observed exit, then clean up
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
- `ServiceManager.instance_key(definition, directory, task, variations)` -> `web@1a2b3c4d`; `sm.instances` (`ServiceManager::Instance`: `key`, `definition`, `directory`, `task`, `run_id`), `resolve_instance(name)`, `run_for(instance)`, `active?(instance)`
- `ServiceDefinition#ready_command` (`ready:` shell text) and `#stop_timeout` (`stop_timeout:`, default 10)
- State tracked per instance in `~/.config/hiiro/services/running.yml`; per-instance scripts in `services/scripts/KEY/`

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

Tracked files resolve against the injected context root, not a second app-directory join; root escape (including dangling symlinks) fails before editor launch.

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

- `exe/h` - Entry point: `Hiiro.run` over `Hiiro::RootCommands.register` (lib/hiiro/root_commands.rb)
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

Current config-root stores under `~/.config/hiiro/`:
- `hiiro.db` - Canonical mutable records through the owners listed in README
- `plugins/` - Plugin files, loaded when a command names them
- `services/` - Service runtime state
- `bg-history.txt` - Background command history
- `jumplist/` - Per-client tmux navigation history
- `env_templates/` - Base .env template files for services
- `services.yml` - Service and service group definitions
- `tools.yml` - Runner tool definitions
- `sparse_groups.yml` - Sparse checkout definitions
- `tables.yml` - Per-table action letters for `h table`
- `config.yml` - Preferences
- `app_files.yml` - Per-app tracked file lists

`~/.local/share/hiiro/queue/` contains prompt queue files and companions. `~/.local/share/hiiro/notify_log.yml` contains the Herdr notification log. Task notes, saved artifacts, indexes, and cleanup SQL remain files at their existing locations.

Legacy domain YAML, task metadata directories, and command-pin files are retained explicit migration inputs. They are not current configuration authorities.

# Groups of files

## tmux-related files

- bin/h-buffer
- bin/h-pane
- bin/h-window
- bin/h-session
- lib/hiiro/tmux.rb
- lib/hiiro/tmux/*

