-- Behavioral smoke test for Scoop Up's AI decision (AIDecide_ScoopUp,
-- trainer_cards.asm, general path), run under real LuaJIT rather than only
-- checked as source text: the KO/usability short-circuit, the
-- status/retreat-cost gate, the 70%-max-HP damage threshold (computed via
-- the source's own floor(rawDamage / floor(maxHP/10)) integer division, not
-- a floating-point approximation), and the specialized-deck fail-closed veto.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  PLAY_AREA_ARENA = 0, PLAY_AREA_BENCH_1 = 1, MAX_PLAY_AREA_POKEMON = 3,
  FIRST_ATTACK_OR_PKMN_POWER = 0, SECOND_ATTACK = 1,
  DUELVARS_ARENA_CARD = 0x10, DUELVARS_ARENA_CARD_HP = 0x20,
  DUELVARS_ARENA_CARD_STATUS = 0x30,
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = 0x40,
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x50, DUELVARS_HAND = 0x51,
  POKEMON_POWER = 99,
  CNF_SLP_PRZ = 0x07, PARALYZED = 0x02, ASLEEP = 0x04, NO_STATUS = 0,
  LEGENDARY_ARTICUNO_DECK_ID = 900, LEGENDARY_RONALD_DECK_ID = 901,
  BULBASAUR = 30,
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
  local memory = {
    readSymbol8 = function(_, name) return opts.symbols and opts.symbols[name] or 0 end,
    writeSymbol8 = function() end,
  }
  local ai = AI.new(
    memory,
    {
      get = function(_, addr) return (opts.turn or {})[addr] end,
      getNonTurn = function(_, addr) return (opts.nonTurn or {})[addr] end,
      set = function(_, addr, v) (opts.turn or {})[addr] = v end,
      swapTurn = function() end,
    },
    { random = function() return 5 end },
    {
      getCardIDFromDeckIndex = function(_, deckIndex) return (opts.deckIndexToCardId or {})[deckIndex] end,
      get = function(_, cardId) return (opts.cardRows or {})[cardId] or { hp = 100 } end,
    },
    {
      getPlayAreaCardAttachedEnergies = function() return opts.attachedEnergy or 0 end,
      countNumberOfEnergyCardsAttached = function() return opts.energyCardsAttached or 0 end,
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
-- Only one Pokemon in Play Area -> never scoop (no bench to switch to).
-- ---------------------------------------------------------------------
do
  local ai = newAI({ turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 1 } })
  check("count<2: never scoops", ai:_decideScoopUp(), false)
end

-- ---------------------------------------------------------------------
-- Specialized decks fail closed rather than approximating the general path.
-- ---------------------------------------------------------------------
do
  local ai = newAI({ turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2 },
    symbols = { wOpponentDeckID = C.LEGENDARY_ARTICUNO_DECK_ID } })
  local decided, err = ai:_decideScoopUp()
  check("Legendary Articuno deck fails closed", decided, nil)
  check("Legendary Articuno deck error reason", err, "untranslated_ai_scoop_up_special_deck")
end
do
  local ai = newAI({ turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2 },
    symbols = { wOpponentDeckID = C.LEGENDARY_RONALD_DECK_ID } })
  check("Legendary Ronald deck fails closed", (ai:_decideScoopUp()), nil)
end

-- ---------------------------------------------------------------------
-- A currently-usable lethal attack means no scoop, regardless of damage.
-- ---------------------------------------------------------------------
do
  local attack = { nameTextId = 1, category = 0, energy = {} }
  local ai = newAI({
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2, [C.DUELVARS_ARENA_CARD] = 1,
      [C.DUELVARS_ARENA_CARD_HP] = 5 },
    nonTurn = { [C.DUELVARS_ARENA_CARD_HP] = 10 },
    deckIndexToCardId = { [1] = C.BULBASAUR },
    cardRows = { [C.BULBASAUR] = { hp = 100 } },
    attacks = { [0] = attack, [1] = attack },
  })
  ai._estimateDamageFromPlayArea = function(_, slot, idx)
    return { usable = true, damage = 50 }
  end
  ai._checkAttackUsableForAI = function() return true end
  check("usable lethal attack available -> no scoop", ai:_decideScoopUp(), false)
end

-- ---------------------------------------------------------------------
-- No lethal attack, active is Asleep (so can't retreat), 80 raw damage on a
-- 100-HP card (80% >= 70% threshold) -> scoops with a switch target.
-- ---------------------------------------------------------------------
do
  local attack = { nameTextId = 1, category = 0, energy = {} }
  local ai = newAI({
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2, [C.DUELVARS_ARENA_CARD] = 1,
      [C.DUELVARS_ARENA_CARD_HP] = 20, [C.DUELVARS_ARENA_CARD_STATUS] = C.ASLEEP },
    nonTurn = { [C.DUELVARS_ARENA_CARD_HP] = 999 },
    deckIndexToCardId = { [1] = C.BULBASAUR },
    cardRows = { [C.BULBASAUR] = { hp = 100 } },
    attacks = { [0] = attack, [1] = attack },
  })
  ai._estimateDamageFromPlayArea = function() return { usable = true, damage = 0 } end
  ai.decideBenchPokemonToSwitchTo = function() return C.PLAY_AREA_BENCH_1, 42 end
  local decided, selection = ai:_decideScoopUp()
  check("asleep + 80% damage -> scoops", decided, true)
  check("scoop selection targets the Active slot", selection and selection.playArea, C.PLAY_AREA_ARENA)
  check("scoop selection carries the switch target", selection and selection.replacement, C.PLAY_AREA_BENCH_1)
