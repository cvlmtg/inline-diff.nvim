# Contributing

## Running tests

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim). The bootstrap script clones it automatically if not present.

```bash
nvim --headless \
  -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}" \
  -c "qa"
```

Run a single file:

```bash
nvim --headless \
  -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/diff_spec.lua" \
  -c "qa"
```

## Linting

```bash
luacheck lua/
```

## Formatting

```bash
stylua lua/
```

## Pull requests

- All tests must pass
- Code must be formatted with `stylua` (configuration in `.stylua.toml`)
- Keep changes focused; one concern per PR
