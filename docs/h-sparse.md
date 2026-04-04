# h-sparse

Manage named git sparse-checkout path groups stored in `~/.config/hiiro/sparse_groups.yml`.

## Synopsis

```bash
h sparse <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ls [group]` | List all groups or show paths for a specific group |
| `list [group]` | Alias for `ls` |
| `set <group>` | Apply a group's paths as the sparse checkout in the current repo |
| `add <group> <paths>` | Add paths to a group |
| `rm <group> [paths]` | Remove paths from a group (or delete entire group) |
| `config` | Edit the sparse groups config file |

Groups are matched by exact name first, then prefix, then substring.

### ls

List all configured groups with path counts, or show all paths for a specific group.

**Examples**

```bash
h sparse ls
h sparse ls my-group
```

### set

Apply a group's paths as the git sparse-checkout for the current repository. Uses `git sparse-checkout set --cone --skip-checks`.

**Examples**

```bash
h sparse set my-group
h sparse set fe    # prefix match
```

### add

Add one or more paths to a group. Creates the group if it doesn't exist. Skips paths already in the group.

**Examples**

```bash
h sparse add my-group packages/api packages/web
h sparse add frontend packages/ui
```

### rm

Remove specific paths from a group, or delete the entire group if no paths are given.

**Examples**

```bash
h sparse rm my-group packages/api
h sparse rm old-group              # deletes the group
```

### config

Open `~/.config/hiiro/sparse_groups.yml` in your editor.

**Examples**

```bash
h sparse config
```

## Configuration

`~/.config/hiiro/sparse_groups.yml`:

```yaml
backend:
  - packages/api
  - packages/workers
  - packages/shared

frontend:
  - packages/web
  - packages/mobile
  - packages/ui
```
