-- Pokemon Trading Card Game (GBC) - Booster pack contents and odds
-- Source: src/data/booster_packs.asm
--
-- === HOW THIS FILE CONNECTS TO THE OTHERS ===
-- Every Booster Pack has 10 cards (rules.lua's Rules.deck.booster_pack_size, sourced from the
-- same NUM_CARDS_IN_BOOSTER constant). Boosters.rarity_slots is keyed by the same SET names as
-- expansions.lua's top-level keys, but UPPERCASE (e.g. expansions.lua's "Colosseum" corresponds
-- to Boosters.rarity_slots.COLOSSEUM) -- Mystery and Laboratory have no fixed Energy slot, unlike
-- Colosseum and Evolution. type_chances keys ("Grass", "Fire", ...) match card_database.lua's
-- card_type values for Pokemon cards.

local Boosters = {}

-- Fixed slot composition per booster SET (Colosseum/Evolution have basic Energy slots,
-- Mystery/Laboratory do not): { energies, commons, uncommons, rares } out of 10 total cards.
Boosters.rarity_slots = {
  ["COLOSSEUM"] = { energies = 1, commons = 5, uncommons = 3, rares = 1 },
  ["EVOLUTION"] = { energies = 1, commons = 5, uncommons = 3, rares = 1 },
  ["MYSTERY"] = { energies = 0, commons = 6, uncommons = 3, rares = 1 },
  ["LABORATORY"] = { energies = 0, commons = 6, uncommons = 3, rares = 1 },
}

