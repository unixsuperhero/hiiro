# h-link

Store, search, tag, and open saved URLs.

## Usage

```
h link <subcommand> [options] [args]
```

## Subcommands

### `add`

Add a URL to the link store. With no args, opens an editor template. With a URL, saves it directly. Supports optional description, shorthand alias, and tags.

**Args:** `[url] [description...]`

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--shorthand` | `-s` | Short alias for the link | — |
| `--tag` | `-t` | Tag (repeatable) | — |
| `--tags` | — | Tag (alias for --tag, repeatable) | — |

### `ls` [alias: `list`]

Print all saved links with index, shorthand, URL, and description.

### `search`

Search links by URL, description, or shorthand substring. All terms must match.

**Args:** `<term> [term2...]`

### `select`

Fuzzy-select a link and print its URL. Prompts for placeholder values if the URL contains `{name}` tokens.

**Args:** `[filter...]`

### `copy`

Fuzzy-select a link and copy its URL to clipboard. Handles `{placeholders}` as in `select`.

**Args:** `[filter...]`

### `open`

Open a link in the browser. With no arg, fuzzy-selects. With a number/shorthand/search term, opens that link directly.

**Args:** `[number|shorthand|search_term]`

### `edit`

Open a single link in your editor by number or shorthand.

**Args:** `<number|shorthand>`

### `editall`

Open the raw links YAML file in your editor.

### `rm` [alias: `remove`]

Remove a link by number, shorthand, or URL substring. Fuzzy-selects if no arg given.

**Args:** `[number|shorthand|search_term...]`

### `tags`

List all tags and the links associated with each tag.

**Args:** `[tag...]`

### `paste`

Save the current clipboard URL as a new link with optional description and tags.

**Args:** `[description...]`

**Options:**
| Flag | Short | Description | Default |
|---|---|---|---|
| `--shorthand` | `-s` | Short alias | — |
| `--tag` | `-t` | Tag (repeatable) | — |
| `--tags` | — | Tag (alias, repeatable) | — |

### `path`

Print the path to the links YAML file.
