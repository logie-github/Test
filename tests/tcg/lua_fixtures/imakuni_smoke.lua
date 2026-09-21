-- Behavioral smoke test for Imakuni?'s AI decision (AIDecide_Imakuni,
-- trainer_cards.asm), run under real LuaJIT rather than only checked as
-- source text: plays whenever the Active isn't already Confused, and does
-- NOT try to avoid its own self-inflicted downside.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  DUELVARS_ARENA_CARD_STATUS = 0x10,
  CNF_SLP_PRZ = 0x07, CONFUSED = 0x01, PARALYZED = 0x02, ASLEEP = 0x04, NO_STATUS = 0,
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

local function newAI(status)
  return AI.new(
    { readSymbol8 = function() return 0 end, writeSymbol8 = function() end },
    {
      get = function(_, addr) return addr == C.DUELVARS_ARENA_CARD_STATUS and status or nil end,
      getNonTurn = function() return nil end,
    },
    { random = function() return 5 end },
    { getCardIDFromDeckIndex = function() return nil end, get = function() return nil end },
    {},
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
end

check("no status -> plays", newAI(C.NO_STATUS):_decideImakuni(), true)
check("already confused -> does not play", newAI(C.CONFUSED):_decideImakuni(), false)
check("asleep (not confused) -> plays anyway", newAI(C.ASLEEP):_decideImakuni(), true)
check("paralyzed (not confused) -> plays anyway", newAI(C.PARALYZED):_decideImakuni(), true)

if failures == 0 then
  print("all Imakuni AI decision cases passed")
  os.exit(0)
else
  print(("%d Imakuni AI decision case(s) failed"):format(failures))
  os.exit(1)
end
