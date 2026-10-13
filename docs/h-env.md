# h-env / h-export

Append an environment assignment to a shell file. Both commands write through
one `Hiiro::EnvironmentAssignment`.

```sh
h env add [--file PATH] NAME VALUE
h export add [--file PATH] NAME WORDS...    # words joined with single spaces into one value
```

- **Destination:** `--file PATH` when given; otherwise `~/.zshenv.d/vars.zsh`
  when that file exists; otherwise `~/.zshenv`. `~/.zshrc` is never written
  implicitly. The command prints `Added environment variable to PATH`.
- **Literal values:** the line is `export NAME="VALUE"` with `"`, `\`, `$`, and
  backticks escaped, so sourcing the file yields the value as typed and never
  runs it (`$(cmd)` stays the text `$(cmd)`). A value containing a newline is
  refused.
- **Names** must match `[A-Za-z_][A-Za-z0-9_]*`; otherwise
  `Invalid environment variable name`, exit 1, and nothing is written.
- **Preservation:** the file is appended to, so its existing bytes stay; a
  missing final newline is added before the new line; an existing file keeps
  its mode and a new file is created `0600`.
- Use `--` before a value that starts with `-`.

The installed `h export add NAME CMD...` rewrote `~/.zshrc` with the command
words quoted by Ruby `inspect`, so `$` and backticks were evaluated by the shell
and the file lost its final newline. The clone keeps `h export add` as a
shortcut but deliberately writes to the `h env` destination with literal
values.
