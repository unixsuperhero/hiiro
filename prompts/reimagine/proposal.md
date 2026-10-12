# Reimagining Hiiro as a smaller, systematized tool

This is a snapshot of the original documentation-only study, copied into the redesign workspace. Source links now point into this clone where applicable. Statements about unchanged files and research-only verification describe that original study, not later implementation.

Design thoughts, 2026-10-12. No implementation changes.

## My recommendation

Keep Ruby. Keep the short commands. Rewrite the parts that repeatedly resolve context, own persistent data, launch processes, and interpret remote state. Do not rewrite every useful wrapper or replace native tools.

Hiiro currently combines a reusable CLI framework, a workstation workflow application, and personal integrations. Those are different responsibilities. They can remain in one repository and one gem, but importing the framework should not initialize the workstation application.

The goal is fewer independent implementations, fewer competing sources of truth, and fewer manual handoffs. Fewer command names are secondary. A one-line native wrapper can be cheaper to maintain than a generic system that absorbs it.

My first substantial rewrite would be data ownership. My next would be context and launch orchestration. Command discovery and installation also deserve a focused rewrite because they determine which implementation actually runs.

## What the research establishes

Seven successful read-only subagent slices covered command inventory, framework and persistence, task/runtime workflows, Git/PR workflows, utilities, installed-local extensions, and MCP support. A deterministic Ruby scan verified 81 entry paths under `bin/`, including 77 `h-*` names, plus four `exe/` entry paths. Four bin paths are symlinks, not separate implementations.

A separate executable-only PATH scan found 98 distinct external `h-*` names, including 21 names absent from the source checkout. This is a shell snapshot, not proof of the dispatcher's winner or the contents of every historical gem installation.

The most important completed consolidations are already present:

- `t` and `h task` share `TaskCli`. `tt` mounts its todo grammar. Do not repeat that migration.
- Pane, tab, workspace, task-launch, and several notification flows already use Herdr. Some older tmux-specific utilities remain separate.
- `TaskLocation`, `CurrentTask`, `CommandSpecification`, `EditedDocument`, `CheckSummary`, `PullRequestReference`, `BranchComparison`, and service/environment definitions already model useful concepts.
- Queue, service, runner, and tracked-file commands already reuse command builders across root and app mounts.

Sources: [task reference](../../docs/t.md), [task launchers](../../exe/t), [framework](../../lib/hiiro.rb), [service definitions](../../lib/hiiro/service_definition.rb).

This is a design study, not a runtime bug audit. No Hiiro invocation, migration, service launch, test suite, Git mutation, or remote API call was run. Hiiro startup can write history, initialize schemas, import files, and auto-tag branches, so using it for inventory would violate the read-only request. Source-derived failure risks below are marked `[INFERENCE]`. Usage frequency, latency, migration state, and savings were not measured.

## Separate the framework from the workstation application

Today [lib/hiiro.rb](../../lib/hiiro.rb), lines 1-61 and 80-130, loads workstation domains and initializes the database/history before dispatch. [db.rb](../../lib/hiiro/db.rb), lines 468-474, opens a database at require time. Plugin discovery can create its directory. Root dispatch can also tag the current branch with the current task.

I would retain one gem initially, with these internal responsibilities:

| Responsibility | Owns | Does not own |
|---|---|---|
| CLI framework | Registration, arguments/options, exact and prefix resolution, help, external executable discovery | Tasks, databases, PR state, user-plugin side effects |
| Workstation domains | Tasks, locations, todos, services, queue prompts, PR tracking, saved resources | Native terminal/editor/media implementations |
| Execution and adapters | Process execution, terminal placement, editors, clipboard, GitHub/native tool calls | Business decisions hidden in shell snippets |
| Personal integrations | CodeHiiro builds, Obsidian conventions, Portfolio, machine-specific roots, agent recipes | Portable framework defaults |

This is an internal organization, not a proposal for four packages or four framework layers. A small command can stay small. A domain operation earns a module when multiple commands need its meaning or its lifecycle.

Command resolution and help should work without opening SQLite, migrating files, resolving the current task, or recording an invocation. The selected operation can load the domain it needs. Keep external executables discoverable without running them to ask for metadata.

Keep application presentation outside state mutation. A task query returns task data; a terminal renderer formats it. Do not create a presenter class for every three-line handler.

## Rewrite data ownership before adding unattended automation

The current SQLite/YAML transition has multiple owners. Turning off `DB.dual_write?` does not stop every YAML writer.

Concrete examples:

- `t` writes todo rows directly. `TodoManager#save` deletes and recreates the entire todo table from its loaded snapshot.
- The reminder model exists in SQLite, but `h remind` reads and writes its own YAML file.
- Task helpers, pins, links, branches, and pane homes have YAML writes outside the shared dual-write condition.
- App mutations write database rows while `h app config` opens YAML.
- `h db migrate` archives and deletes configuration YAML using a broad recursive glob, including files that are still live definitions.

Sources: [todo.rb](../../lib/hiiro/todo.rb), lines 322-335; [task_cli.rb](../../lib/hiiro/task_cli.rb), lines 264-295; [h-remind](../../bin/h-remind), lines 154-173; [h-db](../../bin/h-db), lines 113-165; [database migration](../../lib/hiiro/db.rb), lines 64-108.

`[INFERENCE]` A stale whole-table save can overwrite a new todo inserted by another command. A reminder import can move the YAML file away while the active manager still expects it. These are reasons to establish one writer contract before a worker begins changing data periodically.

The target ownership should be explicit:

| Data | Authoritative owner |
|---|---|
| Tasks, todos, PR tracking, saved links/resources | SQLite records with targeted mutations and database-owned IDs |
| Service/tool/sparse definitions and user preferences | Human-editable configuration files |
| Prompt bodies, notes, images, captured logs | Files, with references where a domain needs them |
| Run state and notification checkpoints | Structured runtime records, not reconstructing ownership from labels |
| Legacy YAML | Explicit import/export and recovery inputs, not silent fallback authorities |

Keep configuration under `~/.config/hiiro`. The existing declared data root is `~/.local/share/hiiro`, and queue files already use it. Moving the database and service runtime files there is sensible, but it is a separate migration after writer ownership is correct. A path move is not the fix for conflicting stores.

