local diff = require("inline-diff.diff")

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
    table.insert(chunks, { seg.text, hl })
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
      table.insert(highlights, {
        col = seg.byte_start - 1, -- 0-indexed
        end_col = seg.byte_end, -- exclusive
        hl_group = "InlineDiffWordAdd",
      })
    end
  end
  return highlights
end

function M.apply(bufnr, ns, hunks)
  M.clear(bufnr, ns)

  for _, hunk in ipairs(hunks) do
    if hunk.old_count == 0 then
      -- Pure addition
      for i = 0, hunk.new_count - 1 do
        local line = hunk.new_start - 1 + i -- 0-indexed
        vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
          line_hl_group = "InlineDiffAdd",
        })
      end
    elseif hunk.new_count == 0 then
      -- Pure deletion
      local virt_lines = {}
      for _, old_line in ipairs(hunk.old_lines) do
        table.insert(virt_lines, { { old_line, "InlineDiffDelete" } })
      end
      local anchor = hunk.new_start - 1 -- 0-indexed
      local above = false
      if hunk.new_start == 0 then
        anchor = 0
        above = true
      end
      vim.api.nvim_buf_set_extmark(bufnr, ns, anchor, 0, {
        virt_lines = virt_lines,
        virt_lines_above = above or (hunk.new_start > 0),
      })
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

        -- Single extmark: virt_line above + line highlight for the new line
        vim.api.nvim_buf_set_extmark(bufnr, ns, new_line_idx, 0, {
          virt_lines = { old_chunks },
          virt_lines_above = true,
          line_hl_group = "InlineDiffAdd",
        })

        -- Word-level highlights on new line
        for _, hl in ipairs(new_highlights) do
          vim.api.nvim_buf_set_extmark(bufnr, ns, new_line_idx, hl.col, {
            end_col = hl.end_col,
            hl_group = hl.hl_group,
            priority = 200,
          })
        end
      end

      -- Excess old lines (more deletions than additions)
      if hunk.old_count > hunk.new_count then
        local extra_virt = {}
        for i = paired + 1, hunk.old_count do
          local old_line = hunk.old_lines[i] or ""
          table.insert(extra_virt, { { old_line, "InlineDiffDelete" } })
        end
        local anchor = hunk.new_start - 1 + paired - 1 -- last paired line, 0-indexed
        vim.api.nvim_buf_set_extmark(bufnr, ns, anchor, 0, {
          virt_lines = extra_virt,
        })
      end

      -- Excess new lines (more additions than deletions)
      if hunk.new_count > hunk.old_count then
        for i = paired + 1, hunk.new_count do
          local line_idx = hunk.new_start - 1 + (i - 1)
          vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx, 0, {
            line_hl_group = "InlineDiffAdd",
          })
        end
      end
    end
  end
end

return M
