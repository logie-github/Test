-- First native duel primitives translated directly from
-- pret/poketcg src/home/duel.asm.  These routines intentionally operate on
-- the original RAM layout and deck indexes rather than a redesigned Lua model.

local bit = require("bit")

local DuelOps = {}
DuelOps.__index = DuelOps

local function u8(v) return bit.band(v, 0xff) end

function DuelOps.new(memory, duelVars, rng, constants, decks, cardData)
  return setmetatable({
    memory = assert(memory), duelVars = assert(duelVars),
    rng = assert(rng), c = assert(constants), decks = assert(decks),
    cardData = assert(cardData),
  }, DuelOps)
end

function DuelOps:_addr(offset)
  return self.duelVars:address(offset)
end

function DuelOps:_read(offset)
  return self.memory:read8("wram", self:_addr(offset), 0)
end

function DuelOps:_write(offset, value)
  self.memory:write8("wram", self:_addr(offset), value, 0)
end

-- CopyDeckData:: expands the decomp's quantity/card-id list into the current
-- duelist's 60-byte deck buffer, stores the two-byte deck-name text ID, and
-- returns carry=true when byte 59 remained zero (the source's validity test).
function DuelOps:copyDeckData(deckId)
  local row = assert(self.decks.byId[deckId], "invalid TCG deck id " .. tostring(deckId))
  local deckSymbol = self.duelVars:turn() == self.c.PLAYER_TURN
    and "wPlayerDeck" or "wOpponentDeck"
  local base, bank = self.memory:address(deckSymbol)
  assert(bank == 0, deckSymbol .. " unexpectedly moved out of WRAM0")

  self.memory:write8("wram", base + self.c.DECK_SIZE - 1, 0, bank)
  local cursor = base
  for _, entry in ipairs(row.entries) do
    for _ = 1, entry.quantity do
      self.memory:write8("wram", cursor, entry.cardId, bank)
      cursor = cursor + 1
    end
  end

  local nameAddress, nameBank = self.memory:address("wDeckName")
  assert(nameBank == 0, "wDeckName unexpectedly moved out of WRAM0")
  self.memory:write8("wram", nameAddress, row.nameWord % 0x100, nameBank)
  self.memory:write8("wram", nameAddress + 1, math.floor(row.nameWord / 0x100), nameBank)

  return self.memory:read8("wram", base + self.c.DECK_SIZE - 1, bank) == 0
end

-- CountPrizes:: popcount of DUELVARS_PRIZES.
function DuelOps:countPrizes()
  local value = self:_read(self.c.DUELVARS_PRIZES)
  local count = 0
  for _ = 1, 8 do
    count = count + bit.band(value, 1)
    value = bit.rshift(value, 1)
  end
  return count
end

-- ShuffleDeck:: only the still-drawable suffix participates.
function DuelOps:shuffleDeck()
  local gone = self:_read(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)
  local count = self.c.DECK_SIZE - gone
  local start = self:_addr(self.c.DUELVARS_DECK_CARDS + gone)
  self.rng:shuffleCards(start, count)
end

-- DrawCardFromDeck:: returns deckIndex, carry.
function DuelOps:drawCardFromDeck()
  local gone = self:_read(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)
  -- On the carry path the assembly returns with A still holding the
  -- not-in-deck count, so preserve that value as the first result.
  if gone >= self.c.DECK_SIZE then return gone, true end
  gone = gone + 1
  self:_write(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK, gone)
  local deckIndex = self:_read(self.c.DUELVARS_DECK_CARDS + gone - 1)
  self:_write(deckIndex, self.c.CARD_LOCATION_JUST_DRAWN)
  return deckIndex, false
end

-- ReturnCardToDeck:: expects a deck index that had already left the deck.
function DuelOps:returnCardToDeck(deckIndex)
  local gone = u8(self:_read(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK) - 1)
  self:_write(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK, gone)
  self:_write(self.c.DUELVARS_DECK_CARDS + gone, deckIndex)
  self:_write(deckIndex, self.c.CARD_LOCATION_DECK)
  return deckIndex
end

-- SearchCardInDeckAndAddToHand:: removes a selected deck index from the
-- drawable suffix, marks JUST_DRAWN, and compacts from the array tail backward.
function DuelOps:searchCardInDeckAndAddToHand(deckIndex)
  local gone = self:_read(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)
  local remaining = self.c.DECK_SIZE - gone
  self:_write(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK, gone + 1)
  self:_write(deckIndex, bit.bor(self:_read(deckIndex), self.c.CARD_LOCATION_JUST_DRAWN))

  local sourceOffset = self.c.DUELVARS_DECK_CARDS + self.c.DECK_SIZE - 1
  local destOffset = sourceOffset
  for _ = 1, remaining do
    local value = self:_read(sourceOffset)
    sourceOffset = sourceOffset - 1
    if value ~= deckIndex then
      self:_write(destOffset, value)
      destOffset = destOffset - 1
    end
  end
end

-- AddCardToHand::
function DuelOps:addCardToHand(deckIndex)
  self:_write(deckIndex, self.c.CARD_LOCATION_HAND)
  local count = u8(self:_read(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND) + 1)
  self:_write(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND, count)
  self:_write(self.c.DUELVARS_HAND + count - 1, deckIndex)
  return deckIndex
end

-- RemoveCardFromHand:: compacts all nonmatching entries exactly as the source loop does.
function DuelOps:removeCardFromHand(deckIndex)
  local count = self:_read(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  if count == 0 then return end
  local dest = self.c.DUELVARS_HAND
  for source = self.c.DUELVARS_HAND, self.c.DUELVARS_HAND + count - 1 do
    local value = self:_read(source)
    if value == deckIndex then
      self:_write(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND,
        u8(self:_read(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND) - 1))
    else
      self:_write(dest, value)
      dest = dest + 1
    end
  end
end

-- PutHandCardInPlayArea:: removes a hand card and writes its play-area
-- location byte. `playAreaOffset` is PLAY_AREA_ARENA/BENCH_* (0..5).
function DuelOps:putHandCardInPlayArea(deckIndex, playAreaOffset)
  self:removeCardFromHand(deckIndex)
  local location = bit.bor(playAreaOffset, self.c.CARD_LOCATION_PLAY_AREA)
  self:_write(deckIndex, location)
  return location
end

-- PutHandPokemonCardInPlayArea:: chooses arena/first-free bench from the
-- current Pokemon count, writes card/HP/stage state, and clears arena status.
-- Returns the source A result and carry as (value, carry).
function DuelOps:putHandPokemonCardInPlayArea(deckIndex)
  local count = self:_read(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if count >= self.c.MAX_PLAY_AREA_POKEMON then
    return deckIndex, true
  end

  local playAreaOffset = count
  self:_write(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA, u8(count + 1))
  self:putHandCardInPlayArea(deckIndex, playAreaOffset)
  self:_write(self.c.DUELVARS_ARENA_CARD + playAreaOffset, deckIndex)

  self.cardData:loadBuffer2FromDeckIndex(deckIndex)
  local loaded, bank = self.memory:address("wLoadedCard2")
  assert(bank == 0, "wLoadedCard2 unexpectedly moved out of WRAM0")
  local hp = self.memory:read8("wram", loaded + self.c.CARD_DATA_HP, bank)
  local stage = self.memory:read8("wram", loaded + self.c.CARD_DATA_STAGE, bank)
  self:_write(self.c.DUELVARS_ARENA_CARD_HP + playAreaOffset, hp)
  self:_write(self.c.DUELVARS_ARENA_CARD_FLAGS + playAreaOffset, 0)
  self:_write(self.c.DUELVARS_ARENA_CARD_CHANGED_TYPE + playAreaOffset, 0)
  self:_write(self.c.DUELVARS_ARENA_CARD_ATTACHED_PLUSPOWER + playAreaOffset, 0)
  self:_write(self.c.DUELVARS_ARENA_CARD_ATTACHED_DEFENDER + playAreaOffset, 0)
  self:_write(self.c.DUELVARS_ARENA_CARD_STAGE + playAreaOffset, stage)

  if playAreaOffset == self.c.PLAY_AREA_ARENA then
    self:clearAllStatusConditions()
  end
  return playAreaOffset, false
end

-- CheckIfCanEvolveInto:: boolean/cause form. Compatibility is determined by
-- the source text-ID comparison, not by authored evolution relationships.
function DuelOps:checkIfCanEvolveInto(deckIndex, playAreaOffset)
  local currentDeckIndex = self:_read(self.c.DUELVARS_ARENA_CARD + playAreaOffset)
  if currentDeckIndex == 0xff then return false, "empty_slot" end

  local currentCardId = self.cardData:getCardIDFromDeckIndex(currentDeckIndex)
  local current = assert(self.cardData:get(currentCardId))
  local evolutionCardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
  local evolution = assert(self.cardData:get(evolutionCardId))
  if evolution.preEvolutionTextId ~= current.nameTextId then
    return false, "incompatible"
  end

  local flags = self:_read(self.c.DUELVARS_ARENA_CARD_FLAGS + playAreaOffset)
  if bit.band(flags, self.c.CAN_EVOLVE_THIS_TURN) == 0 then
    return false, "played_this_turn"
  end
  return true
end

-- EvolvePokemonCardIfPossible:: / EvolvePokemonCard::. The old card remains
-- attached in the same location through PutHandCardInPlayArea semantics; HP is
-- increased only by the evolution's max-HP delta, preserving existing damage.
function DuelOps:evolvePokemonCardIfPossible(deckIndex, playAreaOffset)
  local can, reason = self:checkIfCanEvolveInto(deckIndex, playAreaOffset)
  if not can then return false, reason end

  local oldDeckIndex = self:_read(self.c.DUELVARS_ARENA_CARD + playAreaOffset)
  self.memory:writeSymbol8("wPreEvolutionPokemonCard", oldDeckIndex)
  local oldCardId = self.cardData:getCardIDFromDeckIndex(oldDeckIndex)
  local newCardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
  local oldRow = assert(self.cardData:get(oldCardId))
  local newRow = assert(self.cardData:get(newCardId))

  self:_write(self.c.DUELVARS_ARENA_CARD + playAreaOffset, deckIndex)
  self:putHandCardInPlayArea(deckIndex, playAreaOffset)
  local hpOffset = self.c.DUELVARS_ARENA_CARD_HP + playAreaOffset
  self:_write(hpOffset, u8(self:_read(hpOffset) + newRow.hp - oldRow.hp))
  self:_write(self.c.DUELVARS_ARENA_CARD_FLAGS + playAreaOffset, 0)
  self:_write(self.c.DUELVARS_ARENA_CARD_CHANGED_TYPE + playAreaOffset, 0)
  if playAreaOffset == self.c.PLAY_AREA_ARENA then self:clearAllStatusConditions() end
  self:_write(self.c.DUELVARS_ARENA_CARD_STAGE + playAreaOffset, newRow.stage)
  return true
end


-- PutCardInDiscardPile::
function DuelOps:putCardInDiscardPile(deckIndex)
  self:_write(deckIndex, self.c.CARD_LOCATION_DISCARD_PILE)
  local count = u8(self:_read(self.c.DUELVARS_NUMBER_OF_CARDS_IN_DISCARD_PILE) + 1)
  self:_write(self.c.DUELVARS_NUMBER_OF_CARDS_IN_DISCARD_PILE, count)
  self:_write(self.c.DUELVARS_DECK_CARDS + count - 1, deckIndex)
end

-- MoveHandCardToDiscardPile:: only accepts HAND after masking JUST_DRAWN.
function DuelOps:moveHandCardToDiscardPile(deckIndex)
  local location = bit.band(self:_read(deckIndex),
    bit.bxor(0xff, self.c.CARD_LOCATION_JUST_DRAWN))
  if location ~= self.c.CARD_LOCATION_HAND then return false end
  self:removeCardFromHand(deckIndex)
  self:putCardInDiscardPile(deckIndex)
  return true
end

-- MoveDiscardPileCardToHand:: marks JUST_DRAWN and compacts the discard prefix.
function DuelOps:moveDiscardPileCardToHand(deckIndex)
  self:_write(deckIndex, bit.bor(self:_read(deckIndex), self.c.CARD_LOCATION_JUST_DRAWN))
  local count = self:_read(self.c.DUELVARS_NUMBER_OF_CARDS_IN_DISCARD_PILE)
  if count == 0 then return 0 end
  self:_write(self.c.DUELVARS_NUMBER_OF_CARDS_IN_DISCARD_PILE, count - 1)
  local dest = self.c.DUELVARS_DECK_CARDS
  for source = self.c.DUELVARS_DECK_CARDS, self.c.DUELVARS_DECK_CARDS + count - 1 do
    local value = self:_read(source)
    if value ~= deckIndex then
      self:_write(dest, value)
      dest = dest + 1
    end
  end
  return deckIndex
end

-- CheckPrizeTaken:: zero means taken, nonzero means still available.
function DuelOps:checkPrizeTaken(prizeIndex)
  local mask = bit.lshift(1, prizeIndex)
  return bit.band(self:_read(self.c.DUELVARS_PRIZES), mask) == 0
end

local function writeFFList(memory, base, values)
  for i, value in ipairs(values) do
    memory:write8("wram", base + i - 1, value, 0)
  end
  memory:write8("wram", base + #values, 0xff, 0)
end

-- CreateDiscardPileCardList:: copies discard cards in reverse order.
function DuelOps:createDiscardPileCardList()
  local count = self:_read(self.c.DUELVARS_NUMBER_OF_CARDS_IN_DISCARD_PILE)
  local values = {}
  for index = count - 1, 0, -1 do
    values[#values + 1] = self:_read(self.c.DUELVARS_DECK_CARDS + index)
  end
  local base = self.memory:address("wDuelTempList")
  writeFFList(self.memory, base, values)
  return values, count == 0
end

-- CreateDeckCardList:: copies the still-drawable suffix forward.
function DuelOps:createDeckCardList()
  local gone = self:_read(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)
  local values = {}
  if gone < self.c.DECK_SIZE then
    for index = gone, self.c.DECK_SIZE - 1 do
      values[#values + 1] = self:_read(self.c.DUELVARS_DECK_CARDS + index)
    end
  end
  local base = self.memory:address("wDuelTempList")
  writeFFList(self.memory, base, values)
  return values, #values == 0
end

-- CreateHandCardList:: copies newest-to-oldest hand entries, skipping cards
-- whose CardLocations byte has CARD_LOCATION_JUST_DRAWN_F set. Carry follows
-- NUMBER_OF_CARDS_IN_HAND exactly, not the number of entries that survived.
function DuelOps:createHandCardList()
  local count = self:_read(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  local values = {}
  for index = count - 1, 0, -1 do
    local deckIndex = self:_read(self.c.DUELVARS_HAND + index)
    local location = self:_read(deckIndex)
    if bit.band(location, self.c.CARD_LOCATION_JUST_DRAWN) == 0 then
      values[#values + 1] = deckIndex
    end
  end
  local base = self.memory:address("wDuelTempList")
  writeFFList(self.memory, base, values)
  return values, count == 0
end

-- SortCardsInDuelTempListByID:: selection-sort semantics from the source.
-- Equal IDs select the later candidate (the assembly updates on <=), which is
-- retained here even though the decomp notes equal-card deck-index order is irrelevant.
function DuelOps:sortCardsInDuelTempListByID()
  local base = self.memory:address("wDuelTempList")
  local ptrAddress, ptrBank = self.memory:address("hTempListPtr_ff99")
  local idAddress, idBank = self.memory:address("hTempCardID_ff9b")
  self.memory:write8("hram", ptrAddress, base % 0x100, ptrBank)
  self.memory:write8("hram", ptrAddress + 1, math.floor(base / 0x100), ptrBank)

  local pos = base
  while self.memory:read8("wram", pos, 0) ~= 0xff do
    local selected = pos
    local selectedDeck = self.memory:read8("wram", selected, 0)
    local selectedId = self.cardData:getCardIDFromDeckIndex(selectedDeck)
    self.memory:write8("hram", idAddress, selectedId, idBank)
    self.memory:write8("hram", idAddress + 1, 0, idBank)
    local scan = pos + 1
    while self.memory:read8("wram", scan, 0) ~= 0xff do
      local candidateDeck = self.memory:read8("wram", scan, 0)
      local candidateId = self.cardData:getCardIDFromDeckIndex(candidateDeck)
      if candidateId <= selectedId then
        selected = scan
        selectedId = candidateId
        self.memory:write8("hram", idAddress, selectedId, idBank)
        self.memory:write8("hram", idAddress + 1, 0, idBank)
      end
      scan = scan + 1
    end
    local here = self.memory:read8("wram", pos, 0)
    local low = self.memory:read8("wram", selected, 0)
    self.memory:write8("wram", pos, low, 0)
    self.memory:write8("wram", selected, here, 0)
    pos = pos + 1
    self.memory:write8("hram", ptrAddress, pos % 0x100, ptrBank)
    self.memory:write8("hram", ptrAddress + 1, math.floor(pos / 0x100), ptrBank)
  end
end

-- SortHandCardsByID:: reverse hand into wDuelTempList, sort low-to-high there,
-- then copy forward from the temp list back toward older hand slots.
function DuelOps:sortHandCardsByID()
  local count = self:_read(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  if count == 0 then return end
  local values = {}
  for index = count - 1, 0, -1 do
    values[#values + 1] = self:_read(self.c.DUELVARS_HAND + index)
  end
  local base = self.memory:address("wDuelTempList")
  writeFFList(self.memory, base, values)
  self:sortCardsInDuelTempListByID()
  for i = 0, count - 1 do
    local value = self.memory:read8("wram", base + i, 0)
    self:_write(self.c.DUELVARS_HAND + count - 1 - i, value)
  end
end

-- RemoveCardFromDuelTempList:: compacts nonmatching entries and preserves the
-- implementation's actual carry behavior: carry is set when the resulting list
-- is empty, even though the source comment says "if no matches were found".
function DuelOps:removeCardFromDuelTempList(deckIndex)
  local base = self.memory:address("wDuelTempList")
  local source = base
  local dest = base
  local kept = 0
  while true do
    local value = self.memory:read8("wram", source, 0)
    source = source + 1
    if value == 0xff then
      self.memory:write8("wram", dest, 0xff, 0)
      return kept == 0
    end
    if value ~= deckIndex then
      self.memory:write8("wram", dest, value, 0)
      dest = dest + 1
      kept = kept + 1
    end
  end
end

-- CountCardsInDuelTempList::
function DuelOps:countCardsInDuelTempList()
  local base = self.memory:address("wDuelTempList")
  local count = 0
  while self.memory:read8("wram", base + count, 0) ~= 0xff do
    count = count + 1
  end
  return count
end


-- GetPlayAreaCardAttachedEnergies:: preserves the source's eight energy-type
-- counters. Double Colorless increments COLORLESS twice.
function DuelOps:getPlayAreaCardAttachedEnergies(playAreaOffset)
  local attachedBase, attachedBank = self.memory:address("wAttachedEnergies")
  assert(attachedBank == 0, "wAttachedEnergies unexpectedly moved out of WRAM0")
  for i = 0, self.c.NUM_TYPES - 1 do
    self.memory:write8("wram", attachedBase + i, 0, attachedBank)
  end

  local wanted = bit.bor(self.c.CARD_LOCATION_PLAY_AREA, playAreaOffset)
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    if self:_read(deckIndex) == wanted then
      self.cardData:loadBuffer2FromDeckIndex(deckIndex)
      local loaded, bank = self.memory:address("wLoadedCard2")
      local cardType = self.memory:read8("wram", loaded + self.c.CARD_DATA_TYPE, bank)
      if bit.band(cardType, bit.lshift(1, self.c.TYPE_ENERGY_F)) ~= 0 then
        local energyType = bit.band(cardType, self.c.TYPE_PKMN)
        local address = attachedBase + energyType
        local value = u8(self.memory:read8("wram", address, attachedBank) + 1)
        self.memory:write8("wram", address, value, attachedBank)
        if energyType == self.c.COLORLESS then
          self.memory:write8("wram", address, u8(value + 1), attachedBank)
        end
      end
    end
  end

  local total = 0
  for i = 0, self.c.NUM_TYPES - 1 do
    total = u8(total + self.memory:read8("wram", attachedBase + i, attachedBank))
  end
  self.memory:writeSymbol8("wTotalAttachedEnergies", total)
  return total
end


-- CreateArenaOrBenchEnergyCardList:: fills wDuelTempList with deck indexes of
-- Energy cards attached to the requested Play Area slot and terminates with $ff.
-- Returns (count, carry), with carry set when no Energy cards were found.
function DuelOps:createArenaOrBenchEnergyCardList(playAreaOffset)
  local wanted = bit.bor(self.c.CARD_LOCATION_PLAY_AREA, playAreaOffset)
  local base, bank = self.memory:address("wDuelTempList")
  local count = 0
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    if self:_read(deckIndex) == wanted then
      self.cardData:loadBuffer2FromDeckIndex(deckIndex)
      local loaded, loadedBank = self.memory:address("wLoadedCard2")
      local cardType = self.memory:read8("wram", loaded + self.c.CARD_DATA_TYPE, loadedBank)
      if bit.band(cardType, bit.lshift(1, self.c.TYPE_ENERGY_F)) ~= 0 then
        self.memory:write8("wram", base + count, deckIndex, bank)
        count = count + 1
      end
    end
  end
  self.memory:write8("wram", base + count, 0xff, bank)
  return count, count == 0
end

-- CheckIfThereAreAnyEnergyCardsAttached:: scans every card attached anywhere
-- in the turn holder's Play Area and returns carry=true when none are present.
function DuelOps:checkIfThereAreAnyEnergyCardsAttached()
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    local location = self:_read(deckIndex)
    if bit.band(location, self.c.CARD_LOCATION_PLAY_AREA) ~= 0 then
      self.cardData:loadBuffer2FromDeckIndex(deckIndex)
      local loaded, loadedBank = self.memory:address("wLoadedCard2")
      local cardType = self.memory:read8("wram", loaded + self.c.CARD_DATA_TYPE, loadedBank)
      if bit.band(cardType, bit.lshift(1, self.c.TYPE_ENERGY_F)) ~= 0 then
        return true, false
      end
    end
  end
  return false, true
end

-- EmptyPlayAreaSlot:: does not clear the flags byte in the source.
function DuelOps:emptyPlayAreaSlot(playAreaOffset)
  self:_write(self.c.DUELVARS_ARENA_CARD + playAreaOffset, 0xff)
  self:_write(self.c.DUELVARS_ARENA_CARD_HP + playAreaOffset, 0)
  self:_write(self.c.DUELVARS_ARENA_CARD_STAGE + playAreaOffset, 0)
  self:_write(self.c.DUELVARS_ARENA_CARD_CHANGED_TYPE + playAreaOffset, 0)
  self:_write(self.c.DUELVARS_ARENA_CARD_ATTACHED_DEFENDER + playAreaOffset, 0)
  self:_write(self.c.DUELVARS_ARENA_CARD_ATTACHED_PLUSPOWER + playAreaOffset, 0)
end

-- MovePlayAreaCardToDiscardPile:: discards every card whose location byte
-- equals the removed slot, including attached Energy and prior evolution cards.
function DuelOps:movePlayAreaCardToDiscardPile(playAreaOffset)
  self:emptyPlayAreaSlot(playAreaOffset)
  self:_write(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA,
    u8(self:_read(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) - 1))
  local location = bit.bor(self.c.CARD_LOCATION_PLAY_AREA, playAreaOffset)
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    if self:_read(deckIndex) == location then
      self:putCardInDiscardPile(deckIndex)
    end
  end
end

-- SwapPlayAreaPokemon:: swaps the seven per-slot duel variables used by the
-- source and rewrites all attached-card location bytes for both slots.
function DuelOps:swapPlayAreaPokemon(slotD, slotE)
  if slotD == slotE then return end
  for _, base in ipairs({
    self.c.DUELVARS_ARENA_CARD,
    self.c.DUELVARS_ARENA_CARD_HP,
    self.c.DUELVARS_ARENA_CARD_FLAGS,
    self.c.DUELVARS_ARENA_CARD_STAGE,
    self.c.DUELVARS_ARENA_CARD_CHANGED_TYPE,
    self.c.DUELVARS_ARENA_CARD_ATTACHED_PLUSPOWER,
    self.c.DUELVARS_ARENA_CARD_ATTACHED_DEFENDER,
  }) do
    local d = self:_read(base + slotD)
    local e = self:_read(base + slotE)
    self:_write(base + slotD, e)
    self:_write(base + slotE, d)
  end

  local locationD = bit.bor(self.c.CARD_LOCATION_PLAY_AREA, slotD)
  local locationE = bit.bor(self.c.CARD_LOCATION_PLAY_AREA, slotE)
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    local value = self:_read(deckIndex)
    if value == locationE then
      self:_write(deckIndex, locationD)
    elseif value == locationD then
      self:_write(deckIndex, locationE)
    end
  end
end

function DuelOps:swapArenaWithBenchPokemon(benchSlot)
  self:clearAllStatusConditions()
  self:swapPlayAreaPokemon(self.c.PLAY_AREA_ARENA, benchSlot)
end

function DuelOps:shiftTurnPokemonToFirstPlayAreaSlots()
  local destination = self.c.PLAY_AREA_ARENA
  for source = self.c.PLAY_AREA_ARENA, self.c.MAX_PLAY_AREA_POKEMON - 1 do
    if self:_read(self.c.DUELVARS_ARENA_CARD + source) ~= 0xff then
      self:swapPlayAreaPokemon(source, destination)
      destination = destination + 1
    end
  end
end

function DuelOps:shiftAllPokemonToFirstPlayAreaSlots()
  self:shiftTurnPokemonToFirstPlayAreaSlots()
  self.duelVars:swapTurn()
  self:shiftTurnPokemonToFirstPlayAreaSlots()
  self.duelVars:swapTurn()
end

-- CountCardIDInLocation:: returns how many copies of cardId have the exact
-- CARD_LOCATION_* byte in the current turn holder's duel page.  The source
-- damage engine uses this for attached PlusPower and Defender rather than
-- trusting their cached per-slot counters.
function DuelOps:countCardIDInLocation(cardId, location)
  local count = 0
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    if self:_read(deckIndex) == location
        and self.cardData:getCardIDFromDeckIndex(deckIndex) == cardId then
      count = count + 1
    end
  end
  return count
end

-- MoveCardToDiscardPileIfInPlayArea:: used for attached PlusPower/Defender.
function DuelOps:moveCardToDiscardPileIfInPlayArea(cardId)
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    local location = self:_read(deckIndex)
    if bit.band(location, self.c.CARD_LOCATION_PLAY_AREA) ~= 0
        and self.cardData:getCardIDFromDeckIndex(deckIndex) == cardId then
      self:putCardInDiscardPile(deckIndex)
    end
  end
end

-- HasAlivePokemonInBench:: via _HasAlivePokemonInPlayArea with input a=1.
-- Returns (count, carry), where carry is set when no alive Bench Pokemon exist.
-- Preserve the source UI bookkeeping side effects as well.
function DuelOps:hasAlivePokemonInBench()
  self.memory:writeSymbol8("wExcludeArenaPokemon", 1)
  self.memory:writeSymbol8("wPlayAreaScreenLoaded", 0)
  self.memory:writeSymbol8("wPlayAreaSelectAction", 0)

  local count = self:_read(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  -- Source uses 8-bit C: count=0 underflows and scans 255 bytes. Preserve it.
  local iterations = count == 0 and 0xff or count - 1
  local hpAddress = self.duelVars:address(self.c.DUELVARS_ARENA_CARD_HP + 1)
  local alive = 0
  for i = 0, iterations - 1 do
    if self.memory:read8("wram", hpAddress + i, 0) ~= 0 then alive = alive + 1 end
  end
  return alive, alive == 0
end

-- SubtractHP:: returns carry=true when HP remains nonzero.
function DuelOps:subtractHP(duelVarOffset, damage)
  local hp = self:_read(duelVarOffset)
  local remaining = hp - damage
  if remaining < 0 then remaining = 0 end
  remaining = u8(remaining)
  self:_write(duelVarOffset, remaining)
  return remaining, remaining ~= 0
end

-- ClearAllStatusConditions:: does not clear Headache; the source clears only
-- SUBSTATUS3_THIS_TURN_DOUBLE_DAMAGE_F in substatus3, then zeroes eight bytes
-- beginning at ARENA_CARD_DISABLED_ATTACK_INDEX.
function DuelOps:clearAllStatusConditions()
  self:_write(self.c.DUELVARS_ARENA_CARD_STATUS, 0)
  self:_write(self.c.DUELVARS_ARENA_CARD_SUBSTATUS1, 0)
  self:_write(self.c.DUELVARS_ARENA_CARD_SUBSTATUS2, 0)
  self:_write(self.c.DUELVARS_ARENA_CARD_CHANGED_WEAKNESS, 0)
  self:_write(self.c.DUELVARS_ARENA_CARD_CHANGED_RESISTANCE, 0)

  local sub3 = self:_read(self.c.DUELVARS_ARENA_CARD_SUBSTATUS3)
  sub3 = bit.band(sub3, bit.bnot(bit.lshift(1,
    self.c.SUBSTATUS3_THIS_TURN_DOUBLE_DAMAGE_F)))
  self:_write(self.c.DUELVARS_ARENA_CARD_SUBSTATUS3, sub3)

  for offset = 0, 7 do
    self:_write(self.c.DUELVARS_ARENA_CARD_DISABLED_ATTACK_INDEX + offset, 0)
  end
end

return DuelOps
