# Changelog

## [0.1.393] - 2026-10-12

### Added
- `h json` subcommand (`bin/h-json`)

## [0.1.392] - 2026-10-12

### Changed
- `add_cmd` accepts `opts`, `flags`, and `mopts` arrays for value options, boolean flags, and repeated value options. Existing definitions are reused, and new short names use the first available alphanumeric character in the full name.
- Automatic command definitions are registered for reuse by later commands. Existing boolean callers now use `flags`.

## [0.1.390] - 2026-10-07

### Added
- `Hiiro::Tuios` class and `Hiiro#tuios` accessor for TUIOS integration

## [0.1.387.pre.2] - 2026-10-01

### Changed
- publish script now uses the `sonnet` model alias instead of `claude-haiku-4-5` for commit plan and changelog generation

## [0.1.387.pre.1] - 2026-10-01

### Added
- `Hiiro::Extractor` value object for data extraction
- Support for Integer return values as exit codes from subcommand handlers

## Unreleased

### Changed
- Merged main (0.1.393): saved links, project aliases, command pins, and sounds are registry tables (`link`, `project`, the table named after the command, `sound`), the rows `h table` shows. `Hiiro::Link`, `Hiiro::Project`, and `Hiiro::PinRecord` are gone; `bin/h-link` wraps `RegistryEntry` rows in `LinkPresenter`, `Hiiro::Projects` reads table `project`, and the Pins plugin stores text (collections as JSON). `h db migrate` imports `links.yml`, `projects.yml`, `pins/*`, and `sounds.yml` into those tables with the same plan, ledger, and conflict rules; the retired `pins`, `links`, and `projects` SQLite tables are copied into the registry once at setup (`Hiiro::DB.import_legacy_tables!`) and left in place. `t use` stores the current task in table `t`. Boolean command options declared through `add_cmd` are now `flags:` (upstream `add_cmd` semantics: undeclared `opts:` are value options).
- From main: `h table`, `t ui`, `h project ui`, `h tuios ui`, the line editor with completing prompts, `h json`, `h strip ctrl`, `h registry` over the same rows as `h table`.

