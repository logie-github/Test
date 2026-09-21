-- Behavioral smoke test for Porygon's Mystery Attack, run under real
-- LuaJIT. Closes 2 more of the card-effects backlog.
--
-- An 8-way RNG pick (UpdateRNGSources & %111 -- NOT a coin flip, unlike
-- most random-effect attacks in this game), reusing the four unconditional
-- status handlers (Paralysis/Poison/Sleep/Confusion) directly by name for
-- rolls 0-3. Roll 4 ("recover") does nothing in the random-pick phase
-- itself -- a separate, later effect phase (MysteryAttack_RecoverEffect)
-- checks the relayed roll and only then heals 10. Roll 5 is a pure no-op.
-- Roll 6 overrides the initial 10 damage to 20. Roll 7 zeroes damage and
-- marks "no effect from status" (this game's generic "the attack fails to
-- have its usual effect" flag).

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")
local bit = require("bit")

local C = setmetatable({
  PSN_DBLPSN = "PSN_DBLPSN", CNF_SLP_PRZ = "CNF_SLP_PRZ",
  PARALYZED = "PARALYZED", POISONED = "POISONED", ASLEEP = "ASLEEP", CONFUSED = "CONFUSED",
  ATK_ANIM_GLOW_EFFECT = "ATK_ANIM_GLOW_EFFECT",
  EFFECT_FAILED_NO_EFFECT = "EFFECT_FAILED_NO_EFFECT",
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

local function newEffects(rngByte)
  local memory = { words = {},
    readSymbol8 = function(self, n) return self.words[n] or 0 end,
    writeSymbol8 = function(self, n, v) self.words[n] = v end,
    address = function() return 1000, 0 end,
    read8 = function() return 0 end,
    write8 = function() end,
  }
  local queueCalls = {}
  local status = {
    queueStatusCondition = function(_, mask, condition)
      queueCalls[#queueCalls + 1] = condition
      return true
    end,
  }
  local setup = { rng = { updateSources = function() return rngByte end } }
  local effects = EffectCommands.new(memory, setup, status, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  local actor = {
    duelVars = { get = function() return 0 end, set = function() end,
      getNonTurn = function() return 0 end, swapTurn = function() end },
    cardData = { getCardIDFromDeckIndex = function() return 1 end, get = function() return { hp = 60 } end },
  }
  return effects, memory, queueCalls, actor
end

local cases = {
  { roll = 0, label = "paralysis", queued = C.PARALYZED },
  { roll = 1, label = "poison", queued = C.POISONED },
  { roll = 2, label = "sleep", queued = C.ASLEEP },
  { roll = 3, label = "confusion", queued = C.CONFUSED },
}
for _, case in ipairs(cases) do
  local effects, memory, queueCalls, actor = newEffects(case.roll)
  local carry = effects.handlers["MysteryAttack_RandomEffect"](effects, { combat = actor })
  check(("roll %d (%s): carry true"):format(case.roll, case.label), carry, true)
  check(("roll %d (%s): queues the right status"):format(case.roll, case.label), queueCalls[1], case.queued)
  check(("roll %d (%s): base damage 10 set first"):format(case.roll, case.label),
    memory:readSymbol8("wAIMaxDamage"), 10)
end

-- Roll 4: recover -- does nothing itself, but relays the roll for the
-- later MysteryAttack_RecoverEffect phase to see.
do
  local effects, memory, _, actor = newEffects(4)
  local carry = effects.handlers["MysteryAttack_RandomEffect"](effects, { combat = actor })
  check("roll 4: carry false (no immediate status)", carry, false)
  check("roll 4: relays the roll", memory:readSymbol8("hTemp_ffa0"), 4)
end

-- Roll 5: pure no-op.
do
  local effects, memory, queueCalls, actor = newEffects(5)
  local carry = effects.handlers["MysteryAttack_RandomEffect"](effects, { combat = actor })
  check("roll 5: carry false", carry, false)
  check("roll 5: nothing queued", #queueCalls, 0)
end

-- Roll 6: overrides damage to 20 (checked via a real _setDefiniteDamage
-- write, i.e. wAIMinDamage/wAIMaxDamage both become 20).
do
  local effects, memory, _, actor = newEffects(6)
  effects.handlers["MysteryAttack_RandomEffect"](effects, { combat = actor })
  check("roll 6: max damage overridden to 20", memory:readSymbol8("wAIMaxDamage"), 20)
  check("roll 6: min damage overridden to 20", memory:readSymbol8("wAIMinDamage"), 20)
end

-- Roll 7: zero damage, marks no-effect, sets the glow animation.
do
  local effects, memory, _, actor = newEffects(7)
  local carry = effects.handlers["MysteryAttack_RandomEffect"](effects, { combat = actor })
  check("roll 7: carry false", carry, false)
  check("roll 7: damage zeroed", memory:readSymbol8("wAIMaxDamage"), 0)
  check("roll 7: marks EFFECT_FAILED_NO_EFFECT", memory:readSymbol8("wEffectFailed"), C.EFFECT_FAILED_NO_EFFECT)
  check("roll 7: sets the glow animation", memory:readSymbol8("wLoadedAttackAnimation"), C.ATK_ANIM_GLOW_EFFECT)
end

-- A raw RNG byte above 7 is masked down (e.g. 12 & 7 == 4).
do
  local effects, memory, _, actor = newEffects(12)
  effects.handlers["MysteryAttack_RandomEffect"](effects, { combat = actor })
  check("raw byte 12 masked to roll 4", memory:readSymbol8("hTemp_ffa0"), 4)
end

-- RecoverEffect: heals 10 only when the relayed roll was exactly 4.
do
  local effects, memory, _, actor = newEffects(0)
  memory:writeSymbol8("hTemp_ffa0", 4)
  actor.duelVars = { get = function(_, a)
    if a == "DUELVARS_ARENA_CARD" then return 1 end
    if a == "DUELVARS_ARENA_CARD_HP" then return 40 end
    return 0
  end, set = function() end, getNonTurn = function() return 0 end, swapTurn = function() end }
  local healedTo
  actor.duelVars.set = function(_, a, v) if a == "DUELVARS_ARENA_CARD_HP" then healedTo = v end end
  local carry = effects.handlers["MysteryAttack_RecoverEffect"](effects, { combat = actor })
  check("recover phase: roll==4 heals (carry false)", carry, false)
  check("recover phase: HP increased by 10", healedTo, 50)
end
do
  local effects, memory, _, actor = newEffects(0)
  memory:writeSymbol8("hTemp_ffa0", 6)
  local setCalled = false
  actor.duelVars.set = function() setCalled = true end
  local carry = effects.handlers["MysteryAttack_RecoverEffect"](effects, { combat = actor })
  check("recover phase: roll!=4 does nothing (carry false)", carry, false)
  check("recover phase: roll!=4 never writes HP", setCalled, false)
end

if failures == 0 then
  print("all Mystery Attack effect cases passed")
  os.exit(0)
else
  print(("%d Mystery Attack effect case(s) failed"):format(failures))
  os.exit(1)
end
