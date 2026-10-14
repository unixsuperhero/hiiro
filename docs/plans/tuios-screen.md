# Tuios screen plan (PR 7 of the Hiiro TUI plan)

`h tuios ui` opens one flat list of every tuios window on this machine, one row per window with its session, workspace, and agent state, a detail pane that can show the pane's last screen lines, and keys to jump, rename, minimize, open, and message. One PR, one new screen class, one listing class, one new `h tuios` subcommand. Decided 2026-10-12 after a survey of the tuios command line and two row layouts rendered from saved listings (Appendix A).

## How to read this

One box is one unit of work with the evidence that checks it. Unit tests drive the screen through `handle_key` against a fake runner that answers canned JSON and records every argv, and assert `frame` literally. The live check launches `h tuios ui` in a window of this very session, drives it with `tuios send-keys`, and keeps the captures. Tests alone do not verify the PR.

## What the survey found

- The hierarchy is host, session, workspace, window. A window is a pane; `TUIOS_WINDOW_ID` and `TUIOS_PANE_ID` are the same id here. Every verb must be given `-s SESSION`, or it answers for the focused session, which may belong to someone else.
- `tuios ls --json` returns every session on this machine with its windows (`id`, `title`, `workspace`, `agent_state`, `agent_harness`, `agent_message`, `foreground_cmd`) in 20 ms. A session with no windows omits the `windows` key. `tuios ls --all-hosts --json` adds the three configured hosts (`hscale`, `m3pro`, `vps`) in 71 ms as `{ hosts: [{ host, status, sessions }] }`.
- `tuios list-windows -s S --json` adds per window `cwd`, `focused`, `minimized`, `index`, `display_name`, `running_cmdline`. `tuios list-workspaces -s S --json` lists nine workspaces per session, almost all unnamed and empty. `tuios list-attention --json` counts what waits for you (`finished`, `ask`, `approval`, `mail`, ...) across hosts.
- `tuios capture-pane -s S -w ID --lines N` returns a pane's last lines in 16 ms. `tuios jump-window ID` moves an attached client to a window in any session. `tuios set-window -w ID --name|--minimize|--restore`, `tuios new-window NAME -s S --cwd DIR`, `tuios send-agent-message TEXT -s S -w ID --from $TUIOS_PANE_ID`, and `tuios peek-prompt -s S -w ID` cover the actions.
- Agent states are `none`, `working`, `needs_input`, `idle`, `done`, `errored`, `unknown`. The skill forbids typing at a pane on `needs_input` and answering another agent's prompt; the screen only reads such a pane.
- Usage from `invocation_resolutions`: `h tuios status` 21, `stop` 14, `start` 13, `setup` 7. Nothing in hiiro navigates tuios today; `lib/hiiro/tuios.rb` is the installer and `Hiiro::Tuios#capture(*args)` already runs the binary and raises `Hiiro::Error` on failure.
- No table maps tuios windows to tasks. A window's `cwd` does: task scope is the windows whose `cwd` is under the current task's code directory, worktree, or home.
- Live session now: 4 sessions, 7 windows, 3 hosts up. Nothing in hiiro drives this surface yet, so every key is new ground and the live drive runs against the real daemon.

## Vocabulary

- **window**. One row. `{ id, title, session, workspace, index, state, harness, message, cwd, focused, minimized, host }`. `host` is `local` unless hosts are shown.
- **session**. `{ name, id, attached, dir, branch, host }`. Not a row; a column and a header group count.
- **listing**. `Hiiro::TuiosListing.load(runner:, hosts: false)`: one `tuios ls --json` (or `--all-hosts`) for sessions and windows, then one `tuios list-windows -s S --json` per local session that has windows for `cwd`, `focused`, `minimized`. About 100 ms locally. `reload` repeats it.
- **mark**. One character for the state: `●` working, `?` needs_input, `✓` done, `○` idle, `!` errored, space otherwise.
- **scope**. `:global` lists every window. `:task` lists windows whose `cwd` is under one of the current task's directories (`TaskLocation` code directory, worktree path, home). `g` toggles.
- **screen**. The last 20 lines of the pane under the cursor, fetched on `c` and cached per window id until `R`.

```ruby
window  = { id: '48d24347-…', title: 'π ⠧ Summarize Session Work', session: 'inbox-839a21ba', workspace: 2, index: 1,
            state: 'working', harness: 'omp', message: '', cwd: '/Users/me/proj/fleet', focused: false, minimized: false, host: 'local' }
row     = 'inbox-839a21ba   ws2  ● π ⠧ Summarize Session Work with Colored Stat   omp'
header  = 'tuios  host:local  scope:global  7 windows in 4 sessions  attention: 2 finished'
```

## PR 7. `h tuios ui`