end

-- ---------------------------------------------------------------------
-- Not asleep/paralyzed, has enough Energy to retreat normally -> no scoop.
-- ---------------------------------------------------------------------
do
  local attack = { nameTextId = 1, category = 0, energy = {} }
  local ai = newAI({
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2, [C.DUELVARS_ARENA_CARD] = 1,
      [C.DUELVARS_ARENA_CARD_HP] = 20, [C.DUELVARS_ARENA_CARD_STATUS] = C.NO_STATUS },
    nonTurn = { [C.DUELVARS_ARENA_CARD_HP] = 999 },
    deckIndexToCardId = { [1] = C.BULBASAUR },
    cardRows = { [C.BULBASAUR] = { hp = 100 } },
    attacks = { [0] = attack, [1] = attack },
    energyCardsAttached = 2,
  })
  ai._estimateDamageFromPlayArea = function() return { usable = true, damage = 0 } end
  ai.getPlayAreaCardRetreatCost = function() return 2 end
  check("can retreat normally (enough energy, no bad status) -> no scoop", ai:_decideScoopUp(), false)
end

-- ---------------------------------------------------------------------
-- Not asleep/paralyzed, NOT enough Energy to retreat, but damage is under
-- the 70% threshold (60/100 = 60%) -> still no scoop.
-- ---------------------------------------------------------------------
do
  local attack = { nameTextId = 1, category = 0, energy = {} }
  local ai = newAI({
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2, [C.DUELVARS_ARENA_CARD] = 1,
      [C.DUELVARS_ARENA_CARD_HP] = 40, [C.DUELVARS_ARENA_CARD_STATUS] = C.NO_STATUS },
    nonTurn = { [C.DUELVARS_ARENA_CARD_HP] = 999 },
    deckIndexToCardId = { [1] = C.BULBASAUR },
    cardRows = { [C.BULBASAUR] = { hp = 100 } },
    attacks = { [0] = attack, [1] = attack },
    energyCardsAttached = 0,
  })
  ai._estimateDamageFromPlayArea = function() return { usable = true, damage = 0 } end
  ai.getPlayAreaCardRetreatCost = function() return 2 end
  check("can't retreat but damage under 70% threshold -> no scoop", ai:_decideScoopUp(), false)
end

-- ---------------------------------------------------------------------
-- Integer-division edge: maxHP=90 (9 counters), rawDamage=62 ->
-- floor(62/9)=6 (<7) -> no scoop, even though 62/90 = 68.9% is close to 70%.
-- This specifically exercises the source's integer (not floating-point)
-- division, which a naive `damage/maxHP >= 0.7` reimplementation would get
-- wrong at this exact boundary (62/90 rounds differently than 6 vs 7).
-- ---------------------------------------------------------------------
do
  local attack = { nameTextId = 1, category = 0, energy = {} }
  local ai = newAI({
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2, [C.DUELVARS_ARENA_CARD] = 1,
      [C.DUELVARS_ARENA_CARD_HP] = 28, [C.DUELVARS_ARENA_CARD_STATUS] = C.NO_STATUS },
    nonTurn = { [C.DUELVARS_ARENA_CARD_HP] = 999 },
    deckIndexToCardId = { [1] = C.BULBASAUR },
    cardRows = { [C.BULBASAUR] = { hp = 90 } },
    attacks = { [0] = attack, [1] = attack },
    energyCardsAttached = 0,
  })
  ai._estimateDamageFromPlayArea = function() return { usable = true, damage = 0 } end
  ai.getPlayAreaCardRetreatCost = function() return 2 end
  check("integer-division threshold: floor(62/9)=6 stays under 7 -> no scoop",
    ai:_decideScoopUp(), false)
end
do
  local attack = { nameTextId = 1, category = 0, energy = {} }
  local ai = newAI({
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2, [C.DUELVARS_ARENA_CARD] = 1,
      [C.DUELVARS_ARENA_CARD_HP] = 27, [C.DUELVARS_ARENA_CARD_STATUS] = C.NO_STATUS },
    nonTurn = { [C.DUELVARS_ARENA_CARD_HP] = 999 },
    deckIndexToCardId = { [1] = C.BULBASAUR },
    cardRows = { [C.BULBASAUR] = { hp = 90 } },
    attacks = { [0] = attack, [1] = attack },
    energyCardsAttached = 0,
  })
  ai._estimateDamageFromPlayArea = function() return { usable = true, damage = 0 } end
  ai.getPlayAreaCardRetreatCost = function() return 2 end
  ai.decideBenchPokemonToSwitchTo = function() return C.PLAY_AREA_BENCH_1, 42 end
  check("integer-division threshold: floor(63/9)=7 reaches the scoop threshold",
    (ai:_decideScoopUp()), true)
end

if failures == 0 then
  print("all Scoop Up AI decision cases passed")
  os.exit(0)
else
  print(("%d Scoop Up AI decision case(s) failed"):format(failures))
  os.exit(1)
end
