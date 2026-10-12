# 14. Shared utility registrations and personal profiles

Work ONLY in `/Users/unixsuperhero/proj/rehiiro`. Read [the shared contract](00-start-here.md), [the proposal](proposal.md), and applicable project instructions first. Verify the implemented dependency outputs below, then execute only this planned step. Inspect current source before editing because the research snapshot can differ.

## Goal

Remove actual utility duplication through value-backed registrations, media presets, directory profiles, and shared selectors. Preserve distinct byte, formatting, capture, and personal-integration contracts.

## Inputs

- Time: `bin/h-date`, `bin/h-time`, `lib/hiiro/time_input.rb`, `lib/hiiro/duration.rb`.
- Media and output: `bin/h-video`, `bin/h-mermaid`, `bin/h-html`, `bin/h-jsonl`.
- Profiles and selectors: `bin/h-home`, `bin/h-dotfiles`, `bin/h-vim`, `bin/h-plugin`, `bin/h-config`, `bin/h-commit`, `bin/h-sha`, `bin/h-pm`, `bin/h-claude`.
- Environment assignments: `bin/h-env`; compare the explicitly named installed export source below without editing it.
- Existing screen and table contracts: `lib/hiiro/tui.rb`, `lib/hiiro/table.rb`, `lib/hiiro/table_scope.rb`, `lib/hiiro/table_actions.rb`; read the Table/Tui sections of [AGENTS.md](../../AGENTS.md) and [the TUI plan](../../docs/plans/hiiro-tui.md). Unchecked future plan items are not this step's scope.
- Read [command docs](../../docs/README.md), [README](../../README.md), and [CHANGELOG](../../CHANGELOG.md).
- Read-only external sources: `/Users/unixsuperhero/bin/h-encode`, `h-decode`, `h-audio`, `h-ruby`, `h-iface`, `h-screencap`, `h-crop`, `h-export`, and `h-asciinema` in that same directory. These supply existing implementations absent from the clone, not permission to execute or edit the installed originals. If source/support needed for a named cutover is unavailable, report the exact blocker rather than reconstructing it.

## Dependencies

Verify [02 context](02-command-context.md), [03 execution](03-owned-execution.md), [04 catalog](04-command-catalog-and-lazy-boot.md), [10 validation](10-validation-recipes.md), [11 artifacts](11-clipboard-artifacts-and-context.md), and [13 picker](13-editable-fuzzy-picker-pruning.md). Require working directory provenance, owned outcomes, read-only registrations, recipe execution, byte-preserving artifacts, and editable identity-backed selection. Reuse their implemented interfaces, not assumed Ruby signatures.

## Work

