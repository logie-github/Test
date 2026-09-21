-- Behavioral smoke test for Lass's AI decision (AIDecide_Lass,
-- trainer_cards.asm), run under real LuaJIT rather than only checked as
-- source text: the opponent-hand-size gate, and the own-hand Trainer scan
-- that excludes Lass itself by card ID (not by hand position).

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x10, DUELVARS_HAND = 0x11,
  TYPE_TRAINER = 9, TYPE_ENERGY = 8,
  LASS = 100, BILL = 101, POTION = 102, FIRE_ENERGY = 200, BULBASAUR = 300,
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

local function newAI(opts)
  opts = opts or {}
  return AI.new(
    { readSymbol8 = function() return 0 end, writeSymbol8 = function() end },
    {
      get = function(_, addr) return (opts.turn or {})[addr] end,
      getNonTurn = function(_, addr) return (opts.nonTurn or {})[addr] end,
      swapTurn = function() end,
    },
    { random = function() return 5 end },
    {
      getCardIDFromDeckIndex = function(_, deckIndex) return (opts.deckIndexToCardId or {})[deckIndex] end,
      get = function(_, cardId) return (opts.cardRows or {})[cardId] end,
    },
    { createHandCardList = function() return opts.hand or {} end },
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
end

-- Opponent has fewer than 7 cards -> never play, regardless of own hand.
do
  local ai = newAI({ nonTurn = { [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 6 }, hand = {} })
  check("opponent hand < 7 -> no play", ai:_decideLass(), false)
end

-- Opponent has exactly 7 cards, AI's own hand has only Lass copies and
-- non-Trainer cards -> play.
do
  local ai = newAI({
    nonTurn = { [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 7 },
    hand = { 1, 2, 3 },
    deckIndexToCardId = { [1] = C.LASS, [2] = C.LASS, [3] = C.FIRE_ENERGY },
    cardRows = { [C.LASS] = { type = C.TYPE_TRAINER }, [C.FIRE_ENERGY] = { type = C.TYPE_ENERGY } },
  })
  check("opponent>=7, own hand has no OTHER Trainer -> plays", ai:_decideLass(), true)
end

-- Own hand has a non-Lass Trainer card (Bill) -> don't play, even though
-- opponent qualifies.
do
  local ai = newAI({
    nonTurn = { [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 9 },
    hand = { 1, 4 },
    deckIndexToCardId = { [1] = C.LASS, [4] = C.BILL },
    cardRows = { [C.LASS] = { type = C.TYPE_TRAINER }, [C.BILL] = { type = C.TYPE_TRAINER } },
  })
  check("own hand has another Trainer (Bill) -> does not play", ai:_decideLass(), false)
end

-- Own hand has Basic Pokemon and Energy cards only (no Trainer at all,
-- besides Lass) -> play.
do
  local ai = newAI({
    nonTurn = { [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 10 },
    hand = { 1, 5, 6 },
    deckIndexToCardId = { [1] = C.LASS, [5] = C.BULBASAUR, [6] = C.FIRE_ENERGY },
    cardRows = {
      [C.LASS] = { type = C.TYPE_TRAINER },
      [C.BULBASAUR] = { type = 0 },
      [C.FIRE_ENERGY] = { type = C.TYPE_ENERGY },
    },
  })
  check("own hand has only Pokemon/Energy besides Lass -> plays", ai:_decideLass(), true)
end

if failures == 0 then
  print("all Lass AI decision cases passed")
  os.exit(0)
else
  print(("%d Lass AI decision case(s) failed"):format(failures))
  os.exit(1)
end
