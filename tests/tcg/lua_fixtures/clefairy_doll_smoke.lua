-- Behavioral smoke test for Clefairy Doll / Mysterious Fossil's shared AI
-- decision (AIDecide_ClefairyDollOrMysteriousFossil, trainer_cards.asm), run
-- under real LuaJIT rather than only checked as source text: the hard-max
-- Play Area gate, the Wigglytuff-Active override (bypasses the <4 rule), and
-- the ordinary <4-Pokemon threshold.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  MAX_PLAY_AREA_POKEMON = 5,
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = 0x10,
  DUELVARS_ARENA_CARD = 0x20,
  WIGGLYTUFF = 400, BULBASAUR = 300,
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
    { get = function(_, addr) return (opts.turn or {})[addr] end, getNonTurn = function() return nil end },
    { random = function() return 5 end },
    { getCardIDFromDeckIndex = function(_, deckIndex) return (opts.deckIndexToCardId or {})[deckIndex] end,
      get = function() return nil end },
    {},
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
end

-- At the hard max (5) -> never plays, even with Wigglytuff active.
do
  local ai = newAI({
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 5, [C.DUELVARS_ARENA_CARD] = 1 },
    deckIndexToCardId = { [1] = C.WIGGLYTUFF },
  })
  check("at hard max -> never plays even with Wigglytuff active",
    ai:_decideClefairyDollOrMysteriousFossil(), false)
end

-- Below hard max, Active is Wigglytuff, count already at 4 -> plays anyway
-- (Wigglytuff bypasses the ordinary <4 rule).
do
  local ai = newAI({
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 4, [C.DUELVARS_ARENA_CARD] = 1 },
    deckIndexToCardId = { [1] = C.WIGGLYTUFF },
  })
  check("Wigglytuff active bypasses the <4 rule", ai:_decideClefairyDollOrMysteriousFossil(), true)
end

-- Not Wigglytuff, count is 4 (not <4) -> does not play.
do
  local ai = newAI({
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 4, [C.DUELVARS_ARENA_CARD] = 1 },
    deckIndexToCardId = { [1] = C.BULBASAUR },
  })
  check("non-Wigglytuff active, count=4 -> does not play",
    ai:_decideClefairyDollOrMysteriousFossil(), false)
end

-- Not Wigglytuff, count is 3 (<4) -> plays.
do
  local ai = newAI({
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 3, [C.DUELVARS_ARENA_CARD] = 1 },
    deckIndexToCardId = { [1] = C.BULBASAUR },
  })
  check("non-Wigglytuff active, count=3 -> plays", ai:_decideClefairyDollOrMysteriousFossil(), true)
end

if failures == 0 then
  print("all Clefairy Doll / Mysterious Fossil AI decision cases passed")
  os.exit(0)
else
  print(("%d Clefairy Doll / Mysterious Fossil AI decision case(s) failed"):format(failures))
  os.exit(1)
end
