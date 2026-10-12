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

## h strip ctrl

`h strip ctrl` is a separate external command, not an `h misc` subcommand. It
removes terminal escape sequences and control characters from input bytes.

```bash
h strip ctrl FILE...
command | h strip ctrl
h strip ctrl TEXT...
h strip ctrl --help
```

When every argument names an existing file, the command concatenates their bytes
in argument order, without separators. Otherwise, it treats all arguments as
literal text and joins them with spaces. With no arguments, it reads piped stdin.

Output goes to stdout without an added newline. Tabs, line feeds, UTF-8 text, and
raw invalid bytes are preserved. The command removes:

- ASCII ESC sequences, including CSI color, cursor, and erase commands.
- OSC sequences terminated by BEL or ESC followed by a backslash.
- DCS, APC, and PM sequences terminated by ESC followed by a backslash.
- C0 controls and DEL, except tab and line feed.

Bytes from `0x80` through `0x9F` are not interpreted as C1 terminal controls.
Stripping does not reconstruct a terminal screen or apply cursor movements.
The command reads the whole input into memory.

### Examples

```bash
h strip ctrl terminal.log > clean.log
h strip ctrl first.log second.log > combined-clean.log
printf '\033[31mhello\033[0m\n' | h strip ctrl
h strip ctrl $'\033[31mhello\033[0m' world
```

Redirect to a different file. Redirecting stdout to an input file truncates that
file before the command reads it.
