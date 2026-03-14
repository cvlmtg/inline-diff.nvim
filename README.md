# inline-diff.nvim

![Demo](/.github/assets/diff.gif)

High performance, live, VSCode-style inline diff for Neovim. Shows the current buffer's changes against a git ref (which defaults to `HEAD`) as you type, with word-level highlighting.

This plugin was built as an experiment in vibe coding with [Claude Code](https://claude.ai/code). The goal was to explore how far AI-assisted development could go on a real, non-trivial Neovim plugin — from architecture to edge cases to performance. The result turned out to be genuinely useful, carefully tested, and high-performance, so it felt worth sharing.

**Requires Neovim 0.11+.**

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
