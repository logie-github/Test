-- Behavioral smoke test for the Supersonic confusion family (Zubat/
-- Nidorina/Lickitung/Shellder/Tentacruel), run under real LuaJIT. The last
-- three names had never been exercised under real execution before (only
-- Zubat/Nidorina had registrations at all); this proves all five share the
-- one `supersonic` handler and it behaves correctly on both coin outcomes.
--
-- Source shape (identical for all five): call Confusion50PercentEffect;
-- call nc, SetNoEffectFromStatus -- i.e. coin heads confuses the Defending
-- Pokemon, coin tails marks "no effect" instead of silently doing nothing.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = setmetatable({ HEADS = "HEADS", TAILS = "TAILS",
  PSN_DBLPSN = "PSN_DBLPSN", CONFUSED = "CONFUSED",
  EFFECT_FAILED_NO_EFFECT = "EFFECT_FAILED_NO_EFFECT" },
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

local function newEffects(coinResult)
  local memory = { words = {},
    readSymbol8 = function(self, n) return self.words[n] or 0 end,
    writeSymbol8 = function(self, n, v) self.words[n] = v end,
  }
  local queueCalls, setup = {}, { tossCoin = function() return coinResult end }
  local status = {
    queueStatusCondition = function(_, mask, condition)
      queueCalls[#queueCalls + 1] = { mask = mask, condition = condition }
      return true
    end,
  }
  local effects = EffectCommands.new(memory, setup, status, C,
    { schema = 1, byAddress = {}, byLabel = {} }, {})
  return effects, memory, queueCalls
end

for _, name in ipairs({
  "ZubatSupersonicEffect", "NidorinaSupersonicEffect", "LickitungSupersonicEffect",
  "ShellderSupersonicEffect", "TentacruelSupersonicEffect",
}) do
  do
    local effects, memory, queueCalls = newEffects(C.HEADS)
    local carry = effects.handlers[name](effects)
    check(name .. " heads: confuses (carry true)", carry, true)
    check(name .. " heads: queues CONFUSED", queueCalls[1] and queueCalls[1].condition, C.CONFUSED)
  end
  do
    local effects, memory, queueCalls = newEffects(C.TAILS)
    local carry = effects.handlers[name](effects)
    check(name .. " tails: no confusion (carry false)", carry, false)
    check(name .. " tails: no status queued", #queueCalls, 0)
    check(name .. " tails: marks EFFECT_FAILED_NO_EFFECT",
      memory.words.wEffectFailed, C.EFFECT_FAILED_NO_EFFECT)
  end
end

if failures == 0 then
  print("all Supersonic effect cases passed")
  os.exit(0)
else
  print(("%d Supersonic effect case(s) failed"):format(failures))
  os.exit(1)
end
