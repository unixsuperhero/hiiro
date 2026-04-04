# h-sha

Fuzzy-select, show, and copy git commit SHAs.

## Synopsis

```bash
h sha <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `select` | Fuzzy-select a commit SHA from the last 100 commits |
| `ls` | List recent commits via `git log --oneline` |
| `show` | Run `git show` on a SHA |
| `copy` | Copy a SHA to clipboard |

## Subcommand Details

### `select`

Show the last 100 commits via `git log --oneline`, fuzzy-select one, and print its SHA. Extra args are forwarded to `git log`.

```bash
h sha select
h sha select --author="Josh"
sha=$(h sha select)
```

### `ls`

List recent commits via `git log --oneline`. Extra args forwarded to `git log`.

```bash
h sha ls
h sha ls -n 50
h sha ls --since="2 weeks ago"
```

### `show`

Run `git show` on a SHA. If no SHA is given, runs `h sha select` interactively.

```bash
h sha show
h sha show abc1234
h sha show abc1234 --stat
```

### `copy`

Copy a SHA to clipboard. If no SHA is given, runs `h sha select` interactively.

```bash
h sha copy
h sha copy abc1234
```

## Examples

```bash
# Select a SHA to cherry-pick
git cherry-pick $(h sha select)

# Show a selected commit's diff
h sha show

# Copy a SHA for use elsewhere
h sha copy

# Find recent commits by author
h sha ls --author="Josh" | head -20
```