1. Compare handlers and record their differences before extraction. Distinguish equivalent recipes from similar names with different output. Reproduce uncertain behavior in disposable fixtures before changing it.
2. Share date/time registrations over `TimeInput` and `Duration`. Keep aliases and usage errors. Date parsing prints ISO8601 with milliseconds; time parsing prints `HH:MM:SS.mmm`. Preserve `now` differences, UTC/local offsets, numeric unit detection, rational inputs, rounding, negative duration signs, diff direction, and percent insertion in `fmt`.
3. Parameterize genuinely repeated FFmpeg recipes and output naming. Preserve H.264/AAC, VP9/Opus, MKV remux, quality, scale, and audio choices. `clip` uses duration, `clip_to` uses end time, and `clip_precise` re-encodes. Keep seeking placement and stream-copy distinctions. Reuse duration/clipping for the completed audio handlers; retain transcription as a configured adapter with its prerequisites loaded only when selected.
4. Keep screen capture, terminal casts, and amber-border detection separate recipes. Preserve multi-window/audio modes, graceful finalization, border tolerance/inset, and even dimensions without falsely promising exact 16:9. Retain existing native/Python adapters rather than rewriting their algorithms. For terminal casts, consolidate dated name allocation into one operation; preserve record, playback, and resume-as-a-new-cast behavior. Move output-directory and editor recipe policy into a personal profile rather than hard-coding notes paths or `safe_nvim`. Do not port audio mapping debugger bodies as completed features.
5. Pair encode/decode input handling and codec selection. Preserve file, explicit `-`, piped stdin, and clipboard precedence; binary reads/writes; newline-free output; unpadded Base64url; percent versus form semantics; UTF-8 requirements; malformed-input failures; and JSON-string-only decoding.
6. Share directory registrations for home, dotfiles, Neovim, and plugins while preserving defaults and specialized actions. Deduplicate `h-config`'s repeated Herdr registration. Use resolved context and owned execution without fake task records. Keep native config/editor behavior and optional terminal adapters.
7. Share commit identities and selection mechanics between `h-commit` and `h-sha`, preserving log options, defaults, and stdout newline differences. Use step 13's picker contract and one `Tui::State`; do not add curses or external fuzzy finders as screen engines. Keep `h-pm` as named queued prompts, Claude as a native adapter, and JSONL as explicit-file export rather than an agent-history database. Share Mermaid format registration and output mechanics only where behavior matches.
8. Consolidate installed `h-export` and clone `h-env` through one clone-owned environment-assignment writer. Compare their current destinations and argument semantics first. Choose and document destination and literal-value-versus-command semantics explicitly; do not silently redirect writes or execute supplied values as shell code. Preserve safe variable-name validation, escaping, existing file contents, newlines, and permissions. Expose any retained export shortcut over that same implementation; never modify live shell configuration during checks.
9. Consolidate installed `h-ruby iface` and `h-iface rb` into one clone-owned text-inspection operation with explicit pattern groups and deliberate aliases. Preserve exact/unique-prefix group selection, the class/attributes/methods/accessmodifiers/tests/lets/hiiro/all groups, declaration output, and file arguments. This is text matching, not a Ruby parser. Eliminate the shared fixed `/tmp/patterns` file using invocation-local input or an owned temporary file with cleanup; concurrent inspections must not change each other's patterns.
10. Migrate every affected caller, remove superseded clone-owned bodies, and update docs/changelog with preserved shortcuts, profiles, and actual prerequisites. Leave the installed reference files untouched.

## Acceptance criteria

- Equivalent handlers have one implementation; deliberate aliases preserve documented behavior.
- Time, codec, media, profile, and selector edge cases retain literal consumer-visible results.
- Personal recipes remain adapters; discovery does not require providers, credentials, or launch them.
- Environment assignment destinations and quoting are explicit, preserve unrelated configuration, and never evaluate literal values.
- Ruby inspection has one implementation without shared temporary-file races; cast naming/output/editor profiles preserve record/resume/play behavior.

## Verification

Run scoped deterministic behavioral tests, including existing time/duration and commit/SHA tests. Smoke actual sandboxed CLI commands: UTC epoch parsing prints `1970-01-01T00:00:00.000Z` for date and `00:00:00.000` for time; `diff 120 0` prints `-2m`. Round-trip bytes including NUL through codecs. Percent decoding `a+b` preserves `+`; form decoding yields a space. Invalid escapes fail without success output. Generate synthetic media and inspect actual codecs, dimensions, and copy/precise cuts with ffprobe. Exercise a real interactive selector and sandbox profile paths, queued prompts, and HTML/Mermaid artifacts. Record missing native prerequisites as blockers, not successful mock runs.

Use disposable shell configuration files to smoke the environment writer, including quotes, dollar signs, backticks, backslashes, invalid names, files without a final newline, and the documented destination policy; inspect exact file contents and permissions. Run Ruby inspection against fixture declarations under each accepted group and alias, including concurrent runs with different groups. Record, resume into a new cast, and play harmless terminal output through the clone-owned cast adapter with disposable output paths and a configured editor recipe; confirm naming/profile behavior and inspect actual cast artifacts. Missing source or native tooling leaves the relevant criterion blocked, not mocked or omitted.

## Non-goals and safety

No Git worktrees, universal resource DSL, new language/framework, TTS implementation, or unfinished-experiment completion. Original repository and installed files are reference-only. Sandbox HOME, database, configuration, outputs, and clipboard adapters. Do not mutate live accounts, capture private windows, or launch providers.

## Completion and handoff

After complete artifact smoke proof, mark only step 14 in [the index](README.md) and commit the complete step in the clone. Report interfaces/callers, preserved values, removed duplication, exact commands and observed outputs, limitations, and commit SHA. Leave the box unchecked if blocked. The next eligible step is [15](15-legacy-cutover-and-product-scope.md) only when all its dependencies are proved.
