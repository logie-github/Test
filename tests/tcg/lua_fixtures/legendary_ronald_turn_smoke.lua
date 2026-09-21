-- Behavioral smoke test for AIDoTurn_LegendaryRonald
-- (engine/duel/ai/decks/legendary_ronald.asm), run under real LuaJIT.
--
-- Last of the five Legendary bosses' bespoke turn logic. Unlike all four
-- others, this one has NO anti-Mewtwo-mill check at all -- the whole turn
-- runs unconditionally. Reuses AI:_tryToPlayMoltresLv37Directly (factored
-- out of Moltres's own translation, byte-identical gate) TWICE: once in the
-- initial pass and again in its Professor-Oak repeat pass. No bespoke
-- Energy-attach branch either (plain processAndTryToPlayEnergy both times,
-- like Articuno's).

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  AI_TRAINER_CARD_PHASE_01 = 1, AI_TRAINER_CARD_PHASE_02 = 2,
  AI_TRAINER_CARD_PHASE_04 = 4, AI_TRAINER_CARD_PHASE_05 = 5,
  AI_TRAINER_CARD_PHASE_07 = 7, AI_TRAINER_CARD_PHASE_10 = 10,
  AI_TRAINER_CARD_PHASE_15 = 15,
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = 0x18,
  DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK = 0x19,
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x20, DUELVARS_HAND = 0x30,
  MAX_PLAY_AREA_POKEMON = 6, DECK_SIZE = 60,
  MOLTRES_LV37 = 1, MUK = 2, TYPE_ENERGY = 8,
  AI_FLAG_USED_PROFESSOR_OAK = 0x04,
}

local CARD_ROWS = { [C.MOLTRES_LV37] = { type = 0 } }

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

-- opts.playAreaCount, opts.notInDeck, opts.muk, opts.hasMoltresInHand,
-- opts.alreadyPlayedEnergy, opts.usedProfessorOak
local function newAI(opts)
  local vars = {
    [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = opts.playAreaCount or 3,
    [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = opts.notInDeck or 10,
  }
  local symbols = {
    wAlreadyPlayedEnergy = opts.alreadyPlayedEnergy or 0,
    wPreviousAIFlags = opts.usedProfessorOak and C.AI_FLAG_USED_PROFESSOR_OAK or 0,
  }
  if opts.hasMoltresInHand then
    vars[C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 1
    vars[C.DUELVARS_HAND] = 100
  else
    vars[C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 0
  end
  local cardIdByDeckIndex = { [100] = C.MOLTRES_LV37 }

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
  local combat = {
    core = { clearNonTurnTemporaryDuelvars = function() end },
    status = {
      countPokemonWithActivePkmnPowerInBothPlayAreas = function(_, cardId)
        check("Muk check uses MUK card id", cardId, C.MUK)
        return 0, opts.muk == true
      end,
    },
  }
  local ai = AI.new(memory, duelVars, { random = function() return 0 end }, cardData, {}, C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} }, {})
  ai.combat = combat

  local calls = {}
  local phaseLog = {}
  local moltresPlayCount = 0
  ai.initTurnVars = function() calls.initTurnVars = true end
  ai.handleAIAntiMewtwoDeckStrategy = function()
    calls.handleAIAntiMewtwoDeckStrategy = true
    return true
  end
  ai.processHandTrainerCards = function(_, phase) phaseLog[#phaseLog + 1] = phase; return true end
  ai.playerActions = {
    playBasic = function(_, cardId)
      moltresPlayCount = moltresPlayCount + 1
      calls.playBasicCount = moltresPlayCount
      check("playBasic called with MoltresLv37", cardId, C.MOLTRES_LV37)
      return true, 0
    end,
  }
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
-- No anti-mill check at all: handleAIAntiMewtwoDeckStrategy is stubbed to
-- record whether it was ever called, and must never be.
-- ---------------------------------------------------------------------
do
  local ai, calls, phases = newAI({})
  ai:doTurnLegendaryRonald()
  check("handleAIAntiMewtwoDeckStrategy is never called", calls.handleAIAntiMewtwoDeckStrategy, nil)
  check("phase 01 processed unconditionally (no anti-mill gate)", phases[1], C.AI_TRAINER_CARD_PHASE_01)
end

-- ---------------------------------------------------------------------
-- MoltresLv37 direct-play gate, reused from Moltres's translation.
-- ---------------------------------------------------------------------
do
  local ai, calls = newAI({ hasMoltresInHand = true })
  ai:doTurnLegendaryRonald()
  check("all gates pass: MoltresLv37 played directly", calls.playBasicCount, 1)
end
do
  local ai, calls = newAI({ hasMoltresInHand = false })
  ai:doTurnLegendaryRonald()
  check("MoltresLv37 not in hand: not played directly", calls.playBasicCount, nil)
end
do
  local ai, calls = newAI({ hasMoltresInHand = true, muk = true })
  ai:doTurnLegendaryRonald()
  check("Muk in play: not played directly", calls.playBasicCount, nil)
end

-- ---------------------------------------------------------------------
-- No Professor Oak: no repeat pass, single MoltresLv37 attempt.
-- ---------------------------------------------------------------------
do
  local ai, calls, phases = newAI({ hasMoltresInHand = true })
  ai:doTurnLegendaryRonald()
  check("no Professor Oak: phase order is 1,2,4,5,7,10,15",
    phases, { C.AI_TRAINER_CARD_PHASE_01, C.AI_TRAINER_CARD_PHASE_02, C.AI_TRAINER_CARD_PHASE_04,
      C.AI_TRAINER_CARD_PHASE_05, C.AI_TRAINER_CARD_PHASE_07, C.AI_TRAINER_CARD_PHASE_10,
      C.AI_TRAINER_CARD_PHASE_15 })
  check("no Professor Oak: decidePlayPokemonCard called twice", calls.decidePlayPokemonCard, 2)
  check("no Professor Oak: MoltresLv37 played once", calls.playBasicCount, 1)
  check("no Professor Oak: processAndTryToPlayEnergy called once", calls.processAndTryToPlayEnergy, 1)
end

-- ---------------------------------------------------------------------
-- Professor Oak used: repeat pass re-runs the MoltresLv37 gate a second
-- time (once per pass, matching the source calling it twice total).
-- ---------------------------------------------------------------------
do
  local ai, calls, phases = newAI({ hasMoltresInHand = true, usedProfessorOak = true })
  ai:doTurnLegendaryRonald()
  check("Professor Oak used: phase order is 1,2,4,5,7,10,15,1,2,4,5,7,10 (no second 15)",
    phases, { C.AI_TRAINER_CARD_PHASE_01, C.AI_TRAINER_CARD_PHASE_02, C.AI_TRAINER_CARD_PHASE_04,
      C.AI_TRAINER_CARD_PHASE_05, C.AI_TRAINER_CARD_PHASE_07, C.AI_TRAINER_CARD_PHASE_10,
      C.AI_TRAINER_CARD_PHASE_15,
      C.AI_TRAINER_CARD_PHASE_01, C.AI_TRAINER_CARD_PHASE_02, C.AI_TRAINER_CARD_PHASE_04,
      C.AI_TRAINER_CARD_PHASE_05, C.AI_TRAINER_CARD_PHASE_07, C.AI_TRAINER_CARD_PHASE_10 })
  check("Professor Oak used: decidePlayPokemonCard called 4 times", calls.decidePlayPokemonCard, 4)
  check("Professor Oak used: MoltresLv37 gate attempted twice", calls.playBasicCount, 2)
  check("Professor Oak used: processRetreat called twice", calls.processRetreat, 2)
  check("Professor Oak used: processAndTryToPlayEnergy called twice", calls.processAndTryToPlayEnergy, 2)
  check("Professor Oak used: still tries to attack", calls.processAndTryToUseAttack, true)
end

if failures == 0 then
  print("all AIDoTurn_LegendaryRonald cases passed")
  os.exit(0)
else
  print(("%d AIDoTurn_LegendaryRonald case(s) failed"):format(failures))
  os.exit(1)
end
