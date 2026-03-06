local state = require("inline-diff.state")
local highlight = require("inline-diff.highlight")
local diff = require("inline-diff.diff")
local render = require("inline-diff.render")

local M = {}

M.config = {
  debounce_ms = 150,
  ref = "HEAD",
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  highlight.define()
  highlight.setup_autocmd()
end

function M._refresh(bufnr)
  local s = state.get(bufnr)
  if not s.enabled then
    return
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  s.generation = s.generation + 1
  local gen = s.generation

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then
    return
  end

  local function do_diff(old_lines)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local s2 = state._bufs[bufnr]
    if not s2 or not s2.enabled or s2.generation ~= gen then
      return
    end

    local new_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    diff.compute_hunks(old_lines, new_lines, function(hunks, herr)
      if herr or not hunks then
        return
      end
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      local s3 = state._bufs[bufnr]
      if not s3 or not s3.enabled or s3.generation ~= gen then
        return
      end
      render.apply(bufnr, s3.ns, hunks)
      M._adjust_scroll(bufnr, s3.ns)
    end)
  end

  -- Use cached ref content when available
  if s.ref_lines and not s.ref_dirty then
    do_diff(s.ref_lines)
    return
  end

  diff.get_ref_content(filepath, M.config.ref, function(old_lines, err)
    if err or not old_lines then
      return
    end
    local s2 = state._bufs[bufnr]
    if s2 then
      s2.ref_lines = old_lines
      s2.ref_dirty = false
    end
    do_diff(old_lines)
  end)
end

function M._adjust_scroll(bufnr, ns)
  local s = state._bufs[bufnr]
  if not s then
    return
  end

  -- Short-circuit: no edge virtual lines means nothing to adjust
  if not s.has_top_virt and not s.has_bot_virt then
    return
  end

  local buf_line_count = vim.api.nvim_buf_line_count(bufnr)
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    local view = vim.api.nvim_win_call(winid, vim.fn.winsaveview)

    -- First-line deletion: set topfill so virt_lines_above at row 0 are visible.
    if s.has_top_virt and view.topline == 1 then
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { 0, 0 }, { 0, -1 }, { details = true })
      for _, m in ipairs(marks) do
        if m[4].virt_lines and m[4].virt_lines_above then
          local count = #m[4].virt_lines
          if view.topfill ~= count then
            vim.fn.win_execute(winid, "lua vim.fn.winrestview({topfill=" .. count .. "})")
          end
          break
        end
      end
    end

    -- Last-line deletion: scroll down so all virtual lines below the last buffer
    -- line fit within the window.
    if s.has_bot_virt then
      local win_height = vim.api.nvim_win_get_height(winid)
      local last_row = buf_line_count - 1
      local bot_marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { last_row, 0 }, { last_row, -1 }, { details = true })
      for _, m in ipairs(bot_marks) do
        if m[4].virt_lines and not (m[4].virt_lines_above == true) then
          local count = #m[4].virt_lines
          if buf_line_count - view.topline < win_height then
            local height_above = 0
            if buf_line_count >= 2 then
              local h = vim.api.nvim_win_text_height(winid, {
                start_row = view.topline - 1,
                end_row = buf_line_count - 2,
              })
              height_above = h.all
            end
            local last_line_row = view.topfill + height_above
            if last_line_row <= win_height - 1 then
              local space = (win_height - 1) - last_line_row
              local needed = count - space
              if needed > 0 then
                vim.fn.win_execute(winid, "normal! " .. needed .. "\5") -- N<C-e>
              end
            end
          end
          break
        end
      end
    end
  end
end

function M._schedule_refresh(bufnr)
  local s = state.get(bufnr)
  if not s.enabled then
    return
  end
  if not s.timer then
    s.timer = vim.uv.new_timer()
  end
  s.timer:stop()
  s.timer:start(
    M.config.debounce_ms,
    0,
    vim.schedule_wrap(function()
      M._refresh(bufnr)
    end)
  )
end

function M.enable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local s = state.get(bufnr)
  if s.enabled then
    return
  end
  s.enabled = true

  -- Ensure highlights are defined
  highlight.define()

  -- Initial refresh
  M._refresh(bufnr)

  -- Set up autocmds for live updates
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = s.augroup,
    buffer = bufnr,
    callback = function()
      M._schedule_refresh(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = s.augroup,
    buffer = bufnr,
    callback = function()
      local sb = state._bufs[bufnr]
      if sb then sb.ref_dirty = true end
      M._refresh(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd("FocusGained", {
    group = s.augroup,
    buffer = bufnr,
    callback = function()
      local sb = state._bufs[bufnr]
      if sb then sb.ref_dirty = true end
      M._refresh(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = s.augroup,
    buffer = bufnr,
    callback = function()
      local s2 = state._bufs[bufnr]
      if s2 and s2.enabled then
        M._adjust_scroll(bufnr, s2.ns)
      end
    end,
  })
end

function M.disable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local s = state._bufs[bufnr]
  if not s or not s.enabled then
    return
  end
  render.clear(bufnr, s.ns)
  state.remove(bufnr)
end

function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local s = state._bufs[bufnr]
  if s and s.enabled then
    M.disable(bufnr)
  else
    M.enable(bufnr)
  end
end

return M
