# h-commit

Fuzzy-select a git commit SHA from the recent log.

## Synopsis

```bash
h commit <subcommand> [git-log-args]
```

## Subcommands

| Subcommand | Aliases | Description |
|------------|---------|-------------|
| `select` | `sk` | Fuzzy-select a commit and print its SHA |

## Subcommand Details

### `select` / `sk`

Show the last 50 commits via `git log --oneline --decorate`, open them in `sk` for fuzzy selection, and print the selected commit's SHA. Any extra args are forwarded to `git log`.

```bash
h commit select
h commit sk
h commit select --author="Josh"
h commit select -n 100
```

The output is just the raw SHA, suitable for use in scripts:

```bash
sha=$(h commit select)
git show $sha
git cherry-pick $sha
```

## Examples

```bash
# Select a commit to cherry-pick
git cherry-pick $(h commit select)

# Select a commit to reset to
git reset --soft $(h commit select)

# View a selected commit
git show $(h commit sk)
```
