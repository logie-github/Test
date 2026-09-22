package.path = "./?.lua;" .. package.path
local CardPalette = require("src.tcg.states.CardPalette")

local checks, failures = 0, 0
local function check(label, got, want, tol)
  checks = checks + 1
  tol = tol or 1e-6
  if math.abs(got - want) > tol then
    failures = failures + 1
    print(("FAIL  %s: got %s want %s"):format(label, tostring(got), tostring(want)))
  end
end

-- Known GBC BGR555 words (rgbgfx/hardware standard), low byte first:
-- pure red 0x001F, pure green 0x03E0, pure blue 0x7C00, white 0x7FFF, black 0.
local palette = CardPalette.decode({
  0x1F, 0x00, -- color 1: pure red
  0xE0, 0x03, -- color 2: pure green
  0x00, 0x7C, -- color 3: pure blue
  0xFF, 0x7F, -- color 4: white
})

check("red.r", palette[1][1], 1.0)
check("red.g", palette[1][2], 0.0)
check("red.b", palette[1][3], 0.0)

check("green.r", palette[2][1], 0.0)
check("green.g", palette[2][2], 1.0)
check("green.b", palette[2][3], 0.0)

check("blue.r", palette[3][1], 0.0)
check("blue.g", palette[3][2], 0.0)
check("blue.b", palette[3][3], 1.0)

check("white.r", palette[4][1], 1.0)
check("white.g", palette[4][2], 1.0)
check("white.b", palette[4][3], 1.0)

-- A fake ImageData: a 2x2 grid seeded with decode2bpp's four exact shade
-- levels (lightest to darkest), one per pixel, all fully opaque. colorize
-- should remap each to the matching decoded palette color by shade order.
local FakeImageData = {}
FakeImageData.__index = FakeImageData

function FakeImageData.new(pixels, w, h)
  return setmetatable({ pixels = pixels, w = w, h = h }, FakeImageData)
end

function FakeImageData:getDimensions() return self.w, self.h end

function FakeImageData:getPixel(x, y)
  local p = self.pixels[y * self.w + x + 1]
  return p[1], p[2], p[3], p[4]
end

function FakeImageData:setPixel(x, y, r, g, b, a)
  self.pixels[y * self.w + x + 1] = { r, g, b, a }
end

local shadePalette = CardPalette.decode({
  0x1F, 0x00, -- shade index 1 (lightest) -> red
  0xE0, 0x03, -- shade index 2 -> green
  0x00, 0x7C, -- shade index 3 -> blue
  0x00, 0x00, -- shade index 4 (darkest) -> black
})

local img = FakeImageData.new({
  { 1, 1, 1, 1 },          -- shade 0 (lightest)
  { 2 / 3, 2 / 3, 2 / 3, 1 }, -- shade 1
  { 1 / 3, 1 / 3, 1 / 3, 1 }, -- shade 2
  { 0, 0, 0, 0 },          -- shade 3 (darkest), but transparent -- must stay untouched
}, 2, 2)

CardPalette.colorize(img, shadePalette)

local r, g, b, a = img:getPixel(0, 0)
check("shade0.r", r, 1.0); check("shade0.g", g, 0.0); check("shade0.b", b, 0.0); check("shade0.a", a, 1.0)

r, g, b, a = img:getPixel(1, 0)
check("shade1.r", r, 0.0); check("shade1.g", g, 1.0); check("shade1.b", b, 0.0); check("shade1.a", a, 1.0)

r, g, b, a = img:getPixel(0, 1)
check("shade2.r", r, 0.0); check("shade2.g", g, 0.0); check("shade2.b", b, 1.0); check("shade2.a", a, 1.0)

-- transparent pixel must be left alone (not recolored to black)
r, g, b, a = img:getPixel(1, 1)
check("transparent.a", a, 0.0)
check("transparent.r", r, 0.0)

checks = checks + 1
if failures == 0 then
  print(("all card palette cases passed (%d checks)"):format(checks))
else
  print(("FAIL  %d/%d card palette checks failed"):format(failures, checks))
  os.exit(1)
end
