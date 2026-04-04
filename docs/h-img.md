# h-img

Save or base64-encode images from the clipboard or from files.

## Synopsis

```bash
h img <subcommand> [args]
```

Requires `pngpaste` to be installed for clipboard operations (`brew install pngpaste`).

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `save` | Save the current clipboard image to a file |
| `b64` | Print a base64 data URI for an image file or clipboard image |

## Subcommand Details

### `save`

Save the current clipboard image to a file on disk. Uses `pngpaste` to read from the clipboard.

```bash
h img save ~/notes/files/screenshot.png
h img save /tmp/diagram.png
```

### `b64`

Print a full base64 data URI for an image. If a `path` is given, encodes that file. If omitted, reads from the clipboard via `pngpaste`.

Output format: `data:<mime>;base64,<encoded>`

Supported MIME types are detected from the file extension: `jpg`/`jpeg`, `gif`, `webp`, `png`. Unknown extensions default to `image/png`.

```bash
h img b64                        # clipboard image as data URI
h img b64 ~/screenshots/foo.png
h img b64 ~/screenshots/foo.jpg  # => data:image/jpeg;base64,...
```

## Examples

```bash
# Save clipboard screenshot for later reference
h img save ~/notes/files/error-screenshot.png

# Get a data URI to embed in a markdown file or HTML
h img b64 ~/notes/files/diagram.png

# Capture clipboard screenshot and get data URI in one shot
h img b64

# Use in a Claude prompt (paste the URI as context)
h img b64 | pbcopy
```
