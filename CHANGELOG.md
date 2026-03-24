## h pr: add --diff/-d to ls, rename --drafts to -D, strip ANSI from fuzzyfind keys

- `h pr ls -d` / `--diff`: fuzzy-select a PR from the filtered list and open `gh pr diff`
- Changed `--drafts` short flag from `-d` to `-D` to free up `-d` for diff
- Strip ANSI escape codes from PR display strings used as fuzzyfinder keys (fixes raw color codes showing in sk/fzf)

Done.
