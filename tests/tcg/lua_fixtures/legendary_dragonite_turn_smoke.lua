-- Behavioral smoke test for AIDoTurn_LegendaryDragonite
-- (engine/duel/ai/decks/legendary_dragonite.asm), run under real LuaJIT.
--
-- Third of the five Legendary bosses' bespoke turn logic. Unlike Zapdos's
-- and Moltres's, phase 01 runs BEFORE the anti-Mewtwo-mill check here
-- (matching AIMainTurnLogic's own ordering, not the other two bosses'). The
-- Energy-attach branch force-attaches directly to the Arena when it's
-- Kangaskhan with no Energy attached yet (single-card gate, reusing
-- AI:_tryToPlayEnergyCard). Also has its own short Professor-Oak repeat
-- pass (01/02/07/retreat/10/11/energy/play, no phase 15 on the repeat),
-- distinct from AIMainTurnLogic's longer one and absent from Zapdos/Moltres
-- entirely.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")
local bit = require("bit")

local C = {
  AI_TRAINER_CARD_PHASE_01 = 1, AI_TRAINER_CARD_PHASE_02 = 2,
  AI_TRAINER_CARD_PHASE_07 = 7, AI_TRAINER_CARD_PHASE_10 = 10,
  AI_TRAINER_CARD_PHASE_11 = 11, AI_TRAINER_CARD_PHASE_15 = 15,
  DUELVARS_ARENA_CARD = 0x10,
  PLAY_AREA_ARENA = 0,
  TYPE_ENERGY = 8, TYPE_TRAINER = 9,
  KANGASKHAN = 1, EEVEE = 2, FIRE_ENERGY = 100,
  AI_FLAG_USED_PROFESSOR_OAK = 0x04,
}

