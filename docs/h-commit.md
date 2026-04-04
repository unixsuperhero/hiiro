# h-commit

Fuzzy-select a git commit SHA from the recent log.

## Synopsis

```bash
h commit <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `select` / `sk` | Fuzzy-select a commit and print its SHA |

### select / sk

Show the last 50 commits via `sk` and print the SHA of the selected commit. Extra arguments are forwarded to `git log`.

**Examples**

```bash
h commit select
h commit sk
h commit select -- path/to/file
sha=$(h commit select)
git show $(h commit select)
```
