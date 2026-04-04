# h-bin

List and edit hiiro bin scripts (`h-*` executables found in PATH).

## Synopsis

```bash
h bin <subcommand> [filters...]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `list` | Print paths of all `h-*` executables in PATH |
| `edit` | Open matching `h-*` executables in your editor |

## Subcommand Details

### `list`

Print the full paths of all `h-*` executables found in PATH. Optionally filter by name patterns — each pattern matches as `h-<pattern>` or `<pattern>` directly. When multiple executables with the same basename exist in different PATH directories, only the first one (highest priority) is shown.

```bash
h bin list           # list all h-* executables
h bin list branch    # list h-branch only
h bin list br pr     # list h-branch and h-pr
```

### `edit`

Open matching `h-*` executables in your editor. Patterns work the same as `list`. With no args, opens the `h-bin` script itself.

```bash
h bin edit           # edit h-bin itself
h bin edit branch    # edit h-branch
h bin edit pr app    # edit h-pr and h-app
```

## Examples

```bash
# Find where h-pr lives
h bin list pr

# Edit the h-branch bin script
h bin edit branch

# Open multiple related bin files at once
h bin edit pane window session buffer
```
