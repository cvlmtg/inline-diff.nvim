# inline-diff.nvim

Live, VSCode-style inline diff for Neovim. Shows the current buffer's changes against a git ref (which defaults to `HEAD`) as you type, with word-level highlighting.

**Requires Neovim 0.11+.**

---

## Installation

### lazy.nvim

```lua
{
  "cvlmtg/inline-diff.nvim",
  config = function()
    require("inline-diff").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "cvlmtg/inline-diff.nvim",
  config = function()
    require("inline-diff").setup()
  end,
}
```

### Manual (no plugin manager)

Clone the repo into your Neovim packages directory:

```bash
git clone https://github.com/cvlmtg/inline-diff.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/inline-diff.nvim
```

Then call `setup()` somewhere in your config:

```lua
require("inline-diff").setup()
```

---

## Configuration

`setup()` accepts an optional table. These are the defaults:

```lua
require("inline-diff").setup({
  debounce_ms = 150,  -- ms to wait after last keystroke before refreshing
})
```

---

## Usage

### Commands

| Command | Description |
|---|---|
| `:InlineDiffEnable [ref]` | Enable inline diff for the current buffer, optionally against `ref` (default: `HEAD`) |
| `:InlineDiffDisable` | Disable inline diff and clear all highlights |
| `:InlineDiff [ref]` | Toggle inline diff; if `ref` is given, always enable with that ref |

`ref` can be any git ref (`HEAD~1`, a commit SHA, a branch name) or the special value `staged` to diff against the index (what you've `git add`-ed). If `staged` is used but the file has no staged content, the diff falls back to `HEAD` automatically.

```vim
:InlineDiff staged    " diff against staged (index)
:InlineDiff HEAD~1    " diff against the previous commit
:InlineDiff main      " diff against a branch
```

### Lua API

```lua
local d = require("inline-diff")

d.enable()              -- enable for current buffer, diff against HEAD
d.enable(nil, "HEAD~1") -- diff against a specific ref
d.enable(bufnr, ref)    -- enable for a specific buffer and ref

d.disable()             -- disable for current buffer
d.disable(bufnr)

d.toggle()              -- toggle for current buffer
d.toggle(nil, ref)      -- always enable with ref (never disables)
d.toggle(bufnr, ref)
```

### Suggested keymaps

```lua
vim.keymap.set("n", "<leader>gd", "<cmd>InlineDiff<cr>", { desc = "Toggle inline diff" })
```

---

## Highlight groups

The plugin derives its colors from your colorscheme's `DiffAdd` and `DiffDelete` groups and recomputes them automatically on `ColorScheme`.

| Group | Used for |
|---|---|
| `InlineDiffAdd` | Background of added lines |
| `InlineDiffDelete` | Background of deleted/old virtual lines |
| `InlineDiffWordAdd` | Background of added words (brighter green) |
| `InlineDiffWordDel` | Background of deleted words (brighter red) + strikethrough |

To override any group, set it after `setup()` or in a `ColorScheme` autocmd:

```lua
vim.api.nvim_set_hl(0, "InlineDiffWordAdd", { bg = 0x00AA44 })
```

---

## Requirements

- Neovim 0.11+
- `git` available in `$PATH`
- The file must be inside a git repository

---

## Running the tests

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)'s busted runner. The test bootstrap script (`tests/minimal_init.lua`) automatically clones plenary if it is not already installed.

Run the full test suite:

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}" \
  -c "qa"
```

Run a single test file:

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/diff_spec.lua" \
  -c "qa"
```

Available test files:

| File | What it covers |
|---|---|
| `tests/diff_spec.lua` | LCS algorithm, pure Lua line diff (`_diff_lines`), word-level diff |
| `tests/highlight_spec.lua` | HSL color math, round-trips, boost/contrast formulas |
| `tests/render_spec.lua` | Extmark chunk builders, virt_line placement |
| `tests/pipeline_spec.lua` | End-to-end: line diff → render → extmark positions |
