# h-app

Manage named application subdirectories within a git repo, with shortcuts to cd, search, and run tools scoped to each app.

## Usage

```
h app <subcommand> [args]
```

## Subcommands

### `config`

Open `~/.config/hiiro/apps.yml` in your editor.

### `cd` [alias: none]

Send a `cd` command to the current tmux pane to switch into an app directory (or the repo root if no name given).

**Args:** `[app_name]`

### `ls`

List all configured apps and their relative paths from the repo root.

### `path`

Print the relative path from the current directory to the app (or repo root).

**Args:** `[app_name]`

### `abspath`

Print the absolute filesystem path of the app directory (or repo root).

**Args:** `[app_name]`

### `add`

Register a new app name with a path relative to the repo root.

**Args:** `<app_name>` `<relative_path>`

### `rm` [alias: `remove`]

Remove a registered app by name.

**Args:** `<app_name>`

### `fd`

Run `fd` inside the named app's directory, passing all extra arguments to `fd`.

**Args:** `<app_name>` `[fd_args...]`

### `rg`

Run `rg` (ripgrep) inside the named app's directory.

**Args:** `<app_name>` `[rg_args...]`

### `vim`

Open vim inside the named app's directory.

**Args:** `<app_name>` `[vim_args...]`

### `sh`

Open a shell (or run a command) inside the named app's directory.

**Args:** `<app_name>` `[cmd...]`

### `service`

Delegate to `Hiiro::ServiceManager` subcommands scoped to the current app context. See `h service` for subcommand details.

### `run`

Delegate to `Hiiro::RunnerTool` subcommands. See `h run` for subcommand details.

### `file`

Delegate to `Hiiro::AppFiles` subcommands. See `h file` for subcommand details.
# h-bg

Run commands in background tmux windows with history tracking.

## Usage

```
h bg <subcommand> [args]
```

## Subcommands

### `popup`

Open your `$EDITOR` with recent command history as comments, then run whatever you type in a background tmux window. History is stored in `~/.config/hiiro/bg-history.txt` (max 50 entries).

### `run`

Run a command immediately in a new background tmux window.

**Args:** `<cmd...>`

### `attach` [alias: `a`]

Switch the current tmux client to the background session.

### `history` [alias: `hist`]

Print the recent background command history (up to 50 entries), newest last.

### `setup`

Print the tmux.conf line needed to bind `prefix + b` to open the popup. Does not modify any config files automatically.
# h-bin

List and edit hiiro bin scripts (`h-*` executables found in PATH).

## Usage

```
h bin <subcommand> [filters...]
```

## Subcommands

### `list`

Print the paths of all `h-*` executables found in PATH. Optionally filter by name patterns; each pattern is matched as `h-<pattern>` or `<pattern>`.

**Args:** `[subcmd_name...]`

### `edit`

Open matching `h-*` executables in your editor. Patterns work the same as `list`.

**Args:** `[subcmd_name...]`
# h-branch

Manage, tag, search, and inspect git branches with task and PR associations stored in SQLite.

## Usage

```
h branch <subcommand> [options] [args]
```

## Subcommands

### `save`

Save the current (or named) branch to the branch store with current task, worktree, and tmux context.

**Args:** `[branch_name]`

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--tag` | `-t` | Tag to apply (repeatable) | — |

### `saved`

List saved branches, with optional filter string.

**Args:** `[filter]`

### `current`

Print the current git branch name.

### `info`

Show detailed info about the current branch: SHA, task, worktree, tmux context, ahead/behind vs main, associated PR, and note.

### `ls`

List branches (saved by default, or all local with `-a`).

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--tag` | `-t` | Filter by tag (OR when multiple, repeatable) | — |
| `--all` | `-a` | Show all local branches instead of just saved | false |

### `search`

Search saved (or all) branches by name or tag substring.

**Args:** `<term> [term2...]`

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Search all local branches | false |

### `tag`

Add tags to a branch. With `-e`, opens a YAML editor for bulk tagging.

**Args:** `[branch] <tag> [tag2...]`

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--edit` | `-e` | Open YAML editor for bulk tagging | false |

### `untag`

Remove one or more tags from a branch, or clear all tags if none specified.

**Args:** `[branch] [tag...]`

### `tags`

Show all tagged branches grouped by tag.

### `select`

Fuzzy-select a branch name from saved (or all) branches and print it.

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Select from all local branches | false |

### `copy`

Fuzzy-select a branch and copy its name to clipboard.

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Select from all local branches | false |

### `co` [alias: `checkout`]

Checkout a branch, fuzzy-selecting if no name given.

**Args:** `[branch]`

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Select from all local branches | false |

### `rm` [alias: `remove`]

Delete a branch (`git branch -d`), fuzzy-selecting if no name given.

**Args:** `[branch]`

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Select from all local branches | false |

### `rename`

Rename a branch locally and on the remote, then update the saved record.

**Args:** `<new_name> [old_name]`

### `status`

Show ahead/behind counts and associated PR state for each branch.

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Show all local branches | false |

### `merged`

List branches that have been merged into main/master.

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Show all merged branches, not just saved | false |

### `clean`

Interactively delete merged branches. With `-f`, delete all without prompting.

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Include all merged branches | false |
| `--force` | `-f` | Delete all without confirmation | false |

### `recent`

Show the N most recently visited branches from reflog.

**Args:** `[n]` (default: 10)

### `note`

Get or set a freeform note on a branch.

**Args:** `[text...]`

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--clear` | — | Clear the note | false |

### `for-task`

List saved branches associated with a given task name (or current task).

**Args:** `[task_name]`

### `for-pr` [alias: `pr`]

Print the head branch name for a tracked PR (fuzzy-select if no arg).

