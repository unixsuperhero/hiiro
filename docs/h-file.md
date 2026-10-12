# h file

Track frequently-used files per application and open them together in your editor. Files resolve from the shared context root: selected task code/home directory, otherwise the invocation Git root or cwd. An app mount retains that root while carrying its effective directory.

Available as `h file` and `h app file [--app APP] ...`. The app selector precedes the child command, for example `h app file --app api edit api`.

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

Open the tracked files in your editor, using `-O` for vim vertical splits. Resolve every configured filename from the selected context root, independent of the effective app cwd. Traversal, symlink escapes, and unresolved symlink ancestors fail before editor launch. A leading `--app APP` on the app mount selects its context, not a second prefix for stored filenames.

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