A migration must enumerate the stores it owns, preserve IDs/relationships, report conflicts, and prove each import. Keep service/tool definitions out of deletion lists. Preserve tags, task resources, pin value types, reminder recurrence, and repo-qualified PR identity. Keep recovery material until a verified reload reproduces the data.

I would not put everything into SQLite. Markdown prompts and notes should remain ordinary files. The simplification is one owner per kind of data, not one storage format for the whole application.

## Resolve one context for each operation

A recurring pattern is “find task, find tree, find app, choose directory, find terminal, execute.” Variants appear in task commands, apps, projects, queue prompts, and services.

`CurrentTask` has strict workspace/directory/pin resolution and ambiguity errors. The older `Environment` can choose a first matching task or app. Queue launch and pane-add paths also resolve directories differently. Sharing a helper while retaining different implicit policies does not make the behavior consistent.

Sources: [current_task.rb](../../lib/hiiro/current_task.rb), lines 24-81; [tasks.rb](../../lib/hiiro/tasks.rb), lines 1646-1757; [task_location.rb](../../lib/hiiro/task_location.rb); [queue.rb](../../lib/hiiro/queue.rb), lines 128-171 and 365-388.

I would extend the existing task/location values into one resolved command context. Simplified proposed data:

~~~js
const context = {
	taskId: 42,
	project: "hiiro",
	app: "cli",
	cwd: "/Users/me/proj/hiiro",
	cwdSource: "primary-directory",
	taskSource: "calling-workspace",
	terminal: { backend: "herdr", workspaceId: "ws-1", paneId: "pane-7" }
};
~~~

Explicit selections must stay distinct from inferred context. Preserve strict ambiguity errors and explicit calling-pane IDs. A project or home directory does not need a fake task record.

Reuse this result for `path`, `open`, `cd`, and command execution. Root profiles such as notes, dotfiles, and Neovim configuration can reuse directory operations while keeping their own paths and conventions.

Do not parse a formatted picker row back into an identity. The existing mapped fuzzy-selection pattern already returns the original object. Use it consistently.

## Edit and permanently prune lists from the fuzzy picker

Add a discoverable, configurable binding, such as `Ctrl-E`, that opens an editor for the current picker list and its persistent exclusion rules. Removing an option from the edited list creates a literal exclusion for its stable identity. Rules can also remove groups of options without editing each row.

Support these explicit matching modes:

- Literal matches exclude an exact identity, name, or path.
- Substring matches exclude values containing the supplied text.
- Regex matches exclude values matching a regular expression.
- Glob matches exclude patterns such as `**/*.bak` or `archive/*`.
- Extglob matches support extended patterns such as `**/*.@(bak|tmp)`.
- Keep the rule format open to additional matching methods when a concrete need appears, without treating every pattern as an ambiguous mix of syntaxes.

Simplified proposed data:

~~~js
const pickerPruning = {
	picker: "task-files",
	scope: { taskId: 42 },
	exclude: [
		{ mode: "literal", field: "path", pattern: "./scratch.md" },
		{ mode: "substring", field: "name", pattern: "generated" },
		{ mode: "regex", field: "name", pattern: "^draft-[0-9]+" },
		{ mode: "glob", field: "path", pattern: "**/*.bak" },
		{ mode: "extglob", field: "path", pattern: "**/*.@(bak|tmp)" }
	]
};
~~~

Any matching exclusion removes the option from that picker, including future searches and subsequent invocations. Save the rules under the named picker and chosen scope. Global exclusions must be an explicit choice, not an accidental consequence of pruning one task list. Match stable item fields rather than decorated display rows. Define case sensitivity, path separators, and glob/extglob semantics explicitly; do not execute patterns through a shell.

Show a preview and the matching rule before saving. Reject invalid patterns without changing the saved rules. After editing, return to the picker with its query, position, and still-visible selections preserved. Provide a show-excluded view and a way to edit or remove rules so permanent pruning is reversible.

Pruning permanently removes choices from the picker until their exclusion is removed. It does not delete underlying files, tasks, PRs, or records. Actual resource deletion remains a separate, explicit domain operation. This shared picker behavior should work across command, file, task, branch, PR, and saved-information lists without giving them a shared storage model.

## Share execution ownership, not a universal workflow engine

Queue, services, background commands, task AI sessions, captured output, and validation recipes all need a directory, environment, command, placement, and outcome. They do not have the same lifecycle.

Reuse `CommandSpecification` and `Result`. Add only the launch/ownership information those consumers actually need. Simplified proposed data:

~~~js
const request = {
	owner: { kind: "service", taskId: 42, definition: "web" },
	command: { argv: ["bundle", "exec", "rails", "server"], cwd: context.cwd, env: {} },
	placement: { kind: "new-tab", focus: false }
};

const run = {
	id: "run-17",
	owner: request.owner,
	state: "starting",
	terminal: { backend: "herdr", tabId: "tab-8", paneId: "pane-9" },
	process: null,
	exitCode: null
};
~~~

A created tab is not proof that the command started. A live shell pane is not proof that a service is still running. PID alone is not sufficient authority to stop a process after reuse. Service identity must distinguish a definition from a running instance in a task/directory.

Queue completion should report the actual child exit status. Queue ownership should survive a failed launch without stranding an entry as running. Services need preparation/start/readiness/stop outcomes. Background commands need lighter ownership, not the full service model.

Sources: [queue launch](../../lib/hiiro/queue.rb), lines 117-252; [service lifecycle](../../lib/hiiro/service_manager.rb), lines 162-319; [background](../../lib/hiiro/background.rb); [Herdr launch results](../../lib/hiiro/herdr.rb), lines 234-300.

Keep argv and deliberately authored shell text distinct. Preserve inherited terminal I/O, process replacement, piped stdin, and bounded log streaming. `h capture` streams to disk and forwards stdin; replacing it with the current buffered shell helper would lose those properties.

Task completion, todo completion, queue completion, and process completion remain different states. Finishing an agent run must not silently mark its task done.

Do not rewrite Herdr or TUIOS. Delegate native operations. Introduce shared terminal capabilities only where there are real consumers on both backends. Keep tmux-specific buffer/jumplist behavior explicitly optional until its users are known.

## Make one command catalog explain what actually runs

