-- Pokemon Trading Card Game (GBC) - Effect command dispatch tables
-- Source: src/engine/duel/effect_commands.asm
--
-- === HOW THIS FILE CONNECTS TO THE OTHERS ===
-- Keys here (e.g. "EkansSpitPoisonEffectCommands") are the SAME as card_database.lua's per-attack
-- and per-Trainer/Energy-card "effect_fn" field -- look a card's effect up here to get its exact
-- ordered list of hooks and which named function handles each hook.
-- Each hook's ["function"] value (e.g. "Paralysis50PercentEffect") is in turn a key into
-- effect_function_analysis.lua's EffectAnalysis.functions table (100% of the 632 function
-- references here resolve there, verified) -- that file has the raw Z80 source for every one of
-- them plus heuristic tags (coin-flip odds, status effects applied) where detected. A handful of
-- the most-reused ones (Paralysis50PercentEffect, PoisonEffect, etc.) also get a hand-written
-- plain-English description in generic_helpers.lua.
-- This table also lets you see which cards share an IDENTICAL underlying function (see
-- shared_functions below) vs. which have a fully bespoke one, without reading the function bodies.

local EffectCommands = {}

-- hook_type -> human description of when/how it runs
EffectCommands.hook_types = {
  ["EFFECTCMDTYPE_INITIAL_EFFECT_1"] = "Runs immediately when the attack/Trainer card is used, before anything else (bypassed by Smokescreen/Sand Attack evasion effects).",
  ["EFFECTCMDTYPE_INITIAL_EFFECT_2"] = "Runs immediately when the attack/Pokemon Power/Trainer card is used (not bypassed by evasion effects).",
  ["EFFECTCMDTYPE_DISCARD_ENERGY"] = "Discards attached Energy card(s) as a cost/side-effect of the attack or Trainer card.",
  ["EFFECTCMDTYPE_REQUIRE_SELECTION"] = "Prompts the player (or AI) to pick a card/target, e.g. from the Play Area or a card list.",
  ["EFFECTCMDTYPE_BEFORE_DAMAGE"] = "The attack's main effect, run before damage is dealt (or the main effect for a Trainer card/Pokemon Power).",
  ["EFFECTCMDTYPE_AFTER_DAMAGE"] = "Runs after damage has been dealt.",
  ["EFFECTCMDTYPE_AI_SWITCH_DEFENDING_PKMN"] = "AI-only logic for attacks that may force the opponent's Pokemon to switch out.",
  ["EFFECTCMDTYPE_PKMN_POWER_TRIGGER"] = "Pokemon Power effects that trigger the instant the Pokemon card is played.",
  ["EFFECTCMDTYPE_AI"] = "AI-only scoring logic used to help the AI decide whether/how to use this effect.",
  ["EFFECTCMDTYPE_AI_SELECTION"] = "AI-only logic for picking a card/target when EFFECTCMDTYPE_REQUIRE_SELECTION applies.",
}

