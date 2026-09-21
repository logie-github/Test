-- Deck-loading routines translated from pret/poketcg:
--   src/home/load_deck.asm  (LoadDeck)
--   src/engine/duel/core.asm (LoadPlayerDeck)
--   src/home/ai.asm         (LoadOpponentDeck)
--
-- The SRAM player-deck path stays address-based; built-in opponent decks use
-- the ROM/decomp-extracted deck lists already validated at import time.

local bit = require("bit")

local DeckLoader = {}
DeckLoader.__index = DeckLoader

function DeckLoader.new(memory, duelVars, duelOps, rng, constants, decks)
  return setmetatable({
    memory = assert(memory),
    duelVars = assert(duelVars),
    duelOps = assert(duelOps),
    rng = assert(rng),
    c = assert(constants),
    decks = assert(decks),
  }, DeckLoader)
end

-- LoadDeck:: resolves DeckPointers[a], returning carry for its NULL entry.
function DeckLoader:loadDeck(deckId)
  if not self.decks.byId[deckId] then return true end
  self.duelOps:copyDeckData(deckId)
  return false
end

-- LoadPlayerDeck:: copies the selected SRAM deck's 60 card bytes to
-- wPlayerDeck. The source computes the slot stride from sDeck2Cards-sDeck1Cards;
-- do the same from generated RGBDS addresses rather than DECK_STRUCT_SIZE.
function DeckLoader:loadPlayerDeck()
  local selected = self.memory:readSymbol8("sCurrentlySelectedDeck")
  local s1Space, s1Bank, s1 = self.memory:resolve("sDeck1Cards")
  local s2Space, s2Bank, s2 = self.memory:resolve("sDeck2Cards")
  assert(s1Space == "sram" and s2Space == "sram" and s1Bank == s2Bank,
    "SRAM deck symbol layout changed")
  local stride = s2 - s1
  local source = s1 + stride * selected

  local dest, destBank = self.memory:address("wPlayerDeck")
  assert(destBank == 0, "wPlayerDeck unexpectedly moved out of WRAM0")
  for offset = 0, self.c.DECK_SIZE - 1 do
    local value = self.memory:read8("sram", source + offset, s1Bank)
    self.memory:write8("wram", dest + offset, value, destBank)
  end
end

-- LoadOpponentDeck:: includes the original Sam/practice special cases and RNG
-- seed. It expects hWhoseTurn to identify the opponent, as in StartDuel_VSAIOpp.
function DeckLoader:loadOpponentDeck()
  self.memory:writeSymbol8("wIsPracticeDuel", 0)
  local opponentId = self.memory:readSymbol8("wOpponentDeckID")
  local deckId

  if opponentId == self.c.SAMS_NORMAL_DECK_ID
      or opponentId == self.c.SAMS_PRACTICE_DECK_ID then
    if opponentId == self.c.SAMS_PRACTICE_DECK_ID then
      self.memory:writeSymbol8("wIsPracticeDuel", 1)
    end

    self.memory:writeSymbol8("wOpponentDeckID", 0)
    self.duelVars:swapTurn()
    self:loadDeck(self.c.PRACTICE_PLAYER_DECK)
    self.duelVars:swapTurn()
    self.memory:writeSymbol8("wRNG1", 0x57)
    self.memory:writeSymbol8("wRNG2", 0x57)
    self.memory:writeSymbol8("wRNGCounter", 0x57)
    deckId = self.c.SAMS_PRACTICE_DECK -- source A is xor'd then incremented twice
  else
    deckId = (opponentId + 2) % 0x100
  end

  local carry = self:loadDeck(deckId)

  opponentId = self.memory:readSymbol8("wOpponentDeckID")
  if opponentId >= self.c.NUM_DECK_IDS + 1 then
    opponentId = self.c.PRACTICE_PLAYER_DECK_ID
    self.memory:writeSymbol8("wOpponentDeckID", opponentId)
  end

  self.duelVars:set(self.c.DUELVARS_DUELIST_TYPE,
    bit.bor(opponentId, self.c.DUELIST_TYPE_AI_OPP))
  return carry
end

return DeckLoader
