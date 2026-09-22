-- Behavioral smoke test for Zapdos' Big Thunder, run under real LuaJIT.
--
-- RandomlyDamagePlayAreaPokemon: an UpdateRNGSources coin-like pick of
-- own vs. opponent Play Area, then Random(count) for the slot within
-- that side. Own-side picks re-roll the WHOLE sample (side choice
-- included) if the slot lands on the attacker itself
-- (hTempPlayAreaLocation_ff9d); opponent-side picks never re-roll.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = setmetatable({
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = "DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA",
  ATK_ANIM_THUNDER_PLAY_AREA = "ATK_ANIM_THUNDER_PLAY_AREA",
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

-- updateSourcesQueue: sequence of raw bytes (bit 0 decides own(0)/opp(1)).
-- randomQueue: sequence of Random(count) results, consumed in call order.
local function newEffects(opts)
  opts = opts or {}
  local memory = { words = {},
    readSymbol8 = function(self, n) return self.words[n] or 0 end,
    writeSymbol8 = function(self, n, v) self.words[n] = v end,
  }
  memory.words["hTempPlayAreaLocation_ff9d"] = opts.attackerSlot or 0
  local updateSourcesIndex, randomIndex = 0, 0
  local setup = {
    exchangeRNG = function() return opts.exchangeFailed == true, opts.exchangeErr end,
    rng = {
      updateSources = function()
        updateSourcesIndex = updateSourcesIndex + 1
        return (opts.updateSourcesQueue or {})[updateSourcesIndex]
      end,
      random = function(_, maxExclusive)
        randomIndex = randomIndex + 1
        check("random: max exclusive matches the current side's count",
          maxExclusive, (opts.countsBySide or {})[opts.turnSequence and opts.turnSequence[randomIndex] or "attacker"])
        return (opts.randomQueue or {})[randomIndex]
      end,
    },
  }
  local effects = EffectCommands.new(memory, setup, {}, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  local turn = "attacker"
  local swaps = 0
  local calls = {}
  local combat = {
    duelVars = {
      swapTurn = function() swaps = swaps + 1; turn = (turn == "attacker") and "defender" or "attacker" end,
      get = function(_, addr)
        if addr == C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA then return (opts.countsBySide or {})[turn] end
      end,
    },
    dealDamageToPlayAreaPokemon = function(_, slot, amount, targetNonTurn, options)
      calls[#calls + 1] = { side = turn, slot = slot, amount = amount,
        targetNonTurn = targetNonTurn, isDamageToSelf = options and options.isDamageToSelf or false }
      return 1
    end,
  }
  return effects, combat, memory, calls, function() return swaps end
end

-- exchangeRNG failure propagates immediately.
do
  local effects, combat = newEffects({ exchangeFailed = true, exchangeErr = "boom" })
  local carry, err = effects.handlers["BigThunderEffect"](effects, { combat = combat })
  check("exchange failure: carry nil", carry, nil)
  check("exchange failure: propagates the error", err, "boom")
end

-- Own side, no collision: hits a random own-Bench slot.
do
  local effects, combat, memory, calls, swaps = newEffects({
    attackerSlot = 0, countsBySide = { attacker = 4 },
    updateSourcesQueue = { 0 }, randomQueue = { 2 }, turnSequence = { "attacker" },
  })
  local carry = effects.handlers["BigThunderEffect"](effects, { combat = combat })
  check("own side: carry false", carry, false)
  check("own side: no swaps", swaps(), 0)
  check("own side: exactly one damage call", #calls, 1)
  check("own side: hits the picked slot", calls[1].slot, 2)
  check("own side: deals 70", calls[1].amount, 70)
  check("own side: flagged as self-damage", calls[1].isDamageToSelf, true)
  check("own side: sets the thunder animation",
    memory:readSymbol8("wLoadedAttackAnimation"), C.ATK_ANIM_THUNDER_PLAY_AREA)
end

-- Own side, first pick collides with the attacker itself: re-rolls the
-- whole sample (a fresh side coin AND a fresh slot) before succeeding.
do
  local effects, combat, _, calls, swaps = newEffects({
    attackerSlot = 0, countsBySide = { attacker = 4 },
    updateSourcesQueue = { 0, 0 }, randomQueue = { 0, 3 }, turnSequence = { "attacker", "attacker" },
  })
  local carry = effects.handlers["BigThunderEffect"](effects, { combat = combat })
  check("self collision: carry false", carry, false)
  check("self collision: no swaps", swaps(), 0)
  check("self collision: exactly one damage call after the retry", #calls, 1)
  check("self collision: hits the second, non-colliding slot", calls[1].slot, 3)
end

-- Opponent side: swaps, hits a random opponent slot, swaps back -- no
-- self-exclusion needed on this branch.
do
  local effects, combat, _, calls, swaps = newEffects({
    attackerSlot = 0, countsBySide = { defender = 5 },
    updateSourcesQueue = { 1 }, randomQueue = { 4 }, turnSequence = { "defender" },
  })
  local carry = effects.handlers["BigThunderEffect"](effects, { combat = combat })
  check("opponent side: carry false", carry, false)
  check("opponent side: swaps twice (bracket)", swaps(), 2)
  check("opponent side: exactly one damage call", #calls, 1)
  check("opponent side: hits the picked slot", calls[1].slot, 4)
  check("opponent side: not flagged as self-damage", calls[1].isDamageToSelf, false)
  check("opponent side: never asks the primitive to swap itself", calls[1].targetNonTurn, false)
end

if failures == 0 then
  print("all big thunder effect cases passed")
  os.exit(0)
else
  print(("%d big thunder effect case(s) failed"):format(failures))
  os.exit(1)
end