local CARD_ROWS = {
  [C.KANGASKHAN] = { type = 0 }, [C.EEVEE] = { type = 0 },
  [C.FIRE_ENERGY] = { type = C.TYPE_ENERGY },
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

-- opts.arenaCardId, opts.handCardIds, opts.attachedToArena,
-- opts.alreadyPlayedEnergy, opts.antiMillOk, opts.usedProfessorOak
local function newAI(opts)
  local vars = { [C.DUELVARS_ARENA_CARD] = 1 }
  local symbols = {
    wAlreadyPlayedEnergy = opts.alreadyPlayedEnergy or 0,
    wPreviousAIFlags = opts.usedProfessorOak and C.AI_FLAG_USED_PROFESSOR_OAK or 0,
  }
  local cardIdByDeckIndex = { [1] = opts.arenaCardId or 999 }

  local memory = {
    readSymbol8 = function(_, name) return symbols[name] or 0 end,
    writeSymbol8 = function(_, name, v) symbols[name] = v end,
  }
  local duelVars = {
    get = function(_, offset) return vars[offset] or 0 end,
    getNonTurn = function() return 0 end,
    swapTurn = function() end,
  }
  local cardData = {
    getCardIDFromDeckIndex = function(_, deckIndex) return cardIdByDeckIndex[deckIndex] end,
    get = function(_, cardId) return CARD_ROWS[cardId] end,
  }
  local duelOps = {
    countNumberOfEnergyCardsAttached = function() return opts.attachedToArena or 0 end,
  }
  local ai = AI.new(memory, duelVars, { random = function() return 0 end }, cardData, duelOps, C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} }, {})
  ai.combat = { core = { clearNonTurnTemporaryDuelvars = function() end } }

  local calls = {}
  local phaseLog = {}
  local handEnergy = {}
  for _, cardId in ipairs(opts.handCardIds or {}) do
    if CARD_ROWS[cardId] and CARD_ROWS[cardId].type == C.TYPE_ENERGY then
      handEnergy[#handEnergy + 1] = { cardId = cardId }
    end
  end
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
  ai._energyCardsInHand = function() return handEnergy end
  ai.processAndTryToPlayEnergy = function()
    calls.processAndTryToPlayEnergy = (calls.processAndTryToPlayEnergy or 0) + 1; return true
  end
  ai._tryToPlayEnergyCard = function(_, slot, energy)
    calls.tryToPlayEnergyCard = { slot = slot, handEnergyCount = #energy }
    return true
  end
  ai.processAndTryToUseAttack = function() calls.processAndTryToUseAttack = true; return true, "attacked" end
  return ai, calls, phaseLog
end

-- ---------------------------------------------------------------------
-- Phase 01 runs before the anti-mill check (unlike Zapdos/Moltres).
-- ---------------------------------------------------------------------
do
  local ai, calls, phases = newAI({ arenaCardId = C.EEVEE, antiMillOk = false })
  ai:doTurnLegendaryDragonite()
  check("mill special path: only phase 01 processed (before the anti-mill check)",
    phases, { C.AI_TRAINER_CARD_PHASE_01 })
  check("mill special path: decidePlayPokemonCard NOT called", calls.decidePlayPokemonCard, nil)
  check("mill special path: still tries to attack", calls.processAndTryToUseAttack, true)
end

-- ---------------------------------------------------------------------
-- Kangaskhan Energy-attach branch.
-- ---------------------------------------------------------------------
do
  local ai, calls = newAI({ arenaCardId = C.KANGASKHAN, handCardIds = { C.FIRE_ENERGY }, attachedToArena = 0 })
  ai:doTurnLegendaryDragonite()
  check("Kangaskhan Arena, bare: _tryToPlayEnergyCard called with PLAY_AREA_ARENA",
    calls.tryToPlayEnergyCard and calls.tryToPlayEnergyCard.slot, C.PLAY_AREA_ARENA)
  check("Kangaskhan Arena, bare: processAndTryToPlayEnergy NOT called (pass 1)",
    calls.processAndTryToPlayEnergy, nil)
end
do
  local ai, calls = newAI({ arenaCardId = C.KANGASKHAN, handCardIds = { C.FIRE_ENERGY }, attachedToArena = 1 })
  ai:doTurnLegendaryDragonite()
  check("Kangaskhan Arena, already has Energy: processAndTryToPlayEnergy called",
    calls.processAndTryToPlayEnergy, 1)
  check("Kangaskhan Arena, already has Energy: _tryToPlayEnergyCard NOT called",
    calls.tryToPlayEnergyCard, nil)
end
do
  local ai, calls = newAI({ arenaCardId = C.EEVEE, handCardIds = { C.FIRE_ENERGY }, attachedToArena = 0 })
  ai:doTurnLegendaryDragonite()
  check("other Arena Pokemon: processAndTryToPlayEnergy called (normal path)",
    calls.processAndTryToPlayEnergy, 1)
  check("other Arena Pokemon: _tryToPlayEnergyCard NOT called", calls.tryToPlayEnergyCard, nil)
end

-- ---------------------------------------------------------------------
-- No Professor Oak used: no repeat pass, phase 15 runs once.
-- ---------------------------------------------------------------------
do
  local ai, calls, phases = newAI({ arenaCardId = C.EEVEE, handCardIds = { C.FIRE_ENERGY } })
  ai:doTurnLegendaryDragonite()
  check("no Professor Oak: phase order is 1, 2, 7, 10, 11, 15",
    phases, { C.AI_TRAINER_CARD_PHASE_01, C.AI_TRAINER_CARD_PHASE_02, C.AI_TRAINER_CARD_PHASE_07,
      C.AI_TRAINER_CARD_PHASE_10, C.AI_TRAINER_CARD_PHASE_11, C.AI_TRAINER_CARD_PHASE_15 })
  check("no Professor Oak: decidePlayPokemonCard called twice", calls.decidePlayPokemonCard, 2)
  check("no Professor Oak: processRetreat called once", calls.processRetreat, 1)
  check("no Professor Oak: processAndTryToPlayEnergy called once", calls.processAndTryToPlayEnergy, 1)
end

-- ---------------------------------------------------------------------
-- Professor Oak used: short repeat pass (no phase 15 on the repeat), plus
-- a 3rd decidePlayPokemonCard and 2nd processRetreat/processAndTryToPlayEnergy.
-- ---------------------------------------------------------------------
do
  local ai, calls, phases = newAI({
    arenaCardId = C.EEVEE, handCardIds = { C.FIRE_ENERGY }, usedProfessorOak = true,
  })
  ai:doTurnLegendaryDragonite()
  check("Professor Oak used: phase order is 1,2,7,10,11,15,1,2,7,10,11 (no second 15)",
    phases, { C.AI_TRAINER_CARD_PHASE_01, C.AI_TRAINER_CARD_PHASE_02, C.AI_TRAINER_CARD_PHASE_07,
      C.AI_TRAINER_CARD_PHASE_10, C.AI_TRAINER_CARD_PHASE_11, C.AI_TRAINER_CARD_PHASE_15,
      C.AI_TRAINER_CARD_PHASE_01, C.AI_TRAINER_CARD_PHASE_02, C.AI_TRAINER_CARD_PHASE_07,
      C.AI_TRAINER_CARD_PHASE_10, C.AI_TRAINER_CARD_PHASE_11 })
  -- 2 calls in the first pass (before and after the energy-attach block) +
  -- 2 more in the short repeat pass (before phase 07 and after energy).
  check("Professor Oak used: decidePlayPokemonCard called 4 times", calls.decidePlayPokemonCard, 4)
  check("Professor Oak used: processRetreat called twice", calls.processRetreat, 2)
  check("Professor Oak used: processAndTryToPlayEnergy called twice", calls.processAndTryToPlayEnergy, 2)
  check("Professor Oak used: still tries to attack", calls.processAndTryToUseAttack, true)
end

if failures == 0 then
  print("all AIDoTurn_LegendaryDragonite cases passed")
  os.exit(0)
else
  print(("%d AIDoTurn_LegendaryDragonite case(s) failed"):format(failures))
  os.exit(1)
end
