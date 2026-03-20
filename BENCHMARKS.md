# Benchmarks

Measures end-to-end time from having `old_lines` + `new_lines` ready through diff
computation to `render.apply()` completing (extmarks set).

## How to run

```bash
nvim --headless --clean -c "set rtp+=." -c "luafile bench/run.lua"
```

## Environment

| | |
|---|---|
| Machine | Apple M4 Pro, 24 GB RAM |
| OS | macOS Tahoe 26.3.1 (Darwin 25.3.0) |
| Neovim | 0.11.6 |
| Iterations | 10 measured + 2 warmup |

## Approaches

| Name | Description |
|---|---|
| **Myers (current)** | Pure Lua Myers O(ND) diff. Sync on the main thread for < 500 total lines; spawns a `vim.uv` thread for ≥ 500 lines and round-trips results via JSON. |
| **git diff (old)** | Pre-[99b3974](https://github.com/you/neovim-inline-diff/commit/99b3974) approach. Writes both line arrays to temp files, shells out to `git diff --no-index --unified=0`, and parses the unified-diff output. Always async (subprocess). |
| **vim.diff (xdiff)** | Neovim's built-in `vim.diff()` wrapper around the C xdiff library. Always synchronous. Returns `{old_start, old_count, new_start, new_count}` index tuples that are converted to the hunk format expected by `render.apply()`. |

## Results

```
Dataset                                 Approach               Median ms    Min ms    Max ms   Mean ms
────────────────────────────────────────────────────────────────────────────────────────────────────
small/scattered (100+110, sync)         Myers (current)            0.206     0.153     0.316     0.232
small/scattered (100+110, sync)         git diff (old)            24.969    23.303    27.088    24.985
small/scattered (100+110, sync)         vim.diff (xdiff)           0.165     0.130     0.352     0.204
────────────────────────────────────────────────────────────────────────────────────────────────────
small/mixed   (200+~200, sync)          Myers (current)            5.159     4.927     5.437     5.171
small/mixed   (200+~200, sync)          git diff (old)            29.046    27.822    30.639    29.098
small/mixed   (200+~200, sync)          vim.diff (xdiff)           3.331     3.014     3.387     3.287
────────────────────────────────────────────────────────────────────────────────────────────────────
large/scattered (1000+1050, async)      Myers (current)            7.678     7.209     9.562     7.902
large/scattered (1000+1050, async)      git diff (old)            27.188    26.264    28.110    27.217
large/scattered (1000+1050, async)      vim.diff (xdiff)           1.308     1.214     1.877     1.508
────────────────────────────────────────────────────────────────────────────────────────────────────
large/mixed   (2000+~2000, async)       Myers (current)          203.925   143.744   230.573   189.576
large/mixed   (2000+~2000, async)       git diff (old)            62.357    61.233    63.933    62.386
large/mixed   (2000+~2000, async)       vim.diff (xdiff)          33.501    33.425    33.787    33.563
```

## Considerations

### git diff subprocess is never competitive

The old subprocess approach takes 25–30 ms even on small files — an irreducible
floor imposed by process spawning, two `writefile` calls, and IPC overhead.
That's 100–150× slower than the Lua paths on the same input and would be
perceptible as a flicker on every keystroke.

### Myers vs. vim.diff on small files (sync path)

On the sync path (< 500 total lines) both approaches are well under 1 ms for
lightly-edited files (scattered), so the difference is imperceptible in
practice. With a heavier edit pattern (mixed: insertions, deletions, and
modifications throughout 200-line files), Myers takes ~5 ms versus ~3.3 ms for
xdiff. The gap comes from Myers being an O(ND) Lua implementation while xdiff
is compiled C, but 5 ms is still comfortably below any perceptible threshold.

### Myers vs. vim.diff on large files (async path)

The async path tells a different story. On `large/scattered` (1050 + 1000
lines, few edits) Myers takes ~8 ms and xdiff 1.3 ms. For `large/mixed` (≈4000
total lines, heavy edits) Myers balloons to ~200 ms while xdiff stays at
~34 ms.

The Myers slowdown on `large/mixed` is **not** the Myers algorithm itself —
it is the async thread's serialization overhead. Every time `compute_hunks`
dispatches to the worker thread it must:

1. `table.concat` both line arrays into strings
2. Spawn a `vim.uv` thread
3. Re-split the strings back into line arrays inside the worker
4. JSON-encode the full hunk list (which for a heavily-edited 2000-line file
   can be thousands of entries)
5. Deliver the JSON string back over the `vim.uv.new_async` channel
6. `vim.json.decode` the result on the main thread

Steps 4–6 dominate at high hunk counts. For `large/scattered` (few hunks, ~100
changed lines) the JSON round-trip is cheap, and the overhead is only ~6–7 ms
extra compared to xdiff. For `large/mixed` (hundreds of hunks) it overwhelms
the actual diff time.

### Why Myers is still the right default

Despite the async overhead, swapping to `vim.diff` is not straightforward:

- `vim.diff` is synchronous and blocks the main thread. For very large,
  heavily-modified files this would stall Neovim's UI for tens of milliseconds
  on every keystroke — exactly the problem the async thread was introduced to
  solve.
- The 200 ms figure for `large/mixed` is a worst-case: 2000-line files with
  edits on roughly every 4th line. Realistic editing sessions rarely produce
  that many simultaneous hunks.
- The current 500-line threshold means that files where the sync→async
  transition is most impactful already have the worst serialization ratio.

A targeted improvement would be to reduce JSON overhead in the thread worker
(e.g. pass hunk counts through the async channel and keep line content on the
main thread) or to lower the async threshold further. The `vim.diff` numbers
serve as a useful lower bound on what a C-level synchronous implementation
could achieve.
