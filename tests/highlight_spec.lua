local highlight = require("inline-diff.highlight")

describe("_rgb_to_hsl / _hsl_to_rgb round-trip", function()
  local function round_trip(rgb)
    local h, s, l = highlight._rgb_to_hsl(rgb)
    return highlight._hsl_to_rgb(h, s, l)
  end

  it("round-trips pure red", function()
    assert.are.equal(0xFF0000, round_trip(0xFF0000))
  end)

  it("round-trips pure green", function()
    assert.are.equal(0x00FF00, round_trip(0x00FF00))
  end)

  it("round-trips pure blue", function()
    assert.are.equal(0x0000FF, round_trip(0x0000FF))
  end)

  it("round-trips white", function()
    assert.are.equal(0xFFFFFF, round_trip(0xFFFFFF))
  end)

  it("round-trips black", function()
    assert.are.equal(0x000000, round_trip(0x000000))
  end)

  it("round-trips a mid-tone color", function()
    -- Allow +-1 per channel due to rounding
    local original = 0x2E4B2E
    local result = round_trip(original)
    local diff = math.abs(result - original)
    assert.is_true(diff <= 0x010101, "round-trip drift too large: " .. string.format("0x%06X vs 0x%06X", original, result))
  end)
end)

describe("_contrast_fg", function()
  it("returns white for dark backgrounds", function()
    assert.are.equal(0xFFFFFF, highlight._contrast_fg(0x1E3A1E)) -- dark green
    assert.are.equal(0xFFFFFF, highlight._contrast_fg(0x000000)) -- black
    assert.are.equal(0xFFFFFF, highlight._contrast_fg(0x3C1C1C)) -- dark red
  end)

  it("returns black for bright backgrounds", function()
    assert.are.equal(0x000000, highlight._contrast_fg(0xFFFFFF)) -- white
    assert.are.equal(0x000000, highlight._contrast_fg(0xDDDDDD)) -- light gray
    assert.are.equal(0x000000, highlight._contrast_fg(0x90EE90)) -- light green
  end)
end)

describe("_boost_color", function()
  it("lightens a dark color and boosts saturation", function()
    local input = 0x2E4B2E -- dark green (l < 0.5)
    local h_in, s_in, l_in = highlight._rgb_to_hsl(input)
    local boosted = highlight._boost_color(input)
    local h_out, s_out, l_out = highlight._rgb_to_hsl(boosted)

    assert.is_true(math.abs(h_out - h_in) < 0.02, "hue changed too much")
    assert.is_true(s_out >= s_in, "saturation should increase")
    assert.is_true(l_out > l_in, "dark color should be lightened")
  end)

  it("darkens a bright color and boosts saturation", function()
    local input = 0xDDDDDD -- very light gray (l > 0.5)
    local h_in, s_in, l_in = highlight._rgb_to_hsl(input)
    local boosted = highlight._boost_color(input)
    local h_out, s_out, l_out = highlight._rgb_to_hsl(boosted)

    assert.is_true(math.abs(h_out - h_in) < 0.02, "hue changed too much")
    assert.is_true(l_out < l_in, "bright color should be darkened")
  end)

  it("always produces a color different from the input", function()
    local inputs = { 0x2E4B2E, 0x4B2E2E, 0xDDDDDD, 0x888888, 0xFF0000 }
    for _, input in ipairs(inputs) do
      local boosted = highlight._boost_color(input)
      assert.are_not.equal(input, boosted, string.format("color 0x%06X was unchanged", input))
    end
  end)

  it("caps saturation at 1.0", function()
    local input = 0xFF0000 -- fully saturated red
    local boosted = highlight._boost_color(input)
    local _, s, _ = highlight._rgb_to_hsl(boosted)
    assert.is_true(s <= 1.01, "saturation should not exceed 1.0")
  end)

  it("output lightness differs from input by roughly l_delta", function()
    local input = 0x2E4B2E -- dark green
    local _, _, l_in = highlight._rgb_to_hsl(input)
    local boosted = highlight._boost_color(input, 0.22, 0.20)
    local _, _, l_out = highlight._rgb_to_hsl(boosted)
    assert.is_true(math.abs((l_out - l_in) - 0.22) < 0.02, "lightness delta should be ~0.22")
  end)
end)
