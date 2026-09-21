-- Behavioral smoke test for the Mewtwo Lv53 mill-deck detector
-- (InitAITurnVars / CheckIfPlayerHasPokemonOtherThanMewtwoLv53,
-- engine/duel/ai/{init,common}.asm), run under real LuaJIT.
--
-- Before this change, AI:initTurnVars() delegated the "is the Player really
-- running a MewtwoLv53-only deck" question to self.adapters.
-- checkPlayerMewtwoMillDeck, an adapter nothing ever wired up -- so the
-- AI_MEWTWO_MILL flag (read by Gambler's decision and by two other already-
-- translated spots) could increment the turn counter but could never
-- actually get set. This fixture proves the native replacement (the arena-
-- card-is-MewtwoLv53 gate plus the full 60-card deck scan) both sets and
-- un-sets the flag under the real conditions from the source, including the
-- "flag already set, Player still complying" refresh-to-exactly-$80 case
-- that a naive increment would get wrong.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  MEWTWO_LV53 = 1,
  DECK_SIZE = 60,
  TYPE_ENERGY = 8,
  DUELVARS_ARENA_CARD = 0x10,
  AI_MEWTWO_MILL_F = 7,
  AI_MEWTWO_MILL = 0x80,
}

local FIRE_ENERGY = 900
local BULBASAUR = 901

local CARD_ROWS = {
  [C.MEWTWO_LV53] = { type = 0 },
  [FIRE_ENERGY] = { type = C.TYPE_ENERGY },
  [BULBASAUR] = { type = 0 },
}

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(("FAIL  %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
  else
    print(("ok    %s"):format(label))
  end
end

-- deckCardIds: sparse map of physical deckIndex -> cardId. Any index not
-- given defaults to FIRE_ENERGY (never counts as "another Pokemon").
local function newAI(symbols, deckCardIds, arenaDeckIndex)
  local swapCount = 0
  local memory = {
    readSymbol8 = function(_, name) return symbols[name] or 0 end,
    writeSymbol8 = function(_, name, v) symbols[name] = v end,
  }
  local duelVars = {
    get = function() return 0 end,
    getNonTurn = function(_, offset)
      check("getNonTurn called with DUELVARS_ARENA_CARD", offset, C.DUELVARS_ARENA_CARD)
      return arenaDeckIndex
    end,
    swapTurn = function() swapCount = swapCount + 1 end,
  }
  local cardData = {
    getCardIDFromDeckIndex = function(_, deckIndex)
      return deckCardIds[deckIndex] or FIRE_ENERGY
    end,
    get = function(_, cardId) return CARD_ROWS[cardId] end,
  }
  local ai = AI.new(memory, duelVars, { random = function() return 0 end },
    cardData, {}, C, { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} }, {})
  return ai, function() return swapCount end
end

-- ---------------------------------------------------------------------
-- No Barrier used last turn.
-- ---------------------------------------------------------------------
do
  local ai = newAI({ wPlayerAttackingAttackIndex = 0xff, wAIBarrierFlagCounter = 0 }, {}, 0)
  ai:initTurnVars()
  check("no attack last turn, flag unset -> counter stays 0",
    ai.memory:readSymbol8("wAIBarrierFlagCounter"), 0)
end
do
  local ai = newAI({ wPlayerAttackingAttackIndex = 0xff, wAIBarrierFlagCounter = C.AI_MEWTWO_MILL },
    {}, 0)
  ai:initTurnVars()
  check("no attack last turn, flag SET -> counter increments (keeps flag bit)",
    ai.memory:readSymbol8("wAIBarrierFlagCounter"), C.AI_MEWTWO_MILL + 1)
end

-- ---------------------------------------------------------------------
-- Barrier used, but fewer than 3 turns in a row so far: no arena check yet.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    wPlayerAttackingAttackIndex = 1, wPlayerAttackingCardIndex = 3,
    wAIBarrierFlagCounter = 1,
  }, { [3] = C.MEWTWO_LV53 }, 0)
  ai:initTurnVars()
  check("2nd consecutive Barrier turn -> counter is just 2 (below 3, no arena/deck check yet)",
    ai.memory:readSymbol8("wAIBarrierFlagCounter"), 2)
