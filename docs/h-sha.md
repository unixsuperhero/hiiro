# h-sha

Fuzzy-select, show, and copy git commit SHAs.

## Synopsis

```bash
h sha <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `select` | Fuzzy-select from last 100 commits and print SHA |
| `ls [args]` | List commits via `git log --oneline` |
| `show [sha]` | Show a commit (fuzzy-select if no SHA given) |
| `copy [sha]` | Copy a SHA to clipboard |

### select

Show the last 100 commits via fuzzy finder and print the selected SHA. Useful for scripting.

**Examples**

```bash
h sha select
git show $(h sha select)
git cherry-pick $(h sha select)
```

### ls

List commits with `git log --oneline`. Extra arguments are forwarded to git.

**Examples**

```bash
h sha ls
h sha ls -20
h sha ls --all
```

### show

Show a commit's diff and metadata. Fuzzy-selects from recent commits if no SHA given.

**Examples**

```bash
h sha show
h sha show abc1234
```

### copy

Copy a SHA to the clipboard. Fuzzy-selects from recent commits if no SHA given.

**Examples**

```bash
h sha copy
h sha copy abc1234
```
