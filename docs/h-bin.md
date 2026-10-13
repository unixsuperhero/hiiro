# h-bin

Create Hiiro bin scripts, and inspect the root `h` command catalog.

`h bin add` creates executables in `~/bin`. `list`, `edit`, `complete`, and `docs` read the same catalog `h` dispatches through (`Hiiro::RootCommands` registrations plus eligible `h-*` executables on the current `PATH`), so they agree with `h` on winners, aliases, shadowed copies, and ambiguity. None of them runs a candidate, opens the database, or creates config directories.

## Synopsis

```bash
h bin <subcommand> [names...]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `add NAME [COMMAND ...]` | Create an executable template without overwriting an existing file |
| `list`, `ls [prefixes]` | List catalog entries, with shadowed claims |
| `edit [names]` | Open the source each name dispatches to |
| `complete [word]` | Print every command name and alias starting with `word` |
| `docs [--json]` | Print the catalog as a Markdown table, or as JSON |

### add

Create `~/bin/h-NAME`. An optional `h-` prefix is accepted. Executable names must
start with a letter or digit and contain only letters, digits, underscores, or
hyphens.

```sh
h bin add scratch
```

With no command arguments, the generated file contains:

```ruby
#!/usr/bin/env ruby

require 'hiiro'

Hiiro.run do
end
```

To include empty command blocks:

```sh
h bin add josh list show
```

```ruby
#!/usr/bin/env ruby

require 'hiiro'

Hiiro.run do
  add_cmd :list do
  end

  add_cmd :show do
  end
end
```

Command names are serialized as Ruby symbols, including quoted symbols for
names such as `hello-world`. Generated files are executable. Existing files
and symlinks are refused, and no editor or generated command is launched.
Native Hiiro options handle `--help` and the `--` end-of-options marker.

### edit

Open the source each name resolves to — the same file `h NAME` runs. An inline command opens the file that registers it; an alias opens its command. With no arguments, opens `h-bin` itself. An ambiguous or unknown name prints an error, exits 1, and opens nothing; `h edit NAME` behaves the same.

**Examples**

```bash
h bin edit
h bin edit branch
h bin edit pr notify
h bin edit svc         # lib/hiiro/root_commands.rb (service)
```

### list

List catalog entries: name and aliases, arguments, kind (`inline` or `external`), and source (with the origin of an external file in brackets), followed by any shadowed claims. With prefixes, lists the entries whose name or alias starts with one of them.

```text
  pr          (external)  $BIN/h-pr  [modified (managed hiiro 0.1.393)]
              shadows external /Users/me/proj/hiiro/bin/h-pr  [user]
  pr-monitor  (external)  $BIN/h-pr-monitor  [managed hiiro 0.1.393]
```

**Examples**

```bash
h bin list
h bin list branch pr
```

### complete

Print, one per line and sorted, every name and alias that starts with `word` (all of them without a word). Each printed word resolves exactly to one catalog entry.

```bash
h bin complete se      # service, session, setup, ...
```

### docs

Print the catalog as a Markdown table (`Command | Aliases | Kind | Arguments | Source | Origin | Shadowed`). With `--json`, print an array of entries:

```js
[{ name: "service", kind: "inline", source: "/path/lib/hiiro/root_commands.rb:171",
   aliases: ["svc"], arguments: "[*svc_args]", shadowed: [], origin: "package hiiro 0.1.393" }]
```
