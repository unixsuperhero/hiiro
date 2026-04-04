# h-tags

Query tags grouped by taggable type from the hiiro database.

## Synopsis

```bash
h tags <subcommand> [args]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `tags_by_type [types]` | Show tags and tagged objects, grouped by type |

Note: this command is currently a low-level utility used for debugging and exploration. For tagging branches and tasks, use the `tag` subcommands on [h-branch](h-branch.md) and [h-pm](h-pm.md).

### tags_by_type

List all tags of the given types, then list all objects tagged with those tags.

**Examples**

```bash
h tags tags_by_type branch
h tags tags_by_type task branch
```