**Args:** `[pr_number_or_url]`

### `duplicate`

Create a new branch as a copy of the current (or specified) branch.

**Args:** `<new_name> [source_branch]`

### `push`

Push a branch to a remote with optional force and upstream tracking.

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--remote` | `-r` | Remote name | `origin` |
| `--from` | `-f` | Local branch or commit | current branch |
| `--to` | `-t` | Remote branch name | same as from |
| `--force` | `-F` | Force push | false |
| `--set-upstream` | `-u` | Set upstream tracking | false |

### `diff`

Show commit log between two refs (defaults to `main..HEAD`).

**Args:** `[from] [to]`

### `changed`

List files changed between the current branch and its upstream fork point.

**Args:** `[upstream]`

### `ahead`

Show how many commits the branch is ahead of a base.

**Args:** `[base] [branch]`

### `behind`

Show how many commits the branch is behind a base.

**Args:** `[base] [branch]`

### `log`

Show the commit log for changes since the upstream fork point.

**Args:** `[upstream]`

### `q` [alias: `query`]

Query the branches SQLite table directly. Pass a table name, `key=value` filters, or raw SQL.

**Args:** `[table|sql|key=value...]`

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Show all rows (no 50-row limit) | false |

### `forkpoint`

Print the merge-base SHA between the current branch and an upstream.

**Args:** `[upstream] [branch]`

### `ancestor`

Check whether one ref is an ancestor of another.

**Args:** `[ancestor] [descendant]`
# h-buffer

Manage tmux paste buffers — list, show, copy to clipboard, save, load, paste, and delete.

## Usage

```
h buffer <subcommand> [args]
```

## Subcommands

### `ls`

List all tmux buffers. Extra args are passed directly to `tmux list-buffers`.

**Args:** `[tmux_args...]`

### `show`

Print the contents of a buffer (fuzzy-select if no name given).

**Args:** `[buffer_name] [tmux_args...]`

### `copy`

Copy a buffer's contents to the macOS clipboard via `pbcopy` (fuzzy-select if no name).

**Args:** `[buffer_name]`

### `save`

Save a buffer's contents to a file (fuzzy-select buffer if name not given).

**Args:** `<path> [buffer_name] [tmux_args...]`

### `load`

Load a file into the tmux buffer stack.

**Args:** `<path> [tmux_args...]`

### `set`

Set buffer contents; all args passed directly to `tmux set-buffer`.

**Args:** `[tmux_args...]`

### `paste`

Paste a buffer into the current pane.

**Args:** `[buffer_name] [tmux_args...]`

### `delete`

Delete a buffer (fuzzy-select if no name given).

**Args:** `[buffer_name]`

### `choose`

Open the tmux buffer chooser UI.

**Args:** `[tmux_args...]`

### `clear`

Delete all tmux buffers.

### `select`

Fuzzy-select a buffer name and print it.
# h-claude

Launch Claude Code sessions in tmux splits/windows, search `.claude` directories, and run inline prompts.

## Usage

```
h claude <subcommand> [options] [args]
```

## Global Options

These flags apply to `split`, `vsplit`, `hsplit`, and `window` subcommands:

| Flag | Short | Description | Default |
|---|---|---|---|
| `--danger` | `-d` | Pass `--dangerously-skip-permissions` | false |
| `--horizontal` | `-h` | Split horizontally instead of vertically | false |
| `--percent` | `-p` | Interpret size as a percentage | false |
| `--bottom` | `-b` | Place new pane at the bottom | false |
| `--left` | `-l` | Place new pane on the left | false |
| `--ignore` | `-i` | Use fire-and-forget mode (`claude -p`, window closes when done) | false |
| `--size` | `-s` | Pane size | `40` |

## Subcommands

### `split`

Split the current tmux pane and start a Claude session in the new pane.

**Args:** `[args passed to claude...]`

### `vsplit`

Create a vertical split and start Claude.

**Args:** `[args passed to claude...]`

### `hsplit`

Create a horizontal split and start Claude.

**Args:** `[args passed to claude...]`

### `window`

Open a new tmux window and start Claude.

**Args:** `[args passed to claude...]`

### `inline`

Send a prompt directly to `claude -p` and print the response. Reads from stdin, positional args, or opens your editor if neither is provided.

**Args:** `[prompt...]`

### `new`

Open your editor to write a prompt, then exec `claude` with it as the initial message.

### `loop`

Interactive prompt loop: open editor, send to `claude -p`, display response, repeat. Leave the editor empty to exit.

### `all`

List all agents, commands, and skills found in `.claude` directories walking up from `$PWD`.

**Options (tool flags):**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--full` | `-f` | Full-text search (grep) rather than name match | false |
| `--verbose` | `-v` | Show `.claude` dir paths on stderr | false |
| `--veryverbose` | `-V` | Show all stderr debug output | false |

**Args:** `[filter...]`

### `agents`

List agents from `.claude/agents/` directories.

**Args:** `[filter...]`

### `commands`

List commands from `.claude/commands/` directories.

**Args:** `[filter...]`

### `skills`

List skills from `.claude/skills/` directories.

**Args:** `[filter...]`

### `vim`

Open matching agents, commands, or skill SKILL.md files in vim.

**Args:** `[filter...]`
# h-commit

Fuzzy-select a git commit SHA from the recent log.

## Usage

```
h commit <subcommand> [git-log-args]
```

## Subcommands

### `select` [alias: `sk`]

Show the last 50 commits via `git log --oneline --decorate`, open them in `sk` for fuzzy selection, and print the selected SHA. Any extra args are forwarded to `git log`.

**Args:** `[git_log_args...]`
# h-config

