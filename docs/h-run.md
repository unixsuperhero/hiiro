# h run

Run dev tools (linters, formatters, test suites) against changed files and report what each one actually did. Tools are configured in `~/.config/hiiro/tools.yml` with file extension filters, tool type, and optional named variations.

## Synopsis

```bash
h run [change_set] [tool_type] [file_type_group] [--variation <name>]
h run <subcmd> [args]
```

Positional arguments can appear in any order. When no subcommand is given, matching tools run in the resolved context’s effective directory. Git discovery uses that directory, not the original process cwd, so `h run` from another directory and `t run TASK` enumerate the same repository. Dirty/branch paths are restricted to the effective subtree and passed relative to it.

`t run TASK [--app APP] ...` and `h app run [--app APP] ...` pass the selected context into this same runner. The app selector precedes runner arguments. For example, `h app run --app api all test` runs test recipes in the api directory. Missing explicit directories and ambiguous app/task selectors fail before a tool runs.

**change_set** — which files to consider:

| Value | Description |
|-------|-------------|
| `dirty` | Working tree changes against `HEAD`: modified, added, untracked, and renamed files (read on a copy of the index, so nothing is staged) |
| `branch` | Files committed on this branch vs `main` (`git diff --name-status -M $(git merge-base HEAD main)...HEAD`) |
| `all` | No file filter; each tool runs once with no file arguments |

A renamed file contributes its new path. Deleted paths are never passed to a tool; the run prints how many it left out. A Git failure (not a repository, no merge base with `main`) is an error before any tool runs, never an empty change set.

**tool_type** — filter by type: `lint`, `test`, `format`

**file_type_group** — filter by group name (e.g. `ruby`, `frontend`) as defined in tools.yml

**Options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--variation <name>` | `-v` | Use a named variation of the tool command |

## Commands and filenames

A tool's command is either an argv list or authored shell text, never a string with filenames spliced in:

```yaml
rubocop:
  tool_type: lint
  file_type_group: ruby
  file_extensions: rb
  argv: [bundle, exec, rubocop, --, "[FILENAMES]"]
  variations:
    fix: { argv: [bundle, exec, rubocop, -A, "[FILENAMES]"] }
    summary: { shell: 'bundle exec rubocop "$@" | tail -5' }

jest:
  tool_type: test
  file_type_group: frontend
  file_extensions: ts,tsx
  argv: [yarn, jest, "[FILENAMES]"]
```

- `argv:` runs the program directly; no shell sees the filenames. `[FILENAMES]` must be a whole element and expands to one argument per file, so spaces, quotes, newlines, and `$(...)` arrive unchanged. A file whose name starts with `-` is passed as `./-name` (the same file, never parsed as an option) unless the element before `[FILENAMES]` is `--`, in which case it is passed exactly.
- `shell:` is shell text you wrote. It receives the files as positional parameters, so use `"$@"`; `[FILENAMES]` is not substituted into shell text.
- Errors before anything runs: `[FILENAMES]` inside a larger element (`--files=[FILENAMES]`), any other `[PLACEHOLDER]`, `[FILENAMES]` twice or first, an empty argv, blank shell text, or a definition with both or neither of `argv:` / `shell:`.

## Running, ordering, and outcomes

Selected tools run in tools.yml order. Each command streams its combined stdout/stderr to the terminal and to a log file in bounded chunks (output is a pipe, so tools that color only on a terminal print plain text). A failed command does not stop later commands. Ctrl-C reaches the running command; the run then stops and the remaining commands are skipped.

Every selected tool ends as exactly one of:

| Outcome | Meaning | Log |
|---|---|---|
| `succeeded` | exit 0 | deleted |
| `failed` | nonzero exit, a signal, or a command that cannot start (`exit 127`, the error is the log) | kept |
| `interrupted` | Ctrl-C arrived while it ran | kept |
| `skipped` | no matching files, no such variation on this tool, or not run after an interrupt | none |

```
dirty: 3 files under /work/app (1 deleted, not passed)
==> rubocop: bundle exec rubocop -- a\ b.rb lib/x.rb
...
--- run 20261013144713-ab12cd: 1 failed, 1 succeeded, 1 skipped
✗ rubocop  failed (exit 1)  log: ~/.local/share/hiiro/captures/validation/20261013144713-ab12cd/01-rubocop.log
✓ jest     exit 0
- eslint   skipped: no matching files (js)
Queue these failures for an agent: h run queue 20261013144713-ab12cd
```

The exit status is 130 when the run was interrupted, otherwise the first failed command's status (128 + signal number for a signal), otherwise 0, so a later success never hides an earlier failure.

| Situation | Result |
|---|---|
| No tools match the filters | `ERROR: No tools match tool_type …, file_type_group …`, exit 1 |
| `--variation` that no selected tool defines | `ERROR: Unknown variation …`, exit 1, nothing runs |
| `--variation` that only some tools define | the others are `skipped: no variation 'NAME'` |
| Tools match but no changed file matches a tool | that tool is `skipped`; exit 0 when nothing failed |
| tools.yml still has `command:` strings | `ERROR: … run \`h run migrate\``, exit 1, nothing runs |

Failed and interrupted commands are kept as `h capture` rows (`h capture ls` shows them after the run, in any later process) with the command, cwd, run id, start and finish times, exit status or signal, task, and the context provenance (task and how it was chosen, app, root and its source, directory and its source).

## Subcommands

### `h run queue [RUN_ID]`

Writes one pending queue prompt, `validation-RUN_ID.md`, for a run's retained failures (default: the most recent run with a failure). Nothing is queued automatically and nothing launches; start it with `h queue run` when you choose to. The prompt keeps the run's `task_name`, `app`, and `dir` (relative to the task or app directory) in its frontmatter, so the queue resolves the same context, and its body names each failed command, its cwd, outcome, log path, and times. A taskless run carries its absolute directory in the body only; the queue resolves taskless prompts from where it runs. Runs from `h js all` and `h ch make` can be queued the same way.

### `h run migrate`

The explicit cutover from the old `command:` strings. Each command made only of plain words becomes `argv:`; one with shell syntax becomes `shell:` with every unquoted, standalone `[FILENAMES]` replaced by `"$@"`. A command where `[FILENAMES]` is quoted or embedded is left unchanged and reported for a manual edit (exit 1). The original file is copied to `tools.yml.YYYYMMDDHHMMSS.bak` first; other keys, tool order, and variations are kept.

```
rubocop: rubocop [FILENAMES]
  -> {"argv":["rubocop","[FILENAMES]"]}
Backup: ~/.config/hiiro/tools.yml.20261013144713.bak
```

### `h run add`

Add a new tool via an editor template. Opens a YAML template in `$EDITOR`:

```yaml
new_tool:
  tool_type: lint
  argv:
  - echo
  - "[FILENAMES]"
  variations: {}
  file_type_group: ''
  file_extensions: ''
```

### `h run config`

Open `~/.config/hiiro/tools.yml` in your editor.

### `h run ls`

List all configured tools with their type, group, extensions, and variations.

```
rubocop         [lint]  ruby        exts: rb (fix, summary)
jest            [test]  frontend    exts: ts,tsx
```

### `h run rm`

```bash
h run rm <name>
```

Remove a tool by name.

## Other validation commands

`h js all` runs `yarn fmt`, `yarn typecheck`, `yarn test`, and `yarn build` in the current directory through the same runner: all four run, failed logs are kept under the run id (no longer written to `~/notes/files`), and it exits with the first failure's status. `h ch make` streams the personal desktop build adapter (`bun run dist` / `pnpm dist` in the mapped tree) through it too, then checks the build product.
