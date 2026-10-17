# h-hub

A central filesystem hub: one directory (default `~/hub`) of symlinks to the places you actually work in. Originals are never moved, copied, deleted, or changed.

## Synopsis

```bash
h hub init [CATALOG]          # first-time setup; CATALOG defaults to the bundled bin/lib/hub-catalog.json
h hub sync [--dry-run]        # create missing directories and symlinks
h hub doctor                  # read-only health report; nonzero when unhealthy
h hub list [QUERY]            # alias: ls
h hub path [NAME]             # no NAME: hub root; otherwise a registered link or group path
h hub open [NAME]             # open in Finder (macOS `open`)
h hub find NAME QUERY [--limit N]
h hub recent NAME [--limit N] [--json|--paths] [--repo OWNER/REPO]   # newest first, default 20
h hub latest NAME [--json] [--repo OWNER/REPO]                       # the single newest item
h hub add NAME TARGET DESCRIPTION
```

`--root PATH` or `H_HUB_ROOT` selects a base other than `~/hub`. Help never reads or creates the hub.

## Recent and latest

`recent` and `latest` answer "what changed last" for any registered link, or for a group (all leaf links under it, deduplicated by real path). They are computed live from the filesystem on every call: no file contents are read, and there is no daemon, cache, or generated "recent" link.

```bash
h hub recent notes --limit 5          # newest first, one per line
h hub recent downloads --paths        # paths only
open "$(h hub latest downloads)"      # open the newest finished download
cd "$(h hub latest projects)"         # enter the most recently changed project
h hub recent docs --json              # [] when empty, exit 0
h hub latest notes --json             # one object; nonzero and no stdout when nothing is found
h hub recent prs --repo owner/name    # your authored PRs, newest update first
```

`latest` prints only the path or PR URL on stdout. Quote command substitutions to preserve spaces. `--limit` is supported by `recent` (default 20) and `find` (default 100), never `latest`. `--repo` is valid only for `prs`, which reads GitHub through `gh` and works without an initialized hub. `--json` and `--paths` are exclusive.

JSON records have string keys; `recent` is an array of them, `latest` one object:

```js
const record = {
  name: "Weekly Plan v2.md",                       // readable name
  path: "/Users/me/hub/notes/plans/Weekly Plan v2.md",   // hub path (a PR: its URL)
  timestamp: "2026-01-05T12:00:00.000Z",           // UTC ISO 8601
  basis: "modified"                                // created | modified | updated
};
```

Order is newest first, ties broken by path, and the whole tree is scanned before `--limit` applies. The basis is what the timestamp means, by category:

| Category | One item is | Timestamp |
|----------|-------------|-----------|
| Downloads | each direct, non-hidden, finished file or directory (not `.part`, `.crdownload`, `.download`, `.partial`, `.tmp`) | creation time (`created`) where the OS reports it, since a download is new when it arrives and a later touch should not reorder it; `modified` otherwise |
| Notes, docs, any other link | every file, recursively (any extension) | file mtime; a directory's own mtime changes on rename and is ignored |
| Projects | each immediate project directory | newest source-file or surviving directory mtime, including uncommitted changes and additions/deletions; Git projects enumerate tracked and nonignored untracked files, while non-Git projects use a pruned walk |
| PRs | each PR authored by the active `gh` account, open or closed | GitHub last-update time (`updated`); at most 1000 results |

Interior symlinked directories and cycles are not entered. Symlinked files are never followed outside the link. `.git`, `node_modules`, `.cache`, `.obsidian`, `__pycache__`, `.venv`, `venv`, `dist`, `build`, `target`, `.next`, `vendor`, `.DS_Store`, and `.localized` are skipped. A registered root may itself be a symlink. An unavailable root or unreadable directory is an error, never an empty success.

The special download and project rules apply to the registered names `downloads` and `projects`. Download creation time is a filesystem timestamp, not browser download history or Finder date-added metadata; copying files while preserving timestamps can affect the order. These are metadata queries, not a history of edits. Project directory timestamps help detect additions and deletions but can also reflect generated files added in the same directory. Large project collections take longer because every candidate is checked before selecting the newest results.

## Changing directory

A subprocess cannot change your shell's directory, so use `path`:

```bash
cd "$(h hub path notes)"
cd "$(h hub path sessions)"     # a group directory works too
```

## The catalog

The live catalog is `ROOT/.hub.json`. `init` copies the bundled default (or the CATALOG you name) into a fresh or empty hub; it refuses a populated unrelated directory. Running `init` again on an initialized hub only syncs and never overwrites the catalog.

