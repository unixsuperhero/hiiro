# h-save

Save clipboard text or images to `~/saved/` and manage what's there.

## Synopsis

```bash
h save [text...]
h save <subcommand> [name]
```

## Default (no subcommand)

Saves the clipboard and prints the new file's path.

- If the clipboard holds an image (detected with `pngpaste`), it is saved as `<timestamp>-image.png`.
- Otherwise the text from `pbpaste` is saved as `<timestamp>-<slug>.txt`, where the slug is the first few words of the text, lowercased, with non-alphanumerics collapsed to `-`.
- If arguments are given, they are joined with spaces and saved as text instead of reading the clipboard.
- An empty clipboard prints `Clipboard is empty` and exits 1.
- Name collisions get a `-2`, `-3`, ... suffix before the extension. Existing files are never overwritten.

```bash
h save                  # save clipboard
h save some quick note  # saves "some quick note" as text
```

## Subcommands

Every subcommand that takes a `name` matches it as a substring of the saved
filenames. An exact or single match is used directly, several matches open a
fuzzy finder over them, and no `name` opens a fuzzy finder over everything.

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
h save rm               # fuzzy-select a file to delete
```

Set `HIIRO_SAVED_DIR` to use a directory other than `~/saved`.

Requires `pngpaste` for clipboard images.
