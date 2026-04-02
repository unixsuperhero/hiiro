# h-sparse

Manage named git sparse-checkout path groups stored in `~/.config/hiiro/sparse_groups.yml`.

## Usage

```
h sparse <subcommand> [args]
```

## Subcommands

### `config`

Open `~/.config/hiiro/sparse_groups.yml` in your editor.

### `ls` [alias: `list`]

List all configured sparse groups. With a group name, list that group's paths. Without an arg, show all groups with path counts.

**Args:** `[group_name]`

### `set`

Apply a sparse group to the current git repository using `git sparse-checkout set --cone`.

**Args:** `<group_name>`

### `add`

Add one or more paths to a named sparse group (creates the group if it does not exist).

**Args:** `<group_name> <path> [path2...]`

### `rm`

Remove a group entirely (no paths given) or remove specific paths from a group.

**Args:** `<group_name> [path...]`
