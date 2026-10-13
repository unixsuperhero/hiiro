# h-tuios

Set up TUIOS for agent harnesses, manage the inbox server, read your own pane's mail, and navigate every tuios window from one screen.

## Synopsis

```bash
h tuios <subcommand> [args] [options]
```

The synchronized `h-tuios` executables use the adjacent current Hiiro source when available, otherwise `~/proj/hiiro/lib`, before falling back to the installed gem. This keeps `ui` available when the installed gem predates its screen classes. The `h-tuios` executable accepts the same subcommands directly. `h tuios` with no subcommand prints the full guide (`h tuios help`).

To check the five local copies for drift, run `ruby script/sync-tuios --check` from the Hiiro repository. After merging any new functionality into `bin/h-tuios`, use `--write` to synchronize them. The command prints SHA-256 hashes and preserves existing executable modes.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `start [--foreground]` | Start the inbox server (`~/proj/tuios-inbox/server.mjs`) with Bun in the background and wait for HTTP readiness; `--foreground` runs `bun start` attached to the terminal |
| `stop` | Send SIGTERM to the inbox server and wait for it to exit; never stops the TUIOS daemon |
| `status [HARNESS...]` | Print the server URL and PID and check its HTTP response; exit 0 when ready, 1 otherwise. With harness arguments, inspect their setup instead |
| `setup [HARNESS...] [--dry-run]` | Install skills, global startup rules, and native integrations for the selected harnesses |
| `skills-install [HARNESS...] [--dry-run]` | Save `tuios --skill all` as the shared `tuios-inbox` skill and link each harness to it |
| `skills-refresh [HARNESS...] [--dry-run]` | Alias for `skills-install`; use after upgrading TUIOS |
| `bootstrap-install [HARNESS...] [--dry-run]` | Add or update the marked startup block in each supported global instruction file |
| `bootstrap-project DIRECTORY [--dry-run] [--remove]` | Add (or remove) the same startup block in `DIRECTORY/AGENTS.md` |
| `bootstrap-remove [HARNESS...] [--dry-run]` | Remove only the managed block from the selected global instruction files |
| `uninstall [HARNESS...] [--dry-run]` | Remove managed instruction blocks and skill links; keeps the shared skill content and backups |
| `integrations-install [ID...] [--dry-run]` | Run TUIOS's native installer for missing or stale harness integrations |
| `targets` | Print every known setup target with its skill link and instruction destination |
| `setup-status [HARNESS...]` | Report whether each harness's saved skill and startup rule are current, stale, or missing |
| `integrations-status` | Run native `tuios integration status` for the configured hook executable |
| `doctor [agents\|shell]` | Run TUIOS's read-only diagnostics (default `agents`) |
| `config` | Print the active config path from `tuios config path` |
| `hooks` | Print native `tuios list-hooks --json` |
| `ui [--hosts]` | Open the windows screen: one row per tuios window, a detail pane, and keys to jump, capture, rename, minimize, open, and mail |
| `skill [TOPIC]` | Print the live skill from the selected TUIOS binary (`all`, `mail`, `state`, ...) |
| `instructions` | Print the startup/mail rule text for manual insertion |
| `bootstrap` | Inside TUIOS, print pane identity, the startup instructions, and the core and mail skills |
| `env` | Print the available `TUIOS_ENV`, `TUIOS_SESSION`, and `TUIOS_PANE_ID` as JSON |
| `mail` | Read unread mail addressed to the session and pane in your environment |
| `help` | Print the complete guide |

`--dry-run` previews managed changes without writing skills, startup rules, or hooks. `TUIOS_BIN` selects the tuios executable.

### ui

`h tuios ui` opens a `Hiiro::Tui` screen over every tuios window on this machine, read through the tuios command line (`ls --json`, then `list-windows -s SESSION --json` per session for the directory and layout, and `list-attention --json` for the header counts). Nothing is read from another pane's mailbox.

