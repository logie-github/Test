-- Development-only extraction/translation status state.
-- It contains no Pokemon TCG game behavior.

local TranslationIncomplete = {}
TranslationIncomplete.__index = TranslationIncomplete
TranslationIncomplete.isOpaque = true

function TranslationIncomplete.new(game, data)
  return setmetatable({ game = game, data = data or {} }, TranslationIncomplete)
end

function TranslationIncomplete:update()
  -- No invented game behavior. Input is intentionally ignored here.
end

function TranslationIncomplete:draw()
  local meta = self.data.meta or {}
  local extracted = meta.extracted or {}
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.print("POKEMON TCG", 8, 8)
  love.graphics.print("ROM DATA EXTRACTED", 8, 24)
  love.graphics.print(("CARDS %s"):format(tostring(extracted.cards or "?")), 8, 40)
  love.graphics.print(("DECKS %s"):format(tostring(extracted.decks or "?")), 8, 52)
  love.graphics.print(("TEXT  %s"):format(tostring(extracted.text or "?")), 8, 64)
  love.graphics.print(("RAM   %s"):format(tostring(extracted.memorySymbols or "?")), 8, 76)
  love.graphics.print("BEHAVIOR TRANSLATION PARTIAL", 8, 92)
  if meta.decompCommit then
    love.graphics.print("DECOMP " .. tostring(meta.decompCommit):sub(1, 12), 8, 108)
  end
  love.graphics.print("DEV MODE ONLY", 8, 124)
end

return TranslationIncomplete
