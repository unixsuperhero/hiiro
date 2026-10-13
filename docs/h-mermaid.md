# h mermaid

Renders Mermaid diagrams with `mmdc` (mermaid-cli).

- `h mermaid png FILE...` writes `FILE.png` next to each input.
- `h mermaid svg FILE...` writes `FILE.svg` next to each input.
- Arguments that are not regular files are skipped. The command fails when any `mmdc` run fails.
- `h mermaid install` runs `npm i -g @mermaid-js/mermaid-cli`.

`png` and `svg` are one registration over the format list `%w[png svg]`.