### Added
- `script/acceptance [-o OUT] [NN ...]`: rerunnable isolated end-to-end acceptance (scenarios in `script/acceptance.d/`): each scenario gets a disposable HOME with the default file database, data roots, gem home, a recording-fixture PATH, and `env -i`; every check prints its literal expected value before the command and records `pass`/`FAIL`/`incomplete` in `OUT/results.tsv`. Covers migration and reload, task context, owned launches, artifacts and recurring jobs, commit planning and PR snapshots, the picker in real terminal windows, the installed gem, and an unchanged live home. See README "End-to-end acceptance".
- Tests wait for or kill every child process (`test/support/child_guard.rb`): an `Open3`/`PTY.spawn` child running past `HIIRO_TEST_CHILD_LIMIT` seconds (default 300) is killed with its tree and fails its test, a test that leaves a descendant running fails, and the end of a run kills any left.
- `h encode` / `h decode` (clone-owned, from the installed filters): one `Hiiro::Codec` table for `base64`/`b64`, `base64url`/`b64url` (unpadded), `hex`/`base16`/`b16`, `uri`/`url`/`percent`, `form`/`query`, `html`/`html-entities`, `json`/`json-string`, `rot13`; input from a file, `-`, piped stdin, or the clipboard; binary-safe, no added newline; malformed input prints `Decode failed: ...` and exits 1 with no output.
- `h ruby iface` / `h iface rb` (clone-owned): one `Hiiro::TextInspection` over the groups `class`, `attributes`, `methods`, `accessmodifiers`, `tests`, `lets`, `hiiro`, and the aliases `all` and `iface` (the default); exact or unique-prefix group names, in-process patterns (no `rg`, no `/tmp/patterns`).
- `h audio` (`clips` over the `clip_to` preset, `length` with the old `*_length` names as aliases, `transcribe`/`xscribe` as a profile-configured adapter), `h screencap`, `h crop` (the amber-border Python adapter), and `h asciinema` (dated casts through `Hiiro::Cast`) are clone-owned recipes. The installed `audio map`/`times` debugger bodies are not ported.
- `~/.config/hiiro/profile.yml` (`Hiiro::Profile`): personal recipe policy with sections `casts` (`dir`, `editor`, `resume_args`), `screencap` (`out_dir`, `apps`), and `transcribe` (`command`, `model`); see [docs/README.md](docs/README.md#personal-profile).
- `h env add` / `h export add` take `--file PATH`.
- `h vim session|tmux` works again through an optional tmux adapter.
- One picker for command, file, task, project, branch, PR, and saved-information choices (`Hiiro::PickerScreen` on `Tui::Screen`): `/` search, Enter choose, Tab mark, `Ctrl-E` (configurable with `HIIRO_PICKER_EDIT_KEY`) to edit the listed rows and the picker's exclusion rules in `$EDITOR`, a preview of every newly excluded or restored item before anything is saved, `Ctrl-X` for the excluded rows with their rules, and `u` to restore one. Deleting a row adds an exact rule for that item's stable identity, and only rows in the edited snapshot can be excluded that way. Group rules need an explicit mode (`literal`, `substring`, `regex`, `glob`, `extglob`) and field. Rules persist in SQLite (`picker_exclusions`, exported with the other owned records) per picker and scope (`picker`, `task`, `project`, `global`), and apply to later searches and invocations. Invalid documents save nothing and keep the edited text under `~/.local/share/hiiro/edits/`. Pruning hides choices only. See `docs/picker.md`.
- An ambiguous `h edit NAME` / `h bin edit NAME` on a terminal offers the matching commands (identified by kind, name, and source) instead of failing.
- `h schedule` (`ls`, `plan`, `enable`, `disable`, `run`, `status`, `ui`): recurring work from `~/.config/hiiro/schedules.yml` (jobs `reminders`, `queue`, `pr-monitor`, `command`, and each `~/ai/loops/NAME` recipe as `loop-NAME`), interval or wall-clock (`at:`, `timezone:`) recurrence with a `missed:` policy, `max_concurrent`, and `timeout`. Nothing is registered until `enable`, which writes one owned launchd plist (`com.hiiro.schedule.NAME`) and bootstraps it; a failed bootstrap removes the plist and leaves the schedule disabled; `disable` boots out and removes only that plist. Every run claims its occurrence once (`job_claims`) and records one outcome in `job_outcomes`: `completed`, `failed`, `interrupted`, `startup-failed`, `stale-owner`, or `skipped-overlap`, with exit status or signal, times, context, the retained log of a failed run, and artifact paths. Opt-in `notify: failures|always` records whether delivery worked without changing the outcome.
- `h queue tick [--max N]`: one bounded, locked pass that settles running entries whose process is gone, then launches the oldest pending entries detached (`omp -p`) up to N, with each run's output in `NAME.log` beside the settled entry. A queue schedule must say `agent: true`.
- `h schedule ui` / `h loop ui`: outcome screen whose background refresh keeps the search query, selected row, and scroll (`Tui::Screen#refresh_interval`, `#refresh!`, `#replace_items`).
- `h notify claude setup|reset_hooks --dry-run`.
- `h save --bundle` / `--task TASK [--label LABEL]` and `h context save|tmp|img|tmpimage --task TASK` attach the file they just captured (no second clipboard read) to the current context bundle and/or a task's `file` resources. TASK is an exact name, unique prefix, or `.`; unknown or ambiguous tasks fail before the clipboard is read. Repeats keep one association per destination and never change task status. A failed attachment after a successful capture keeps the file, names it on stderr, and exits 2.
- `h obsidian copy`, `h docs copy`, and `h docs url` (with `--all` for every match).

### Changed
- `h strip ctrl` replaces bare `h strip` for stripping ASCII terminal escapes and C0/DEL controls from files, stdin, or text. Tabs, line feeds, UTF-8 text, and raw invalid bytes are preserved.
- `hiiro` is the long name of `h`: `exe/hiiro` registers the same `RootCommands` (all root commands, not a four-command copy) and no longer asks for the missing `Tasks` plugin, so it prints no `unable to load plugin` line. `hiiro setup` still installs `hiiro-NAME`.
- Product scope is stated in the docs: `h dotenv copy_to` reports differences and missing names against the last file and copies nothing; `h sign` inspects and verifies code signatures and never signs (new `docs/h-dotenv.md`, `docs/h-sign.md`). `h jumplist` is documented as optional tmux integration. `examples/` is neither dispatched nor installed.
- `h date` and `h time` are one set of registrations (`Hiiro::TimeCommands`) over `TimeInput`/`Duration`; outputs, aliases, and usage errors are unchanged (`h date from_unix 0 -u` → `1970-01-01T00:00:00.000Z`, `h time from_unix 0 -u` → `00:00:00.000`, `diff 120 0` → `-2m`).
- `h video`'s repeated verbs are registered from one preset table (`Hiiro::Media::PRESETS`) with one output-naming rule; argv, codecs, quality, scale, seek placement, copy versus re-encode, and default output names are unchanged. A missing argument is a one-line error instead of a backtrace. `h mermaid png|svg` share one registration and exit 1 when an item fails.
- `h env add` and `h export add` write through one `Hiiro::EnvironmentAssignment`: `--file`, else `~/.zshenv.d/vars.zsh` when it exists, else `~/.zshenv`; values are literal (`"`, `\`, `$`, backticks escaped), newlines refused, files appended with their mode kept (new files `0600`). `h export add` no longer rewrites `~/.zshrc` or lets the shell evaluate `$`/backticks.
- `h home`, `h dotfiles`, `h vim`, and `h plugin` share `Hiiro::DirectoryProfile` (root, default action, specialised actions) over a taskless `TaskLocation`. `path` prints the configured root without a newline; `h home abspath` prints the real path. `h config` registers `herdr` once and `h config git` accepts extra arguments.
- `h commit select` and `h sha select|show|copy` read commits through `Hiiro::CommitLog` and choose in one `commits` picker (new `commit` family, identity `[commit, repo, sha]`); `sk`, `fuzzyfind_from_map`, and the shelled-out `h sha select` are gone. `h commit` prints the SHA with a newline, `h sha` without.
- `h pm` queues its prompt in process as `pm-SUBCMD[-ARGS]` (no `h queue add` subprocess), chooses the default command with the `pm-commands` picker, and exits 0.
- `h crop` no longer claims an exact 16:9 snap (dimensions are only made even) and its help states the real `--tolerance` default (60).

- `h branch select|copy|co|rm|clean`, `h pr select|copy|track|diff|untrack|fix|from-template` and the `pr` resolver, `h project select|copy|open` and the project resolver, task choice in `t` and the legacy task manager, `t file|dir|doc|link open`, `h registry select` / `Hiiro#registry_pick`, `h link`, `h obsidian`, `h docs`, and `h save` choose through the shared picker instead of `sk`/`fzf`. `h branch select|copy TERMS` keeps branches containing every term (the old filter called an undefined method). Every choice returns its record; nothing parses the displayed row.
- Removed: `RegistryEntry.fuzzy_lines` and the column splitting in `h registry select` and `Hiiro#registry_pick` (`RegistryEntry#fuzzy_line` is now `#picker_label`, display only), `Fuzzyfind.select_index`, and the direct `sk` calls in `h branch`.
- `h remind check` claims each reminder occurrence, so overlapping checks notify once; it delivers synchronously and advances the checkpoint only after `terminal-notifier` succeeded. A failed delivery is recorded as `failed`, stays due, is retried by the next check, and makes `check` exit 1. `howto` describes the schedule instead of a crontab line.
- `h loop` runs each cycle as an owned schedule run (`start`/`stop` enable and disable `loop-NAME`; new `run`). A prompt loop needs an explicit `agent:` argv (or a deterministic `command:`); permission-bypass flags are refused. `ls`, `status`/`prs`/`slack`, and `render` read recorded outcomes and logs; `render` no longer adds a self-reloading meta refresh. Existing `config.yml` recipes keep their prompts.
- `h notify claude setup` appends only Hiiro's two hook entries when missing and keeps every other event, group, and hook (it replaced the `Notification` and `Stop` arrays); `reset_hooks` removes only those entries and the groups they leave empty. Invalid settings JSON is refused instead of being overwritten.
- `h pr-monitor` can run as a `pr-monitor` schedule (one `--once` cycle per run).
- Removed: `h queue watch` (foreground polling loop that re-`exec`ed itself on new versions), `h loop tmux`, the loops tmux session, `claude --dangerously-skip-permissions` launches, the instruction asking each loop agent to write `status.json` and run `h-loop render`, and every `status.json`/`info.json` reader.
- One capture path (`Hiiro::Clipboard` adapters + `Hiiro::Artifact`) behind `h save`, `h img`, `h context`, `h note save`, and `h link paste`. Clipboard bytes are written unchanged and the path is printed only after the write. An empty clipboard, missing `pngpaste`, a failing clipboard tool, and an unwritable destination are distinct errors that write nothing; a failing `pngpaste` no longer falls back to saving text, and `h img save` never saves text.
- `h img save PATH`, `h context save|img NAME`, and `h note save FILE` refuse to replace an existing file unless `--force` (they silently overwrote). `h save` keeps its `-2`, `-3` suffixes and now creates each name exclusively.
- `h context open` (alias `edit`) edits a copy of the manifest: every line must name an existing path and the manifest must not have changed meanwhile, else it is left alone and the edited text is kept under `~/.local/share/hiiro/edits/`. A failing editor or emptied text cancels.
- `h link select|copy|open`, `h obsidian select|url|open|copy`, and `h docs open|url|copy|rm` pick through `Hiiro::Selection` and the shared picker, so the chosen original record (link id, vault-relative note, Portfolio id) is returned even when labels are equal. `h link open TERMS` offers several matches to the picker instead of reporting not found. Opening or copying exits 1 when the opener or `pbcopy` fails.
- URL placeholder values and `h link edit` are edited through `InputFile`: invalid YAML or fields exit 1 with the edited text kept under `~/.local/share/hiiro/edits/`; an unchanged template cancels.

- `tools.yml` commands are `argv: [...]` (with `[FILENAMES]` as one element, expanded to one argument per file) or authored `shell:` text that receives the files as `"$@"`. The old `command:` strings are refused until the new `h run migrate` converts them (plain commands become argv, shell commands keep their text with `[FILENAMES]` → `"$@"`, quoted or embedded uses are left for a manual edit) after copying tools.yml to a timestamped `.bak`. A file starting with `-` is passed as `./-name` unless `--` precedes `[FILENAMES]`.
- `h run` reports every selected tool as succeeded, failed, interrupted, or skipped, keeps running after a failure, stops on Ctrl-C, and exits with the first failure's status (130 when interrupted) instead of always 0. No matching tools and an unknown variation are errors before anything runs; Git failures (not a repository, no merge base with `main`) are errors instead of "no matching files". Renames pass their new path; deleted files are not passed.
- Failed and interrupted `h run` / `h js all` / `h ch make` logs are kept under `~/.local/share/hiiro/captures/validation/RUN_ID/` as `h capture` rows with the command, cwd, run id, times, exit status or signal, task, and context provenance; succeeded logs are deleted. New `h run queue [RUN_ID]` writes a pending queue prompt naming those logs with the run's task/app/dir; it never launches an agent.
- `h js all` runs its four yarn checks through the same runner in the current directory and exits nonzero when one fails (it exited 0); failed logs no longer go to `~/notes/files`.
- `h ch make` streams the build to the terminal and a log (it only went to a temp file) and exits with the build's status; `h ch run` runs `open` in the foreground.
- `h capture` rows record the cwd, run id, times, outcome (`interrupted` when Ctrl-C arrived), and signal. A closed output pipe (`h capture … | head`) no longer stops the capture; the file still gets every byte and the child's status is kept.
- Removed `Shell.stream` / `stream_combined` / `Result.collect_chunks` (they buffered all output in memory) and `Git#dirty_files`; streaming goes through `Capture.stream`.
- `h pr` single and bulk actions are one implementation (`Hiiro::PrActions`): targets are resolved to `owner/name#N` first, then fields are validated for every target before anything runs, and each target prints its own `✓`/`✗` outcome; any failure exits 1. `mopen`, `mmerge`, `mready`, `mto-draft`, `mcomment`, `mfix`, `mrm`, and the new `msync` share one YAML selection (`prs:` plus the action's fields). An editor that fails, an empty file, or an unchanged document cancels; invalid YAML or fields exit 1; `prs: []` does nothing. `mrm` selects by reference instead of row id. `prune`, `ls -d`, and the fuzzy-picked forms use the same actions.
- `h pr merge` accepts only `--merge`, `--squash`, `--rebase`, and `-d`/`--delete-branch`; anything else is refused before `gh` runs. `h pr open` goes through `gh pr view --web` with the PR URL. `h pr comment` takes `-b TEXT` or an editor; an empty comment is an error.
- `h pr check`/`watch`/`fwatch` run native `gh pr checks` with the PR URL on the terminal and exit with gh's own status (130 when interrupted, without a notification). A nonzero exit is reported as failing only when a fresh snapshot shows a failed check; otherwise `unknown`. Notifications go through the `h alert` adapter (`terminal-notifier`); the `say` call and hard-coded notifier path are gone.
- `h pr-monitor` watches tracked open PRs through the snapshot refresh instead of parsing `gh pr status`. The first cycle records a baseline; later cycles notify check, review, and dependency transitions once, from checkpoints keyed by repository, number, channel, head revision, and state in the `pr_monitor_checkpoints` table, so restarts do not repeat them and a new head is a new event. Stale, incomplete, or unknown observations never produce passing or approval events. `--queue-fixes` queues one fix job per failing head and never launches it; `--mark-ready` needs a fresh, complete, passing head. Dependency completion only notifies. New `--once`, `--interval`, `--tag`, and `--no-notify-dependencies`.
- `h cpr [-C DIR] SUBCOMMAND ...` resolves the current branch's PR in the selected directory and passes it to `h pr` out of band (`HIIRO_PR_CURRENT`), so nested commands (`h cpr dep add team/two#5`, `h cpr merge --squash`) keep their grammar. No PR for the branch exits 1 and never falls back to another repository's same-number PR.
- `h pr fix`/`mfix` queue jobs named `pr-fix-OWNER-NAME-N-HEAD7` whose frontmatter and body carry the PR URL, head revision, snapshot completeness, and failing checks, plus the PR's task, tree, and workspace.
- `h pr` keeps one repository-qualified snapshot per tracked PR: head revision, fetch time, raw checks and reviews with completeness, and `fresh` / `stale` / `unknown` freshness, separate from local tags, task, dependencies, and tracking. Lists, `update`, `track`, and `status` share one repository-batched refresh; output names PRs as `owner/name#N`.
- `h pr dep` stores dependencies as `owner/name#N`; legacy numbers are qualified at startup only when unambiguous and are otherwise kept and reported by `dep ls`.
- The ISC code freeze is applied as a policy when checks are counted; GitHub's raw contexts are stored unchanged and `ls -C` shows both. When `isc` is unavailable GitHub's state stands (it was previously forced to success).

### Fixed
- `h pr track` records the task (and its worktree) of the directory it runs in, and `h pr for-task` with no name lists the current directory's task; both named an undefined top-level `Environment`, so `track` stored no task and `for-task` always asked for a name.
- `h save` inbox names stop at `-1000`: the candidate list was endless, so a write error mistaken for a taken name could spin forever (an orphaned `h save` from a test once ran at 80% CPU for hours). All names taken now fails with `PATH already exists`.
- A detached owned launch (`h bg run`, a detached `h service start`) no longer keeps the caller's stdout and stderr open: the supervisor and child write `~/.local/share/hiiro/runs/RUN_ID.log`, so `out=$(h service start web)` or `h bg run ... | cat` returns once the child has started instead of waiting for it to exit.
- `t sh TASK CMD` with a CMD that cannot start prints `ERROR: Could not run CMD: REASON` and exits 1 instead of a Ruby backtrace.
- `test/bin/asciinema_test.rb` no longer depends on asciinema replaying the recorded event (asciinema 3.2.1 sometimes prints only its banners); it asserts the cast bytes and which cast `play` chose.
- `h html vids` (missing `require "digest"`) and the spurious Tmux plugin warning in `h jsonl`.
- `h note save FILE TEXT...` saves TEXT (it always read the clipboard) and no longer leaves an empty temp file in the system temp directory.
- `h context rm 0` no longer removes the last bundle entry.
- `h pr attach` no longer stages everything, makes a `WIP` commit, or checks out the PR branch: it opens a tab in the task's directory and leaves HEAD, the index, files, and branches as they were. It also finds the task again (it named a top-level `Environment` that hiiro never defines, so it always reported no workspace).
- `h pr to-draft`/`mto-draft` call `gh pr ready --undo` (the `--draft` flag they passed does not exist).
- `h pr-monitor` no longer opens a browser when checks pass and no longer links every PR to one hard-coded repository.
- `h pr` refresh now pages reviews (previously only the last 50) as well as checks, re-reads the head on every page, and never combines pages from two heads. A failed page, malformed output, partial GraphQL errors, or a repeated cursor leaves the snapshot incomplete instead of complete.
- A failed refresh keeps the last observation and marks it `stale`; incomplete, stale, and unknown snapshots are never `green`.
- A refresh no longer overwrites tags, task, or dependency changes made while it runs, does not replace a newer snapshot, and does not recreate an untracked PR.
- PRs without a repository are no longer fetched from a hard-coded default repository; a bare number that matches PRs in two repositories is an error, and a dependency number is no longer matched against any repository.
- `h git commit` no longer touches the real index while planning: `-n`, a cancelled confirmation, an invalid plan, or a failing planner leave index bytes, staged changes, `HEAD`, and working files unchanged (the old snapshot ran `git add -A` + `git reset` and dropped the staging selection, even on a dry run).
- `h git commit` rejects plans with unknown, duplicated, or missing paths, empty messages, or bad JSON before staging anything, and fails when the planner exits nonzero or cannot start.
- `h git commit` stops at the first failing `git add`, commit, or hook with exit 1, reports completed commits, and never runs later groups; each commit contains only its group, and the remaining paths keep their staging. `-y`/`--yes` and the `[y/N]` confirmation now exist as documented. Files with both staged and unstaged changes are committed whole only with the new `-w`/`--whole-files`; renames, deletions, untracked files, and unusual file names are handled exactly.
- `script/publish` commits its release plan through the same validated path; an unusable plan or a failed commit aborts the publish instead of falling back to one catch-all commit.
- Fix `PsProcess::Snapshot.capture` constant lookup, which raised `NameError` in `h ps byport`, `h ps indir`, and parent/child process lookups.
- Optional context resolution no longer hides ambiguity, and scoped Git commands honor their supplied directory.
- Queue entries move to `done/` only when the agent exits 0; the launcher previously read an unexported `HQ_EXIT` and filed every finished entry as done.
- `h capture` exits with the captured command's status (128 + signal when killed), passes stdin through untouched, and records `127` for a command that cannot start.
- `h bg` reports launch failures instead of returning nil, and concurrent launches no longer type into the same idle pane.
- Herdr `new_tab` / `split_pane` with a command raise when Herdr does not run it.
- Executable discovery reads `PATH` when a command runs instead of at load, honors empty and relative entries, and ignores directories, non-executables, and broken links. Same-name copies later in `PATH` no longer make a prefix ambiguous; dispatch, help, and edit pick the same file.
- `h bin edit NAME` no longer opens non-Hiiro executables named `NAME`, and `h edit NAME` opens the command `NAME` dispatches to instead of the `h` script.
- The invocation `command` column records the full root command line (it dropped the subcommand).

### Added
- `h herdr` and `hh` pane controls for Vim-style focus, two-pane reflow, resize, swap, and zoom
- `prefix+shift+h/j/k/l` reflows a two-pane tab toward an edge; `prefix+alt+h/j/k/l` resizes the current pane
- `h db manifest`, inspectable `plan`, explicit owned-store `migrate`, and typed canonical `export`/`restore` with IDs, relations, import verification, and allocator state. Exports refuse existing destinations; recovery rejects conflicting later writes.
- `Hiiro::OwnedRun`: launch requests, durable run records (`~/.local/share/hiiro/runs/`), an allocated/started/ready/completed/failed state machine, a supervisor that records pid, start time, and actual exit status or signal, and process identity checks that reject reused pids. See `docs/owned-runs.md`.
- `CommandSpecification.shell` keeps authored shell text distinct from argv; `Hiiro::ProcessOutcome` separates signals from exit codes.
- Service `ready:` probes and `stop_timeout:`; `h bg ls` lists background runs with their outcomes.
- `Hiiro::Catalog`: one command table (name, kind, source, aliases, shadowed claims) used by dispatch, help, `edit`, and the new `h bin complete` / `h bin docs [--json]`. Aliases from `add_subcmd(:service, :svc)` resolve to one entry.
- `Hiiro::Runtime` and `hiiro/persistence`: persistence, invocation history, and task auto-tagging start on first persistent use; frames pass to external commands through `HIIRO_INVOCATION_FRAMES` so one root invocation keeps ordered resolutions across processes.
- `t --help`, `t todo --help`, and `t tree --help` print help before any task lookup.
- Managed installation (`Hiiro::Install`): an install manifest (`~/.config/hiiro/install-manifest.json`) records each destination hiiro wrote with source, package version and root, SHA-256, mode, and source link. `h setup` prints a read-only plan (`missing`, `unchanged`, `updatable`, `user-modified`, `collision`, `obsolete`); `--apply`, `--retire`, and `--adopt NAME` act on selected entries. Commands load supporting files from `bin/lib/`, installed beside them.
- Catalog entries carry an origin (`managed hiiro VERSION`, `modified (managed ...)`, `package hiiro VERSION`, `user`) in `h bin list`, `h bin docs [--json]`, and `h edit`.
- The gem ships the `h mcp` implementation (`require 'hiiro/mcp'`: `MCPRegistry`, `MCPCatalog`, `MCPCommands`, `MCPSync`) and its behavioral tests (`test/bin/mcp_test.rb`), with `docs/h-mcp.md`. `h db manifest`, `export`, and `restore` include the `mcps` table.

### Changed
- Mutable domain records use SQLite without live YAML mirrors. `t`, `tt`, and `h todo` share database-owned todo IDs and targeted mutations.
- Pins preserve strings, numbers, booleans, and collections as distinct types. Named pane-home updates retain omitted fields and unrelated homes.
- Reminder CRUD, recurrence checkpoints, pause/resume, cleanup, and bulk edits use canonical SQLite rows with stable IDs.
- Task metadata, resources, project aliases, app mappings, saved links, branches, and tags use targeted database operations. Definitions, preferences, runtime files, and ordinary artifacts remain file-owned.
- Legacy imports retain source bytes and verify selected records. Repeating accepted sources preserves later canonical changes and deletions; explicit restore can recreate exported deleted rows.
- Database-backed editors use temporary projections and reject failed editors, invalid input, and conflicting changes without partial writes.
- TaskLocation carries one optional task/app/project context, root/effective directory, separate provenance, and calling-terminal IDs through root/task/app workflows. Project/home operations require no task.
- Exact names precede unique prefixes; terminal ambiguity uses original-object pickers, while non-interactive ambiguity/stale/missing targets fail before launch. Native arguments and explicit calling panes remain intact.
- Queue normal and pane launch share strict frontmatter resolution; service definitions/env preparation, scoped Git/tool discovery, and root-relative tracked files reuse the selected context.
- Queue launches claim entries atomically, print `Launched:` only after the agent started, and leave allocation/start failures in `failed/` with the error; `kill` signals only the verified process and waits for its exit. Agent completion never changes task status.
- Services run as instances keyed by definition, directory, task, and variations, each with its own run and scripts. Stop signals the verified process group (or runs `stop` with the real `$PID`), waits for the observed exit, and only then cleans up; unowned legacy records are not stopped by label.
- Background commands reserve their Herdr pane under a lock and release it when the run finishes or fails.
- `require 'hiiro'` loads only the framework; domain classes autoload. Import, registration, help, completion, and docs create no database, history, tags, or config/plugin directories. Operations that never use persistence are not recorded.
- Plugins load only when a command names them (`plugins: [:Pins]`), from `~/.config/hiiro/plugins/` then the gem's `plugins/`. `Config.config_dir` and `plugin_dir` no longer create directories; the database directory is created when the database is first opened.
- Root `h` commands live in `Hiiro::RootCommands` (`lib/hiiro/root_commands.rb`); `exe/h` runs them and `h bin` reads them. Root `service`/`run`/`file` mounts resolve task context on first use, so their help needs no task.
- `h bin list` prints catalog entries (kind, source, shadowed claims) for prefixes rather than raw `h-NAME`/`NAME` PATH matches.
- `h setup` / `hiiro setup` no longer copy over existing files: without `--apply` they only plan; apply writes missing files and unmodified managed ones, rechecks each destination first, replaces by rename (never through a link), records ownership only for writes that landed, and exits 1 on a failed write.
- `h update` (and `script/publish`, `script/update`) installs the gem in each compatible Ruby independently, then applies shared assets once from the Ruby with the newest installed hiiro and names that source; it exits 1 when any Ruby failed. `h update` reads its own arguments (it parsed the process `ARGV`). `h delayed_update VERSION` runs `h update -a --wait VERSION --notify` in the background. RubyGems polling for publish, `script/available`, and `--wait` is one `Hiiro::Rollout::RubyGems`.
- `script/install`, `script/compare`, and `script/sync` read the same plan instead of rsync, `diff -qrs` copy commands, and interactive copies in both directions.
- `bin/h-mcp` no longer needs `lib/h_mcp_catalog.rb` / `lib/h_mcp_registry.rb` beside it, and installs without support files. The gem declares `mcp ~> 1.5`, `faraday`, and `event_stream_parser`. Registrations, saved catalogs, the `mcp_json_catalogs_to_sqlite` marker, legacy JSON backups, and `mcp-sync` ownership are unchanged.

### Removed
- `h otask`, `h osubtask`, `h zosubtask`: they needed the `Tmux`, `OldTask`, and `Task` plugins the package stopped shipping in February 2026 (`h osubtask`/`h zosubtask` raised `NoMethodError`). Use `t`; see `docs/h-task.md#removed-legacy-task-commands`. Task rows, `tasks.metadata_json` (saved windows, `saved_at`), and `assignments` are unchanged.
- The uncalled inline `h task`/`h subtask` grammar `Hiiro::Tasks`, `Hiiro::FallbackTarget`, `Task#display_data`, and the `TaskManager` actions only it used (`start_task`, `switch_to_task`, `stop_task`, `resume_task`, `task_from_worktree`, `filter_tasks`, `list`, `status`, `save`, app/branch/cd helpers, interactive selectors, `add_resolvers`) and the writers `TaskManager::Config#create_task` / `#attach_tree`. `TaskManager#create_tree`, `#apply_sparse_checkout`, `#tasks`, `Config#tasks` / `#apps` / `#detach_tree`, `Tree`, `Task`, `App`, `SparseGroups`, and `Environment` remain.
- `h .config` (its `herdr` handler did nothing; use `h config herdr`), `h dsstore` (empty), `h uri decode` (printed a Python one-liner; use `h decode uri`), `h tags` (stopped in `binding.pry`; use `h branch tags`, `h pr tags`, `h link tags`, or `h db q`), and `h buffer` (its tmux library was removed with the Herdr adoption, so it raised `NameError`; use `tmux list-buffers` / `show-buffer`).
- `bin/h-demo` and `bin/h-dsstore-read` moved to `examples/h-demo` and `examples/dsstore-read` (now `#!/usr/bin/env python3` instead of a personal virtualenv); they are no longer commands or installed assets.
- `h pr review`/`cr` (it checked out master and could create a worktree, then only printed numbers), the per-action `m*` copies, `PinnedPRManager#pr_yaml_lines`, `Git::Pr#view`/`#checkout`/`#merge`/`#close`/`#reopen`, the backtick `Git::Pr.current`, `h pr number`'s text parsing, and `h pr-monitor`'s `gh pr status` parser and `pr_approved`/`pr_passing`/`pr_failing`/`pr_pending`/`pr_publishing` helper calls.
- Automatic legacy domain YAML import and mutable-record dual writers. Legacy sources remain explicit retained recovery inputs.
- Obsolete todo file-path, saved-link snapshot, and task YAML backup APIs; `h db remigrate`, broad YAML retirement, and YAML/tar restore.
- Conflicting first-match Environment/task/app/project selectors and queue pane-directory fallback joins.
- Per-entry queue `.sh` launchers and the service launcher's `trap 'h service reset'`; the run supervisor owns completion.
- The two setup copy loops (`exe/h` root commands and `exe/hiiro`), the per-Ruby `h setup` inside every gem install, `RootCommands.update_hiiro`, the generated `/tmp/h-delayed-update-*.rb` poller, and the RubyGems pollers in `script/publish` and `script/available`.
- `Hiiro.load_env`, eager plugin requiring at import, `Config.plugin_files`, `Invocation.record!`, the Runners PATH glob and its prefix/ambiguity helpers, and `Runners::Bin` / `Subcommand` `match?` / `exact_match?`.

## [0.1.384] - 2026-09-23

### Added
- `h plist` command for working with property lists

### Fixed
- publish script now requires hiiro unconditionally at startup instead of only when falling back to local version

## [0.1.381] - 2026-09-20

### Added
- `Hiiro::Options` now includes file/directory filtering methods: `files`, `dirs`, `file_or_dirs`, `not_files`, and `not_file_or_dirs` for convenient argument classification

## [0.1.377] - 2026-09-17

### Changed
- `h save` redesigned with slug-based filenames (`<timestamp>-<slug>.txt` / `<timestamp>-image.png`), image handling via `pngpaste`, and environment-configurable destination via `HIIRO_SAVED_DIR`

### Added
- `h save` subcommands: `ls`/`list`, `dir`, `show`/`cat`, `copy`, `open`, `edit`, `rm`/`remove` for managing saved files
- `t path`, `t cd`, `t start`, and `t switch` accept optional `APP` argument to select a configured relative directory beneath the task root
- APP resolves by exact name or unique case-sensitive prefix; fails when ambiguous or missing
- `t switch` / `t workspace` and `t cd` accept an optional APP positional (or `--app`) resolving through the apps registry by exact name or unique prefix; the workspace or pane cd targets the app directory under the task worktree, e.g. `t switch aldi cpm` opens `~/work/aldi/main/retailer-tools/content-page-migrator`

## [0.1.376] - 2026-09-14

### Changed
- Herdr `hiiro.nvim` action opens bare `nvim` in the calling pane's working directory instead of the task notes home

## [0.1.375] - 2026-09-14

### Changed
- `t switch`, `t tab open`, and `t pane open` no longer default to the current task; with no destination they open the picker (tasks, workspaces, panes, or tabs) and fail non-interactively. `.` still means the current task

## [0.1.374] - 2026-09-14

### Changed
- `h alert` plays sounds through terminal-notifier's `-sound` (macOS system sound names, `none` for silent, `-S` accepted as an alias for `-s`) instead of a separate `afplay` process

### Removed
- Support for custom sound files in `~/.config/hiiro/sounds/`

## [0.1.372] - 2026-09-14

### Changed
- `h bg run` reuses an idle shell pane in the `h-bg` workspace and opens a new tab only when every pane is busy, instead of one tab per command

## [0.1.371] - 2026-09-14

### Added
- `t ls` lists the panes under every open workspace with directory, agent state, and foreground command via `herdr pane process-info`; `t switch` accepts an exact pane ID and its picker includes panes
- `Hiiro::Herdr#process_info` and `Pane#foreground_command`

## [0.1.370] - 2026-09-14

### Added
- `t ls` marks tasks with an open Herdr workspace with `@` and lists workspaces that belong to no task

## [0.1.369] - 2026-09-14

### Added
- `t switch NAME` matches live Herdr workspaces that belong to no task, and the fuzzy finder for `switch` lists tasks plus those workspaces, numbering duplicate workspace names
- `t` opens the fuzzy finder instead of failing when a task prefix is ambiguous or no current task can be resolved, when stdin is a terminal

## [0.1.368] - 2026-09-14

### Added
- `h herdr`: Herdr plugin exposing `t` through keybound popups for fuzzy task switching, todo capture, todo copying, task shell, and nvim access; `h herdr install` copies and links the plugin, `h herdr keys` prints keybindings

### Changed
- Task CLI grammar converted to command-first: `t COMMAND [TASK] [ARGS...]` matching the legacy `h task` rule where the first positional word is the task when it names one (exact or unique prefix), otherwise the current task is used and the word stays in the payload

### Removed
- `Hiiro::TaskScope` class; task resolution logic integrated into `Hiiro::TaskCli`

## [0.1.367] - 2026-09-14

### Added
- `t use TASK` (alias `pin`) saves the fallback task; `t current` now only prints
- `-t TASK` / `-f` task options on every `t` command that acts on a task
- `h herdr`: a Herdr plugin (`herdr-plugin/herdr-plugin.toml`) with actions `hiiro.switch`, `hiiro.todo-add`, `hiiro.todos`, `hiiro.shell`, and `hiiro.nvim` that open a popup running `t`; `h herdr install` copies and links it, `h herdr keys` prints keybindings
- `Hiiro::TestHarness` understands `add_cmd`, `add_option`, `add_flag`, and `opts`
- `t TASK todo show ID` and `tt TASK show ID` print one todo's text; `todo ls --plain` prints text only
- Add `h env add NAME VALUE` and `h alias add NAME COMMAND...` to append safely quoted shell definitions, preferring existing zsh module files and falling back to the root dotfiles. Use native Hiiro options, including `opts.global` and `--`.
- Add `h bin add NAME [COMMAND ...]` to generate executable `Hiiro.run` templates with optional empty `add_cmd` blocks. Serialize command names as Ruby symbols and refuse existing files or symlinks.
- `t ls` and `t list` root commands list tasks like bare `t`
- `Hiiro::Error`: `Hiiro#run` prints only `ERROR: message` for it, no backtrace
- `builtin_commands: false` option for `Hiiro.run`/`run_child` to skip the automatic `pry` and `edit` commands
- `Hiiro#open_default(target)` opens a path or URL with `open`/`xdg-open`
- `t` and `tt` are gem executables (`exe/t`, `exe/tt`) installed with Hiiro
- `t TASK tree new|rm|resume`, `t TASK tree`, `t TASK path`, `t TASK branch`, `t TASK sh`, and `t TASK cd` bring worktree and shell commands from `h task` into `t`; subtasks are `parent/child` names
- `Hiiro::CurrentTask`: one resolver for the current task (Herdr workspace, working directory, saved pin) used by `t` and by `Environment#task`
- `Hiiro::Git.repo_dir` so worktree commands work when `~/work/.git` is a gitfile pointing at the bare repo

### Fixed
- `h task start` and worktree listing failed with "Not a directory" when `~/work/.git` is a gitfile; git now runs in the parent directory

### Changed
- `t` grammar is now command-first, `t COMMAND [TASK] [ARGS...]`, matching the old `h task` rule: the first positional word is the task when it names one (exact or unique prefix), otherwise the current task is used and the word stays in the payload. `.` is the current task, `-` selects orphan todos. `tt ...` is `t todo ...`. `Hiiro::TaskScope` is removed
- `t todo add` no longer creates tasks; only `t new NAME` does
- Move the task CLI into `lib/hiiro/task_cli.rb` (`Hiiro::TaskCli`); `exe/t` and `exe/tt` are thin `Hiiro.run` launchers and `bin/t`, `bin/tt` are symlinks
- `t` requires `hiiro` like other bins instead of editing the load path; `task_scope` and `task_sessions` load with `hiiro`
- `t` errors print without a backtrace; task, scope, and session errors subclass `Hiiro::Error`
- `t` saves the current task through the `PinRecord` model and resolves resources, documents, tabs, and panes with `Hiiro::Matcher`, accepting unique prefixes and offering fuzzyfind when no reference is given
- `tt` runs the todo scope in-process instead of exec'ing `t`
- `h task` is now a symlink to `t` (`bin/h-task` -> `exe/t`); the inline `h task` and `h subtask` subcommands are gone, and `h task start|stop|resume|switch|sh|cd|path|branch|todo` map to `t` commands (see docs/h-task.md)
- `Environment#task` also matches the working directory against task homes, primary directories, and registered directories
- `TaskManager#start_task` uses the extracted `create_tree`
- Task listing prints aligned columns with the open todo count after each name, e.g. `prez (3)`, plus `next:`/`waiting:` text
- `ls` and `list` are now reserved root words in `t`; tasks with those exact names need a unique prefix

## [0.1.366] - 2026-09-14

### Changed
- Implement task-first CLI syntax: `t TASK COMMAND...` replaces `t COMMAND [TASK]...`
- Task names now precede commands, appearing immediately after `t` or after a group
- Task resolution prefers exact names, then unique case-sensitive prefixes; ambiguous prefixes fail
- Move workspace command from `t workspace TASK` to `t TASK switch` (keep `workspace` as alias)
- Rename implicit task selection to explicit `.` reference; bare `t` lists all tasks without selecting
- Update `t current TASK` to `t TASK current`; explicit named selections save fallback after success
- Context resolution checks calling Herdr workspace, then current directory, then saved task; reject ambiguous matches

### Added
- Task todo management under `t TASK todo` with `add`, `rm`, `list`/`ls` subcommands; todos share existing database with `h todo`
- `tt TASK ...` shortcut delegates to `t TASK todo ...`; bare `tt` uses current task via `.` selection
- Orphan todo scope with `t - todo` and `tt -` for unassigned todos; `-` invalid outside todo commands
- Native AI session launches via `t TASK omp`, `codex`/`cdx`, and `claude`/`cld` for fresh tool instances
- Resume mode with first-argument prefix matching (e.g., `r`, `res`, `resume`); focuses unique running instance or launches native picker
- `Hiiro::TaskScope` library for named/current/orphan task reference resolution with cached context
- `Hiiro::TaskSessions` library for AI tool launch/resume dispatch with Herdr workspace integration
- New `lib/hiiro/task_scope.rb` and `lib/hiiro/task_sessions.rb` support libraries
- New `bin/tt` executable for todo shortcut

## [0.1.365] - 2026-09-13

### Added
- Add the `t` task CLI with `--task`/`-t` selection, durable task status and next actions, document homes, resource references, and Herdr workspace/tab/pane commands.
- Allow block-only command dispatch with `external_commands: false`, keeping legacy `t-*` executables out of the task CLI.
- Add `Hiiro::Herdr`, a JSON-backed adapter for Herdr workspaces, tabs, panes, notifications, and command execution.
- Persist Herdr workspace/tab/pane IDs for invocations, branches, queued prompts, services, and tracked PRs, with read fallbacks for legacy metadata.

### Changed
- Keep task command definitions and helpers in `~/bin/t`, using `add_cmd` and native Hiiro help instead of a library-level TaskCLI and custom help template.
- Preserve task records and resource references when detaching or pruning worktrees.
- Move task, project, queue, service, background, Claude, app navigation, PR attach, title, and notification workflows from tmux to Herdr.
- Keep `h session` and `h window` as compatibility commands for Herdr workspaces and tabs.

### Removed
- Remove tmux paste-buffer, jumplist, task-color, focus-hook, and arbitrary-layout features that Herdr 0.8.2 does not support.
- Remove the old `Hiiro::Tmux` adapter and tmux-specific command tests.
