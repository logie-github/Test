-- Behavioral smoke test for Magneton's Magnetic Storm, run under real
-- LuaJIT.
--
-- Gathers every Energy card attached anywhere in the attacker's own Play
-- Area, shuffles them, and redistributes them evenly across every
-- Pokemon in that Play Area (floor(totalEnergy / pokemonCount) each,
-- consumed off the front of the shuffled list in Play Area order), then
-- randomly hands out the totalEnergy % pokemonCount leftover cards one
-- each to a random subset of Pokemon (a second shuffle of the slot
-- indices themselves).

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")
local bit = require("bit")

local C = setmetatable({
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = 1000,
  CARD_LOCATION_PLAY_AREA = 0x10, CARD_LOCATION_DECK = 0x01, CARD_LOCATION_HAND = 0x02,
  DECK_SIZE = 60, TYPE_ENERGY_F = 3, TYPE_PKMN_FIRE = 1,
}, { __index = function(_, k) return k end })

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(("FAIL  %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
  else
    print(("ok    %s"):format(label))
  end
end

local WDUELTEMPLIST_BASE, HTEMPLIST_BASE = 2000, 3000

-- cards: {deckIndex -> {cardId=.., type=..}}, locations: {deckIndex -> bitmask}
local function newHarness(opts)
  opts = opts or {}
  local wram, hram = {}, {}
  local cardById, cardIdByDeckIndex = {}, {}
  for deckIndex, card in pairs(opts.cards or {}) do
    cardIdByDeckIndex[deckIndex] = card.cardId
    cardById[card.cardId] = { type = card.type }
  end
  local locations = opts.locations or {}

  local memory = {
    address = function(_, symbol)
      if symbol == "wDuelTempList" then return WDUELTEMPLIST_BASE, 0 end
      if symbol == "hTempList" then return HTEMPLIST_BASE, 0 end
      error("unexpected address: " .. tostring(symbol))
    end,
    read8 = function(_, area, addr) return (area == "hram" and hram or wram)[addr] end,
    write8 = function(_, area, addr, value) (area == "hram" and hram or wram)[addr] = value end,
    readSymbol8 = function() return 0 end,
    writeSymbol8 = function() end,
  }
  local shuffleCalls = {}
  local addedToHand, attachedTo = {}, {}
  local duelOps = {
    rng = { shuffleCards = function(_, addr, count) shuffleCalls[#shuffleCalls + 1] = { addr = addr, count = count } end },
    addCardToHand = function(_, deckIndex) addedToHand[#addedToHand + 1] = deckIndex end,
    putHandCardInPlayArea = function(_, deckIndex, slot) attachedTo[#attachedTo + 1] = { deckIndex = deckIndex, slot = slot } end,
  }
  local cardData = {
    getCardIDFromDeckIndex = function(_, deckIndex) return cardIdByDeckIndex[deckIndex] end,
    get = function(_, cardId) return cardById[cardId] end,
  }
  local duelVars = {
    get = function(_, a)
      if a == C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA then return opts.pokemonCount end
      return locations[a] or 0
    end,
  }
  local actor = { duelVars = duelVars, duelOps = duelOps, cardData = cardData, memory = memory }
  local effects = EffectCommands.new(memory, {}, {}, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  return effects, actor, shuffleCalls, addedToHand, attachedTo
end

local ENERGY_TYPE = bit.lshift(1, C.TYPE_ENERGY_F)
local POKEMON_TYPE = C.TYPE_PKMN_FIRE

-- Evenly divisible: 6 Energy cards, 3 Pokemon -> 2 each, no remainder.
do
  local cards, locations = {}, {}
  for i, deckIndex in ipairs({ 10, 11, 12, 13, 14, 15 }) do
    cards[deckIndex] = { cardId = deckIndex, type = ENERGY_TYPE }
    locations[deckIndex] = C.CARD_LOCATION_PLAY_AREA
  end
  -- a Pokemon card in the Play Area (not Energy -- must be excluded)
  cards[20] = { cardId = 20, type = POKEMON_TYPE }
  locations[20] = C.CARD_LOCATION_PLAY_AREA
  -- an Energy card in hand (not in the Play Area -- must be excluded)
  cards[30] = { cardId = 30, type = ENERGY_TYPE }
  locations[30] = C.CARD_LOCATION_HAND

  local effects, actor, shuffleCalls, addedToHand, attachedTo = newHarness({
    pokemonCount = 3, cards = cards, locations = locations,
  })
  local carry = effects.handlers["MagneticStormEffect"](effects, { combat = actor })
  check("even split: carry false", carry, false)
  check("even split: gathered exactly 6 energy cards", shuffleCalls[1].count, 6)
  check("even split: only one shuffle call (no remainder)", #shuffleCalls, 1)
  check("even split: exactly 6 cards moved", #addedToHand, 6)
  check("even split: exactly 6 attachments", #attachedTo, 6)
  check("even split: slot 0 gets the first two", attachedTo[1].slot, 0)
  check("even split: slot 0 gets the first two (deck index)", attachedTo[1].deckIndex, 10)
  check("even split: slot 0's second card", attachedTo[2].deckIndex, 11)
  check("even split: slot 1 gets the next two", attachedTo[3].slot, 1)
  check("even split: slot 1's first card", attachedTo[3].deckIndex, 12)
  check("even split: slot 2 gets the last two", attachedTo[5].slot, 2)
  check("even split: slot 2's first card", attachedTo[5].deckIndex, 14)
end

-- 7 Energy cards, 3 Pokemon -> 2 each (6 consumed) plus 1 leftover
-- handed to a randomly shuffled slot.
do
  local cards, locations = {}, {}
  for _, deckIndex in ipairs({ 10, 11, 12, 13, 14, 15, 16 }) do
    cards[deckIndex] = { cardId = deckIndex, type = ENERGY_TYPE }
    locations[deckIndex] = C.CARD_LOCATION_PLAY_AREA
  end

  local effects, actor, shuffleCalls, addedToHand, attachedTo = newHarness({
    pokemonCount = 3, cards = cards, locations = locations,
  })
  local carry = effects.handlers["MagneticStormEffect"](effects, { combat = actor })
  check("with remainder: carry false", carry, false)
  check("with remainder: gathered exactly 7 energy cards", shuffleCalls[1].count, 7)
  check("with remainder: a second shuffle for the slot order", #shuffleCalls, 2)
  check("with remainder: second shuffle covers all 3 slots", shuffleCalls[2].count, 3)
  check("with remainder: exactly 7 cards moved total", #addedToHand, 7)
  check("with remainder: exactly 7 attachments total", #attachedTo, 7)
  check("with remainder: the 7th (leftover) card is the last in the shuffled list",
    attachedTo[7].deckIndex, 16)
  check("with remainder: it lands on the first shuffled slot", attachedTo[7].slot, 0)
end

-- No Energy attached anywhere: nothing happens, no shuffle at all.
do
  local effects, actor, shuffleCalls, addedToHand, attachedTo = newHarness({
    pokemonCount = 2, cards = {}, locations = {},
  })
  local carry = effects.handlers["MagneticStormEffect"](effects, { combat = actor })
  check("no energy: carry false", carry, false)
  check("no energy: still calls shuffle once with count 0", shuffleCalls[1].count, 0)
  check("no energy: nothing moved", #addedToHand, 0)
  check("no energy: nothing attached", #attachedTo, 0)
end

if failures == 0 then
  print("all magnetic storm effect cases passed")
  os.exit(0)
else
  print(("%d magnetic storm effect case(s) failed"):format(failures))
  os.exit(1)
end
