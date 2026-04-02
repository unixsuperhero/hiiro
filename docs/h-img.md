# h-img

Save or base64-encode images from the clipboard or from files.

## Usage

```
h img <subcommand> [args]
```

Requires `pngpaste` to be installed for clipboard operations.

## Subcommands

### `save`

Save the current clipboard image to a file on disk.

**Args:** `<outpath>`

### `b64`

Print a base64 data URI for an image file or the current clipboard image.

**Args:** `[path]`

If `path` is omitted, reads from the clipboard. Outputs the full data URI: `data:<mime>;base64,<encoded>`.
