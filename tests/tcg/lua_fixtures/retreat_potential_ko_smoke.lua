-- Behavioral smoke test for the retreat potential-KO + one-Energy-from-hand
-- edge (see AI.lua: _estimatePotentialKO, _checkIfBenchAttackUnusable,
-- _canKnockOutNowOrWithHandEnergy).
--
-- Unlike the rest of this project's test suite, this actually LOADS and RUNS
-- the Lua module under LuaJIT/PUC Lua rather than only checking source text.
-- To keep the fixture small, `_estimateDamageFromPlayArea` -- the expensive,
-- already-covered-elsewhere damage pipeline this edge sits on top of -- is
-- monkey-patched to a scripted double per case; everything above that seam
-- (checkEnergyNeededForAttack, _lookForEnergyNeededInHand, and the new
-- combinators themselves) runs for real against a minimal hand/play-area
-- double.
--
-- Invoked by test_retreat_potential_ko_energy_edge.py via subprocess; prints
-- one line per case and exits nonzero on any mismatch or Lua error.

package.path = package.path .. ";./?.lua"

local AI = require("src.tcg.duel.AI")

-- ---------------------------------------------------------------------
-- Minimal constants. Only the names the exercised functions actually read.
-- ---------------------------------------------------------------------
local C = {
  PLAY_AREA_ARENA = 0,
  FIRST_ATTACK_OR_PKMN_POWER = 0,
  SECOND_ATTACK = 1,
  DUELVARS_ARENA_CARD = 0x10,
  DUELVARS_ARENA_CARD_HP = 0x20,
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x30,
  DUELVARS_HAND = 0x31,
  POKEMON_POWER = 99,
  IGNORE_THIS_ATTACK_F = 5,
  NUM_COLORED_TYPES = 6,
  COLORLESS = 6,
  TYPE_ENERGY = 8,
  TYPE_TRAINER = 9,
  FIRE = 0, GRASS = 1, LIGHTNING = 2, WATER = 3, FIGHTING = 4, PSYCHIC = 5,
  FIRE_ENERGY = 9001, GRASS_ENERGY = 9003, LIGHTNING_ENERGY = 9004,
  WATER_ENERGY = 9005, FIGHTING_ENERGY = 9006, PSYCHIC_ENERGY = 9007,
  DOUBLE_COLORLESS_ENERGY = 9002,
}

-- ---------------------------------------------------------------------
-- Fake duelVars: a flat address->value table. "Non-turn" reads use a
-- separate table so the defender's HP can differ from the turn-holder's own
-- values, matching the real GetTurnDuelistVariable/GetNonTurnDuelistVariable
-- split.
-- ---------------------------------------------------------------------
local function newFakeDuelVars(turn, nonTurn)
  return {
    get = function(_, addr) return turn[addr] end,
    getNonTurn = function(_, addr) return nonTurn[addr] end,
    set = function(_, addr, v) turn[addr] = v end,
  }
end

-- deckIndexToCardId: {[deckIndex]=cardId}. cardTypes: {[cardId]=type}.
local function newFakeCardData(deckIndexToCardId, cardTypes)
  return {
    getCardIDFromDeckIndex = function(_, deckIndex) return deckIndexToCardId[deckIndex] end,
    get = function(_, cardId) return { type = cardTypes[cardId] or 0 } end,
  }
end

local function newFakeCombat(attack)
  return { loadAttack = function(_, deckIndex, attackIndex) return nil, attack end }
end

-- No Energy is ever actually attached in these cases (the whole point is
-- that raw KO potential is still detected without it); a constant-zero
-- attached-energy memory is sufficient and keeps the fixture small.
local function newFakeMemory()
  local words = {}
  return {
    readSymbol8 = function(_, name) return words[name] or 0 end,
    writeSymbol8 = function(_, name, v) words[name] = v end,
    address = function() return 0, 0 end,
    read8 = function() return 0 end,
  }
end

