-- Behavioral smoke test for a third batch of standalone card effects, run
-- under real LuaJIT. Closes 8 more of the card-effects backlog.
--
-- ToxicGasEffect/StrikesBackEffect/RetreatAidEffect: pure EFFECTCMDTYPE_
-- INITIAL_EFFECT_1 stubs (`scf; ret` in the source, always carry) --
-- confirmed each real command list uses only that one phase, the same
-- "triggered-only Power" shape as the already-translated Quickfreeze/
-- Firegiver/HealingWind/PealOfThunder/Transparency/PrehistoricPower/
-- Clairvoyance/InvisibleWall/NeutralizingShield/KabutoArmor/ThickSkinned
-- stubs.
-- SingEffect/SleepingGasEffect: coin heads inflicts ASLEEP, tails marks
-- "no effect" -- the exact same shape as the already-translated Supersonic
-- family, just Sleep instead of Confused.
-- HeadacheEffect: sets the SUBSTATUS3_HEADACHE_F bit on the Defending
-- Pokemon's SUBSTATUS3, unconditional, no coin, preserving other bits.
-- FoulOdorEffect: confuses BOTH active Pokemon unconditionally -- plain
-- ConfusionEffect, then SwapTurn, ConfusionEffect, SwapTurn back.
-- TantrumEffect: heads does nothing; tails sets the multiple-slash
-- animation and confuses the ATTACKER'S OWN side (SwapTurn bracketed
-- ConfusionEffect call).

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")
local bit = require("bit")

local C = setmetatable({
  HEADS = "HEADS", TAILS = "TAILS",
  PSN_DBLPSN = "PSN_DBLPSN", ASLEEP = "ASLEEP", CONFUSED = "CONFUSED",
  EFFECT_FAILED_NO_EFFECT = "EFFECT_FAILED_NO_EFFECT",
  ATK_ANIM_MULTIPLE_SLASH = "ATK_ANIM_MULTIPLE_SLASH", ATK_ANIM_NONE = 0,
  DUELVARS_ARENA_CARD_SUBSTATUS3 = "DUELVARS_ARENA_CARD_SUBSTATUS3",
  SUBSTATUS3_HEADACHE_F = 3,
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

local function newEffects(coinResult)
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
  local setup = { tossCoin = function() return coinResult end }
  local effects = EffectCommands.new(memory, setup, status, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  return effects, memory, queueCalls
end

-- Pure stubs: always carry, no matter the constructor-level state.
for _, name in ipairs({ "ToxicGasEffect", "StrikesBackEffect", "RetreatAidEffect" }) do
  local effects = newEffects()
  check(name .. ": always carry true", effects.handlers[name](effects), true)
end

-- SingEffect/SleepingGasEffect: heads.
for _, name in ipairs({ "SingEffect", "SleepingGasEffect" }) do
  local effects, memory, queueCalls = newEffects(C.HEADS)
  local carry = effects.handlers[name](effects)
  check(name .. " heads: carry true (asleep applied)", carry, true)
  check(name .. " heads: queues ASLEEP", queueCalls[1], C.ASLEEP)
  check(name .. " heads: no failure flag set", memory:readSymbol8("wEffectFailed"), 0)
end

-- SingEffect/SleepingGasEffect: tails.
for _, name in ipairs({ "SingEffect", "SleepingGasEffect" }) do
  local effects, memory, queueCalls = newEffects(C.TAILS)
  local carry = effects.handlers[name](effects)
  check(name .. " tails: carry false (no effect)", carry, false)
  check(name .. " tails: no status queued", #queueCalls, 0)
  check(name .. " tails: marks EFFECT_FAILED_NO_EFFECT",
    memory:readSymbol8("wEffectFailed"), C.EFFECT_FAILED_NO_EFFECT)
end

-- HeadacheEffect: sets the bit on the non-turn side, preserving other bits.
do
  local effects, memory = newEffects()
  local nonTurnWrites = {}
  local actor = {
    duelVars = {
      getNonTurn = function(_, addr)
        check("headache: reads SUBSTATUS3", addr, C.DUELVARS_ARENA_CARD_SUBSTATUS3)
        return 0x04 -- some unrelated bit already set
      end,
      setNonTurn = function(_, addr, value) nonTurnWrites[#nonTurnWrites + 1] = { addr = addr, value = value } end,
    },
  }
  local carry = effects.handlers["HeadacheEffect"](effects, { combat = actor })
  check("headache: carry false", carry, false)
  check("headache: exactly one write", #nonTurnWrites, 1)
  check("headache: writes SUBSTATUS3", nonTurnWrites[1].addr, C.DUELVARS_ARENA_CARD_SUBSTATUS3)
  check("headache: sets HEADACHE bit, keeps prior bit",
    nonTurnWrites[1].value, bit.bor(0x04, bit.lshift(1, C.SUBSTATUS3_HEADACHE_F)))
end

-- FoulOdorEffect: confuses both sides -- one plain call, one swapTurn-bracketed.
do
  local effects = newEffects()
  local swapCount = 0
  local actor = { duelVars = { swapTurn = function() swapCount = swapCount + 1 end } }
  local carry = effects.handlers["FoulOdorEffect"](effects, { combat = actor })
  check("foul odor: carry false", carry, false)
  check("foul odor: swapTurn called twice (bracket)", swapCount, 2)
end

-- TantrumEffect: heads -- nothing happens.
do
  local effects, memory = newEffects(C.HEADS)
  local swapCount = 0
  local actor = { duelVars = { swapTurn = function() swapCount = swapCount + 1 end } }
  local carry = effects.handlers["TantrumEffect"](effects, { combat = actor })
  check("tantrum heads: carry false", carry, false)
  check("tantrum heads: no swapTurn", swapCount, 0)
  check("tantrum heads: no animation set", memory:readSymbol8("wLoadedAttackAnimation"), C.ATK_ANIM_NONE)
end

-- TantrumEffect: tails -- confuses own side.
do
  local effects, memory = newEffects(C.TAILS)
  local swapCount = 0
  local actor = { duelVars = { swapTurn = function() swapCount = swapCount + 1 end } }
  local carry = effects.handlers["TantrumEffect"](effects, { combat = actor })
  check("tantrum tails: carry false", carry, false)
  check("tantrum tails: swapTurn called twice (bracket)", swapCount, 2)
  check("tantrum tails: sets multiple-slash animation",
    memory:readSymbol8("wLoadedAttackAnimation"), C.ATK_ANIM_MULTIPLE_SLASH)
end

if failures == 0 then
  print("all standalone effects batch 3 cases passed")
  os.exit(0)
else
  print(("%d standalone effects batch 3 case(s) failed"):format(failures))
  os.exit(1)
end
