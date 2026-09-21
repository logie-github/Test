-- Behavioral smoke test for Scoop Up's AI decision (AIDecide_ScoopUp,
-- trainer_cards.asm), run under real LuaJIT rather than only checked as
-- source text: the general path's KO/usability short-circuit, the
-- status/retreat-cost gate, the 70%-max-HP damage threshold (computed via
-- the source's own floor(rawDamage / floor(maxHP/10)) integer division, not
-- a floating-point approximation), and the Legendary Articuno/Ronald deck-
-- specific Bench-scoop handlers (Snorlax check, no-energy-attached gate,
-- and Articuno's own Arena-card KO-danger branch).

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  PLAY_AREA_ARENA = 0, PLAY_AREA_BENCH_1 = 1, MAX_PLAY_AREA_POKEMON = 6,
  FIRST_ATTACK_OR_PKMN_POWER = 0, SECOND_ATTACK = 1,
  DUELVARS_ARENA_CARD = 0x10, DUELVARS_ARENA_CARD_HP = 0x20,
  DUELVARS_ARENA_CARD_STATUS = 0x30,
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = 0x40,
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x50, DUELVARS_HAND = 0x51,
  POKEMON_POWER = 99,
  CNF_SLP_PRZ = 0x07, PARALYZED = 0x02, ASLEEP = 0x04, NO_STATUS = 0,
  LEGENDARY_ARTICUNO_DECK_ID = 900, LEGENDARY_RONALD_DECK_ID = 901,
  BULBASAUR = 30,
  ARTICUNO_LV37 = 40, CHANSEY = 41, SNORLAX = 42, ZAPDOS_LV68 = 43, MOLTRES_LV37 = 44,
  EEVEE = 45,
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
  if opts.playerCanKO ~= nil then
    ai.checkIfDefendingPokemonCanKnockOut = function() return opts.playerCanKO end
  end
  return ai
end

-- Fills DUELVARS_ARENA_CARD+slot for slots 0..count-1 with distinct fake
-- deck indices mapped to the given card IDs (nil = Basic filler card), and
-- terminates the Play Area with 0xff at slot count (required by
-- _findCardIDInPlayArea's scan, which stops at the first 0xff).
local function playArea(turn, deckIndexToCardId, cardIds)
  for i, cardId in ipairs(cardIds) do
    local slot = i - 1
    local deckIndex = 1000 + slot
    turn[C.DUELVARS_ARENA_CARD + slot] = deckIndex
    deckIndexToCardId[deckIndex] = cardId or C.BULBASAUR
  end
  turn[C.DUELVARS_ARENA_CARD + #cardIds] = 0xff
end

-- ---------------------------------------------------------------------
-- Only one Pokemon in Play Area -> never scoop (no bench to switch to).
-- ---------------------------------------------------------------------
do
  local ai = newAI({ turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 1 } })
  check("count<2: never scoops", ai:_decideScoopUp(), false)
end

-- ---------------------------------------------------------------------
-- Legendary Articuno/Ronald: fewer than 3 Play Area Pokemon -> never scoop.
-- ---------------------------------------------------------------------
do
  local ai = newAI({ turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2 },
    symbols = { wOpponentDeckID = C.LEGENDARY_ARTICUNO_DECK_ID } })
  check("Legendary Articuno, <3 in Play Area: no scoop", ai:_decideScoopUp(), false)
end
do
  local ai = newAI({ turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2 },
    symbols = { wOpponentDeckID = C.LEGENDARY_RONALD_DECK_ID } })
  check("Legendary Ronald, <3 in Play Area: no scoop", ai:_decideScoopUp(), false)
end

