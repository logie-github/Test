-- Behavioral smoke test for CatPunchEffect/SlicingWindEffect/FirstAid_
-- DamageCheck, run under real LuaJIT. Closes 3 more of the card-effects
-- backlog.
--
-- CatPunchEffect/SlicingWindEffect: PickRandomPlayAreaCard on the
-- opponent's side (plain Random(count), no self-exclusion or re-roll --
-- unlike the own/opponent-coin-pick RandomlyDamagePlayAreaPokemon
-- primitive used by the still-deferred BigThunder/MagneticStorm), then
-- straight into DealDamageToPlayAreaPokemon (Cat Punch: 20 damage, its own
-- animation; Slicing Wind: 30 damage, the shared "regular anim" bench-hit
-- animation).
-- FirstAid_DamageCheck: fails (carry true) unless the attacker's own Arena
-- Pokemon has at least 10 damage counters -- the same _playAreaDamage
-- read already used by the paired, already-translated FirstAid_HealEffect.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = setmetatable({
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = "DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA",
  DUELVARS_ARENA_CARD = 0x10, DUELVARS_ARENA_CARD_HP = 0x20,
  PLAY_AREA_ARENA = 0,
  ATK_ANIM_CAT_PUNCH_PLAY_AREA = "ATK_ANIM_CAT_PUNCH_PLAY_AREA",
  ATK_ANIM_BENCH_HIT = "ATK_ANIM_BENCH_HIT", ATK_ANIM_NONE = 0,
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

local function newEffects(randomResult)
  local memory = { words = {},
    readSymbol8 = function(self, n) return self.words[n] or 0 end,
    writeSymbol8 = function(self, n, v) self.words[n] = v end,
  }
  local setup = { rng = { random = function(_, maxExclusive)
    check("random: max exclusive is opponent's play area count", maxExclusive, 3)
    return randomResult
  end } }
  local effects = EffectCommands.new(memory, setup, {}, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  return effects, memory
end

-- CatPunchEffect / SlicingWindEffect: pick a random opponent slot, deal
-- fixed damage, set the expected animation.
for _, case in ipairs({
  { name = "CatPunchEffect", amount = 20, anim = C.ATK_ANIM_CAT_PUNCH_PLAY_AREA },
  { name = "SlicingWindEffect", amount = 30, anim = C.ATK_ANIM_BENCH_HIT },
}) do
  local effects, memory = newEffects(2)
  local calls = {}
  local combat = {
    duelVars = { getNonTurn = function(_, addr)
      check(case.name .. ": reads opponent's play area count", addr, C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
      return 3
    end },
    dealDamageToPlayAreaPokemon = function(_, slot, amount, targetNonTurn)
      calls[#calls + 1] = { slot = slot, amount = amount, targetNonTurn = targetNonTurn }
      return 1
    end,
  }
  local carry = effects.handlers[case.name](effects, { combat = combat })
  check(case.name .. ": carry false", carry, false)
  check(case.name .. ": exactly one damage call", #calls, 1)
  check(case.name .. ": hits the randomly picked slot", calls[1].slot, 2)
  check(case.name .. ": deals the fixed amount", calls[1].amount, case.amount)
  check(case.name .. ": targets the opponent's side", calls[1].targetNonTurn, true)
  check(case.name .. ": sets the expected animation",
    memory:readSymbol8("wLoadedAttackAnimation"), case.anim)
end

-- FirstAid_DamageCheck: fails below 10 damage, passes at/above it.
do
  local effects = newEffects()
  local actor = {
    duelVars = { get = function(_, addr)
      if addr == C.DUELVARS_ARENA_CARD then return 0 end
      if addr == C.DUELVARS_ARENA_CARD_HP then return 90 end
    end },
    cardData = {
      getCardIDFromDeckIndex = function() return 1 end,
      get = function() return { hp = 100 } end,
    },
  }
  local carry = effects.handlers["FirstAid_DamageCheck"](effects, { combat = actor })
  check("first aid: 10 damage -> passes (carry false)", carry, false)
end
do
  local effects = newEffects()
  local actor = {
    duelVars = { get = function(_, addr)
      if addr == C.DUELVARS_ARENA_CARD then return 0 end
      if addr == C.DUELVARS_ARENA_CARD_HP then return 95 end
    end },
    cardData = {
      getCardIDFromDeckIndex = function() return 1 end,
      get = function() return { hp = 100 } end,
    },
  }
  local carry = effects.handlers["FirstAid_DamageCheck"](effects, { combat = actor })
  check("first aid: 5 damage -> fails (carry true)", carry, true)
end

if failures == 0 then
  print("all standalone effects batch 4 cases passed")
  os.exit(0)
else
  print(("%d standalone effects batch 4 case(s) failed"):format(failures))
  os.exit(1)
end
