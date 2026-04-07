# h-link

Store, search, tag, and open saved URLs.

## Synopsis

```bash
h link <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `add [url] [desc]` | Add a URL (with optional description and tags) |
| `paste [desc]` | Add URL from clipboard |
| `ls` / `list` | List all saved links |
| `search <terms>` | Search links by URL, description, or shorthand |
| `select [terms]` | Fuzzy-select a link and print its URL |
| `copy [terms]` | Fuzzy-select a link and copy URL to clipboard |
| `open [ref]` | Open a link in the browser |
| `edit <ref>` | Edit a specific link in editor |
| `editall` | Edit the links YAML file directly |
| `rm [ref]` | Remove a link |
| `remove [ref]` | Alias for `rm` |
| `tags [tag]` | List links grouped by tag |
| `path` | Print path to the links storage file |

### add

Add a URL. With no arguments, opens an editor with a YAML template. With a URL, creates the link directly.

Links can contain `{placeholder}` syntax — when opened/selected/copied, you'll be prompted to fill in values.

**Options**

| Flag | Short | Description |
|------|-------|-------------|
| `--shorthand` | `-s` | Shorthand alias for the link |
| `--tag` | `-t` | Tag (repeatable) |
| `--tags` | | Tag (alias, repeatable) |

**Examples**

```bash
h link add
h link add https://example.com "My site"
h link add https://example.com --shorthand ex --tag reference
h link add "https://jira.example.com/browse/{ticket}" --tag jira
```

### copy

Fuzzy-select a link and copy its URL to the clipboard. Supports placeholder substitution.

**Examples**

```bash
h link copy
h link copy github
```

### edit

Edit a specific link (by index number or shorthand) in a YAML editor.

**Examples**

```bash
h link edit 3
h link edit ex
```

### editall

Open the raw links YAML file in your editor.

**Examples**

```bash
h link editall
```

### ls / list

List all saved links with index, shorthand (if any), URL, and description.

**Examples**

```bash
h link ls
h link list
```

### open

Open a link in the browser. With no argument, fuzzy-selects. With a number or shorthand, opens directly. Supports placeholder substitution.

**Examples**

```bash
h link open
h link open 3
h link open ex
h link open github
```

### paste

Add the URL currently in the clipboard as a new link.

**Options**

Same as `add`: `--shorthand`, `--tag`, `--tags`.

**Examples**

```bash
h link paste
h link paste "PR template" --tag github
```

### path

Print the path to the links YAML file.

**Examples**

```bash
h link path
```
### rm / remove

Remove a link. With no argument, fuzzy-selects. With a number or shorthand, removes directly. Supports substring URL matching.

**Examples**

```bash
h link rm
h link rm 3
h link rm ex
```

### search

Search saved links by URL, description, or shorthand. All terms must match (AND logic).

**Examples**

```bash
h link search github
h link search jira ticket
```

### select

Fuzzy-select a link and print its URL. If the URL has `{placeholder}` variables, opens an editor to fill them in. Optionally pre-filter with search terms.

**Examples**

```bash
h link select
h link select jira
url=$(h link select)
```

### tags

List all links grouped by tag.

**Examples**

```bash
h link tags
```

