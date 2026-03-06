# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
