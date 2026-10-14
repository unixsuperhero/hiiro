# h-dotenv

Compare `.env`-style files. Both subcommands only read and print; neither writes a file.

A line counts when it is not a `#` comment and contains `=` or `:`; the name is the text before the first `=`/`:` (whitespace trimmed). Names containing `TIMEOUT` are ignored.

## Synopsis

```bash
h dotenv copy_to FILE... TARGET
h dotenv compare FILE...
```

| Subcommand | What it prints |
|------------|----------------|
| `copy_to FILE... TARGET` | For each name that the last file (`TARGET`) lacks or holds a different value for: `VALUE FOR NAME is different` with TARGET's value and each differing file's value, or `VALUE MISSING: NAME` with the files that define it. Despite its name it copies nothing; use the report to edit TARGET yourself |
| `compare FILE...` | For every name: whether it is in all files, and the single shared value or each file's value |
