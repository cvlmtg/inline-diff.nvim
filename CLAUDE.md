# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Neovim plugin written in Lua providing inline diff functionality.

## Commands

Run tests (requires [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)):
```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}" -c "qa"
```

Run a single test file:
```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/path_to_spec.lua" -c "qa"
```

Lint with `luacheck`:
```bash
luacheck lua/
```

Format with `stylua`:
```bash
stylua lua/
```

## Architecture

Standard Neovim plugin layout:

```
lua/inline-diff/
  init.lua        # Public API: setup(), enable(), disable(), toggle()
  diff.lua        # Diff engine: LCS line diff + word diff, git HEAD retrieval
  highlight.lua   # Derive InlineDiff* highlight groups from DiffAdd/DiffDelete
  render.lua      # Apply extmarks (line highlights, virt_lines, inline virt_text)
  state.lua       # Per-buffer state: namespace, augroup, debounce timer, edge-virt flags, ref cache
plugin/
  inline-diff.lua # Auto-loaded: registers InlineDiffEnable/Disable/Toggle(InlineDiff) commands
tests/
  minimal_init.lua  # Minimal Neovim config bootstrapping plenary
  *_spec.lua        # Test files (plenary busted)
```

### Key design notes

- Requires **Neovim 0.11+** (uses `virt_text_pos = "inline"` and `vim.uv`).
- Internals are exposed as `M._*` for unit testing.
- Word-level colors are derived at runtime by shifting the HSL lightness and saturation of `DiffAdd`/`DiffDelete`. Groups are re-derived on `ColorScheme`.
- Deleted lines render as `virt_lines`.
- Live updates are debounced (default 150 ms) via a reused `vim.uv` timer per buffer.
- Tests use plenary's `busted`-compatible API (`describe`, `it`, `assert`).
