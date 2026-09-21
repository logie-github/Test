-- Behavioral smoke test for Slowpoke's Spacing Out and Venusaur's Solar
-- Power, run under real LuaJIT. Closes the last 4 grouped card-effects
-- backlog names.
--
-- SpacingOut_CheckDamage: same damage-check shape as FirstAid_DamageCheck.
-- SpacingOut_Success50PercentEffect: coin flip; heads sets the Recover
-- animation, tails marks the attack unsuccessful -- either way the raw
-- coin result is stashed in hTemp_ffa0 for the later heal phase.
-- SpacingOut_HealEffect: skips on a stashed tails result or on no
-- remaining damage; otherwise a raw +10 HP add (not the clamped
-- _healAttackingArena helper -- safe because CheckDamage already
-- guaranteed damage >= 10).
-- SolarPower_CheckUse: usable once per turn, and only while at least one
-- active Pokemon (either side) has a status condition.
-- SolarPower_RemoveStatusEffect: marks the Power used and clears both
-- sides' status unconditionally.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")
local bit = require("bit")

local C = setmetatable({
  HEADS = "HEADS", TAILS = "TAILS",
  ATK_ANIM_RECOVER = "ATK_ANIM_RECOVER", ATK_ANIM_HEAL_BOTH_SIDES = "ATK_ANIM_HEAL_BOTH_SIDES",
  EFFECT_FAILED_UNSUCCESSFUL = "EFFECT_FAILED_UNSUCCESSFUL",
  DUELVARS_ARENA_CARD = 0x10, DUELVARS_ARENA_CARD_HP = 0x20,
  DUELVARS_ARENA_CARD_FLAGS = 0x30, DUELVARS_ARENA_CARD_STATUS = 0x40,
  PLAY_AREA_ARENA = 0, USED_PKMN_POWER_THIS_TURN_F = 5, NO_STATUS = 0,
  POISONED = 7,
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

local function newSpacingOutEffects(opts)
  opts = opts or {}
  local words = {}
  local memory = { words = {},
    readSymbol8 = function(self, n) return self.words[n] or 0 end,
    writeSymbol8 = function(self, n, v) self.words[n] = v end,
    address = function() return 1000, 0 end,
    read8 = function() return 0 end,
    write8 = function() end,
  }
  local setup = { tossCoin = function() return opts.coin end }
  local effects = EffectCommands.new(memory, setup, {}, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  local hpWrites = {}
  local actor = {
    duelVars = {
      get = function(_, addr)
        if addr == C.DUELVARS_ARENA_CARD then return 0 end
        if addr == C.DUELVARS_ARENA_CARD_HP then return opts.hp or 0 end
      end,
      set = function(_, addr, value)
        check("writes to the arena HP slot", addr, C.DUELVARS_ARENA_CARD_HP)
        hpWrites[#hpWrites + 1] = value
      end,
    },
    cardData = {
      getCardIDFromDeckIndex = function() return 1 end,
      get = function() return { hp = opts.maxHp or 100 } end,
    },
  }
  return effects, actor, memory, hpWrites
end

-- SpacingOut_CheckDamage
do
  local effects, actor = newSpacingOutEffects({ hp = 90, maxHp = 100 })
  check("check damage: 10 damage passes (carry false)",
    effects.handlers["SpacingOut_CheckDamage"](effects, { combat = actor }), false)
end
do
  local effects, actor = newSpacingOutEffects({ hp = 95, maxHp = 100 })
  check("check damage: 5 damage fails (carry true)",
    effects.handlers["SpacingOut_CheckDamage"](effects, { combat = actor }), true)
end

-- SpacingOut_Success50PercentEffect
do
  local effects, _, memory = newSpacingOutEffects({ coin = C.HEADS })
  local carry = effects.handlers["SpacingOut_Success50PercentEffect"](effects)
  check("success heads: carry false", carry, false)
  check("success heads: stashes HEADS", memory:readSymbol8("hTemp_ffa0"), C.HEADS)
  check("success heads: sets recover animation",
    memory:readSymbol8("wLoadedAttackAnimation"), C.ATK_ANIM_RECOVER)
end
do
  local effects, _, memory = newSpacingOutEffects({ coin = C.TAILS })
  local carry = effects.handlers["SpacingOut_Success50PercentEffect"](effects)
  check("success tails: carry false", carry, false)
  check("success tails: stashes TAILS", memory:readSymbol8("hTemp_ffa0"), C.TAILS)
  check("success tails: marks unsuccessful",
    memory:readSymbol8("wEffectFailed"), C.EFFECT_FAILED_UNSUCCESSFUL)
end

-- SpacingOut_HealEffect
do
  local effects, actor, memory, hpWrites = newSpacingOutEffects({ hp = 80, maxHp = 100 })
  memory:writeSymbol8("hTemp_ffa0", C.HEADS)
  local carry = effects.handlers["SpacingOut_HealEffect"](effects, { combat = actor })
  check("heal, heads with damage: carry false", carry, false)
  check("heal, heads with damage: raw +10 add", hpWrites[1], 90)
end
do
  local effects, actor, memory, hpWrites = newSpacingOutEffects({ hp = 80, maxHp = 100 })
  memory:writeSymbol8("hTemp_ffa0", C.TAILS)
  local carry = effects.handlers["SpacingOut_HealEffect"](effects, { combat = actor })
  check("heal, tails: carry false", carry, false)
  check("heal, tails: no HP write", #hpWrites, 0)
end
do
  local effects, actor, memory, hpWrites = newSpacingOutEffects({ hp = 100, maxHp = 100 })
  memory:writeSymbol8("hTemp_ffa0", C.HEADS)
  local carry = effects.handlers["SpacingOut_HealEffect"](effects, { combat = actor })
  check("heal, heads but no damage: carry false", carry, false)
  check("heal, heads but no damage: no HP write", #hpWrites, 0)
end

local function newSolarPowerEffects(opts)
  opts = opts or {}
  local memory = { words = {},
    readSymbol8 = function(self, n) return self.words[n] or 0 end,
    writeSymbol8 = function(self, n, v) self.words[n] = v end,
  }
  local status = { checkIsIncapableOfUsingPkmnPower = function() return opts.incapable == true end }
  local effects = EffectCommands.new(memory, {}, status, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  local flagWrites = {}
  local statusWrites = { own = {}, nonTurn = {} }
  local actor = {
    duelVars = {
      get = function(_, addr)
        if addr == C.DUELVARS_ARENA_CARD_FLAGS then return opts.flags or 0 end
        if addr == C.DUELVARS_ARENA_CARD_STATUS then return opts.ownStatus or 0 end
      end,
      getNonTurn = function(_, addr)
        if addr == C.DUELVARS_ARENA_CARD_STATUS then return opts.nonTurnStatus or 0 end
      end,
      set = function(_, addr, value)
        if addr == C.DUELVARS_ARENA_CARD_FLAGS then flagWrites[#flagWrites + 1] = value
        elseif addr == C.DUELVARS_ARENA_CARD_STATUS then statusWrites.own[#statusWrites.own + 1] = value end
      end,
      setNonTurn = function(_, addr, value)
        if addr == C.DUELVARS_ARENA_CARD_STATUS then statusWrites.nonTurn[#statusWrites.nonTurn + 1] = value end
      end,
    },
  }
  return effects, actor, memory, flagWrites, statusWrites
end

-- SolarPower_CheckUse
do
  local effects, actor = newSolarPowerEffects({ flags = bit.lshift(1, C.USED_PKMN_POWER_THIS_TURN_F) })
  check("check use: already used this turn -> carry true",
    effects.handlers["SolarPower_CheckUse"](effects, { combat = actor }), true)
end
do
  local effects, actor = newSolarPowerEffects({ incapable = true })
  check("check use: incapable -> carry true",
    effects.handlers["SolarPower_CheckUse"](effects, { combat = actor }), true)
end
do
  local effects, actor = newSolarPowerEffects({ ownStatus = 0, nonTurnStatus = 0 })
  check("check use: neither side has status -> carry true",
    effects.handlers["SolarPower_CheckUse"](effects, { combat = actor }), true)
end
do
  local effects, actor = newSolarPowerEffects({ ownStatus = C.POISONED, nonTurnStatus = 0 })
  check("check use: own side has status -> carry false",
    effects.handlers["SolarPower_CheckUse"](effects, { combat = actor }), false)
end
do
  local effects, actor = newSolarPowerEffects({ ownStatus = 0, nonTurnStatus = C.POISONED })
  check("check use: opponent side has status -> carry false",
    effects.handlers["SolarPower_CheckUse"](effects, { combat = actor }), false)
end

-- SolarPower_RemoveStatusEffect
do
  local effects, actor, memory, flagWrites, statusWrites = newSolarPowerEffects({
    flags = 0, ownStatus = C.POISONED, nonTurnStatus = 0,
  })
  local carry = effects.handlers["SolarPower_RemoveStatusEffect"](effects, { combat = actor })
  check("remove status: carry false", carry, false)
  check("remove status: sets heal-both-sides animation",
    memory:readSymbol8("wLoadedAttackAnimation"), C.ATK_ANIM_HEAL_BOTH_SIDES)
  check("remove status: marks the power used",
    bit.band(flagWrites[1], bit.lshift(1, C.USED_PKMN_POWER_THIS_TURN_F)), bit.lshift(1, C.USED_PKMN_POWER_THIS_TURN_F))
  check("remove status: clears own status", statusWrites.own[1], C.NO_STATUS)
  check("remove status: clears non-turn status", statusWrites.nonTurn[1], C.NO_STATUS)
end

if failures == 0 then
  print("all spacing out / solar power effect cases passed")
  os.exit(0)
else
  print(("%d spacing out / solar power effect case(s) failed"):format(failures))
  os.exit(1)
end
