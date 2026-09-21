-- Behavioral smoke test for the Selfdestruct attack family (Weezing/Golem/
-- Magnemite/Magneton Lv28/Magneton Lv35), run under real LuaJIT. Closes 5
-- of the ~66 genuinely-missing card effects found by cross-checking every
-- self:register() call EffectCommands.lua actually makes at runtime
-- (introspecting self.handlers after construction, since several existing
-- families -- e.g. "Call for Family" -- build their registered names by
-- string concatenation in a loop, invisible to a plain source-text search)
-- against every function name engine/duel/effect_commands.asm's 317 lists
-- reference (parsed with the project's own tools/tcg/build_manifest.py).
--
-- Source shape (identical across all five, only the two damage amounts
-- differ): DealRecoilDamageToSelf(recoil), then DealDamageToAllBenchedPokemon
-- for the ATTACKER's own bench (wIsDamageToSelf=TRUE, no SwapTurn), then the
-- SAME amount for the DEFENDER's bench (SwapTurn-bracketed in the source,
-- which Combat:dealDamageToAllBenchedPokemon's targetNonTurn=true already
-- models). Reuses the exact same Combat:dealRecoilDamageToSelf/
-- dealDamageToAllBenchedPokemon primitives Blizzard/StretchKick/Spark/
-- GengarDarkMind/HypnoDarkMind already use elsewhere in this file.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

-- Constants: an explicit few the test itself inspects, self-describing
-- fallback for everything _installSharedHandlers references but this test
-- doesn't care about the value of (eager table-literal keys elsewhere in
-- the file, e.g. card IDs used by unrelated families).
local C = setmetatable({ HEADS = "HEADS", TAILS = "TAILS" },
  { __index = function(_, k) return k end })

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(("FAIL  %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
  else
    print(("ok    %s"):format(label))
  end
end

local function newEffects()
  local memory = setmetatable({}, { __index = function() return function() return 0 end end })
  local permissive = setmetatable({}, { __index = function() return function() return 0 end end })
  return EffectCommands.new(memory, permissive, permissive, C,
    { schema = 1, byAddress = {}, byLabel = {} }, {})
end

local function newCombat()
  local calls = {}
  local combat = {
    dealRecoilDamageToSelf = function(_, amount)
      calls[#calls + 1] = { fn = "recoil", amount = amount }
      return 0
    end,
    dealDamageToAllBenchedPokemon = function(_, amount, targetNonTurn, options)
      calls[#calls + 1] = {
        fn = "bench", amount = amount, targetNonTurn = targetNonTurn,
        isDamageToSelf = options.isDamageToSelf,
      }
      return true
    end,
  }
  return combat, calls
end

local cases = {
  { "WeezingSelfdestructEffect", 60, 10 },
  { "GolemSelfdestructEffect", 100, 20 },
  { "MagnemiteSelfdestructEffect", 40, 10 },
  { "MagnetonLv28SelfdestructEffect", 80, 20 },
  { "MagnetonLv35SelfdestructEffect", 100, 20 },
}

for _, case in ipairs(cases) do
  local name, recoil, bench = case[1], case[2], case[3]
  local effects = newEffects()
  local combat, calls = newCombat()
  local carry, err = effects.handlers[name](effects, { combat = combat })
  check(name .. ": carry false (success)", carry, false)
  check(name .. ": exactly 3 calls", #calls, 3)
  check(name .. ": recoil first", calls[1].fn, "recoil")
  check(name .. ": recoil amount", calls[1].amount, recoil)
  check(name .. ": own bench second, no swap", calls[2].fn, "bench")
  check(name .. ": own bench amount", calls[2].amount, bench)
  check(name .. ": own bench targetNonTurn=false", calls[2].targetNonTurn, false)
  check(name .. ": own bench isDamageToSelf=true", calls[2].isDamageToSelf, true)
  check(name .. ": opponent bench third, swaps", calls[3].fn, "bench")
  check(name .. ": opponent bench amount", calls[3].amount, bench)
  check(name .. ": opponent bench targetNonTurn=true", calls[3].targetNonTurn, true)
  check(name .. ": opponent bench isDamageToSelf=false", calls[3].isDamageToSelf, false)
end

-- Missing combat context fails closed rather than erroring.
do
  local effects = newEffects()
  local carry, err = effects.handlers["GolemSelfdestructEffect"](effects, {})
  check("missing combat context: carry nil", carry, nil)
  check("missing combat context: reason", err, "effect_context_missing_combat")
end

if failures == 0 then
  print("all Selfdestruct effect cases passed")
  os.exit(0)
else
  print(("%d Selfdestruct effect case(s) failed"):format(failures))
  os.exit(1)
end