-- effect_fn label (matches card_database.lua's "effect_fn" fields) -> ordered hook dispatch list
EffectCommands.dispatch = {
  ["EkansSpitPoisonEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SpitPoison_Poison50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "SpitPoison_AIEffect" },
  },
  ["EkansWrapEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["ArbokTerrorStrikeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "TerrorStrike_SwitchDefendingPokemon" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "TerrorStrike_50PercentSelectSwitchPokemon" },
    { hook = "EFFECTCMDTYPE_AI_SWITCH_DEFENDING_PKMN", ["function"] = "TerrorStrike_50PercentSelectSwitchPokemon" },
  },
  ["ArbokPoisonFangEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PoisonEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "PoisonFang_AIEffect" },
  },
  ["WeepinbellPoisonPowderEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Poison50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "WeepinbellPoisonPowder_AIEffect" },
  },
  ["VictreebelLureEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "VictreebelLure_AssertPokemonInBench" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "VictreebelLure_SwitchDefendingPokemon" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "VictreebelLure_SelectSwitchPokemon" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "VictreebelLure_GetBenchPokemonWithLowestHP" },
  },
  ["VictreebelAcidEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "AcidEffect" },
  },
  ["PinsirIronGripEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["CaterpieStringShotEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["GloomPoisonPowderEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PoisonEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "GloomPoisonPowder_AIEffect" },
  },
  ["GloomFoulOdorEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "FoulOdorEffect" },
  },
  ["KakunaStiffenEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "KakunaStiffenEffect" },
  },
  ["KakunaPoisonPowderEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Poison50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "KakunaPoisonPowder_AIEffect" },
  },
  ["GolbatLeechLifeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "GolbatLeechLifeEffect" },
  },
  ["VenonatStunSporeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["VenonatLeechLifeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "VenonatLeechLifeEffect" },
  },
  ["ScytherSwordsDanceEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SwordsDanceEffect" },
  },
  ["ZubatSupersonicEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ZubatSupersonicEffect" },
  },
  ["ZubatLeechLifeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "ZubatLeechLifeEffect" },
  },
  ["BeedrillTwineedleEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Twineedle_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "Twineedle_AIEffect" },
  },
  ["BeedrillPoisonStingEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Poison50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "BeedrillPoisonSting_AIEffect" },
  },
  ["ExeggcuteHypnosisEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SleepEffect" },
  },
  ["ExeggcuteLeechSeedEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "ExeggcuteLeechSeedEffect" },
  },
  ["KoffingFoulGasEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "FoulGas_PoisonOrConfusionEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "FoulGas_AIEffect" },
  },
  ["MetapodStiffenEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "MetapodStiffenEffect" },
  },
  ["MetapodStunSporeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["OddishStunSporeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["OddishSproutEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Sprout_CheckDeckAndPlayArea" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "Sprout_PutInPlayAreaEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "Sprout_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "Sprout_AISelectEffect" },
  },
  ["ExeggutorTeleportEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Teleport_CheckBench" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "Teleport_SwitchEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "Teleport_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "Teleport_AISelectEffect" },
  },
  ["ExeggutorBigEggsplosionEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "BigEggsplosion_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "BigEggsplosion_AIEffect" },
  },
  ["NidokingThrashEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Thrash_ModifierEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "Thrash_RecoilEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "Thrash_AIEffect" },
  },
  ["NidokingToxicEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Toxic_DoublePoisonEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "Toxic_AIEffect" },
  },
  ["NidoqueenBoyfriendsEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "BoyfriendsEffect" },
  },
  ["NidoranFFurySwipesEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "NidoranFFurySwipes_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "NidoranFFurySwipes_AIEffect" },
  },
  ["NidoranFCallForFamilyEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "NidoranFCallForFamily_CheckDeckAndPlayArea" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "NidoranFCallForFamily_PutInPlayAreaEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "NidoranFCallForFamily_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "NidoranFCallForFamily_AISelectEffect" },
  },
  ["NidoranMHornHazardEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "HornHazard_NoDamage50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "HornHazard_AIEffect" },
  },
  ["NidorinaSupersonicEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "NidorinaSupersonicEffect" },
  },
  ["NidorinaDoubleKickEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "NidorinaDoubleKick_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "NidorinaDoubleKick_AIEffect" },
  },
  ["NidorinoDoubleKickEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "NidorinoDoubleKick_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "NidorinoDoubleKick_AIEffect" },
  },
  ["ButterfreeWhirlwindEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "ButterfreeWhirlwind_SwitchEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "ButterfreeWhirlwind_CheckBench" },
    { hook = "EFFECTCMDTYPE_AI_SWITCH_DEFENDING_PKMN", ["function"] = "ButterfreeWhirlwind_CheckBench" },
  },
  ["ButterfreeMegaDrainEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "ButterfreeMegaDrainEffect" },
  },
  ["ParasSporeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SleepEffect" },
  },
  ["ParasectSporeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SleepEffect" },
  },
  ["WeedlePoisonStingEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Poison50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "WeedlePoisonSting_AIEffect" },
  },
  ["IvysaurPoisonPowderEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PoisonEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "IvysaurPoisonPowder_AIEffect" },
  },
  ["BulbasaurLeechSeedEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "BulbasaurLeechSeedEffect" },
  },
  ["VenusaurEnergyTransEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "EnergyTrans_CheckPlayArea" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "EnergyTrans_TransferEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "EnergyTrans_AIEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "EnergyTrans_PrintProcedure" },
  },
  ["GrimerNastyGooEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["GrimerMinimizeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "GrimerMinimizeEffect" },
  },
  ["MukToxicGasEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "ToxicGasEffect" },
  },
  ["MukSludgeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Poison50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "Sludge_AIEffect" },
  },
  ["BellsproutCallForFamilyEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "BellsproutCallForFamily_CheckDeckAndPlayArea" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "BellsproutCallForFamily_PutInPlayAreaEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "BellsproutCallForFamily_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "BellsproutCallForFamily_AISelectEffect" },
  },
  ["WeezingSmogEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Poison50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "WeezingSmog_AIEffect" },
  },
  ["WeezingSelfdestructEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "WeezingSelfdestructEffect" },
  },
  ["VenomothShiftEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "Shift_OncePerTurnCheck" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Shift_ChangeColorEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "Shift_PlayerSelectEffect" },
  },
  ["VenomothVenomPowderEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "VenomPowder_PoisonConfusion50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "VenomPowder_AIEffect" },
  },
  ["TangelaBindEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["TangelaPoisonPowderEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PoisonEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "TangelaPoisonPowder_AIEffect" },
  },
  ["VileplumeHealEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "Heal_OncePerTurnCheck" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Heal_RemoveDamageEffect" },
  },
  ["VileplumePetalDanceEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PetalDance_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "PetalDance_AIEffect" },
  },
  ["TangelaStunSporeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["TangelaPoisonWhipEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PoisonEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "PoisonWhip_AIEffect" },
  },
  ["VenusaurSolarPowerEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "SolarPower_CheckUse" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SolarPower_RemoveStatusEffect" },
  },
  ["VenusaurMegaDrainEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "VenusaurMegaDrainEffect" },
  },
  ["OmastarWaterGunEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "OmastarWaterGunEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "OmastarWaterGunEffect" },
  },
  ["OmastarSpikeCannonEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "OmastarSpikeCannon_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "OmastarSpikeCannon_AIEffect" },
  },
  ["OmanyteClairvoyanceEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "ClairvoyanceEffect" },
  },
  ["OmanyteWaterGunEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "OmanyteWaterGunEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "OmanyteWaterGunEffect" },
  },
  ["WartortleWithdrawEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "WartortleWithdrawEffect" },
  },
  ["BlastoiseRainDanceEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "RainDanceEffect" },
  },
  ["BlastoiseHydroPumpEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "HydroPumpEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "HydroPumpEffect" },
  },
  ["GyaradosBubblebeamEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["KinglerFlailEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "KinglerFlail_HPCheck" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "KinglerFlail_AIEffect" },
  },
  ["KrabbyCallForFamilyEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "KrabbyCallForFamily_CheckDeckAndPlayArea" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "KrabbyCallForFamily_PutInPlayAreaEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "KrabbyCallForFamily_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "KrabbyCallForFamily_AISelectEffect" },
  },
  ["MagikarpFlailEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "MagikarpFlail_HPCheck" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "MagikarpFlail_AIEffect" },
  },
  ["PsyduckHeadacheEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "HeadacheEffect" },
  },
  ["PsyduckFurySwipesEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PsyduckFurySwipes_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "PsyduckFurySwipes_AIEffect" },
  },
  ["GolduckPsyshockEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["GolduckHyperBeamEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "GolduckHyperBeam_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "GolduckHyperBeam_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "GolduckHyperBeam_AISelectEffect" },
  },
  ["SeadraWaterGunEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SeadraWaterGunEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "SeadraWaterGunEffect" },
  },
  ["SeadraAgilityEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SeadraAgilityEffect" },
  },
  ["ShellderSupersonicEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ShellderSupersonicEffect" },
  },
  ["ShellderHideInShellEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "HideInShellEffect" },
  },
  ["VaporeonQuickAttackEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "VaporeonQuickAttack_DamageBoostEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "VaporeonQuickAttack_AIEffect" },
  },
  ["VaporeonWaterGunEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "VaporeonWaterGunEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "VaporeonWaterGunEffect" },
  },
  ["DewgongIceBeamEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["StarmieRecoverEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "StarmieRecover_CheckEnergyHP" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "StarmieRecover_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "StarmieRecover_HealEffect" },
    { hook = "EFFECTCMDTYPE_DISCARD_ENERGY", ["function"] = "StarmieRecover_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "StarmieRecover_AISelectEffect" },
  },
  ["StarmieStarFreezeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["SquirtleBubbleEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["SquirtleWithdrawEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SquirtleWithdrawEffect" },
  },
  ["HorseaSmokescreenEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "HorseaSmokescreenEffect" },
  },
  ["TentacruelSupersonicEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "TentacruelSupersonicEffect" },
  },
  ["TentacruelJellyfishStingEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PoisonEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "JellyfishSting_AIEffect" },
  },
  ["PoliwhirlAmnesiaEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "PoliwhirlAmnesia_CheckAttacks" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "PoliwhirlAmnesia_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PoliwhirlAmnesia_DisableEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "PoliwhirlAmnesia_AISelectEffect" },
  },
  ["PoliwhirlDoubleslapEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PoliwhirlDoubleslap_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "PoliwhirlDoubleslap_AIEffect" },
  },
  ["PoliwrathWaterGunEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PoliwrathWaterGunEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "PoliwrathWaterGunEffect" },
  },
  ["PoliwrathWhirlpoolEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "Whirlpool_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "Whirlpool_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "Whirlpool_AISelectEffect" },
  },
  ["PoliwagWaterGunEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PoliwagWaterGunEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "PoliwagWaterGunEffect" },
  },
  ["CloysterClampEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ClampEffect" },
  },
  ["CloysterSpikeCannonEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "CloysterSpikeCannon_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "CloysterSpikeCannon_AIEffect" },
  },
  ["ArticunoFreezeDryEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["ArticunoBlizzardEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Blizzard_BenchDamage50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "Blizzard_BenchDamageEffect" },
  },
  ["TentacoolCowardiceEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "Cowardice_CheckUseAndBench" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Cowardice_ReturnToHandEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "Cowardice_PlayerSelectEffect" },
  },
  ["LaprasWaterGunEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "LaprasWaterGunEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "LaprasWaterGunEffect" },
  },
  ["LaprasConfuseRayEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Confusion50PercentEffect" },
  },
  ["ArticunoQuickfreezeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Quickfreeze_InitialEffect" },
    { hook = "EFFECTCMDTYPE_PKMN_POWER_TRIGGER", ["function"] = "Quickfreeze_Paralysis50PercentEffect" },
  },
  ["ArticunoIceBreathEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "IceBreath_ZeroDamage" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "IceBreath_RandomPokemonDamageEffect" },
  },
  ["VaporeonFocusEnergyEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "FocusEnergyEffect" },
  },
  ["ArcanineFlamethrowerEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "ArcanineFlamethrower_CheckEnergy" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "ArcanineFlamethrower_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_DISCARD_ENERGY", ["function"] = "ArcanineFlamethrower_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "ArcanineFlamethrower_AISelectEffect" },
  },
  ["ArcanineTakeDownEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "TakeDownEffect" },
  },
  ["ArcanineQuickAttackEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ArcanineQuickAttack_DamageBoostEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "ArcanineQuickAttack_AIEffect" },
  },
  ["ArcanineFlamesOfRageEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "FlamesOfRage_CheckEnergy" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "FlamesOfRage_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "FlamesOfRage_DamageBoostEffect" },
    { hook = "EFFECTCMDTYPE_DISCARD_ENERGY", ["function"] = "FlamesOfRage_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "FlamesOfRage_AISelectEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "FlamesOfRage_AIEffect" },
  },
  ["RapidashStompEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "RapidashStomp_DamageBoostEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "RapidashStomp_AIEffect" },
  },
  ["RapidashAgilityEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "RapidashAgilityEffect" },
  },
  ["NinetalesLureEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "NinetalesLure_CheckBench" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "NinetalesLure_SwitchEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "NinetalesLure_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "NinetalesLure_AISelectEffect" },
  },
  ["NinetalesFireBlastEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "FireBlast_CheckEnergy" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "FireBlast_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_DISCARD_ENERGY", ["function"] = "FireBlast_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "FireBlast_AISelectEffect" },
  },
  ["CharmanderEmberEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Ember_CheckEnergy" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "Ember_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_DISCARD_ENERGY", ["function"] = "Ember_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "Ember_AISelectEffect" },
  },
  ["MoltresWildfireEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Wildfire_CheckEnergy" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "Wildfire_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "Wildfire_DiscardDeckEffect" },
    { hook = "EFFECTCMDTYPE_DISCARD_ENERGY", ["function"] = "Wildfire_DiscardEnergyEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "Wildfire_AISelectEffect" },
  },
  ["MoltresLv35DiveBombEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "MoltresLv35DiveBomb_Success50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "MoltresLv35DiveBomb_AIEffect" },
  },
  ["FlareonQuickAttackEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "FlareonQuickAttack_DamageBoostEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "FlareonQuickAttack_AIEffect" },
  },
  ["FlareonFlamethrowerEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "FlareonFlamethrower_CheckEnergy" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "FlareonFlamethrower_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_DISCARD_ENERGY", ["function"] = "FlareonFlamethrower_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "FlareonFlamethrower_AISelectEffect" },
  },
  ["MagmarFlamethrowerEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "MagmarFlamethrower_CheckEnergy" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "MagmarFlamethrower_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_DISCARD_ENERGY", ["function"] = "MagmarFlamethrower_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "MagmarFlamethrower_AISelectEffect" },
  },
  ["MagmarSmokescreenEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "MagmarSmokescreenEffect" },
  },
  ["MagmarSmogEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Poison50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "MagmarSmog_AIEffect" },
  },
  ["CharmeleonFlamethrowerEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "CharmeleonFlamethrower_CheckEnergy" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "CharmeleonFlamethrower_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_DISCARD_ENERGY", ["function"] = "CharmeleonFlamethrower_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "CharmeleonFlamethrower_AISelectEffect" },
  },
  ["CharizardEnergyBurnEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "EnergyBurnEffect" },
  },
  ["CharizardFireSpinEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "FireSpin_CheckEnergy" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "FireSpin_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_DISCARD_ENERGY", ["function"] = "FireSpin_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "FireSpin_AISelectEffect" },
  },
  ["VulpixConfuseRayEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Confusion50PercentEffect" },
  },
  ["FlareonRageEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "FlareonRage_DamageBoostEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "FlareonRage_AIEffect" },
  },
  ["NinetalesMixUpEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "MixUpEffect" },
  },
  ["NinetalesDancingEmbersEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "DancingEmbers_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "DancingEmbers_AIEffect" },
  },
  ["MoltresFiregiverEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Firegiver_InitialEffect" },
    { hook = "EFFECTCMDTYPE_PKMN_POWER_TRIGGER", ["function"] = "Firegiver_AddToHandEffect" },
  },
  ["MoltresLv37DiveBombEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "MoltresLv37DiveBomb_Success50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "MoltresLv37DiveBomb_AIEffect" },
  },
  ["AbraPsyshockEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["GengarCurseEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "Curse_CheckDamageAndBench" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Curse_TransferDamageEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "Curse_PlayerSelectEffect" },
  },
  ["GengarDarkMindEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "GengarDarkMind_DamageBenchEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "GengarDarkMind_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "GengarDarkMind_AISelectEffect" },
  },
  ["GastlySleepingGasEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SleepingGasEffect" },
  },
  ["GastlyDestinyBondEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "DestinyBond_CheckEnergy" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "DestinyBond_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "DestinyBond_DestinyBondEffect" },
    { hook = "EFFECTCMDTYPE_DISCARD_ENERGY", ["function"] = "DestinyBond_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "DestinyBond_AISelectEffect" },
  },
  ["GastlyLickEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["GastlyEnergyConversionEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "EnergyConversion_CheckEnergy" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "EnergyConversion_AddToHandEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "EnergyConversion_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "EnergyConversion_AISelectEffect" },
  },
  ["HaunterHypnosisEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SleepEffect" },
  },
  ["HaunterDreamEaterEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "DreamEaterEffect" },
  },
  ["HaunterTransparencyEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "TransparencyEffect" },
  },
  ["HaunterNightmareEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SleepEffect" },
  },
  ["HypnoProphecyEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Prophecy_CheckDeck" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "Prophecy_ReorderDeckEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "Prophecy_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "Prophecy_AISelectEffect" },
  },
  ["HypnoDarkMindEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "HypnoDarkMind_DamageBenchEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "HypnoDarkMind_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "HypnoDarkMind_AISelectEffect" },
  },
  ["DrowzeeConfuseRayEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Confusion50PercentEffect" },
  },
  ["MrMimeInvisibleWallEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "InvisibleWallEffect" },
  },
  ["MrMimeMeditateEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "MrMimeMeditate_DamageBoostEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "MrMimeMeditate_AIEffect" },
  },
  ["AlakazamDamageSwapEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "DamageSwap_CheckDamage" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "DamageSwap_SelectAndSwapEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "DamageSwap_SwapEffect" },
  },
  ["AlakazamConfuseRayEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Confusion50PercentEffect" },
  },
  ["MewPsywaveEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PsywaveEffect" },
  },
  ["MewDevolutionBeamEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "DevolutionBeam_CheckPlayArea" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "DevolutionBeam_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "DevolutionBeam_LoadAnimation" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "DevolutionBeam_DevolveEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "DevolutionBeam_AISelectEffect" },
  },
  ["MewNeutralizingShieldEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "NeutralizingShieldEffect" },
  },
  ["MewPsyshockEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["MewtwoPsychicEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Psychic_DamageBoostEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "Psychic_AIEffect" },
  },
  ["MewtwoBarrierEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Barrier_CheckEnergy" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "Barrier_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Barrier_BarrierEffect" },
    { hook = "EFFECTCMDTYPE_DISCARD_ENERGY", ["function"] = "Barrier_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "Barrier_AISelectEffect" },
  },
  ["MewtwoAltEnergyAbsorptionEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "MewtwoAltEnergyAbsorption_CheckDiscardPile" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "MewtwoAltEnergyAbsorption_AddToHandEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "MewtwoAltEnergyAbsorption_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "MewtwoAltEnergyAbsorption_AISelectEffect" },
  },
  ["MewtwoEnergyAbsorptionEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "MewtwoEnergyAbsorption_CheckDiscardPile" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "MewtwoEnergyAbsorption_AddToHandEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "MewtwoEnergyAbsorption_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "MewtwoEnergyAbsorption_AISelectEffect" },
  },
  ["SlowbroStrangeBehaviorEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "StrangeBehavior_CheckDamage" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "StrangeBehavior_SelectAndSwapEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "StrangeBehavior_SwapEffect" },
  },
  ["SlowbroPsyshockEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["SlowpokeSpacingOutEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "SpacingOut_CheckDamage" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SpacingOut_Success50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "SpacingOut_HealEffect" },
  },
  ["SlowpokeScavengeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Scavenge_CheckDiscardPile" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "Scavenge_PlayerSelectEnergyEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "Scavenge_AddToHandEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "Scavenge_PlayerSelectTrainerEffect" },
    { hook = "EFFECTCMDTYPE_DISCARD_ENERGY", ["function"] = "Scavenge_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "Scavenge_AISelectEffect" },
  },
  ["SlowpokeAmnesiaEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "SlowpokeAmnesia_CheckAttacks" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "SlowpokeAmnesia_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SlowpokeAmnesia_DisableEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "SlowpokeAmnesia_AISelectEffect" },
  },
  ["KadabraRecoverEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "KadabraRecover_CheckEnergyHP" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "KadabraRecover_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "KadabraRecover_HealEffect" },
    { hook = "EFFECTCMDTYPE_DISCARD_ENERGY", ["function"] = "KadabraRecover_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "KadabraRecover_AISelectEffect" },
  },
  ["JynxDoubleslapEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "JynxDoubleslap_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "JynxDoubleslap_AIEffect" },
  },
  ["JynxMeditateEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "JynxMeditate_DamageBoostEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "JynxMeditate_AIEffect" },
  },
  ["MewMysteryAttackEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "MysteryAttack_RandomEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "MysteryAttack_RecoverEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "MysteryAttack_AIEffect" },
  },
  ["GeodudeStoneBarrageEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "StoneBarrage_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "StoneBarrage_AIEffect" },
  },
  ["OnixHardenEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "OnixHardenEffect" },
  },
  ["PrimeapeFurySwipesEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PrimeapeFurySwipes_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "PrimeapeFurySwipes_AIEffect" },
  },
  ["PrimeapeTantrumEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "TantrumEffect" },
  },
  ["MachampStrikesBackEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "StrikesBackEffect" },
  },
  ["KabutoKabutoArmorEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "KabutoArmorEffect" },
  },
  ["KabutopsAbsorbEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "AbsorbEffect" },
  },
  ["CuboneSnivelEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SnivelEffect" },
  },
  ["CuboneRageEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "CuboneRage_DamageBoostEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "CuboneRage_AIEffect" },
  },
  ["MarowakBonemerangEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Bonemerang_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "Bonemerang_AIEffect" },
  },
  ["MarowakCallforFriendEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "MarowakCallForFamily_CheckDeckAndPlayArea" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "MarowakCallForFamily_PutInPlayAreaEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "MarowakCallForFamily_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "MarowakCallForFamily_AISelectEffect" },
  },
  ["MachokeKarateChopEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "KarateChop_DamageSubtractionEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "KarateChop_AIEffect" },
  },
  ["MachokeSubmissionEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "SubmissionEffect" },
  },
  ["GolemSelfdestructEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "GolemSelfdestructEffect" },
  },
  ["GravelerHardenEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "GravelerHardenEffect" },
  },
  ["RhydonRamEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "Ram_RecoilSwitchEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "Ram_SelectSwitchEffect" },
    { hook = "EFFECTCMDTYPE_AI_SWITCH_DEFENDING_PKMN", ["function"] = "Ram_SelectSwitchEffect" },
  },
  ["RhyhornLeerEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "LeerEffect" },
  },
  ["HitmonleeStretchKickEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "StretchKick_CheckBench" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "StretchKick_BenchDamageEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "StretchKick_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "StretchKick_AISelectEffect" },
  },
  ["SandshrewSandAttackEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SandAttackEffect" },
  },
  ["SandslashFurySwipesEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SandslashFurySwipes_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "SandslashFurySwipes_AIEffect" },
  },
  ["DugtrioEarthquakeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "EarthquakeEffect" },
  },
  ["AerodactylPrehistoricPowerEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "PrehistoricPowerEffect" },
  },
  ["MankeyPeekEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "Peek_OncePerTurnCheck" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Peek_SelectEffect" },
  },
  ["MarowakBoneAttackEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "BoneAttackEffect" },
  },
  ["MarowakWailEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Wail_BenchCheck" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "Wail_FillBenchEffect" },
  },
  ["ElectabuzzThundershockEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["ElectabuzzThunderpunchEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Thunderpunch_ModifierEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "Thunderpunch_RecoilEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "Thunderpunch_AIEffect" },
  },
  ["ElectabuzzLightScreenEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "LightScreenEffect" },
  },
  ["ElectabuzzQuickAttackEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ElectabuzzQuickAttack_DamageBoostEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "ElectabuzzQuickAttack_AIEffect" },
  },
  ["MagnemiteThunderWaveEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["MagnemiteSelfdestructEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "MagnemiteSelfdestructEffect" },
  },
  ["ZapdosThunderEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ZapdosThunder_Recoil50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "ZapdosThunder_RecoilEffect" },
  },
  ["ZapdosThunderboltEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ThunderboltEffect" },
  },
  ["ZapdosThunderstormEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "ThunderstormEffect" },
  },
  ["JolteonQuickAttackEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "JolteonQuickAttack_DamageBoostEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "JolteonQuickAttack_AIEffect" },
  },
  ["JolteonPinMissileEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PinMissile_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "PinMissile_AIEffect" },
  },
  ["FlyingPikachuThundershockEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["FlyingPikachuFlyEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Fly_Success50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "Fly_AIEffect" },
  },
  ["PikachuThunderJoltEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ThunderJolt_Recoil50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "ThunderJolt_RecoilEffect" },
  },
  ["PikachuSparkEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "Spark_BenchDamageEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "Spark_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "Spark_AISelectEffect" },
  },
  ["PikachuLv16GrowlEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PikachuLv16GrowlEffect" },
  },
  ["PikachuLv16ThundershockEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["PikachuAltLv16GrowlEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PikachuAltLv16GrowlEffect" },
  },
  ["PikachuAltLv16ThundershockEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["ElectrodeChainLightningEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "ChainLightningEffect" },
  },
  ["RaichuAgilityEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "RaichuAgilityEffect" },
  },
  ["RaichuThunderEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "RaichuThunder_Recoil50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "RaichuThunder_RecoilEffect" },
  },
  ["RaichuGigashockEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "Gigashock_BenchDamageEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "Gigashock_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "Gigashock_AISelectEffect" },
  },
  ["MagnetonThunderWaveEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["MagnetonLv28SelfdestructEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "MagnetonLv28SelfdestructEffect" },
  },
  ["MagnetonSonicboomEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "MagnetonSonicboom_UnaffectedByColorEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "MagnetonSonicboom_NullEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "MagnetonSonicboom_UnaffectedByColorEffect" },
  },
  ["MagnetonLv35SelfdestructEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "MagnetonLv35SelfdestructEffect" },
  },
  ["ZapdosPealOfThunderEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "PealOfThunder_InitialEffect" },
    { hook = "EFFECTCMDTYPE_PKMN_POWER_TRIGGER", ["function"] = "PealOfThunder_RandomlyDamageEffect" },
  },
  ["ZapdosBigThunderEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "BigThunderEffect" },
  },
  ["MagnemiteMagneticStormEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "MagneticStormEffect" },
  },
  ["ElectrodeSonicboomEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ElectrodeSonicboom_UnaffectedByColorEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "ElectrodeSonicboom_NullEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "ElectrodeSonicboom_UnaffectedByColorEffect" },
  },
  ["ElectrodeEnergySpikeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "EnergySpike_DeckCheck" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "EnergySpike_AttachEnergyEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "EnergySpike_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "EnergySpike_AISelectEffect" },
  },
  ["JolteonDoubleKickEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "JolteonDoubleKick_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "JolteonDoubleKick_AIEffect" },
  },
  ["JolteonStunNeedleEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["EeveeTailWagEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "TailWagEffect" },
  },
  ["EeveeQuickAttackEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "EeveeQuickAttack_DamageBoostEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "EeveeQuickAttack_AIEffect" },
  },
  ["SpearowMirrorMoveEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "SpearowMirrorMove_InitialEffect1" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "SpearowMirrorMove_InitialEffect2" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SpearowMirrorMove_BeforeDamage" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "SpearowMirrorMove_AfterDamage" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "SpearowMirrorMove_PlayerSelection" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "SpearowMirrorMove_AISelection" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "SpearowMirrorMove_AIEffect" },
  },
  ["FearowAgilityEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "FearowAgilityEffect" },
  },
  ["DragoniteStepInEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "StepIn_BenchCheck" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "StepIn_SwitchEffect" },
  },
  ["DragoniteLv45SlamEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "DragoniteLv45Slam_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "DragoniteLv45Slam_AIEffect" },
  },
  ["SnorlaxThickSkinnedEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "ThickSkinnedEffect" },
  },
  ["SnorlaxBodySlamEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["FarfetchdLeekSlapEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "LeekSlap_OncePerDuelCheck" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "LeekSlap_NoDamage50PercentEffect" },
    { hook = "EFFECTCMDTYPE_DISCARD_ENERGY", ["function"] = "LeekSlap_SetUsedThisDuelFlag" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "LeekSlap_AIEffect" },
  },
  ["KangaskhanFetchEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "FetchEffect" },
  },
  ["KangaskhanCometPunchEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "CometPunch_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "CometPunch_AIEffect" },
  },
  ["TaurosStompEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "TaurosStomp_DamageBoostEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "TaurosStomp_AIEffect" },
  },
  ["TaurosRampageEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Rampage_Confusion50PercentEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "Rampage_AIEffect" },
  },
  ["DoduoFuryAttackEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "FuryAttack_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "FuryAttack_AIEffect" },
  },
  ["DodrioRetreatAidEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "RetreatAidEffect" },
  },
  ["DodrioRageEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "DodrioRage_DamageBoostEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "DodrioRage_AIEffect" },
  },
  ["MeowthPayDayEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "PayDayEffect" },
  },
  ["DragonairSlamEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "DragonairSlam_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "DragonairSlam_AIEffect" },
  },
  ["DragonairHyperBeamEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "DragonairHyperBeam_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "DragonairHyperBeam_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "DragonairHyperBeam_AISelectEffect" },
  },
  ["ClefableMetronomeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "ClefableMetronome_CheckAttacks" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "ClefableMetronome_UseAttackEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "ClefableMetronome_AISelectEffect" },
  },
  ["ClefableMinimizeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ClefableMinimizeEffect" },
  },
  ["PidgeotHurricaneEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "HurricaneEffect" },
  },
  ["PidgeottoWhirlwindEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "PidgeottoWhirlwind_SwitchEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "PidgeottoWhirlwind_SelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SWITCH_DEFENDING_PKMN", ["function"] = "PidgeottoWhirlwind_SelectEffect" },
  },
  ["PidgeottoMirrorMoveEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "PidgeottoMirrorMove_InitialEffect1" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "PidgeottoMirrorMove_InitialEffect2" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PidgeottoMirrorMove_BeforeDamage" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "PidgeottoMirrorMove_AfterDamage" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "PidgeottoMirrorMove_PlayerSelection" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "PidgeottoMirrorMove_AISelection" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "PidgeottoMirrorMove_AIEffect" },
  },
  ["ClefairySingEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SingEffect" },
  },
  ["ClefairyMetronomeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "ClefairyMetronome_CheckAttacks" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "ClefairyMetronome_UseAttackEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "ClefairyMetronome_AISelectEffect" },
  },
  ["WigglytuffLullabyEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SleepEffect" },
  },
  ["WigglytuffDoTheWaveEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "DoTheWaveEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "DoTheWaveEffect" },
  },
  ["JigglypuffLullabyEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SleepEffect" },
  },
  ["JigglypuffFirstAidEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "FirstAid_DamageCheck" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "FirstAid_HealEffect" },
  },
  ["JigglypuffDoubleEdgeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "JigglypuffDoubleEdgeEffect" },
  },
  ["PersianPounceEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PounceEffect" },
  },
  ["LickitungTongueWrapEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Paralysis50PercentEffect" },
  },
  ["LickitungSupersonicEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "LickitungSupersonicEffect" },
  },
  ["PidgeyWhirlwindEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "PidgeyWhirlwind_SwitchEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "PidgeyWhirlwind_SelectEffect" },
    { hook = "EFFECTCMDTYPE_AI_SWITCH_DEFENDING_PKMN", ["function"] = "PidgeyWhirlwind_SelectEffect" },
  },
  ["PorygonConversion1EffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Conversion1_WeaknessCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "Conversion1_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "Conversion1_ChangeWeaknessEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "Conversion1_AISelectEffect" },
  },
  ["PorygonConversion2EffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Conversion2_ResistanceCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "Conversion2_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "Conversion2_ChangeResistanceEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "Conversion2_AISelectEffect" },
  },
  ["ChanseyScrunchEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ScrunchEffect" },
  },
  ["ChanseyDoubleEdgeEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "ChanseyDoubleEdgeEffect" },
  },
  ["RaticateSuperFangEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SuperFang_HalfHPEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "SuperFang_AIEffect" },
  },
  ["TrainerCardAsPokemonEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "TrainerCardAsPokemon_BenchCheck" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "TrainerCardAsPokemon_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "TrainerCardAsPokemon_PlayerSelectSwitch" },
  },
  ["DragoniteHealingWindEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "HealingWind_InitialEffect" },
    { hook = "EFFECTCMDTYPE_PKMN_POWER_TRIGGER", ["function"] = "HealingWind_PlayAreaHealEffect" },
  },
  ["DragoniteLv41SlamEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "DragoniteLv41Slam_MultiplierEffect" },
    { hook = "EFFECTCMDTYPE_AI", ["function"] = "DragoniteLv41Slam_AIEffect" },
  },
  ["MeowthCatPunchEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "CatPunchEffect" },
  },
  ["DittoMorphEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "MorphEffect" },
  },
  ["PidgeotSlicingWindEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "SlicingWindEffect" },
  },
  ["PidgeotGaleEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Gale_LoadAnimation" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "Gale_SwitchEffect" },
  },
  ["JigglypuffFriendshipSongEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "FriendshipSong_BenchCheck" },
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "FriendshipSong_AddToBench50PercentEffect" },
  },
  ["JigglypuffExpandEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_AFTER_DAMAGE", ["function"] = "ExpandEffect" },
  },
  ["SuperPotionEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "SuperPotion_DamageEnergyCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "SuperPotion_PlayerSelectEffect" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SuperPotion_HealEffect" },
  },
  ["ImakuniEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ImakuniEffect" },
  },
  ["EnergyRemovalEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "EnergyRemoval_EnergyCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "EnergyRemoval_PlayerSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "EnergyRemoval_DiscardEffect" },
    { hook = "EFFECTCMDTYPE_AI_SELECTION", ["function"] = "EnergyRemoval_AISelection" },
  },
  ["EnergyRetrievalEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "EnergyRetrieval_HandEnergyCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "EnergyRetrieval_PlayerHandSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "EnergyRetrieval_DiscardAndAddToHandEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "EnergyRetrieval_PlayerDiscardPileSelection" },
  },
  ["EnergySearchEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "EnergySearch_DeckCheck" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "EnergySearch_AddToHandEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "EnergySearch_PlayerSelection" },
  },
  ["ProfessorOakEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ProfessorOakEffect" },
  },
  ["PotionEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Potion_DamageCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "Potion_PlayerSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Potion_HealEffect" },
  },
  ["GamblerEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "GamblerEffect" },
  },
  ["ItemFinderEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "ItemFinder_HandDiscardPileCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "ItemFinder_PlayerSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ItemFinder_DiscardAddToHandEffect" },
  },
  ["DefenderEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "Defender_PlayerSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Defender_AttachDefenderEffect" },
  },
  ["MysteriousFossilEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "MysteriousFossil_BenchCheck" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "MysteriousFossil_PlaceInPlayAreaEffect" },
  },
  ["FullHealEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "FullHeal_StatusCheck" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "FullHeal_ClearStatusEffect" },
  },
  ["ImposterProfessorOakEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ImposterProfessorOakEffect" },
  },
  ["ComputerSearchEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "ComputerSearch_HandDeckCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "ComputerSearch_PlayerDiscardHandSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ComputerSearch_DiscardAddToHandEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "ComputerSearch_PlayerDeckSelection" },
  },
  ["ClefairyDollEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "ClefairyDoll_BenchCheck" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ClefairyDoll_PlaceInPlayAreaEffect" },
  },
  ["MrFujiEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "MrFuji_BenchCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "MrFuji_PlayerSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "MrFuji_ReturnToDeckEffect" },
  },
  ["PlusPowerEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PlusPowerEffect" },
  },
  ["SwitchEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Switch_BenchCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "Switch_PlayerSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Switch_SwitchEffect" },
  },
  ["PokemonCenterEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "PokemonCenter_DamageCheck" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PokemonCenter_HealDiscardEnergyEffect" },
  },
  ["PokemonFluteEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "PokemonFlute_BenchCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "PokemonFlute_PlayerSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PokemonFlute_PlaceInPlayAreaText" },
  },
  ["PokemonBreederEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "PokemonBreeder_HandPlayAreaCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "PokemonBreeder_PlayerSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PokemonBreeder_EvolveEffect" },
  },
  ["ScoopUpEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "ScoopUp_BenchCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "ScoopUp_PlayerSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "ScoopUp_ReturnToHandEffect" },
  },
  ["PokemonTraderEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "PokemonTrader_HandDeckCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "PokemonTrader_PlayerHandSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PokemonTrader_TradeCardsEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "PokemonTrader_PlayerDeckSelection" },
  },
  ["PokedexEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Pokedex_DeckCheck" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Pokedex_OrderDeckCardsEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "Pokedex_PlayerSelection" },
  },
  ["BillEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "BillEffect" },
  },
  ["LassEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "LassEffect" },
  },
  ["MaintenanceEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Maintenance_HandCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "Maintenance_PlayerSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Maintenance_ReturnToDeckAndDrawEffect" },
  },
  ["PokeBallEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "PokeBall_DeckCheck" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "PokeBall_AddToHandEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "PokeBall_PlayerSelection" },
  },
  ["RecycleEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Recycle_DiscardPileCheck" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Recycle_AddToHandEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "Recycle_PlayerSelection" },
  },
  ["ReviveEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "Revive_BenchCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "Revive_PlayerSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "Revive_PlaceInPlayAreaEffect" },
  },
  ["DevolutionSprayEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "DevolutionSpray_PlayAreaEvolutionCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "DevolutionSpray_PlayerSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "DevolutionSpray_DevolutionEffect" },
  },
  ["SuperEnergyRemovalEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "SuperEnergyRemoval_EnergyCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "SuperEnergyRemoval_PlayerSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SuperEnergyRemoval_DiscardEffect" },
  },
  ["SuperEnergyRetrievalEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "SuperEnergyRetrieval_HandEnergyCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "SuperEnergyRetrieval_PlayerHandSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "SuperEnergyRetrieval_DiscardAndAddToHandEffect" },
    { hook = "EFFECTCMDTYPE_REQUIRE_SELECTION", ["function"] = "SuperEnergyRetrieval_PlayerDiscardPileSelection" },
  },
  ["GustOfWindEffectCommands"] = {
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_1", ["function"] = "GustOfWind_BenchCheck" },
    { hook = "EFFECTCMDTYPE_INITIAL_EFFECT_2", ["function"] = "GustOfWind_PlayerSelection" },
    { hook = "EFFECTCMDTYPE_BEFORE_DAMAGE", ["function"] = "GustOfWind_SwitchEffect" },
  },
}

