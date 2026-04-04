# h-img

Save or base64-encode images from the clipboard or from files.

## Synopsis

```bash
h img <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `save <path>` | Save clipboard image to a file |
| `b64 [path]` | Print base64 data URI for a file or clipboard image |

Requires `pngpaste` to be installed for clipboard operations.

### save

Save the current clipboard image to a file using `pngpaste`. Exits with error if clipboard contains no image.

**Examples**

```bash
h img save ~/screenshots/shot.png
h img save /tmp/image.png
```

### b64

Print a base64 data URI (`data:<mime>;base64,...`) for a file or the clipboard image. Supports jpg, jpeg, gif, webp, and png.

**Examples**

```bash
h img b64 ~/screenshots/shot.png
h img b64               # uses clipboard image
```
