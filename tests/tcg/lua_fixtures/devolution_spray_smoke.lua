-- Behavioral smoke test for Devolution Spray (Trainer), run under real
-- LuaJIT. Closes 3 more of the card-effects backlog found by the same
-- runtime introspection sweep as selfdestruct_effect_smoke.lua.
--
-- Unlike Devolution Beam (an attack, either side), Devolution Spray only
-- targets the Turn Duelist's own Play Area, and can repeat the devolution
-- multiple times on the same chosen card in one use (the source's own
-- "devolve again or finish" menu loop, modeled here as a step count chosen
-- up front rather than re-implementing that loop). Reuses the exact same
-- cardOneStageBelow primitive Devolution Beam uses, and the same
-- combat.status:handleDestinyBondSubstatus + combat.knockouts:
-- handlePendingResolution pair Curse's damage-transfer effect already calls,
-- for the identical reason (Trainer cards don't fall through the shared
-- attack AFTER_DAMAGE/KO pipeline, so the source calls this explicitly).

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")
local bit = require("bit")

local C = setmetatable({
  PLAY_AREA_ARENA = 0, PLAY_AREA_BENCH_1 = 1,
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = 0x50,
  DUELVARS_ARENA_CARD = 0x60, DUELVARS_ARENA_CARD_HP = 0x70, DUELVARS_ARENA_CARD_STAGE = 0x80,
  CARD_LOCATION_PLAY_AREA = 0x10,
  BASIC = 0, STAGE1 = 1, STAGE2 = 2, STAGE2_WITHOUT_STAGE1 = 3,
  TYPE_ENERGY = 8, DECK_SIZE = 60,
}, { __index = function(_, k) return k end })

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(("FAIL  %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
  else
    print(("ok    %s"):format(label))
  end
end

-- cards: {deckIndex -> {cardId=.., stage=.., hp=maxHp}}, playArea: {slot -> deckIndex}
local function newHarness(opts)
  local turn = {}
  local location = {}
  local cardById = {}
  local cardIdByDeckIndex = {}
  for deckIndex, card in pairs(opts.cards or {}) do
    cardIdByDeckIndex[deckIndex] = card.cardId
    cardById[card.cardId] = { hp = card.hp, stage = card.stage, type = 0 }
  end
  local maxCount = 0
  for slot, deckIndex in pairs(opts.playArea or {}) do
    turn[C.DUELVARS_ARENA_CARD + slot] = deckIndex
    location[deckIndex] = bit.bor(C.CARD_LOCATION_PLAY_AREA, slot)
    maxCount = math.max(maxCount, slot + 1)
  end
  for deckIndex, slot in pairs(opts.attachedTo or {}) do
    location[deckIndex] = C.CARD_LOCATION_PLAY_AREA + slot
  end
  turn[C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = opts.playAreaCount or maxCount
  for slot, hp in pairs(opts.hp or {}) do turn[C.DUELVARS_ARENA_CARD_HP + slot] = hp end
  for slot, stage in pairs(opts.stage or {}) do turn[C.DUELVARS_ARENA_CARD_STAGE + slot] = stage end

  local discardCalls = {}
  local actor = {
    duelVars = {
      get = function(_, a)
        if turn[a] ~= nil then return turn[a] end
        return location[a] or 0
      end,
      set = function(_, a, v) turn[a] = v end,
      getNonTurn = function() return 0 end, swapTurn = function() end,
    },
    cardData = {
      getCardIDFromDeckIndex = function(_, deckIndex) return cardIdByDeckIndex[deckIndex] end,
      get = function(_, cardId) return cardById[cardId] end,
    },
    duelOps = {
      putCardInDiscardPile = function(_, deckIndex) discardCalls[#discardCalls + 1] = deckIndex end,
      clearAllStatusConditions = function() end,
    },
  }
  local memory = { words = {},
    readSymbol8 = function(self, n) return self.words[n] or 0 end,
    writeSymbol8 = function(self, n, v) self.words[n] = v end,
  }
  local effects = EffectCommands.new(memory, {}, {}, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  return effects, actor, discardCalls
end

-- PlayAreaEvolutionCheck: fails when everything is Basic.
do
  local effects, actor = newHarness({
    cards = { [1] = { cardId = 1, stage = C.BASIC, hp = 60 } },
    playArea = { [0] = 1 },
  })
  local carry = effects.handlers["DevolutionSpray_PlayAreaEvolutionCheck"](effects, { combat = actor })
  check("no evolved Pokemon -> fail (carry true)", carry, true)
end
do
  local effects, actor = newHarness({
    cards = { [1] = { cardId = 1, stage = C.STAGE1, hp = 90 } },
    playArea = { [0] = 1 },
  })
  local carry = effects.handlers["DevolutionSpray_PlayAreaEvolutionCheck"](effects, { combat = actor })
  check("an evolved Pokemon present -> ok (carry false)", carry, false)
end

-- PlayerSelection: rejects a Basic target, rejects a bad step count, relays
-- a valid selection into effectState.
do
  local effects, actor = newHarness({
    cards = { [1] = { cardId = 1, stage = C.BASIC, hp = 60 } },
    playArea = { [0] = 1 },
  })
  local context = { combat = actor, selection = { playArea = 0, devolutionSteps = 1 } }
  local carry, err = effects.handlers["DevolutionSpray_PlayerSelection"](effects, context)
  check("selecting a Basic target -> rejected", carry, nil)
  check("rejection reason", err, "invalid_selection:devolutionPlayArea")
end
do
  local effects, actor = newHarness({
    cards = { [1] = { cardId = 1, stage = C.STAGE2, hp = 100 } },
    playArea = { [0] = 1 }, stage = { [0] = C.STAGE2 },
  })
  local context = { combat = actor, selection = { playArea = 0, devolutionSteps = 0 } }
  local carry, err = effects.handlers["DevolutionSpray_PlayerSelection"](effects, context)
  check("zero devolution steps -> rejected", carry, nil)
  check("rejection reason", err, "invalid_selection:devolutionSteps")
end
do
  local effects, actor = newHarness({
    cards = { [1] = { cardId = 1, stage = C.STAGE2, hp = 100 } },
    playArea = { [0] = 1 }, stage = { [0] = C.STAGE2 },
  })
  local context = { combat = actor, selection = { playArea = 0, devolutionSteps = 2 } }
  local carry = effects.handlers["DevolutionSpray_PlayerSelection"](effects, context)
  check("valid selection -> carry false", carry, false)
  check("relays chosen slot", context.effectState.devolutionPlayArea, 0)
  check("relays chosen step count", context.effectState.devolutionSteps, 2)
end

-- DevolutionEffect: single step, carrying damage forward onto the lower
-- stage's max HP, discarding exactly the old card, triggering the KO check.
do
  -- Stage1 (id=2, hp 90) with a Basic pre-evolution (id=1, hp 60) in the
  -- same Play Area location. Current HP 30 (60 damage taken).
  local effects, actor, discards = newHarness({
    cards = { [1] = { cardId = 1, stage = C.BASIC, hp = 60 }, [2] = { cardId = 2, stage = C.STAGE1, hp = 90 } },
    playArea = { [0] = 2 }, attachedTo = { [1] = 0 },
    hp = { [0] = 30 }, stage = { [0] = C.STAGE1 },
  })
  local knockoutCalls = 0
  actor.status = { handleDestinyBondSubstatus = function() end }
  actor.knockouts = { handlePendingResolution = function() knockoutCalls = knockoutCalls + 1; return false end }
  local context = { combat = actor, effectState = { devolutionPlayArea = 0, devolutionSteps = 1 } }
  local carry, err = effects.handlers["DevolutionSpray_DevolutionEffect"](effects, context)
  check("single devolution: carry false", carry, false)
  check("single devolution: slot now holds the Basic", actor.duelVars:get(C.DUELVARS_ARENA_CARD + 0), 1)
  check("single devolution: damage carried forward, clamped at zero (60 dmg on a 60-HP Basic)",
    actor.duelVars:get(C.DUELVARS_ARENA_CARD_HP + 0), 0)
  check("single devolution: stage updated to Basic", actor.duelVars:get(C.DUELVARS_ARENA_CARD_STAGE + 0), C.BASIC)
  check("single devolution: discards exactly the old Stage1 card", discards[1], 2)
  check("single devolution: discards nothing else", #discards, 1)
  check("single devolution: KO resolution invoked", knockoutCalls, 1)
end
do
  -- Same setup but with less damage taken, to confirm the carried-forward
  -- damage arithmetic (not always clamped to zero).
  local effects, actor, discards = newHarness({
    cards = { [1] = { cardId = 1, stage = C.BASIC, hp = 60 }, [2] = { cardId = 2, stage = C.STAGE1, hp = 90 } },
    playArea = { [0] = 2 }, attachedTo = { [1] = 0 },
    hp = { [0] = 80 }, stage = { [0] = C.STAGE1 }, -- 10 damage taken
  })
  actor.status = { handleDestinyBondSubstatus = function() end }
  actor.knockouts = { handlePendingResolution = function() return false end }
  local context = { combat = actor, effectState = { devolutionPlayArea = 0, devolutionSteps = 1 } }
  effects.handlers["DevolutionSpray_DevolutionEffect"](effects, context)
  check("light damage: carried forward onto lower max HP (60-10)",
    actor.duelVars:get(C.DUELVARS_ARENA_CARD_HP + 0), 50)
end

if failures == 0 then
  print("all Devolution Spray effect cases passed")
  os.exit(0)
else
  print(("%d Devolution Spray effect case(s) failed"):format(failures))
  os.exit(1)
end
