# h file

Track frequently-used files per application and open them together in your editor. Files are resolved relative to the current task's tree root when an environment is available.

Available as both `h file` (top-level) and `h app file` (scoped to `h app`).

## Synopsis

```bash
h file <subcmd> [args]
```

Config: `~/.config/hiiro/app_files.yml`

## Subcommands

### `h file add`

```bash
h file add <app_name> <file1> [file2 ...]
```

Add one or more files to an app's tracked file list.

### `h file edit`

```bash
h file edit <app_name>
```

Open all tracked files for `<app_name>` in your editor. Uses `-O` for vertical splits in vim. Files are resolved relative to the current task's tree root when available.

### `h file ls`

```bash
h file ls [app_name]
```

List tracked files — all apps if no name given, or just the specified app.

### `h file rm`

```bash
h file rm <app_name> <file1> [file2 ...]
```

Remove one or more files from an app's tracked list.