-- Functions reused identically across multiple cards' effects (5 such shared functions).
-- If two cards' attacks point to the same function name here, their mechanic is IDENTICAL --
-- useful for inferring exact behavior of a card via a sibling that shares the same function.
EffectCommands.shared_functions = {
  ["Paralysis50PercentEffect"] = { "AbraPsyshockEffectCommands", "ArticunoFreezeDryEffectCommands", "CaterpieStringShotEffectCommands", "DewgongIceBeamEffectCommands", "EkansWrapEffectCommands", "ElectabuzzThundershockEffectCommands", "FlyingPikachuThundershockEffectCommands", "GastlyLickEffectCommands", "GolduckPsyshockEffectCommands", "GrimerNastyGooEffectCommands", "GyaradosBubblebeamEffectCommands", "JolteonStunNeedleEffectCommands", "LickitungTongueWrapEffectCommands", "MagnemiteThunderWaveEffectCommands", "MagnetonThunderWaveEffectCommands", "MetapodStunSporeEffectCommands", "MewPsyshockEffectCommands", "OddishStunSporeEffectCommands", "PikachuAltLv16ThundershockEffectCommands", "PikachuLv16ThundershockEffectCommands", "PinsirIronGripEffectCommands", "SlowbroPsyshockEffectCommands", "SnorlaxBodySlamEffectCommands", "SquirtleBubbleEffectCommands", "StarmieStarFreezeEffectCommands", "TangelaBindEffectCommands", "TangelaStunSporeEffectCommands", "VenonatStunSporeEffectCommands" },
  ["Poison50PercentEffect"] = { "BeedrillPoisonStingEffectCommands", "KakunaPoisonPowderEffectCommands", "MagmarSmogEffectCommands", "MukSludgeEffectCommands", "WeedlePoisonStingEffectCommands", "WeepinbellPoisonPowderEffectCommands", "WeezingSmogEffectCommands" },
  ["SleepEffect"] = { "ExeggcuteHypnosisEffectCommands", "HaunterHypnosisEffectCommands", "HaunterNightmareEffectCommands", "JigglypuffLullabyEffectCommands", "ParasSporeEffectCommands", "ParasectSporeEffectCommands", "WigglytuffLullabyEffectCommands" },
  ["PoisonEffect"] = { "ArbokPoisonFangEffectCommands", "GloomPoisonPowderEffectCommands", "IvysaurPoisonPowderEffectCommands", "TangelaPoisonPowderEffectCommands", "TangelaPoisonWhipEffectCommands", "TentacruelJellyfishStingEffectCommands" },
  ["Confusion50PercentEffect"] = { "AlakazamConfuseRayEffectCommands", "DrowzeeConfuseRayEffectCommands", "LaprasConfuseRayEffectCommands", "VulpixConfuseRayEffectCommands" },
}

return EffectCommands