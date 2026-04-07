# h run

Run dev tools (linters, formatters, test suites) against changed files. Tools are configured in `~/.config/hiiro/tools.yml` with file extension filters, tool type, and optional named variations.

## Synopsis

```bash
h run [change_set] [tool_type] [file_type_group] [--variation <name>]
h run <subcmd> [args]
```

Positional arguments can appear in any order. When no subcommand is given, matching tools are run against changed files.

**change_set** — which files to consider:

| Value | Description |
|-------|-------------|
| `dirty` | Git working tree changes (default) |
| `branch` | Files changed vs `main` (`git diff main...HEAD`) |
| `all` | All files (no file filter) |

**tool_type** — filter by type: `lint`, `test`, `format`

**file_type_group** — filter by group name (e.g. `ruby`, `frontend`) as defined in tools.yml

**Options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--variation <name>` | `-v` | Use a named variation of the tool command |

## Subcommands

### `h run add`

Add a new tool via an editor template. Opens a YAML template in `$EDITOR`:

```yaml
new_tool:
  tool_type: lint
  command: echo [FILENAMES]
  variations: {}
  file_type_group: ''
  file_extensions: ''
```

`[FILENAMES]` is replaced with the space-joined list of matching files when the tool runs.

### `h run config`

Open `~/.config/hiiro/tools.yml` in your editor.

### `h run ls`

List all configured tools with their type, group, extensions, and variations.

```
rubocop         [lint]  ruby        exts: rb (quick, fix)
jest            [test]  frontend    exts: ts,tsx
```

### `h run rm`

```bash
h run rm <name>
```

Remove a tool by name.

## Config format

`~/.config/hiiro/tools.yml`:

```yaml
rubocop:
  tool_type: lint
  command: "rubocop [FILENAMES]"
  file_type_group: ruby
  file_extensions: "rb"
  variations:
    quick: "rubocop --only Style [FILENAMES]"
    fix: "rubocop -A [FILENAMES]"

jest:
  tool_type: test
  command: "yarn jest [FILENAMES]"
  file_type_group: frontend
  file_extensions: "ts,tsx"
```
