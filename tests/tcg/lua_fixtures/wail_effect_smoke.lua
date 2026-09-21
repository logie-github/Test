-- Behavioral smoke test for Wail, run under real LuaJIT. Closes 2 more of
-- the card-effects backlog.
--
-- Wail_BenchCheck: fails only if BOTH players' Benches are already full.
-- Wail_FillBenchEffect: fills each player's Bench (opponent first, then
-- the attacker's own, matching the source's SwapTurn/.FillBench/SwapTurn/
-- .FillBench order for RNG parity) with Basic Pokemon shuffled out of that
-- player's own Deck, stopping once the Bench is full or the shuffled Deck
-- list runs out; always reshuffles the remaining Deck afterward, unless
-- that side's Deck was empty to begin with.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = setmetatable({
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = "DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA",
  MAX_PLAY_AREA_POKEMON = 6, TYPE_ENERGY = 100, BASIC = 0, STAGE1 = 1,
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

local function newEffects(opts)
  opts = opts or {}
  local turn = "attacker"
  local swaps = 0
  local shuffleCalls = {}
  local shuffleDeckCalls = { attacker = 0, defender = 0 }
  local placedBySide = { attacker = {}, defender = {} }
  local benchCounts = { attacker = opts.benchCounts and opts.benchCounts.attacker or 0,
    defender = opts.benchCounts and opts.benchCounts.defender or 0 }
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

  local duelOps = {
    rng = { shuffleCards = function(_, base, count)
      shuffleCalls[#shuffleCalls + 1] = { side = turn, base = base, count = count }
    end },
    createDeckCardList = function()
      local list = (opts.deckListsBySide or {})[turn] or {}
      for i, v in ipairs(list) do tempListWords[WDUELTEMPLIST_BASE + i - 1] = v end
      tempListWords[WDUELTEMPLIST_BASE + #list] = 0xff
      return list, #list == 0
    end,
    searchCardInDeckAndAddToHand = function() end,
    addCardToHand = function() end,
    putHandPokemonCardInPlayArea = function(_, deckIndex)
      table.insert(placedBySide[turn], deckIndex)
    end,
    shuffleDeck = function() shuffleDeckCalls[turn] = shuffleDeckCalls[turn] + 1 end,
  }

  local cardData = {
    getCardIDFromDeckIndex = function(_, deckIndex) return deckIndex end,
    get = function(_, cardId) return (opts.cardsById or {})[cardId] end,
  }

  local duelVars = {
    swapTurn = function()
      swaps = swaps + 1
      turn = (turn == "attacker") and "defender" or "attacker"
    end,
    get = function(_, addr)
      if addr == C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA then
        return benchCounts[turn] + #placedBySide[turn]
      end
    end,
    getNonTurn = function(_, addr)
      if addr == C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA then
        local other = (turn == "attacker") and "defender" or "attacker"
        return benchCounts[other] + #placedBySide[other]
      end
    end,
  }

  local actor = { duelVars = duelVars, duelOps = duelOps, cardData = cardData, memory = memory }
  local effects = EffectCommands.new(memory, {}, {}, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  return effects, actor, placedBySide, shuffleCalls, shuffleDeckCalls, function() return swaps end
end

-- Wail_BenchCheck
do
  local effects, actor = newEffects({ benchCounts = { attacker = 6, defender = 6 } })
  check("both full: carry true", effects.handlers["Wail_BenchCheck"](effects, { combat = actor }), true)
end
do
  local effects, actor = newEffects({ benchCounts = { attacker = 3, defender = 6 } })
  check("own has room: carry false", effects.handlers["Wail_BenchCheck"](effects, { combat = actor }), false)
end
do
  local effects, actor = newEffects({ benchCounts = { attacker = 6, defender = 2 } })
  check("opponent has room: carry false", effects.handlers["Wail_BenchCheck"](effects, { combat = actor }), false)
end

-- Wail_FillBenchEffect: opponent filled first, then own side; only Basics
-- get placed, and placement stops once the Bench is full.
do
  local cardsById = {
    [10] = { type = 1, stage = C.BASIC },   -- basic
    [11] = { type = 1, stage = C.STAGE1 },  -- evolved, skipped
    [12] = { type = C.TYPE_ENERGY, stage = C.BASIC }, -- energy, skipped
    [13] = { type = 1, stage = C.BASIC },   -- basic
    [14] = { type = 1, stage = C.BASIC },   -- basic (should never be reached: bench fills first)
    [20] = { type = 1, stage = C.BASIC },
  }
  local effects, actor, placedBySide, shuffleCalls, shuffleDeckCalls, swapCount = newEffects({
    benchCounts = { attacker = 4, defender = 5 },
    deckListsBySide = { attacker = { 10, 11, 12, 13, 14 }, defender = { 20 } },
    cardsById = cardsById,
  })
  local carry = effects.handlers["Wail_FillBenchEffect"](effects, { combat = actor })
  check("fill: carry false", carry, false)
  check("fill: swaps twice (net back to attacker)", swapCount(), 2)
  check("fill: opponent side processed first", shuffleCalls[1].side, "defender")
  check("fill: attacker side processed second", shuffleCalls[2].side, "attacker")
  check("fill: opponent gets its one basic", #placedBySide.defender, 1)
  check("fill: opponent's placed card is the basic", placedBySide.defender[1], 20)
  check("fill: attacker fills only up to Bench capacity (2 slots free)", #placedBySide.attacker, 2)
  check("fill: attacker's first placement skips the evolved/energy cards", placedBySide.attacker[1], 10)
  check("fill: attacker's second placement is the next basic", placedBySide.attacker[2], 13)
  check("fill: both sides reshuffle their remaining deck", shuffleDeckCalls.attacker, 1)
  check("fill: both sides reshuffle their remaining deck (defender)", shuffleDeckCalls.defender, 1)
end

-- Empty deck on one side: no shuffle, no placement, no reshuffle for it.
do
  local effects, actor, placedBySide, shuffleCalls, shuffleDeckCalls, swapCount = newEffects({
    benchCounts = { attacker = 0, defender = 0 },
    deckListsBySide = { attacker = {}, defender = {} },
  })
  local carry = effects.handlers["Wail_FillBenchEffect"](effects, { combat = actor })
  check("empty decks: carry false", carry, false)
  check("empty decks: no shuffle calls", #shuffleCalls, 0)
  check("empty decks: no placements on either side", #placedBySide.attacker + #placedBySide.defender, 0)
  check("empty decks: no reshuffle calls", shuffleDeckCalls.attacker + shuffleDeckCalls.defender, 0)
  check("empty decks: still swaps twice", swapCount(), 2)
end

if failures == 0 then
  print("all wail effect cases passed")
  os.exit(0)
else
  print(("%d wail effect case(s) failed"):format(failures))
  os.exit(1)
end
