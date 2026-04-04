# h-cpr

Proxy `h pr` subcommands to the PR associated with the current git branch.

## Synopsis

```bash
h cpr [subcommand] [args]
```

`h-cpr` detects the PR number for the current branch via `gh pr view --json number`, then delegates to [h-pr](h-pr.md). With no subcommand, runs `h pr view <number>`. With a subcommand, runs `h pr <subcommand> <number> [args...]`.

Exits with status 1 if there is no open PR for the current branch.

## Examples

```bash
h cpr              # h pr view <current PR number>
h cpr check        # h pr check <current PR number>
h cpr open         # h pr open <current PR number>
h cpr diff         # h pr diff <current PR number>
h cpr watch        # h pr watch <current PR number>
h cpr ready        # h pr ready <current PR number>
```

Any subcommand and args valid for `h pr` can be used:

```bash
h cpr status
h cpr merge --squash
h cpr tag my-tag
```
