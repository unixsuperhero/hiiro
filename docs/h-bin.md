# h-bin

List and edit hiiro bin scripts (`h-*` executables found in PATH).

## Synopsis

```bash
h bin <subcommand> [names...]
```

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `list [names]` | List matching bin files |
| `edit [names]` | Open matching bin files in editor |

### edit

Open matching `h-*` bin files in your editor. With no arguments, opens `h-bin` itself.

**Examples**

```bash
h bin edit
h bin edit branch
h bin edit pr notify
```
### list

List `h-*` executables found in PATH. With no arguments, lists all. With names, filters to those matching `h-<name>` or `<name>` patterns. Deduplicates by basename (first occurrence wins).

**Examples**

```bash
h bin list
h bin list branch pr
```