There are competing executable scanners, separate installation paths, and user-editable copies. `Runners` and `Bins` apply different filtering. Dispatch does not explicitly enforce the same precedence as shell PATH lookup.

The catalog should be derived from command registrations and executable candidates. It is not the existing SQL resource registry and should not become another manually maintained database.

~~~js
const command = {
	name: "pr",
	kind: "external",
	path: "/Users/me/bin/h-pr",
	origin: "managed-install",
	canonicalName: "pr",
	aliases: [],
	shadowedPaths: ["/Users/me/proj/phome/bin/h-pr"]
};
~~~

Keep the existing `add_cmd` and `OptionSet` metadata. One inventory should drive dispatch, help, completion, searchable selection, source editing, generated documentation, and install manifests. Unknown external-script metadata can remain unknown rather than executing arbitrary scripts during discovery.

Choose executable eligibility, canonical-name precedence, PATH order, and ambiguity rules explicitly. Show collisions instead of letting dispatch and “edit this command” select different files.

Installation should distinguish managed assets from user overrides. Install gems per Ruby version, but update shared `~/bin` and plugin assets once. Preserve modified files and show a drift plan. Include supporting libraries, not only filenames matching `h-*`.

Sources: [Runners](../../lib/hiiro.rb), lines 587-797; [Bins](../../lib/hiiro/bins.rb); [setup](../../exe/h), lines 67-158; [gemspec](../../hiiro.gemspec); [sync script](../../script/sync).

## Rebuild PR workflows around one qualified snapshot

This is the largest single command-family rewrite I would choose. `h pr` has 1,559 physical source lines, alongside the manager, model, Git PR object, and independent monitor. The line count locates concentrated orchestration; it does not prove that the behavior is unnecessary.

Keep `PullRequestReference`, `RepositoryIdentity`, `CheckSummary`, and existing repository-batched fetching/pagination. Finish their adoption instead of inventing new equivalents.

Separate local tracking preferences from observed GitHub data:

~~~js
const tracked = {
	ref: { repo: "owner/hiiro", number: 123 },
	taskId: 42,
	tags: ["review"],
	watch: { notifyChecks: true, queueFix: false }
};

const snapshot = {
	ref: tracked.ref,
	headSha: "abc123",
	fetchedAt: "2026-10-12T10:00:00Z",
	checks: { complete: true, success: 12, failed: 0, pending: 0 },
	reviews: { complete: true, decision: "approved" }
};
~~~

One refresh path supplies lists, status, watch transitions, dependency views, and fix prompts. Remote refresh changes remote fields, not an entire loaded collection of local tags and associations.

Use repository plus PR number everywhere. Keep head revision and completeness explicit. A partially fetched list of successful checks is not sufficient evidence for automatic merge eligibility. Show stale/unknown separately from passing, and preserve the last known observation when a refresh fails.

Single and bulk actions should use the same operation. `mopen`, `mmerge`, `mready`, and their peers need target sets, not independent orchestration. Editable YAML can remain a useful selection/parameter editor through `EditedDocument`.

The independent monitor currently parses human-oriented status output. Replace that parser with shared snapshot transitions and the existing notification adapter. Keep foreground “wait for checks” distinct from continuous monitoring.

Sources: [h-pr](../../bin/h-pr), lines 1124-1515; [pinned manager](../../lib/hiiro/pinned_pr_manager.rb), lines 77-164 and 499-609; [check summary](../../lib/hiiro/check_summary.rb); [PR monitor](../../bin/h-pr-monitor).

Commit-planning safety is an earlier prerequisite. The current snapshot helper stages and resets the real index, including before its dry-run return. `[INFERENCE]` Planning can discard an existing staging selection. A replacement should inspect without touching that index, validate the plan, and stop on execution failure. This is more important than making the AI prompt smarter. See [h-git](../../bin/h-git), lines 19-24 and 219-275.

## Treat installed-local commands as part of the design

The source checkout is not the whole workstation. The 21 additional executable names on PATH include encode/decode filters, rebase reporting, screen recording, terminal casts, audio transcription, skill tooling, PRD navigation, and personal project integrations. Their inventory appears after the source appendix.

This changes the consolidation map. Installed encode/decode already provide real URI transformations, while the source `uri decode` prints a recipe. Installed export overlaps the newer environment writer. Ruby/iface overlap. Audio duration and clipping overlap existing video commands, while transcription and automatic border detection remain distinct jobs.

Keep specialized recipes such as multi-window recording and border detection. Reuse execution, output naming, and media operations without pretending all capture methods are interchangeable. Move hard-coded project/provider paths and prompt choices into explicit personal profiles.

Several installed handlers are experiments rather than completed capability. The four TTS handlers are empty. Skill distribution and audio mapping stop at debuggers. Do not count registration as a working feature or port these bodies unchanged into a redesigned system.

Source evidence comes from the installed command files, including [h-encode](../../../../bin/h-encode), [h-decode](../../../../bin/h-decode), [h-audio](../../../../bin/h-audio), [h-screencap](../../../../bin/h-screencap), and [h-skill](../../../../bin/h-skill). This study did not run their external applications or providers.

## Preserve the existing MCP implementation and fix its ownership

MCP is not an unimplemented concept. Its catalog/client and registry exist under installed-local and phome support directories. The current source `h-mcp` requires those support classes, but the checkout does not contain them. The installer copies immediate `h-*` files, not their adjacent support directory.

I would make Hiiro the canonical package owner of the existing implementation, put its support modules under the gem's library, and keep phome/local commands as consumers. Audit differences before deleting duplicate copies. This is a packaging cutover, not a new protocol stack or registry.

Keep the current shared SQLite records, exact client-source references, MCP SDK transports, paginated discovery, credential scoping, and stored tool schemas. Keep externally mutating tool calls explicit.

Preserve the sync safeguards already implemented: unrelated client settings, restrictive backups, atomic replacement, dry-run behavior, and fingerprint-guarded stale pruning. Do not overstate them. Active same-name exports are overwritten, and config replacement plus ownership-record updates are sequential rather than one transaction. The visible export path is HTTP-only even though the client can use stdio and HTTP.

Sources: [installed catalog](../../../../bin/lib/h_mcp_catalog.rb), [installed registry](../../../../bin/lib/h_mcp_registry.rb), [MCP command](../../bin/h-mcp), and [existing phome regression source](../../../phome/scripts/test-h-mcp.rb). Those tests were inspected, not run.