Open common configuration files in your editor.

## Usage

```
h config <subcommand>
```

## Subcommands

### `vim`

Open `~/.config/nvim/init.lua` (or `init.vim` if lua not found).

### `git`

Open git config files. This subcommand has nested sub-subcommands:

- `h config git global` — Open `~/.gitconfig`
- `h config git ignore` — Open `~/.config/git/ignore`
- `h config git local` — Open `.git/config` in the current repository

### `tmux`

Open `~/.tmux.conf`.

### `zsh`

Open `~/.zshrc`.

### `profile`

Open `~/.zprofile`.

### `starship`

Open `~/.config/starship/starship.toml`.

### `claude`

Open `~/.claude/settings.json`.
# h-cpr

Proxy `h pr` subcommands to the PR associated with the current git branch.

## Usage

```
h cpr [subcommand] [args]
```

`h-cpr` detects the PR number for the current branch via `gh pr view`, then delegates to `h pr`. With no subcommand it runs `h pr view <number>`. With a subcommand it runs `h pr <subcommand> <number> [args...]`.

## Examples

```
h cpr            # h pr view <current PR number>
h cpr check      # h pr check <current PR number>
h cpr open       # h pr open <current PR number>
h cpr diff       # h pr diff <current PR number>
```

Exits with status 1 if there is no open PR for the current branch.
# h-db

Inspect and manage the hiiro SQLite database (`~/.config/hiiro/hiiro.db`).

## Usage

```
h db <subcommand> [args]
```

## Subcommands

### `status`

Show connection info (path, file size), migration state, dual-write status, table row counts, and available backup archives.

### `tables`

List all table names in the database.

### `q` [alias: `query`]

Query the database. Accepts a table name with optional `key=value` filters, or raw SQL.

**Args:** `<table|sql> [key=value...]`

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Show all rows (no 50-row limit) | false |

**Examples:**
```
h db q branches
h db q branches task=my-task
h db q "SELECT * FROM branches WHERE name LIKE '%feat%'"
```

### `migrate`

Archive all YAML files to a timestamped `.tar.gz` and disable dual-write mode. Prompts for confirmation before deleting YAML files.

### `remigrate`

Re-import data from YAML sources into SQLite. Optionally limit to specific tables.

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--only` | — | Comma-separated list of tables to remigrate | all |

### `cleanup`

Scan all tables for duplicate rows (using natural unique keys), generate a SQL file with `DELETE` statements to fix them, open it in your editor, and print instructions for applying it. The SQL file is saved to `~/notes/files/`.

### `restore`

Restore YAML files from the most recent backup archive in `~/.config/hiiro/`.
# h-img

Save or base64-encode images from the clipboard or from files.

## Usage

```
h img <subcommand> [args]
```

Requires `pngpaste` to be installed for clipboard operations.

## Subcommands

### `save`

Save the current clipboard image to a file on disk.

**Args:** `<outpath>`

### `b64`

Print a base64 data URI for an image file or the current clipboard image.

**Args:** `[path]`

If `path` is omitted, reads from the clipboard. Outputs the full data URI: `data:<mime>;base64,<encoded>`.
# h-jumplist

Vim-style tmux navigation history — jump backward and forward through pane/window/session focus history.

## Usage

```
h jumplist <subcommand>
```

History is stored per tmux client in `~/.config/hiiro/jumplist/`. Dead panes are automatically pruned. Duplicate consecutive entries are deduplicated. Forward history is truncated when you navigate to a new location (like vim).

## Subcommands

### `setup`

Write `~/.config/tmux/h-jumplist.tmux.conf` with tmux hooks to record navigation events and key bindings (`Ctrl-B` = back, `Ctrl-F` = forward). Append a `source-file` line to `~/.tmux.conf`.

### `record`

Record the current pane/window/session as a new jumplist entry. Called automatically by tmux hooks; typically not invoked manually. Suppresses itself if `TMUX_JUMPLIST_SUPPRESS=1` is set.

### `back`

Navigate to the previous position in history (older). If already at the oldest entry, shows a tmux message.

### `forward`

Navigate to the next position in history (newer). If already at the newest entry, shows a tmux message.

### `to`

Navigate directly to a specific history entry by index.

**Args:** `<index>`

### `ls` [alias: `list`]

Print the full jumplist with timestamps and a `<--` marker on the current position.

### `clear`

Clear the jumplist and reset position to the current pane.

### `path`

Print the jumplist file path for the current tmux client.
# h-link

Store, search, tag, and open saved URLs.

## Usage

```
h link <subcommand> [options] [args]
```

## Subcommands

### `add`

Add a URL to the link store. With no args, opens an editor template. With a URL, saves it directly. Supports optional description, shorthand alias, and tags.

**Args:** `[url] [description...]`

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--shorthand` | `-s` | Short alias for the link | — |
| `--tag` | `-t` | Tag (repeatable) | — |
| `--tags` | — | Tag (alias for --tag, repeatable) | — |

### `ls` [alias: `list`]

Print all saved links with index, shorthand, URL, and description.

### `search`

Search links by URL, description, or shorthand substring. All terms must match.

**Args:** `<term> [term2...]`

### `select`

Fuzzy-select a link and print its URL. Prompts for placeholder values if the URL contains `{name}` tokens.

**Args:** `[filter...]`

### `copy`

Fuzzy-select a link and copy its URL to clipboard. Handles `{placeholders}` as in `select`.

**Args:** `[filter...]`

### `open`

Open a link in the browser. With no arg, fuzzy-selects. With a number/shorthand/search term, opens that link directly.

**Args:** `[number|shorthand|search_term]`

### `edit`

Open a single link in your editor by number or shorthand.

**Args:** `<number|shorthand>`

