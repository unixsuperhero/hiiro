# h-ruby iface / h-iface rb

Print the declaration lines of Ruby files by named pattern group. This is text
matching (`Hiiro::TextInspection`), not a Ruby parser; the patterns live in the
process, so concurrent runs with different groups never share a file.

```sh
h ruby iface [GROUP...] FILE...
h iface rb [GROUP...] FILE...      # same operation
```

| Group | Matches |
|---|---|
| `class` | `class`, `module` |
| `attributes` | `attr_reader`, `attr_writer`, `attr_accessible` |
| `methods` | `def`, `alias`, `alias_method`, `def_delegator`, `Struct`, `OStruct`, `Data` |
| `accessmodifiers` | `public`, `private`, `protected` |
| `tests` | `context`, `describe`, `it` |
| `lets` | `let` |
| `hiiro` | `Hiiro`, `build_child`/`make_child`/`run_child`, `add_cmd`/`add_subcmd`/`run_cmd`/…, `add_default` |
| `all` (alias) | every group |
| `iface` (alias, the default) | `class`, `attributes`, `methods` |

An argument naming an existing file is a file; anything else is a group, chosen
by exact name or unique prefix (`att`, `me`). An ambiguous prefix
(`a` → `accessmodifiers, all, attributes`) or unknown group is an error, exit 1.

Output per file: a blank line, `  FILE: PATH`, an `=` underline of the same
width, the matching lines verbatim, and a blank line. Every file is printed;
the command exits 1 when any file had no matching line.

Differences from the installed commands (deliberate): with no group the
installed `h ruby iface` printed only headers (its pattern file was empty) and
now uses the `iface` default; a prefix matching several groups selected all of
them and is now an error; `rg` and the shared `/tmp/patterns` file are gone;
`h iface rb` stopped at the first file without declarations and now prints
every file before exiting 1.