```js
const catalog = {
  version: 1,
  description: "...",
  directories: {                                          // every parent grouping directory, declared
    config: "Hand-edited configuration",
    "config/shell": "Zsh startup files"
  },
  links: [{ name: "notes", target: "~/notes", description: "Personal notes." }]
};
```

Rules: names are relative logical paths (no leading `/`, no `..`); `.hub.json` and `README.md` are reserved; a leaf link cannot also be a directory or the ancestor of another entry; every parent of a link must appear in `directories`; a target may not be the hub or inside it.

### Editing and adding registrations

Prefer `h hub add NAME TARGET DESCRIPTION`: it validates the whole catalog before touching the filesystem, writes `.hub.json` atomically, then syncs. To edit by hand, change `ROOT/.hub.json` and run `h hub sync --dry-run`, then `h hub sync`. To change what a fresh machine gets, edit `bin/lib/hub-catalog.json`.

Sync only creates symlinks for targets that exist. Missing sources are reported, skipped, and make the command exit nonzero. An existing correct link is left alone; a conflicting file or a link pointing elsewhere is reported and never overwritten.

After changing a target in the catalog, inspect the old hub symlink with `readlink`. Remove only that symlink, without a trailing slash, then run `h hub sync`. Never remove the source directory. Removing a catalog entry alone does not remove its old symlink.

```bash
link="$(h hub path docs/ai)"
readlink "$link"
# After verifying this is the old hub symlink and updating .hub.json:
test -L "$link" && unlink "$link"
h hub sync
```

The default catalog describes this workstation. On another machine, pass a tailored catalog to `init`; unavailable sources are reported rather than created.

## What the bundled catalog covers

| Group | Contents |
|-------|----------|
| top level | `notes`, `projects`, `vaults`, `downloads`, `desktop`, `recordings` |
| `docs/` | `ai` (~/ai/docs), `claude` (~/claude/docs): HTML and Markdown docs |
| `ai/` | `workspace` (~/ai), `claude` (~/claude): the full AI workspaces |
| `config/` | `apps` (~/.config), `shell/` (zshrc, zshenv, zprofile and the `.d` directories) |
| `tools/` | `local` (~/.local), `cache` (~/.cache), `pandoc`, `bin`, `hiiro` |
| `harnesses/` | private roots: claude, omp, codex, pi, agents, grok, gemini, cursor, prime, opencode |
| `sessions/` | one link per real transcript location |
| `skills/` | one link per real skills directory |
| `prompts/`, `hooks/` | `prompts/ai` (~/ai/prompts), `prompts/claude` (~/claude/prompts), pi prompts, Claude commands; `hooks/workspace` (~/claude/hooks), Claude, Grok, Codex, Cursor hooks |

Distinguish the groups: `config` is hand-edited settings; `tools/local` (~/.local) is persistent app data that is not cache; `tools/cache` (~/.cache) is disposable-ish, so review before deleting and never blanket-delete; `harnesses` are private roots.

Notes on specific entries:

- `skills/shared` is `~/.agents/skills`; `~/.gemini/skills` is already a symlink to it, so there is no separate Gemini entry.
- `sessions/omp-history` links the single file `~/.omp/agent/history.db`. SQLite's `-wal` and `-shm` companions stay beside the real file at the source. It is a symlink, not a hardlink, so no companion is separated from it.
- Shell history, completion dumps, and backup copies are not linked. The `zshrc.d` and `zshenv.d` drop-in directories are linked and may contain secrets, so treat them as private.
- Desktop is registered once, as `desktop`.
- Targets nest in places (`~/.config` and `~/.config/opencode`; `~/proj` and `~/proj/hiiro`). That is fine: only logical names must not overlap.
- No per-file links across large collections; link the directory.

The implementation writes `README.md` descriptions into the hub root and each declared real grouping directory. Nothing is written inside a symlink target.

## Behavior to know

- Symlinks only. Directories cannot be hardlinked, and a mutable file replaced by rename leaves a hardlink pointing at the stale old file. There are no automatic hardlinks.
- The tool itself never moves originals, but applications reached through a symlink can modify, replace, or delete the originals. Edits through the hub are edits to the originals, and source changes show up immediately. Moving or renaming a source breaks its link; `doctor` reports it and you update the catalog.
- Back up the originals, not the link tree. Do not follow symlinks in backups through the hub.
- **Do not commit hub contents.** Harness roots can contain credentials (`auth.json`, tokens, OAuth state) and full transcripts. Do not publish, sync, or index `~/hub` with tools that follow symlinks.
- `find NAME QUERY` is a filename-only, case-insensitive search scoped to one registered link or group. It follows the registered link, not symlinks inside it, skips `.git`, `node_modules`, and `.cache`, never reads file contents, and stops at `--limit` (default 100).
- The hub root is mode 0700.
