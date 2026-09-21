-- Behavioral smoke test for _AIProcessHandTrainerCards' relist cadence
-- (trainer_cards.asm), run under real LuaJIT rather than only checked as
-- source text. Exercises the parts that changed in this round's rewrite:
-- hand-order iteration (not this file's per-phase authoring order),
-- CheckCantUseTrainerDueToEffect/EFFECTCMDTYPE_INITIAL_EFFECT_1 gating
-- ahead of the random-skip gate and the card-specific decision, the
-- relist-on-AI_FLAG_MODIFIED_HAND restart (fresh snapshot, flag cleared,
-- loop restarts from position 1), and the SWITCH already-used skip.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")
local bit = require("bit")

local C = {
  EFFECTCMDTYPE_INITIAL_EFFECT_1 = 1,
  AI_FLAG_MODIFIED_HAND = 0x01, AI_FLAG_USED_SWITCH = 0x02,
  POTION = 100, GUST_OF_WIND = 101, SWITCH = 102, BILL = 103, ITEM_FINDER = 104,
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x10, DUELVARS_HAND = 0x11,
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

-- Builds an AI instance whose processHandTrainerCards collaborators are all
-- controllable: hand snapshots come from `opts.snapshots` (a queue of
-- deckIndex-array tables, consumed one per createHandCardList call, so a
-- test can hand back a DIFFERENT list on relist), card IDs from
-- `opts.cardIdByDeckIndex`, and headache/INITIAL_EFFECT_1 results from
-- `opts.headache`/`opts.initialEffect1Carry` (either a fixed value or a
-- function of deckIndex).
local function newAI(opts)
  opts = opts or {}
  local symbols = {}
  for k, v in pairs(opts.symbols or {}) do symbols[k] = v end
  local memory = {
    readSymbol8 = function(_, name) return symbols[name] or 0 end,
    writeSymbol8 = function(_, name, v) symbols[name] = v end,
  }
  local snapshots = opts.snapshots or { {} }
  local snapshotCalls = 0
  local ai = AI.new(
    memory,
    { get = function() return nil end, getNonTurn = function() return nil end },
    { random = function() return 5 end },
    {
      getCardIDFromDeckIndex = function(_, deckIndex) return opts.cardIdByDeckIndex[deckIndex] end,
    },
    {
      createHandCardList = function()
        snapshotCalls = snapshotCalls + 1
        return snapshots[math.min(snapshotCalls, #snapshots)]
      end,
    },
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
  ai:setCombat({ status = {
    checkCantUseTrainerDueToEffect = function()
      if type(opts.headache) == "function" then return opts.headache() end
      return opts.headache or false
    end,
  } })
  local effectCalls = {}
  ai:setPlayerActions({
    effects = {
      loadNonPokemonCardEffectCommands = function(_, deckIndex) effectCalls[#effectCalls + 1] = deckIndex end,
      tryExecute = function(_, _, _)
        local carry = opts.initialEffect1Carry
        if type(carry) == "function" then carry = carry() end
        return carry or false
      end,
    },
  })
  return ai, symbols, effectCalls, function() return snapshotCalls end
end

-- ---------------------------------------------------------------------
-- Hand-order iteration: two different matching card types in one phase;
-- whichever appears FIRST in the hand snapshot is decided first, not
-- whichever is authored first in AI_TRAINER_PHASES[phase].
-- (Phase 7's authored order is POTION, GUST_OF_WIND, ...)
-- ---------------------------------------------------------------------
do
  local decided = {}
  local ai = newAI({
    snapshots = { { 1, 2 } },
    cardIdByDeckIndex = { [1] = C.GUST_OF_WIND, [2] = C.POTION },
  })
  ai._chooseRandomlyNotToDoAction = function() return false end
  ai._decideTrainer = function(_, constantName)
    decided[#decided + 1] = constantName
    return false
  end
  local ok = ai:processHandTrainerCards(7)
  check("hand-order: scan completes", ok, true)
  check("hand-order: Gust of Wind (hand position 1) decided first", decided[1], "GUST_OF_WIND")
  check("hand-order: Potion (hand position 2) decided second", decided[2], "POTION")
end

-- ---------------------------------------------------------------------
-- CheckCantUseTrainerDueToEffect (headache) gates BEFORE the decision --
-- a blocked card is skipped, never reaching _decideTrainer.
-- ---------------------------------------------------------------------
do
  local decided = {}
  local ai = newAI({
    snapshots = { { 1 } },
    cardIdByDeckIndex = { [1] = C.POTION },
    headache = true,
  })
  ai._decideTrainer = function(_, constantName) decided[#decided + 1] = constantName; return false end
  local ok = ai:processHandTrainerCards(7)
  check("headache gate: scan completes", ok, true)
  check("headache gate: blocked card never reaches the decision", #decided, 0)
end

-- ---------------------------------------------------------------------
-- EFFECTCMDTYPE_INITIAL_EFFECT_1 gates BEFORE the random-skip gate and the
-- decision -- a carry (rejected) card is skipped without either running.
-- ---------------------------------------------------------------------
do
  local decided, randomSkipCalls = {}, 0
  local ai = newAI({
    snapshots = { { 1 } },
    cardIdByDeckIndex = { [1] = C.POTION },
    initialEffect1Carry = true,
  })
  ai._chooseRandomlyNotToDoAction = function() randomSkipCalls = randomSkipCalls + 1; return false end
  ai._decideTrainer = function(_, constantName) decided[#decided + 1] = constantName; return false end
  local ok = ai:processHandTrainerCards(7)
  check("INITIAL_EFFECT_1 gate: scan completes", ok, true)
  check("INITIAL_EFFECT_1 gate: random-skip never runs for a rejected card", randomSkipCalls, 0)
  check("INITIAL_EFFECT_1 gate: decision never runs for a rejected card", #decided, 0)
end

-- ---------------------------------------------------------------------
-- Relist on AI_FLAG_MODIFIED_HAND: a successful play that leaves the flag
-- set in wPreviousAIFlags forces a fresh snapshot and restarts from
-- position 1 -- including re-deciding a card already passed over earlier
-- in the OLD snapshot, and the flag is cleared afterward.
-- ---------------------------------------------------------------------
do
  local decided = {}
  local ai, symbols, _, snapshotCallCount = newAI({
    -- First snapshot: [Bill, Item Finder]. After Bill is "played" (setting
    -- MODIFIED_HAND), relist yields a fresh snapshot: [Item Finder] only
    -- (Bill left hand, a new card arrived but isn't a phase-4 match).
    snapshots = { { 10, 20 }, { 20 } },
    cardIdByDeckIndex = { [10] = C.BILL, [20] = C.ITEM_FINDER },
  })
  ai._chooseRandomlyNotToDoAction = function() return false end
  ai._decideTrainer = function(_, constantName)
    decided[#decided + 1] = constantName
    return constantName == "BILL"
  end
  ai._playTrainerForAI = function(_, constantName)
    if constantName == "BILL" then
      symbols.wPreviousAIFlags = bit.bor(symbols.wPreviousAIFlags or 0, C.AI_FLAG_MODIFIED_HAND)
    end
    return true
  end
  local ok = ai:processHandTrainerCards(4) -- phase 4 = { BILL, ITEM_FINDER }
  check("relist: scan completes", ok, true)
  check("relist: Bill decided once from the first snapshot", decided[1], "BILL")
  check("relist: after Bill's play, a fresh (second) snapshot was taken", snapshotCallCount(), 2)
  check("relist: Item Finder (only entry in the fresh snapshot) decided next", decided[2], "ITEM_FINDER")
  check("relist: exactly two decisions total (no phantom third pass)", #decided, 2)
  check("relist: AI_FLAG_MODIFIED_HAND is cleared after consuming it",
    bit.band(symbols.wPreviousAIFlags or 0, C.AI_FLAG_MODIFIED_HAND), 0)
end

-- ---------------------------------------------------------------------
-- No relist when AI_FLAG_MODIFIED_HAND is NOT set: the scan just
-- continues to the next snapshot position (only one snapshot ever taken).
-- ---------------------------------------------------------------------
do
  local decided = {}
  local ai, _, _, snapshotCallCount = newAI({
    snapshots = { { 1, 2 } },
    cardIdByDeckIndex = { [1] = C.POTION, [2] = C.GUST_OF_WIND },
  })
  ai._chooseRandomlyNotToDoAction = function() return false end
  ai._decideTrainer = function(_, constantName) decided[#decided + 1] = constantName; return true end
  ai._playTrainerForAI = function() return true end -- never sets MODIFIED_HAND
  local ok = ai:processHandTrainerCards(7)
  check("no relist: scan completes", ok, true)
  check("no relist: both hand cards decided from the same snapshot", #decided, 2)
  check("no relist: only one snapshot ever taken", snapshotCallCount(), 1)
end

-- ---------------------------------------------------------------------
-- SWITCH never matches once AI_FLAG_USED_SWITCH is already set in
-- wPreviousAIFlags -- the card is skipped as if it simply didn't match.
-- ---------------------------------------------------------------------
do
  local decided = {}
  local ai = newAI({
    snapshots = { { 1 } },
    cardIdByDeckIndex = { [1] = C.SWITCH },
    symbols = { wPreviousAIFlags = C.AI_FLAG_USED_SWITCH },
  })
  ai._decideTrainer = function(_, constantName) decided[#decided + 1] = constantName; return false end
  local ok = ai:processHandTrainerCards(9) -- phase 9 = { SWITCH }
  check("SWITCH already used: scan completes", ok, true)
  check("SWITCH already used: never reaches the decision", #decided, 0)
end

-- ---------------------------------------------------------------------
-- SWITCH matches normally when AI_FLAG_USED_SWITCH is NOT set.
-- ---------------------------------------------------------------------
do
  local decided = {}
  local ai = newAI({
    snapshots = { { 1 } },
    cardIdByDeckIndex = { [1] = C.SWITCH },
  })
  ai._chooseRandomlyNotToDoAction = function() return false end
  ai._decideTrainer = function(_, constantName) decided[#decided + 1] = constantName; return false end
  local ok = ai:processHandTrainerCards(9)
  check("SWITCH not yet used: reaches the decision", decided[1], "SWITCH")
  check("SWITCH not yet used: scan completes", ok, true)
end

-- ---------------------------------------------------------------------
-- A phase with no AITrainerCardLogic entries at all (e.g. an attack-policy
-- phase number, never a Trainer phase) returns success immediately without
-- touching the hand.
-- ---------------------------------------------------------------------
do
  local snapshotCalls = 0
  local ai = newAI({
    snapshots = { { 1 } },
    cardIdByDeckIndex = { [1] = C.POTION },
  })
  local realCreate = ai.duelOps.createHandCardList
  ai.duelOps.createHandCardList = function(...)
    snapshotCalls = snapshotCalls + 1
    return realCreate(...)
  end
  local ok = ai:processHandTrainerCards(99)
  check("unknown phase: returns success", ok, true)
  check("unknown phase: never takes a hand snapshot", snapshotCalls, 0)
end

-- ---------------------------------------------------------------------
-- A card ID with no AI_TRAINER_PHASES entry anywhere (not a Trainer this
-- file's AI logic ever plays) is a harmless skip, not a crash.
-- ---------------------------------------------------------------------
do
  local decided = {}
  local ai = newAI({
    snapshots = { { 1, 2 } },
    cardIdByDeckIndex = { [1] = 9999, [2] = C.POTION }, -- 9999 = some unrelated card
  })
  ai._chooseRandomlyNotToDoAction = function() return false end
  ai._decideTrainer = function(_, constantName) decided[#decided + 1] = constantName; return false end
  local ok = ai:processHandTrainerCards(7)
  check("unrelated card ID: skipped without matching anything", ok, true)
  check("unrelated card ID: only the real Trainer card was decided", decided[1], "POTION")
  check("unrelated card ID: exactly one decision", #decided, 1)
end

if failures == 0 then
  print("all _AIProcessHandTrainerCards relist cadence cases passed")
  os.exit(0)
else
  print(("%d _AIProcessHandTrainerCards relist cadence case(s) failed"):format(failures))
  os.exit(1)
end
