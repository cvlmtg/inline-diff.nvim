# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.3.0] - 2026-03-14

### Fixed
- Word-level diff no longer splits multi-byte UTF-8 characters (CJK, accented letters, emoji) across token boundaries. Previously each byte of a multi-byte character was treated as a separate token, which could produce `nvim_buf_set_extmark` calls with byte offsets landing mid-codepoint, causing garbled highlight rendering.

### Tests
- 74 tests (up from 69); added `_tokenize` unit tests and multi-byte word-diff coverage

## [2.2.0] - 2026-03-14

### Documentation
- Improved README with clearer setup and usage instructions
- Updated demo GIF

## [2.1.0] - 2026-03-14

### Performance
- Myers O(ND) algorithm now used for word-level diff, replacing the O(m×n) LCS
- Hunk cache: skip extmark clear+rebuild when hunks are unchanged between refreshes (common during typing)
- Synchronous diff path for files under 500 total lines, avoiding thread serialization overhead
- `decode_lines` in worker no longer allocates a copy of the full content string

### Fixed
- `prev_hunks` cache correctly invalidated when switching refs, preventing blank buffer after `render.clear()`

### Tests
- 69 tests (up from 60); added `_hunks_equal` unit tests and ref-switch invalidation coverage

## [2.0.0] - 2026-03-13

### Fixed
- Windows: `git show` path spec now uses forward slashes; backslashes in
  `relpath` caused git to report "path exists on disk but not in HEAD"
- Windows: `git show` output with CRLF line endings no longer leaves
  trailing `\r` on every old line, which caused all lines to compare unequal
- Thread worker: if `require("inline-diff._worker")` fails in the background
  thread (e.g. due to `package.path` resolution differences), the diff now
  falls back to synchronous computation on the main thread instead of
  silently producing no output

### Performance
- Diff computation runs off the main thread via `vim.uv.new_thread`, keeping
  the UI responsive on large files

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
