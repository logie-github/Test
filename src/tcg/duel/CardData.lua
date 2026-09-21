-- Native card-data accessors translated from pret/poketcg
-- src/home/card_data.asm and the deck-index lookup in src/home/duel.asm.
-- Card bytes themselves were extracted from the validated ROM.

local bit = require("bit")

local CardData = {}
CardData.__index = CardData

local function cloneBytes(values)
  local out = {}
  for i, value in ipairs(values) do out[i] = value end
  return out
end

function CardData.new(memory, duelVars, data)
  assert(data and data.cards and data.constants)
  return setmetatable({
    memory = assert(memory),
    duelVars = assert(duelVars),
    cards = data.cards,
    core = assert(data.core),
    c = data.constants,
  }, CardData)
end

function CardData:get(cardId)
  if type(cardId) ~= "number" then return nil end
  return self.cards.byId[cardId]
end

-- GetCardPointer's useful native result: nil for an out-of-range/non-card ID.
function CardData:getCard(cardId)
  return self:get(cardId)
end

function CardData:getType(cardId)
  local row = self:get(cardId)
  return row and row.type or nil
end

function CardData:getName(cardId)
  local row = self:get(cardId)
  return row and row.nameTextId or nil
end

function CardData:getTypeRarityAndSet(cardId)
  local row = self:get(cardId)
  if not row then return nil end
  return row.type, row.rarity, row.set
end

-- LoadCardDataToHL_FromCardID always copies PKMN_CARD_DATA_LENGTH bytes,
-- including bytes following short Energy/Trainer records.
function CardData:bufferForCardID(cardId)
  local row = assert(self:get(cardId), "invalid TCG card id " .. tostring(cardId))
  assert(#row.bufferRaw == self.c.PKMN_CARD_DATA_LENGTH,
    "generated card buffer length differs from decomp")
  return cloneBytes(row.bufferRaw)
end

function CardData:loadBufferFromCardID(symbol, cardId)
  local address, bank = self.memory:address(symbol)
  assert(bank == 0, symbol .. " unexpectedly moved out of WRAM0")
  local raw = self:bufferForCardID(cardId)
  self.memory:writeBlock("wram", address, raw, bank)
  return raw
end

function CardData:loadBuffer1FromCardID(cardId)
  return self:loadBufferFromCardID("wLoadedCard1", cardId)
end

function CardData:loadBuffer2FromCardID(cardId)
  return self:loadBufferFromCardID("wLoadedCard2", cardId)
end

-- LoadCardDataToBuffer1_FromName:: scans card records in CardPointers order.
function CardData:loadBuffer1FromName(nameTextId)
  for cardId = 1, self.cards.count do
    local row = self.cards.byId[cardId]
    if row.nameTextId == nameTextId then
      self:loadBuffer1FromCardID(cardId)
      return cardId
    end
  end
  return nil
end

-- ConvertSpecialTrainerCardToPokemon:: from engine/duel/core.asm. The overwrite
-- bytes are extracted from the routine's local .trainer_to_pkmn_data symbol,
-- so text/effect pointers stay tied to the validated ROM/decomp build.
function CardData:convertSpecialTrainerCardToPokemon(bufferSymbol, deckIndex, cardId)
  local base, bank = self.memory:address(bufferSymbol)
  assert(bank == 0, bufferSymbol .. " unexpectedly moved out of WRAM0")
  if self.memory:read8("wram", base + self.c.CARD_DATA_TYPE, bank)
      ~= self.c.TYPE_TRAINER then
    return false
  end

  local location = self.duelVars:get(deckIndex)
  if bit.band(location, self.c.CARD_LOCATION_PLAY_AREA) == 0 then
    return false
  end
  if cardId ~= self.c.MYSTERIOUS_FOSSIL and cardId ~= self.c.CLEFAIRY_DOLL then
    return false
  end

  self.memory:write8("wram", base + self.c.CARD_DATA_TYPE,
    self.c.TYPE_PKMN_COLORLESS, bank)
  local template = self.core.specialTrainerTemplate
  assert(#template == self.c.CARD_DATA_AI_INFO - self.c.CARD_DATA_HP,
    "special trainer conversion template length changed")
  self.memory:writeBlock("wram", base + self.c.CARD_DATA_HP, template, bank)
  return true