-- ---------------------------------------------------------------------
-- Legendary Articuno: ArticunoLv37 on Bench, Player's Active is Snorlax ->
-- skipped (the source's own noted quirk: no Muk check here at all).
-- ---------------------------------------------------------------------
do
  local turn, deckIndexToCardId = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 3 }, {}
  playArea(turn, deckIndexToCardId, { C.BULBASAUR, C.EEVEE, C.ARTICUNO_LV37 })
  local nonTurn = { [C.DUELVARS_ARENA_CARD] = 5000 }
  deckIndexToCardId[5000] = C.SNORLAX
  local ai = newAI({ turn = turn, nonTurn = nonTurn, deckIndexToCardId = deckIndexToCardId,
    symbols = { wOpponentDeckID = C.LEGENDARY_ARTICUNO_DECK_ID } })
  check("Legendary Articuno, ArticunoLv37 on Bench, Player has Snorlax: no scoop",
    ai:_decideScoopUp(), false)
end

-- ---------------------------------------------------------------------
-- Legendary Articuno: ArticunoLv37 on Bench, Player's Active is NOT
-- Snorlax -> scoop it exactly when it has no Energy attached.
-- ---------------------------------------------------------------------
do
  local turn, deckIndexToCardId = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 3 }, {}
  playArea(turn, deckIndexToCardId, { C.BULBASAUR, C.EEVEE, C.ARTICUNO_LV37 })
  local nonTurn = { [C.DUELVARS_ARENA_CARD] = 5000 }
  deckIndexToCardId[5000] = C.EEVEE
  local ai = newAI({ turn = turn, nonTurn = nonTurn, deckIndexToCardId = deckIndexToCardId,
    symbols = { wOpponentDeckID = C.LEGENDARY_ARTICUNO_DECK_ID }, energyCardsAttached = 0 })
  local ok, selection = ai:_decideScoopUp()
  check("Legendary Articuno, ArticunoLv37 on Bench, no Energy attached: scoops", ok, true)
  check("Legendary Articuno bench scoop: targets the found slot (2)", selection.playArea, 2)
  check("Legendary Articuno bench scoop: no replacement needed", selection.replacement, nil)
end
do
  local turn, deckIndexToCardId = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 3 }, {}
  playArea(turn, deckIndexToCardId, { C.BULBASAUR, C.EEVEE, C.ARTICUNO_LV37 })
  local nonTurn = { [C.DUELVARS_ARENA_CARD] = 5000 }
  deckIndexToCardId[5000] = C.EEVEE
  local ai = newAI({ turn = turn, nonTurn = nonTurn, deckIndexToCardId = deckIndexToCardId,
    symbols = { wOpponentDeckID = C.LEGENDARY_ARTICUNO_DECK_ID }, energyCardsAttached = 1 })
  check("Legendary Articuno, ArticunoLv37 on Bench, HAS Energy attached: no scoop",
    ai:_decideScoopUp(), false)
end

-- ---------------------------------------------------------------------
-- Legendary Articuno: no ArticunoLv37 on Bench, Arena is Chansey, no
-- lethal available this turn, and the Player threatens a KO -> scoop the
-- Arena with a Bench replacement.
-- ---------------------------------------------------------------------
do
  local turn, deckIndexToCardId = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 3 }, {}
  playArea(turn, deckIndexToCardId, { C.CHANSEY, C.EEVEE, C.BULBASAUR })
  local ai = newAI({ turn = turn, nonTurn = { [C.DUELVARS_ARENA_CARD_HP] = 100 },
    deckIndexToCardId = deckIndexToCardId,
    symbols = { wOpponentDeckID = C.LEGENDARY_ARTICUNO_DECK_ID },
    attacks = { [0] = { nameTextId = 0 }, [1] = { nameTextId = 0 } }, playerCanKO = true })
  ai.decideBenchPokemonToSwitchTo = function() return 1 end
  local ok, selection = ai:_decideScoopUp()
  check("Legendary Articuno, Arena=Chansey, no lethal, Player threatens KO: scoops", ok, true)
  check("Legendary Articuno Arena scoop: targets the Arena", selection.playArea, C.PLAY_AREA_ARENA)
  check("Legendary Articuno Arena scoop: carries the switch target", selection.replacement, 1)
