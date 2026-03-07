-- Pure Lua module loaded inside a vim.uv thread — no vim API available here.
-- package.path must be set by the caller before require'ing this module.
local diff = require("inline-diff.diff")

local M = {}

local function decode_lines(s)
  if s == "" then return {} end
  local t = {}
  for line in (s .. "\n"):gmatch("([^\n]*)\n") do
    t[#t + 1] = line
  end
  return t
end

local function encode(v)
  local t = type(v)
  if t == "string" then
    return '"'
      .. v:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
      .. '"'
  elseif t == "number" then
    return tostring(v)
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "table" then
    if #v > 0 then
      local a = {}
      for _, x in ipairs(v) do
        a[#a + 1] = encode(x)
      end
      return "[" .. table.concat(a, ",") .. "]"
    else
      local a = {}
      for k, x in pairs(v) do
        a[#a + 1] = '"' .. k .. '":' .. encode(x)
      end
      return "{" .. table.concat(a, ",") .. "}"
    end
  end
  return "null"
end

function M.run(old_s, new_s)
  local hunks = diff._diff_lines(decode_lines(old_s), decode_lines(new_s))
  return encode(hunks)
end

return M