### `editall`

Open the raw links YAML file in your editor.

### `rm` [alias: `remove`]

Remove a link by number, shorthand, or URL substring. Fuzzy-selects if no arg given.

**Args:** `[number|shorthand|search_term...]`

### `tags`

List all tags and the links associated with each tag.

**Args:** `[tag...]`

### `paste`

Save the current clipboard URL as a new link with optional description and tags.

**Args:** `[description...]`

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--shorthand` | `-s` | Short alias | — |
| `--tag` | `-t` | Tag (repeatable) | — |
| `--tags` | — | Tag (alias, repeatable) | — |

### `path`

Print the path to the links YAML file.
# h-misc

Miscellaneous utility subcommands.

## Usage

```
h misc <subcommand> [options] [args]
```

## Subcommands

### `symlink_destinations`

List symlinks under a given directory whose targets point outside that directory, formatted as `dest => link_path`.

**Args:** `<basedir> [basedir2...]`

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--root` | `-r` | Root path for relative display | git repo root |
# h-notify

Push and manage in-pane notifications with macOS alerts, tmux menu navigation, and Claude Code hook integration.

## Usage

```
h notify <subcommand> [options] [args]
```

## Global Options

These options are parsed from `args` before subcommand dispatch:

| Flag | Short | Description | Default |
|---|---|---|---|
| `--type` | `-t` | Notification type: `success`, `error`, `info`, `warning` | `info` |

## Subcommands

### `push`

Push a notification for the current tmux pane. Fires a macOS `terminal-notifier` alert and records the entry in the log (one entry per pane, newest first).

**Args:** `<message...>`

### `ls`

List all current notifications with index, type prefix, session/pane, command, message, and timestamp.

### `menu`

Open a tmux `display-menu` showing up to 10 pending notifications. Selecting one switches to that pane. A "Clear all" option is also provided.

### `jump`

Navigate to the pane associated with a notification by index and remove it from the log.

**Args:** `<index>`

### `clear`

Remove all notifications from the log.

### `remove_pane`

Remove all notifications associated with a pane ID (called automatically by tmux `after-kill-pane` hook).

**Args:** `<pane_id>`

### `remove_window`

Remove notifications for a window ID (called by tmux `window-unlinked` hook).

**Args:** `<window_id>`

### `remove_session`

Remove notifications for a session (called by tmux `session-closed` hook).

**Args:** `<session_name>`

### `tmux`

Manage tmux hook configuration for automatic notification cleanup. Nested subcommands:

- `h notify tmux setup` — Write `~/.config/tmux/h-notify.tmux.conf`
- `h notify tmux add_hooks` — Source the conf file from `~/.tmux.conf`
- `h notify tmux reset_hooks` — Unset the managed tmux hooks
- `h notify tmux load_hooks` — Reload `~/.tmux.conf` via `tmux source-file`

### `claude`

Manage Claude Code hook integration in `~/.claude/settings.json`. Nested subcommands:

- `h notify claude setup` — Write fresh `Notification` and `Stop` hooks that call `h alert` + `h notify push`
- `h notify claude add_hooks` — Inject `h notify push` into existing hooks without overwriting them
- `h notify claude reset_hooks` — Strip the `h notify push` portion from existing hooks
- `h notify claude load_hooks` — Print a reminder that Claude Code settings load on startup
# h-pane

Manage tmux panes — list, split, kill, zoom, capture, resize, and configure named home panes.

## Usage

```
h pane <subcommand> [args]
```

## Subcommands

### `ls`

List panes in the current window. Extra args passed to `tmux list-panes`.

**Args:** `[tmux_args...]`

### `lsa`

List all panes across all sessions.

**Args:** `[tmux_args...]`

### `split`

Split the current window. All args passed to `tmux split-window`.

**Args:** `[tmux_args...]`

### `splitv`

Split vertically.

**Args:** `[tmux_args...]`

### `splith`

Split horizontally.

**Args:** `[tmux_args...]`

### `kill`

Kill a pane (fuzzy-select if no target given).

**Args:** `[target]`

### `swap`

Swap panes. Args passed to `tmux swap-pane`.

**Args:** `[tmux_args...]`

### `zoom`

Toggle zoom on a pane.

**Args:** `[target]`

### `capture`

Capture the current pane's output. Args passed to `tmux capture-pane`.

**Args:** `[tmux_args...]`

### `select`

Fuzzy-select a pane ID and print it.

**Args:** `[target]`

### `copy`

Fuzzy-select a pane ID and copy it to clipboard.

**Args:** `[target]`

### `sw` [alias: `switch`]

Switch to a pane (fuzzy-select if no target).

**Args:** `[target]`

### `home`

Manage named home panes. Nested subcommands:

- `h pane home ls` — List configured home panes
- `h pane home add <name> <session> [path]` — Add a home pane mapping
- `h pane home rm <name>` — Remove a home pane
- `h pane home switch [name]` — Switch to a home pane (fuzzy-select if no name); creates the session/window if needed

### `move`

Move a pane. Args passed to `tmux move-pane`.

**Args:** `[tmux_args...]`

### `break`

Break a pane out into its own window.

**Args:** `[tmux_args...]`

### `join`

Join a pane into the current window. Args passed to `tmux join-pane`.

**Args:** `[tmux_args...]`

### `resize`

Resize a pane. Args passed to `tmux resize-pane`.

**Args:** `[tmux_args...]`

### `width`

Set the pane width to a specific size.

**Args:** `<size> [target]`

### `height`

Set the pane height to a specific size.

**Args:** `<size> [target]`

### `info`

Show details for the current (or target) pane: size, command, and path.

**Args:** `[target]`
# h-plugin

