# h-cpr

Run an `h pr` subcommand on the PR of the current git branch.

## Synopsis

```bash
h cpr [-C DIR] [subcommand] [args]
```

## Description

`h cpr` asks `gh pr view` for the PR of the branch checked out in `DIR` (default: the current directory) and qualifies it by the repository in its URL. It then runs `h pr` with that PR as the command's PR argument. The reference travels out of band (`HIIRO_PR_CURRENT=owner/name#N`), not as an inserted argument, so every subcommand keeps its own argv and flags: `h cpr dep add team/two#5` adds `team/two#5` as a dependency of the current PR, and `h cpr merge --squash -d` merges it.

With no subcommand it runs `h pr view`. When the branch has no PR (or gh cannot tell which), it prints gh's reason and exits 1; it never picks a same-numbered PR from another repository.

## Examples

```bash
h cpr                          # h pr view <current PR>
h cpr -C ~/work/other merge --squash
h cpr check                    # gh pr checks <current PR URL>
h cpr dep add team/two#5
h cpr tag needs-review
h cpr fix
```

## See also

[h-pr](h-pr.md)
