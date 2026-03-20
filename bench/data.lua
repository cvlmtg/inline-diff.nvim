-- Synthetic test data generation for benchmarks.
-- All data is deterministic (seeded RNG).

local M = {}

math.randomseed(42)

local function make_line(n)
  return string.format("local var_%d = require('module_%d') -- comment line %d", n, n, n)
end

local function make_file(n)
  local lines = {}
  for i = 1, n do
    lines[i] = make_line(i)
  end
  return lines
end

-- Modify ~pct% of lines with a word substitution
local function apply_scattered_mods(lines, pct)
  local result = {}
  for i, line in ipairs(lines) do
    result[i] = line
  end
  local n = #lines
  local count = math.max(1, math.floor(n * pct / 100))
  local step = math.floor(n / count)
  for i = 0, count - 1 do
    local idx = 1 + (i * step)
    if idx <= n then
      -- substitute the line number to make it look different
      result[idx] = result[idx]:gsub("comment line %d+", "CHANGED line " .. idx)
    end
  end
  return result
end

-- Mixed edits: deletions, insertions, modifications scattered throughout
local function apply_mixed(lines)
  local result = {}
  local i = 1
  local n = #lines
  local counter = 0
  while i <= n do
    counter = counter + 1
    local r = (counter % 7)
    if r == 0 and i <= n - 2 then
      -- delete 2 lines
      i = i + 2
    elseif r == 1 then
      -- insert 2 new lines
      result[#result + 1] = "-- inserted line A at pos " .. i
      result[#result + 1] = "-- inserted line B at pos " .. i
      result[#result + 1] = lines[i]
      i = i + 1
    elseif r == 2 then
      -- modify line
      result[#result + 1] = lines[i]:gsub("var_%d+", "VAR_MOD_" .. i)
      i = i + 1
    else
      result[#result + 1] = lines[i]
      i = i + 1
    end
  end
  return result
end

function M.generate()
  local datasets = {}

  -- Small files: sync path (<500 total lines)
  local small_old = make_file(100)
  datasets[#datasets + 1] = {
    label = "small/scattered (100+110, sync)",
    old_lines = small_old,
    new_lines = apply_scattered_mods(small_old, 10),
  }

  local medium_old = make_file(200)
  datasets[#datasets + 1] = {
    label = "small/mixed   (200+~200, sync)",
    old_lines = medium_old,
    new_lines = apply_mixed(medium_old),
  }

  -- Large files: async path (>=500 total lines)
  local large_old = make_file(1000)
  datasets[#datasets + 1] = {
    label = "large/scattered (1000+1050, async)",
    old_lines = large_old,
    new_lines = apply_scattered_mods(large_old, 10),
  }

  local xlarge_old = make_file(2000)
  datasets[#datasets + 1] = {
    label = "large/mixed   (2000+~2000, async)",
    old_lines = xlarge_old,
    new_lines = apply_mixed(xlarge_old),
  }

  return datasets
end

return M