**Files.** Create `lib/hiiro/tuios_listing.rb`, `lib/hiiro/tuios_screen.rb`, `test/hiiro/tuios_listing_test.rb`, `test/hiiro/tuios_screen_test.rb`. Edit `bin/h-tuios` (one `add_cmd(:ui)`), `lib/hiiro.rb` (requires), `docs/h-tuios.md` (create if absent; `README.md` row), `AGENTS.md`.

**Build.**
- [x] `Hiiro::TuiosListing`. `load(runner:, hosts: false)` where `runner` is a callable `(*argv) -> stdout` defaulting to `Hiiro::Tuios.new.method(:capture)`. Parses `ls --json` (sessions, windows, `windows` absent means none) and `list-windows -s S --json` per local session, merges by window id, and sorts windows by host, session name, workspace, index. With `hosts: true` it also reads `ls --all-hosts --json` and adds one summary row per remote session, since that listing carries no windows (see Risks). Exposes `windows`, `sessions`, `attention` (from `list-attention --json` counts, failures ignored), and `reload`.
- [x] `Hiiro::TuiosScreen < Tui::Screen`. `TuiosScreen.new(listing:, scope: :global, current: nil, runner:, own: ENV.slice('TUIOS_SESSION', 'TUIOS_PANE_ID'))`. Row text `SESSION  wsN  MARK TITLE  HARNESS` with the session column sized to the longest name capped at 18, the title truncated to fit, `host:` prefixed to the session when hosts are shown, and `*` before the session of the pane the screen runs in. Minimized windows show `(min)` after the title. Header `tuios  host:local|all  scope:LABEL  N windows in M sessions  attention: COUNTS` with zero counts dropped, plus the key hint.
- [x] Detail pane. `title`, `session`, `ws`, `state`, `harness`, `message`, `cwd`, `cmd`, `id`, then `screen (n)` with the cached capture lines or `screen   (press c)`, and no separate `peek-prompt` fetch, because `message` already carries the prompt text of a `needs_input` window.
- [x] Keys, through the class key map. `Enter` runs `jump-window ID` and quits. `c` fetches `capture-pane -s S -w ID --lines 20` into the pane. `R` reloads the listing and clears captures. `H` toggles hosts and reloads. `g` toggles scope. `n` prompts `name` (prefilled with the title) and runs `set-window -s S -w ID --name TEXT`. `M` runs `set-window --minimize` or `--restore` by the row's `minimized`. `N` prompts `new window` and runs `new-window NAME -s S --cwd CWD` in the row's session and directory, then reloads with the cursor on the new id (`--print-id`). `m` prompts `message` and runs `send-agent-message TEXT -s S -w ID --from OWN_PANE`; refused with `no own pane` when the screen is not inside tuios. `y` copies the window id. `q` quits. Every verb goes through `runner`, and a `Hiiro::Error` becomes the status message.
- [x] `h tuios ui [--hosts]` in `bin/h-tuios` as `add_cmd(:ui, flags: [:hosts])`, resolving the current task like `h project ui` does. Outside tuios (`TUIOS_ENV` unset) it still lists through the socket; only `m` needs the pane.
- [x] Docs. `docs/h-tuios.md` gains a `ui` section with the key table and the scope rule; `README.md` names `h tuios ui`; `AGENTS.md` gets one paragraph after the `h project ui` paragraph for `TuiosListing` and `TuiosScreen` as the fourth screen.

**You see.** The V2 frame from Appendix A: `inbox-839a21ba   ws2  ✓ π > Implement JSON Task Status Management  omp`, the pane's last lines in the detail pane after `c`, the title changing after `n`, `(min)` after `M`, a new row after `N`, `scope:task(@NAME)` with only that task's windows after `g`, and the client landing on the window after `Enter`.

**Verify, unit.** Done 2026-10-12: tuios_listing_test 11 runs 34 assertions, tuios_screen_test 18 runs 56 assertions (one added after the live drive: a US-ASCII capture with glyphs, since a daemon-spawned window has no locale and `strip` raised), tui_test and project_screen_test unchanged; full suite 708 runs with only the six pre-existing failures. `c` and `R` frames are asserted at 18 rows because the nine fields fill a 14-row pane before the capture lines. `test/hiiro/tuios_listing_test.rb` feeds the saved `ls` and `list-windows` JSON through a fake runner and asserts the window list literally, including a session without `windows`, the merge of `cwd` and `minimized`, and the sort. `test/hiiro/tuios_screen_test.rb` uses the same fake runner, which also records every argv, and asserts `frame(rows: 14, cols: 110)` literally for: the list; `/mdoc` search; `c` showing three canned screen lines; `R` clearing them; `H` adding `m3pro:` rows; `g` with a task whose code directory is one window's `cwd`; `n` sending `['set-window', '-s', S, '-w', ID, '--name', 'x']`; `M` sending `--minimize`; `N` sending `new-window`; `m` sending `send-agent-message` with `--from` and refusing without an own pane; `Enter` sending `['jump-window', ID]` and `run` returning true. Run `ruby -Ilib -Itest test/hiiro/tuios_screen_test.rb`.

