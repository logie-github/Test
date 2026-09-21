-- Behavioral smoke test for Pokemon Breeder's AI decision arithmetic
-- (AIDecide_PokemonBreeder, trainer_cards.asm): the CalculateFitness score
-- (HP-counters-swapped-nibble | capped energy count), the Dragonite Lv41
-- evolution gate, and the two-pass forced-priority/general-fallback scan.
-- Run under real LuaJIT rather than only checked as source text.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  PLAY_AREA_ARENA = 0, PLAY_AREA_BENCH_1 = 1, PLAY_AREA_BENCH_2 = 2,
  MAX_PLAY_AREA_POKEMON = 3,
  DUELVARS_ARENA_CARD = 0x10, DUELVARS_ARENA_CARD_HP = 0x20,
  DUELVARS_ARENA_CARD_FLAGS = 0x50,
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = 0x40,
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x30, DUELVARS_HAND = 0x31,
  CAN_EVOLVE_THIS_TURN = 1,
  NUM_COLORED_TYPES = 6, COLORLESS = 6,
  TYPE_ENERGY = 8, TYPE_TRAINER = 9, STAGE2 = 2, BASIC = 0,
  AERODACTYL = 5001, MUK = 5002,
  VENUSAUR_LV64 = 10, VENUSAUR_LV67 = 11, BLASTOISE = 12, VILEPLUME = 13,
  ALAKAZAM = 14, GENGAR = 15, DRAGONITE_LV41 = 16,
  OTHER_STAGE2 = 20, BULBASAUR = 30,
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