## Automate specific manual handoffs

These examples are proposals, not new commands implemented by this study.

| Manual work today | System responsibility | Human control that remains |
|---|---|---|
| Rediscover task/app/directory before services or tools | Resolve one context and reuse it | Explicit task/app override and ambiguity selection |
| Run several validation commands and collect failure text | Existing RunnerTool executes a configured recipe and retains failed logs | Choose recipe and decide whether to invoke an agent |
| Refresh PRs, inspect checks, build a fix prompt | Shared snapshots produce revision-specific evidence for the existing queue | Opt in to queueing; no automatic merge |
| Save clipboard content, copy its path, paste into a bundle/task | Capture an artifact once and attach its returned path | Choose destination and association |
| Maintain cron instructions or a foreground queue watcher | Platform-managed scheduling for existing reminder/queue workers | Enable schedule, concurrency, and notifications explicitly |
| Ask an agent to write status JSON and rebuild a dashboard each cycle | Job completion writes an outcome; status views read it | Use agents only for interpretation or non-deterministic work |
| Compare copied commands and manually copy or diff files | Managed installation shows a drift plan and applies selected owned updates | Preserve overrides; never overwrite unrelated files |

For example, “work on task 42” should reuse its directory and selected app, open the requested terminal, and optionally start its explicitly configured service group. It should not create a worktree, modify Git state, or launch every available service merely because it can.

For validation, a failed lint run can already have an execution result, a log artifact, a task association, and a queue prompt. The user should not need to reconstruct those relationships by copying terminal text between commands.

For scheduled work, reuse macOS launchd where appropriate rather than inventing a general scheduler daemon. A queue worker still needs its own atomic claim, launch, and completion rules. Scheduling does not supply process ownership. Any automatic status refresh must preserve selection, scroll position, and local interaction state.

## Reorganize by ownership without hiding useful shortcuts

I would keep familiar user-facing commands where they help. Internally, group them by the system they use:

| Group | Current commands that belong together | Decision |
|---|---|---|
| Work context | `t`, `tt`, task, project, app, home, wtree, sparse | One context policy; preserve typed task/project/worktree operations |
| Execution | queue, service, run, bg, capture, cmd | Shared execution values and ownership; recipes are not completed runs |
| Review | git, branch, pr, pr-monitor, commit, sha, cpr | Shared selectors and snapshots; explicit mutation policy |
| Saved information | save, context, link, note, docs, obsidian, file | Share capture/selection/open mechanics, keep source ownership distinct |
| Terminal integration | herdr, tuios, pane, window, session, hh, title, notify, buffer, jumplist | Native delegation plus task context and owned handles |
| Native utilities | extract, strip, date/time, video, plist, sign, mermaid, mic, filesystem inspection | Keep thin; parameterize duplicated recipes |
| Administration/personal profiles | config, bin, plugin, registry, env, alias, dotfiles, vim, ch, pm, t3, pgsync | Keep portable mechanics separate from machine/project policy |

A bookmark, an Obsidian note, and a Portfolio document can share “select, open, copy,” without sharing a database. Keep Portfolio's index and Obsidian's URI behavior native. Obsidian's personal Markdown task schema is not automatically equivalent to Hiiro TaskRecord.

Prefer data for known recipe differences. Date/time already share parsing and duration values; share registrations while preserving output styles. Video size/codec/quality variants can become presets and options, but stream copy and precise re-encoding remain distinct operations. Prompt tables such as `h pm` are named agent recipes, not eleven separate project-management implementations.

Do not turn this organization into a universal resource/action DSL. Typed operations such as todo completion, PR merge, service readiness, and link expansion have different invariants. Reuse their mechanics only where the contracts genuinely match.

## What I would rewrite, in order

| Priority | Rewrite | What disappears | What must survive |
|---|---|---|---|
| 1 | Canonical data mutations and ownership-aware migration | Whole-table snapshot saves, competing live backups, broad YAML deletion | IDs, relations, recurrence, user definitions, recovery |
| 2 | Context/directory resolution and owned launch results | First-match guesses, repeated cwd joins, “pane exists means job runs” | CurrentTask strictness, TaskLocation provenance, native resume |
| 3 | Read-only command discovery and managed installation | Competing scanners, duplicate setup/sync paths, untracked copies | External scripts, overrides, abbreviations, source editing |
| 4 | PR refresh/monitoring and shared target-set actions | Human-output polling, parallel single/bulk actions, number-only identity | Qualified refs, check completeness, tags, native gh output |
| 5 | Validation, clipboard capture, and recurring job outcomes | Repeated log/path handoffs and producer-driven dashboard regeneration | stdin/stream behavior, artifact paths, opt-in schedules |
| 6 | Registration/preset and legacy-command cleanup | Duplicated date/time registration, media preset handlers, old task trees when proven replaceable | Useful shortcuts and unmatched domain behavior |

The implementation order has concrete completion criteria. A store cutover is complete when every writer uses its owner and reload preserves existing data. A context cutover is complete when services/queue/tools choose the same explicit task/app directory as task commands. A launch cutover is complete when failure and termination produce correct owned-run state. A PR cutover is complete when identical numbers in different repositories, stale fetches, partial checks, and revision changes remain distinguishable.

Apply each cutover to all its consumers, then remove its obsolete implementation. Do not leave indefinite old/new parallel paths. User-facing aliases may remain when they are deliberate shortcuts over one operation, not compatibility engines.

## What I would not rewrite

- Ruby into another language without measured evidence that Ruby is the constraint.
- Git, gh, FFmpeg/ffprobe, plutil, codesign, Mermaid, native editors/search tools, or terminal managers.
- Existing good value objects merely to change their names or directory layout.
- The current shared TaskCli, its short entrypoints, or the already-completed Herdr adoption.
- Portfolio indexing or Obsidian storage as Hiiro-owned replacements.
- Native agent histories and session-resume behavior as a Hiiro-owned session database.
- Every small utility into a plugin framework, universal workflow engine, or generic CRUD layer.

Preserve `extract`'s path/link semantics and encounter-order behavior. Preserve `capture`'s streaming and stdin. Preserve mute/unmute volume restoration. Preserve different escape-filter byte contracts until they are explicitly reconciled. Small utilities can encode valuable behavior.