**Verify, live.** Done 2026-10-12 in a `ui-drive` window of this session against the real daemon: 21 windows in 5 sessions with `attention: 3 finished`, `/kickoff`, `c` showing this pane's last 20 lines, `H` (`host:all`, 8 sessions) and back, `g` (`no current task to scope to`, the pinned task has no tree), `n` to `ui-drive2` and back, `M` showing `(min)` then restored, `N` opening `ui-child` (`opened ID` in the status line, closed afterwards), `m` delivering `hello from ui` to this pane's inbox as message 6, `y` copying this pane's id, `q`. The first run crashed on `c` with `invalid byte sequence in US-ASCII`, fixed by forcing UTF-8 on the capture. Two lessons for the driver: a search query persists after Enter, so a second `/` must Backspace it first, and a command window on a detached session lingers after its process exits until `tuios run-command -s S CloseWindow ID`. In a window of this session: `ruby -Ilib bin/h-tuios ui`, then `/kickoff`, `c` (the capture shows this conversation's pane), `H`, `g`, `n` renaming the drive window to `ui-drive` and back, `M` then `M` on the drive window, `N` opening `ui-child` in this session (closed afterwards with `exit`), `m` sending `hello from ui` to this pane and reading it with `read-agent-messages`, `y`, `q`. Each step captured and the renames confirmed with `tuios list-windows`. `Enter` is not pressed live because `jump-window` moves an attached client, which is the person's view; the recorded argv is its evidence.

## Alternatives rejected

- **Tree of session, workspace, window** (Appendix A, V1). Mirrors the tuios rail, but each session has nine workspaces, nearly all unnamed and empty, so the tree spends a row per workspace to show nothing. Workspace is a column instead.
- **Attention-first sort.** Tempting for `needs_input` rows, but the order would change under the cursor on every `R`. The mark column and `/` cover it; the header shows the attention counts.
- **Reading another pane's mail.** The mailbox is per pane and the skill says to address only your own. The screen sends mail and never reads a foreign inbox.
- **A tuios workspace per project in this PR.** Belongs with `select-workspace` and `move-window`, which this screen does not need yet.

## Risks

- The toolkit blocks on a key, so states go stale until `R`. A read timeout in `Tui::Screen` that triggers a reload is a toolkit change for a later PR; `R` is the first version.
- `jump-window` on a remote host's window may need `attach --host`; the plan sends `jump-window` and shows the error in the status line if it refuses.
- `h tuios` today runs with `external_commands: false` and `add_cmd` with declared option buckets; the `ui` command uses `flags:` for its boolean option, not `add_subcmd`.
- Titles carry glyphs and spinners (`π ⠧`, `◐`) that change width; the row truncates by characters, so columns may drift by one cell on some fonts.
- `tuios ls --all-hosts --json` turned out to be summary-only (`{hosts:[{host,status,sessions}]}` with `{name, window_count, agent_state?}` per session, `sessions` sometimes `null`, no window ids), and no verb lists a remote host's windows, so `H` / `--hosts` shows one `host:session` row per remote session whose window keys print `tuios attach --host HOST NAME` instead of acting; local windows still come from the plain `ls --json`.

## Appendix A. Prototype evidence

Throwaway script on `Hiiro::Tui::Screen` over `tuios ls --json` saved from the live daemon on 2026-10-12, scratch dir `scratchpad/tuios-proto/` of the session, not in this repo. Timings on the live daemon: `ls --json` 20 ms, `ls --all-hosts --json` 71 ms, `capture-pane --lines 5` 16 ms.

```text
V1 tree (17 rows)                                   V2 flat (7 rows)
    inbox-839a21ba    (4)                           inbox-839a21ba   ws1  ● inbox remote host capture
    ws 1                                            inbox-839a21ba   ws2  ● π ⠧ Summarize Session Work…
      ● inbox remote host capture      omp          inbox-839a21ba   ws2  ✓ π > Implement JSON Task St…
>   ws 2                                            inbox-839a21ba   ws3  ● ◑ Md file open with mdoc…
      ● π ⠧ Summarize Session Work…    omp        > inbox-a73372d8   ws1  ● ◐ PR 1 kickoff
      ✓ π > Implement JSON Task St…    omp          inbox-a73372d8   ws2  ● π ⠴ Complete Remaining St…
    ws 3                                            global           ws1  ● π ⠹ 🌌 STAR: Configure Un…
```
