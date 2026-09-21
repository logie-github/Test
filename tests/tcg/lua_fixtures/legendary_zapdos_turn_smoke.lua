-- Behavioral smoke test for AIDoTurn_LegendaryZapdos
-- (engine/duel/ai/decks/legendary_zapdos.asm), run under real LuaJIT.
--
-- This is the first of the five Legendary bosses' bespoke turn logic to be
-- translated. It reuses the same native primitives as the generic
-- mainTurnLogic (initTurnVars, handleAIAntiMewtwoDeckStrategy,
-- processHandTrainerCards, decidePlayPokemonCard, processRetreat,
-- processAndTryToPlayEnergy, processAndTryToUseAttack), plus one genuinely
-- bespoke branch: if the Arena Pokemon is Voltorb-with-ElectrodeLv35-in-hand
-- or Electabuzz, and the Arena has no Energy attached yet, force-attach an
-- Energy card directly to the Arena via the new _tryToPlayEnergyCard
-- (factored out of AIProcessAndTryToPlayEnergy's own tail) rather than the
-- normal scoring-based attach.
--
-- Higher-level collaborators (decidePlayPokemonCard, processRetreat,
-- processAndTryToPlayEnergy, processAndTryToUseAttack,
-- handleAIAntiMewtwoDeckStrategy) are stubbed at the instance level -- each
-- already has its own dedicated fixture -- so this one isolates
-- doTurnLegendaryZapdos's own control flow and the real Voltorb/Electabuzz
-- decision (arena-card lookup, hand search, attached-energy count) against
-- real card/duel-var data.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  AI_TRAINER_CARD_PHASE_01 = 1, AI_TRAINER_CARD_PHASE_04 = 4,
  AI_TRAINER_CARD_PHASE_07 = 7, AI_TRAINER_CARD_PHASE_10 = 10,
  AI_TRAINER_CARD_PHASE_13 = 13,
  DUELVARS_ARENA_CARD = 0x10,
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x20, DUELVARS_HAND = 0x30,
  PLAY_AREA_ARENA = 0,
  TYPE_ENERGY = 8, TYPE_TRAINER = 9,
  VOLTORB = 1, ELECTRODE_LV35 = 2, ELECTABUZZ_LV35 = 3, EEVEE = 4,
  FIRE_ENERGY = 100,
}

