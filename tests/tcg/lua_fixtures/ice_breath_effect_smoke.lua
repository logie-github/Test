-- Behavioral smoke test for Articuno's Ice Breath, run under real LuaJIT.
-- Closes 2 more of the card-effects backlog.
--
-- IceBreath_ZeroDamage: 0 printed damage from the normal attack pipeline.
-- IceBreath_RandomPokemonDamageEffect: 40 damage to a random opponent
-- Play Area Pokemon -- reuses the exact same damageRandomOpponentPlayArea
-- Pokemon helper as CatPunch/SlicingWind.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = setmetatable({
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = "DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA",
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
  local wordBytes = {}
  local memory = { words = {},
    readSymbol8 = function(self, n) return self.words[n] or 0 end,
    writeSymbol8 = function(self, n, v) self.words[n] = v end,
    address = function() return 1000, 0 end,
    read8 = function(_, area, addr) return wordBytes[addr] or 0 end,
    write8 = function(_, area, addr, value) wordBytes[addr] = value end,
  }
  local setup = { rng = { random = function(_, maxExclusive) return randomResult end } }
  local effects = EffectCommands.new(memory, setup, {}, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  local function readDamage() return (wordBytes[1000] or 0) + 0x100 * (wordBytes[1001] or 0) end
  return effects, memory, readDamage
end

-- IceBreath_ZeroDamage
do
  local effects, memory, readDamage = newEffects()
  local carry = effects.handlers["IceBreath_ZeroDamage"](effects)
  check("zero damage: carry false", carry, false)
  check("zero damage: wDamage is 0", readDamage(), 0)
end

-- IceBreath_RandomPokemonDamageEffect: random opponent slot, fixed 40, bench-hit anim.
do
  local effects, memory = newEffects(1)
  local calls = {}
  local combat = {
    duelVars = { getNonTurn = function(_, addr)
      check("reads opponent's play area count", addr, C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
      return 2
    end },
    dealDamageToPlayAreaPokemon = function(_, slot, amount, targetNonTurn)
      calls[#calls + 1] = { slot = slot, amount = amount, targetNonTurn = targetNonTurn }
      return 1
    end,
  }
  local carry = effects.handlers["IceBreath_RandomPokemonDamageEffect"](effects, { combat = combat })
  check("random damage: carry false", carry, false)
  check("random damage: exactly one damage call", #calls, 1)
  check("random damage: hits the randomly picked slot", calls[1].slot, 1)
  check("random damage: deals 40", calls[1].amount, 40)
  check("random damage: targets the opponent's side", calls[1].targetNonTurn, true)
  check("random damage: sets the bench-hit animation",
    memory:readSymbol8("wLoadedAttackAnimation"), C.ATK_ANIM_BENCH_HIT)
end

if failures == 0 then
  print("all ice breath effect cases passed")
  os.exit(0)
else
  print(("%d ice breath effect case(s) failed"):format(failures))
  os.exit(1)
end
