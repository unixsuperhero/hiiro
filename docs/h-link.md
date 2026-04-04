# h-link

Store, search, tag, and open saved URLs.

## Synopsis

```bash
h link <subcommand> [options] [args]
```

Links are stored in SQLite (`~/.config/hiiro/hiiro.db`, table `links`) with a YAML backup at `~/.config/hiiro/links.yml`. URLs may contain `{placeholder}` tokens that are filled in interactively when opening or selecting.

## Subcommands

| Subcommand | Aliases | Description |
|------------|---------|-------------|
| `add` | — | Add a URL to the link store |
| `ls` | `list` | Print all saved links |
| `search` | — | Search by URL, description, or shorthand |
| `select` | — | Fuzzy-select a link and print its URL |
| `copy` | — | Fuzzy-select a link and copy URL to clipboard |
| `open` | — | Open a link in the browser |
| `edit` | — | Open a single link in editor |
| `editall` | — | Open the raw links YAML file in editor |
| `rm` | `remove` | Remove a link |
| `tags` | — | List all tags and their associated links |
| `paste` | — | Save the current clipboard URL as a new link |
| `path` | — | Print path to the links YAML file |

## Options

### `add` and `paste`

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--shorthand` | `-s` | Short alias for the link | — |
| `--tag` | `-t` | Tag (repeatable) | — |
| `--tags` | — | Tag (alias for `--tag`, repeatable) | — |

## Subcommand Details

### `add`

Add a URL to the link store. With no args, opens a YAML editor template. With a URL arg, saves directly. Description is all remaining args after the URL.

```bash
h link add
h link add https://example.com "My Example Site"
h link add https://docs.ruby-lang.org Ruby docs -s ruby-docs
h link add https://github.com/... PR for feature -t pr -t review
```

### `ls` / `list`

Print all saved links with index, shorthand (if any), URL, and description.

```bash
h link ls
#   1. [ruby-docs] https://docs.ruby-lang.org - Ruby docs
#   2. https://github.com/... - PR for feature  pr  review
```

### `search`

Search links by URL, description, or shorthand substring. All terms must match (AND logic).

```bash
h link search ruby
h link search github pr
```

### `select`

Fuzzy-select a link and print its URL. If the URL contains `{placeholder}` tokens, opens your editor to fill in values before printing.

```bash
h link select
h link select ruby     # pre-filter to ruby links
url=$(h link select)
```

### `copy`

Fuzzy-select a link and copy its URL to clipboard. Handles `{placeholders}` the same as `select`.

```bash
h link copy
h link copy docs
```

### `open`

Open a link in the browser. With no arg, fuzzy-selects. With a number (1-based), shorthand, or search term, opens that link directly. Handles `{placeholders}`.

```bash
h link open            # fuzzy select
h link open 3          # open link #3
h link open ruby-docs  # open by shorthand
h link open "ruby"     # search and open if exactly one match
```

### `edit`

Open a single link in your editor by 1-based number or shorthand.

```bash
h link edit 3
h link edit ruby-docs
```

### `editall`

Open the raw `links.yml` file in your editor.

```bash
h link editall
```

### `rm` / `remove`

Remove a link by 1-based number, shorthand, or URL substring. Fuzzy-selects from all links if no arg given.

```bash
h link rm              # fuzzy select
h link rm 3
h link rm ruby-docs
```

### `tags`

List all tags and the links associated with each tag.

```bash
h link tags
h link tags pr         # show only the "pr" tag
```

### `paste`

Save the current clipboard URL as a new link. Optional description and tags may be provided.

```bash
h link paste
h link paste "Interesting article" -t reading
```

### `path`

Print the path to the links YAML file.

```bash
h link path
# => /Users/josh/.config/hiiro/links.yml
```

## Examples

```bash
# Save a frequently-used Jira board link
h link add https://jira.example.com/board?project=MY "My Jira Board" -s jira -t work

# Save a parameterized search URL
h link add "https://github.com/search?q={query}+language:ruby" "GitHub Ruby Search" -s ghsearch

# Open a parameterized link (prompts for {query})
h link open ghsearch

# Track a PR link
h link paste -t pr -t review
h pr track   # also register it with h-pr

# Browse all work links
h link tags work
```
