# Performance optimization options

After replacing the O(m×n) LCS line diff with Myers O(ND), the line-level
diff is no longer the bottleneck. These are the remaining optimizations
ranked by impact/effort ratio.

## Option A: Cache hunks, skip render when unchanged ✅

- **Impact: High** | **Effort: Easy**
- **Files**: `init.lua`, `state.lua`
- During normal typing, most debounced refreshes produce identical hunks
  (user is editing within an already-changed region). Currently every
  refresh clears ALL extmarks and recreates them + runs word diff on
  every paired line.
- Fix: store previous hunks in buffer state. After `compute_hunks`,
  compare with cached hunks. If identical, skip `render.apply` entirely.

## Option B: Reuse Myers for word diff (replace O(m×n) `_lcs`) ✅

- **Impact: High** | **Effort: Medium**
- **Files**: `diff.lua`
- `_word_diff` calls `_lcs` which is still O(m×n) on tokens. Myers would
  be O(ND) which is much better for similar lines (small D).
- `_myers_matched` already exists and could be adapted for token arrays.

## Option C: Skip thread for small diffs ✅

- **Impact: High** | **Effort: Medium**
- **Files**: `diff.lua`
- `compute_hunks` always serializes through the thread even for trivial
  diffs. For single-line edits, run `_diff_lines` synchronously to avoid
  the concat → thread → split → encode → decode round-trip.

## Option D: Avoid string copy in `decode_lines` ✅

- **Impact: Medium** | **Effort: Easy**
- **Files**: `_worker.lua`
- `(s .. "\n"):gmatch(...)` copies the entire file content just to append
  one newline. Use `s:gmatch("([^\n]*)\n?")` or a `string.find` loop.
