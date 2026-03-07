# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-03-07

### Added
- `[ref]` argument on all commands and the Lua API — diff against any git ref
  per invocation without changing the default (`HEAD~1`, a branch, a SHA, …)
- `staged` ref: diff against the git index (what you've `git add`-ed); falls
  back to `HEAD` automatically when the file has no staged content

### Fixed
- Auto-scroll now correctly reveals all bottom virtual lines when the last
  buffer line wraps to more than one visual row
- Auto-scroll no longer crashes when `topline == buf_line_count`

### Performance
- Removed redundant O(m+n) line-copy in `_diff_lines`
- LCS dp-table initialization reduced from O(m×n) to O(m+n) by only
  pre-filling boundary rows/cols
- `compute_hunks` now delivers results synchronously, saving one event-loop
  round-trip per keystroke

### Tests
- Expanded test suite to 56 tests; added dedicated `scroll_spec.lua`

## [0.1.0] - 2026-03-06

### Added
- Initial implementation: live inline diff against a git ref with word-level highlighting
- `InlineDiffEnable`, `InlineDiffDisable`, `InlineDiff` (toggle) commands
- `setup()`, `enable()`, `disable()`, `toggle()` Lua API
- Highlight groups derived from colorscheme's `DiffAdd`/`DiffDelete`, recomputed on `ColorScheme`
- Debounced live updates on `TextChanged`/`TextChangedI`
- Auto-scroll to reveal virtual lines at buffer edges (top/bottom deletions)
- Pure Lua LCS-based line diff — no `git diff` subprocess
- Git repo root and HEAD ref content cached per buffer; invalidated on `BufWritePost`, `BufReadPost`, and `FocusGained`
- `CursorMoved` scroll adjustment short-circuited when no edge virtual lines exist
- Identifier-boundary word tokenization: `vim.o.something` → `vim.o.{foobar}` highlights only the changed part

### Fixed
- Word-level highlight colors, layering, and foreground contrast
- Buffer reload via `:e!` now correctly refreshes the diff
