-- Behavioral smoke test for Super Potion's AI decision arithmetic
-- (AIDecide_SuperPotion_Phase08/Phase11, trainer_cards.asm) and its
-- discard-energy-after simulation (CheckEnergyNeededForAttackAfterDiscard,
-- core.asm), run under real LuaJIT rather than only checked as source text.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  PLAY_AREA_ARENA = 0, PLAY_AREA_BENCH_1 = 1, MAX_PLAY_AREA_POKEMON = 3,
  FIRST_ATTACK_OR_PKMN_POWER = 0, SECOND_ATTACK = 1,
  DUELVARS_ARENA_CARD = 0x10, DUELVARS_ARENA_CARD_HP = 0x20,
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = 0x40,
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x30, DUELVARS_HAND = 0x31,
  POKEMON_POWER = 99, IGNORE_THIS_ATTACK_F = 5, HIGH_RECOIL_F = 6,
  BOOST_IF_TAKEN_DAMAGE_F = 7,
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

-- Real memory: wAttachedEnergies is a contiguous block (indices 0..6), plus
-- named scratch symbols, sufficient to exercise the discard-simulation math
-- for real (not stubbed), since that arithmetic is exactly what a
-- source-text search cannot verify.
local function newFakeMemory()
  local words = {}
  local attached = {}
  local ADDR = {}
  for c = 0, C.NUM_COLORED_TYPES - 1 do ADDR[c] = c end
  local BASE = 1000
  return {
    readSymbol8 = function(_, name) return words[name] or 0 end,
    writeSymbol8 = function(_, name, v) words[name] = v end,
    address = function(_, name)
      if name == "wAttachedEnergies" then return BASE, 0 end
      return 0, 0
    end,
    read8 = function(_, kind, addr, bank)
      return attached[addr - BASE] or 0
    end,
    write8 = function(_, kind, addr, value, bank)
      attached[addr - BASE] = value
    end,
    _setAttached = function(_, color, value) attached[color] = value end,
  }
end

local function newFakeDuelVars(turn, nonTurn)
  return {
    get = function(_, addr) return turn[addr] end,
    getNonTurn = function(_, addr) return nonTurn[addr] end,
    set = function(_, addr, v) turn[addr] = v end,
    swapTurn = function() end,
  }
end

