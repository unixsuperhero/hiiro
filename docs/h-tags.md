# h-tags

Query tags grouped by taggable type from the hiiro database.

## Usage

```
h tags <subcommand> [args]
```

## Subcommands

### `tags_by_type`

Look up tags filtered by taggable type and print all tagged objects for those tags.

**Args:** `[type...]`

Note: This subcommand is a development/debug utility and drops into a `pry` REPL after displaying results.
