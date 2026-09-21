-- Behavioral smoke test for Computer Search's AI decision boundary
-- (AIDecide_ComputerSearch, trainer_cards.asm), run under real LuaJIT
-- rather than only checked as source text: the deck-agnostic hand-count
-- gate, the fail-closed veto for each of the four specialized decks with
-- their own untranslated multi-branch search routines, and correct no-op
-- behavior for every other deck (which the real ASM never plays this
-- against at all, regardless of hand size).

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x10,
  ROCK_CRUSHER_DECK_ID = 501, WONDERS_OF_SCIENCE_DECK_ID = 502,
  FIRE_CHARGE_DECK_ID = 503, ANGER_DECK_ID = 504,
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

local function newAI(opts)
  opts = opts or {}
  return AI.new(
    { readSymbol8 = function(_, name) return (opts.symbols or {})[name] or 0 end, writeSymbol8 = function() end },
    { get = function(_, addr) return (opts.turn or {})[addr] end, getNonTurn = function() return nil end },
    { random = function() return 5 end },
    { getCardIDFromDeckIndex = function() return nil end, get = function() return nil end },
    {},
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
end

check("hand < 3 cards -> never plays, even for a specialized deck",
  newAI({ turn = { [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 2 },
    symbols = { wOpponentDeckID = C.ROCK_CRUSHER_DECK_ID } }):_decideComputerSearch(), false)

check("hand >= 3, ordinary deck -> never plays (no general path exists)",
  newAI({ turn = { [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 5 },
    symbols = { wOpponentDeckID = C.ORDINARY_DECK_ID } }):_decideComputerSearch(), false)

for _, deckId in ipairs({ C.ROCK_CRUSHER_DECK_ID, C.WONDERS_OF_SCIENCE_DECK_ID,
    C.FIRE_CHARGE_DECK_ID, C.ANGER_DECK_ID }) do
  local ai = newAI({ turn = { [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 5 },
    symbols = { wOpponentDeckID = deckId } })
  local decided, err = ai:_decideComputerSearch()
  check(("hand >= 3, specialized deck %d fails closed"):format(deckId), decided, nil)
  check(("hand >= 3, specialized deck %d error reason"):format(deckId), err,
    "untranslated_ai_computer_search_special_deck")
end

if failures == 0 then
  print("all Computer Search AI decision cases passed")
  os.exit(0)
else
  print(("%d Computer Search AI decision case(s) failed"):format(failures))
  os.exit(1)
end