end
do
  local turn, deckIndexToCardId = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 3 }, {}
  playArea(turn, deckIndexToCardId, { C.CHANSEY, C.EEVEE, C.BULBASAUR })
  local ai = newAI({ turn = turn, nonTurn = { [C.DUELVARS_ARENA_CARD_HP] = 100 },
    deckIndexToCardId = deckIndexToCardId,
    symbols = { wOpponentDeckID = C.LEGENDARY_ARTICUNO_DECK_ID },
    attacks = { [0] = { nameTextId = 0 }, [1] = { nameTextId = 0 } }, playerCanKO = false })
  check("Legendary Articuno, Arena=Chansey, Player does NOT threaten a KO: no scoop",
    ai:_decideScoopUp(), false)
end
do
  -- Arena is neither ArticunoLv37 nor Chansey -> no scoop, regardless of
  -- anything else.
  local turn, deckIndexToCardId = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 3 }, {}
  playArea(turn, deckIndexToCardId, { C.EEVEE, C.EEVEE, C.BULBASAUR })
  local ai = newAI({ turn = turn, deckIndexToCardId = deckIndexToCardId,
    symbols = { wOpponentDeckID = C.LEGENDARY_ARTICUNO_DECK_ID } })
  check("Legendary Articuno, Arena is neither Articuno nor Chansey: no scoop",
    ai:_decideScoopUp(), false)
end

-- ---------------------------------------------------------------------
-- Legendary Ronald: checks ArticunoLv37, then ZapdosLv68, then MoltresLv37
-- on the Bench, in that order; no Arena-card branch at all.
-- ---------------------------------------------------------------------
do
  local turn, deckIndexToCardId = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 3 }, {}
  playArea(turn, deckIndexToCardId, { C.BULBASAUR, C.ZAPDOS_LV68, C.EEVEE })
  local ai = newAI({ turn = turn, deckIndexToCardId = deckIndexToCardId,
    symbols = { wOpponentDeckID = C.LEGENDARY_RONALD_DECK_ID }, energyCardsAttached = 0 })
  local ok, selection = ai:_decideScoopUp()
  check("Legendary Ronald, ZapdosLv68 on Bench, no Energy: scoops it", ok, true)
  check("Legendary Ronald: targets the Zapdos slot (1)", selection.playArea, 1)
end
do
  local turn, deckIndexToCardId = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 3 }, {}
  playArea(turn, deckIndexToCardId, { C.BULBASAUR, C.EEVEE, C.MOLTRES_LV37 })
  local ai = newAI({ turn = turn, deckIndexToCardId = deckIndexToCardId,
    symbols = { wOpponentDeckID = C.LEGENDARY_RONALD_DECK_ID }, energyCardsAttached = 0 })
  local ok, selection = ai:_decideScoopUp()
  check("Legendary Ronald, MoltresLv37 on Bench, no Energy: scoops it", ok, true)
  check("Legendary Ronald: targets the Moltres slot (2)", selection.playArea, 2)
end
do
  -- Zapdos AND Moltres both present -> Zapdos wins (checked first).
  local turn, deckIndexToCardId = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 3 }, {}
  playArea(turn, deckIndexToCardId, { C.BULBASAUR, C.ZAPDOS_LV68, C.MOLTRES_LV37 })
  local ai = newAI({ turn = turn, deckIndexToCardId = deckIndexToCardId,
    symbols = { wOpponentDeckID = C.LEGENDARY_RONALD_DECK_ID }, energyCardsAttached = 0 })
  local ok, selection = ai:_decideScoopUp()
  check("Legendary Ronald, both Zapdos and Moltres present: Zapdos wins", selection.playArea, 1)
end
do
  local turn, deckIndexToCardId = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 3 }, {}
  playArea(turn, deckIndexToCardId, { C.BULBASAUR, C.EEVEE, C.EEVEE })
  local ai = newAI({ turn = turn, deckIndexToCardId = deckIndexToCardId,
    symbols = { wOpponentDeckID = C.LEGENDARY_RONALD_DECK_ID } })
  check("Legendary Ronald, none of the three found: no scoop", ai:_decideScoopUp(), false)
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