end

-- ---------------------------------------------------------------------
-- Barrier used a 3rd consecutive time: arena-card gate + full deck scan.
-- ---------------------------------------------------------------------
do
  -- Arena is MewtwoLv53, and no other Pokemon anywhere in the 60-card deck.
  local deck = { [3] = C.MEWTWO_LV53, [40] = C.MEWTWO_LV53 }
  local ai = newAI({
    wPlayerAttackingAttackIndex = 1, wPlayerAttackingCardIndex = 3,
    wAIBarrierFlagCounter = 2,
  }, deck, 40)
  ai:initTurnVars()
  check("3rd Barrier turn, Arena=Mewtwo, deck is Mewtwo-only -> AI_MEWTWO_MILL flag set",
    ai.memory:readSymbol8("wAIBarrierFlagCounter"), C.AI_MEWTWO_MILL)
end
do
  -- Arena is MewtwoLv53, but the deck also has a Bulbasaur somewhere.
  local deck = { [3] = C.MEWTWO_LV53, [40] = C.MEWTWO_LV53, [10] = BULBASAUR }
  local ai = newAI({
    wPlayerAttackingAttackIndex = 1, wPlayerAttackingCardIndex = 3,
    wAIBarrierFlagCounter = 2,
  }, deck, 40)
  ai:initTurnVars()
  check("3rd Barrier turn, Arena=Mewtwo, deck has another Pokemon -> counter reset to 0",
    ai.memory:readSymbol8("wAIBarrierFlagCounter"), 0)
end
do
  -- Arena card is NOT MewtwoLv53 at the moment of the check.
  local deck = { [3] = C.MEWTWO_LV53, [40] = BULBASAUR }
  local ai = newAI({
    wPlayerAttackingAttackIndex = 1, wPlayerAttackingCardIndex = 3,
    wAIBarrierFlagCounter = 2,
  }, deck, 40)
  ai:initTurnVars()
  check("3rd Barrier turn, Arena is not Mewtwo -> counter reset to 0",
    ai.memory:readSymbol8("wAIBarrierFlagCounter"), 0)
end

-- ---------------------------------------------------------------------
-- Flag already set, and Player still complying (Barrier used again): the
-- source refreshes the byte to exactly $80, not a plain increment.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    wPlayerAttackingAttackIndex = 1, wPlayerAttackingCardIndex = 3,
    wAIBarrierFlagCounter = C.AI_MEWTWO_MILL + 5,
  }, { [3] = C.MEWTWO_LV53 }, 0)
  ai:initTurnVars()
  check("flag already set + Barrier used again -> refreshed to exactly AI_MEWTWO_MILL",
    ai.memory:readSymbol8("wAIBarrierFlagCounter"), C.AI_MEWTWO_MILL)
end

-- ---------------------------------------------------------------------
-- _checkIfPlayerHasPokemonOtherThanMewtwoLv53 directly, including that
-- SwapTurn is called in pairs (the real bug class this pattern risks: an
-- unbalanced swap would leave the AI computing everything after this call
-- from the wrong duelist's page for the rest of the turn).
-- ---------------------------------------------------------------------
do
  local ai, swaps = newAI({}, { [0] = C.MEWTWO_LV53, [59] = C.MEWTWO_LV53 }, 0)
  check("pure Mewtwo deck -> no other Pokemon found",
    ai:_checkIfPlayerHasPokemonOtherThanMewtwoLv53(), false)
  check("swapTurn called in a balanced pair", swaps(), 2)
end
do
  local ai, swaps = newAI({}, { [0] = C.MEWTWO_LV53, [59] = BULBASAUR }, 0)
  check("Bulbasaur present at deck index 59 -> other Pokemon found",
    ai:_checkIfPlayerHasPokemonOtherThanMewtwoLv53(), true)
  check("swapTurn called in a balanced pair even on early return", swaps(), 2)
end

if failures == 0 then
  print("all Mewtwo Lv53 mill detector cases passed")
  os.exit(0)
else
  print(("%d Mewtwo Lv53 mill detector case(s) failed"):format(failures))
  os.exit(1)
end
