# inline-diff.nvim

![Neovim](https://img.shields.io/badge/Neovim-0.11+-green?logo=neovim)
![License](https://img.shields.io/github/license/cvlmtg/inline-diff.nvim)
![Latest release](https://img.shields.io/github/v/release/cvlmtg/inline-diff.nvim)

![Demo](/.github/assets/diff.gif)

High performance, live, VSCode-style inline diff for Neovim. Shows the current buffer's changes against a git ref (which defaults to `HEAD`) as you type, with word-level highlighting.

## Features

- 🔴 Live word-level highlighting as you type
- ⚡ High performance via debouncing and sync / async diffing with Myers algorithm
- 🎯 Compares against any git ref (default: `HEAD`)
- 🎨 Fully customizable highlight groups
- 📦 Zero dependencies beyond Neovim 0.11+ and git

## Why inline-diff.nvim?

Unlike split-based diff tools like `diffview.nvim` or Neovim's built-in
`:diffsplit`, which open a separate panel to show changes side by side,
inline-diff.nvim renders deletions and insertions **directly in your buffer**,
word by word — like VSCode's inline diff editor. There's no context switch,
no extra window to manage: you see what changed exactly where it changed,
while you keep editing.

`gitsigns.nvim` also works inline, but only marks changed lines in the sign
column without showing the actual content of deletions. inline-diff.nvim
shows you the full picture: removed text appears struck through (or
highlighted) next to the new version, at the word level.

`mini.diff` also updates live as you type and can display word-level diffs
with deleted virtual lines via its togglable overlay — so the visualization
is comparable. The difference is scope: mini.diff is a broader hunk-management
tool with apply/reset actions, navigation mappings, and textobject support,
while inline-diff.nvim is intentionally a focused, zero-friction visualization
layer. If you just want to see what changed without any extra bindings or
mental overhead, inline-diff.nvim is the leaner choice.

---

## Get started

### lazy.nvim

```lua
{ "cvlmtg/inline-diff.nvim", opts = {} }
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

```bash
git clone https://github.com/cvlmtg/inline-diff.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/inline-diff.nvim
```

Then call `setup()` somewhere in your config:

```lua
require("inline-diff").setup()
```

### Suggested keymap

```lua
vim.keymap.set("n", "<leader>gd", "<cmd>InlineDiff<cr>", { desc = "Toggle inline diff" })
```

---

For the full reference — commands, Lua API, highlight groups, and configuration — see `:help inline-diff`.

---

## Background

This plugin was built as an experiment in vibe coding with [Claude Code](https://claude.ai/code). The goal was to explore how far AI-assisted development could go on a real, non-trivial Neovim plugin — from architecture to edge cases to performance. The result turned out to be genuinely useful, carefully tested, and high-performance, so it felt worth sharing.
