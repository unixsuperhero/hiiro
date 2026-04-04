# h-tags

Query tags grouped by taggable type from the hiiro database.

## Synopsis

```bash
h tags <subcommand> [args]
```

Tags in hiiro can be applied to multiple resource types (branches, PRs, links, etc.) and are stored in the SQLite `tags` table. This command provides utilities for querying tags across types.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `tags_by_type` | Look up tags filtered by taggable type and print all tagged objects |

## Subcommand Details

### `tags_by_type`

Look up tags filtered by one or more taggable type names, then print both the tags and all tagged objects of those types. After printing, drops into a `pry` REPL for interactive exploration.

**Note:** This is primarily a development and debugging utility, not intended for regular use.

```bash
h tags tags_by_type branch
h tags tags_by_type branch pr
```

## Notes

For day-to-day tag management, use the `tag` and `tags` subcommands on individual resource commands:

- `h branch tags` — view branches grouped by tag
- `h branch tag <name> <tag>` — tag a branch
- `h pr tags` — view PRs grouped by tag
- `h pr tag <number> <tag>` — tag a PR
- `h link tags` — view links grouped by tag
