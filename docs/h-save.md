# h-save

Save clipboard text or images to `~/saved/` and manage what's there.

## Synopsis

```bash
h save [--bundle] [--task TASK [--label LABEL]] [text...]
h save <subcommand> [name]
```

## Default (no subcommand)

Saves the clipboard and prints the new file's path.

- If the clipboard holds an image (detected with `pngpaste`), its exact PNG bytes are saved as `<timestamp>-image.png`.
- Otherwise the text from `pbpaste` is saved byte for byte as `<timestamp>-<slug>.txt`, where the slug is the first few words of the text, lowercased, with non-alphanumerics collapsed to `-`. Without `pngpaste` installed the clipboard text is saved.
- If arguments are given, they are joined with spaces and saved as text instead of reading the clipboard (the clipboard is not read). Put `--` before text that starts with `-`.
- Name collisions get a `-2`, `-3`, ... suffix before the extension. Existing files are never overwritten: each name is created exclusively.
- The path is printed only after the file is written.

Failures print one line on stderr, exit 1, and leave nothing behind:

| Case | Message |
|------|---------|
| Empty clipboard | `Clipboard is empty` |
| `pngpaste` fails for another reason | `pngpaste failed: ...` (the text is **not** saved instead) |
| `pbpaste` fails | `pbpaste failed: ...` |
| The file cannot be written | `Could not write PATH: ...` |

### Attaching the saved file

`--bundle` (`-b`) adds the saved file to the current `h context` bundle and
`--task TASK` (`-t`) attaches it to a task as a `file` resource (the same row
`t file add` writes; `--label` sets its label). TASK is an exact name or unique
prefix, or `.` for the current task; an unknown or ambiguous task is an error
before the clipboard is read, and no other task is chosen. Each destination
gets one association however often the same file is attached, and the task's
status and next action are not touched.

The path is printed on stdout; each attachment is reported on stderr
(`attached to task alpha`). If the file was saved but an attachment failed,
stderr says `attach to bundle PATH failed: ...; artifact kept at FILE` and the
exit status is 2.

```bash
h save --task . --bundle   # save the clipboard, attach to the current task and bundle
```

```bash
h save                  # save clipboard
h save some quick note  # saves "some quick note" as text
```

## Subcommands

Every subcommand that takes a `name` matches it as a substring of the saved
filenames. An exact or single match is used directly, several matches open a
the shared picker over them, and no `name` opens the shared picker over everything.
`copy` exits 1 when the clipboard tool fails.

| Subcommand | Description |
|------------|-------------|
| `ls`, `list` | List saved files, newest first |
| `dir` | Print the `~/saved` directory path |
| `show [name]`, `cat [name]` | Print a text file's contents (prints the path for images) |
| `copy [name]` | Copy a saved file back to the clipboard (text or PNG) |
| `open [name]` | Open the file with `open` |
| `edit [name]` | Open the file in your editor |
| `rm [name]`, `remove [name]` | Delete the file |

```bash
h save ls
h save show meeting     # matches 20260915120000-meeting-notes.txt
h save copy image       # puts the PNG back on the clipboard
h save rm               # pick a file to delete
```

Set `HIIRO_SAVED_DIR` to use a directory other than `~/saved`.

Requires `pngpaste` for clipboard images. `h img`, `h context`, and `h note
save` capture through the same code (`Hiiro::Artifact` over `Hiiro::Clipboard`)
and keep their own destinations.
