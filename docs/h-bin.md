# h-bin

Create, list, and edit Hiiro bin scripts.

`h bin add` creates executables in `~/bin`. The `list` and `edit` commands use `Hiiro::Bins` to scan the current `PATH`.

## Synopsis

```bash
h bin <subcommand> [names...]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `add NAME [COMMAND ...]` | Create an executable template without overwriting an existing file |
| `list [names]` | List matching bin files |
| `edit [names]` | Open matching bin files in editor |

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

Open matching `h-*` bin files in your editor. With no arguments, opens `h-bin` itself.

**Examples**

```bash
h bin edit
h bin edit branch
h bin edit pr notify
```
### list

List `h-*` executables found in PATH. With no arguments, lists all. With names, filters to those matching `h-<name>` or `<name>` patterns. Deduplicates by basename (first occurrence wins).

**Examples**

```bash
h bin list
h bin list branch pr
```
