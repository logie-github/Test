-- Behavioral smoke test for Imposter Professor Oak's AI decision arithmetic
-- (AIDecide_ImposterProfessorOak, trainer_cards.asm), run under real LuaJIT
-- rather than only checked as source text. Both counts come from the
-- NON-turn duelist (the human opponent), so this exercises AI.lua's
-- getNonTurn wiring, not just the threshold comparisons themselves.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  DECK_SIZE = 60,
  DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK = 0x10,
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x20,
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

local function newAI(nonTurn)
  return AI.new(
    { readSymbol8 = function() return 0 end, writeSymbol8 = function() end },
    {
      get = function() return nil end,
      getNonTurn = function(_, addr) return nonTurn[addr] end,
      swapTurn = function() end,
    },
    { random = function() return 5 end },
    { getCardIDFromDeckIndex = function() return nil end, get = function() return nil end },
    {},
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
end

-- Opponent has 20 cards not in deck -> 40 still in deck (<=14? no, >14) ->
-- ".more_than_14_cards" branch: play only if hand count >= 9.
do
  local ai = newAI({ [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 20, [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 8 })
  check("many-in-deck branch: hand=8 (<9) does not play", ai:_decideImposterProfessorOak(), false)
end
do
  local ai = newAI({ [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 20, [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 9 })
  check("many-in-deck branch: hand=9 (>=9) plays", ai:_decideImposterProfessorOak(), true)
end

-- Opponent has 50 cards not in deck -> 10 still in deck (<=14) ->
-- fallthrough branch: play only if hand count < 6.
do
  local ai = newAI({ [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 50, [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 6 })
  check("few-in-deck branch: hand=6 (not <6) does not play", ai:_decideImposterProfessorOak(), false)
end
do
  local ai = newAI({ [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 50, [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 5 })
  check("few-in-deck branch: hand=5 (<6) plays", ai:_decideImposterProfessorOak(), true)
end

-- Exact boundary: notInDeck == DECK_SIZE - 14 (46) falls into the
-- "<=14 remaining" branch (the source's `cp`/`jr c` is a strict-less-than
-- carry test, so equality does NOT take the more_than_14_cards branch).
do
  local ai = newAI({ [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 46, [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 5 })
  check("boundary: exactly 14 left in deck uses the few-in-deck (<6) rule", ai:_decideImposterProfessorOak(), true)
end

if failures == 0 then
  print("all Imposter Professor Oak AI decision cases passed")
  os.exit(0)
else
  print(("%d Imposter Professor Oak AI decision case(s) failed"):format(failures))
  os.exit(1)
end
