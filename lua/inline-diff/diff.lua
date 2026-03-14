local M = {}

M._root_cache = {}

-- Prevents async handles from being GC'd before the thread callback fires.
local _pending = {} -- luacheck: ignore
local _pending_id = 0 -- luacheck: ignore

function M.get_ref_content(filepath, ref, callback)
  local dir = vim.fn.fnamemodify(filepath, ":h")
  local cached_root = M._root_cache[dir]

  local function fetch_content(root)
    local relpath = filepath:sub(#root + 2):gsub("\\", "/") -- skip root + sep; normalize to forward slashes for git

    local function deliver(stdout)
      local lines = vim.split(stdout, "\r?\n")
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

-- Myers shortest-edit-script algorithm.
-- Returns old_matched[i] / new_matched[j] boolean tables for the full arrays,
-- with prefix and suffix lines already marked matched on entry.
--
-- old_lines  full old sequence (lines or tokens)
-- new_lines  full new sequence
-- prefix     number of equal elements at the start (already matched)
-- suffix     number of equal elements at the end   (already matched)
-- m          #old_lines
-- n          #new_lines
-- om         number of old elements in the middle  (m - prefix - suffix)
-- nm         number of new elements in the middle  (n - prefix - suffix)
function M._myers_matched(old_lines, new_lines, prefix, suffix, m, n, om, nm)
  local old_matched = {}
  local new_matched = {}

  for k = 1, prefix do
    old_matched[k] = true
    new_matched[k] = true
  end
  for k = 0, suffix - 1 do
    old_matched[m - k] = true
    new_matched[n - k] = true
  end

  if om == 0 or nm == 0 then
    return old_matched, new_matched
  end

  -- V[k] = furthest x reached on diagonal k = x - y.
  -- Lua tables support negative indices natively.
  local V = { [1] = 0 }
  local trace = {}

  for d = 0, om + nm do
    for k = -d, d, 2 do
      local x
      if k == -d or (k ~= d and (V[k - 1] or 0) < (V[k + 1] or 0)) then
        x = V[k + 1] or 0 -- move down (insertion)
      else
        x = (V[k - 1] or 0) + 1 -- move right (deletion)
      end
      local y = x - k
      while x < om and y < nm and old_lines[prefix + x + 1] == new_lines[prefix + y + 1] do
        x = x + 1
        y = y + 1
      end
      V[k] = x

      if x >= om and y >= nm then
        -- Backtrace: walk the stored V snapshots in reverse to mark matched lines.
        local cx, cy = om, nm
        for bd = d, 1, -1 do
          local Vp = trace[bd - 1]
          local kk = cx - cy
          local sx, _, px, py
          if kk == -bd or (kk ~= bd and (Vp[kk - 1] or 0) < (Vp[kk + 1] or 0)) then
            local vp = Vp[kk + 1] or 0 -- insertion: came from diagonal kk+1
            sx, _ = vp, vp - kk
            px, py = vp, vp - kk - 1
          else
            local vp = Vp[kk - 1] or 0 -- deletion: came from diagonal kk-1
            sx, _ = vp + 1, vp - kk + 1
            px, py = vp, vp - kk + 1
          end
          while cx > sx do -- mark the snake (diagonal = matching lines)
            cx = cx - 1
            cy = cy - 1
            old_matched[prefix + cx + 1] = true
            new_matched[prefix + cy + 1] = true
          end
          cx, cy = px, py
        end
        while cx > 0 do -- remaining snake at d=0
          cx = cx - 1
          cy = cy - 1
          old_matched[prefix + cx + 1] = true
          new_matched[prefix + cy + 1] = true
        end
        return old_matched, new_matched
      end
    end
    local snap = {}
    for kk, vv in pairs(V) do snap[kk] = vv end
    trace[d] = snap
  end

  return old_matched, new_matched
end

function M._diff_lines(old_lines, new_lines)
  local m, n = #old_lines, #new_lines

  -- Strip common prefix and suffix to reduce Myers work
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

  local old_matched, new_matched = M._myers_matched(old_lines, new_lines, prefix, suffix, m, n, om, nm)

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
  -- For small inputs the thread round-trip (concat→spawn→decode→encode→decode)
  -- costs more than the diff itself; run synchronously instead.
  if not vim.uv.new_thread or #old_lines + #new_lines < 200 then
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
    if result:sub(1, 4) == "ERR:" then
      -- Thread failed to load the worker (e.g. package.path issue on Windows);
      -- fall back to computing the diff synchronously on the main thread.
      callback(M._diff_lines(old_lines, new_lines))
      return
    end
    local ok, hunks = pcall(vim.json.decode, result)
    callback(ok and hunks or nil, not ok and result or nil)
  end))
  _pending[id] = async -- prevent GC before the thread fires

  vim.uv.new_thread(function(pkg, old, new, handle)
    package.path = pkg
    local ok, worker = pcall(require, "inline-diff._worker")
    if not ok then
      handle:send("ERR:" .. tostring(worker))
      return
    end
    local ok2, result = pcall(worker.run, old, new)
    if not ok2 then
      handle:send("ERR:" .. tostring(result))
      return
    end
    handle:send(result)
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

  local m, n = #old_tokens, #new_tokens
  local prefix = 0
  while prefix < m and prefix < n and old_tokens[prefix + 1] == new_tokens[prefix + 1] do
    prefix = prefix + 1
  end
  local suffix = 0
  while suffix < (m - prefix) and suffix < (n - prefix) and old_tokens[m - suffix] == new_tokens[n - suffix] do
    suffix = suffix + 1
  end
  local matches_a, matches_b = M._myers_matched(old_tokens, new_tokens, prefix, suffix, m, n, m - prefix - suffix, n - prefix - suffix)

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
