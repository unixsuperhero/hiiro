# The shared picker and persistent pruning

Every interactive choice among commands, files, tasks, projects, branches, PRs,
and saved information opens one picker (`Hiiro::PickerScreen`, built on
`Hiiro::Tui::Screen`). Each picker has a stable name, and each choice has a stable
identity. Exclusion rules hide choices from a picker across searches and later
invocations. A rule never deletes, closes, or changes the resource behind a
choice. Removing the rule makes the choice selectable again.

## Keys

| Key | Action |
|---|---|
| `j` / `k`, arrows | Move |
| `/` | Search the labels; the query stays after Enter or Escape |
| `Enter` | Choose the row under the cursor; with marks, choose the marked rows |
| `Tab` | Mark or unmark the row, in pickers that take several choices (`h branch clean`) |
| `Ctrl-E` | Edit this picker's list and rules in `$EDITOR` |
| `Ctrl-X` | Switch between the choices and the excluded rows. Each excluded row shows the rule that hides it |
| `u` | In the excluded view, remove the rules that hide the row under the cursor |
| `q` / `Esc` | Cancel |

To use a different edit key, set `HIIRO_PICKER_EDIT_KEY=ctrl-o` (any `ctrl-LETTER`).
The header shows the edit key in use.

After an edit or a restore, the picker previews the change. It lists each rule
to be added (`+ rule`) or removed (`- rule`), each choice that becomes excluded
(with the rule that matches it), and each choice that is restored. `y` (or
Enter) saves; `n` (or Esc) discards. Nothing is written before `y`. Afterwards the
picker returns with the same query and the same marks, except marks on rows that
are now hidden. The cursor stays on the same row. If that row is now hidden, the
cursor moves to the next row still listed, or to the previous one when nothing
follows.

## The edit document

`Ctrl-E` writes a YAML document and opens it with `InputFile`:

```yaml
# Picker branches (branch items). Save and quit to preview; nothing is saved until you confirm.
# ...
scope: task
items:
- ["branch","/src/app","main"]  # main
- ["branch","/src/app","wip/spike"]  # wip/spike
rules:
- {id: 4, scope: picker, mode: glob, field: name, pattern: "tmp/**"}
```

- `items` is a snapshot of the rows listed when you pressed `Ctrl-E`, after the
  search filter. Each line is the item's identity; the comment is only its
  label. Deleting a line adds an `exact` rule for that identity. Rows that were
  filtered out, already excluded, or added later are not in the snapshot, so
  this edit can never exclude them. A line that is not in the snapshot is an
  error.
- `rules` lists the rules that apply here. Delete a line to remove that rule.
  Change a line to replace it. Add a line without an `id` to create a rule.
- `scope` is the default scope for new rules and for deleted rows. Any rule
  may name its own `scope`.

An invalid document saves nothing. This covers unparseable YAML, unknown keys,
fields, modes, or scopes, a scope with no current task or project, an unknown
rule id, and a malformed regex or glob. The status line shows the error. The
edited text is kept under `~/.local/share/hiiro/edits/picker-*.yml`, and the
next `Ctrl-E` reopens it with the error at the top.

## Rules

```js
// one row of picker_exclusions (SQLite, owned by Hiiro::PickerExclusion)
{ id: 4, picker: "branches", scope: "task", scope_key: "3", mode: "glob",
  field: "name", pattern: "wip/**", label: null, created_at: "2026-10-13T09:00:00-04:00" }
```

| Scope | Applies to |
|---|---|
| `picker` | This picker, in any task or directory |
| `task` | This picker, only while the current task is the one it was saved in (`scope_key` is the task ID) |
| `project` | This picker, only inside that project's directory (`scope_key` is the project name) |
| `global` | Every picker whose items have the field. Global applies only when a document says `scope: global`, and the preview warns before saving it |

The task comes from `CurrentTask` inference for the working directory (calling
workspace, then directory, then pin), or from the task a `t` command is acting
on. The project is the `h project` entry whose directory holds the working
directory. Table visibility (`TableScope`) is separate and grants nothing here.

