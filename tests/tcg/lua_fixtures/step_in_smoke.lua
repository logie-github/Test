-- Behavioral smoke test for Slowbro's Step In Power, run under real
-- LuaJIT. Closes 2 more of the card-effects backlog.
--
-- Unlike Cowardice/Heal/Shift (already-translated manual Powers, usable
-- from anywhere in the Play Area), Step In can ONLY be used from the
-- Bench -- the source's own gate fails immediately if the card is
-- currently the Active Pokemon. After swapping into Active, the
-- used-this-turn flag is set unconditionally on PLAY_AREA_ARENA (no +slot
-- offset in the source), since by then this card IS the Arena occupant.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")
local bit = require("bit")

local C = setmetatable({
  PLAY_AREA_ARENA = 0, PLAY_AREA_BENCH_1 = 1, PLAY_AREA_BENCH_2 = 2,
  DUELVARS_ARENA_CARD_FLAGS = 0x60,
  USED_PKMN_POWER_THIS_TURN_F = 3,
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

local function newHarness(opts)
  local flags = opts.flagsBySlot or {}
  local memory = { words = {},
    readSymbol8 = function(self, n) return self.words[n] or 0 end,
    writeSymbol8 = function(self, n, v) self.words[n] = v end,
  }
  local swapCalls = {}
  local actor = {
    duelVars = {
      get = function(_, a) return flags[a - C.DUELVARS_ARENA_CARD_FLAGS] or 0 end,
      set = function(_, a, v) flags[a - C.DUELVARS_ARENA_CARD_FLAGS] = v end,
      getNonTurn = function() return 0 end, swapTurn = function() end,
    },
    duelOps = {
      swapArenaWithBenchPokemon = function(_, slot) swapCalls[#swapCalls + 1] = slot end,
    },
  }
  local effects = EffectCommands.new(memory, {}, { checkIsIncapableOfUsingPkmnPower = function()
    return opts.incapable == true
  end }, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  return effects, actor, memory, swapCalls
end

-- BenchCheck: fails outright when the card is already Active.
do
  local effects, actor, memory = newHarness({})
  local carry = effects.handlers["StepIn_BenchCheck"](effects, { combat = actor, powerSlot = C.PLAY_AREA_ARENA })
  check("already Active -> fail (carry true)", carry, true)
  check("still relays the slot", memory:readSymbol8("hTemp_ffa0"), C.PLAY_AREA_ARENA)
end

-- BenchCheck: benched, not yet used this turn, not incapacitated -> ok.
do
  local effects, actor = newHarness({ incapable = false })
  local carry = effects.handlers["StepIn_BenchCheck"](effects, { combat = actor, powerSlot = C.PLAY_AREA_BENCH_1 })
  check("benched, unused, capable -> ok (carry false)", carry, false)
end

-- BenchCheck: already used this turn -> fail.
do
  local usedMask = bit.lshift(1, C.USED_PKMN_POWER_THIS_TURN_F)
  local effects, actor = newHarness({ flagsBySlot = { [C.PLAY_AREA_BENCH_1] = usedMask } })
  local carry = effects.handlers["StepIn_BenchCheck"](effects, { combat = actor, powerSlot = C.PLAY_AREA_BENCH_1 })
  check("already used this turn -> fail (carry true)", carry, true)
end

-- BenchCheck: incapacitated (asleep/paralyzed/etc.) -> fail.
do
  local effects, actor = newHarness({ incapable = true })
  local carry = effects.handlers["StepIn_BenchCheck"](effects, { combat = actor, powerSlot = C.PLAY_AREA_BENCH_2 })
  check("incapacitated -> fail (carry true)", carry, true)
end

-- SwitchEffect: swaps the benched card into Active, marks PLAY_AREA_ARENA
-- (not the original Bench slot) as having used its Power this turn.
do
  local effects, actor, memory, swapCalls = newHarness({})
  memory:writeSymbol8("hTemp_ffa0", C.PLAY_AREA_BENCH_2)
  local carry = effects.handlers["StepIn_SwitchEffect"](effects, { combat = actor })
  check("switch: carry false", carry, false)
  check("switch: swaps with the relayed Bench slot", swapCalls[1], C.PLAY_AREA_BENCH_2)
  local newArenaFlags = actor.duelVars:get(C.DUELVARS_ARENA_CARD_FLAGS + C.PLAY_AREA_ARENA)
  check("switch: marks PLAY_AREA_ARENA used, not the old Bench slot",
    bit.band(newArenaFlags, bit.lshift(1, C.USED_PKMN_POWER_THIS_TURN_F)) ~= 0, true)
  local oldSlotFlags = actor.duelVars:get(C.DUELVARS_ARENA_CARD_FLAGS + C.PLAY_AREA_BENCH_2)
  check("switch: old Bench slot's flags untouched", oldSlotFlags, 0)
end

if failures == 0 then
  print("all Step In effect cases passed")
  os.exit(0)
else
  print(("%d Step In effect case(s) failed"):format(failures))
  os.exit(1)
end
