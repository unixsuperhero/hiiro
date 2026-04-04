# h-misc

Miscellaneous utility subcommands.

## Synopsis

```bash
h misc <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `symlink_destinations <dirs>` | List symlinks in directories whose destinations are outside those directories |

### symlink_destinations

Walk one or more directories and list all symlinks whose destinations fall outside those directories. Useful for auditing symlink layouts in a monorepo or project.

**Options**

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--root` | `-r` | Root path for resolving relative paths | `git rev-parse --show-toplevel` |

**Examples**

```bash
h misc symlink_destinations packages/
h misc symlink_destinations packages/ apps/ --root /path/to/repo
```
