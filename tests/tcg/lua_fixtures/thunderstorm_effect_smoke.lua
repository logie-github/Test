-- Behavioral smoke test for Zapdos' Thunderstorm, run under real LuaJIT.
-- The last of the card-effects backlog.
--
-- Coin-flips every one of the opponent's Benched Pokemon (Arena
-- excluded), takes 10 recoil damage per tails, then deals 20 damage to
-- every Benched Pokemon that came up heads.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = setmetatable({
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = "DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA",
  HEADS = "HEADS", TAILS = "TAILS",
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
  local memory = {}
  local coinIndex = 0
  local setup = { tossCoin = function()
    coinIndex = coinIndex + 1
    return (opts.coinQueue or {})[coinIndex]
  end }
  local effects = EffectCommands.new(memory, setup, {}, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  local swaps = 0
  local recoilCalls, damageCalls = {}, {}
  local combat = {
    duelVars = {
      swapTurn = function() swaps = swaps + 1 end,
      get = function(_, addr)
        if addr == C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA then return opts.count end
      end,
    },
    dealRecoilDamageToSelf = function(_, amount) recoilCalls[#recoilCalls + 1] = amount end,
    dealDamageToPlayAreaPokemon = function(_, slot, amount, targetNonTurn)
      damageCalls[#damageCalls + 1] = { slot = slot, amount = amount, targetNonTurn = targetNonTurn }
      return 1
    end,
  }
  return effects, combat, function() return swaps end, recoilCalls, damageCalls
end

-- 3 Benched Pokemon: heads, tails, heads. One recoil hit, two damage hits.
do
  local effects, combat, swaps, recoilCalls, damageCalls = newEffects({
    count = 4, coinQueue = { C.HEADS, C.TAILS, C.HEADS },
  })
  local carry = effects.handlers["ThunderstormEffect"](effects, { combat = combat })
  check("mixed: carry false", carry, false)
  check("mixed: swaps four times (three brackets)", swaps(), 4)
  check("mixed: exactly one recoil call", #recoilCalls, 1)
  check("mixed: recoil is 10 per tails", recoilCalls[1], 10)
  check("mixed: exactly two damage calls", #damageCalls, 2)
  check("mixed: first heads slot damaged", damageCalls[1].slot, 1)
  check("mixed: second heads slot damaged", damageCalls[2].slot, 3)
  check("mixed: each hit deals 20", damageCalls[1].amount, 20)
  check("mixed: never asks the primitive to swap itself", damageCalls[1].targetNonTurn, false)
end

-- No Bench at all: nothing tossed, no recoil, no damage, but the four
-- unconditional swaps still happen.
do
  local effects, combat, swaps, recoilCalls, damageCalls = newEffects({ count = 1, coinQueue = {} })
  local carry = effects.handlers["ThunderstormEffect"](effects, { combat = combat })
  check("no bench: carry false", carry, false)
  check("no bench: swaps four times", swaps(), 4)
  check("no bench: no recoil", #recoilCalls, 0)
  check("no bench: no damage", #damageCalls, 0)
end

-- All tails: recoil scales with the tails count, no damage calls at all.
do
  local effects, combat, _, recoilCalls, damageCalls = newEffects({
    count = 3, coinQueue = { C.TAILS, C.TAILS },
  })
  local carry = effects.handlers["ThunderstormEffect"](effects, { combat = combat })
  check("all tails: carry false", carry, false)
  check("all tails: recoil is 2 tails * 10", recoilCalls[1], 20)
  check("all tails: no damage calls", #damageCalls, 0)
end

-- All heads: no recoil call at all, every Bench slot damaged.
do
  local effects, combat, _, recoilCalls, damageCalls = newEffects({
    count = 3, coinQueue = { C.HEADS, C.HEADS },
  })
  local carry = effects.handlers["ThunderstormEffect"](effects, { combat = combat })
  check("all heads: carry false", carry, false)
  check("all heads: no recoil call", #recoilCalls, 0)
  check("all heads: both slots damaged", #damageCalls, 2)
end

if failures == 0 then
  print("all thunderstorm effect cases passed")
  os.exit(0)
else
  print(("%d thunderstorm effect case(s) failed"):format(failures))
  os.exit(1)
end