local function newAI(opts)
  local memory = newFakeMemory()
  local ai = AI.new(
    memory,
    newFakeDuelVars(opts.turn or {}, opts.nonTurn or {}),
    { random = function() return opts.random or 5 end },
    {
      getCardIDFromDeckIndex = function(_, deckIndex) return (opts.deckIndexToCardId or {})[deckIndex] end,
      get = function(_, cardId) return { type = (opts.cardTypes or {})[cardId] or 0 } end,
    },
    {
      getPlayAreaCardAttachedEnergies = function(_, slot)
        -- NUM_TYPES (6 colored + 1 Colorless) = 7, matching the real
        -- DuelOps:getPlayAreaCardAttachedEnergies total-sum range. This fake
        -- does not reset wAttachedEnergies to zero first (the test cases
        -- pre-seed it directly via _setAttached and never call this more
        -- than once per case with changing state), unlike the real routine.
        local total = 0
        for c = 0, C.NUM_COLORED_TYPES do total = total + memory:read8("wram", 1000 + c, 0) end
        memory:writeSymbol8("wTotalAttachedEnergies", total)
        return total
      end,
      createArenaOrBenchEnergyCardList = function(_, slot)
        return opts.energyCount or 0
      end,
      countPrizes = function() return opts.playerPrizes or 2 end,
    },
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
  ai:setCombat({
    loadAttack = function(_, deckIndex, attackIndex) return nil, (opts.attacks or {})[attackIndex] end,
    status = { handleEnergyBurn = function() end },
  })
  ai._memoryHandle = memory
  return ai, memory
end

-- ---------------------------------------------------------------------
-- _checkEnergyNeededForAttackAfterDiscard: discarding a colored Energy
-- correctly reduces just that color's attached count.
-- ---------------------------------------------------------------------
do
  local attack = { nameTextId = 1, category = 0, energy = { [C.FIRE] = 2 } }
  local ai, mem = newAI({
    turn = { [C.DUELVARS_ARENA_CARD] = 5 },
    attacks = { [0] = attack },
    deckIndexToCardId = { [7] = C.FIRE_ENERGY },
  })
  mem:_setAttached(C.FIRE, 2)
  ai._pickEnergyCardToDiscard = function() return 7 end

  local before = ai:checkEnergyNeededForAttack(C.PLAY_AREA_ARENA, 0)
  check("super-potion: 2 Fire attached satisfies a 2-Fire attack now", before.enough, true)

  local after = ai:_checkEnergyNeededForAttackAfterDiscard(C.PLAY_AREA_ARENA, 0)
  check("super-potion: discarding 1 of 2 Fire makes it insufficient after", after.enough, false)
  check("super-potion: after-discard reports the correct colored deficit", after.colored, 1)
end

-- ---------------------------------------------------------------------
-- Discarding Double Colorless Energy removes exactly 2 from Colorless.
-- ---------------------------------------------------------------------
do
  local attack = { nameTextId = 1, category = 0, energy = { [C.COLORLESS] = 2 } }
  local ai, mem = newAI({
    turn = { [C.DUELVARS_ARENA_CARD] = 5 },
    attacks = { [0] = attack },
    deckIndexToCardId = { [8] = C.DOUBLE_COLORLESS_ENERGY },
  })
  mem:_setAttached(C.COLORLESS, 2)
  ai._pickEnergyCardToDiscard = function() return 8 end

  local before = ai:checkEnergyNeededForAttack(C.PLAY_AREA_ARENA, 0)
  check("super-potion: 2 Colorless (as 1 DCE) satisfies a 2-Colorless attack", before.enough, true)
  local after = ai:_checkEnergyNeededForAttackAfterDiscard(C.PLAY_AREA_ARENA, 0)
  check("super-potion: discarding the DCE removes both Colorless units", after.enough, false)
  check("super-potion: after-discard colorless deficit is exactly 2", after.colorless, 2)
end

-- ---------------------------------------------------------------------
-- Discarding an unrelated Energy does not affect an attack that does not
-- need that color at all.
-- ---------------------------------------------------------------------
do
  local attack = { nameTextId = 1, category = 0, energy = { [C.WATER] = 1 } }
  local ai, mem = newAI({
    turn = { [C.DUELVARS_ARENA_CARD] = 5 },
    attacks = { [0] = attack },
    deckIndexToCardId = { [9] = C.FIRE_ENERGY },
  })
  mem:_setAttached(C.WATER, 1)
  mem:_setAttached(C.FIRE, 1)
  ai._pickEnergyCardToDiscard = function() return 9 end

  local after = ai:_checkEnergyNeededForAttackAfterDiscard(C.PLAY_AREA_ARENA, 0)
  check("super-potion: discarding an unrelated color leaves the Water attack usable", after.enough, true)
end

-- ---------------------------------------------------------------------
-- _discardingMakesAttacksUnusable: end-to-end over both attacks.
-- ---------------------------------------------------------------------
do
  local firstAttack = { nameTextId = 1, category = 0, energy = { [C.FIRE] = 2 } }
  local secondAttack = { nameTextId = 1, category = 0, energy = { [C.WATER] = 1 } }
  local ai, mem = newAI({
    turn = { [C.DUELVARS_ARENA_CARD] = 5 },
    attacks = { [0] = firstAttack, [1] = secondAttack },
    deckIndexToCardId = { [7] = C.FIRE_ENERGY },
  })
  mem:_setAttached(C.FIRE, 2)
  mem:_setAttached(C.WATER, 1)
  ai._pickEnergyCardToDiscard = function() return 7 end

  local becomesUnusable = ai:_discardingMakesAttacksUnusable(C.PLAY_AREA_ARENA)
  check("super-potion: discard that breaks the first attack is flagged", becomesUnusable, true)
end

do
  -- Same shape, but the discarded card is not actually needed by either
  -- currently-usable attack -- must NOT be flagged.
  local firstAttack = { nameTextId = 1, category = 0, energy = { [C.FIRE] = 1 } }
  local secondAttack = { nameTextId = 1, category = 0, energy = { [C.WATER] = 1 } }
  local ai, mem = newAI({
    turn = { [C.DUELVARS_ARENA_CARD] = 5 },
    attacks = { [0] = firstAttack, [1] = secondAttack },
    deckIndexToCardId = { [7] = C.FIRE_ENERGY },
  })
  mem:_setAttached(C.FIRE, 2) -- one spare Fire beyond the 1 needed
  mem:_setAttached(C.WATER, 1)
  ai._pickEnergyCardToDiscard = function() return 7 end

  local becomesUnusable = ai:_discardingMakesAttacksUnusable(C.PLAY_AREA_ARENA)
  check("super-potion: discarding a spare Energy does not break either attack", becomesUnusable, false)
end

-- ---------------------------------------------------------------------
-- Phase08 threshold: heals only when healing actually prevents the KO.
-- ---------------------------------------------------------------------
do
  -- Active at 20 HP, defender's exact-KO check already confirms 20 damage
  -- incoming (koDamage == current HP, by construction of that check), one
  -- Fire Energy attached (satisfies the "has energy" precondition), no
  -- usable safe attack (forces the emergency-heal branch to matter), and
  -- current damage taken is 30 (so heal = min(40,30) = 30).
  local ai, mem = newAI({
    turn = { [C.DUELVARS_ARENA_CARD] = 5, [C.DUELVARS_ARENA_CARD_HP] = 20 },
    energyCount = 1,
  })
  -- getPlayAreaCardAttachedEnergies (the "has energy to discard" precondition
  -- check) and createArenaOrBenchEnergyCardList (energyCount, used by
  -- _pickEnergyCardToDiscard elsewhere) are separate fakes; the Active card
  -- needs at least one attached Energy byte set for the former to see it.
  mem:_setAttached(C.FIRE, 1)
  ai.decideWhetherToRetreat = function() return false end
  ai._checkIfAttackIsHighRecoilForAI = function() return false end -- no safe attack
  ai.checkIfDefendingPokemonCanKnockOut = function() return true, 20 end
  ai._damageAt = function() return 30 end
  ai._pickEnergyCardToDiscard = function() return 42 end

  local decided, selection = ai:_decideSuperPotion(8)
  check("super-potion phase08: heals when 20hp+30heal survives a 20-damage KO", decided, true)
  check("super-potion phase08: targets the Active slot", selection and selection.playArea, C.PLAY_AREA_ARENA)
  check("super-potion phase08: relays the chosen discard", selection and selection.discardEnergy, 42)
end

do
  -- Same shape, but current damage taken is only 5 (heal=5): 20+5=25 vs
  -- koDamage=20 -- 25 > 20 survives, so this SHOULD still fire; flip to a
  -- case where healing does NOT reach survival: koDamage is bumped to 60
  -- (still <= current HP is impossible by construction, so instead lower
  -- current damage to 0, i.e. already full HP -- heal becomes 0, which must
  -- bail per the explicit `heal == 0` source check).
  local ai = newAI({
    turn = { [C.DUELVARS_ARENA_CARD] = 5, [C.DUELVARS_ARENA_CARD_HP] = 20 },
    energyCount = 1,
  })
  ai.decideWhetherToRetreat = function() return false end
  ai._checkIfAttackIsHighRecoilForAI = function() return false end
  ai.checkIfDefendingPokemonCanKnockOut = function() return true, 20 end
  ai._damageAt = function() return 0 end -- already at full HP: heal = 0
  ai._pickEnergyCardToDiscard = function() return 42 end

  local decided = ai:_decideSuperPotion(8)
  check("super-potion phase08: bails when there is nothing to heal (heal==0)", decided, false)
end

do
  -- No Energy attached at all -- must bail before ever reaching the KO
  -- check, per the source's own early .CheckIfHasEnergies gate.
  local ai = newAI({
    turn = { [C.DUELVARS_ARENA_CARD] = 5, [C.DUELVARS_ARENA_CARD_HP] = 20 },
    energyCount = 0,
  })
  ai.decideWhetherToRetreat = function() return false end
  ai._checkIfAttackIsHighRecoilForAI = function() return false end
  local koChecked = false
  ai.checkIfDefendingPokemonCanKnockOut = function() koChecked = true; return true, 20 end

  local decided = ai:_decideSuperPotion(8)
  check("super-potion phase08: bails with no Energy attached", decided, false)
  check("super-potion phase08: never reaches the KO check with no Energy", koChecked, false)
end

do
  -- A safe usable attack is available -- per the source's inverted-name
  -- helper, this SKIPS the whole KO-avoidance branch (bails false)
  -- regardless of HP/damage.
  local ai = newAI({
    turn = { [C.DUELVARS_ARENA_CARD] = 5, [C.DUELVARS_ARENA_CARD_HP] = 1 },
    energyCount = 3,
  })
  ai.decideWhetherToRetreat = function() return false end
  ai._checkIfAttackIsHighRecoilForAI = function() return true end -- has a safe attack
  local koChecked = false
  ai.checkIfDefendingPokemonCanKnockOut = function() koChecked = true; return true, 1 end

  local decided = ai:_decideSuperPotion(8)
  check("super-potion phase08: a safe usable attack skips this branch entirely", decided, false)
  check("super-potion phase08: KO check never runs when a safe attack exists", koChecked, false)
end

-- ---------------------------------------------------------------------
-- Phase11: source unconditionally BAILS (the whole call returns false) when
-- healing the Active card would have prevented an otherwise-lethal hit --
-- Phase08 owns that scenario, not Phase11's general opportunistic scan.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    turn = { [C.DUELVARS_ARENA_CARD] = 5, [C.DUELVARS_ARENA_CARD_HP] = 20,
              [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2 },
  })
  ai.checkIfDefendingPokemonCanKnockOut = function() return true, 20 end
  ai._damageAt = function() return 30 end -- heal=30; 20+30=50>20 survives -> prevents the KO
  local anySlotChecked = false
  ai.duelOps.getPlayAreaCardAttachedEnergies = function() anySlotChecked = true; return 0 end

  local decided = ai:_decideSuperPotion(11)
  check("super-potion phase11: bails entirely when healing would prevent the KO", decided, false)
  check("super-potion phase11: never reaches the general scan in that case", anySlotChecked, false)
