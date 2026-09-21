-- Behavioral smoke test for Pidgeot's Gale, run under real LuaJIT. Closes
-- 2 more of the card-effects backlog.
--
-- Gale_LoadAnimation: sets the Gale animation, unconditional.
-- Gale_SwitchEffect: unless the attack was unaffected (Status:checkNoDamage
-- OrEffect), switches the Defending Pokemon to a random Bench slot --
-- triggering Destiny Bond first if the Defending Pokemon's HP is already 0,
-- and clearing wDealtDamage if the switch actually happened -- then always
-- switches the Attacking Pokemon to a random Bench slot too, whether or not
-- the Defending-side switch ran.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = setmetatable({
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = "DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA",
  DUELVARS_ARENA_CARD_HP = "DUELVARS_ARENA_CARD_HP",
  ATK_ANIM_GALE = "ATK_ANIM_GALE",
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

local function newEffects(opts)
  opts = opts or {}
  local turn = "attacker"
  local swapCalls = {}
  local swapArenaCalls = {}
  local destinyBondCalls = 0
  local words = { defenderHP = opts.defenderHP or 0 }
  local memory = { words = {},
    readSymbol8 = function(self, n) return self.words[n] or 0 end,
    writeSymbol8 = function(self, n, v) self.words[n] = v end,
    address = function() return 1000, 0 end,
    read8 = function(_, area, addr) return words[addr] or 0 end,
    write8 = function(_, area, addr, value) words[addr] = value end,
  }
  words[1000] = 0x22 -- pre-existing wDealtDamage, non-zero so a clear is observable
  words[1001] = 0x11
  local status = {
    checkNoDamageOrEffect = function() return opts.prevented == true end,
    handleDestinyBondSubstatus = function() destinyBondCalls = destinyBondCalls + 1 end,
  }
  local setup = { rng = { random = function(_, maxExclusive)
    swapCalls[#swapCalls + 1] = { kind = "random", turn = turn, maxExclusive = maxExclusive }
    return (opts.randomResult or {})[turn] or 0
  end } }
  local effects = EffectCommands.new(memory, setup, status, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  local combat = {
    status = status,
    duelVars = {
      swapTurn = function()
        swapCalls[#swapCalls + 1] = { kind = "swap" }
        turn = (turn == "attacker") and "defender" or "attacker"
      end,
      getNonTurn = function(_, addr)
        check("reads defender HP", addr, C.DUELVARS_ARENA_CARD_HP)
        return opts.defenderHP or 0
      end,
      get = function(_, addr)
        if addr == C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA then
          return (opts.countsBySide or {})[turn] or 1
        end
      end,
    },
    duelOps = {
      swapArenaWithBenchPokemon = function(_, slot)
        swapArenaCalls[#swapArenaCalls + 1] = { turn = turn, slot = slot }
      end,
    },
  }
  local function readDealtDamage() return (words[1000] or 0) + 0x100 * (words[1001] or 0) end
  return effects, memory, combat, swapArenaCalls, function() return destinyBondCalls end, readDealtDamage
end

-- Gale_LoadAnimation: unconditional.
do
  local effects, memory = newEffects()
  local carry = effects.handlers["Gale_LoadAnimation"](effects)
  check("load animation: carry false", carry, false)
  check("load animation: sets ATK_ANIM_GALE", memory:readSymbol8("wLoadedAttackAnimation"), C.ATK_ANIM_GALE)
end

-- Unaffected: skip the defender switch and Destiny Bond entirely, but
-- still switch the attacker's own Pokemon.
do
  local effects, _, combat, swapArenaCalls, destinyBondCalls, readDealtDamage = newEffects({
    prevented = true, countsBySide = { attacker = 3 }, randomResult = { attacker = 1 },
  })
  local carry = effects.handlers["Gale_SwitchEffect"](effects, { combat = combat })
  check("unaffected: carry false", carry, false)
  check("unaffected: no Destiny Bond call", destinyBondCalls(), 0)
  check("unaffected: exactly one switch (attacker's own)", #swapArenaCalls, 1)
  check("unaffected: switches on the attacker's turn", swapArenaCalls[1].turn, "attacker")
  check("unaffected: picks bench slot 1+random", swapArenaCalls[1].slot, 2)
  check("unaffected: wDealtDamage left untouched", readDealtDamage(), 0x1122)
end

-- Affected, defender HP > 0: no Destiny Bond, but both sides switch and
-- wDealtDamage is cleared.
do
  local effects, _, combat, swapArenaCalls, destinyBondCalls, readDealtDamage = newEffects({
    prevented = false, defenderHP = 40,
    countsBySide = { attacker = 2, defender = 3 },
    randomResult = { attacker = 0, defender = 1 },
  })
  local carry = effects.handlers["Gale_SwitchEffect"](effects, { combat = combat })
  check("affected, hp>0: carry false", carry, false)
  check("affected, hp>0: no Destiny Bond call", destinyBondCalls(), 0)
  check("affected, hp>0: two switches (defender then attacker)", #swapArenaCalls, 2)
  check("affected, hp>0: defender switched first", swapArenaCalls[1].turn, "defender")
  check("affected, hp>0: defender bench slot 1+random", swapArenaCalls[1].slot, 2)
  check("affected, hp>0: attacker switched second", swapArenaCalls[2].turn, "attacker")
  check("affected, hp>0: attacker bench slot 1+random", swapArenaCalls[2].slot, 1)
  check("affected, hp>0: wDealtDamage cleared", readDealtDamage(), 0)
end

-- Affected, defender HP == 0: Destiny Bond fires once before the switch.
do
  local effects, _, combat, swapArenaCalls, destinyBondCalls = newEffects({
    prevented = false, defenderHP = 0,
    countsBySide = { attacker = 2, defender = 2 },
    randomResult = { attacker = 0, defender = 0 },
  })
  local carry = effects.handlers["Gale_SwitchEffect"](effects, { combat = combat })
  check("affected, hp=0: carry false", carry, false)
  check("affected, hp=0: Destiny Bond fires exactly once", destinyBondCalls(), 1)
  check("affected, hp=0: two switches still happen", #swapArenaCalls, 2)
end

-- Affected, defender has no Bench: skip clearing wDealtDamage, still
-- switch the attacker afterward.
do
  local effects, _, combat, swapArenaCalls, _, readDealtDamage = newEffects({
    prevented = false, defenderHP = 40,
    countsBySide = { attacker = 3, defender = 1 },
    randomResult = { attacker = 1 },
  })
  local carry = effects.handlers["Gale_SwitchEffect"](effects, { combat = combat })
  check("defender no bench: carry false", carry, false)
  check("defender no bench: only the attacker's own switch happens", #swapArenaCalls, 1)
  check("defender no bench: attacker's switch is the one recorded", swapArenaCalls[1].turn, "attacker")
  check("defender no bench: wDealtDamage left untouched", readDealtDamage(), 0x1122)
end

if failures == 0 then
  print("all gale effect cases passed")
  os.exit(0)
else
  print(("%d gale effect case(s) failed"):format(failures))
  os.exit(1)
end
