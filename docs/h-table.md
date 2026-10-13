# h-table

Browse and edit every registry table (links, sounds, pins, project aliases, anything stored with `h registry`) in a TUI, with CLI twins for scripts.

A **table** is one named list (`registry.resource_type`); an **entry** is one row of it: `{ table, name, value, short, desc, tags, task }`.

## Synopsis

```bash
h table [table]            # open the TUI across every table, or one table
h table ui [table]         # same; use this when a table name collides with a subcommand prefix
h table <subcommand> [args]
```

## TUI

```
tables  scope:global  table:*
[/]search [@]table [g]scope [a]dd [r]ename [e]dit [d]elete [T]ag [m]ove ...
>   link     gh               git…│table  link
    link     hn               new…│name   gh
  * sound    ping             Pin…│short
                                  │desc
                                  │value  github.com
                                  │tags   daily
                                  │task   -
                                  │
                                  │actions:
                                  │  o  open {value}
                                  │  y  pbcopy <<< {value}
1/3
```

Rows are `mark table name value #tags`, ordered by table then name. `*` marks a row.

| Key | Action |
|-----|--------|
| `j` `k` / arrows | Move |
| `h` `l` | Scroll the list sideways |
| `/` | Search name, value, description, short name, and tags |
| `@` | Pick a table: a `table:` prompt that completes table names; Enter accepts the bracketed choice, a second Enter switches to it |
| `g` | Toggle scope between global and the current task |
| `a` | Add: prompts for name, value, then table (prefilled with the filter or the current row's table). In task scope the entry is attached to the task |
| `r` | Rename the current entry |
| `R` | Rename the current row's table (every entry moves) |
| `e` | Edit the current value |
| `d` | Delete the marked rows (or the current row) and their tags after a `y` |
| `T` | Tag the marked rows (or the current row): space-separated tags, `-tag` removes one |
| `m` | Move the marked rows (or the current row) to another table |
| Space | Mark / unmark the current row and move down |
| any other letter | Run that letter's action from `tables.yml` (`o` open and `y` copy by default) |
| `q` / Esc / Ctrl-C | Quit |

Prompts appear in the status line as `label: text_`. Enter submits, Esc cancels.

**Editing in a prompt.** Left, Right, Home, End, Delete, and Ctrl-U (clear) edit the text; while choices show after `▸`, Up and Down move the `[ ]` selection, Tab accepts it, and Enter accepts it before a second Enter submits. The `table` prompts (`@`, the last `a` prompt, `m`) complete table names, and `T` completes each space-separated word from existing tags.

## Scope

`h table` starts in task scope when the current directory or Herdr pane resolves to a task, and shows only entries whose `task_id` is that task. Otherwise it starts global and shows every entry. `g` flips between the two; the header shows `scope:task(@NAME)` or `scope:global`.

## Actions (`~/.config/hiiro/tables.yml`)

Per-table shell command templates keyed by one letter. `{value}`, `{name}`, and `{table}` are shell-escaped. Every table gets `o` (`open {value}`) and `y` (`pbcopy <<< {value}`); a table's own letters override them.

```yaml
link:
  c: "echo {value} | pbcopy"
dir:
  o: "open -a Finder {value}"
  c: "cd {value} && $SHELL"
```

The status line reports `ran: <command>` after an action.

## CLI subcommands

Output is plain text for scripts. Failures print to stderr and exit 1.

| Subcommand | Output |
|------------|--------|
| `tables` | `NAME  COUNT` per table |
| `ls` / `list [table] [-g]` | `TABLE<TAB>NAME<TAB>VALUE` per entry, `No entries.` when empty. Current scope unless `-g/--global` |
| `add <table> <name> <value> [-s short] [-d desc] [--task]` | `added TABLE/NAME`; `exists: TABLE/NAME` on a duplicate; `--task` attaches the current task (`No current task.` without one) |
| `rm` / `remove <table> <name>` | `removed TABLE/NAME` (its tags go too); `not found: TABLE/NAME` |
| `mv <table> <new_table>` | `renamed TABLE to NEW`; fails when the new table already has rows |
| `set <table> <name> <value>` | `set TABLE/NAME` |
| `get <table> <name>` | The value only |
| `tag <table> <name> <tag...>` | `tags TABLE/NAME: a b` |
| `untag <table> <name> <tag...>` | `tags TABLE/NAME: b` |

Names are exact (no prefix or alias matching).

**Examples**

```bash
h table add link gh https://github.com -d "GitHub"
h table add dir notes ~/notes --task
h table ls -g link
h table get link gh
open "$(h table get link gh)"
h table tag link gh work daily
h table set link gh https://github.com/unixsuperhero
h table mv link links
h table rm links gh
```

`h registry` reads and writes the same rows under its older interface.