List, edit, and search hiiro plugin files in `~/.config/hiiro/plugins/`.

## Usage

```
h plugin <subcommand> [args]
```

## Subcommands

### `path`

Print the plugin directory path (`~/.config/hiiro/plugins`).

### `ls`

Print the paths of all files in the plugin directory.

### `edit`

Open plugin files in your editor. With no args, opens `h-plugin` itself. With name args, prefix-matches plugin filenames and opens the matches.

**Args:** `[plugin_name...]`

### `rg`

Run `rg -S` (case-smart ripgrep) inside the plugin directory.

**Args:** `[rg_args...]`

### `rgall`

Run `rg -S --no-ignore-vcs` inside the plugin directory (includes VCS-ignored files).

**Args:** `[rg_args...]`
# h-pm

Queue `/project-manager` skill prompts via `h queue add`.

## Usage

```
h pm [subcommand] [args]
```

With no subcommand, fuzzy-selects a project-manager command interactively.

## Subcommands

Each subcommand builds a `/project-manager <subcmd> [args]` prompt and queues it via `h queue add`.

### `discover`

Auto-discover projects and tasks from PRs, worktrees, and olive runs.

**Args:** `[project]`

### `resume`

Show a "where was I?" session briefing for a project.

**Args:** `<project>`

### `status`

Show a project status overview.

**Args:** `<project>`

### `add`

Add a new task to a project.

**Args:** `<project> <task>`

### `start`

Load context and begin working on a task.

**Args:** `<project> <task>`

### `plan`

Generate or update a proposal document for a task.

**Args:** `<project> <task>`

### `complete`

Mark a task as complete.

**Args:** `<project> <task>`

### `ref`

Add a reference document (PRD, spec, Figma link, etc.) to a project.

**Args:** `<project> [url-or-path]`

### `impact`

Analyze cascading impact of a task deviation on child tasks.

**Args:** `<project> <task>`

### `archive`

Archive a completed or stale project.

**Args:** `<project>`

### `unarchive`

Restore an archived project.

**Args:** `<project>`

### `help`

Print usage information.
# h-pr-monitor

Poll `gh pr status` in a loop and send macOS notifications when PR check status or approval counts change.

## Usage

```
h pr-monitor [options]
```

This command runs indefinitely, polling every 60 seconds (or `$sleep_for` env var).

## Options

| Flag | Description | Default |
|---|---|---|
| `-a`, `--no-notify-approvals` | Disable notifications for new approvals | notify enabled |
| `-s`, `--no-notify-status` | Disable notifications for check status changes | notify enabled |
| `-u`, `--no-notify-publishing` | Disable notification when marking PR ready | notify enabled |
| `-r`, `--mark-ready` | Automatically mark PR as ready when checks pass | false |
| `-h`, `--help` | Print help | — |

## Notes

Notifications are sent via shell scripts `pr_approved`, `pr_passing`, `pr_failing`, `pr_pending`, and `pr_publishing` — these must exist in PATH. When `--mark-ready` is enabled and checks pass, `gh pr ready <number>` is called automatically.
# h-pr

Track, update, view, and act on GitHub pull requests with pinned PR management and multi-PR batch operations.

## Usage

```
h pr <subcommand> [options] [args]
```

## Subcommands

### `check`

Run `gh pr checks` on a PR and send a macOS notification when done.

**Args:** `[pr_number]`

### `watch`

Run `gh pr checks --watch` on a PR and notify when complete.

**Args:** `[pr_number]`

### `fwatch`

Run `gh pr checks --watch --fail-fast` and notify.

**Args:** `[pr_number]`

### `number`

Print the PR number for the current branch.

### `link`

Print the URL for a PR (from pinned store or `gh pr view`).

**Args:** `[pr_number_or_ref]`

### `open`

Open a PR in the browser. With no arg, opens the current branch's PR.

**Args:** `[pr_number_or_ref...]`

### `view`

Run `gh pr view` on a PR.

**Args:** `[pr_number_or_ref]`

### `select`

Fuzzy-select from your open PRs and print the PR number.

### `copy`

Fuzzy-select from your open PRs and copy the number to clipboard.

### `track`

Start tracking a PR: fetch its info, tag it with current task/worktree context, and add it to the pinned store.

**Args:** `[pr_number|-]`

### `ls`

List tracked PRs with check status, review counts, and state.

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--update` | `-u` | Refresh status before listing | false |
| `--verbose` | `-v` | Multi-line output per PR | false |
| `--checks` | `-C` | Show individual check run details | false |
| `--diff` | `-d` | Open diff for fuzzy-selected PR | false |
| `--all` | `-a` | Show all tracked PRs without filter | false |

### `status`

Show check status summary for a PR (or the current branch's PR).

**Args:** `[pr_number_or_ref...]`

### `update`

Refresh check status and reviews for all active tracked PRs, then display the list.

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--force-update` | `-u` | Force refresh even if recently checked | false |
| `--all` | `-a` | Show all tracked PRs | false |

### `green`

List tracked PRs with all checks passing.

### `red`

List tracked PRs with failing checks.

### `old`

List merged/closed tracked PRs.

### `prune`

Remove all merged and closed PRs from tracking.

### `draft`

List tracked PRs that are in draft state.

### `assigned`

List open PRs assigned to you, indicating which are already tracked.

### `created`

List open PRs created by you, indicating which are already tracked.

### `missing`

List your open/assigned PRs that are not yet tracked.

### `amissing`

Interactively add untracked PRs: opens a YAML editor pre-filled with untracked PR numbers; save to track selected ones.

### `attach`

Open a new tmux window in the PR's task session, checkout the PR branch (committing any WIP first).

