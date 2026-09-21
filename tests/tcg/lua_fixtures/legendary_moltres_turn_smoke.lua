-- Behavioral smoke test for AIDoTurn_LegendaryMoltres
-- (engine/duel/ai/decks/legendary_moltres.asm), run under real LuaJIT.
--
-- Second of the five Legendary bosses' bespoke turn logic. Shares the
-- anti-Mewtwo-mill-first ordering and the "force-attach Energy directly to
-- a specific Arena Pokemon with none attached yet" shape with Zapdos's, but
-- with two differences: a bespoke "play MoltresLv37 directly from hand"
-- branch (gated on Bench space, deck size, no Muk in play, and the card
-- actually being in hand) right after phases 2/4, and a single-card
-- (MagmarLv31, not a two-name check) gate for the Energy-attach branch.
--
-- Higher-level collaborators are stubbed at the instance level, same
-- pattern as legendary_zapdos_turn_smoke.lua, isolating
-- doTurnLegendaryMoltres's own control flow and its two bespoke decisions
-- against real card/duel-var data.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  AI_TRAINER_CARD_PHASE_02 = 2, AI_TRAINER_CARD_PHASE_04 = 4,
  AI_TRAINER_CARD_PHASE_05 = 5, AI_TRAINER_CARD_PHASE_10 = 10,
  AI_TRAINER_CARD_PHASE_11 = 11, AI_TRAINER_CARD_PHASE_13 = 13,
  DUELVARS_ARENA_CARD = 0x10,
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = 0x18,
  DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK = 0x19,
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x20, DUELVARS_HAND = 0x30,
  PLAY_AREA_ARENA = 0, MAX_PLAY_AREA_POKEMON = 6, DECK_SIZE = 60,
  TYPE_ENERGY = 8, TYPE_TRAINER = 9,
  MAGMAR_LV31 = 1, MOLTRES_LV37 = 2, MUK = 3, EEVEE = 4,
  FIRE_ENERGY = 100,
}

