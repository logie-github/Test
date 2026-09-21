-- Behavioral smoke test for a second batch of standalone card effects, run
-- under real LuaJIT. Closes 6 more of the card-effects backlog.
--
-- Clairvoyance/InvisibleWall/NeutralizingShield/KabutoArmor/ThickSkinned:
-- pure EFFECTCMDTYPE_INITIAL_EFFECT_1 stubs (`scf; ret` in the source,
-- always carry), confirmed each real command list uses only that one
-- phase -- same "triggered-only Power" shape as the already-translated
-- Quickfreeze/Firegiver/HealingWind/PealOfThunder/Transparency/Prehistoric
-- Power stubs.
-- Clamp: heads keeps the printed damage and jumps straight into the plain
-- (unconditional) ParalysisEffect, already registered elsewhere in this
-- file and reused directly by name; tails zeroes damage and marks the
-- attack unsuccessful.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = setmetatable({
  HEADS = "HEADS", TAILS = "TAILS",
  ATK_ANIM_HIT_EFFECT = "ATK_ANIM_HIT_EFFECT", ATK_ANIM_NONE = 0,
  PSN_DBLPSN = "PSN_DBLPSN", PARALYZED = "PARALYZED",
  EFFECT_FAILED_UNSUCCESSFUL = "EFFECT_FAILED_UNSUCCESSFUL",
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
for _, name in ipairs({
  "ClairvoyanceEffect", "InvisibleWallEffect", "NeutralizingShieldEffect",
  "KabutoArmorEffect", "ThickSkinnedEffect",
}) do
  local effects = newEffects()
  check(name .. ": always carry true", effects.handlers[name](effects), true)
end

-- Clamp: heads.
do
  local effects, memory, queueCalls = newEffects(C.HEADS)
  local carry = effects.handlers["ClampEffect"](effects)
  check("clamp heads: sets hit-effect animation", memory:readSymbol8("wLoadedAttackAnimation"),
    C.ATK_ANIM_HIT_EFFECT)
  check("clamp heads: carry true (paralysis applied)", carry, true)
  check("clamp heads: queues PARALYZED", queueCalls[1], C.PARALYZED)
end

-- Clamp: tails.
do
  local effects, memory, queueCalls = newEffects(C.TAILS)
  local carry = effects.handlers["ClampEffect"](effects)
  check("clamp tails: carry false (unsuccessful)", carry, false)
  check("clamp tails: no status queued", #queueCalls, 0)
  check("clamp tails: animation reset to none", memory:readSymbol8("wLoadedAttackAnimation"), C.ATK_ANIM_NONE)
  check("clamp tails: marks EFFECT_FAILED_UNSUCCESSFUL",
    memory:readSymbol8("wEffectFailed"), C.EFFECT_FAILED_UNSUCCESSFUL)
end

if failures == 0 then
  print("all standalone effects batch 2 cases passed")
  os.exit(0)
else
  print(("%d standalone effects batch 2 case(s) failed"):format(failures))
  os.exit(1)
end