local function newAI(opts)
  opts = opts or {}
  local ai = AI.new(
    { readSymbol8 = function() return 0 end, writeSymbol8 = function() end },
    {
      get = function(_, addr) return (opts.turn or {})[addr] end,
      getNonTurn = function(_, addr) return (opts.nonTurn or {})[addr] end,
      set = function(_, addr, v) (opts.turn or {})[addr] = v end,
      swapTurn = function() end,
    },
    { random = function() return 5 end },
    {
      getCardIDFromDeckIndex = function(_, deckIndex) return (opts.deckIndexToCardId or {})[deckIndex] end,
      get = function(_, cardId) return (opts.cardRows or {})[cardId] end,
    },
    {
      createHandCardList = function() return opts.hand or {} end,
      checkIfCanEvolveIntoBasicToStage2 = function(_, deckIndex, slot)
        local fn = opts.canEvolve
        if not fn then return true end
        return fn(deckIndex, slot)
      end,
      getPlayAreaCardAttachedEnergies = function(_, slot)
        return (opts.energyAt or {})[slot] or 0
      end,
      countNumberOfEnergyCardsAttached = function(_, slot)
        return (opts.energyCardsAt or {})[slot] or 0
      end,
    },
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
  ai.combat = { status = {
    countPokemonWithActivePkmnPowerInBothPlayAreas = function(_, cardId)
      if cardId == C.AERODACTYL then return nil, opts.aerodactylActive or false end
      if cardId == C.MUK then return nil, opts.mukActive or false end
      return nil, false
    end,
  } }
  return ai
end

-- ---------------------------------------------------------------------
-- _breederFitnessScore: swap-nibble of HP counters | capped energy count.
-- ---------------------------------------------------------------------
do
  local ai = newAI({ turn = { [C.DUELVARS_ARENA_CARD_HP] = 40 }, energyAt = { [0] = 3 } })
  -- 40 HP -> 4 counters -> swap(4) = 0x40; energy 3 -> score 0x43.
  check("fitness: 40 HP / 3 energy -> 0x43", ai:_breederFitnessScore(0), 0x43)
end
do
  local ai = newAI({ turn = { [C.DUELVARS_ARENA_CARD_HP] = 0 }, energyAt = { [0] = 20 } })
  -- Energy count is explicitly capped at 15 before the OR.
  check("fitness: energy count caps at 15", ai:_breederFitnessScore(0), 15)
end

-- ---------------------------------------------------------------------
-- _dragoniteLv41Blocks: only gates evolutions into Dragonite Lv41.
-- ---------------------------------------------------------------------
do
  local ai = newAI({})
  check("dragonite gate: non-Dragonite target never blocked",
    ai:_dragoniteLv41Blocks(C.OTHER_STAGE2, C.PLAY_AREA_ARENA), false)
end
do
  -- Active card, raw damage 4 (<5) -> blocked regardless of energy.
  local ai = newAI({ turn = { [C.DUELVARS_ARENA_CARD + 0] = 1, [C.DUELVARS_ARENA_CARD_HP + 0] = 96 },
    deckIndexToCardId = { [1] = C.BULBASAUR }, cardRows = { [C.BULBASAUR] = { hp = 100 } },
    energyCardsAt = { [0] = 5 } })
  check("dragonite gate: active with <5 raw damage blocked",
    ai:_dragoniteLv41Blocks(C.DRAGONITE_LV41, C.PLAY_AREA_ARENA), true)
end
do
  local ai = newAI({ turn = { [C.DUELVARS_ARENA_CARD + 0] = 1, [C.DUELVARS_ARENA_CARD_HP + 0] = 90 },
    deckIndexToCardId = { [1] = C.BULBASAUR }, cardRows = { [C.BULBASAUR] = { hp = 100 } },
    energyCardsAt = { [0] = 2 } })
  -- damage = 10 (>=5) but energyCardsAttached = 2 (<3) -> blocked.
  check("dragonite gate: active with enough damage but <3 energy cards blocked",
    ai:_dragoniteLv41Blocks(C.DRAGONITE_LV41, C.PLAY_AREA_ARENA), true)
end
do
  local ai = newAI({ turn = { [C.DUELVARS_ARENA_CARD + 0] = 1, [C.DUELVARS_ARENA_CARD_HP + 0] = 90 },
    deckIndexToCardId = { [1] = C.BULBASAUR }, cardRows = { [C.BULBASAUR] = { hp = 100 } },
    energyCardsAt = { [0] = 3 } })
  -- damage = 10 (>=5) and energyCardsAttached = 3 (>=3) -> allowed.
  check("dragonite gate: active with enough damage and energy allowed",
    ai:_dragoniteLv41Blocks(C.DRAGONITE_LV41, C.PLAY_AREA_ARENA), false)
end
do
  -- Bench card: gate depends on TOTAL damage counters across the WHOLE play
  -- area (not just the bench card itself), threshold >=8 counters (>=80 HP).
  local ai = newAI({
    turn = {
      [C.DUELVARS_ARENA_CARD + 0] = 1, [C.DUELVARS_ARENA_CARD_HP + 0] = 60,
      [C.DUELVARS_ARENA_CARD + 1] = 2, [C.DUELVARS_ARENA_CARD_HP + 1] = 90,
      [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2,
    },
    deckIndexToCardId = { [1] = C.BULBASAUR, [2] = C.BULBASAUR },
    cardRows = { [C.BULBASAUR] = { hp = 100 } },
  })
  -- Damage: slot0 = 40, slot1 = 10 -> counters 4 + 1 = 5 (<8) -> blocked.
  check("dragonite gate: bench blocked when whole-play-area damage under 8 counters",
    ai:_dragoniteLv41Blocks(C.DRAGONITE_LV41, C.PLAY_AREA_BENCH_1), true)
end
do
  local ai = newAI({
    turn = {
      [C.DUELVARS_ARENA_CARD + 0] = 1, [C.DUELVARS_ARENA_CARD_HP + 0] = 10,
      [C.DUELVARS_ARENA_CARD + 1] = 2, [C.DUELVARS_ARENA_CARD_HP + 1] = 10,
      [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2,
    },
    deckIndexToCardId = { [1] = C.BULBASAUR, [2] = C.BULBASAUR },
    cardRows = { [C.BULBASAUR] = { hp = 100 } },
  })
  -- Damage: slot0 = 90, slot1 = 90 -> counters 9+9=18 (>=8) -> allowed.
  check("dragonite gate: bench allowed when whole-play-area damage at least 8 counters",
    ai:_dragoniteLv41Blocks(C.DRAGONITE_LV41, C.PLAY_AREA_BENCH_1), false)
end

-- ---------------------------------------------------------------------
-- _decidePokemonBreeder: Prehistoric Power veto.
-- ---------------------------------------------------------------------
do
  local ai = newAI({ aerodactylActive = true, mukActive = false,
    hand = { 1 }, turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 1 } })
  check("decide: Prehistoric Power active vetoes the whole card",
    ai:_decidePokemonBreeder(), false)
end

-- ---------------------------------------------------------------------
-- _decidePokemonBreeder: empty hand -> false.
-- ---------------------------------------------------------------------
do
  local ai = newAI({ hand = {}, turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 1 } })
  check("decide: empty hand -> false", ai:_decidePokemonBreeder(), false)
end

-- ---------------------------------------------------------------------
-- _decidePokemonBreeder: forced-priority pass has no minimum-energy
-- requirement (unlike the general pass), and wins even with 0 energy.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    hand = { 7 },
    deckIndexToCardId = { [7] = C.ALAKAZAM },
    cardRows = { [C.ALAKAZAM] = { type = 0, stage = C.STAGE2 } },
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 1, [C.DUELVARS_ARENA_CARD_HP] = 30 },
    energyAt = { [0] = 0 },
    canEvolve = function() return true end,
  })
  local decided, selection = ai:_decidePokemonBreeder()
  check("decide: forced-priority Alakazam picked despite 0 energy", decided, true)
  check("decide: forced-priority selection targets slot 0", selection and selection.playArea, 0)
  check("decide: forced-priority selection carries the hand card", selection and selection.handStage2Pokemon, 7)
