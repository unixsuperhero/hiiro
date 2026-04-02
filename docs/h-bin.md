# h-bin

List and edit hiiro bin scripts (`h-*` executables found in PATH).

## Usage

```
h bin <subcommand> [filters...]
```

## Subcommands

### `list`

Print the paths of all `h-*` executables found in PATH. Optionally filter by name patterns; each pattern is matched as `h-<pattern>` or `<pattern>`.

**Args:** `[subcmd_name...]`

### `edit`

Open matching `h-*` executables in your editor. Patterns work the same as `list`.

**Args:** `[subcmd_name...]`
