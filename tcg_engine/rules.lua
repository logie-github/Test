-- Pokemon Trading Card Game (GBC) - Core duel rules
-- Extracted from: src/constants/duel_constants.asm, src/constants/card_data_constants.asm,
--                  src/home/duel.asm, src/engine/duel/core.asm
--
-- === HOW THIS FILE CONNECTS TO THE OTHERS ===
-- This file is mostly standalone constants/formulas (no card-specific keys to join). Where it
-- does connect: status_conditions ids match the status names applied by effect_function_analysis's
-- "applies_status" tags and by effect_commands.lua's QueueStatusCondition calls (see
-- generic_helpers.lua for exactly how that function works). damage_modifiers here is the SAME
-- weakness/resistance/PlusPower/Defender math that every attack's printed damage in
-- card_database.lua is subject to at resolution time -- it is not re-derived per card.
-- For the duel engine's actual turn-by-turn control flow (as opposed to these rule constants),
-- see duel_engine_routine_catalog.lua, which catalogs the routines in the same two source files.

local Rules = {

  deck = {
    deck_size = 60,          -- DECK_SIZE, card_data_constants.asm
    starting_hand_size = 7,  -- STARTING_HAND_SIZE, duel_constants.asm
    booster_pack_size = 10,  -- NUM_CARDS_IN_BOOSTER, booster_constants.asm (see booster_packs_data.lua for odds)
  },

  play_area = {
    max_bench_pokemon = 5,      -- MAX_BENCH_POKEMON
    max_play_area_pokemon = 6,  -- MAX_PLAY_AREA_POKEMON (1 active + 5 bench)
  },

  prizes = {
    standard_prizes = 6,     -- wNPCDuelPrizes, normal duels (PRIZES_1..PRIZES_6 constants exist)
    sudden_death_prizes = 1, -- set explicitly in core.asm when a tie triggers Sudden Death
  },

  damage_modifiers = {
    -- ApplyDamageModifiers_DamageToTarget / _DamageToSelf, home/duel.asm
    weakness_multiplier = 2,     -- damage is doubled (arithmetic shift left)
    resistance_reduction = -30,  -- flat 30 damage reduction
    plus_power_bonus = 10,       -- +10 damage per attached PlusPower
    defender_reduction = -20,    -- -20 damage per attached Defender
    damage_floor = 0,            -- negative results after modifiers clamp to 0 (underflow check)
  },

  status_conditions = {
    -- DUELVARS_ARENA_CARD_STATUS, duel_constants.asm
    -- confused/asleep/paralyzed share the low nybble (mutually exclusive);
    -- poisoned/double-poisoned use the high nybble (can combine with the above)
    confused = {
      id = 1,
      effect = "Before attacking, flip a coin. Tails: attack fails and the Pokemon "
             .. "damages itself (CheckSelfConfusionDamage / ConfusionCheckDamageText).",
    },
    asleep = {
      id = 2,
      effect = "Cannot attack or retreat while asleep (CheckIfActiveCardParalyzedOrAsleep). "
             .. "Checked at the start of the turn: flip a coin, heads cures sleep, "
             .. "tails keeps the Pokemon asleep (HandleSleepCheck).",
    },
    paralyzed = {
      id = 3,
      effect = "Cannot attack or retreat while paralyzed (CheckIfActiveCardParalyzedOrAsleep). "
             .. "Automatically cured at the end of the turn it was inflicted.",
    },
    poisoned = {
      id = 0x80,
      damage_between_turns = 10, -- PSN_DAMAGE
    },
    double_poisoned = {
      id = 0xc0,
      damage_between_turns = 20, -- DBLPSN_DAMAGE
    },
  },

  evolution = {
    rule = "A Pokemon cannot evolve the same turn it was played, and only one evolution "
         .. "per Pokemon per turn is allowed (CAN_EVOLVE_THIS_TURN flag, set once per turn "
         .. "in card-location update, cleared on evolving; CantEvolvePokemonInSameTurnItsPlacedText).",
  },

  retreat = {
    rule = "Retreating requires discarding energy cards attached to the active Pokemon equal "
         .. "to its retreat cost. Not allowed while the active Pokemon is asleep or paralyzed.",
  },

  turn_structure = {
    steps = {
      "Draw 1 card (DisplayDrawOneCardScreen)",
      "Play basic Pokemon / evolve / attach energy (1 per turn) / play Trainer cards / retreat",
      "Attack (ends the turn) or pass",
      "Between-turn status effects resolve: poison/double poison damage, sleep coin-flip check",
    },
  },

  win_conditions = {
    "Take all of your prize cards (wDuelInitialPrizes reaches 0)",
    "Opponent has no Pokemon left in play",
    "Opponent cannot draw a card from an empty deck at the start of their turn",
    "A tie leads to a 1-prize Sudden Death match (StartSuddenDeathMatchText)",
  },

}

return Rules