local CARD_ROWS = {
  [C.MAGMAR_LV31] = { type = 0 }, [C.MOLTRES_LV37] = { type = 0 },
  [C.EEVEE] = { type = 0 }, [C.FIRE_ENERGY] = { type = C.TYPE_ENERGY },
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
-- opts.alreadyPlayedEnergy (0/1), opts.antiMillOk (true/false),
-- opts.playAreaCount, opts.notInDeck, opts.muk (bool)
local function newAI(opts)
  local vars = {
    [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = opts.playAreaCount or 1,
    [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = opts.notInDeck or 0,
  }
  local symbols = { wAlreadyPlayedEnergy = opts.alreadyPlayedEnergy or 0 }
  local cardIdByDeckIndex = { [1] = opts.arenaCardId or 999 }
  vars[C.DUELVARS_ARENA_CARD] = 1
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
    countNumberOfEnergyCardsAttached = function() return opts.attachedToArena or 0 end,
  }
  local combat = {
    core = { clearNonTurnTemporaryDuelvars = function() end },
    status = {
      countPokemonWithActivePkmnPowerInBothPlayAreas = function(_, cardId)
        check("Muk check uses MUK card id", cardId, C.MUK)
        return 0, opts.muk == true
      end,
    },
  }
  local ai = AI.new(memory, duelVars, { random = function() return 0 end }, cardData, duelOps, C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} }, {})
  ai.combat = combat

  local calls = {}
  local phaseLog = {}
  ai.initTurnVars = function() calls.initTurnVars = true end
  ai.handleAIAntiMewtwoDeckStrategy = function()
    calls.handleAIAntiMewtwoDeckStrategy = true
    if opts.antiMillOk == false then return false, "anti_mewtwo_mill_bench_ready" end
    return true
  end
  ai.processHandTrainerCards = function(_, phase) phaseLog[#phaseLog + 1] = phase; return true end
  ai.playerActions = {
    playBasic = function(_, cardId)
      calls.playBasic = cardId
      return true, C.PLAY_AREA_ARENA + 1
    end,
  }
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
-- The MoltresLv37-direct-play branch: all four gates.
-- ---------------------------------------------------------------------
do
  local ai, calls = newAI({
    playAreaCount = 3, notInDeck = 10, muk = false, handCardIds = { C.MOLTRES_LV37 },
  })
  ai:doTurnLegendaryMoltres()
  check("all gates pass: MoltresLv37 played directly from hand", calls.playBasic, C.MOLTRES_LV37)
end
do
  local ai, calls = newAI({
    playAreaCount = C.MAX_PLAY_AREA_POKEMON, notInDeck = 10, muk = false,
    handCardIds = { C.MOLTRES_LV37 },
  })
  ai:doTurnLegendaryMoltres()
  check("Bench full: MoltresLv37 NOT played directly", calls.playBasic, nil)
end
do
  local ai, calls = newAI({
    playAreaCount = 3, notInDeck = C.DECK_SIZE - 9, muk = false, handCardIds = { C.MOLTRES_LV37 },
  })
  ai:doTurnLegendaryMoltres()
  check("deck has <= 9 cards left: MoltresLv37 NOT played directly", calls.playBasic, nil)
end
do
  local ai, calls = newAI({
    playAreaCount = 3, notInDeck = 10, muk = true, handCardIds = { C.MOLTRES_LV37 },
  })
  ai:doTurnLegendaryMoltres()
  check("Muk in play: MoltresLv37 NOT played directly", calls.playBasic, nil)
end
do
  local ai, calls = newAI({ playAreaCount = 3, notInDeck = 10, muk = false, handCardIds = {} })
  ai:doTurnLegendaryMoltres()
  check("MoltresLv37 not in hand: not played directly", calls.playBasic, nil)
end

-- ---------------------------------------------------------------------
-- MagmarLv31 Energy-attach branch (single-card gate, unlike Zapdos's two).
-- ---------------------------------------------------------------------
do
  local ai, calls = newAI({
    arenaCardId = C.MAGMAR_LV31, handCardIds = { C.FIRE_ENERGY }, attachedToArena = 0,
    playAreaCount = 6,
  })
  ai:doTurnLegendaryMoltres()
  check("MagmarLv31 Arena, bare: _tryToPlayEnergyCard called with PLAY_AREA_ARENA",
    calls.tryToPlayEnergyCard and calls.tryToPlayEnergyCard.slot, C.PLAY_AREA_ARENA)
  check("MagmarLv31 Arena, bare: processAndTryToPlayEnergy NOT called", calls.processAndTryToPlayEnergy, nil)
end
do
  local ai, calls = newAI({
    arenaCardId = C.MAGMAR_LV31, handCardIds = { C.FIRE_ENERGY }, attachedToArena = 1,
    playAreaCount = 6,
  })
  ai:doTurnLegendaryMoltres()
  check("MagmarLv31 Arena, already has Energy: processAndTryToPlayEnergy called",
    calls.processAndTryToPlayEnergy, true)
  check("MagmarLv31 Arena, already has Energy: _tryToPlayEnergyCard NOT called",
    calls.tryToPlayEnergyCard, nil)
end
do
  local ai, calls = newAI({
    arenaCardId = C.EEVEE, handCardIds = { C.FIRE_ENERGY }, attachedToArena = 0, playAreaCount = 6,
  })
  ai:doTurnLegendaryMoltres()
  check("other Arena Pokemon: processAndTryToPlayEnergy called (normal path)",
    calls.processAndTryToPlayEnergy, true)
  check("other Arena Pokemon: _tryToPlayEnergyCard NOT called", calls.tryToPlayEnergyCard, nil)
end
do
  local ai, calls = newAI({
    arenaCardId = C.MAGMAR_LV31, handCardIds = { C.FIRE_ENERGY }, attachedToArena = 0,
    playAreaCount = 6, alreadyPlayedEnergy = 1,
  })
  ai:doTurnLegendaryMoltres()
  check("Energy already played: neither attach path runs", calls.processAndTryToPlayEnergy, nil)
  check("Energy already played: _tryToPlayEnergyCard NOT called", calls.tryToPlayEnergyCard, nil)
end

-- ---------------------------------------------------------------------
-- Anti-Mewtwo-mill special path and full normal-path phase ordering.
-- ---------------------------------------------------------------------
do
  local ai, calls, phases = newAI({ playAreaCount = 6, antiMillOk = false })
  ai:doTurnLegendaryMoltres()
  check("mill special path: no phase processed by this routine itself", phases, {})
  check("mill special path: decidePlayPokemonCard NOT called", calls.decidePlayPokemonCard, nil)
  check("mill special path: playBasic NOT called", calls.playBasic, nil)
  check("mill special path: still tries to attack", calls.processAndTryToUseAttack, true)
end
do
  local ai, calls, phases = newAI({
    playAreaCount = 6, arenaCardId = C.EEVEE, handCardIds = { C.FIRE_ENERGY }, attachedToArena = 0,
  })
  ai:doTurnLegendaryMoltres()
  check("normal path: phase order is 2, 4, 5, 10, 11, 13",
    phases, { C.AI_TRAINER_CARD_PHASE_02, C.AI_TRAINER_CARD_PHASE_04, C.AI_TRAINER_CARD_PHASE_05,
      C.AI_TRAINER_CARD_PHASE_10, C.AI_TRAINER_CARD_PHASE_11, C.AI_TRAINER_CARD_PHASE_13 })
  check("normal path: decidePlayPokemonCard called twice", calls.decidePlayPokemonCard, 2)
  check("normal path: processRetreat called", calls.processRetreat, true)
  check("normal path: still tries to attack", calls.processAndTryToUseAttack, true)
end

if failures == 0 then
  print("all AIDoTurn_LegendaryMoltres cases passed")
  os.exit(0)
else
  print(("%d AIDoTurn_LegendaryMoltres case(s) failed"):format(failures))
  os.exit(1)
end
