local M = {}

M._root_cache = {}

-- Prevents async handles from being GC'd before the thread callback fires.
local _pending = {} -- luacheck: ignore
local _pending_id = 0 -- luacheck: ignore

function M.get_ref_content(filepath, ref, callback)
  local dir = vim.fn.fnamemodify(filepath, ":h")
  local cached_root = M._root_cache[dir]

  local function fetch_content(root)
    local relpath = filepath:sub(#root + 2) -- skip root + "/"

    local function deliver(stdout)
      local lines = vim.split(stdout, "\n", { plain = true })
      -- git show output ends with a newline, producing a trailing empty string
      if #lines > 0 and lines[#lines] == "" then
        table.remove(lines)
      end
      callback(lines)
    end

    local function on_fail(err)
      callback(nil, "git show failed: " .. (err or ""))
    end

    local git_ref = ref == "staged" and ":0" or ref

    vim.system({ "git", "show", git_ref .. ":" .. relpath }, { text = true, cwd = root }, function(obj)
      if obj.code == 0 then
        vim.schedule(function() deliver(obj.stdout) end)
        return
      end
      if ref ~= "staged" then
        vim.schedule(function() on_fail(obj.stderr) end)
        return
      end
      -- Nothing staged; fall back to HEAD
      vim.system({ "git", "show", "HEAD:" .. relpath }, { text = true, cwd = root }, function(obj2)
        vim.schedule(function()
          if obj2.code ~= 0 then
            on_fail(obj2.stderr)
            return
          end
          deliver(obj2.stdout)
        end)
      end)
    end)
  end

  if cached_root then
    fetch_content(cached_root)
    return
  end

  vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true, cwd = dir }, function(obj)
    if obj.code ~= 0 then
      vim.schedule(function() callback(nil, "not a git repo") end)
      return
    end
    local root = vim.trim(obj.stdout)
    M._root_cache[dir] = root
    fetch_content(root)
  end)
end

