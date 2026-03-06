local M = {}

function M._rgb_to_hsl(rgb)
  local r = bit.rshift(bit.band(rgb, 0xFF0000), 16) / 255
  local g = bit.rshift(bit.band(rgb, 0x00FF00), 8) / 255
  local b = bit.band(rgb, 0x0000FF) / 255

  local max = math.max(r, g, b)
  local min = math.min(r, g, b)
  local l = (max + min) / 2
  local h, s

  if max == min then
    h, s = 0, 0
  else
    local d = max - min
    s = l > 0.5 and d / (2 - max - min) or d / (max + min)
    if max == r then
      h = (g - b) / d + (g < b and 6 or 0)
    elseif max == g then
      h = (b - r) / d + 2
    else
      h = (r - g) / d + 4
    end
    h = h / 6
  end

  return h, s, l
end

local function hue_to_rgb(p, q, t)
  if t < 0 then t = t + 1 end
  if t > 1 then t = t - 1 end
  if t < 1 / 6 then return p + (q - p) * 6 * t end
  if t < 1 / 2 then return q end
  if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
  return p
end

function M._hsl_to_rgb(h, s, l)
  local r, g, b
  if s == 0 then
    r, g, b = l, l, l
  else
    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q
    r = hue_to_rgb(p, q, h + 1 / 3)
    g = hue_to_rgb(p, q, h)
    b = hue_to_rgb(p, q, h - 1 / 3)
  end
  local ri = math.floor(r * 255 + 0.5)
  local gi = math.floor(g * 255 + 0.5)
  local bi = math.floor(b * 255 + 0.5)
  return ri * 65536 + gi * 256 + bi
end

-- Shift lightness by `l_delta` toward whichever direction creates more contrast:
-- darken if the color is already bright (l >= 0.5), lighten if it is dark.
-- Also boost saturation by `s_delta`. Both parameters are additive, so the
-- output always differs from the input regardless of the base color's values.
function M._boost_color(rgb, l_delta, s_delta)
  l_delta = l_delta or 0.22
  s_delta = s_delta or 0.20
  local h, s, l = M._rgb_to_hsl(rgb)
  s = math.min(1, s + s_delta)
  if l < 0.5 then
    l = math.min(1, l + l_delta)
  else
    l = math.max(0, l - l_delta)
  end
  return M._hsl_to_rgb(h, s, l)
end

-- Returns 0x000000 (black) or 0xFFFFFF (white), whichever contrasts better
-- with the given background color.
function M._contrast_fg(rgb)
  local _, _, l = M._rgb_to_hsl(rgb)
  return l >= 0.45 and 0x000000 or 0xFFFFFF
end

function M.define()
  local add_hl = vim.api.nvim_get_hl(0, { name = "DiffAdd", link = false })
  local del_hl = vim.api.nvim_get_hl(0, { name = "DiffDelete", link = false })

  local add_bg = add_hl.bg or 0x2E4B2E
  local del_bg = del_hl.bg or 0x4B2E2E
  local word_add_bg = M._boost_color(add_bg, 0.08, 0.05)
  local word_del_bg = M._boost_color(del_bg, 0.12, 0.15)

  vim.api.nvim_set_hl(0, "InlineDiffAdd", { bg = add_bg, fg = M._contrast_fg(add_bg) })
  vim.api.nvim_set_hl(0, "InlineDiffDelete", { bg = del_bg, fg = M._contrast_fg(del_bg) })
  vim.api.nvim_set_hl(0, "InlineDiffWordAdd", { bg = word_add_bg, fg = M._contrast_fg(word_add_bg) })
  vim.api.nvim_set_hl(0, "InlineDiffWordDel", { bg = word_del_bg, fg = M._contrast_fg(word_del_bg), strikethrough = true })
end

function M.setup_autocmd()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("InlineDiffHighlight", {}),
    callback = function()
      M.define()
    end,
  })
end

return M
