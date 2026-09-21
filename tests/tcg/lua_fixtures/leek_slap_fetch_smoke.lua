-- Behavioral smoke test for Farfetch'd's Leek Slap once-per-duel gate and
-- Fetch (a simple "draw 1 card" attack), run under real LuaJIT. Closes 3
-- more of the card-effects backlog.
--
-- Leek Slap: a duel-long flag on the Arena card (USED_LEEK_SLAP_THIS_DUEL_F),
-- distinct from the per-turn USED_PKMN_POWER_THIS_TURN flags used
-- elsewhere in this file -- once set, it never clears for the rest of the
-- duel.
-- Fetch: DrawCardFromDeck then AddCardToHand; does nothing if the deck is
-- empty (everything past that in the source is pure presentation).

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")
local bit = require("bit")

local C = setmetatable({
  DUELVARS_ARENA_CARD_FLAGS = 0x60,
  USED_LEEK_SLAP_THIS_DUEL_F = 5,
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
  local flags = { [C.DUELVARS_ARENA_CARD_FLAGS] = opts.flags or 0 }
  local drawQueue = opts.drawQueue or {}
  local drawIndex = 0
  local hand = {}
  local actor = {
    duelVars = {
      get = function(_, a) return flags[a] or 0 end,
      set = function(_, a, v) flags[a] = v end,
      getNonTurn = function() return 0 end, swapTurn = function() end,
    },
    duelOps = {
      drawCardFromDeck = function()
        drawIndex = drawIndex + 1
        local entry = drawQueue[drawIndex]
        if not entry then return nil, true end
        return entry, false
      end,
      addCardToHand = function(_, deckIndex) hand[#hand + 1] = deckIndex end,
    },
  }
  local memory = setmetatable({}, { __index = function() return function() return 0 end end })
  local effects = EffectCommands.new(memory, {}, {}, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  return effects, actor, hand
end

-- LeekSlap_OncePerDuelCheck
do
  local effects, actor = newEffects({ flags = 0 })
  local carry = effects.handlers["LeekSlap_OncePerDuelCheck"](effects, { combat = actor })
  check("never used -> ok (carry false)", carry, false)
end
do
  local effects, actor = newEffects({ flags = bit.lshift(1, C.USED_LEEK_SLAP_THIS_DUEL_F) })
  local carry = effects.handlers["LeekSlap_OncePerDuelCheck"](effects, { combat = actor })
  check("already used this duel -> fail (carry true)", carry, true)
end

-- LeekSlap_SetUsedThisDuelFlag
do
  local effects, actor = newEffects({ flags = 0 })
  local carry = effects.handlers["LeekSlap_SetUsedThisDuelFlag"](effects, { combat = actor })
  check("set flag: carry false", carry, false)
  local flags = actor.duelVars:get(C.DUELVARS_ARENA_CARD_FLAGS)
  check("set flag: flag now set", bit.band(flags, bit.lshift(1, C.USED_LEEK_SLAP_THIS_DUEL_F)) ~= 0, true)
end
do
  -- Setting again preserves any other flag bits already set.
  local otherBit = bit.lshift(1, 2)
  local effects, actor = newEffects({ flags = otherBit })
  effects.handlers["LeekSlap_SetUsedThisDuelFlag"](effects, { combat = actor })
  local flags = actor.duelVars:get(C.DUELVARS_ARENA_CARD_FLAGS)
  check("set flag: other bits preserved", bit.band(flags, otherBit) ~= 0, true)
end

-- FetchEffect
do
  local effects, actor, hand = newEffects({ drawQueue = { 42 } })
  local carry = effects.handlers["FetchEffect"](effects, { combat = actor })
  check("deck has a card: carry false", carry, false)
  check("deck has a card: added to hand", hand[1], 42)
  check("deck has a card: exactly one card added", #hand, 1)
end
do
  local effects, actor, hand = newEffects({ drawQueue = {} })
  local carry = effects.handlers["FetchEffect"](effects, { combat = actor })
  check("empty deck: carry false (does nothing, not an error)", carry, false)
  check("empty deck: nothing added to hand", #hand, 0)
end

if failures == 0 then
  print("all Leek Slap / Fetch effect cases passed")
  os.exit(0)
else
  print(("%d Leek Slap / Fetch effect case(s) failed"):format(failures))
  os.exit(1)
end
