# h-sparse

Manage named git sparse-checkout path groups stored in `~/.config/hiiro/sparse_groups.yml`.

## Synopsis

```bash
h sparse <subcommand> [args]
```

Sparse groups are named lists of directory paths. Applying a group sets `git sparse-checkout` to those paths in the current repository. This is useful for large monorepos where you only need a subset of directories checked out.

## Subcommands

| Subcommand | Aliases | Description |
|------------|---------|-------------|
| `config` | — | Open `sparse_groups.yml` in editor |
| `ls` | `list` | List groups (or paths for a specific group) |
| `set` | — | Apply a sparse group to the current git repo |
| `add` | — | Add paths to a named group |
| `rm` | — | Remove a group or specific paths from a group |

## Subcommand Details

### `config`

Open `~/.config/hiiro/sparse_groups.yml` in your editor.

```bash
h sparse config
```

### `ls` / `list`

Without an arg, list all groups with path counts. With a group name, list that group's paths. Group name matching: exact first, then prefix, then substring.

```bash
h sparse ls
# groups:
#   backend   (3 paths)
#   frontend  (5 paths)

h sparse ls backend
# backend:
#   services/backend
#   lib/shared
#   config
```

### `set`

Apply a sparse group to the current repository using `git sparse-checkout set --cone`. Leading `/` is stripped from paths before passing to git.

```bash
h sparse set backend
h sparse set front    # prefix match
```

### `add`

Add one or more paths to a named group. Creates the group if it does not exist.

```bash
h sparse add backend services/backend
h sparse add backend lib/shared config
```

### `rm`

Without paths, remove the entire group. With paths, remove specific paths from the group.

```bash
h sparse rm backend                    # remove entire group
h sparse rm backend lib/shared         # remove one path
h sparse rm backend lib/shared config  # remove multiple paths
```

## Examples

```bash
# Set up groups for a monorepo
h sparse add api services/api lib/api
h sparse add web apps/web lib/web

# Apply the api group to work on the API
h sparse set api

# See what's in each group
h sparse ls

# Add a new shared library to the api group
h sparse add api lib/new-shared

# Apply a different group
h sparse set web
```
