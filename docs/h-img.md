# h-img

Save or base64-encode images from the clipboard or from files.

## Synopsis

```bash
h img <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `save [--force] <path>` | Save clipboard image to a file |
| `b64 [path]` | Print base64 data URI for a file or clipboard image |

Requires `pngpaste` to be installed for clipboard operations.

### b64

Print a base64 data URI (`data:<mime>;base64,...`) for a file or the clipboard image. Supports jpg, jpeg, gif, webp, and png. A clipboard image is read without leaving a file behind; the same errors as `save` exit 1.

**Examples**

```bash
h img b64 ~/screenshots/shot.png
h img b64               # uses clipboard image
```
### save

Save the current clipboard image to a file using `pngpaste` and print `Saved to PATH`. An existing file is refused (`PATH already exists (use --force to replace it)`, exit 1) unless `--force` is given, which replaces it atomically. Missing directories are created.

Exits 1 with `No image in clipboard`, `pngpaste not found`, `pngpaste failed: ...`, or `Could not write PATH: ...`; clipboard text is never saved in place of an image.

**Examples**

```bash
h img save ~/screenshots/shot.png
h img save /tmp/image.png
```

