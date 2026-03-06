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

describe("_boost_color", function()
  it("boosts saturation and lightness", function()
    local input = 0x2E4B2E -- dark green
    local h_in, s_in, l_in = highlight._rgb_to_hsl(input)
    local boosted = highlight._boost_color(input)
    local h_out, s_out, l_out = highlight._rgb_to_hsl(boosted)

    -- Hue should stay the same (within tolerance)
    assert.is_true(math.abs(h_out - h_in) < 0.02, "hue changed too much")
    -- Saturation should increase
    assert.is_true(s_out >= s_in, "saturation should increase or stay same")
    -- Lightness should increase
    assert.is_true(l_out >= l_in, "lightness should increase or stay same")
  end)

  it("caps lightness at 0.65", function()
    -- A very light color
    local input = 0xDDDDDD
    local boosted = highlight._boost_color(input)
    local _, _, l = highlight._rgb_to_hsl(boosted)
    assert.is_true(l <= 0.66, "lightness should be capped near 0.65")
  end)

  it("caps saturation at 1.0", function()
    -- A highly saturated color
    local input = 0xFF0000
    local boosted = highlight._boost_color(input)
    local _, s, _ = highlight._rgb_to_hsl(boosted)
    assert.is_true(s <= 1.01, "saturation should not exceed 1.0")
  end)
end)