local CARD_ROWS = {
  [C.VOLTORB] = { type = 0 }, [C.ELECTRODE_LV35] = { type = 0 },
  [C.ELECTABUZZ_LV35] = { type = 0 }, [C.EEVEE] = { type = 0 },
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

-- opts.arenaCardId, opts.handCardIds (array), opts.attachedToArena (count),
-- opts.alreadyPlayedEnergy (0/1), opts.antiMillOk (true/false)
local function newAI(opts)
  local vars = { [C.DUELVARS_ARENA_CARD] = 999 }
  local symbols = { wAlreadyPlayedEnergy = opts.alreadyPlayedEnergy or 0 }
  local deckIndexByCardId = { [999] = 999 }
  deckIndexByCardId[opts.arenaCardId or 999] = 1
  vars[C.DUELVARS_ARENA_CARD] = 1
  local cardIdByDeckIndex = { [1] = opts.arenaCardId or 999 }
  local hand = opts.handCardIds or {}
  vars[C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = #hand
  for i, cardId in ipairs(hand) do
    local deckIndex = 100 + i
    cardIdByDeckIndex[deckIndex] = cardId
    vars[C.DUELVARS_HAND + (i - 1)] = deckIndex
  end

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
    countNumberOfEnergyCardsAttached = function(_, slot)
      check("countNumberOfEnergyCardsAttached called with PLAY_AREA_ARENA", slot, C.PLAY_AREA_ARENA)
      return opts.attachedToArena or 0
    end,
  }
  local ai = AI.new(memory, duelVars, { random = function() return 0 end }, cardData, duelOps, C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} }, {})

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
  ai.processRetreat = function() calls.processRetreat = true; return true end
  ai.processAndTryToPlayEnergy = function() calls.processAndTryToPlayEnergy = true; return true end
  ai._tryToPlayEnergyCard = function(_, slot, handEnergy)
    calls.tryToPlayEnergyCard = { slot = slot, handEnergyCount = #handEnergy }
    return true
  end
  ai.processAndTryToUseAttack = function() calls.processAndTryToUseAttack = true; return true, "attacked" end
  return ai, calls, phaseLog
end

-- ---------------------------------------------------------------------
-- Arena is neither Voltorb nor Electabuzz -> normal scoring-based attach.
-- ---------------------------------------------------------------------
do
  local ai, calls = newAI({ arenaCardId = C.EEVEE, handCardIds = { C.FIRE_ENERGY }, attachedToArena = 0 })
  ai:doTurnLegendaryZapdos()
  check("other Arena Pokemon: processAndTryToPlayEnergy called", calls.processAndTryToPlayEnergy, true)
  check("other Arena Pokemon: _tryToPlayEnergyCard NOT called", calls.tryToPlayEnergyCard, nil)
end

-- ---------------------------------------------------------------------
-- Arena is Voltorb, but no ElectrodeLv35 in hand -> normal attach.
-- ---------------------------------------------------------------------
do
  local ai, calls = newAI({ arenaCardId = C.VOLTORB, handCardIds = { C.FIRE_ENERGY }, attachedToArena = 0 })
  ai:doTurnLegendaryZapdos()
  check("Voltorb w/o Electrode in hand: processAndTryToPlayEnergy called", calls.processAndTryToPlayEnergy, true)
  check("Voltorb w/o Electrode in hand: _tryToPlayEnergyCard NOT called", calls.tryToPlayEnergyCard, nil)
end

-- ---------------------------------------------------------------------
-- Arena is Voltorb with ElectrodeLv35 in hand, but no Energy in hand at
-- all -> skip entirely (neither attach path runs).
-- ---------------------------------------------------------------------
do
  local ai, calls = newAI({ arenaCardId = C.VOLTORB, handCardIds = { C.ELECTRODE_LV35 }, attachedToArena = 0 })
  ai:doTurnLegendaryZapdos()
  check("Voltorb+Electrode, no Energy in hand: processAndTryToPlayEnergy NOT called",
    calls.processAndTryToPlayEnergy, nil)
  check("Voltorb+Electrode, no Energy in hand: _tryToPlayEnergyCard NOT called", calls.tryToPlayEnergyCard, nil)
end

-- ---------------------------------------------------------------------
-- Arena is Voltorb with ElectrodeLv35 in hand, Energy in hand, but Arena
-- already has Energy attached -> falls to the normal scoring-based attach.
-- ---------------------------------------------------------------------
do
  local ai, calls = newAI({
    arenaCardId = C.VOLTORB, handCardIds = { C.ELECTRODE_LV35, C.FIRE_ENERGY }, attachedToArena = 1,
  })
  ai:doTurnLegendaryZapdos()
  check("Voltorb+Electrode, Arena already has Energy: processAndTryToPlayEnergy called",
    calls.processAndTryToPlayEnergy, true)
  check("Voltorb+Electrode, Arena already has Energy: _tryToPlayEnergyCard NOT called",
    calls.tryToPlayEnergyCard, nil)
end

-- ---------------------------------------------------------------------
-- Arena is Voltorb with ElectrodeLv35 in hand, Energy in hand, Arena has
-- NO Energy attached yet -> the bespoke forced direct-to-Arena attach.
-- ---------------------------------------------------------------------
do
  local ai, calls = newAI({
    arenaCardId = C.VOLTORB, handCardIds = { C.ELECTRODE_LV35, C.FIRE_ENERGY }, attachedToArena = 0,
  })
  ai:doTurnLegendaryZapdos()
  check("Voltorb+Electrode, Arena bare: _tryToPlayEnergyCard called with PLAY_AREA_ARENA",
    calls.tryToPlayEnergyCard and calls.tryToPlayEnergyCard.slot, C.PLAY_AREA_ARENA)
  check("Voltorb+Electrode, Arena bare: hand energy count passed through",
    calls.tryToPlayEnergyCard and calls.tryToPlayEnergyCard.handEnergyCount, 1)
  check("Voltorb+Electrode, Arena bare: processAndTryToPlayEnergy NOT called (fallthrough is a no-op)",
    calls.processAndTryToPlayEnergy, nil)
end

-- ---------------------------------------------------------------------
-- Arena is Electabuzz (no Electrode-in-hand check needed), bare Arena.
-- ---------------------------------------------------------------------
do
  local ai, calls = newAI({ arenaCardId = C.ELECTABUZZ_LV35, handCardIds = { C.FIRE_ENERGY }, attachedToArena = 0 })
  ai:doTurnLegendaryZapdos()
  check("Electabuzz, Arena bare: _tryToPlayEnergyCard called with PLAY_AREA_ARENA",
    calls.tryToPlayEnergyCard and calls.tryToPlayEnergyCard.slot, C.PLAY_AREA_ARENA)
  check("Electabuzz, Arena bare: processAndTryToPlayEnergy NOT called", calls.processAndTryToPlayEnergy, nil)
end

-- ---------------------------------------------------------------------
-- Energy already played this turn -> the entire energy block is skipped.
-- ---------------------------------------------------------------------
do
  local ai, calls = newAI({
    arenaCardId = C.VOLTORB, handCardIds = { C.ELECTRODE_LV35, C.FIRE_ENERGY }, attachedToArena = 0,
    alreadyPlayedEnergy = 1,
  })
  ai:doTurnLegendaryZapdos()
  check("Energy already played: processAndTryToPlayEnergy NOT called", calls.processAndTryToPlayEnergy, nil)
  check("Energy already played: _tryToPlayEnergyCard NOT called", calls.tryToPlayEnergyCard, nil)
end

-- ---------------------------------------------------------------------
-- Anti-Mewtwo-mill special path: skip straight to the attack tail. Unlike
-- AIMainTurnLogic (which processes phase 01 *before* the anti-mill check),
-- AIDoTurn_LegendaryZapdos calls HandleAIAntiMewtwoDeckStrategy immediately
-- after InitAITurnVars -- so on the special path, this routine itself has
-- not processed any phase yet (phase 05, if any, happens inside the
-- anti-mill handler itself, which is stubbed out here).
-- ---------------------------------------------------------------------
do
  local ai, calls, phases = newAI({ arenaCardId = C.EEVEE, handCardIds = {}, antiMillOk = false })
  ai:doTurnLegendaryZapdos()
  check("mill special path: no phase processed by this routine itself", phases, {})
  check("mill special path: decidePlayPokemonCard NOT called", calls.decidePlayPokemonCard, nil)
  check("mill special path: processRetreat NOT called", calls.processRetreat, nil)
  check("mill special path: processAndTryToPlayEnergy NOT called", calls.processAndTryToPlayEnergy, nil)
  check("mill special path: still tries to attack", calls.processAndTryToUseAttack, true)
end

-- ---------------------------------------------------------------------
-- Normal path: full phase ordering and call sequence.
-- ---------------------------------------------------------------------
do
  local ai, calls, phases = newAI({ arenaCardId = C.EEVEE, handCardIds = { C.FIRE_ENERGY }, attachedToArena = 0 })
  ai:doTurnLegendaryZapdos()
  check("normal path: phase order is 1, 4, 7, 10, 13",
    phases, { C.AI_TRAINER_CARD_PHASE_01, C.AI_TRAINER_CARD_PHASE_04,
      C.AI_TRAINER_CARD_PHASE_07, C.AI_TRAINER_CARD_PHASE_10, C.AI_TRAINER_CARD_PHASE_13 })
  check("normal path: decidePlayPokemonCard called twice", calls.decidePlayPokemonCard, 2)
  check("normal path: processRetreat called", calls.processRetreat, true)
  check("normal path: still tries to attack", calls.processAndTryToUseAttack, true)
  check("normal path: initTurnVars called", calls.initTurnVars, true)
  check("normal path: handleAIAntiMewtwoDeckStrategy called", calls.handleAIAntiMewtwoDeckStrategy, true)
end

if failures == 0 then
  print("all AIDoTurn_LegendaryZapdos cases passed")
  os.exit(0)
else
  print(("%d AIDoTurn_LegendaryZapdos case(s) failed"):format(failures))
  os.exit(1)
end
