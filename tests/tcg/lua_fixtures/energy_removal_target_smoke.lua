-- Behavioral smoke test for AIDecide_EnergyRemoval's real target-priority
-- logic (engine/duel/ai/trainer_cards.asm), run under real LuaJIT.
--
-- Before this change, AI:_decideEnergyRemoval() was a placeholder: it just
-- grabbed the first Play Area slot (starting from Arena) with ANY energy
-- attached, on the Player's side, ignoring the source's actual priority
-- cascade entirely. This exercises two layers for real:
--
-- Part A: the two new small helpers (_lookForEnergyNeededForAttackInHand,
-- _checkIfNotEnoughEnergyToAttack) against the real, already-existing
-- checkEnergyNeededForAttack/_surplusEnergyForAttack pipeline and a real
-- memory-backed wAttachedEnergies block (not stubbed -- this is exactly the
-- kind of energy-cost arithmetic a source-text search cannot verify).
--
-- Part B: _decideEnergyRemoval's own control flow (where to start scanning,
-- first-match-wins, the Bench-damage fallback, "nothing found" -> false),
-- with the already-proven-elsewhere deep collaborators
-- (checkIfAnyAttackKnocksOutDefendingCard, _checkAttackUsableForAI,
-- _findHighestDamagingBenchAttack, _pickAttachedEnergyToRemove) stubbed at
-- the instance level to isolate the orchestration itself.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  PLAY_AREA_ARENA = 0, PLAY_AREA_BENCH_1 = 1, MAX_PLAY_AREA_POKEMON = 6,
  FIRST_ATTACK_OR_PKMN_POWER = 0, SECOND_ATTACK = 1,
  DUELVARS_ARENA_CARD = 0x10,
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = 0x40,
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x30, DUELVARS_HAND = 0x31,
  POKEMON_POWER = 99,
  NUM_COLORED_TYPES = 6, COLORLESS = 6,
  TYPE_ENERGY = 8, TYPE_TRAINER = 9,
  FIRE = 0, GRASS = 1, LIGHTNING = 2, WATER = 3, FIGHTING = 4, PSYCHIC = 5,
  FIRE_ENERGY = 9001, GRASS_ENERGY = 9003, LIGHTNING_ENERGY = 9004,
  WATER_ENERGY = 9005, FIGHTING_ENERGY = 9006, PSYCHIC_ENERGY = 9007,
  DOUBLE_COLORLESS_ENERGY = 9002,
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

-- ---------------------------------------------------------------------
-- Part A harness: real checkEnergyNeededForAttack/_surplusEnergyForAttack.
-- ---------------------------------------------------------------------
local function newFakeMemory()
  local words = {}
  local attached = {}
  local BASE = 1000
  return {
    readSymbol8 = function(_, name) return words[name] or 0 end,
    writeSymbol8 = function(_, name, v) words[name] = v end,
    address = function(_, name)
      if name == "wAttachedEnergies" then return BASE, 0 end
      return 0, 0
    end,
    read8 = function(_, kind, addr, bank) return attached[addr - BASE] or 0 end,
    write8 = function(_, kind, addr, value, bank) attached[addr - BASE] = value end,
    _setAttached = function(_, color, value) attached[color] = value end,
  }
end

