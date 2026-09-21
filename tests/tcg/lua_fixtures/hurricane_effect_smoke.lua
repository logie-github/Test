-- Behavioral smoke test for Pidgeotto's Hurricane, run under real
-- LuaJIT.
--
-- Unless the attack was unaffected or the Defending Pokemon was already
-- KO'd, returns the Defending Pokemon and every card attached to it
-- (Energy, Trainers -- anything sharing its CARD_LOCATION_ARENA slot) to
-- the opponent's hand, then clears the Arena slot outright.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = setmetatable({
  DUELVARS_ARENA_CARD_HP = "DUELVARS_ARENA_CARD_HP", DUELVARS_ARENA_CARD = "DUELVARS_ARENA_CARD",
  CARD_LOCATION_ARENA = "CARD_LOCATION_ARENA", CARD_LOCATION_BENCH = "CARD_LOCATION_BENCH",
  DECK_SIZE = 60,
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
  local status = { checkNoDamageOrEffect = function() return opts.prevented == true end }
  local effects = EffectCommands.new(memory, {}, status, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  local turn = "attacker"
  local swaps = 0
  local added = {}
  local writes = {}
  local locations = opts.locations or {}
  local actor = {
    duelVars = {
      swapTurn = function() swaps = swaps + 1; turn = (turn == "attacker") and "defender" or "attacker" end,
      getNonTurn = function(_, addr)
        if addr == C.DUELVARS_ARENA_CARD_HP then return opts.defenderHP or 0 end
      end,
      get = function(_, deckIndex) return (locations[turn] or {})[deckIndex] end,
      set = function(_, addr, value) writes[#writes + 1] = { addr = addr, value = value, turn = turn } end,
    },
    duelOps = { addCardToHand = function(_, deckIndex) added[#added + 1] = deckIndex end },
  }
  return effects, actor, function() return swaps end, added, writes
end

-- Unaffected: no-op entirely.
do
  local effects, actor, swaps, added, writes = newEffects({ prevented = true })
  local carry = effects.handlers["HurricaneEffect"](effects, { combat = actor })
  check("unaffected: carry false", carry, false)
  check("unaffected: no swaps", swaps(), 0)
  check("unaffected: nothing added to hand", #added, 0)
  check("unaffected: no state writes", #writes, 0)
end

-- Defending Pokemon already KO'd: no-op entirely.
do
  local effects, actor, swaps, added, writes = newEffects({ prevented = false, defenderHP = 0 })
  local carry = effects.handlers["HurricaneEffect"](effects, { combat = actor })
  check("already ko'd: carry false", carry, false)
  check("already ko'd: no swaps", swaps(), 0)
  check("already ko'd: nothing added to hand", #added, 0)
  check("already ko'd: no state writes", #writes, 0)
end

-- Normal case: the Defending Pokemon and its attached cards go to hand;
-- unrelated Bench cards are left alone; the Arena slot is cleared.
do
  local locations = {
    defender = { [5] = C.CARD_LOCATION_ARENA, [12] = C.CARD_LOCATION_ARENA,
      [13] = C.CARD_LOCATION_ARENA, [20] = C.CARD_LOCATION_BENCH },
  }
  local effects, actor, swaps, added, writes = newEffects({
    prevented = false, defenderHP = 60, locations = locations,
  })
  local carry = effects.handlers["HurricaneEffect"](effects, { combat = actor })
  check("normal: carry false", carry, false)
  check("normal: swaps twice (bracket)", swaps(), 2)
  check("normal: exactly 3 cards added to hand", #added, 3)
  check("normal: adds the Pokemon itself", added[1], 5)
  check("normal: adds its attached cards too", added[2], 12)
  check("normal: adds its attached cards too (second)", added[3], 13)
  check("normal: exactly 2 state writes (card, hp)", #writes, 2)
  check("normal: clears DUELVARS_ARENA_CARD to 0xff", writes[1].value, 0xff)
  check("normal: clears DUELVARS_ARENA_CARD_HP to 0", writes[2].value, 0)
  check("normal: clears happen while still on the defender's turn", writes[1].turn, "defender")
end

if failures == 0 then
  print("all hurricane effect cases passed")
  os.exit(0)
else
  print(("%d hurricane effect case(s) failed"):format(failures))
  os.exit(1)
end
