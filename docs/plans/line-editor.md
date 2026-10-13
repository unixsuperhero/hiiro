# Line editor plan (PR 8 of the Hiiro TUI plan)

Every text prompt on `Hiiro::Tui::Screen` gets a cursor, the usual editing keys, and trigger-character completion: `@` offers projects, `#` offers tags, and a prompt whose whole value is a name (a table, a branch, a task) completes the field itself. Candidates rank fuzzily and show inline in the status line. One PR, one value object, one ranker, one `prompt` keyword, and the old pick mode deleted. Decided 2026-10-12 after a throwaway editor rendered two layouts over the real project names (Appendix A).

## How to read this

One box is one unit of work with the evidence that checks it. Unit tests drive the editor directly and the screens through `handle_key`, and assert `frame` and the status line literally. The live check types into real prompts in tuios windows against a database copy and confirms what was written with `h db q`. Tests alone do not verify the PR.

## What the survey found

- Nineteen `prompt` calls across the four screens. Six take a name the system already knows: `table` and `move to table` (TableScreen), `tags` (TableScreen), `branch` (ProjectScreen), `new task` (TaskScreen, where `parent/child` needs the parent's name). Four take free text where a project or tag reference is natural: `todo`, `next action`, `waiting on` (TaskScreen), `message` (TuiosScreen). The rest are confirmations and paths.
- The prompt today appends and backspaces only. `Left`, `Right`, `Home`, `End`, `Tab`, and `Ctrl-U` are ignored, and `Home`/`End` arrive as an unknown escape that `read_key` reports as `:escape`, which cancels the prompt.
- Pick mode (`@` in list mode) is one caller: TableScreen picks a table by prefix. It is thirty lines of its own mode, query, and status line that a field-completing prompt replaces.
- Candidate pools are small and fast: 127 project names in 1 ms from `Hiiro::Projects#all`, 5 tables, 7 tasks, 0 registry tags today (todo tags live as text on `TodoItem`). Ranking 127 names takes 0.2 ms per keystroke.

## Vocabulary

- **editor**. The text under edit. `{ text, cursor, selected }` plus the prompt's trigger table. Owned by `Tui::LineEditor`; `state.prompt_text` reads through it so every existing screen keeps working.
- **trigger**. One character that starts a token, or `''` for the whole field. `{ '@' => source, '#' => source }` or `{ '' => source }`.
- **source**. A callable returning candidate strings, run once per prompt on the first token and cached.
- **token**. The trigger and the text after it, ending at the cursor, starting at the field start or after a space. `{ start: 16, trigger: '@', query: 'hii' }`, or nil when the cursor is not in one.
- **choice**. A ranked candidate. `Tui::Fuzzy.rank(candidates, query)`: prefix matches first, then word-start matches (`hiiro-config` for `cfg`), then subsequences by gap count; ties by length then name.

```ruby
editor   = { text: 'fix the pane in @hii', cursor: 20, selected: 0 }
triggers = { '@' => -> { Hiiro::Completions.projects }, '#' => -> { Hiiro::Completions.tags } }
token    = { start: 16, trigger: '@', query: 'hii' }
status   = 'todo: fix the pane in @hii_  @hii ▸ [hiiro] hiiro-config rehiiro'
after    = { text: 'fix the pane in @hiiro ', cursor: 23 }          # Tab accepted the bracketed choice
```

## PR 8. `Tui::LineEditor`

**Files.** Edit `lib/hiiro/tui.rb`, `lib/hiiro/table_screen.rb`, `lib/hiiro/task_screen.rb`, `lib/hiiro/project_screen.rb`, `test/hiiro/tui_test.rb`, `test/hiiro/table_screen_test.rb`, `test/hiiro/task_screen_test.rb`, `test/hiiro/project_screen_test.rb`, `docs/h-table.md`, `docs/t.md`, `docs/h-project.md`, `README.md`, `AGENTS.md`. Create `lib/hiiro/completions.rb`, `test/hiiro/line_editor_test.rb`, `test/hiiro/completions_test.rb`.

**Build.**
- [ ] `Tui::Fuzzy.rank(candidates, query)` in `tui.rb`. Empty query returns the candidates unchanged. Case-insensitive. Scores: 0 prefix, 1 word start on `- _ / .` and space, else 2 plus the number of gaps in the subsequence; non-subsequences drop out. Stable order by score, length, name.
- [ ] `Tui::LineEditor.new(text:, triggers:)`. `text`, `cursor`, `selected`; `insert(char)`, `backspace`, `delete`, `left`, `right`, `home`, `end`, `kill_line`; `token`, `choices(limit: 8)`, `select(delta)`, `accept`. `accept` replaces the token with the selected choice; a trigger token gains one trailing space, a field completion does not. No choices when the field text already equals the top choice, so a completed field shows nothing more.
- [ ] `read_key` learns `\t` as `:tab`, `\u0015` as `:ctrl_u`, `\e[H` `\e[F` `\e[1~` `\e[4~` as `:home` and `:end`, and `\e[3~` as `:delete`. Unknown sequences still read as `:escape`.
- [ ] `prompt(label, default: '', complete: {}) { |text| }`. `complete` is the trigger table. Prompt mode keys: printable inserts at the cursor, `Backspace`, `Delete`, `Left`, `Right`, `Home`, `End`, `Ctrl-U`; `Up` and `Down` move `selected`; `Tab` accepts; `Enter` accepts when a token has choices and the editor text does not already equal that choice, otherwise submits; `Escape` cancels the prompt; `Ctrl-C` quits. Status line `LABEL: head_tail` followed by `  TRIGGERQUERY ▸ [first] second third` truncated to the line, bracket on the selected choice.
- [ ] Pick mode deleted. `state.mode` loses `:pick`, `state.pick_query`, `pick_trigger`, `pick_candidates`, `picked`, `pick_mode_key`, `pick_matches`, `pick_status`, and `leave_pick` go. TableScreen binds `key '@', :pick_table` and opens `prompt('table', complete: { '' => -> { Table.all.map(&:name) } })` with the same `picked` behaviour inside the block. Checked 2026-10-12: nothing under `bin/` or `lib/` outside the toolkit and TableScreen reads pick state.
- [ ] `Hiiro::Completions` in `lib/hiiro/completions.rb`: `projects` (`Projects.new.all.keys` sorted), `tags` (distinct `Tag` names plus the comma-split tags of every `TodoItem`, sorted unique), `tables` (`Table.all` names), `tasks` (`TaskRecord` names sorted), `branches(repo_path)` (`Git::Branches.fetch`). Each is a plain method returning an Array; screens wrap them in lambdas so nothing runs until a token appears.
- [ ] Prompts wired. TableScreen: `table` and `move to table` complete the field from `tables`; `tags` completes `#` from `tags` and the field from `tags`. TaskScreen: `todo`, `next action`, `waiting on` complete `@` from `projects` and `#` from `tags`; `new task` completes the field from `tasks`. ProjectScreen: `branch` completes the field from `branches(repo.path)` of the row's repo. TuiosScreen `message` completes `@` from `projects`. Confirmations and `path` prompts take no `complete`.
- [ ] Docs. `AGENTS.md` Tui section shows the new `prompt` signature, `LineEditor`, `Fuzzy.rank`, and `Completions`, and drops the `@` pick lines. `docs/h-table.md`, `docs/t.md`, `docs/h-project.md` gain one paragraph on editing keys and which prompts complete what. `README.md` names the completion in the `h table` row.

**You see.** In `t ui`, pressing `t` and typing `fix the pane in @hii` shows `@hii ▸ [hiiro] hiiro-config rehiiro` at the end of the status line, `Tab` turns the token into `@hiiro `, `#u` offers `[ui] urgent`, and `Enter` twice (accept, then submit) adds the todo with both references in its text. In `h table`, `@` opens `table: _  ▸ [link] project sha sound t`, typing `pr` narrows to `[project]`, and `Enter` switches the screen to that table.

**Verify, unit.** `test/hiiro/line_editor_test.rb` asserts, with literal text and cursor values: insert at the cursor after `Left`; `Home`, `End`, `Delete`, `Ctrl-U`; a token only when the trigger starts the field or follows a space; no token across a space; `choices` for `@hii` over a fixed list equal to `%w[hiiro hiiro-config rehiiro]`; `accept` producing `fix @hiiro ` with the cursor at 10; field accept producing `link` with no trailing space and no further choices. A `Fuzzy.rank` test asserts the order for `hi`, `cfg`, `hro`, and `h2` over a fixed list. `test/hiiro/tui_test.rb` drives a screen with a completing prompt and asserts the status line literally after typing, after `Down`, after `Tab`, after `Enter` with a choice open (text changed, mode still `:prompt`), and after a second `Enter` (block called with the text); the two pick tests become one `@` test on TableScreen. `test/hiiro/completions_test.rb` seeds one task, one todo with tags `a,b`, one registry tag `c`, one table, and asserts each method's Array. The four screen tests keep passing unchanged except where they drove pick mode. Run `ruby -Ilib -Itest test/hiiro/line_editor_test.rb` and the four screen tests.

**Verify, live.** In tuios windows against a database copy through `HIIRO_TEST_DB`: `t ui`, `t`, type `fix the pane in @hii`, capture (choices visible), `Tab`, type `for #u`, `Down`, `Tab`, `Enter`, and confirm the todo text with `h db q` on the copy; `n` on a task with `Left` ×3 and an insert to show mid-text editing in the capture and in the DB; `h table`, `@`, `pr`, `Enter`, capture showing the `project` table; `h project ui --root` on the throwaway root, `a`, `f`, `Tab` completing `feat`, `Escape`. Each step captured; the driver clears the search query between searches and closes its windows with `run-command CloseWindow`.

## Alternatives rejected

- **A popup list above the status line** (Appendix A, V2). Reads well but hides list rows while open and needs the footer height to change per keystroke, which every `frame` assertion in the four screen tests encodes. The inline line costs nothing in layout and the bracket marks the selection.
- **Keeping pick mode beside the completing prompt.** Two ways to choose a name from a list in one toolkit. The prompt covers the one caller, so pick mode is deleted in the same PR.
- **Shelling out to fzf for completion.** The toolkit rule from the engine decision: no fuzzy finder inside a screen. The in-process ranker is thirty lines and measured fast enough.
- **Enter always submits, Tab is the only accept.** Shorter rules, but on the `table` prompt it means typing `pr`, `Tab`, `Enter` for what every shell does on one `Enter`. The `▸` indicator shows when `Enter` will accept instead.

## Risks

- `Enter` accepting a choice instead of submitting can surprise in free text: `fix @hi` then `Enter` completes to `@hiiro ` and waits for a second `Enter`. The status line shows the open token, and `Escape` still cancels.
- Terminals differ on `Home` and `End` sequences; the four listed cover xterm, tuios, and the VT220 forms. An unlisted one still reads as `:escape` and cancels the prompt, as today.
- `Completions.projects` reads `~/proj` once per prompt. If a screen opens prompts in a loop the directory listing repeats; at 1 ms it does not matter.
- Deleting pick mode changes `Tui::State`; any screen outside this repo that reads `state.pick_query` breaks. The repo has none.

## Appendix A. Prototype evidence

Throwaway `scratchpad/complete-proto/proto.rb` of the session (not in this repo) on 2026-10-12: an editor struct with the token rule, the ranker, and two status renderings over the real 127 project names and the 5 tables.

```text
ranking            hi  -> hiiro, hiiro-config, rehiiro, thinktank, procedural-thinking, home-ic
                   cfg -> hiiro-config          h2 -> h2, old-home.2020          tu -> tuios, tuios-inbox, tuios-tasks
V1 inline          todo: fix the pane in @hii_  @hii ▸ [hiiro] hiiro-config rehiiro procedural-thinking
                   todo: fix the pane in @hiiro-config for #u_  #u ▸ [ui] urgent bug tuios
                   move to table: l_  l ▸ [link]
V2 popup           > hiiro
                     hiiro-config
                     rehiiro
                   todo: fix the pane in @hii_
timing             rank 127 names x200: 37 ms
```
