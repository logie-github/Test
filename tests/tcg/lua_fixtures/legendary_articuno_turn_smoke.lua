-- Behavioral smoke test for AIDoTurn_LegendaryArticuno
-- (engine/duel/ai/decks/legendary_articuno.asm), run under real LuaJIT.
--
-- Fourth of the five Legendary bosses' bespoke turn logic, and the
-- simplest: phase 01 runs before the anti-Mewtwo-mill check (like
-- Dragonite's), and there is NO bespoke Energy-attach branch at all --
-- Articuno's whole specialization (ScoreLegendaryArticunoCards) already
-- lives inside the common energy-scoring pipeline via the already-
-- translated AI:_legendaryArticunoEnergyDeltas, so this routine just calls
-- the ordinary processAndTryToPlayEnergy. It has a Professor-Oak repeat
-- pass (phases 01/02, play, retreat, 10, energy, play again -- no phase
-- 13/15 on the repeat, unlike phase 15 appearing once on the first pass).

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  AI_TRAINER_CARD_PHASE_01 = 1, AI_TRAINER_CARD_PHASE_02 = 2,
  AI_TRAINER_CARD_PHASE_10 = 10, AI_TRAINER_CARD_PHASE_13 = 13,
  AI_TRAINER_CARD_PHASE_15 = 15,
  AI_FLAG_USED_PROFESSOR_OAK = 0x04,
}

local failures = 0
local function arraysEqual(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
local function fmt(v)
  if type(v) == "table" then return "{" .. table.concat(v, ",") .. "}" end
  return tostring(v)
end
local function check(label, got, want)
  local equal
  if type(got) == "table" or type(want) == "table" then equal = arraysEqual(got, want)
  else equal = got == want end
  if not equal then
    failures = failures + 1
    print(("FAIL  %s: got %s, want %s"):format(label, fmt(got), fmt(want)))
  else
    print(("ok    %s"):format(label))
  end
end

-- opts.alreadyPlayedEnergy, opts.antiMillOk, opts.usedProfessorOak
local function newAI(opts)
  local symbols = {
    wAlreadyPlayedEnergy = opts.alreadyPlayedEnergy or 0,
    wPreviousAIFlags = opts.usedProfessorOak and C.AI_FLAG_USED_PROFESSOR_OAK or 0,
  }
  local memory = {
    readSymbol8 = function(_, name) return symbols[name] or 0 end,
    writeSymbol8 = function(_, name, v) symbols[name] = v end,
  }
  local duelVars = { get = function() return 0 end, getNonTurn = function() return 0 end,
    swapTurn = function() end }
  local cardData = { getCardIDFromDeckIndex = function() return nil end, get = function() return nil end }
  local ai = AI.new(memory, duelVars, { random = function() return 0 end }, cardData, {}, C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} }, {})
  ai.combat = { core = { clearNonTurnTemporaryDuelvars = function() end } }

  local calls = {}
  local phaseLog = {}
  ai.initTurnVars = function() calls.initTurnVars = true end
  ai.handleAIAntiMewtwoDeckStrategy = function()
    calls.handleAIAntiMewtwoDeckStrategy = true
    if opts.antiMillOk == false then return false, "anti_mewtwo_mill_bench_ready" end
    return true
  end
  ai.processHandTrainerCards = function(_, phase) phaseLog[#phaseLog + 1] = phase; return true end
  ai.decidePlayPokemonCard = function()
    calls.decidePlayPokemonCard = (calls.decidePlayPokemonCard or 0) + 1; return true
  end
  ai.processRetreat = function()
    calls.processRetreat = (calls.processRetreat or 0) + 1; return true
  end
  ai.processAndTryToPlayEnergy = function()
    calls.processAndTryToPlayEnergy = (calls.processAndTryToPlayEnergy or 0) + 1; return true
  end
  ai.processAndTryToUseAttack = function() calls.processAndTryToUseAttack = true; return true, "attacked" end
  return ai, calls, phaseLog
end

-- ---------------------------------------------------------------------
-- Phase 01 runs before the anti-mill check.
-- ---------------------------------------------------------------------
do
  local ai, calls, phases = newAI({ antiMillOk = false })
  ai:doTurnLegendaryArticuno()
  check("mill special path: only phase 01 processed (before the anti-mill check)",
    phases, { C.AI_TRAINER_CARD_PHASE_01 })
  check("mill special path: decidePlayPokemonCard NOT called", calls.decidePlayPokemonCard, nil)
  check("mill special path: processAndTryToPlayEnergy NOT called", calls.processAndTryToPlayEnergy, nil)
  check("mill special path: still tries to attack", calls.processAndTryToUseAttack, true)
end

-- ---------------------------------------------------------------------
-- No bespoke Energy-attach branch: always the plain scoring routine.
-- ---------------------------------------------------------------------
do
  local ai, calls = newAI({})
  ai:doTurnLegendaryArticuno()
  check("normal path: processAndTryToPlayEnergy called once", calls.processAndTryToPlayEnergy, 1)
end
do
  local ai, calls = newAI({ alreadyPlayedEnergy = 1 })
  ai:doTurnLegendaryArticuno()
  check("Energy already played: processAndTryToPlayEnergy NOT called", calls.processAndTryToPlayEnergy, nil)
end

-- ---------------------------------------------------------------------
-- No Professor Oak: no repeat pass, phases 13 and 15 each run once.
-- ---------------------------------------------------------------------
do
  local ai, calls, phases = newAI({})
  ai:doTurnLegendaryArticuno()
  check("no Professor Oak: phase order is 1, 2, 10, 13, 15",
    phases, { C.AI_TRAINER_CARD_PHASE_01, C.AI_TRAINER_CARD_PHASE_02, C.AI_TRAINER_CARD_PHASE_10,
      C.AI_TRAINER_CARD_PHASE_13, C.AI_TRAINER_CARD_PHASE_15 })
  check("no Professor Oak: decidePlayPokemonCard called twice", calls.decidePlayPokemonCard, 2)
  check("no Professor Oak: processRetreat called once", calls.processRetreat, 1)
end

-- ---------------------------------------------------------------------
-- Professor Oak used: short repeat pass (no phase 13/15 on the repeat).
-- ---------------------------------------------------------------------
do
  local ai, calls, phases = newAI({ usedProfessorOak = true })
  ai:doTurnLegendaryArticuno()
  check("Professor Oak used: phase order is 1,2,10,13,15,1,2,10 (no second 13/15)",
    phases, { C.AI_TRAINER_CARD_PHASE_01, C.AI_TRAINER_CARD_PHASE_02, C.AI_TRAINER_CARD_PHASE_10,
      C.AI_TRAINER_CARD_PHASE_13, C.AI_TRAINER_CARD_PHASE_15,
      C.AI_TRAINER_CARD_PHASE_01, C.AI_TRAINER_CARD_PHASE_02, C.AI_TRAINER_CARD_PHASE_10 })
  check("Professor Oak used: decidePlayPokemonCard called 4 times", calls.decidePlayPokemonCard, 4)
  check("Professor Oak used: processRetreat called twice", calls.processRetreat, 2)
  check("Professor Oak used: processAndTryToPlayEnergy called twice", calls.processAndTryToPlayEnergy, 2)
  check("Professor Oak used: still tries to attack", calls.processAndTryToUseAttack, true)
end

if failures == 0 then
  print("all AIDoTurn_LegendaryArticuno cases passed")
  os.exit(0)
else
  print(("%d AIDoTurn_LegendaryArticuno case(s) failed"):format(failures))
  os.exit(1)
end
