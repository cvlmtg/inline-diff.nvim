local diff = require("inline-diff.diff")
local state = require("inline-diff.state")

local M = {}

function M.clear(bufnr, ns)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

function M._build_old_line_chunks(line, segments)
  if not segments then
    return { { line, "InlineDiffDelete" } }
  end
  local chunks = {}
  for _, seg in ipairs(segments) do
    local hl = seg.type == "del" and "InlineDiffWordDel" or "InlineDiffDelete"
    chunks[#chunks + 1] = { seg.text, hl }
  end
  return chunks
end

function M._build_new_line_highlights(segments)
  if not segments then
    return {}
  end
  local highlights = {}
  for _, seg in ipairs(segments) do
    if seg.type == "add" then
      highlights[#highlights + 1] = {
        col = seg.byte_start - 1, -- 0-indexed
        end_col = seg.byte_end, -- exclusive
        hl_group = "InlineDiffWordAdd",
      }
    end
  end
  return highlights
end

function M.apply(bufnr, ns, hunks)
  M.clear(bufnr, ns)

  local set_extmark = vim.api.nvim_buf_set_extmark
  local buf_line_count = vim.api.nvim_buf_line_count(bufnr)
  local last_row = buf_line_count - 1

  -- Reset edge virt flags for this render cycle
  local s = state._bufs[bufnr]
  if s then
    s.has_top_virt = false
    s.has_bot_virt = false
  end

  for _, hunk in ipairs(hunks) do
    if hunk.old_count == 0 then
      -- Pure addition
      for i = 1, hunk.new_count do
        local line_idx = hunk.new_start - 1 + (i - 1) -- 0-indexed
        local line_len = #(hunk.new_lines[i] or "")
        set_extmark(bufnr, ns, line_idx, 0, {
          end_col = line_len,
          hl_group = "InlineDiffAdd",
          hl_eol = true,
          priority = 200,
        })
      end
    elseif hunk.new_count == 0 then
      -- Pure deletion
      local virt_lines = {}
      for _, old_line in ipairs(hunk.old_lines) do
        virt_lines[#virt_lines + 1] = { { old_line, "InlineDiffDelete" } }
      end

      if hunk.new_start == 0 then
        set_extmark(bufnr, ns, 0, 0, {
          virt_lines = virt_lines,
          virt_lines_above = true,
        })
        if s then s.has_top_virt = true end
      else
        local anchor = math.min(hunk.new_start - 1, last_row) -- 0-indexed, clamped
        set_extmark(bufnr, ns, anchor, 0, {
          virt_lines = virt_lines,
          virt_lines_above = false,
        })
        if s and anchor == last_row then s.has_bot_virt = true end
      end
    else
      -- Changed lines: pair old and new 1:1
      local paired = math.min(hunk.old_count, hunk.new_count)

      for i = 1, paired do
        local old_line = hunk.old_lines[i] or ""
        local new_line = hunk.new_lines[i] or ""
        local old_segs, new_segs = diff._word_diff(old_line, new_line)

        local old_chunks = M._build_old_line_chunks(old_line, old_segs)
        local new_highlights = M._build_new_line_highlights(new_segs)

        local new_line_idx = hunk.new_start - 1 + (i - 1) -- 0-indexed

        -- virt_lines (old line above)
        set_extmark(bufnr, ns, new_line_idx, 0, {
          virt_lines = { old_chunks },
          virt_lines_above = true,
        })
        if s and new_line_idx == 0 then s.has_top_virt = true end

        -- Line background at priority 200 so it overrides treesitter/syntax fg.
        set_extmark(bufnr, ns, new_line_idx, 0, {
          end_col = #new_line,
          hl_group = "InlineDiffAdd",
          hl_eol = true,
          priority = 200,
        })

        -- Word-level highlights at priority 300 so they override the line bg.
        for _, hl in ipairs(new_highlights) do
          set_extmark(bufnr, ns, new_line_idx, hl.col, {
            end_col = hl.end_col,
            hl_group = hl.hl_group,
            priority = 300,
          })
        end
      end

      -- Excess old lines (more deletions than additions)
      if hunk.old_count > hunk.new_count then
        local extra_virt = {}
        for i = paired + 1, hunk.old_count do
          local old_line = hunk.old_lines[i] or ""
          extra_virt[#extra_virt + 1] = { { old_line, "InlineDiffDelete" } }
        end
        local anchor = hunk.new_start - 1 + paired - 1 -- last paired line, 0-indexed
        set_extmark(bufnr, ns, anchor, 0, {
          virt_lines = extra_virt,
        })
        if s and anchor == last_row then s.has_bot_virt = true end
      end

      -- Excess new lines (more additions than deletions)
      if hunk.new_count > hunk.old_count then
        for i = paired + 1, hunk.new_count do
          local line_idx = hunk.new_start - 1 + (i - 1)
          local line_len = #(hunk.new_lines[i] or "")
          set_extmark(bufnr, ns, line_idx, 0, {
            end_col = line_len,
            hl_group = "InlineDiffAdd",
            hl_eol = true,
            priority = 200,
          })
        end
      end
    end
  end
end

return M