-- Every specific booster pack variant a player can open (a pack is picked based on context --
-- e.g. which "pick a card type" bonus was chosen -- then draws from these weighted odds).
-- type_chances are relative weights (not necessarily summing to 100); after each of the 10
-- cards is drawn, that type\'s remaining chance is reduced by the pack\'s original average
-- weight across all 8 categories, capped so it can\'t go negative (this prevents e.g. drawing
-- 10 Fire-type cards from a single "boosted Fire" pack).
Boosters.variants = {
  ["BoosterPack_ColosseumNeutral"] = {
    booster_set = "COLOSSEUM",
    energy_source = "GenerateRandomEnergy", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 20,
      ["Fire"] = 20,
      ["Water"] = 20,
      ["Lightning"] = 20,
      ["Fighting"] = 20,
      ["Psychic"] = 20,
      ["Colorless"] = 20,
      ["Trainer"] = 20,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_ColosseumGrass"] = {
    booster_set = "COLOSSEUM",
    energy_source = "GRASS_ENERGY", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 48,
      ["Fire"] = 16,
      ["Water"] = 16,
      ["Lightning"] = 16,
      ["Fighting"] = 16,
      ["Psychic"] = 16,
      ["Colorless"] = 16,
      ["Trainer"] = 16,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_ColosseumFire"] = {
    booster_set = "COLOSSEUM",
    energy_source = "FIRE_ENERGY", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 16,
      ["Fire"] = 48,
      ["Water"] = 16,
      ["Lightning"] = 16,
      ["Fighting"] = 16,
      ["Psychic"] = 16,
      ["Colorless"] = 16,
      ["Trainer"] = 16,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_ColosseumWater"] = {
    booster_set = "COLOSSEUM",
    energy_source = "WATER_ENERGY", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 16,
      ["Fire"] = 16,
      ["Water"] = 48,
      ["Lightning"] = 16,
      ["Fighting"] = 16,
      ["Psychic"] = 16,
      ["Colorless"] = 16,
      ["Trainer"] = 16,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_ColosseumLightning"] = {
    booster_set = "COLOSSEUM",
    energy_source = "LIGHTNING_ENERGY", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 16,
      ["Fire"] = 16,
      ["Water"] = 16,
      ["Lightning"] = 48,
      ["Fighting"] = 16,
      ["Psychic"] = 16,
      ["Colorless"] = 16,
      ["Trainer"] = 16,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_ColosseumFighting"] = {
    booster_set = "COLOSSEUM",
    energy_source = "FIGHTING_ENERGY", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 16,
      ["Fire"] = 16,
      ["Water"] = 16,
      ["Lightning"] = 16,
      ["Fighting"] = 48,
      ["Psychic"] = 16,
      ["Colorless"] = 16,
      ["Trainer"] = 16,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_ColosseumTrainer"] = {
    booster_set = "COLOSSEUM",
    energy_source = "GenerateRandomEnergy", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 16,
      ["Fire"] = 16,
      ["Water"] = 16,
      ["Lightning"] = 16,
      ["Fighting"] = 16,
      ["Psychic"] = 16,
      ["Colorless"] = 16,
      ["Trainer"] = 48,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_EvolutionNeutral"] = {
    booster_set = "EVOLUTION",
    energy_source = "GenerateRandomEnergy", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 20,
      ["Fire"] = 20,
      ["Water"] = 20,
      ["Lightning"] = 20,
      ["Fighting"] = 20,
      ["Psychic"] = 20,
      ["Colorless"] = 20,
      ["Trainer"] = 20,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_EvolutionGrass"] = {
    booster_set = "EVOLUTION",
    energy_source = "GRASS_ENERGY", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 48,
      ["Fire"] = 16,
      ["Water"] = 16,
      ["Lightning"] = 16,
      ["Fighting"] = 16,
      ["Psychic"] = 16,
      ["Colorless"] = 16,
      ["Trainer"] = 16,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_EvolutionNeutralFireEnergy"] = {
    booster_set = "EVOLUTION",
    energy_source = "FIRE_ENERGY", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 20,
      ["Fire"] = 20,
      ["Water"] = 20,
      ["Lightning"] = 20,
      ["Fighting"] = 20,
      ["Psychic"] = 20,
      ["Colorless"] = 20,
      ["Trainer"] = 20,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_EvolutionWater"] = {
    booster_set = "EVOLUTION",
    energy_source = "WATER_ENERGY", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 16,
      ["Fire"] = 16,
      ["Water"] = 48,
      ["Lightning"] = 16,
      ["Fighting"] = 16,
      ["Psychic"] = 16,
      ["Colorless"] = 16,
      ["Trainer"] = 16,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_EvolutionFighting"] = {
    booster_set = "EVOLUTION",
    energy_source = "FIGHTING_ENERGY", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 16,
      ["Fire"] = 16,
      ["Water"] = 16,
      ["Lightning"] = 16,
      ["Fighting"] = 48,
      ["Psychic"] = 16,
      ["Colorless"] = 16,
      ["Trainer"] = 16,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_EvolutionPsychic"] = {
    booster_set = "EVOLUTION",
    energy_source = "PSYCHIC_ENERGY", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 16,
      ["Fire"] = 16,
      ["Water"] = 16,
      ["Lightning"] = 16,
      ["Fighting"] = 16,
      ["Psychic"] = 48,
      ["Colorless"] = 16,
      ["Trainer"] = 16,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_EvolutionTrainer"] = {
    booster_set = "EVOLUTION",
    energy_source = "GenerateRandomEnergy", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 16,
      ["Fire"] = 16,
      ["Water"] = 16,
      ["Lightning"] = 16,
      ["Fighting"] = 16,
      ["Psychic"] = 16,
      ["Colorless"] = 16,
      ["Trainer"] = 48,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_MysteryNeutral"] = {
    booster_set = "MYSTERY",
    energy_source = "NULL", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 17,
      ["Fire"] = 17,
      ["Water"] = 17,
      ["Lightning"] = 17,
      ["Fighting"] = 17,
      ["Psychic"] = 17,
      ["Colorless"] = 17,
      ["Trainer"] = 17,
      ["Energy"] = 17,
    },
  },
  ["BoosterPack_MysteryGrassColorless"] = {
    booster_set = "MYSTERY",
    energy_source = "NULL", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 48,
      ["Fire"] = 12,
      ["Water"] = 12,
      ["Lightning"] = 12,
      ["Fighting"] = 12,
      ["Psychic"] = 12,
      ["Colorless"] = 22,
      ["Trainer"] = 12,
      ["Energy"] = 12,
    },
  },
  ["BoosterPack_MysteryWaterColorless"] = {
    booster_set = "MYSTERY",
    energy_source = "NULL", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 12,
      ["Fire"] = 12,
      ["Water"] = 48,
      ["Lightning"] = 12,
      ["Fighting"] = 12,
      ["Psychic"] = 12,
      ["Colorless"] = 22,
      ["Trainer"] = 12,
      ["Energy"] = 12,
    },
  },
  ["BoosterPack_MysteryLightningColorless"] = {
    booster_set = "MYSTERY",
    energy_source = "NULL", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 12,
      ["Fire"] = 12,
      ["Water"] = 12,
      ["Lightning"] = 48,
      ["Fighting"] = 12,
      ["Psychic"] = 12,
      ["Colorless"] = 22,
      ["Trainer"] = 12,
      ["Energy"] = 12,
    },
  },
  ["BoosterPack_MysteryFightingColorless"] = {
    booster_set = "MYSTERY",
    energy_source = "NULL", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 12,
      ["Fire"] = 12,
      ["Water"] = 12,
      ["Lightning"] = 12,
      ["Fighting"] = 48,
      ["Psychic"] = 12,
      ["Colorless"] = 22,
      ["Trainer"] = 12,
      ["Energy"] = 12,
    },
  },
  ["BoosterPack_MysteryTrainerColorless"] = {
    booster_set = "MYSTERY",
    energy_source = "NULL", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 12,
      ["Fire"] = 12,
      ["Water"] = 12,
      ["Lightning"] = 12,
      ["Fighting"] = 12,
      ["Psychic"] = 12,
      ["Colorless"] = 22,
      ["Trainer"] = 48,
      ["Energy"] = 12,
    },
  },
  ["BoosterPack_LaboratoryMostlyNeutral"] = {
    booster_set = "LABORATORY",
    energy_source = "NULL", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 20,
      ["Fire"] = 20,
      ["Water"] = 20,
      ["Lightning"] = 20,
      ["Fighting"] = 16,
      ["Psychic"] = 20,
      ["Colorless"] = 20,
      ["Trainer"] = 24,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_LaboratoryGrass"] = {
    booster_set = "LABORATORY",
    energy_source = "NULL", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 48,
      ["Fire"] = 16,
      ["Water"] = 16,
      ["Lightning"] = 16,
      ["Fighting"] = 16,
      ["Psychic"] = 16,
      ["Colorless"] = 16,
      ["Trainer"] = 16,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_LaboratoryWater"] = {
    booster_set = "LABORATORY",
    energy_source = "NULL", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 16,
      ["Fire"] = 16,
      ["Water"] = 48,
      ["Lightning"] = 16,
      ["Fighting"] = 16,
      ["Psychic"] = 16,
      ["Colorless"] = 16,
      ["Trainer"] = 16,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_LaboratoryPsychic"] = {
    booster_set = "LABORATORY",
    energy_source = "NULL", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 16,
      ["Fire"] = 16,
      ["Water"] = 16,
      ["Lightning"] = 16,
      ["Fighting"] = 16,
      ["Psychic"] = 48,
      ["Colorless"] = 16,
      ["Trainer"] = 16,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_LaboratoryTrainer"] = {
    booster_set = "LABORATORY",
    energy_source = "NULL", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 16,
      ["Fire"] = 16,
      ["Water"] = 16,
      ["Lightning"] = 16,
      ["Fighting"] = 16,
      ["Psychic"] = 16,
      ["Colorless"] = 16,
      ["Trainer"] = 48,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_EnergyLightningFire"] = {
    booster_set = "COLOSSEUM",
    energy_source = "GenerateEnergyBoosterLightningFire", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 0,
      ["Fire"] = 0,
      ["Water"] = 0,
      ["Lightning"] = 0,
      ["Fighting"] = 0,
      ["Psychic"] = 0,
      ["Colorless"] = 0,
      ["Trainer"] = 0,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_EnergyWaterFighting"] = {
    booster_set = "COLOSSEUM",
    energy_source = "GenerateEnergyBoosterWaterFighting", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 0,
      ["Fire"] = 0,
      ["Water"] = 0,
      ["Lightning"] = 0,
      ["Fighting"] = 0,
      ["Psychic"] = 0,
      ["Colorless"] = 0,
      ["Trainer"] = 0,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_EnergyGrassPsychic"] = {
    booster_set = "COLOSSEUM",
    energy_source = "GenerateEnergyBoosterGrassPsychic", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 0,
      ["Fire"] = 0,
      ["Water"] = 0,
      ["Lightning"] = 0,
      ["Fighting"] = 0,
      ["Psychic"] = 0,
      ["Colorless"] = 0,
      ["Trainer"] = 0,
      ["Energy"] = 0,
    },
  },
  ["BoosterPack_RandomEnergies"] = {
    booster_set = "COLOSSEUM",
    energy_source = "GenerateRandomEnergyBooster", -- specific energy type, or a function name for random/mixed energy
    type_chances = {
      ["Grass"] = 0,
      ["Fire"] = 0,
      ["Water"] = 0,
      ["Lightning"] = 0,
      ["Fighting"] = 0,
      ["Psychic"] = 0,
      ["Colorless"] = 0,
      ["Trainer"] = 0,
      ["Energy"] = 0,
    },
  },
}

return Boosters