end

-- LoadCardDataToBuffer{1,2}_FromDeckIndex::
function CardData:loadBufferFromDeckIndex(bufferSymbol, deckIndex)
  local cardId = self:getCardIDFromDeckIndex(deckIndex)
  self:loadBufferFromCardID(bufferSymbol, cardId)
  self:convertSpecialTrainerCardToPokemon(bufferSymbol, deckIndex, cardId)
  return cardId
end

function CardData:loadBuffer1FromDeckIndex(deckIndex)
  return self:loadBufferFromDeckIndex("wLoadedCard1", deckIndex)
end

function CardData:loadBuffer2FromDeckIndex(deckIndex)
  return self:loadBufferFromDeckIndex("wLoadedCard2", deckIndex)
end

-- IsLoadedCard1BasicPokemon.skip_mysterious_fossil_clefairy_doll::
function CardData:isLoadedCard1BasicPokemonSkipSpecial()
  local base, bank = self.memory:address("wLoadedCard1")
  assert(bank == 0, "wLoadedCard1 unexpectedly moved out of WRAM0")
  local cardType = self.memory:read8("wram", base + self.c.CARD_DATA_TYPE, bank)
  if cardType >= self.c.TYPE_ENERGY then return 0, true end
  local stage = self.memory:read8("wram", base + self.c.CARD_DATA_STAGE, bank)
  if stage ~= self.c.BASIC then return 0, true end
  return 1, false
end

-- IsLoadedCard1BasicPokemon:: counts the two Trainer cards that the original
-- explicitly treats as Basic at this entry point.
function CardData:isLoadedCard1BasicPokemon()
  local base, bank = self.memory:address("wLoadedCard1")
  local cardId = self.memory:read8("wram", base + self.c.CARD_DATA_ID, bank)
  if cardId == self.c.MYSTERIOUS_FOSSIL or cardId == self.c.CLEFAIRY_DOLL then
    return 1, false
  end
  return self:isLoadedCard1BasicPokemonSkipSpecial()
end


-- _GetCardIDFromDeckIndex:: chooses wPlayerDeck/wOpponentDeck from hWhoseTurn.
function CardData:getCardIDFromDeckIndex(deckIndex)
  local deckSymbol = self.duelVars:turn() == self.c.PLAYER_TURN
    and "wPlayerDeck" or "wOpponentDeck"
  local base, bank = self.memory:address(deckSymbol)
  assert(bank == 0, deckSymbol .. " unexpectedly moved out of WRAM0")
  return self.memory:read8("wram", base + (deckIndex % 0x100), bank)
end

-- Write-side counterpart of getCardIDFromDeckIndex, used only by Ditto's
-- Morph to permanently overwrite a deck slot's card identity in place
-- (the deck position itself is untouched; only what card that position
-- reports as changes for the rest of the duel).
function CardData:setCardIDForDeckIndex(deckIndex, cardId)
  local deckSymbol = self.duelVars:turn() == self.c.PLAYER_TURN
    and "wPlayerDeck" or "wOpponentDeck"
  local base, bank = self.memory:address(deckSymbol)
  assert(bank == 0, deckSymbol .. " unexpectedly moved out of WRAM0")
  self.memory:write8("wram", base + (deckIndex % 0x100), cardId, bank)
end

-- GetCardInDuelTempList_OnlyDeckIndex::
function CardData:getCardInDuelTempListOnlyDeckIndex(index)
  local base, bank = self.memory:address("wDuelTempList")
  local deckIndex = self.memory:read8("wram", base + index, bank)
  self.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
  return deckIndex
end

-- GetCardInDuelTempList:: additionally resolves the card ID.
function CardData:getCardInDuelTempList(index)
  local deckIndex = self:getCardInDuelTempListOnlyDeckIndex(index)
  return deckIndex, self:getCardIDFromDeckIndex(deckIndex)
end


return CardData
