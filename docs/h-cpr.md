# h-cpr

Proxy `h pr` subcommands to the PR associated with the current git branch.

## Usage

```
h cpr [subcommand] [args]
```

`h-cpr` detects the PR number for the current branch via `gh pr view`, then delegates to `h pr`. With no subcommand it runs `h pr view <number>`. With a subcommand it runs `h pr <subcommand> <number> [args...]`.

## Examples

```
h cpr            # h pr view <current PR number>
h cpr check      # h pr check <current PR number>
h cpr open       # h pr open <current PR number>
h cpr diff       # h pr diff <current PR number>
```

Exits with status 1 if there is no open PR for the current branch.
