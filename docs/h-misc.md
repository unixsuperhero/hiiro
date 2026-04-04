# h-misc

Miscellaneous utility subcommands.

## Synopsis

```bash
h misc <subcommand> [options] [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `symlink_destinations` | List symlinks pointing outside a given directory |

## Subcommand Details

### `symlink_destinations`

List symlinks under one or more base directories whose targets point outside those directories. Output format is `<dest> => <link_path>`, with paths shown relative to the repository root (or the `--root` option).

**Args:** `<basedir> [basedir2...]`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--root` | `-r` | Root path for relative display | git repo root |

```bash
h misc symlink_destinations apps/frontend
h misc symlink_destinations apps/frontend apps/backend
h misc symlink_destinations apps/frontend -r /Users/josh/work/myrepo
```

## Examples

```bash
# Find all symlinks in a directory that point outside it
h misc symlink_destinations services/api

# Check multiple directories at once
h misc symlink_destinations apps services packages

# Use a custom root for relative paths in the output
h misc symlink_destinations apps -r /Users/josh/work/myrepo
```
