-- Behavioral smoke test for five small standalone card effects, run under
-- real LuaJIT. Closes 5 more of the card-effects backlog.
--
-- TransparencyEffect / PrehistoricPowerEffect: pure INITIAL_EFFECT_1 stubs
-- (`scf; ret` in the source, always carry) -- the exact same "triggered-
-- only Power, blocks ordinary-attack usage" shape as the already-
-- translated Quickfreeze/Firegiver/HealingWind/PealOfThunder stubs,
-- confirmed by checking both real command lists use ONLY
-- EFFECTCMDTYPE_INITIAL_EFFECT_1.
-- EarthquakeEffect: 10 damage to every one of the attacker's own Benched
-- Pokemon only -- reuses the same Combat:dealDamageToAllBenchedPokemon
-- primitive the Selfdestruct family uses, just once and without recoil.
-- PayDayEffect: coin heads only, then the same draw-1-card shape as Fetch.
-- DreamEaterEffect: usable only while the Defending Pokemon is Asleep.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")
local bit = require("bit")

local C = setmetatable({
  HEADS = "HEADS", TAILS = "TAILS",
  CNF_SLP_PRZ = 0x03, ASLEEP = 0x02, PARALYZED = 0x01,
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
  local memory = setmetatable({}, { __index = function() return function() return 0 end end })
  local setup = { tossCoin = function() return opts.coin end }
  local status = {}
  local effects = EffectCommands.new(memory, setup, status, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  local drawIndex = 0
  local hand = {}
  local benchCalls = {}
  local actor = {
    duelVars = {
      get = function() return 0 end,
      getNonTurn = function() return opts.nonTurnStatus or 0 end,
      swapTurn = function() end,
    },
    duelOps = {
      drawCardFromDeck = function()
        drawIndex = drawIndex + 1
        local entry = (opts.drawQueue or {})[drawIndex]
        if not entry then return nil, true end
        return entry, false
      end,
      addCardToHand = function(_, deckIndex) hand[#hand + 1] = deckIndex end,
    },
    dealDamageToAllBenchedPokemon = function(_, amount, targetNonTurn, o)
      benchCalls[#benchCalls + 1] = { amount = amount, targetNonTurn = targetNonTurn, isDamageToSelf = o.isDamageToSelf }
      return true
    end,
  }
  return effects, actor, hand, benchCalls
end

-- TransparencyEffect / PrehistoricPowerEffect: always carry.
do
  local effects = newEffects()
  check("TransparencyEffect: always carry true", effects.handlers["TransparencyEffect"](effects), true)
  check("PrehistoricPowerEffect: always carry true", effects.handlers["PrehistoricPowerEffect"](effects), true)
end

-- EarthquakeEffect: own bench only, no recoil call.
do
  local effects, actor, _, benchCalls = newEffects()
  local carry = effects.handlers["EarthquakeEffect"](effects, { combat = actor })
  check("earthquake: carry false", carry, false)
  check("earthquake: exactly one bench-damage call", #benchCalls, 1)
  check("earthquake: amount 10", benchCalls[1].amount, 10)
  check("earthquake: own bench only (targetNonTurn=false)", benchCalls[1].targetNonTurn, false)
  check("earthquake: isDamageToSelf=true", benchCalls[1].isDamageToSelf, true)
end

-- PayDayEffect
do
  local effects, actor, hand = newEffects({ coin = C.HEADS, drawQueue = { 7 } })
  local carry = effects.handlers["PayDayEffect"](effects, { combat = actor })
  check("pay day heads: carry false", carry, false)
  check("pay day heads: card drawn", hand[1], 7)
end
do
  local effects, actor, hand = newEffects({ coin = C.TAILS, drawQueue = { 7 } })
  local carry = effects.handlers["PayDayEffect"](effects, { combat = actor })
  check("pay day tails: carry false", carry, false)
  check("pay day tails: no card drawn", #hand, 0)
end
do
  local effects, actor, hand = newEffects({ coin = C.HEADS, drawQueue = {} })
  effects.handlers["PayDayEffect"](effects, { combat = actor })
  check("pay day heads, empty deck: no card drawn", #hand, 0)
end

-- DreamEaterEffect
do
  local effects, actor = newEffects({ nonTurnStatus = C.ASLEEP })
  local carry = effects.handlers["DreamEaterEffect"](effects, { combat = actor })
  check("dream eater: defender asleep -> ok (carry false)", carry, false)
end
do
  local effects, actor = newEffects({ nonTurnStatus = C.PARALYZED })
  local carry = effects.handlers["DreamEaterEffect"](effects, { combat = actor })
  check("dream eater: defender paralyzed, not asleep -> fail (carry true)", carry, true)
end
do
  local effects, actor = newEffects({ nonTurnStatus = 0 })
  local carry = effects.handlers["DreamEaterEffect"](effects, { combat = actor })
  check("dream eater: defender has no status -> fail (carry true)", carry, true)
end

if failures == 0 then
  print("all standalone effects batch 1 cases passed")
  os.exit(0)
else
  print(("%d standalone effects batch 1 case(s) failed"):format(failures))
  os.exit(1)
end
