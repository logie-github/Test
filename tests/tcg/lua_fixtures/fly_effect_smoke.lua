-- Behavioral smoke test for Pidgeot's Fly, run under real LuaJIT.
--
-- Found by running the real RomExtractor against a from-source-built,
-- byte-identical poketcg.gbc (SHA-1 matches rom.sha1 exactly) and checking
-- EffectCommands.lua's actual runtime handlers against every real function
-- label the ROM's 317 effect-command lists reference: this was the one
-- genuine gap (568/569), never previously caught by any prior sweep.
--
-- Unlike protectCoin's tails branch (a bare SetWasUnsuccessful), Fly's
-- tails branch also explicitly resets the animation to none and zeroes
-- damage via SetDefiniteDamage (touching the AI hint fields too).

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = setmetatable({
  HEADS = "HEADS", TAILS = "TAILS",
  ATK_ANIM_NONE = "ATK_ANIM_NONE", ATK_ANIM_AGILITY_PROTECT = "ATK_ANIM_AGILITY_PROTECT",
  SUBSTATUS1_FLY = "SUBSTATUS1_FLY",
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
  local setup = { tossCoin = function() return coinResult end }
  local substatusCalls = {}
  local status = { applySubstatus1ToAttackingCard = function(_, value)
    substatusCalls[#substatusCalls + 1] = value
  end }
  local effects = EffectCommands.new(memory, setup, status, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  return effects, memory, substatusCalls
end

-- Heads: applies the Fly substatus and sets the agility-protect animation.
do
  local effects, memory, substatusCalls = newEffects(C.HEADS)
  local carry = effects.handlers["Fly_Success50PercentEffect"](effects)
  check("heads: carry false", carry, false)
  check("heads: sets agility-protect animation",
    memory:readSymbol8("wLoadedAttackAnimation"), C.ATK_ANIM_AGILITY_PROTECT)
  check("heads: applies SUBSTATUS1_FLY", substatusCalls[1], C.SUBSTATUS1_FLY)
  check("heads: no failure flag set", memory:readSymbol8("wEffectFailed"), 0)
end

-- Tails: resets animation to none, zeroes damage, marks unsuccessful.
do
  local effects, memory, substatusCalls = newEffects(C.TAILS)
  local carry = effects.handlers["Fly_Success50PercentEffect"](effects)
  check("tails: carry false", carry, false)
  check("tails: resets animation to none",
    memory:readSymbol8("wLoadedAttackAnimation"), C.ATK_ANIM_NONE)
  check("tails: no substatus applied", #substatusCalls, 0)
  check("tails: marks EFFECT_FAILED_UNSUCCESSFUL",
    memory:readSymbol8("wEffectFailed"), C.EFFECT_FAILED_UNSUCCESSFUL)
end

if failures == 0 then
  print("all fly effect cases passed")
  os.exit(0)
else
  print(("%d fly effect case(s) failed"):format(failures))
  os.exit(1)
end