**A row** is one window: `SESSION  wsN  MARK TITLE  HARNESS`, with `*` before the session of the pane the screen runs in (`TUIOS_SESSION`) and `(min)` after the title of a minimized window. Rows sort by host, session, workspace, then window index. The header reads `tuios  host:local  scope:global  7 windows in 4 sessions  attention: 2 finished`; only nonzero attention counts are shown, `none` otherwise.

```text
tuios  host:local  scope:global  4 windows in 3 sessions  attention: 1 ask, 2 finished
[enter]jump [/]search [c]apture [R]eload [H]osts [g]scope [n]ame [M]in [N]ew [m]ail [y]ank id [q]uit
> *alpha  ws1  ● inbox remote host capture  (min)  omp│title    inbox remote host capture
  *alpha  ws2  ? ◑ Md file open with mdoc cli tool  claude-code│session  alpha
  *alpha  ws2  ✓ π > Implement JSON Task Status Management  omp│ws       1
   zeta   ws1  ● π ⠹ STAR: Configure Unique Starship Styles  omp│state    working
                                                      │harness  omp
                                                      │message  -
                                                      │cwd      /Users/me/proj/hiiro
                                                      │cmd      -
                                                      │id       id-a2
                                                      │
                                                      │screen   (press c)
1/4
```

**Marks** show the window's agent state: `●` working, `?` needs_input, `✓` done, `○` idle, `!` errored, and a space for `none` or an unknown state.

**The detail pane** shows the window's title, session, workspace, state, harness, agent message (which carries the prompt text of a `needs_input` window), cwd, running command, and id, then `screen (N)` with the pane's last 20 lines after `c`, or `screen   (press c)` before. Captures are cached per window id until `R` or `H`.

**Hosts.** `--hosts`, or `H` in the screen, also reads `tuios ls --all-hosts --json` and lists each session on another host as one summary row after the local windows: `HOST:SESSION  -    MARK (N windows)`. TUIOS has no verb that lists a remote host's windows, so a window key (Enter, `c`, `n`, `M`, `N`, `m`, `y`) on such a row only shows `remote session: tuios attach --host HOST NAME`; the detail pane shows the same attach command. The header then reads `host:all`.

**Keys**

| Key | Action |
|-----|--------|
| `Enter`, `o` | `tuios jump-window ID`, then quit (the attached client lands on the window) |
| `/` | Search session, title, state, harness, cwd, and id |
| `c` | `tuios capture-pane -s SESSION -w ID --lines 20` into the detail pane |
| `R` | Reload the listing and drop every capture |
| `H` | Toggle remote sessions on or off and reload |
| `g` | Toggle between every window and the current task's windows |
| `n` | Prompt for a name (prefilled with the title) and run `tuios set-window --name` |
| `M` | `tuios set-window --minimize` or `--restore`, by the row's state |
| `N` | Prompt for a name and run `tuios new-window NAME -s SESSION --cwd CWD --print-id --no-focus`; the cursor lands on the new window |
| `m` | Prompt for a message and run `tuios send-agent-message TEXT -s SESSION -w ID --from $TUIOS_PANE_ID` |
| `y` | Copy the window id to the clipboard |
| `j` / `k`, `h` / `l` | Move, scroll long rows |
| `q`, `Esc` | Quit |

Every verb runs through the tuios binary; a failure becomes the status message and the screen stays open. With an empty listing every key reports `no window`.

**Scope.** `g` keeps the windows whose `cwd` is under one of the current task's directories: its primary directory or worktree (`TaskLocation#code_directory`, `#worktree_path`) or its notes home. The current task resolves like `h project ui` (Herdr environment, directory, or the pinned task). Remote rows have no `cwd` and drop out of task scope. When no task resolves, or none of its directories holds a window, `g` reports `no current task to scope to`. The header shows `scope:task(@NAME)`.

**Mail.** `m` needs the pane the screen runs in: `TUIOS_PANE_ID` is the `--from` sender. Outside a tuios pane it reports `no own pane`. Listing, jumping, capturing, and the other keys work from any terminal that can reach the daemon.

**Examples**

```bash
h tuios ui
h tuios ui --hosts
```
