-- Behavioral smoke test for Mysterious Fossil / Clefairy Doll's synthetic
-- "Discard" Power (engine/duel/core.asm's TrainerToPkmnData patch +
-- effect_commands.asm's TrainerCardAsPokemonEffectCommands), run under real
-- LuaJIT. These two Trainer-as-Pokemon cards get patched card data (10 HP,
-- UNABLE_RETREAT, one fake Power) so they can voluntarily leave play since
-- they can't retreat normally; this is the last piece that Power needs.
--
-- Same shape as the already-translated Cowardice Power, confirmed against
-- both bodies directly: gate on Play Area count (>=2, no
-- CAN_EVOLVE_THIS_TURN check unlike Cowardice), choose a Bench replacement
-- only when the card is the Active (no selection prompt at all when
-- Benched -- `ret nz` on the source's own hTemp_ffa0 check), then discard
-- straight to the discard pile (not back to hand, unlike Cowardice).

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = setmetatable({
  PLAY_AREA_ARENA = 0, PLAY_AREA_BENCH_1 = 1,
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = 0x50,
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
  local words = {}
  local memory = {
    readSymbol8 = function(_, name) return words[name] or 0 end,
    writeSymbol8 = function(_, name, v) words[name] = v end,
  }
  local calls = {}
  local actor = {
    duelVars = {
      get = function(_, a) return a == C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA
        and (opts.playAreaCount or 0) or 0 end,
      getNonTurn = function() return 0 end, swapTurn = function() end,
    },
    duelOps = {
      movePlayAreaCardToDiscardPile = function(_, slot)
        calls[#calls + 1] = { fn = "discard", slot = slot }
      end,
      swapArenaWithBenchPokemon = function(_, slot)
        calls[#calls + 1] = { fn = "swap", slot = slot }
      end,
      shiftAllPokemonToFirstPlayAreaSlots = function()
        calls[#calls + 1] = { fn = "shift" }
      end,
    },
  }
  local effects = EffectCommands.new(memory, {}, {}, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  return effects, actor, memory, calls
end

-- BenchCheck: fails below 2 Play Area Pokemon, relays the slot into hTemp_ffa0.
do
  local effects, actor, memory = newHarness({ playAreaCount = 1 })
  local carry = effects.handlers["TrainerCardAsPokemon_BenchCheck"](effects,
    { combat = actor, powerSlot = C.PLAY_AREA_ARENA })
  check("only 1 in play area -> fail (carry true)", carry, true)
  check("relays slot into hTemp_ffa0", memory:readSymbol8("hTemp_ffa0"), C.PLAY_AREA_ARENA)
end
do
  local effects, actor = newHarness({ playAreaCount = 2 })
  local carry = effects.handlers["TrainerCardAsPokemon_BenchCheck"](effects,
    { combat = actor, powerSlot = C.PLAY_AREA_BENCH_1 })
  check("2 in play area -> ok (carry false)", carry, false)
end

-- PlayerSelectSwitch: no prompt at all when Benched; requires a valid
-- replacement when Active.
do
  local effects, actor = newHarness({ playAreaCount = 3 })
  local carry = effects.handlers["TrainerCardAsPokemon_PlayerSelectSwitch"](effects,
    { combat = actor, powerSlot = C.PLAY_AREA_BENCH_1 })
  check("benched card: no selection needed -> carry false", carry, false)
end
do
  local effects, actor, memory = newHarness({ playAreaCount = 3 })
  local context = { combat = actor, powerSlot = C.PLAY_AREA_ARENA, selection = { replacement = 1 } }
  local carry = effects.handlers["TrainerCardAsPokemon_PlayerSelectSwitch"](effects, context)
  check("active card: valid replacement -> carry false", carry, false)
  check("relays chosen replacement", memory:readSymbol8("hTempPlayAreaLocation_ffa1"), 1)
end
do
  local effects, actor = newHarness({ playAreaCount = 2 })
  local context = { combat = actor, powerSlot = C.PLAY_AREA_ARENA, selection = { replacement = 5 } }
  local carry, err = effects.handlers["TrainerCardAsPokemon_PlayerSelectSwitch"](effects, context)
  check("active card: out-of-range replacement -> rejected", carry, nil)
  check("rejection reason", err, "invalid_selection:replacement")
end

-- DiscardEffect: discards the fake Pokemon; swaps in a replacement only
-- when it was Active; always shifts afterward.
do
  local effects, actor, memory, calls = newHarness({ playAreaCount = 3 })
  memory:writeSymbol8("hTemp_ffa0", C.PLAY_AREA_BENCH_1)
  local carry = effects.handlers["TrainerCardAsPokemon_DiscardEffect"](effects, { combat = actor })
  check("benched discard: carry false", carry, false)
  check("benched discard: discards the benched slot (fn)", calls[1].fn, "discard")
  check("benched discard: discards the benched slot (slot)", calls[1].slot, C.PLAY_AREA_BENCH_1)
  check("benched discard: no swap needed", calls[2].fn, "shift")
  check("benched discard: exactly 2 calls (no swap)", #calls, 2)
end
do
  local effects, actor, memory, calls = newHarness({ playAreaCount = 3 })
  memory:writeSymbol8("hTemp_ffa0", C.PLAY_AREA_ARENA)
  memory:writeSymbol8("hTempPlayAreaLocation_ffa1", 2)
  local carry = effects.handlers["TrainerCardAsPokemon_DiscardEffect"](effects, { combat = actor })
  check("active discard: carry false", carry, false)
  check("active discard: discards the Arena slot (fn)", calls[1].fn, "discard")
  check("active discard: discards the Arena slot (slot)", calls[1].slot, C.PLAY_AREA_ARENA)
  check("active discard: swaps in the chosen replacement (fn)", calls[2].fn, "swap")
  check("active discard: swaps in the chosen replacement (slot)", calls[2].slot, 2)
  check("active discard: then shifts", calls[3].fn, "shift")
  check("active discard: exactly 3 calls", #calls, 3)
end

if failures == 0 then
  print("all Trainer-card-as-Pokemon Discard Power cases passed")
  os.exit(0)
else
  print(("%d Trainer-card-as-Pokemon Discard Power case(s) failed"):format(failures))
  os.exit(1)
end
