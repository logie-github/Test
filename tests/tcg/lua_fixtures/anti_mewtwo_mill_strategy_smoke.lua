-- Behavioral smoke test for HandleAIAntiMewtwoDeckStrategy
-- (engine/duel/ai/common.asm) and its wiring into AIMainTurnLogic /
-- AIDoTurn_GeneralNoRetreat (both call it identically right after
-- AI_TRAINER_CARD_PHASE_01, with `jp nc, .try_attack`), run under real
-- LuaJIT.
--
-- Before this change, mainTurnLogic never called this at all: the
-- AI_MEWTWO_MILL flag could be read (Gambler's decision, a couple of Energy/
-- Trainer scoring spots) but the turn loop itself never acted on it, so once
-- Task 5 made the flag settable, the "AI recognizes it's facing a mill deck
-- with its own Bench fully set up, and skips straight to attacking after a
-- single Trainer-card pass" behavior was still entirely missing.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  AI_MEWTWO_MILL_F = 7,
  AI_MEWTWO_MILL = 0x80,
  AI_TRAINER_CARD_PHASE_05 = 5,
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
  if type(got) == "table" or type(want) == "table" then
    equal = arraysEqual(got, want)
  else
    equal = got == want
  end
  if not equal then
    failures = failures + 1
    print(("FAIL  %s: got %s, want %s"):format(label, fmt(got), fmt(want)))
  else
    print(("ok    %s"):format(label))
  end
end

