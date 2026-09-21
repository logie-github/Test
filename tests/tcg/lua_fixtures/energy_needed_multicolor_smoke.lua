-- Behavioral smoke test for AI:checkEnergyNeededForAttack (engine/duel/ai/
-- core.asm CheckEnergyNeededForAttack), run under real LuaJIT. This closes
-- out the last open item on that ledger entry: the source's own comment
-- documents that running its per-color check back to back overwrites the
-- previous color's result, so a (hypothetical -- no real attack in the
-- game's card pool needs it) attack requiring two different colored
-- energy types would only ever report a shortfall for whichever color has
-- the HIGHEST numeric index, discarding any shortfall in a lower-indexed
-- color entirely. AI.lua's ascending `for color = 0, NUM_COLORED_TYPES - 1`
-- loop keeps overwriting `neededColor`/`coloredNeeded` on every shortfall
-- found, so the last (highest-index) shortfall naturally wins -- this
-- proves that under real execution, not just by reading the loop.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  PLAY_AREA_ARENA = 0, PLAY_AREA_BENCH_1 = 1,
  DUELVARS_ARENA_CARD = 0x10,
  NUM_COLORED_TYPES = 6, COLORLESS = 6,
  FIRE = 0, GRASS = 1, LIGHTNING = 2, WATER = 3, FIGHTING = 4, PSYCHIC = 5,
  FIRE_ENERGY = 9001, GRASS_ENERGY = 9003, LIGHTNING_ENERGY = 9004,
  WATER_ENERGY = 9005, FIGHTING_ENERGY = 9006, PSYCHIC_ENERGY = 9007,
  POKEMON_POWER = 99,
}

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(("FAIL  %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
  else
    print(("ok    %s"):format(label))
  end
end

-- opts.attached = {[color]=count} (colors 0..5, 6=colorless).
-- opts.attack = {nameTextId=1, category=0, damage=0, energy={[color]=amount}}.
local function newAI(opts)
  local turn = { [C.DUELVARS_ARENA_CARD] = 1 }
  local attached = opts.attached or {}
  local total = 0
  for _, v in pairs(attached) do total = total + v end
  local memory = { words = { wTotalAttachedEnergies = total },
    readSymbol8 = function(self, name) return self.words[name] or 0 end,
    writeSymbol8 = function(self, name, v) self.words[name] = v end,
    address = function() return 1000, 0 end,
    read8 = function(_, kind, addr, bank) return attached[addr - 1000] or 0 end,
  }
  local ai = AI.new(
    memory,
    { get = function(_, a) return turn[a] or 0 end, getNonTurn = function() return 0 end, swapTurn = function() end },
    { random = function() return 0 end },
    { getCardIDFromDeckIndex = function() return nil end, get = function() return nil end },
    { getPlayAreaCardAttachedEnergies = function() end },
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
  ai:setCombat({
    loadAttack = function(_, deckIndex, attackIndex) return nil, opts.attack end,
    status = { handleEnergyBurn = function() end },
  })
  return ai
end

-- Single colored requirement, fully attached -> no shortfall.
do
  local ai = newAI({
    attack = { nameTextId = 1, category = 0, energy = { [C.FIRE] = 2 } },
    attached = { [C.FIRE] = 2 },
  })
  local need = ai:checkEnergyNeededForAttack(C.PLAY_AREA_ARENA, 0)
  check("single color, fully attached: enough", need.enough, true)
  check("single color, fully attached: colored", need.colored, 0)
end

-- Single colored requirement, short by 1 -> reports that color.
do
  local ai = newAI({
    attack = { nameTextId = 1, category = 0, energy = { [C.WATER] = 2 } },
    attached = { [C.WATER] = 1 },
  })
  local need = ai:checkEnergyNeededForAttack(C.PLAY_AREA_ARENA, 0)
  check("single color, short by 1: enough", need.enough, false)
  check("single color, short by 1: colored", need.colored, 1)
  check("single color, short by 1: color", need.color, C.WATER)
  check("single color, short by 1: energyCardId", need.energyCardId, C.WATER_ENERGY)
end

-- Colorless-only requirement, satisfied by any attached energy type.
do
  local ai = newAI({
    attack = { nameTextId = 1, category = 0, energy = { [C.COLORLESS] = 2 } },
    attached = { [C.FIRE] = 2 },
  })
  local need = ai:checkEnergyNeededForAttack(C.PLAY_AREA_ARENA, 0)
  check("colorless-only, any energy attached: enough", need.enough, true)
  check("colorless-only, any energy attached: colorless", need.colorless, 0)
end

-- Colorless-only requirement, short.
do
  local ai = newAI({
    attack = { nameTextId = 1, category = 0, energy = { [C.COLORLESS] = 2 } },
    attached = { [C.FIRE] = 1 },
  })
  local need = ai:checkEnergyNeededForAttack(C.PLAY_AREA_ARENA, 0)
  check("colorless-only, short: enough", need.enough, false)
  check("colorless-only, short: colorless", need.colorless, 1)
end

-- Hypothetical two-colored-type requirement (no real card needs this): the
-- source's back-to-back overwrite means only the HIGHEST-index color's
-- shortfall is ever reported, discarding the lower-indexed one entirely.
do
  local ai = newAI({
    attack = { nameTextId = 1, category = 0, energy = { [C.FIRE] = 1, [C.WATER] = 1 } },
    attached = {},
  })
  local need = ai:checkEnergyNeededForAttack(C.PLAY_AREA_ARENA, 0)
  check("two colors both short: highest index (WATER) wins", need.color, C.WATER)
  check("two colors both short: FIRE shortfall discarded", need.colored, 1)
end
do
  -- CheckIfEnoughParticularAttachedEnergy only overwrites the running
  -- shortfall when ITS OWN color is actually short (source: `.has_enough`
  -- never touches wTempLoadedAttackEnergyNeededAmount/Type). So when only
  -- the LOWER-indexed color is short and the higher-indexed one is fully
  -- satisfied, the higher color's check leaves the earlier shortfall
  -- untouched -- it's still correctly reported. The "last shortfall found
  -- wins" quirk only bites when two-or-more colors are short at once (the
  -- case above).
  local ai = newAI({
    attack = { nameTextId = 1, category = 0, energy = { [C.FIRE] = 1, [C.WATER] = 1 } },
    attached = { [C.WATER] = 1 },
  })
  local need = ai:checkEnergyNeededForAttack(C.PLAY_AREA_ARENA, 0)
  check("lower color short, higher color satisfied: shortfall still reported", need.enough, false)
  check("lower color short, higher color satisfied: color", need.color, C.FIRE)
end

-- No attack selected (empty name) -> nil, "no_attack".
do
  local ai = newAI({ attack = { nameTextId = 0, category = 0, energy = {} } })
  local need, err = ai:checkEnergyNeededForAttack(C.PLAY_AREA_ARENA, 0)
  check("no attack: need is nil", need, nil)
  check("no attack: reason", err, "no_attack")
end

-- Pokemon Power selected instead of an attack -> nil, "no_attack".
do
  local ai = newAI({ attack = { nameTextId = 1, category = C.POKEMON_POWER, energy = {} } })
  local need, err = ai:checkEnergyNeededForAttack(C.PLAY_AREA_ARENA, 0)
  check("pokemon power: need is nil", need, nil)
  check("pokemon power: reason", err, "no_attack")
end

if failures == 0 then
  print("all checkEnergyNeededForAttack multi-color edge cases passed")
  os.exit(0)
else
  print(("%d checkEnergyNeededForAttack case(s) failed"):format(failures))
  os.exit(1)
end
