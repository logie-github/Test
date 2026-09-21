-- Behavioral smoke test for AI:_chooseRandomlyNotToDoAction
-- (engine/duel/ai/core.asm AIChooseRandomlyNotToDoAction /
-- CheckIfNotABossDeckID / CheckIfOpponentHasBossDeckID), run under real
-- LuaJIT. Closes out the "exact random-skip cadence" half of the last open
-- item on the shared Potion/Defender/PlusPower/Switch/FullHeal/EnergySearch
-- trainer_cards.asm ledger entry: proves the exact probability table (0%
-- for boss decks or once Legendary Cards are received, 50% for the six
-- listed decks, 25% for everything else) and the exact deck-ID boundaries
-- (LEGENDARY_MOLTRES_DECK_ID <= id < MUSCLES_FOR_BRAINS_DECK_ID is the
-- suppressed boss range) under real execution, not just by reading the loop.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  LEGENDARY_MOLTRES_DECK_ID = 10, MUSCLES_FOR_BRAINS_DECK_ID = 20,
  BLISTERING_POKEMON_DECK_ID = 21, WATERFRONT_POKEMON_DECK_ID = 22,
  BOOM_BOOM_SELFDESTRUCT_DECK_ID = 23, KALEIDOSCOPE_DECK_ID = 24,
  RESHUFFLE_DECK_ID = 25,
  SOME_OTHER_DECK_ID = 30,
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

-- opts.receivedLegendaryCards, opts.deckId, opts.roll (what rng:random(4) returns).
local function newAI(opts)
  local words = { wOpponentDeckID = opts.deckId }
  if opts.receivedLegendaryCards ~= nil then
    words.sReceivedLegendaryCards = opts.receivedLegendaryCards
  end
  local memory = {
    readSymbol8 = function(_, name)
      if name == "sReceivedLegendaryCards" and opts.receivedLegendaryCards == nil then
        error("sReceivedLegendaryCards not present (fresh/sparse SRAM)")
      end
      return words[name] or 0
    end,
    writeSymbol8 = function(_, name, v) words[name] = v end,
  }
  return AI.new(
    memory,
    { get = function() return 0 end, getNonTurn = function() return 0 end, swapTurn = function() end },
    { random = function(_, n) return opts.roll or 0 end },
    { getCardIDFromDeckIndex = function() return nil end, get = function() return nil end },
    {},
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
end

-- Legendary Cards already received -> never randomly skip, regardless of deck/roll.
do
  local ai = newAI({ receivedLegendaryCards = 1, deckId = C.SOME_OTHER_DECK_ID, roll = 0 })
  check("Legendary Cards received: never skips", ai:_chooseRandomlyNotToDoAction(), false)
end

-- Boss deck ID range (inclusive start, exclusive end) -> never randomly skip.
do
  local ai = newAI({ receivedLegendaryCards = 0, deckId = C.LEGENDARY_MOLTRES_DECK_ID, roll = 0 })
  check("boss deck ID (range start): never skips", ai:_chooseRandomlyNotToDoAction(), false)
end
do
  local ai = newAI({ receivedLegendaryCards = 0, deckId = C.MUSCLES_FOR_BRAINS_DECK_ID - 1, roll = 0 })
  check("boss deck ID (range end - 1): never skips", ai:_chooseRandomlyNotToDoAction(), false)
end
do
  -- MUSCLES_FOR_BRAINS_DECK_ID itself is NOT in the boss range (exclusive
  -- end) -- it's one of the six 50%-chance decks instead.
  local ai = newAI({ receivedLegendaryCards = 0, deckId = C.MUSCLES_FOR_BRAINS_DECK_ID, roll = 1 })
  check("MUSCLES_FOR_BRAINS_DECK_ID itself: NOT boss range, rolls 50% instead",
    ai:_chooseRandomlyNotToDoAction(), true)
end

-- 50%-list decks: roll<2 skips, roll>=2 does not.
for _, deckId in ipairs({
  C.MUSCLES_FOR_BRAINS_DECK_ID, C.BLISTERING_POKEMON_DECK_ID, C.WATERFRONT_POKEMON_DECK_ID,
  C.BOOM_BOOM_SELFDESTRUCT_DECK_ID, C.KALEIDOSCOPE_DECK_ID, C.RESHUFFLE_DECK_ID,
}) do
  local aiSkip = newAI({ receivedLegendaryCards = 0, deckId = deckId, roll = 1 })
  check(("50%%-list deck %d: roll=1 -> skip"):format(deckId), aiSkip:_chooseRandomlyNotToDoAction(), true)
  local aiNoSkip = newAI({ receivedLegendaryCards = 0, deckId = deckId, roll = 2 })
  check(("50%%-list deck %d: roll=2 -> no skip"):format(deckId), aiNoSkip:_chooseRandomlyNotToDoAction(), false)
end

-- Any other (non-boss, non-listed) deck: only roll==0 skips (25% chance).
do
  local aiSkip = newAI({ receivedLegendaryCards = 0, deckId = C.SOME_OTHER_DECK_ID, roll = 0 })
  check("other deck: roll=0 -> skip (25%)", aiSkip:_chooseRandomlyNotToDoAction(), true)
  local aiNoSkip = newAI({ receivedLegendaryCards = 0, deckId = C.SOME_OTHER_DECK_ID, roll = 1 })
  check("other deck: roll=1 -> no skip", aiNoSkip:_chooseRandomlyNotToDoAction(), false)
end

-- Fresh/sparse SRAM (sReceivedLegendaryCards never written) treats it as zero
-- rather than erroring, matching real hardware's zeroed-fresh-SRAM behavior.
do
  local ai = newAI({ receivedLegendaryCards = nil, deckId = C.SOME_OTHER_DECK_ID, roll = 0 })
  check("uninitialized sReceivedLegendaryCards treated as zero", ai:_chooseRandomlyNotToDoAction(), true)
end

if failures == 0 then
  print("all random action-skip cadence cases passed")
  os.exit(0)
else
  print(("%d random action-skip cadence case(s) failed"):format(failures))
  os.exit(1)
end