local function newAI(opts)
  local ai = AI.new(
    newFakeMemory(),
    newFakeDuelVars(opts.turn, opts.nonTurn),
    {},
    newFakeCardData(opts.deckIndexToCardId or {}, opts.cardTypes or {}),
    { getPlayAreaCardAttachedEnergies = function() end },
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
  ai:setCombat(newFakeCombat(opts.attack))
  return ai
end

-- ---------------------------------------------------------------------
-- Test harness.
-- ---------------------------------------------------------------------
local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(("FAIL  %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
  else
    print(("ok    %s"):format(label))
  end
end

-- Case 1: Bench slot 2, attack needs one Fire Energy, none attached, but a
-- Fire Energy card sits in the AI's hand. Real damage (once computed,
-- ignoring usability) exceeds the defender's HP; the estimator itself is
-- stubbed to skip the full damage-calculation pipeline.
do
  local slot = 2
  local ai = newAI({
    turn = {
      [C.DUELVARS_ARENA_CARD + slot] = 2,   -- deckIndex 2 occupies that slot
      [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 1,
      [C.DUELVARS_HAND + 0] = 50,            -- deckIndex 50: Fire Energy in hand
    },
    nonTurn = { [C.DUELVARS_ARENA_CARD_HP] = 30 },  -- defender HP
    attack = { nameTextId = 1, category = 0, energy = { [C.FIRE] = 1 } },
    deckIndexToCardId = { [50] = C.FIRE_ENERGY },
    cardTypes = { [C.FIRE_ENERGY] = C.TYPE_ENERGY },
  })
  local need = ai:checkEnergyNeededForAttack(slot, 0)
  check("case1 checkEnergyNeededForAttack sees the deficit", need.enough, false)
  check("case1 needed energy card id resolves to Fire Energy", need.energyCardId, C.FIRE_ENERGY)

  ai._estimateDamageFromPlayArea = function(self, s, attackIndex, opts)
    check("case1 estimator called with ignoreUsability", opts and opts.ignoreUsability, true)
    return { damage = 40, usable = false }
  end

  local potentialKO, attackIndex = ai:_estimatePotentialKO(slot)
  check("case1 potential KO detected despite missing Energy", potentialKO, true)
  check("case1 selected attack index", attackIndex, 0)

  local unusable = ai:_checkIfBenchAttackUnusable(slot, attackIndex)
  check("case1 attack is currently unusable", unusable, true)

  local rescued = ai:_lookForEnergyNeededInHand(slot, attackIndex)
  check("case1 one-Energy rescue succeeds (Fire Energy in hand)", rescued, true)

  local combined, err = ai:_canKnockOutNowOrWithHandEnergy(slot)
  check("case1 combinator: potential KO + rescue = true", combined, true)
  check("case1 combinator error is nil", err, nil)
end

-- Case 2: same shape, but the needed Fire Energy is NOT in hand. The rescue
-- must fail and the combinator must report false, not true.
do
  local slot = 2
  local ai = newAI({
    turn = {
      [C.DUELVARS_ARENA_CARD + slot] = 2,
      [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 0,
    },
    nonTurn = { [C.DUELVARS_ARENA_CARD_HP] = 30 },
    attack = { nameTextId = 1, category = 0, energy = { [C.FIRE] = 1 } },
  })
  ai._estimateDamageFromPlayArea = function() return { damage = 40, usable = false } end

  local combined = ai:_canKnockOutNowOrWithHandEnergy(slot)
  check("case2 combinator: potential KO, no rescue card = false", combined, false)
end

-- Case 3: attack needs two Colorless; Double Colorless Energy is in hand.
-- LookForEnergyNeededForAttackInHand's ".two_colorless" branch must fire.
do
  local slot = 3
  local ai = newAI({
    turn = {
      [C.DUELVARS_ARENA_CARD + slot] = 3,
      [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 1,
      [C.DUELVARS_HAND + 0] = 60,             -- deckIndex 60: DCE in hand
    },
    nonTurn = { [C.DUELVARS_ARENA_CARD_HP] = 30 },
    attack = { nameTextId = 1, category = 0, energy = { [C.COLORLESS] = 2 } },
    deckIndexToCardId = { [60] = C.DOUBLE_COLORLESS_ENERGY },
    cardTypes = { [C.DOUBLE_COLORLESS_ENERGY] = C.TYPE_ENERGY },
  })
  ai._estimateDamageFromPlayArea = function() return { damage = 40, usable = false } end

  local need = ai:checkEnergyNeededForAttack(slot, 0)
  check("case3 checkEnergyNeededForAttack: 2 colorless needed", need.colorless, 2)

  local combined = ai:_canKnockOutNowOrWithHandEnergy(slot)
  check("case3 combinator: two-colorless rescue via DCE = true", combined, true)
end

-- Case 4: attack needs two Colorless; hand has ordinary Energy but no DCE.
-- Source's ".two_colorless" branch specifically requires DOUBLE_COLORLESS_
-- ENERGY -- a same-total ordinary Energy card must NOT satisfy the rescue.
do
  local slot = 3
  local ai = newAI({
    turn = {
      [C.DUELVARS_ARENA_CARD + slot] = 3,
      [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 1,
      [C.DUELVARS_HAND + 0] = 61,             -- ordinary Fire Energy, not DCE
    },
    nonTurn = { [C.DUELVARS_ARENA_CARD_HP] = 30 },
    attack = { nameTextId = 1, category = 0, energy = { [C.COLORLESS] = 2 } },
    deckIndexToCardId = { [61] = C.FIRE_ENERGY },
    cardTypes = { [C.FIRE_ENERGY] = C.TYPE_ENERGY },
  })
  ai._estimateDamageFromPlayArea = function() return { damage = 40, usable = false } end

  local combined = ai:_canKnockOutNowOrWithHandEnergy(slot)
  check("case4 combinator: two-colorless with only ordinary Energy = false", combined, false)
end

-- Case 5: no potential KO at all (damage below HP) -- the combinator must
-- short-circuit to false without ever consulting usability or the hand.
do
  local slot = 2
  local ai = newAI({
    turn = { [C.DUELVARS_ARENA_CARD + slot] = 2 },
    nonTurn = { [C.DUELVARS_ARENA_CARD_HP] = 100 },
    attack = { nameTextId = 1, category = 0, energy = {} },
  })
  ai._estimateDamageFromPlayArea = function() return { damage = 10, usable = true } end
  local usabilityChecked = false
  ai._checkIfBenchAttackUnusable = function() usabilityChecked = true; return true end

  local combined = ai:_canKnockOutNowOrWithHandEnergy(slot)
  check("case5 no potential KO short-circuits to false", combined, false)
  check("case5 usability is never consulted", usabilityChecked, false)
end

-- Case 6: potential KO AND currently usable (enough Energy already
-- attached) -- must succeed without ever touching the hand/rescue path.
do
  local slot = 2
  local ai = newAI({
    turn = { [C.DUELVARS_ARENA_CARD + slot] = 2 },
    nonTurn = { [C.DUELVARS_ARENA_CARD_HP] = 30 },
    attack = { nameTextId = 1, category = 0, energy = {} },
  })
  ai._estimateDamageFromPlayArea = function() return { damage = 40, usable = false } end
  ai._checkIfBenchAttackUnusable = function() return false end -- already usable
  local rescueCalled = false
  ai._lookForEnergyNeededInHand = function() rescueCalled = true; return false end

  local combined = ai:_canKnockOutNowOrWithHandEnergy(slot)
  check("case6 usable KO succeeds without a rescue attempt", combined, true)
  check("case6 rescue is never attempted when already usable", rescueCalled, false)
end

-- ---------------------------------------------------------------------
-- LookForEnergyNeededInHand (both-attack variant), used by
-- AIDecideBenchPokemonToSwitchTo's .check_energy_card scoring bonus.
-- ---------------------------------------------------------------------

-- Case 7: first attack's need is unsatisfiable, second attack's need (one
-- Fire Energy) IS satisfiable. The both-attack search must fall through to
-- attack 1 and leave wSelectedAttack naming it, not attack 0.
do
  local slot = 2
  local firstAttack = { nameTextId = 1, category = 0, energy = { [C.GRASS] = 1 } }   -- Grass needed, none in hand
  local secondAttack = { nameTextId = 1, category = 0, energy = { [C.FIRE] = 1 } }    -- Fire needed, in hand
  local ai = newAI({
    turn = {
      [C.DUELVARS_ARENA_CARD + slot] = 2,
      [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 1,
      [C.DUELVARS_HAND + 0] = 50,
    },
    nonTurn = {},
    attack = firstAttack, -- overwritten per-call below via loadAttack stub
    deckIndexToCardId = { [50] = C.FIRE_ENERGY },
    cardTypes = { [C.FIRE_ENERGY] = C.TYPE_ENERGY },
  })
  ai.combat.loadAttack = function(_, deckIndex, attackIndex)
    if attackIndex == 0 then return nil, firstAttack end
    return nil, secondAttack
  end

  local found = ai:_lookForAnyEnergyNeededInHand(slot)
  check("case7 both-attack search finds the second attack's rescue", found, true)
  check("case7 wSelectedAttack names the matching attack (index 1)",
    ai.memory:readSymbol8("wSelectedAttack"), 1)
end

-- Case 8: neither attack's need is satisfiable -- must fail and still leave
-- wSelectedAttack at the last attack tried (index 1), matching source's
-- unconditional write-before-check.
do
  local slot = 2
  local firstAttack = { nameTextId = 1, category = 0, energy = { [C.GRASS] = 1 } }
  local secondAttack = { nameTextId = 1, category = 0, energy = { [C.WATER] = 1 } }
  local ai = newAI({
    turn = { [C.DUELVARS_ARENA_CARD + slot] = 2, [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = 0 },
    nonTurn = {},
    attack = firstAttack,
  })
  ai.combat.loadAttack = function(_, deckIndex, attackIndex)
    if attackIndex == 0 then return nil, firstAttack end
    return nil, secondAttack
  end

  local found = ai:_lookForAnyEnergyNeededInHand(slot)
  check("case8 both-attack search fails when neither is rescuable", found, false)
  check("case8 wSelectedAttack still ends on the last attack tried",
    ai.memory:readSymbol8("wSelectedAttack"), 1)
end

if failures > 0 then
  print(("\n%d case(s) failed"):format(failures))
  os.exit(1)
end
print("all retreat + both-attack energy-lookahead cases passed")