end

-- ---------------------------------------------------------------------
-- _decidePokemonBreeder: general pass requires >=2 attached Energy on the
-- candidate slot; a 1-energy candidate is skipped even if it is the only
-- Stage2 card that can evolve anything.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    hand = { 9 },
    deckIndexToCardId = { [9] = C.OTHER_STAGE2 },
    cardRows = { [C.OTHER_STAGE2] = { type = 0, stage = C.STAGE2 } },
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 1, [C.DUELVARS_ARENA_CARD_HP] = 30 },
    energyAt = { [0] = 1 },
    canEvolve = function() return true end,
  })
  check("decide: general pass rejects a candidate with only 1 energy attached",
    ai:_decidePokemonBreeder(), false)
end
do
  local ai = newAI({
    hand = { 9 },
    deckIndexToCardId = { [9] = C.OTHER_STAGE2 },
    cardRows = { [C.OTHER_STAGE2] = { type = 0, stage = C.STAGE2 } },
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 1, [C.DUELVARS_ARENA_CARD_HP] = 30 },
    energyAt = { [0] = 2 },
    canEvolve = function() return true end,
  })
  local decided, selection = ai:_decidePokemonBreeder()
  check("decide: general pass accepts a candidate with exactly 2 energy attached", decided, true)
  check("decide: general-pass selection carries the hand card", selection and selection.handStage2Pokemon, 9)
end

-- ---------------------------------------------------------------------
-- _decidePokemonBreeder: general pass respects the Dragonite Lv41 gate.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    hand = { 9 },
    deckIndexToCardId = { [9] = C.DRAGONITE_LV41, [1] = C.BULBASAUR },
    cardRows = { [C.DRAGONITE_LV41] = { type = 0, stage = C.STAGE2 }, [C.BULBASAUR] = { hp = 100 } },
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 1, [C.DUELVARS_ARENA_CARD] = 1,
      [C.DUELVARS_ARENA_CARD_HP] = 100 },
    energyAt = { [0] = 5 }, energyCardsAt = { [0] = 0 },
    canEvolve = function() return true end,
  })
  -- Active target, 0 raw damage (<5) -> Dragonite gate blocks despite plenty
  -- of energy for the ordinary >=2 check.
  check("decide: Dragonite Lv41 target blocked via the dedicated gate even with enough energy",
    ai:_decidePokemonBreeder(), false)
end

-- ---------------------------------------------------------------------
-- _decidePokemonBreeder: ties keep the first (lowest-index) slot.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    hand = { 9 },
    deckIndexToCardId = { [9] = C.OTHER_STAGE2 },
    cardRows = { [C.OTHER_STAGE2] = { type = 0, stage = C.STAGE2 } },
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2, [C.DUELVARS_ARENA_CARD_HP] = 30,
      [C.DUELVARS_ARENA_CARD_HP + 1] = 30 },
    energyAt = { [0] = 2, [1] = 2 },
    canEvolve = function() return true end,
  })
  local decided, selection = ai:_decidePokemonBreeder()
  check("decide: equal-score general-pass tie keeps the first slot", decided, true)
  check("decide: equal-score general-pass tie -> slot 0", selection and selection.playArea, 0)
end

if failures == 0 then
  print("all Pokemon Breeder AI decision cases passed")
  os.exit(0)
else
  print(("%d Pokemon Breeder AI decision case(s) failed"):format(failures))
  os.exit(1)
end
