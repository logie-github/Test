-- Behavioral smoke test for Electrode's Chain Lightning, run under real
-- LuaJIT. Closes 1 more of the card-effects backlog.
--
-- Fixed 10 damage, then an extra 10 to every Play Area Pokemon -- both
-- sides, arena included -- that shares the Defending Pokemon's color
-- (skipped entirely if the Defending Pokemon is Colorless). Reuses the
-- already-registered Combat:dealDamageToPlayAreaPokemon and
-- Status:getPlayAreaCardColor.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = setmetatable({
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = "DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA",
  PLAY_AREA_ARENA = 0, COLORLESS = "COLORLESS",
  FIRE = "FIRE", WATER = "WATER", GRASS = "GRASS",
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

local function newEffects(colorsBySide, countsBySide)
  local turn = "attacker"
  local calls = {}
  local swaps = 0
  local words = {}
  local memory = {
    address = function() return 1000, 0 end,
    read8 = function(_, area, addr) return words[addr] or 0 end,
    write8 = function(_, area, addr, value) words[addr] = value end,
    readSymbol8 = function(_, n) return words[n] or 0 end,
    writeSymbol8 = function(_, n, v) words[n] = v end,
  }
  local status = { getPlayAreaCardColor = function(_, slot) return colorsBySide[turn][slot] end }
  local effects = EffectCommands.new(memory, {}, status, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  local combat = {
    duelVars = {
      swapTurn = function()
        swaps = swaps + 1
        turn = (turn == "attacker") and "defender" or "attacker"
      end,
      get = function(_, addr)
        if addr == C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA then return countsBySide[turn] end
      end,
    },
    dealDamageToPlayAreaPokemon = function(_, slot, amount, targetNonTurn, options)
      calls[#calls + 1] = { side = turn, slot = slot, amount = amount,
        targetNonTurn = targetNonTurn, isDamageToSelf = options and options.isDamageToSelf or false }
      return 1
    end,
  }
  local function readDamage() return (words[1000] or 0) + 0x100 * (words[1001] or 0) end
  return effects, combat, calls, readDamage, function() return swaps end
end

-- Colorless defender: fixed 10, no chain damage, no bench-scan swaps.
do
  local effects, combat, calls, readDamage, swapCount = newEffects(
    { defender = { [0] = C.COLORLESS }, attacker = {} },
    { defender = 1, attacker = 1 })
  local carry = effects.handlers["ChainLightningEffect"](effects, { combat = combat })
  check("colorless: carry false", carry, false)
  check("colorless: base damage set to 10", readDamage(), 10)
  check("colorless: no chain damage calls", #calls, 0)
  check("colorless: only the color-read swap bracket", swapCount(), 2)
end

-- Fire defender: chains through Fire Pokemon on both sides, arena included.
do
  local effects, combat, calls, readDamage, swapCount = newEffects(
    { defender = { [0] = C.FIRE, [1] = C.GRASS },
      attacker = { [0] = C.FIRE, [1] = C.WATER, [2] = C.FIRE } },
    { defender = 2, attacker = 3 })
  local carry = effects.handlers["ChainLightningEffect"](effects, { combat = combat })
  check("fire chain: carry false", carry, false)
  check("fire chain: base damage set to 10", readDamage(), 10)
  check("fire chain: exactly 3 chain-damage calls", #calls, 3)
  check("fire chain: hits defender's own fire arena", calls[1].side, "defender")
  check("fire chain: defender slot 0", calls[1].slot, 0)
  check("fire chain: opponent-side hit is not flagged self-damage", calls[1].isDamageToSelf, false)
  check("fire chain: hits attacker's fire arena", calls[2].side, "attacker")
  check("fire chain: attacker slot 0", calls[2].slot, 0)
  check("fire chain: own-side hit is flagged self-damage", calls[2].isDamageToSelf, true)
  check("fire chain: hits attacker's second fire slot", calls[3].slot, 2)
  check("fire chain: every hit deals 10", calls[1].amount, 10)
  check("fire chain: never asks the primitive to swap itself", calls[1].targetNonTurn, false)
  check("fire chain: ends back on the attacker's turn", swapCount() % 2, 0)
end

if failures == 0 then
  print("all chain lightning effect cases passed")
  os.exit(0)
else
  print(("%d chain lightning effect case(s) failed"):format(failures))
  os.exit(1)
end
