-- Behavioral smoke test for Ninetales' Mix Up, run under real LuaJIT.
--
-- Sorts the opponent's Hand by card ID, moves every Pokemon card found
-- there back into the Deck, always reshuffles the Deck and rebuilds the
-- Deck list (even with no Pokemon in Hand), then -- only if any cards
-- moved -- draws back exactly that many Pokemon cards from the freshly
-- shuffled Deck, stopping once that count is satisfied.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = setmetatable({ TYPE_ENERGY = 100 }, { __index = function(_, k) return k end })

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

local function newEffects(opts)
  opts = opts or {}
  local turn = "attacker"
  local swaps = 0
  local shuffleDeckCalls, createDeckCardListCalls = 0, 0
  local calls = { removed = {}, returned = {}, searched = {}, added = {} }
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
  local function writeList(list)
    for i, v in ipairs(list) do tempListWords[WDUELTEMPLIST_BASE + i - 1] = v end
    tempListWords[WDUELTEMPLIST_BASE + #list] = 0xff
  end
  local duelOps = {
    createHandCardList = function()
      local list = (opts.handBySide or {})[turn] or {}
      writeList(list)
      return list
    end,
    sortCardsInDuelTempListByID = function() end,
    removeCardFromHand = function(_, deckIndex) table.insert(calls.removed, deckIndex) end,
    returnCardToDeck = function(_, deckIndex) table.insert(calls.returned, deckIndex) end,
    shuffleDeck = function() shuffleDeckCalls = shuffleDeckCalls + 1 end,
    createDeckCardList = function()
      createDeckCardListCalls = createDeckCardListCalls + 1
      local list = (opts.deckBySide or {})[turn] or {}
      writeList(list)
      return list
    end,
    searchCardInDeckAndAddToHand = function(_, deckIndex) table.insert(calls.searched, deckIndex) end,
    addCardToHand = function(_, deckIndex) table.insert(calls.added, deckIndex) end,
  }
  local cardData = {
    getCardIDFromDeckIndex = function(_, deckIndex) return deckIndex end,
    get = function(_, cardId) return (opts.cardsById or {})[cardId] end,
  }
  local duelVars = { swapTurn = function()
    swaps = swaps + 1
    turn = (turn == "attacker") and "defender" or "attacker"
  end }
  local actor = { duelVars = duelVars, duelOps = duelOps, cardData = cardData, memory = memory }
  local effects = EffectCommands.new(memory, {}, {}, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  return effects, actor, calls, function() return swaps end,
    function() return shuffleDeckCalls end, function() return createDeckCardListCalls end
end

-- No Pokemon cards in hand: nothing moves, but the deck still gets
-- reshuffled and rebuilt for RNG parity; no redraw loop runs.
do
  local cardsById = { [1] = { type = C.TYPE_ENERGY }, [2] = { type = C.TYPE_ENERGY } }
  local effects, actor, calls, swaps, shuffleDeckCalls, createDeckCardListCalls = newEffects({
    handBySide = { defender = { 1, 2 } }, cardsById = cardsById,
  })
  local carry = effects.handlers["MixUpEffect"](effects, { combat = actor })
  check("no pokemon: carry false", carry, false)
  check("no pokemon: nothing removed from hand", #calls.removed, 0)
  check("no pokemon: nothing returned to deck", #calls.returned, 0)
  check("no pokemon: deck still reshuffled", shuffleDeckCalls(), 1)
  check("no pokemon: deck list still rebuilt", createDeckCardListCalls(), 1)
  check("no pokemon: no redraw", #calls.added, 0)
  check("no pokemon: swaps twice (bracket)", swaps(), 2)
end

-- Two Pokemon cards in hand among Energy cards: both move to the deck,
-- then exactly two Pokemon cards get drawn back, skipping non-Pokemon
-- entries and stopping once satisfied.
do
  local cardsById = {
    [10] = { type = 1 }, [11] = { type = C.TYPE_ENERGY }, [12] = { type = 1 },
    [20] = { type = C.TYPE_ENERGY }, [21] = { type = 1 }, [22] = { type = 1 }, [23] = { type = C.TYPE_ENERGY },
  }
  local effects, actor, calls, swaps, shuffleDeckCalls = newEffects({
    handBySide = { defender = { 10, 11, 12 } },
    deckBySide = { defender = { 20, 21, 22, 23 } },
    cardsById = cardsById,
  })
  local carry = effects.handlers["MixUpEffect"](effects, { combat = actor })
  check("two pokemon: carry false", carry, false)
  check("two pokemon: both removed from hand", #calls.removed, 2)
  check("two pokemon: removed the right cards", calls.removed[1], 10)
  check("two pokemon: removed the right cards (second)", calls.removed[2], 12)
  check("two pokemon: both returned to deck", #calls.returned, 2)
  check("two pokemon: deck reshuffled once", shuffleDeckCalls(), 1)
  check("two pokemon: exactly two cards redrawn", #calls.added, 2)
  check("two pokemon: skips the first energy, draws the pokemon", calls.added[1], 21)
  check("two pokemon: stops after the second pokemon (skips 23)", calls.added[2], 22)
  check("two pokemon: search-and-add pairs match", #calls.searched, 2)
  check("two pokemon: swaps twice (bracket)", swaps(), 2)
end

if failures == 0 then
  print("all mix up effect cases passed")
  os.exit(0)
else
  print(("%d mix up effect case(s) failed"):format(failures))
  os.exit(1)
end
