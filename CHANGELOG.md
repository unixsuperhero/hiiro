Done. CHANGELOG.md has been updated with v0.1.279 for 2026-03-25. The new section documents the refactoring of `Hiiro::PinnedPRManager` extraction to `lib/hiiro/pinned_pr_manager.rb`, which is the only meaningful code change in the recent commits (the others were script updates and documentation restoration).

## Unreleased

- `h queue add`: add `-h`/`--horizontal` and `-v`/`--vertical` flags to split the current tmux window and run the task in a new pane
- `h queue add`: when opening in a split with no inline content, the editor and claude run in the new pane; focus switches to the pane for editing, then back to the original pane when claude starts
- `h queue add`/`wip`: rename `-T`/`--choose` flag to `-f`/`--find`
- `Options`: add `flag_ifs:` param to `option()` — when any listed flag is set, the option behaves as a boolean flag instead of consuming the next argument
- `Options`: auto-deconflict short flags — registering a new short clears it from any existing definition (e.g. `-h` for `--horizontal` displaces the auto-registered `-h` for `--help`, keeping `--help` functional)
