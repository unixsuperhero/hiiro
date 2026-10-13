# h-sha

Choose, show, and copy git commit SHAs. Choosing uses the same `commits` picker as `h commit select` ([picker](picker.md)); a rule saved in either hides the commit in both.

## Synopsis

```bash
h sha <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `select` | Choose from the last 100 commits and print the SHA (no newline) |
| `ls [args]` | List commits via `git log --oneline` |
| `show [sha]` | Show a commit (choose one if no SHA given) |
| `copy [sha]` | Copy a SHA to the clipboard (choose one if no SHA given) |

### copy

Copy a SHA to the clipboard with `pbcopy` and print `Copied SHA to clipboard`. Without a SHA, choose one as `select` does (in process; nothing is copied when cancelled).

**Examples**

```bash
h sha copy
h sha copy abc1234
```
### ls

List commits with `git log --oneline`. Extra arguments are forwarded to git.

**Examples**

```bash
h sha ls
h sha ls -20
h sha ls --all
```

### select

List the last 100 commits (`git log -100 ARGS`, rows `SHORT SUBJECT`) in the `commits` picker and print the abbreviated SHA of the chosen commit with no trailing newline. Extra arguments go to `git log` as arguments (no shell). Cancelling prints nothing. With no commits, `No commits found` goes to stderr (exit 0). Off a terminal: `ERROR: Choosing from commits needs a terminal`, exit 1.

**Examples**

```bash
h sha select
git show $(h sha select)
git cherry-pick $(h sha select)
```

### show

Run `git show SHA [args]`. Without a SHA, choose one as `select` does (the first argument is always taken as the SHA).

**Examples**

```bash
h sha show
h sha show abc1234
```

