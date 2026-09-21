-- Behavioral smoke test for Ditto's Morph, run under real LuaJIT.
--
-- Shuffles the attacker's own Deck (excluding other Dittos) for a random
-- Basic Pokemon, then transforms the Attacking Pokemon into it. Unlike
-- Devolution Beam's slot-content swap, this permanently overwrites the
-- arena's OWN deck slot's card-identity entry (CardData:
-- setCardIDForDeckIndex) -- the picked deck card itself is untouched and
-- stays in the deck. If the Attacking Pokemon isn't already Basic (e.g.
-- when copied via Metronome from an evolved Pokemon), first discards its
-- pre-evolution card and resets its own stage to Basic (reusing the
-- Devolution Spray/Beam family's cardOneStageBelow).

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")
local bit = require("bit")

local C = setmetatable({
  PLAY_AREA_ARENA = 0,
  DUELVARS_ARENA_CARD = 0x60, DUELVARS_ARENA_CARD_HP = 0x70, DUELVARS_ARENA_CARD_STAGE = 0x80,
  DUELVARS_ARENA_CARD_CHANGED_TYPE = 0x90,
  CARD_LOCATION_PLAY_AREA = 0x10,
  BASIC = 0, STAGE1 = 1, STAGE2 = 2, STAGE2_WITHOUT_STAGE1 = 3,
  TYPE_ENERGY = 8, DECK_SIZE = 60, DITTO = 999,
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

local WDUELTEMPLIST_BASE = 2000

-- cards: {deckIndex -> {cardId=.., stage=.., hp=.., type=(optional)}}
-- playArea: {slot -> deckIndex} (own side only, needed for cardOneStageBelow)
-- deckList: deck indices CreateDeckCardList should return, in this order
local function newHarness(opts)
  opts = opts or {}
  local turn = {}
  local location = {}
  local cardById = {}
  local cardIdByDeckIndex = {}
  for deckIndex, card in pairs(opts.cards or {}) do
    cardIdByDeckIndex[deckIndex] = card.cardId
    cardById[card.cardId] = { hp = card.hp, stage = card.stage, type = card.type or 0 }
  end
  for slot, deckIndex in pairs(opts.playArea or {}) do
    turn[C.DUELVARS_ARENA_CARD + slot] = deckIndex
    location[deckIndex] = bit.bor(C.CARD_LOCATION_PLAY_AREA, slot)
  end
  for deckIndex, slot in pairs(opts.attachedTo or {}) do
    location[deckIndex] = bit.bor(C.CARD_LOCATION_PLAY_AREA, slot)
  end
  turn[C.DUELVARS_ARENA_CARD_STAGE] = opts.ownStage
  turn[C.DUELVARS_ARENA_CARD_HP] = opts.ownHP or 0

  local tempListWords = {}
  local memory = {
    address = function(_, symbol)
      check("addresses wDuelTempList", symbol, "wDuelTempList")
      return WDUELTEMPLIST_BASE, 0
    end,
    read8 = function(_, area, addr) return tempListWords[addr] end,
    write8 = function(_, area, addr, value) tempListWords[addr] = value end,
    readSymbol8 = function() return 0 end,
    writeSymbol8 = function() end,
  }
  local discardCalls, setIdCalls, clearStatusCalls = {}, {}, 0
  local duelOps = {
    createDeckCardList = function()
      local list = opts.deckList or {}
      for i, v in ipairs(list) do tempListWords[WDUELTEMPLIST_BASE + i - 1] = v end
      tempListWords[WDUELTEMPLIST_BASE + #list] = 0xff
      return list, #list == 0
    end,
    rng = { shuffleCards = function() end },
    putCardInDiscardPile = function(_, deckIndex) discardCalls[#discardCalls + 1] = deckIndex end,
    clearAllStatusConditions = function() clearStatusCalls = clearStatusCalls + 1 end,
  }
  local cardData = {
    getCardIDFromDeckIndex = function(_, deckIndex) return cardIdByDeckIndex[deckIndex] end,
    get = function(_, cardId) return cardById[cardId] end,
    setCardIDForDeckIndex = function(_, deckIndex, cardId)
      setIdCalls[#setIdCalls + 1] = { deckIndex = deckIndex, cardId = cardId }
    end,
  }
  local actor = {
    duelVars = {
      get = function(_, a)
        if turn[a] ~= nil then return turn[a] end
        return location[a] or 0
      end,
      set = function(_, a, v) turn[a] = v end,
      getNonTurn = function() return 0 end, swapTurn = function() end,
    },
    cardData = cardData,
    duelOps = duelOps,
    memory = memory,
  }
  local effects = EffectCommands.new(memory, {}, {}, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  return effects, actor, discardCalls, setIdCalls, function() return clearStatusCalls end
end

-- No Basic Pokemon in the deck at all (only Ditto and evolved cards):
-- nothing happens, carry false.
do
  local effects, actor, discardCalls, setIdCalls, clearStatusCalls = newHarness({
    ownStage = C.BASIC,
    cards = { [50] = { cardId = C.DITTO, stage = C.BASIC, hp = 50 },
      [51] = { cardId = 200, stage = C.STAGE1, hp = 90 } },
    deckList = { 50, 51 },
  })
  local carry = effects.handlers["MorphEffect"](effects, { combat = actor })
  check("no candidate: carry false", carry, false)
  check("no candidate: nothing discarded", #discardCalls, 0)
  check("no candidate: no identity overwrite", #setIdCalls, 0)
  check("no candidate: no status clear", clearStatusCalls(), 0)
end

-- Own arena is already Basic: transforms directly, no discard needed.
do
  local effects, actor, discardCalls, setIdCalls, clearStatusCalls = newHarness({
    ownStage = C.BASIC, ownHP = 30,
    playArea = { [C.PLAY_AREA_ARENA] = 5 },
    cards = {
      [5] = { cardId = 111, stage = C.BASIC, hp = 60 },     -- Ditto itself, own arena
      [12] = { cardId = C.DITTO, stage = C.BASIC, hp = 50 }, -- excluded
      [13] = { cardId = 222, stage = C.BASIC, hp = 80 },     -- the pick
    },
    deckList = { 12, 13 },
  })
  local carry = effects.handlers["MorphEffect"](effects, { combat = actor })
  check("already basic: carry false", carry, false)
  check("already basic: skips the Ditto candidate", #discardCalls, 0)
  check("already basic: exactly one identity overwrite", #setIdCalls, 1)
  check("already basic: overwrites the arena's own deck slot", setIdCalls[1].deckIndex, 5)
  check("already basic: to the picked card's id", setIdCalls[1].cardId, 222)
  check("already basic: sets HP to the new card's max HP", actor.duelVars:get(C.DUELVARS_ARENA_CARD_HP), 80)
  check("already basic: clears changed type", actor.duelVars:get(C.DUELVARS_ARENA_CARD_CHANGED_TYPE), 0)
  check("already basic: clears status conditions once", clearStatusCalls(), 1)
end

-- Own arena is Stage1 (e.g. via Metronome copying an evolved Pokemon):
-- discards the pre-evolution card and resets its own stage to Basic
-- first, then transforms.
do
  local effects, actor, discardCalls, setIdCalls = newHarness({
    ownStage = C.STAGE1, ownHP = 70,
    playArea = { [C.PLAY_AREA_ARENA] = 5 },
    attachedTo = { [4] = C.PLAY_AREA_ARENA },
    cards = {
      [4] = { cardId = 100, stage = C.BASIC, hp = 60 },   -- the pre-evolution card underneath
      [5] = { cardId = 101, stage = C.STAGE1, hp = 90 },  -- own evolved arena card
      [13] = { cardId = 222, stage = C.BASIC, hp = 80 },  -- the pick
    },
    deckList = { 13 },
  })
  local carry = effects.handlers["MorphEffect"](effects, { combat = actor })
  check("stage1: carry false", carry, false)
  check("stage1: discards the pre-evolution card", discardCalls[1], 4)
  check("stage1: resets own stage to basic", actor.duelVars:get(C.DUELVARS_ARENA_CARD_STAGE), C.BASIC)
  check("stage1: still transforms afterward", #setIdCalls, 1)
  check("stage1: overwrites the arena's own deck slot", setIdCalls[1].deckIndex, 5)
  check("stage1: to the picked card's id", setIdCalls[1].cardId, 222)
end

if failures == 0 then
  print("all morph effect cases passed")
  os.exit(0)
else
  print(("%d morph effect case(s) failed"):format(failures))
  os.exit(1)
end
