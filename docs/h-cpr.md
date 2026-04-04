# h-cpr

Proxy `h pr` subcommands to the PR associated with the current git branch.

## Synopsis

```bash
h cpr [subcommand] [args]
```

## Description

`h cpr` looks up the PR number for the current branch using `gh pr view`, then delegates to `h pr`. With no arguments it runs `h pr view <number>`. With a subcommand, it runs `h pr <subcommand> <number> [args]`.

Exits with an error if the current branch has no associated PR.

## Examples

```bash
h cpr              # same as: h pr view <current pr number>
h cpr checks       # same as: h pr checks <current pr number>
h cpr merge        # same as: h pr merge <current pr number>
h cpr view         # same as: h pr view <current pr number>
```

## See also

[h-pr](h-pr.md)
