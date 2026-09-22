-- Applies a card's embedded GBC palette to the grayscale ImageData that
-- src/tcg/import/ImageWriter.decode2bpp produces. decode2bpp only knows the
-- raw 2-bit tile format (4 shade indices, drawn as gray so it works for any
-- kind of Game Boy tile data); it never reads the color bytes RomExtractor
-- copies alongside each card's tiles (RomExtractor:extractCardGraphic's
-- `palette` field: PAL_SIZE=8 raw bytes, PAL_COLORS=4 colors of 2 bytes
-- each). This module reverses that gap for the one case that needs the
-- real color: card art on the duel screen.
--
-- Color format is GBC's standard packed BGR555 word, little-endian:
--   byte0 | byte1<<8 = r5 | g5<<5 | b5<<10  (5 bits per channel)
-- and 5-to-8-bit channel expansion is (v5<<3)|(v5>>2), matching rgbgfx's
-- own Rgba::fromCGBColor (src/gfx/rgba.cpp in gbdev/rgbds) with its default,
-- non-"color curve" behavior -- the same rgbgfx invocation
-- (--colors embedded --auto-palette, Makefile's card gfx rule) produced
-- these exact bytes, so this is the matching inverse, not a guess.

local CardPalette = {}

-- decode2bpp's SHADES table, in shade-index order (0=lightest..3=darkest):
-- {1,1,1,1}, {2/3,2/3,2/3,1}, {1/3,1/3,1/3,1}, {0,0,0,1}. rgbgfx's
-- --auto-palette sorts a tile's colors by the same lightest-to-darkest
-- order, so palette color N corresponds to shade index N here.
local SHADE_LEVELS = { 1, 2 / 3, 1 / 3, 0 }

local function shadeIndexFromGray(r)
  local bestIndex, bestDist = 1, math.huge
  for i, level in ipairs(SHADE_LEVELS) do
    local dist = math.abs(r - level)
    if dist < bestDist then bestDist, bestIndex = dist, i end
  end
  return bestIndex
end

local function expand5to8(v5)
  return ((v5 * 8) + math.floor(v5 / 4)) / 255
end

-- paletteBytes: the 1-indexed array RomExtractor's copyBytes returns (8
-- bytes: 4 colors, low byte then high byte each). Returns 4 {r,g,b,a}
-- tables in 0..1, indexed 1..4 to match shadeIndexFromGray.
function CardPalette.decode(paletteBytes)
  local colors = {}
  for i = 0, 3 do
    local lo = assert(paletteBytes[i * 2 + 1], "short card palette")
    local hi = assert(paletteBytes[i * 2 + 2], "short card palette")
    local word = lo + hi * 256
    local r5 = word % 32
    local g5 = math.floor(word / 32) % 32
    local b5 = math.floor(word / 1024) % 32
    colors[i + 1] = { expand5to8(r5), expand5to8(g5), expand5to8(b5), 1 }
  end
  return colors
end

-- Mutates imageData in place, remapping each opaque pixel's shade to the
-- decoded color at the same index. Returns imageData for chaining.
function CardPalette.colorize(imageData, colors)
  local width, height = imageData:getDimensions()
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local r, g, b, a = imageData:getPixel(x, y)
      if a > 0 then
        local color = colors[shadeIndexFromGray(r)]
        imageData:setPixel(x, y, color[1], color[2], color[3], a)
      end
    end
  end
  return imageData
end

return CardPalette