## Candidates to retire, not declarations of dead code

Source-only candidates include empty `h dsstore`, the non-acting `h .config` handler, production distribution of `h demo`, exposed diagnostic commands, the printed Python recipe under `h uri decode`, and residual `otask/osubtask/zosubtask` implementations. Keep examples in examples rather than the default product inventory.

Some names overstate their behavior. `dotenv copy_to` reports differences rather than copying. `sign` inspects signatures rather than signing. Parts of `pr review` are commented out. Correct the product description or finish the actual operation only if that job is wanted. Do not add a framework to make incomplete experiments look systematic.

A source file can be unused upstream and still run through an installed user copy or plugin. Check reachability, usage, and unmatched behavior before deleting it. This study did not inspect invocation history or private plugin contents.

## Evidence and verification boundary

The command counts and symlinks were checked using Ruby without requiring project code. Viewer health was checked through `mdoc --rebuild-index`. The proposal is the only authored file. The prompt, repository, installed commands, and configuration were left unchanged.

A small reproducible source inventory, run from the checkout:

~~~sh
ruby -e '
  bins = Dir["bin/*"].select { |p| File.file?(p) }.sort
  exes = Dir["exe/*"].select { |p| File.file?(p) }.sort
  puts "bin entries: #{bins.size}"
  puts "h-* entries: #{bins.count { |p| File.basename(p).start_with?("h-") }}"
  puts "exe entries: #{exes.size}"
  (bins + exes).each do |path|
    target = File.symlink?(path) ? " -> #{File.readlink(path)}" : ""
    puts "#{path}\t#{File.foreach(path).count} lines#{target}"
  end
'
~~~

Physical lines include comments and blank lines. Entry paths include aliases. These are inventory facts, not a measure of useful capability or predicted code savings.

Future implementation verification should exercise partially staged Git data during planning, concurrent todo/tag writes, reminder recurrence after reload, failed terminal allocation, failed process startup, real nonzero queue exits, a reused pane, two service instances in different directories, mixed-repository PRs, and failed refreshes. None of those scenarios were executed in this documentation-only study.

## Source command appendix

This appendix records source registrations and delegated command trees, not a dynamically executed help inventory. Generic injected `pry/edit` commands and private user-plugin additions are not an exhaustive runtime namespace. Physical line counts describe the inspected files, not tested behavior. Root/table source paths refer to [the checkout](../../README.md).

## Sorted complete bin inventory

In the DSL column, slash-separated names share one handler. `default@line` is a default handler, not a named subcommand. The table records explicit and statically expanded registrations, not implicit pry/edit, except where a file explicitly overrides them. Nested names include their parent. Aliases can share behavior but still constitute separate accepted spellings.

