-- Behavioral smoke test for Jigglypuff's Friendship Song, run under real
-- LuaJIT. Closes 2 more of the card-effects backlog.
--
-- FriendshipSong_BenchCheck: fails if the attacker's own Bench is already
-- full.
-- FriendshipSong_AddToBench50PercentEffect: on heads, shuffles the
-- attacker's own Deck and adds the first Basic Pokemon found to the
-- Bench (the same shuffle-then-scan shape as Wail_FillBenchEffect's
-- fillBench, just stopping at the first match). The animation plays on
-- heads regardless of whether a Basic Pokemon turned up.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = setmetatable({
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = "DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA",
  MAX_PLAY_AREA_POKEMON = 6, TYPE_ENERGY = 100, BASIC = 0, STAGE1 = 1,
  HEADS = "HEADS", TAILS = "TAILS", ATK_ANIM_FRIENDSHIP_SONG = "ATK_ANIM_FRIENDSHIP_SONG",
  ATK_ANIM_NONE = 0,
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
  local shuffleCalls, shuffleDeckCalls, placed = 0, 0, {}
  local tempListWords = {}
  local memory = { words = {},
    readSymbol8 = function(self, n) return self.words[n] or 0 end,
    writeSymbol8 = function(self, n, v) self.words[n] = v end,
    address = function(_, symbol)
      check("addresses wDuelTempList", symbol, "wDuelTempList")
      return WDUELTEMPLIST_BASE, 0
    end,
    read8 = function(_, area, addr) return tempListWords[addr] end,
    write8 = function(_, area, addr, value) tempListWords[addr] = value end,
  }
  local setup = { tossCoin = function() return opts.coin end }
  local duelOps = {
    rng = { shuffleCards = function(_, base, count) shuffleCalls = shuffleCalls + 1 end },
    createDeckCardList = function()
      local list = opts.deckList or {}
      for i, v in ipairs(list) do tempListWords[WDUELTEMPLIST_BASE + i - 1] = v end
      tempListWords[WDUELTEMPLIST_BASE + #list] = 0xff
      return list, #list == 0
    end,
    searchCardInDeckAndAddToHand = function() end,
    addCardToHand = function() end,
    putHandPokemonCardInPlayArea = function(_, deckIndex) table.insert(placed, deckIndex) end,
    shuffleDeck = function() shuffleDeckCalls = shuffleDeckCalls + 1 end,
  }
  local cardData = {
    getCardIDFromDeckIndex = function(_, deckIndex) return deckIndex end,
    get = function(_, cardId) return (opts.cardsById or {})[cardId] end,
  }
  local duelVars = { get = function(_, addr)
    if addr == C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA then return opts.benchCount or 0 end
  end }
  local actor = { duelVars = duelVars, duelOps = duelOps, cardData = cardData, memory = memory }
  local effects = EffectCommands.new(memory, setup, {}, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  return effects, actor, function() return shuffleCalls end, function() return shuffleDeckCalls end, placed
end

-- FriendshipSong_BenchCheck
do
  local effects, actor = newEffects({ benchCount = 6 })
  check("bench full: carry true", effects.handlers["FriendshipSong_BenchCheck"](effects, { combat = actor }), true)
end
do
  local effects, actor = newEffects({ benchCount = 3 })
  check("bench has room: carry false", effects.handlers["FriendshipSong_BenchCheck"](effects, { combat = actor }), false)
end

-- Tails: no-op entirely, no shuffle at all.
do
  local effects, actor, shuffleCalls, shuffleDeckCalls, placed = newEffects({ coin = C.TAILS })
  local carry = effects.handlers["FriendshipSong_AddToBench50PercentEffect"](effects, { combat = actor })
  check("tails: carry false", carry, false)
  check("tails: no deck shuffle", shuffleCalls(), 0)
  check("tails: no deck reshuffle", shuffleDeckCalls(), 0)
  check("tails: nothing placed", #placed, 0)
end

-- Heads, a Basic Pokemon is found: placed on the Bench, animation set,
-- deck reshuffled.
do
  local cardsById = {
    [11] = { type = 1, stage = C.STAGE1 },
    [12] = { type = C.TYPE_ENERGY, stage = C.BASIC },
    [13] = { type = 1, stage = C.BASIC },
  }
  local effects, actor, shuffleCalls, shuffleDeckCalls, placed = newEffects({
    coin = C.HEADS, deckList = { 11, 12, 13 }, cardsById = cardsById,
  })
  local carry = effects.handlers["FriendshipSong_AddToBench50PercentEffect"](effects, { combat = actor })
  check("heads, found: carry false", carry, false)
  check("heads, found: deck shuffled once", shuffleCalls(), 1)
  check("heads, found: exactly one card placed", #placed, 1)
  check("heads, found: skips evolved/energy, places the basic", placed[1], 13)
  check("heads, found: sets the friendship song animation",
    effects.memory:readSymbol8("wLoadedAttackAnimation"), C.ATK_ANIM_FRIENDSHIP_SONG)
  check("heads, found: deck reshuffled afterward", shuffleDeckCalls(), 1)
end

-- Heads, no Basic Pokemon anywhere in the deck: animation still plays,
-- deck still reshuffled, nothing placed.
do
  local cardsById = { [21] = { type = 1, stage = C.STAGE1 } }
  local effects, actor, shuffleCalls, shuffleDeckCalls, placed = newEffects({
    coin = C.HEADS, deckList = { 21 }, cardsById = cardsById,
  })
  local carry = effects.handlers["FriendshipSong_AddToBench50PercentEffect"](effects, { combat = actor })
  check("heads, none found: carry false", carry, false)
  check("heads, none found: deck shuffled once", shuffleCalls(), 1)
  check("heads, none found: nothing placed", #placed, 0)
  check("heads, none found: animation still set", effects.memory:readSymbol8("wLoadedAttackAnimation"),
    C.ATK_ANIM_FRIENDSHIP_SONG)
  check("heads, none found: deck reshuffled afterward", shuffleDeckCalls(), 1)
end

-- Heads, deck is entirely empty: no shuffle attempted, still reshuffles
-- (a no-op on an empty deck) and plays the animation.
do
  local effects, actor, shuffleCalls, shuffleDeckCalls, placed = newEffects({
    coin = C.HEADS, deckList = {},
  })
  local carry = effects.handlers["FriendshipSong_AddToBench50PercentEffect"](effects, { combat = actor })
  check("heads, empty deck: carry false", carry, false)
  check("heads, empty deck: no shuffle call (deck already empty)", shuffleCalls(), 0)
  check("heads, empty deck: nothing placed", #placed, 0)
  check("heads, empty deck: still reshuffles", shuffleDeckCalls(), 1)
end

if failures == 0 then
  print("all friendship song effect cases passed")
  os.exit(0)
else
  print(("%d friendship song effect case(s) failed"):format(failures))
  os.exit(1)
end
