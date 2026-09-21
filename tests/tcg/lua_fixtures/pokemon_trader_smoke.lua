-- Behavioral smoke test for Pokemon Trader's AI decision boundary
-- (AIDecide_PokemonTrader, trainer_cards.asm), run under real LuaJIT
-- rather than only checked as source text: fails closed for each of the
-- ten decks with their own untranslated card-search routine, and never
-- plays for any other deck (the source has no general path at all).

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  LEGENDARY_MOLTRES_DECK_ID = 601, LEGENDARY_ARTICUNO_DECK_ID = 602,
  LEGENDARY_DRAGONITE_DECK_ID = 603, LEGENDARY_RONALD_DECK_ID = 604,
  BLISTERING_POKEMON_DECK_ID = 605, SOUND_OF_THE_WAVES_DECK_ID = 606,
  POWER_GENERATOR_DECK_ID = 607, FLOWER_GARDEN_DECK_ID = 608,
  STRANGE_POWER_DECK_ID = 609, FLAMETHROWER_DECK_ID = 610,
  ORDINARY_DECK_ID = 1,
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

local function newAI(deckId)
  return AI.new(
    { readSymbol8 = function(_, name) return name == "wOpponentDeckID" and deckId or 0 end,
      writeSymbol8 = function() end },
    { get = function() return nil end, getNonTurn = function() return nil end },
    { random = function() return 5 end },
    { getCardIDFromDeckIndex = function() return nil end, get = function() return nil end },
    {},
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
end

check("ordinary deck -> never plays (no general path exists)",
  newAI(C.ORDINARY_DECK_ID):_decidePokemonTrader(), false)

for _, deckId in ipairs({
  C.LEGENDARY_MOLTRES_DECK_ID, C.LEGENDARY_ARTICUNO_DECK_ID, C.LEGENDARY_DRAGONITE_DECK_ID,
  C.LEGENDARY_RONALD_DECK_ID, C.BLISTERING_POKEMON_DECK_ID, C.SOUND_OF_THE_WAVES_DECK_ID,
  C.POWER_GENERATOR_DECK_ID, C.FLOWER_GARDEN_DECK_ID, C.STRANGE_POWER_DECK_ID,
  C.FLAMETHROWER_DECK_ID,
}) do
  local ai = newAI(deckId)
  local decided, err = ai:_decidePokemonTrader()
  check(("specialized deck %d fails closed"):format(deckId), decided, nil)
  check(("specialized deck %d error reason"):format(deckId), err,
    "untranslated_ai_pokemon_trader_special_deck")
end

if failures == 0 then
  print("all Pokemon Trader AI decision cases passed")
  os.exit(0)
else
  print(("%d Pokemon Trader AI decision case(s) failed"):format(failures))
  os.exit(1)
end