| Source path | Lines | DSL registrations or entry behavior |
|---|---:|---|
| bin/h | 274 | Same read content as exe/h; base grammar below |
| bin/h-.config | 9 | herdr; handler only filters input paths, with no observable action |
| bin/h-alias | 28 | add |
| bin/h-app | 266 | config, cd, ls, path, abspath, add, rm, remove, fd, rg, vim, sh, service, run, file |
| bin/h-bg | 74 | popup, run, attach/a, history/hist, setup |
| bin/h-bin | 57 | add, list, edit |
| bin/h-branch | 974 | edit, save, saved, current, info, ls, search, tag, untag, tags, select, copy, co/checkout, rm/remove, rename, status, merged, clean, recent, note, for-task, for-pr/pr, duplicate, test, push, diff, changed, ahead, behind, log, q/query, forkpoint, ancestor |
| bin/h-buffer | 123 | ls, show, copy, save, load, set, paste, delete, choose, clear, select |
| bin/h-capture | 200 | new, file, ls, cat, cppath, cp, path |
| bin/h-ch | 531 | bkup/backup, m/make, t/test, home, appsha, r/run, which, migrations/migs, compatible/compat, ls |
| bin/h-claude | 304 | split, vsplit, hsplit, window, env, inline, all, agents, commands, skills, vim, new, loop |
| bin/h-cmd | 71 | save, ls/list, search |
| bin/h-commit | 37 | edit, select/sk, default |
| bin/h-config | 57 | herdr and again, ssh, vim, git with global/ignore/local, zsh, profile, starship, claude |
| bin/h-context | 373 | new/reset/clear, path, ls/list/show, copy, save, tmp/temp, img/imgas, tmpimage/tmpimg, add, rm/remove/delete, save_bundle/bundle_save, load_bundle/bundle_load/use, bundles/list_bundles, open, help |
| bin/h-cpr | 26 | No DSL; forwards arbitrary first subcommand plus PR reference to h pr-26 |
| bin/h-date | 53 | to_unix/unix/ts, from_unix/parse, fmt/format/strftime, now, dur/duration/human, diff |
| bin/h-db | 284 | status, tables, q, query, migrate, remigrate, cleanup, restore |
| bin/h-demo | 14 | josh |
| bin/h-docs | 286 | setup/install, start, stop, restart, status, ls, recent, make, run, open, vim, cat, rm, count, index/tui, reindex/rebuild, path, ports |
| bin/h-dot | 35 | compare |
| bin/h-dotenv | 109 | copy_to, compare |
| bin/h-dotfiles | 42 | edit, path, skf, rg, rgall, ebin |
| bin/h-dsstore | 7 | Empty Hiiro.run block; only framework startup/builtins |
| bin/h-dsstore-read | 7 | Python script, no DSL; reads cwd/.DS_Store; hardcoded /Users/josh/venvs/voxcpm/bin/python3 shebang |
| bin/h-env | 25 | add |
| bin/h-extract | 61 | files/dirs/links generated by loop-20 |
| bin/h-git | 289 | clean, dirty, ignore, commit, edit, default |
| bin/h-herdr | 293 | install, uninstall, keys, actions, focus, resize, swap, move/layout/arrange, zoom, action, popup |
| bin/h-home | 62 | edit, path, skf, rg, rgall, ebin |
| bin/h-html | 380 | vids, videos |
| bin/h-img | 67 | save, b64 |
| bin/h-js | 77 | add, pkg, scripts, all |
| bin/h-jsonl | 776 | export, stats, head, grep, validate |
| bin/h-jumplist | 287 | setup, clear, path, ls, list, record, to, back, forward |
| bin/h-link | 512 | add, ls, list, search, select, copy, editall, edit, rm, remove, open, tags, paste, path |
| bin/h-loop | 475 | list/ls, add, rm, start, stop, restart, tmux/t, render/r, prs, slack |
| bin/h-ls | 69 | ext, last |
| bin/h-mcp | 423 | ls/list/info/add/import/remove/configured/discover/saved/tools/tool/call/guide/test/url loop-358; sync, status, agents |
| bin/h-mermaid | 28 | install, png, svg |
| bin/h-mic | 93 | set, mute, unmute, toggle, status, edit |
| bin/h-misc | 30 | symlink_destinations |
| bin/h-note | 200 | modify, open, edit, categories, tagged_files, ls, tags, copy, move, save |
| bin/h-notify | 194 | push, ls, prune, menu, jump, clear, remove_pane, remove_window/remove_tab, remove_session/remove_workspace, herdr with setup; claude with setup/add_hooks, reset_hooks, load_hooks |
| bin/h-obsidian | 904 | ls, tasks, toggle, list, search, select, url, open, path, vault, help, default |
| bin/h-osubtask | 32 | edit, list, ls, new, switch, app, path, cd, apps, status, st, save, stop, current, default |
| bin/h-otask | 869 | edit, list, ls, start, switch, app, path, cd, apps, status, st, save, stop, current, migrate |
| bin/h-pane | 240 | ls, lsa, split, hsplit/splith, vsplit/splitv, kill, swap, zoom, capture, select, copy, sw/switch, home with ls/add/rm/switch; move, break, join, resize, info |
| bin/h-pgsync | 60 | fix |
| bin/h-plist | 214 | show/print, get, keys, type, lint, set, add/insert, rm/remove/delete, convert, json, xml, create, edit, help, default |
| bin/h-plugin | 46 | path, ls, edit, rg, rgall |
| bin/h-pm | 60 | discover/resume/status/add/start/plan/complete/ref/impact/archive/unarchive from PM_SUBCOMMANDS-21 and registration; help; default |
| bin/h-pr | 1559 | Full large grammar below |
| bin/h-pr-monitor | 158 | No Hiiro DSL; standalone OptionParser/polling script |
| bin/h-project | 203 | open, list, ls, config, edit, select, copy, sh, help, default |
| bin/h-ps | 174 | byport, search, indir, getdir, info, files, ports |
| bin/h-registry | 203 | ls/list, types, add, rm/remove, get, show, select, set-alias, set/update |
| bin/h-remind | 590 | add, once, every, ls, list, remove, pause, resume, check, clean, howto, path, editall |
| bin/h-save | 154 | default, ls/list, dir, show/cat, copy, open, edit, rm/remove |
| bin/h-session | 114 | ls/list, new, kill, attach/switch, rename, has, info, open, sh, select, copy, orphans, okill |
| bin/h-sha | 49 | select, ls, show, copy |
| bin/h-sign | 118 | verify, info, requirement, report |
| bin/h-sparse | 158 | config, ls, list, set, add, rm |
| bin/h-strip | 39 | No DSL; raw byte input and ANSI/control removal |
| bin/h-t3 | 21 | ip, pair; pair creates pairing credential rather than being the TODO comment alone |
| bin/h-tags | 18 | tags_by_type |
| bin/h-task | 7 | TaskCli.setup, already shares t grammar |
| bin/h-time | 53 | to_unix/unix/ts, from_unix/parse, fmt/format/strftime, now, dur/duration/human, diff |
| bin/h-title | 24 | update, setup; setup prints that native Herdr tracking needs no hook |
| bin/h-todo | 269 | ls, list, add, rm, remove, change, start, done, skip, reset, search, path, editall, help |
| bin/h-tuios | 84 | default, gfy, help, setup, skills-install/skills-refresh, bootstrap-project, bootstrap-install, bootstrap-remove, uninstall, integrations-install, integrations-status, targets, start, stop, status, setup-status, doctor, config, hooks, skill, instructions, env, bootstrap, mail |
| bin/h-uri | 9 | decode; prints a Python command rather than decoding input |
| bin/h-video | 533 | Full large grammar below |
| bin/h-vim | 63 | edit, path, init/config, skf, rg, rgall, session, tmux |
| bin/h-window | 62 | ls, lsa, new, kill, rename, select, copy, sw/switch, next, prev, last, info |
| bin/h-wtree | 108 | ls, list, add, lock, move, prune, remove, repair, unlock, switch, select, size, branch, copy |
| bin/h-xxserve | 6 | No DSL; calls miniserve -p 1111 |
| bin/h-zosubtask | 22 | edit, ls, new, switch; commented default is not a registration |
| bin/hh | 54 | ls, switch/start, kill/stop/rm/remove; focus/resize/swap/move/layout/arrange/zoom loop-48; default forwards to herdr |
| bin/t | 7 | TaskCli.setup |
| bin/tt | 7 | TaskCli.setup_todo |

## Sorted complete exe inventory and inline base commands

| Source path | Lines | Explicit grammar |
|---|---:|---|
| exe/h | 274 | version, ping, install/update, setup, alert, queue, service/svc, run, file, check_version, delayed_update, rnext |
| exe/hiiro | 86 | version, ping, setup, alert |
| exe/t | 7 | TaskCli.setup |
| exe/tt | 7 | TaskCli.setup_todo |

Normally Hiiro.init also registers pry@lib/hiiro.rb:114 and edit. The t, tt, and h-task launchers pass `external_commands: false, builtin_commands: false`; h-herdr and h-tuios disable external discovery but retain normal builtins. User plugins can add further behavior; they were deliberately not inspected.

Inline queue names from lib/hiiro/queue.rb:

`watch, run, ls/list, status, attach, peek, say, session, add, cadd, hadd, vadd, wip, ready, kill, retry, clean, sadd, tadd, dir`.

Inline service/svc names, also mounted under h app service, from lib/hiiro/service_manager.rb:

`ls, list, start, stop, reset, clean, attach, open, url, port, status, add, rm, remove, config, groups, env`.

Inline run names, also mounted under h app run, from lib/hiiro/runner_tool.rb:

`default, ls, add, rm, config`.