function M._diff_lines(old_lines, new_lines)
  local m, n = #old_lines, #new_lines
  local max = math.max

  -- Strip common prefix and suffix to reduce LCS work
  local prefix = 0
  while prefix < m and prefix < n and old_lines[prefix + 1] == new_lines[prefix + 1] do
    prefix = prefix + 1
  end
  local suffix = 0
  while suffix < (m - prefix) and suffix < (n - prefix) and old_lines[m - suffix] == new_lines[n - suffix] do
    suffix = suffix + 1
  end

  local om = m - prefix - suffix
  local nm = n - prefix - suffix

  if om == 0 and nm == 0 then
    return {}
  end

  -- Build LCS dp table for the trimmed middle section
  -- Use 1-indexed sub-arrays offset by prefix
  -- Only boundary entries need pre-initialisation; the inner loop writes
  -- every interior cell before it is read.
  local dp = { [0] = {} }
  for j = 0, nm do dp[0][j] = 0 end
  for i = 1, om do dp[i] = { [0] = 0 } end
  for i = 1, om do
    local dp_i, dp_im1 = dp[i], dp[i - 1]
    local val = old_lines[prefix + i]
    for j = 1, nm do
      if val == new_lines[prefix + j] then
        dp_i[j] = dp_im1[j - 1] + 1
      else
        dp_i[j] = max(dp_im1[j], dp_i[j - 1])
      end
    end
  end

  -- Backtrack to find which lines are matched (equal)
  local old_matched = {}
  local new_matched = {}
  local i, j = om, nm
  while i > 0 and j > 0 do
    if old_lines[prefix + i] == new_lines[prefix + j] then
      old_matched[prefix + i] = true
      new_matched[prefix + j] = true
      i = i - 1
      j = j - 1
    elseif dp[i - 1][j] > dp[i][j - 1] then
      i = i - 1
    else
      j = j - 1
    end
  end

  -- Mark prefix/suffix lines as matched
  for k = 1, prefix do
    old_matched[k] = true
    new_matched[k] = true
  end
  for k = 0, suffix - 1 do
    old_matched[m - k] = true
    new_matched[n - k] = true
  end

  -- Walk both sequences in parallel and extract contiguous change blocks
  local hunks = {}
  local oi, ni = 1, 1
  while oi <= m or ni <= n do
    -- Skip matched lines (advance both pointers in lockstep for equal lines)
    if oi <= m and ni <= n and old_matched[oi] and new_matched[ni] and old_lines[oi] == new_lines[ni] then
      oi = oi + 1
      ni = ni + 1
    else
      -- Collect a contiguous block of changes
      local old_start = oi
      local new_start = ni
      local del_lines = {}
      local add_lines = {}

      -- Gather unmatched old lines (deletions)
      while oi <= m and not old_matched[oi] do
        del_lines[#del_lines + 1] = old_lines[oi]
        oi = oi + 1
      end
      -- Gather unmatched new lines (additions)
      while ni <= n and not new_matched[ni] do
        add_lines[#add_lines + 1] = new_lines[ni]
        ni = ni + 1
      end

      if #del_lines > 0 or #add_lines > 0 then
        hunks[#hunks + 1] = {
          old_start = old_start,
          old_count = #del_lines,
          new_start = #add_lines > 0 and new_start or (new_start - 1),
          new_count = #add_lines,
          old_lines = del_lines,
          new_lines = add_lines,
        }
      end
    end
  end

  return hunks
end

function M.compute_hunks(old_lines, new_lines, callback)
  if not vim.uv.new_thread then
    callback(M._diff_lines(old_lines, new_lines))
    return
  end

  local old_s = table.concat(old_lines, "\n")
  local new_s = table.concat(new_lines, "\n")
  local pkg_path = package.path

  _pending_id = _pending_id + 1
  local id = _pending_id
  -- Close the handle on the main thread (closing from the thread suppresses delivery).
  local async
  async = vim.uv.new_async(vim.schedule_wrap(function(result)
    async:close()
    _pending[id] = nil
    local ok, hunks = pcall(vim.json.decode, result)
    callback(ok and hunks or nil, not ok and result or nil)
  end))
  _pending[id] = async -- prevent GC before the thread fires

  vim.uv.new_thread(function(pkg, old, new, handle)
    package.path = pkg
    local ok, worker = pcall(require, "inline-diff._worker")
    if not ok then
      handle:send("[]")
      return
    end
    local ok2, result = pcall(worker.run, old, new)
    handle:send(ok2 and result or "[]")
  end, pkg_path, old_s, new_s, async)
end

local function tokenize(str)
  local tokens = {}
  local i = 1
  local len = #str
  while i <= len do
    local s, e = str:find("^[%w_]+", i)
    if s then
      tokens[#tokens + 1] = str:sub(s, e)
      i = e + 1
    else
      tokens[#tokens + 1] = str:sub(i, i)
      i = i + 1
    end
  end
  return tokens
end

function M._lcs(a, b)
  local m, n = #a, #b
  local max = math.max
  -- dp[i][j] = length of LCS of a[1..i] and b[1..j]
  local dp = { [0] = {} }
  for j = 0, n do dp[0][j] = 0 end
  for i = 1, m do dp[i] = { [0] = 0 } end
  for i = 1, m do
    local dp_i, dp_im1, a_i = dp[i], dp[i - 1], a[i]
    for j = 1, n do
      if a_i == b[j] then
        dp_i[j] = dp_im1[j - 1] + 1
      else
        dp_i[j] = max(dp_im1[j], dp_i[j - 1])
      end
    end
  end

  -- Backtrack to find matched indices
  local matches_a = {}
  local matches_b = {}
  local i, j = m, n
  while i > 0 and j > 0 do
    if a[i] == b[j] then
      matches_a[i] = true
      matches_b[j] = true
      i = i - 1
      j = j - 1
    elseif dp[i - 1][j] > dp[i][j - 1] then
      i = i - 1
    else
      j = j - 1
    end
  end

  return matches_a, matches_b
end

function M._word_diff(old_line, new_line)
  local old_tokens = tokenize(old_line)
  local new_tokens = tokenize(new_line)

  -- Performance guard
  if #old_tokens > 200 or #new_tokens > 200 then
    return {
      { text = old_line, type = "del", byte_start = 1, byte_end = #old_line },
    }, {
      { text = new_line, type = "add", byte_start = 1, byte_end = #new_line },
    }
  end

  local matches_a, matches_b = M._lcs(old_tokens, new_tokens)

  local function build_segments(tokens, matches, change_type)
    local segments = {}
    local pos = 1
    for idx, token in ipairs(tokens) do
      local t = matches[idx] and "equal" or change_type
      local byte_start = pos
      local byte_end = pos + #token - 1
      -- Merge with previous segment if same type
      if #segments > 0 and segments[#segments].type == t then
        local prev = segments[#segments]
        prev.text = prev.text .. token
        prev.byte_end = byte_end
      else
        segments[#segments + 1] = {
          text = token,
          type = t,
          byte_start = byte_start,
          byte_end = byte_end,
        }
      end
      pos = byte_end + 1
    end
    return segments
  end

  return build_segments(old_tokens, matches_a, "del"), build_segments(new_tokens, matches_b, "add")
end

return M
