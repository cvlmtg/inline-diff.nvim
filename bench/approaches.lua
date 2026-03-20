-- The three diff approaches, each with a uniform interface:
--   run(old_lines, new_lines, bufnr, ns, done_cb)
-- done_cb() is called after render.apply() completes.

local diff = require("inline-diff.diff")
local render = require("inline-diff.render")

local M = {}

-- ── Approach 1: Current Myers algorithm ──────────────────────────────────────
-- Sync for <500 total lines, async via vim.uv.new_thread for >=500.

M.myers = {
  name = "Myers (current)",
  run = function(old_lines, new_lines, bufnr, ns, done_cb)
    diff.compute_hunks(old_lines, new_lines, function(hunks)
      if hunks then
        render.apply(bufnr, ns, hunks)
      end
      done_cb()
    end)
  end,
}

-- ── Approach 2: Old git diff subprocess (pre-commit 99b3974) ─────────────────
-- Writes temp files, shells out to `git diff --no-index`, parses unified diff.

local function parse_diff(raw)
  local hunks = {}
  local current = nil
  for line in raw:gmatch("[^\n]*") do
    local os_str, oc_str, ns_str, nc_str = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
    if os_str then
      if current then
        hunks[#hunks + 1] = current
      end
      current = {
        old_start = tonumber(os_str),
        old_count = tonumber(oc_str) or 1,
        new_start = tonumber(ns_str),
        new_count = tonumber(nc_str) or 1,
        old_lines = {},
        new_lines = {},
      }
      if oc_str == "0" then current.old_count = 0 end
      if nc_str == "0" then current.new_count = 0 end
    elseif current then
      local prefix = line:sub(1, 1)
      if prefix == "-" then
        current.old_lines[#current.old_lines + 1] = line:sub(2)
      elseif prefix == "+" then
        current.new_lines[#current.new_lines + 1] = line:sub(2)
      end
    end
  end
  if current then
    hunks[#hunks + 1] = current
  end
  return hunks
end

M.git_diff = {
  name = "git diff (old)",
  run = function(old_lines, new_lines, bufnr, ns, done_cb)
    local old_tmp = vim.fn.tempname()
    local new_tmp = vim.fn.tempname()
    vim.fn.writefile(old_lines, old_tmp)
    vim.fn.writefile(new_lines, new_tmp)
    vim.system(
      { "git", "diff", "--no-index", "--unified=0", "--no-color", old_tmp, new_tmp },
      { text = true },
      function(obj)
        vim.schedule(function()
          os.remove(old_tmp)
          os.remove(new_tmp)
          local hunks
          if obj.code == 0 then
            hunks = {}
          elseif obj.code == 1 then
            hunks = parse_diff(obj.stdout)
          end
          if hunks then
            render.apply(bufnr, ns, hunks)
          end
          done_cb()
        end)
      end
    )
  end,
}

-- ── Approach 3: vim.diff / xdiff ─────────────────────────────────────────────
-- Neovim's built-in xdiff wrapper; synchronous.

M.vimdiff = {
  name = "vim.diff (xdiff)",
  run = function(old_lines, new_lines, bufnr, ns, done_cb)
    local old_str = table.concat(old_lines, "\n") .. "\n"
    local new_str = table.concat(new_lines, "\n") .. "\n"

    local indices = vim.diff(old_str, new_str, { result_type = "indices" })

    local hunks = {}
    for _, idx in ipairs(indices) do
      local os, oc, ns2, nc = idx[1], idx[2], idx[3], idx[4]
      local del = {}
      for i = os, os + oc - 1 do
        del[#del + 1] = old_lines[i]
      end
      local add = {}
      for i = ns2, ns2 + nc - 1 do
        add[#add + 1] = new_lines[i]
      end
      -- Match Myers convention: pure deletions use new_start - 1
      local new_start = (nc == 0) and (ns2 - 1) or ns2
      hunks[#hunks + 1] = {
        old_start = os,
        old_count = oc,
        new_start = new_start,
        new_count = nc,
        old_lines = del,
        new_lines = add,
      }
    end

    render.apply(bufnr, ns, hunks)
    done_cb()
  end,
}

M.all = { M.myers, M.git_diff, M.vimdiff }

return M