Inline file names, also mounted under h app file, from lib/hiiro/app_files.rb:

`ls, add, rm, edit`.

These shared build_hiiro methods are existing reuse, not separate implementations to migrate.

## Large command grammars

### h pr

All root registrations in bin/h-pr:

`check, watch, fwatch, tst, number, link, edit, open, view, select, copy, track, ls, status, update, green, red, old, prune, draft, assigned, created, missing, amissing, attach, rm, ready, to-draft, diff, checkout, merge, sync, fix, comment, templates, new-template, from-template, branch, for-task, review/cr, tag, untag, tags, mfix, mopen, mmerge, mready, mto-draft, mrm, mcomment, dep, config, q/query`.

Nested dep registrations are add, rm, ls, config, edit. Nested config registrations are path and vim.

The m-prefixed actions and status-specific commands are a concrete consolidation candidate. One selection/filter step plus one operation can replace parallel paths without reducing the actual actions. Existing watch_block sharing-66 and PinnedPRManager usage should be retained rather than rewritten as another watcher.

### h video

All explicit registrations in bin/h-video:

`info, streams, duration, resize, resize720, resize1080, convert, to_mp4, to_webm, to_mkv, audio, audio_wav, audio_aac, audio_flac, clip, clip_to, clip_precise, subs, subs_all, list_subs, thumbnail, thumbnails, gif, gif_hq, mute, replace_audio, volume, speed, compress, compress_small, rotate, flip_h, flip_v, crop, concat, fps, metadata, strip_metadata, help`.

The fixed-size/format variants are candidates for data presets on fewer verbs, not distinct backend implementations. Keep ffmpeg/ffprobe as the execution tools. Preserve stream-copy versus re-encode distinctions currently represented by clip variants.

## Task grammar already consolidated

Do not propose a new t versus h task migration. `exe/t`, `bin/h-task`, and `bin/t` call the same `Hiiro::TaskCli.setup`; tt calls setup_todo. TaskCli uses the existing add_cmd DSL and disables unrelated PATH children. README.md:129-131,179 corroborates the current structure.

TaskCli root registrations in lib/hiiro/task_cli.rb:777-955:

- help, list/ls, show, current, use/pin, new, next, waiting, status.
- done/archive from loop-805.
- todo.
- directory/link/pr/file from resource loop-813.
- doc, tree, switch/workspace, path, branch, cd, sh.
- omp, codex/cdx, claude/cld from loop-891.
- tab and pane.
- Default root handler lists tasks.

Nested grammars:

- doc: help, new, list/ls, open.
- tree: default show, help, new, rm/remove, resume.
- tab: help, list/ls, new, open.
- pane: help, list/ls, read, open, run, split.
- todo: default listing, help, list/ls, show, add, rm.
- directory/link/pr/file share `resource_commands`: help, add, list/ls, open. See `lib/hiiro/task_cli.rb:995-1008`.

The TaskCli helper `resource_commands(group)` already removes repeated CRUD-like registration for four resource kinds. Retain that pattern. Legacy `h-otask`, `h-osubtask`, and `h-zosubtask` still contain independent command implementations, but their semantics must be compared with TaskCli before deletion. The current consolidated grammar is evidence that duplication remains elsewhere, not evidence that every older action already has an equivalent.


## Installed-local extension appendix

These 21 executable names were present on the inspected shell PATH and absent from the source bin set. The table records source behavior, not exercised runtime results. In citations, `B` means `/Users/unixsuperhero/bin` and `S` means `/Users/unixsuperhero/proj/hiiro`. External script/application internals are outside this inspection.

