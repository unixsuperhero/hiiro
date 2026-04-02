# h-misc

Miscellaneous utility subcommands.

## Usage

```
h misc <subcommand> [options] [args]
```

## Subcommands

### `symlink_destinations`

List symlinks under a given directory whose targets point outside that directory, formatted as `dest => link_path`.

**Args:** `<basedir> [basedir2...]`

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--root` | `-r` | Root path for relative display | git repo root |