local function newAI(symbols, benchSetUpCount)
  local memory = {
    readSymbol8 = function(_, name) return symbols[name] or 0 end,
    writeSymbol8 = function(_, name, v) symbols[name] = v end,
  }
  local ai = AI.new(memory, { get = function() return 0 end, getNonTurn = function() return 0 end },
    { random = function() return 0 end },
    { getCardIDFromDeckIndex = function() return nil end, get = function() return nil end },
    {}, C, { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} }, {})
  ai._countNumberOfSetUpBenchPokemon = function() return benchSetUpCount end
  local phasesProcessed = {}
  ai.processHandTrainerCards = function(_, phase)
    phasesProcessed[#phasesProcessed + 1] = phase
    return true
  end
  return ai, phasesProcessed
end

-- ---------------------------------------------------------------------
-- HandleAIAntiMewtwoDeckStrategy in isolation.
-- ---------------------------------------------------------------------
do
  local ai, phases = newAI({ wAIBarrierFlagCounter = 0 }, 5)
  local ok, reason = ai:handleAIAntiMewtwoDeckStrategy()
  check("flag unset -> continue normally (carry set)", ok, true)
  check("flag unset -> no phase 05 processed", #phases, 0)
end
do
  -- Flag set, but stale (>= 2 turns since the Player last used Barrier).
  local ai, phases = newAI({ wAIBarrierFlagCounter = C.AI_MEWTWO_MILL + 2 }, 5)
  local ok = ai:handleAIAntiMewtwoDeckStrategy()
  check("flag set, stale (2+ turns since Barrier) -> continue normally", ok, true)
  check("stale counter reset to 0", ai.memory:readSymbol8("wAIBarrierFlagCounter"), 0)
  check("stale -> no phase 05 processed", #phases, 0)
end
do
  -- Flag set, fresh, but Bench not fully set up yet.
  local ai, phases = newAI({ wAIBarrierFlagCounter = C.AI_MEWTWO_MILL + 1 }, 3)
  local ok = ai:handleAIAntiMewtwoDeckStrategy()
  check("flag set, fresh, Bench < 4 set up -> continue normally", ok, true)
  check("counter left untouched", ai.memory:readSymbol8("wAIBarrierFlagCounter"), C.AI_MEWTWO_MILL + 1)
  check("Bench not ready -> no phase 05 processed", #phases, 0)
end
do
  -- Flag set, fresh, Bench fully set up: special path engages.
  local ai, phases = newAI({ wAIBarrierFlagCounter = C.AI_MEWTWO_MILL }, 4)
  local ok, reason = ai:handleAIAntiMewtwoDeckStrategy()
  check("flag set, fresh, Bench >= 4 set up -> special path (carry clear)", ok, false)
  check("processed exactly AI_TRAINER_CARD_PHASE_05", phases, { C.AI_TRAINER_CARD_PHASE_05 })
end

-- ---------------------------------------------------------------------
-- mainTurnLogic wiring: the special path must skip straight to the
-- to_bench Energy Trans + attack tail without running phases 2-4, playing
-- Pokemon, retreating, or attaching Energy.
-- ---------------------------------------------------------------------
do
  local ai = newAI({ wAIBarrierFlagCounter = C.AI_MEWTWO_MILL }, 4)
  ai._countNumberOfSetUpBenchPokemon = function() return 4 end
  local calls = {}
  local phaseLog = {}
  ai.processHandTrainerCards = function(_, phase) phaseLog[#phaseLog + 1] = phase; return true end
  ai.decidePlayPokemonCard = function() calls.decidePlayPokemonCard = true; return true end
  ai.processRetreat = function() calls.processRetreat = true; return true end
  ai.processAndTryToPlayEnergy = function() calls.processAndTryToPlayEnergy = true; return true end
  ai._checkActivePowerBoundary = function() calls.checkActivePowerBoundary = true; return true end
  ai.handleAIEnergyTrans = function(_, mode) calls["energyTrans_" .. mode] = true; return true end
  ai.processAndTryToUseAttack = function() calls.processAndTryToUseAttack = true; return true, "attacked" end
  local ok, result = ai:mainTurnLogic(false)
  check("mainTurnLogic (mill special path): returns ok", ok, true)
  check("mainTurnLogic (mill special path): only phase 05 processed", phaseLog, { 1, C.AI_TRAINER_CARD_PHASE_05 })
  check("mainTurnLogic (mill special path): decidePlayPokemonCard NOT called", calls.decidePlayPokemonCard, nil)
  check("mainTurnLogic (mill special path): processRetreat NOT called", calls.processRetreat, nil)
  check("mainTurnLogic (mill special path): processAndTryToPlayEnergy NOT called",
    calls.processAndTryToPlayEnergy, nil)
  check("mainTurnLogic (mill special path): checkActivePowerBoundary NOT called",
    calls.checkActivePowerBoundary, nil)
  check("mainTurnLogic (mill special path): energyTrans('attack') NOT called",
    calls.energyTrans_attack, nil)
  check("mainTurnLogic (mill special path): energyTrans('to_bench') STILL called",
    calls.energyTrans_to_bench, true)
  check("mainTurnLogic (mill special path): still tries to attack",
    calls.processAndTryToUseAttack, true)
end
do
  -- Normal (non-mill) path still runs the full sequence.
  local ai = newAI({ wAIBarrierFlagCounter = 0 }, 0)
  local calls = {}
  local phaseLog = {}
  ai.processHandTrainerCards = function(_, phase) phaseLog[#phaseLog + 1] = phase; return true end
  ai.decidePlayPokemonCard = function() calls.decidePlayPokemonCard = (calls.decidePlayPokemonCard or 0) + 1; return true end
  ai.processRetreat = function() calls.processRetreat = true; return true end
  ai.processAndTryToPlayEnergy = function() calls.processAndTryToPlayEnergy = true; return true end
  ai._checkActivePowerBoundary = function() return true end
  ai.handleAIEnergyTrans = function(_, mode) calls["energyTrans_" .. mode] = true; return true end
  ai.processAndTryToUseAttack = function() return true, "attacked" end
  local ok = ai:mainTurnLogic(false)
  check("mainTurnLogic (normal path): returns ok", ok, true)
  check("mainTurnLogic (normal path): phase 05 among many phases processed",
    (function() for _, p in ipairs(phaseLog) do if p == 5 then return true end end return false end)(), true)
  check("mainTurnLogic (normal path): decidePlayPokemonCard called", calls.decidePlayPokemonCard, 2)
  check("mainTurnLogic (normal path): processRetreat called", calls.processRetreat, true)
  check("mainTurnLogic (normal path): energyTrans('attack') called", calls.energyTrans_attack, true)
  check("mainTurnLogic (normal path): energyTrans('to_bench') called", calls.energyTrans_to_bench, true)
end

if failures == 0 then
  print("all anti-Mewtwo-mill turn-strategy cases passed")
  os.exit(0)
else
  print(("%d anti-Mewtwo-mill turn-strategy case(s) failed"):format(failures))
  os.exit(1)
end