**Args:** `[pr_number_or_ref]`

### `rm`

Remove a PR from tracking (fuzzy-select if no arg).

**Args:** `[pr_number]`

### `ready`

Mark a PR as ready for review (`gh pr ready`).

**Args:** `[pr_number_or_ref]`

### `to-draft`

Convert a PR to draft (`gh pr ready --draft`).

**Args:** `[pr_number_or_ref]`

### `diff`

Show the PR diff via `gh pr diff`.

**Args:** `[pr_number_or_ref]`

### `checkout`

Checkout the PR branch via `gh pr checkout`.

**Args:** `[pr_number_or_ref]`

### `merge`

Merge a PR via `gh pr merge`.

**Args:** `[pr_number_or_ref] [merge_args...]`

### `sync`

Sync the PR with its base branch via rebase (falls back to merge on conflict).

**Args:** `[pr_number_or_ref]`

### `fix`

Queue a `/pr:fix` task for failing PRs. Fuzzy-selects from failing PRs by default; `-r` fixes all failing at once.

**Args:** `[pr_number_or_ref...]`

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--red` | `-r` | Fix all PRs with failing checks | false |
| `--run` | `-R` | Launch queue tasks immediately | false |

### `comment`

Add a comment to a PR by opening your editor.

**Args:** `[pr_number_or_ref]`

### `templates`

List available comment templates from `~/.config/hiiro/pr_templates/`.

### `new-template`

Create a new comment template.

**Args:** `<name>`

### `from-template`

Fuzzy-select a comment template and post it to a PR.

**Args:** `[pr_number_or_ref]`

### `branch`

Print the head branch name for a tracked PR.

**Args:** `[pr_number_or_url]`

### `for-task`

List tracked PRs associated with a task name (or current task).

**Args:** `[task_name]`

### `tag`

Add tags to a tracked PR. With `-e`, opens a YAML bulk-tag editor.

**Args:** `[pr_ref] <tag> [tag2...]`

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--edit` | `-e` | Open YAML editor for bulk tagging | false |

### `untag`

Remove tags from a PR, or clear all if none specified.

**Args:** `<pr_ref> [tag...]`

### `tags`

Show all tracked PRs grouped by tag.

### `mfix`

Batch fix: YAML editor to select PRs to queue `/pr:fix` tasks for.

### `mopen`

Batch open: YAML editor to select PRs to open in browser.

### `mmerge`

Batch merge: YAML editor to select PRs and merge strategy.

### `mready`

Batch ready: YAML editor to mark selected PRs as ready for review.

### `mto-draft`

Batch draft: YAML editor to convert selected PRs to draft.

### `mrm`

Batch remove: YAML editor to remove selected PRs from tracking.

### `mcomment`

Batch comment: YAML editor to select PRs and write a comment to post on all of them.

### `dep`

Manage PR dependency relationships. Nested subcommands:

- `h pr dep add <pr> <dep1> [dep2...]` — Add dependency PRs
- `h pr dep rm <pr> [dep1 dep2...]` — Remove dependencies (omit deps to clear all)
- `h pr dep ls [pr]` — List dependencies for a PR or all PRs with dependencies

### `config`

Show or edit the pinned PRs config file. Nested subcommands:

- `h pr config path` — Print path to pinned PRs file
- `h pr config vim` — Open pinned PRs file in editor

### `q` [alias: `query`]

Query the `pinned_prs` SQLite table directly.

**Args:** `[table|sql|key=value...]`

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Show all rows (no 50-row limit) | false |
# h-project

Manage project directories and start tmux sessions for them.

## Usage

```
h project <subcommand> [args]
```

Projects are discovered from two sources:
- Directories in `~/proj/`
- Entries in `~/.config/hiiro/projects.yml`

## Subcommands

### `open`

Open a project by name (regex match, case-insensitive) and start or switch to its tmux session. Falls back to `~/proj/` if no match.

**Args:** `<project_name>`

### `list` [alias: `ls`]

List all known projects with source tag (`[config]` or `[dir]`) and path.

### `config`

Print the contents of `~/.config/hiiro/projects.yml`.

### `edit`

Open `~/.config/hiiro/projects.yml` in your editor (creates the file if it does not exist).

### `select`

Fuzzy-select a project and print its path.

### `copy`

Fuzzy-select a project and copy its path to clipboard.

### `sh`

Open a shell (or run a command) inside a project directory.

**Args:** `<project_name> [cmd...]`

### `help`

Print usage information.
# h-registry

Store and look up named resources by type with optional short aliases.

## Usage

```
h registry <subcommand> [args]
```

## Subcommands

### `ls` [alias: `list`]

List all registry entries grouped by type, with short name and description columns.

**Args:** `[type]`

### `types`

List all known resource types in the registry.

### `add`

Add a new entry to the registry.