-- opts.attacks = {[0]=firstAttack, [1]=secondAttack}, opts.attachedByColor
-- = {[color]=count} (colors 0..5 = COLORED, 6 = COLORLESS).
-- opts.handCardIds = array of card IDs in hand.
local function newPartAAI(opts)
  local memory = newFakeMemory()
  for color, count in pairs(opts.attachedByColor or {}) do memory:_setAttached(color, count) end
  local hand = opts.handCardIds or {}
  local turn = {
    [C.DUELVARS_ARENA_CARD] = 1,
    [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = #hand,
  }
  local cardIdByDeckIndex = { [1] = 500 }
  for i, cardId in ipairs(hand) do
    turn[C.DUELVARS_HAND + (i - 1)] = 100 + i
    cardIdByDeckIndex[100 + i] = cardId
  end
  local cardTypes = {}
  for _, cardId in ipairs(hand) do
    cardTypes[cardId] = (cardId >= 9000 and cardId < 9100) and C.TYPE_ENERGY or 0
  end
  local ai = AI.new(
    memory,
    { get = function(_, a) return turn[a] end, getNonTurn = function() return 0 end,
      swapTurn = function() end },
    { random = function() return 0 end },
    {
      getCardIDFromDeckIndex = function(_, deckIndex) return cardIdByDeckIndex[deckIndex] end,
      get = function(_, cardId) return { type = cardTypes[cardId] or 0 } end,
    },
    {
      getPlayAreaCardAttachedEnergies = function(_, slot)
        local total = 0
        for c = 0, C.NUM_COLORED_TYPES do total = total + memory:read8("wram", 1000 + c, 0) end
        memory:writeSymbol8("wTotalAttachedEnergies", total)
        return total
      end,
    },
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
  ai:setCombat({
    loadAttack = function(_, deckIndex, attackIndex) return nil, (opts.attacks or {})[attackIndex] end,
    status = { handleEnergyBurn = function() end },
  })
  return ai
end

-- ---------------------------------------------------------------------
-- _lookForEnergyNeededForAttackInHand
-- ---------------------------------------------------------------------
do
  -- Needs exactly 1 Fire Energy; Fire Energy is in hand.
  local ai = newPartAAI({
    attacks = { [0] = { nameTextId = 1, category = 0, energy = { [C.FIRE] = 1 } } },
    attachedByColor = {},
    handCardIds = { C.FIRE_ENERGY },
  })
  check("needs 1 colored, matching card in hand -> found",
    ai:_lookForEnergyNeededForAttackInHand(C.PLAY_AREA_ARENA, 0), true)
end
do
  -- Needs exactly 1 Fire Energy; hand has Water Energy instead.
  local ai = newPartAAI({
    attacks = { [0] = { nameTextId = 1, category = 0, energy = { [C.FIRE] = 1 } } },
    attachedByColor = {},
    handCardIds = { C.WATER_ENERGY },
  })
  check("needs 1 colored, non-matching card in hand -> not found",
    ai:_lookForEnergyNeededForAttackInHand(C.PLAY_AREA_ARENA, 0), false)
end
do
  -- Needs exactly 1 Colorless; any Energy in hand satisfies it.
  local ai = newPartAAI({
    attacks = { [0] = { nameTextId = 1, category = 0, energy = { [C.COLORLESS] = 1 } } },
    attachedByColor = {},
    handCardIds = { C.WATER_ENERGY },
  })
  check("needs 1 colorless, any Energy in hand -> found",
    ai:_lookForEnergyNeededForAttackInHand(C.PLAY_AREA_ARENA, 0), true)
end
do
  -- Needs exactly 2 Colorless; only Double Colorless Energy satisfies it.
  local ai = newPartAAI({
    attacks = { [0] = { nameTextId = 1, category = 0, energy = { [C.COLORLESS] = 2 } } },
    attachedByColor = {},
    handCardIds = { C.DOUBLE_COLORLESS_ENERGY },
  })
  check("needs 2 colorless, DCE in hand -> found",
    ai:_lookForEnergyNeededForAttackInHand(C.PLAY_AREA_ARENA, 0), true)
end
do
  -- Needs exactly 2 Colorless; ordinary Energy in hand does NOT satisfy it.
  local ai = newPartAAI({
    attacks = { [0] = { nameTextId = 1, category = 0, energy = { [C.COLORLESS] = 2 } } },
    attachedByColor = {},
    handCardIds = { C.FIRE_ENERGY },
  })
  check("needs 2 colorless, ordinary Energy in hand -> not found",
    ai:_lookForEnergyNeededForAttackInHand(C.PLAY_AREA_ARENA, 0), false)
end
do
  -- Needs 1 colored + 1 colorless (total 2, not the colorless==2 case) -> unhandled.
  local ai = newPartAAI({
    attacks = { [0] = { nameTextId = 1, category = 0, energy = { [C.FIRE] = 1, [C.COLORLESS] = 1 } } },
    attachedByColor = {},
    handCardIds = { C.FIRE_ENERGY, C.DOUBLE_COLORLESS_ENERGY },
  })
  check("needs 1 colored + 1 colorless (unhandled combo) -> not found",
    ai:_lookForEnergyNeededForAttackInHand(C.PLAY_AREA_ARENA, 0), false)
end

-- ---------------------------------------------------------------------
-- _checkIfNotEnoughEnergyToAttack
-- ---------------------------------------------------------------------
do
  -- First attack already has enough -> "not enough" is false.
  local ai = newPartAAI({
    attacks = { [0] = { nameTextId = 1, category = 0, energy = { [C.FIRE] = 1 } } },
    attachedByColor = { [C.FIRE] = 1 },
  })
  check("first attack has enough -> false (has enough)",
    ai:_checkIfNotEnoughEnergyToAttack(C.PLAY_AREA_ARENA), false)
end
do
  -- Neither attack has enough -> true.
  local ai = newPartAAI({
    attacks = {
      [0] = { nameTextId = 1, category = 0, energy = { [C.FIRE] = 2 } },
      [1] = { nameTextId = 2, category = 0, energy = { [C.WATER] = 2 } },
    },
    attachedByColor = {},
  })
  check("neither attack has enough -> true (not enough)",
    ai:_checkIfNotEnoughEnergyToAttack(C.PLAY_AREA_ARENA), true)
end
do
  -- First attack not enough, second attack enough with NO surplus (exact
  -- match) -> false (worth picking).
  local ai = newPartAAI({
    attacks = {
      [0] = { nameTextId = 1, category = 0, energy = { [C.FIRE] = 5 } },
      [1] = { nameTextId = 2, category = 0, energy = { [C.WATER] = 1 } },
    },
    attachedByColor = { [C.WATER] = 1 },
  })
  check("second attack enough, exact match (no surplus) -> false (worth picking)",
    ai:_checkIfNotEnoughEnergyToAttack(C.PLAY_AREA_ARENA), false)
end
do
  -- First attack not enough, second attack enough WITH surplus -> true (not
  -- worth picking -- removing one Energy card wouldn't disable it).
  local ai = newPartAAI({
    attacks = {
      [0] = { nameTextId = 1, category = 0, energy = { [C.FIRE] = 5 } },
      [1] = { nameTextId = 2, category = 0, energy = { [C.WATER] = 1 } },
    },
    attachedByColor = { [C.WATER] = 2 },
  })
  check("second attack enough WITH surplus -> true (not worth picking)",
    ai:_checkIfNotEnoughEnergyToAttack(C.PLAY_AREA_ARENA), true)
end

-- ---------------------------------------------------------------------
-- Part B harness: _decideEnergyRemoval orchestration, deep collaborators
-- stubbed at the instance level.
-- ---------------------------------------------------------------------
local function newPartBAI(opts)
  local turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = opts.playAreaCount or 3 }
  local swaps = 0
  local ai = AI.new(
    { readSymbol8 = function() return 0 end, writeSymbol8 = function() end },
    {
      get = function(_, a) return turn[a] or 0 end,
      getNonTurn = function() return 0 end,
      swapTurn = function() swaps = swaps + 1 end,
    },
    { random = function() return 0 end },
    { getCardIDFromDeckIndex = function() return nil end, get = function() return nil end },
    {
      getPlayAreaCardAttachedEnergies = function(_, slot)
        return (opts.attachedBySlot or {})[slot] or 0
      end,
    },
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
  ai.checkIfAnyAttackKnocksOutDefendingCard = function()
    if opts.canKO == nil then return false end
    return opts.canKO, 0
  end
  ai._checkAttackUsableForAI = function() return opts.attackUsable == true end
  ai._lookForEnergyNeededForAttackInHand = function() return opts.energyInHand == true end
  ai._checkIfNotEnoughEnergyToAttack = function(_, slot)
    return (opts.notEnoughBySlot or {})[slot] ~= false
  end
  ai._findHighestDamagingBenchAttack = function(_, slot)
    return (opts.damageBySlot or {})[slot] or 0
  end
  local pickCalls = {}
  ai._pickAttachedEnergyToRemove = function(_, slot, nonTurn)
    pickCalls[#pickCalls + 1] = { slot = slot, nonTurn = nonTurn }
    return (opts.energyDeckIndexBySlot or {})[slot]
  end
  return ai, function() return swaps end, pickCalls
end

do
  -- AI can already KO Player's Active, and the KO attack is usable now ->
  -- start scanning from the Bench, skipping the (doomed-anyway) Active.
  local ai, swaps, picks = newPartBAI({
    canKO = true, attackUsable = true, playAreaCount = 3,
    attachedBySlot = { [1] = 1 }, notEnoughBySlot = { [1] = false },
    energyDeckIndexBySlot = { [1] = 77 },
  })
  local ok, result = ai:_decideEnergyRemoval()
  check("KO+usable: starts from Bench -> picks slot 1 not Arena", result.opponentPlayArea, 1)
  check("KO+usable: swapTurn called in a balanced pair", swaps(), 2)
end
do
  -- AI can KO, attack NOT usable now, but the needed Energy is in hand ->
  -- still start from the Bench (AI can fix the KO itself this turn).
  local ai = newPartBAI({
    canKO = true, attackUsable = false, energyInHand = true, playAreaCount = 2,
    attachedBySlot = { [1] = 1 }, notEnoughBySlot = { [1] = false },
    energyDeckIndexBySlot = { [1] = 77 },
  })
  local ok, result = ai:_decideEnergyRemoval()
  check("KO, unusable, energy in hand: starts from Bench", result.opponentPlayArea, 1)
end
do
  -- AI can KO, attack NOT usable, needed Energy NOT in hand -> start from
  -- the Arena after all (AI can't actually convert this into a KO).
  local ai = newPartBAI({
    canKO = true, attackUsable = false, energyInHand = false, playAreaCount = 2,
    attachedBySlot = { [0] = 1 }, notEnoughBySlot = { [0] = false },
    energyDeckIndexBySlot = { [0] = 55 },
  })
  local ok, result = ai:_decideEnergyRemoval()
  check("KO, unusable, no energy in hand: starts from Arena", result.opponentPlayArea, 0)
end
do
  -- AI cannot KO at all -> start from the Arena.
  local ai = newPartBAI({
    canKO = false, playAreaCount = 2,
    attachedBySlot = { [0] = 1 }, notEnoughBySlot = { [0] = false },
    energyDeckIndexBySlot = { [0] = 55 },
  })
  local ok, result = ai:_decideEnergyRemoval()
  check("cannot KO: starts from Arena", result.opponentPlayArea, 0)
end
do
  -- Skips a card with energy attached but NOT enough to attack, continues
  -- scanning to the next slot.
  local ai = newPartBAI({
    canKO = false, playAreaCount = 3,
    attachedBySlot = { [0] = 1, [1] = 0, [2] = 1 },
    notEnoughBySlot = { [0] = true, [2] = false },
    energyDeckIndexBySlot = { [2] = 99 },
  })
  local ok, result = ai:_decideEnergyRemoval()
  check("skips not-enough-to-attack Arena, skips no-energy Bench1, picks Bench2",
    result.opponentPlayArea, 2)
end
do
  -- Nothing in the main scan qualifies -> falls back to the Bench-only
  -- highest-damage pass.
  local ai = newPartBAI({
    canKO = false, playAreaCount = 3,
    attachedBySlot = { [0] = 1, [1] = 1, [2] = 1 },
    notEnoughBySlot = { [0] = true, [1] = true, [2] = true },
    damageBySlot = { [1] = 30, [2] = 50 },
    energyDeckIndexBySlot = { [2] = 88 },
  })
  local ok, result = ai:_decideEnergyRemoval()
  check("fallback: picks the higher-damage Bench slot (2 over 1)", result.opponentPlayArea, 2)
  check("fallback: energy deck index from the picked slot", result.opponentEnergyDeckIndex, 88)
end
do
  -- Nothing anywhere (no energy at all) -> false.
  local ai = newPartBAI({ canKO = false, playAreaCount = 2, attachedBySlot = {} })
  local ok = ai:_decideEnergyRemoval()
  check("nothing found anywhere -> false", ok, false)
end
do
  -- _pickAttachedEnergyToRemove is called BEFORE the final swap back (still
  -- on the Player's turn), with nonTurn=false (matching the source calling
  -- PickAttachedEnergyCardToRemove before its own final SwapTurn).
  local ai, _, picks = newPartBAI({
    canKO = false, playAreaCount = 2,
    attachedBySlot = { [0] = 1 }, notEnoughBySlot = { [0] = false },
    energyDeckIndexBySlot = { [0] = 42 },
  })
  ai:_decideEnergyRemoval()
  check("_pickAttachedEnergyToRemove called once", #picks, 1)
  check("_pickAttachedEnergyToRemove: slot", picks[1].slot, 0)
  check("_pickAttachedEnergyToRemove: nonTurn=false", picks[1].nonTurn, false)
end

if failures == 0 then
  print("all Energy Removal target-priority cases passed")
  os.exit(0)
else
  print(("%d Energy Removal target-priority case(s) failed"):format(failures))
  os.exit(1)
end
