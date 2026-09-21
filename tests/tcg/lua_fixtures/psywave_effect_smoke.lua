-- Behavioral smoke test for Mew/Voltorb's Psywave, run under real LuaJIT.
-- Closes 1 more of the card-effects backlog.
--
-- GetEnergyAttachedMultiplierDamage: swaps to the Defending Pokemon,
-- counts the Energy CARDS attached to its Arena card (reusing the already-
-- translated DuelOps:countNumberOfEnergyCardsAttached, which folds Double
-- Colorless Energy's doubled point count back down to 1 card), swaps back,
-- and writes 10x that count directly into wDamage -- unlike SetDefiniteDamage,
-- it does not touch the AI damage hint fields (the real command list has no
-- separate AI_EFFECT entry for this attack).

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = setmetatable({ PLAY_AREA_ARENA = 0 }, { __index = function(_, k) return k end })

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(("FAIL  %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
  else
    print(("ok    %s"):format(label))
  end
end

local function newEffects(attachedCount)
  local words = {}
  local memory = {
    address = function(_, symbol)
      check("writes to wDamage", symbol, "wDamage")
      return 1000, 0
    end,
    read8 = function(_, area, addr) return words[addr] or 0 end,
    write8 = function(_, area, addr, value) words[addr] = value end,
  }
  local swapCount = 0
  local actor = {
    duelVars = { swapTurn = function() swapCount = swapCount + 1 end },
    duelOps = { countNumberOfEnergyCardsAttached = function(_, slot)
      check("counts the arena slot", slot, C.PLAY_AREA_ARENA)
      return attachedCount
    end },
  }
  local effects = EffectCommands.new(memory, {}, {}, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  local function readDamage() return (words[1000] or 0) + 0x100 * (words[1001] or 0) end
  return effects, actor, readDamage, function() return swapCount end
end

for _, attachedCount in ipairs({0, 1, 3, 25}) do
  local effects, actor, readDamage, swaps = newEffects(attachedCount)
  local carry = effects.handlers["PsywaveEffect"](effects, { combat = actor })
  check(("psywave %d energy: carry false"):format(attachedCount), carry, false)
  check(("psywave %d energy: damage is 10x count"):format(attachedCount), readDamage(), attachedCount * 10)
  check(("psywave %d energy: swaps turn twice (bracket)"):format(attachedCount), swaps(), 2)
end

if failures == 0 then
  print("all psywave effect cases passed")
  os.exit(0)
else
  print(("%d psywave effect case(s) failed"):format(failures))
  os.exit(1)
end