| Mode | Matches when |
|---|---|
| `exact` | The item's identity equals the pattern, a JSON list. Field `id` only. A deleted row becomes an exact rule |
| `literal` | The field equals the pattern |
| `substring` | The field contains the pattern |
| `regex` | A Ruby (Onigmo) regular expression finds a match anywhere in the field (anchor with `^`/`$` or `\A`/`\z`). The time limit is 1 second |
| `glob` | The whole field matches the glob |
| `extglob` | The whole field matches the glob with extended operators |

All modes are case-sensitive. A regex can use `(?i)`. On `path` fields, the
item and a `literal`, `glob`, or `extglob` pattern are normalized first: `/`
separators, repeated slashes collapsed, and a leading `./` removed, so
`./scratch.md` matches `scratch.md`.

Glob syntax (implemented in Ruby, never passed to a shell):

| Pattern | Meaning |
|---|---|
| `*` | Any run of characters within one segment (no `/`) |
| `?` | One character other than `/` |
| `[abc]` `[a-z]` `[!x]` `[^x]` | One character in (or not in) the class, never `/` |
| `**/` | Zero or more whole segments: `**/*.bak` matches `a.bak` and `x/y/a.bak` |
| `**` | Anywhere else: any characters, including `/` |
| `\c` | `c` literally |

`extglob` adds these, where LIST is alternatives separated by `|` and confined to one segment:
`?(LIST)` zero or one, `*(LIST)` zero or more, `+(LIST)` one or more, `@(LIST)` exactly one,
`!(LIST)` anything except one of them. `**/*.@(bak|tmp)` matches every `.bak`
and `.tmp` file. An unclosed `(` or a `/` inside a list is an error. Brace
expansion (`{a,b}`) is not supported; use `@(a|b)`. Dotfiles get no special
treatment.

## Pickers, identities, and fields

| Family | Pickers | Identity | Fields |
|---|---|---|---|
| command | `<bin>-commands` (ambiguous `h edit NAME` / `h bin edit NAME` on a terminal) | `["command", kind, name, source file]` | `name`, `kind`, `path` |
| file | `task-file`, `task-directory`, `task-document` (`t file open`, `t dir open`, `t doc open`), `pr-templates` (`h pr from-template`) | `["file", base, path relative to base]`; outside the base, the base is `/` | `path`, `name`, `base` |
| task | `tasks` (task choice in `t`, `h task`, the task context), `task-values`, `task-branches` | `["task", task id]` (`name:NAME` for a task without one) | `id`, `name`, `path` (tree) |
| project | `projects` (`h project`, the project resolver, legacy `~/proj` fallback) | `["project", name]` | `name`, `path` |
| branch | `branches` (`h branch select|copy|co|rm`), `merged-branches` (`h branch clean`) | `["branch", repository, name]`; the repository is the main checkout, so every worktree shares it | `name`, `repo` |
| pr | `my-prs` (`h pr select|copy|track`), `tracked-prs` (`h pr` actions and the `pr` resolver), `pinned-prs` (`h branch`) | `["pr", "owner/name", number]` | `number`, `repo`, `branch`, `name` (title) |
| saved | `links`, `obsidian-notes`, `portfolio-docs`, `saved-files`, `registry` / `registry-TYPE`, `task-link`, `task-pr` | `["saved", store, key]`: link ID, vault-relative note, Portfolio ID, saved file, registry row ID, task resource ID | `store`, `id`, `name`, `target` |

Labels (the text in a row) are only for display. Two rows with the same label
remain separate choices. A rule written for an identity still matches after
the label changes. Commands that print a value (`h branch select`,
`h registry select`, `h pr select`, `h project select`) print it from the chosen
record, never by parsing the row text.

Exclusions apply to interactive choices only. An explicit name, number, or
path on the command line still resolves as before. `h branch clean --force`
offers no choice, so its rules do not apply.