**Args:** `<type> <name>`

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--alias` | `-a` | Short alias | — |
| `--desc` | `-d` | Description | — |

### `rm` [alias: `remove`]

Remove an entry by name or alias, optionally scoped to a type.

**Args:** `<name_or_alias> [type]`

### `get`

Print the canonical name for a registry entry (scriptable; exits 1 if not found).

**Args:** `<name_or_alias> [type]`

### `show`

Print human-readable detail for a registry entry.

**Args:** `<name_or_alias> [type]`

### `select`

Fuzzy-select an entry and print its canonical name.

**Args:** `[type]`

### `set-alias`

Update the short alias for an entry.

**Args:** `<name_or_alias> <new_alias> [type]`
# h-session

Manage tmux sessions — list, create, kill, attach, rename, switch, and detect orphans.

## Usage

```
h session <subcommand> [args]
```

## Subcommands

### `ls` [alias: `list`]

List all tmux sessions. Extra args passed to `tmux list-sessions`.

**Args:** `[tmux_args...]`

### `new`

Create a new tmux session.

**Args:** `[name] [tmux_args...]`

### `kill`

Kill a session (fuzzy-select if no name given).

**Args:** `[name]`

### `attach`

Attach to a session (fuzzy-select if no name given).

**Args:** `[name]`

### `rename`

Rename a session.

**Args:** `[old_name] <new_name>`

### `switch`

Switch the current client to a session (fuzzy-select if no name).

**Args:** `[name]`

### `detach`

Detach the current client from its session.

**Args:** `[tmux_args...]`

### `has`

Check whether a session exists (exits 0 or 1).

**Args:** `[name]`

### `info`

Show basic info about the current (or named) session: name, window count, attached status.

**Args:** `[name]`

### `open`

Switch to or attach to a named session.

**Args:** `<name>`

### `sh`

Open a new window in a session and switch to it. Optionally run a command in the new window.

**Args:** `<session_name> [cmd...]`

### `select`

Fuzzy-select a session name and print it.

### `copy`

Fuzzy-select a session name and copy it to clipboard.

### `orphans`

List sessions that have no associated hiiro task.

### `okill`

Open a YAML editor pre-filled with orphan session names; delete all sessions you leave in the file.
# h-sha

Fuzzy-select, show, and copy git commit SHAs.

## Usage

```
h sha <subcommand> [args]
```

## Subcommands

### `select`

Show the last 100 commits via `git log --oneline`, fuzzy-select one, and print its SHA.

**Args:** `[git_log_args...]`

### `ls`

List recent commits via `git log --oneline`.

**Args:** `[git_log_args...]`

### `show`

Run `git show` on a SHA. If no SHA is given, runs `h sha select` interactively.

**Args:** `[sha] [git_show_args...]`

### `copy`

Copy a SHA to clipboard. If no SHA is given, runs `h sha select` interactively.

**Args:** `[sha]`
# h-sparse

Manage named git sparse-checkout path groups stored in `~/.config/hiiro/sparse_groups.yml`.

## Usage

```
h sparse <subcommand> [args]
```

## Subcommands

### `config`

Open `~/.config/hiiro/sparse_groups.yml` in your editor.

### `ls` [alias: `list`]

List all configured sparse groups. With a group name, list that group's paths. Without an arg, show all groups with path counts.

**Args:** `[group_name]`

### `set`

Apply a sparse group to the current git repository using `git sparse-checkout set --cone`.

**Args:** `<group_name>`

### `add`

Add one or more paths to a named sparse group (creates the group if it does not exist).

**Args:** `<group_name> <path> [path2...]`

### `rm`

Remove a group entirely (no paths given) or remove specific paths from a group.

**Args:** `<group_name> [path...]`
# h-tags

Query tags grouped by taggable type from the hiiro database.

## Usage

```
h tags <subcommand> [args]
```

## Subcommands

### `tags_by_type`

Look up tags filtered by taggable type and print all tagged objects for those tags.

**Args:** `[type...]`

Note: This subcommand is a development/debug utility and drops into a `pry` REPL after displaying results.
# h-title

Update the terminal tab title from the current tmux session's associated hiiro task name.

## Usage

```
h title <subcommand>
```

## Subcommands

### `update`

Read the current tmux session name, find the associated hiiro task, and write an OSC escape sequence to the client TTY to set the terminal tab title. Silently does nothing if not in tmux or if the TTY write fails.

### `setup`

Write `~/.config/tmux/h-title.tmux.conf` with tmux hooks that call `h title update` on session change and new session events, then append a `source-file` line to `~/.tmux.conf`.
# h-todo

Manage a personal todo list with statuses, tags, and task associations.

## Usage

```
h todo <subcommand> [args]
```

## Subcommands

### `ls` [alias: `list`]

List todo items. Defaults to active (not done/skip) items.

**Args (inline flags):**
- `-a`, `--all` — Show all items including done/skip
- `-s STATUS`, `--status STATUS` — Filter by status (comma-separated: `not_started`, `started`, `done`, `skip`)
- `-t TAG`, `--tag TAG` — Filter by tag
- `--task TASK` — Filter by task name

### `add`

Add one or more todo items. With no args, opens an editor for YAML bulk input. With text, adds directly. Use `-t` for tags.

**Args:** `[text...] [-t tags]`

### `rm` [alias: `remove`]

Remove a todo item by ID. Fuzzy-selects from active items if no ID given.

**Args:** `[id_or_index]`

### `change`

Modify a todo item's text, tags, or status.

**Args:** `<id_or_index> [new_text] [--text TEXT] [--tags TAGS] [--status STATUS]`

### `start`

Mark a todo item as started (`[>]`). Fuzzy-selects if no ID given.

**Args:** `[id_or_index]`

### `done`

Mark a todo item as done (`[x]`). Fuzzy-selects if no ID given.

**Args:** `[id_or_index]`

### `skip`

Mark a todo item as skipped (`[-]`). Fuzzy-selects if no ID given.

**Args:** `[id_or_index]`

### `reset`

Reset a todo item to `not_started` (`[ ]`). Fuzzy-selects from completed items if no ID given.

**Args:** `[id_or_index]`

### `search`

Search items by text, tags, or task name.

**Args:** `<query...>`

### `path`

Print the path to the todo YAML file.

### `editall`

Open the raw todo YAML file in your editor.

### `help`

Print usage information and status icon legend.

## Status Icons

| Icon | Status |
|---|---|
| `[ ]` | not_started |
| `[>]` | started |
| `[x]` | done |
| `[-]` | skip |
# h-window

Manage tmux windows — list, create, kill, rename, swap, navigate, and change layout.

## Usage

```
h window <subcommand> [args]
```

## Subcommands

### `ls`

List windows in the current session. Extra args passed to `tmux list-windows`.

**Args:** `[tmux_args...]`

### `lsa`

List all windows across all sessions.

**Args:** `[tmux_args...]`

### `new`

Create a new window with an optional name.

**Args:** `[name] [tmux_args...]`

### `kill`

Kill a window (fuzzy-select if no target given).

**Args:** `[target]`

### `rename`

Rename the current window. Args passed to `tmux rename-window`.

**Args:** `[tmux_args...]`

### `swap`

Swap windows. Args passed to `tmux swap-window`.

**Args:** `[tmux_args...]`

### `move`

Move window. Args passed to `tmux move-window`.

**Args:** `[tmux_args...]`

### `select`

Fuzzy-select a window target and print it.

**Args:** `[target]`

### `copy`

Fuzzy-select a window target and copy it to clipboard.

**Args:** `[target]`

### `sw` [alias: `switch`]

Switch to a window (fuzzy-select if no target).

**Args:** `[target]`

### `next`

Go to the next window.

**Args:** `[tmux_args...]`

### `prev`

Go to the previous window.

**Args:** `[tmux_args...]`

### `last`

Go to the last active window.

**Args:** `[tmux_args...]`

### `link`

Link a window to another session. Args passed to `tmux link-window`.

**Args:** `[tmux_args...]`

### `unlink`

Unlink a window from its session.

**Args:** `[target]`

### `info`

Show info about the current (or target) window.

**Args:** `[target]`

### `vsplit`

Apply `even-horizontal` layout to the current window (side-by-side panes).

### `hsplit`

Apply `even-vertical` layout to the current window (top/bottom panes).

### `layout`

Select a tmux layout by fuzzy name. Accepted names map to tmux layout strings (e.g., `horizontal`, `vertical`, `tiled`, `main_horizontal`, `main_vertical`, etc.).

**Args:** `[layout_name]`
# h-wtree

Manage git worktrees with fuzzy selection, tmux session switching, and size reporting.

## Usage

```
h wtree <subcommand> [args]
```

## Subcommands

### `ls` [alias: `list`]

Run `git worktree list`.

**Args:** `[git_args...]`

### `add`

Run `git worktree add`.

**Args:** `[git_args...]`

### `lock`

Run `git worktree lock`.

**Args:** `[git_args...]`

### `move`

Run `git worktree move`.

**Args:** `[git_args...]`

### `prune`

Run `git worktree prune`.

**Args:** `[git_args...]`

### `remove`

Run `git worktree remove`.

**Args:** `[git_args...]`

### `repair`

Run `git worktree repair`.

**Args:** `[git_args...]`

### `unlock`

Run `git worktree unlock`.

**Args:** `[git_args...]`

### `switch`

Fuzzy-select a worktree and open (or create) a tmux session named after the worktree directory, starting in that directory.

**Args:** `[path]`

### `select`

Fuzzy-select a worktree and print its path.

### `size`

List all worktrees with their disk usage from `du -sh`.

### `branch`

Print the branch for each worktree, or for specific paths.

**Args:** `[path...]`

### `copy`

Fuzzy-select a worktree and copy its path to clipboard.
# h

The main hiiro entry point — install, update, setup, and dispatch to all subcommands.

## Usage

```
h <subcommand> [options] [args]
h version [-a]
```

## Subcommands

### `version`

Print the installed hiiro version. With `-a`, print the version for every rbenv-managed Ruby.

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Show version for all rbenv Ruby versions | false |

### `install` [alias: `update`]

Install or update the hiiro gem via rbenv. With `-a`, updates across all rbenv Ruby versions in parallel.

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Update all rbenv Ruby versions | false |
| `--pre` | `-p` | Install pre-release version | false |

### `setup`

Copy hiiro bin scripts and plugins to `~/bin/` and `~/.config/hiiro/plugins/`. Renames `h-*` scripts to match the invocation prefix. Warns if `~/bin` is not in `$PATH`.

### `ping`

Print `pong`. Useful for testing that `h` is working.

### `alert`

Send a macOS notification via `terminal-notifier`. See `Hiiro::Notification` for option details.

**Options (passed via args):**

| Flag | Short | Description |
|---|---|---|
| `-m` | — | Message text |
| `-t` | — | Notification title |
| `-l` | — | Link to open on click |
| `-c` | — | Shell command to run on click |
| `-s` | — | Sound name |

### `queue`

Delegate to the `Hiiro::Queue` subcommands (`add`, `ls`, `run`, `watch`, `attach`, etc.). See the Queue section of CLAUDE.md for full details.

### `service` [alias: `svc`]

Delegate to `Hiiro::ServiceManager` subcommands (`ls`, `start`, `stop`, `attach`, `open`, etc.).

### `run`

Delegate to `Hiiro::RunnerTool` subcommands (`ls`, `add`, `rm`, `config`, and default run).

### `file`

Delegate to `Hiiro::AppFiles` subcommands (`ls`, `add`, `rm`, `edit`).

### `check_version`

Verify that the installed hiiro version matches an expected version string.

**Args:** `[expected_version]`

**Options:**

| Flag | Short | Description | Default |
|---|---|---|---|
| `--all` | `-a` | Check all rbenv versions | false |

### `delayed_update`

Poll RubyGems until an expected version appears, then run `h install -a`. Runs as a background task via `h bg run`. Sends a macOS notification when complete.

**Args:** `<expected_version>`

### `rnext`

Run `git rnext` (custom git alias for rebasing to the next commit).

**Args:** `[git_args...]`