| Command and installed source | Purpose and registered subcommands | Group and disposition |
|---|---|---|
| `h-activity-viewer`, `B/h-activity-viewer:6-13,37-69,71-120` | `status`, `start`, `stop`, `open`, `logs`, `sync`. Runs local `python -m taskdesk` for `~/proj/claude-activity-viewer`, localhost port 8123; sync calls `taskdesk.activity.sync_items` and counts items. | Personal + overlap. Keep app-specific sync as an integration; consolidate generic lifecycle with the existing service system, subject to backend differences. |
| `h-asciinema`, `B/h-asciinema:7-51,56-95` | `nname`, `cname`, `pname`, `fname`, `lname`, `name DAY [INDEX [LAST_INDEX]]`, `record`, `resume`, `play`. Allocates dated `.cast` names in `~/notes/yt/casts`; records `safe_nvim`; resume opens the editor at its saved mark and creates a new cast, not an append to an existing cast. | Recipe + personal. Keep recording/playback; make the output directory and editor recipe independent of personal naming conventions. Consolidate name selection into one operation. |
| `h-audio`, `B/h-audio:6-21,25-125` | `transcribe`/`xscribe` with txt/srt/json flags; `clips`, `map`, `encapsulated_length`, `cls_proc_length`, `inl_proc_length`, `times`. Transcription invokes local VoxCPM venv `mlx_whisper`, using only the first selected file. Clips delegate to `h video clip_to`. `map`/`times` reference literal `rant.json`/`rant.wav`. | Personal + overlap + recipe. Consolidate duration and clipping into media operations; retain transcription as a provider/tool adapter. `TranscriptionJsonFile#contents` is empty; `map` computes JSON then enters `binding.pry`. `WHISPER_MODEL` is fetched at file load, even for non-transcription commands. |
| `h-binding`, `B/h-binding:5-19` | `test ARG` prints diagnostic text and calls `test_fn`, which repeats a message four times. | Demo, not a product recipe. Exclude from the normal command inventory or retain only as a developer example. |
| `h-crop`, `B/h-crop:22-25,107-145,172-225,290-375` | No named subcommands. `INPUT OUTPUT` with `--frame`, `--tolerance`, `--inset`, `--force-encode`. Finds amber RGB border candidates, prefers line clusters scored for 16:9, crops inside, and re-encodes video with FFmpeg. | Recipe + overlap. Keep border detection as a named media recipe, reuse the normal crop/encode operation. Near-16:9 dimensions are made even, not forced to an exact ratio. `--force-encode` changes an informational note, not whether filtering re-encodes. |
| `h-decode`, `B/h-decode:9-68,72-109` | `base64`/`b64`, `base64url`/`b64url`, `hex`/`base16`/`b16`, `uri`/`url`/`percent`, `form`/`query`, `html`/`html-entities`, `json`/`json-string`, `rot13`, `help`; default help. Reads a file, stdin, or clipboard; writes decoded bytes/text. | Recipe + overlap. Share codec selection and input handling with encode, preserving separate percent/form semantics and JSON-string validation. |
| `h-encode`, `B/h-encode:9-49,51-83` | Same formats/aliases and default help as decode. Base64url omits padding; form/HTML/JSON require UTF-8; output has no added newline. | Recipe + overlap. Pair with decode in one codec module rather than duplicate the reader and arity checks. |
| `h-export`, `B/h-export:5-19` | `add NAME COMMAND...` appends a constructed export line by reading and rewriting `.zshrc`; declared `.zshenv`/`.zshenv.d` constants are unused. | Overlap. Consolidate with `S/bin/h-env:6-23`, which already writes environment assignments. Destination/quoting differences require an explicit cutover decision. |
| `h-iface`, `B/h-iface:5-20` | `rb FILE...` prints Ruby lines matching a fixed declaration regex. | Recipe + overlap. Consolidate with `h-ruby iface`; this is text matching, not a Ruby parser. |
| `h-lines`, `B/h-lines:5-42` | `join FILE SEPARATOR` or `join SEPARATOR` from stdin; default usage error. Chomps input lines and prints joined output with a trailing newline. | Recipe. Keep as a small text operation; no application or provider coupling. |
| `h-pipeline`, `B/h-pipeline:5-22` | Default forwards arguments to `~/.claude/skills/lfeature/scripts/pipeline.sh`, sets `PIPELINE_DIR` to the Git root's `.pipeline`, and prints argument diagnostics. | Personal integration. Represent as a configured workflow recipe; wrapper exposes no additional subcommand inventory. External script not read. |
| `h-prd`, `B/h-prd:7-20,27-63,66-153` | `run`, `next`, `prev`, `set`, `bump`, `reset`, `show`/`last`/`get`/`status`, `path`, `find`, `prompt`, `ls`/`list`. Selects numbered files under cwd `plans`, tracks a cursor in Hiiro `prd.yml`, and invokes Claude with a project-local to-issues skill prompt and permission bypass. | Recipe + personal. Keep PRD selection separate from provider execution. The cursor is global while plan resolution is cwd-relative; `do_run` saves selection before Claude runs, so it is not a completion record. |
| `h-rebase`, `B/h-rebase:26-131,134-233` | `status`, `applied`, `total`, `remaining`, `files`, `file_conflicts`/`conflict_count`, `conflicts`, `next`, `help`; default status. Reads Git rebase state, revision counts and conflict-marker chunks; next delegates to `git rnext`. | Recipe + personal dependency. Keep reporting with Git operations; clearly separate it from mutation. `B/git-rnext:1-29` opens marker-bearing files, otherwise stages everything and continues rebase. |
| `h-repo`, `B/h-repo:5-16` | `clone DEST` tokenizes clipboard contents into a command plus final name/URL, derives an output folder, and executes those tokens with that destination appended. The `.claude/skills` constant is unused. | Personal recipe. It is a clipboard command launcher, not a fixed Git clone implementation. A maintained clone recipe should have an explicit repository input instead of an implicit executable supplied by clipboard text. |
| `h-ruby`, `B/h-ruby:5-34` | `iface` selects prefix-matched pattern groups `class`, `attributes`, `methods`, `accessmodifiers`, `tests`, `lets`, `hiiro`, or `all`, then runs `rg` with `/tmp/patterns` against file arguments. | Recipe + overlap. Keep one Ruby inspection command with explicit groups, consolidate `h-iface rb`; avoid a shared fixed temporary pattern file. |
| `h-screencap`, `B/h-screencap:29-65,170-365` | `app`, `start`, `stop`, `status`, `codehiiro`/`ch`. Gets macOS app-window bounds using System Events; one AVFoundation FFmpeg process records separate cropped windows with audio modes `separate`, `first`, `all`, `none`. Saves recording state; stop tries FIFO `q`, then process-group termination. CodeHiiro shortcut opens the app and prints bounds. | Recipe + personal. Keep macOS recording as a platform adapter in media capture; make CodeHiiro an app recipe rather than another native operation. |
| `h-shada`, `B/h-shada:9-103,114-146` | `export [SOURCE [OUT]]`, `path`, `help`; default export. Headless Neovim loads ShaDa and writes grouped histories, oldfiles, registers, and marks via embedded Lua. | Recipe + personal default. Keep explicit-file export as a Neovim adapter, not a generic data transformation. Output can contain sensitive history/register content; the default export writes a file. |
| `h-skill`, `B/h-skill:6-24,26-117,119-156` | `distro`/`distribute`, `mv`, `find`. Searches provider skill directories, wraps sources in `SkillDir::Source`, and moves Markdown files into `NAME/SKILL.md`. `find` walks ancestor directories; accepted globs are not used. | Recipe + personal + unfinished. Distribution handler computes candidates then enters `binding.pry`; `skills.map(&:distribute)` is commented out. Do not count distribution as completed automation. `AiDir` defines instance `new`, not `initialize`; source selection uses global `DESTS`. |
| `h-t3redo`, `B/h-t3redo:5-9` | `rebuild`. Intended Python feature-index rebuild integration. | Personal + unfinished invocation. Source passes `--rebuild` inside `File.join`, creating a path ending `/build_feature_index.py/--rebuild`, rather than a separate Python argument. This is a source observation, not a runtime result. |
| `h-tts`, `B/h-tts:5-17` | `fish`, `fopen`, `vox`, `vopen`. | Unfinished integration. All four registered handler bodies are empty. Do not present any speech-generation capability from this file. |
| `h-yt`, `B/h-yt:13-16,38-120,140-194` | `history [--dry-run]`, `refactor`, `cron`. History reads the YouTube history feed using yt-dlp/browser cookies, deduplicates by saved video ID and appends Markdown. Cron prints a six-hourly crontab line, it does not install it. Refactor opens four numbered, hard-coded project files in Neovim. | Personal recipe. Keep history import as an integration; remove unrelated project editing from this command's domain. `last_checked_at` is metadata, not the fetch filter; the fetch remains bounded by `max_entries`. |

