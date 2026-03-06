local M = {}

M._root_cache = {}

function M.get_ref_content(filepath, ref, callback)
  local dir = vim.fn.fnamemodify(filepath, ":h")
  local cached_root = M._root_cache[dir]

  local function fetch_content(root)
    local relpath = filepath:sub(#root + 2) -- skip root + "/"
    vim.system({ "git", "show", ref .. ":" .. relpath }, { text = true, cwd = root }, function(obj2)
      vim.schedule(function()
        if obj2.code ~= 0 then
          callback(nil, "git show failed: " .. (obj2.stderr or ""))
          return
        end
        local lines = vim.split(obj2.stdout, "\n", { plain = true })
        -- git show output ends with a newline, producing a trailing empty string
        if #lines > 0 and lines[#lines] == "" then
          table.remove(lines)
        end
        callback(lines)
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

  -- Hash lines for O(1) comparison
  local old_h, new_h = {}, {}
  for i = 1, m do old_h[i] = old_lines[i] end
  for i = 1, n do new_h[i] = new_lines[i] end

  -- Strip common prefix and suffix to reduce LCS work
  local prefix = 0
  while prefix < m and prefix < n and old_h[prefix + 1] == new_h[prefix + 1] do
    prefix = prefix + 1
  end
  local suffix = 0
  while suffix < (m - prefix) and suffix < (n - prefix) and old_h[m - suffix] == new_h[n - suffix] do
    suffix = suffix + 1
  end

  local om = m - prefix - suffix
  local nm = n - prefix - suffix

  if om == 0 and nm == 0 then
    return {}
  end

  -- Build LCS dp table for the trimmed middle section
  -- Use 1-indexed sub-arrays offset by prefix
  local dp = {}
  for i = 0, om do
    dp[i] = {}
    for j = 0, nm do
      dp[i][j] = 0
    end
  end
  for i = 1, om do
    local dp_i, dp_im1 = dp[i], dp[i - 1]
    local val = old_h[prefix + i]
    for j = 1, nm do
      if val == new_h[prefix + j] then
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
    if old_h[prefix + i] == new_h[prefix + j] then
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
    if oi <= m and ni <= n and old_matched[oi] and new_matched[ni] and old_h[oi] == new_h[ni] then
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

function M._compute_hunks_git(old_lines, new_lines, callback)
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
        if obj.code == 0 then
          callback({})
        elseif obj.code == 1 then
          callback(M._parse_diff(obj.stdout))
        else
          callback(nil, "git diff failed: " .. (obj.stderr or ""))
        end
      end)
    end
  )
end

function M.compute_hunks(old_lines, new_lines, callback)
  local hunks = M._diff_lines(old_lines, new_lines)
  vim.schedule(function()
    callback(hunks)
  end)
end

function M._parse_diff(raw)
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
      -- Handle the special case where count is explicitly "0"
      if oc_str == "0" then current.old_count = 0 end
      if nc_str == "0" then current.new_count = 0 end
    elseif current then
      local prefix = line:sub(1, 1)
      if prefix == "-" then
        current.old_lines[#current.old_lines + 1] = line:sub(2)
      elseif prefix == "+" then
        current.new_lines[#current.new_lines + 1] = line:sub(2)
      -- skip "\ No newline at end of file" and other \ lines
      end
    end
  end

  if current then
    hunks[#hunks + 1] = current
  end

  return hunks
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
  local dp = {}
  for i = 0, m do
    dp[i] = {}
    for j = 0, n do
      dp[i][j] = 0
    end
  end
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
