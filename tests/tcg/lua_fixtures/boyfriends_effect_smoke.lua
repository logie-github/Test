-- Behavioral smoke test for Nidoqueen's Boyfriends, run under real LuaJIT.
-- Closes 1 more of the card-effects backlog.
--
-- +20 damage for every Nidoking in the attacker's own Play Area. Scans
-- DUELVARS_ARENA_CARD across the play area (the same shape as
-- _playAreaDamage's other callers), counts Nidoking, and adds 20 per match
-- onto the already-loaded printed damage via the shared _addToDamage
-- helper (AddToDamage in the source).

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = setmetatable({
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = "DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA",
  DUELVARS_ARENA_CARD = 0x10, NIDOKING = 111, RAICHU = 26,
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

local function newEffects(cardIds, initialDamage)
  local words = {}
  local memory = {
    address = function(_, symbol)
      check("touches wDamage", symbol, "wDamage")
      return 1000, 0
    end,
    read8 = function(_, area, addr) return words[addr] or 0 end,
    write8 = function(_, area, addr, value) words[addr] = value end,
  }
  words[1000] = (initialDamage or 0) % 0x100
  words[1001] = math.floor((initialDamage or 0) / 0x100)
  local actor = {
    duelVars = { get = function(_, addr)
      if addr == C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA then return #cardIds end
      return cardIds[(addr - C.DUELVARS_ARENA_CARD) + 1]
    end },
    cardData = { getCardIDFromDeckIndex = function(_, deckIndex) return deckIndex end },
  }
  local effects = EffectCommands.new(memory, {}, {}, C, { schema = 1, byAddress = {}, byLabel = {} }, {})
  local function readDamage() return (words[1000] or 0) + 0x100 * (words[1001] or 0) end
  return effects, actor, readDamage
end

-- No Nidoking anywhere: no damage boost.
do
  local effects, actor, readDamage = newEffects({ C.RAICHU, C.RAICHU }, 30)
  local carry = effects.handlers["BoyfriendsEffect"](effects, { combat = actor })
  check("no nidoking: carry false", carry, false)
  check("no nidoking: damage unchanged", readDamage(), 30)
end

-- One Nidoking: +20.
do
  local effects, actor, readDamage = newEffects({ C.NIDOKING, C.RAICHU }, 30)
  local carry = effects.handlers["BoyfriendsEffect"](effects, { combat = actor })
  check("one nidoking: carry false", carry, false)
  check("one nidoking: damage +20", readDamage(), 50)
end

-- Two Nidoking (own Nidoqueen plus a benched Nidoking, plus a third slot): +40.
do
  local effects, actor, readDamage = newEffects({ C.NIDOKING, C.RAICHU, C.NIDOKING }, 30)
  local carry = effects.handlers["BoyfriendsEffect"](effects, { combat = actor })
  check("two nidoking: carry false", carry, false)
  check("two nidoking: damage +40", readDamage(), 70)
end

if failures == 0 then
  print("all boyfriends effect cases passed")
  os.exit(0)
else
  print(("%d boyfriends effect case(s) failed"):format(failures))
  os.exit(1)
end