end

-- Healing would NOT have prevented the KO (dies regardless) and the
-- defending player is not on their last prize -> skip Active, start at
-- Bench.
do
  local ai = newAI({
    turn = { [C.DUELVARS_ARENA_CARD] = 5, [C.DUELVARS_ARENA_CARD_HP] = 20,
              [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2 },
    playerPrizes = 2,
  })
  ai.checkIfDefendingPokemonCanKnockOut = function() return true, 100 end -- dies regardless of heal
  ai._damageAt = function(_, slot) return slot == C.PLAY_AREA_ARENA and 30 or 0 end
  local activeChecked, benchChecked = false, false
  ai.duelOps.getPlayAreaCardAttachedEnergies = function(_, slot)
    if slot == C.PLAY_AREA_ARENA then activeChecked = true end
    if slot == C.PLAY_AREA_BENCH_1 then benchChecked = true end
    return 0
  end

  ai:_decideSuperPotion(11)
  check("super-potion phase11: skips Active when it dies regardless (not last prize)",
    activeChecked, false)
  check("super-potion phase11: starts the general scan at Bench in that case",
    benchChecked, true)
end

-- Same "dies regardless" case, but the defending player IS on their last
-- prize -> source still starts from Active.
do
  local ai = newAI({
    turn = { [C.DUELVARS_ARENA_CARD] = 5, [C.DUELVARS_ARENA_CARD_HP] = 20,
              [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2 },
    playerPrizes = 1,
  })
  ai.checkIfDefendingPokemonCanKnockOut = function() return true, 100 end
  ai._damageAt = function(_, slot) return slot == C.PLAY_AREA_ARENA and 30 or 0 end
  local activeChecked = false
  ai.duelOps.getPlayAreaCardAttachedEnergies = function(_, slot)
    if slot == C.PLAY_AREA_ARENA then activeChecked = true end
    return 0
  end

  ai:_decideSuperPotion(11)
  check("super-potion phase11: still starts from Active when player is on last prize",
    activeChecked, true)
end

-- No KO is possible at all -> jr nc, .start_from_active: starts from Active
-- directly, with no heal-prevents-KO check performed at all.
do
  local ai = newAI({
    turn = { [C.DUELVARS_ARENA_CARD] = 5, [C.DUELVARS_ARENA_CARD_HP] = 20,
              [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2 },
  })
  ai.checkIfDefendingPokemonCanKnockOut = function() return false, 0 end
  local damageAtCalled = false
  ai._damageAt = function() damageAtCalled = true; return 0 end
  local activeChecked = false
  ai.duelOps.getPlayAreaCardAttachedEnergies = function(_, slot)
    if slot == C.PLAY_AREA_ARENA then activeChecked = true end
    return 0
  end

  ai:_decideSuperPotion(11)
  check("super-potion phase11: no KO at all starts straight from Active", activeChecked, true)
  check("super-potion phase11: no KO at all skips the heal-prevents-KO check", damageAtCalled, false)
end

if failures > 0 then
  print(("\n%d case(s) failed"):format(failures))
  os.exit(1)
end
print("all Super Potion + Phase11 start-slot cases passed")
