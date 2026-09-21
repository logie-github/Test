import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class SelectionEnergySwitchSourceTests(unittest.TestCase):
    def test_duel_ops_has_source_energy_list_and_presence_helpers(self):
        src = read("src/tcg/duel/DuelOps.lua")
        self.assertIn("function DuelOps:createArenaOrBenchEnergyCardList", src)
        self.assertIn('self.memory:write8("wram", base + count, 0xff, bank)', src)
        self.assertIn("function DuelOps:checkIfThereAreAnyEnergyCardsAttached", src)
        self.assertIn("TYPE_ENERGY_F", src)

    def test_selection_helpers_validate_bench_and_attached_energy(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        self.assertIn("function EffectCommands:_selection", src)
        self.assertIn("function EffectCommands:_selectBench", src)
        self.assertIn("function EffectCommands:_selectAttachedEnergy", src)
        self.assertIn('"invalid_selection:" .. key', src)
        self.assertIn('"selection_required:" .. key', src)

    def test_fire_energy_discard_family_is_generic(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for prefix in (
            "ArcanineFlamethrower", "FlareonFlamethrower",
            "MagmarFlamethrower", "CharmeleonFlamethrower",
        ):
            self.assertIn(f'"{prefix}"', src)
        for label in (
            "FireBlast_CheckEnergy", "FireBlast_PlayerSelectEffect", "FireBlast_DiscardEffect",
            "Ember_CheckEnergy", "Ember_PlayerSelectEffect", "Ember_DiscardEffect",
        ):
            self.assertIn(label, src)
        self.assertIn('prefix .. "_CheckEnergy"', src)
        self.assertIn('prefix .. "_PlayerSelectEffect"', src)
        self.assertIn('prefix .. "_DiscardEffect"', src)
        self.assertIn("TYPE_ENERGY_FIRE", src)
        self.assertIn("discardTempEnergy", src)

    def test_hyper_beam_and_whirlpool_select_and_discard_defending_energy(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "GolduckHyperBeam_PlayerSelectEffect", "GolduckHyperBeam_DiscardEffect",
            "Whirlpool_PlayerSelectEffect", "Whirlpool_DiscardEffect",
            "DragonairHyperBeam_PlayerSelectEffect", "DragonairHyperBeam_DiscardEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn('"opponentEnergyDeckIndex"', src)
        self.assertIn("LAST_TURN_EFFECT_DISCARD_ENERGY", src)
        self.assertIn("checkNoDamageOrEffect", src)

    def test_switch_gust_and_whirlwind_use_play_area_swap(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "Switch_BenchCheck", "Switch_PlayerSelection", "Switch_SwitchEffect",
            "GustOfWind_BenchCheck", "GustOfWind_PlayerSelection", "GustOfWind_SwitchEffect",
            "ButterfreeWhirlwind_CheckBench", "ButterfreeWhirlwind_SwitchEffect",
            "PidgeottoWhirlwind_SelectEffect", "PidgeottoWhirlwind_SwitchEffect",
            "PidgeyWhirlwind_SelectEffect", "PidgeyWhirlwind_SwitchEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn("swapArenaWithBenchPokemon", src)
        self.assertIn("handleDestinyBondSubstatus", src)
        self.assertIn('"wDefendingWasForcedToSwitch"', src)

    def test_energy_removal_trainer_uses_opponent_play_area_and_energy_selection(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "EnergyRemoval_EnergyCheck", "EnergyRemoval_PlayerSelection",
            "EnergyRemoval_DiscardEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn('"opponentPlayArea"', src)
        self.assertIn('"opponentEnergyDeckIndex"', src)
        self.assertIn("checkIfThereAreAnyEnergyCardsAttached", src)

    def test_play_area_damage_path_covers_bench_power_prevention_and_strikes_back(self):
        combat = read("src/tcg/duel/Combat.lua")
        status = read("src/tcg/duel/Status.lua")
        self.assertIn("function Combat:dealDamageToPlayAreaPokemon", combat)
        self.assertIn("function Combat:dealDamageToAllBenchedPokemon", combat)
        self.assertIn("handlePlayAreaPokemonPowerDamage", combat)
        self.assertIn("strikes_back", combat)
        self.assertIn("function Status:handlePlayAreaPokemonPowerDamage", status)
        self.assertIn("NO_DAMAGE_OR_EFFECT_NSHIELD", status)
        self.assertIn("NO_DAMAGE_OR_EFFECT_TRANSPARENCY", status)

    def test_bench_damage_families_use_shared_play_area_damage(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "StretchKick_BenchDamageEffect", "Spark_BenchDamageEffect",
            "GengarDarkMind_DamageBenchEffect", "HypnoDarkMind_DamageBenchEffect",
            "Blizzard_BenchDamage50PercentEffect", "Blizzard_BenchDamageEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn("dealDamageToPlayAreaPokemon", src)
        self.assertIn("dealDamageToAllBenchedPokemon", src)

    def test_remaining_triggered_power_families_are_registered(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "Firegiver_AddToHandEffect", "HealingWind_PlayAreaHealEffect",
            "PealOfThunder_RandomlyDamageEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn("searchCardInDeckAndAddToHand", src)
        self.assertIn("shuffleDeck", src)
        self.assertIn("handlePendingResolution", src)

    def test_player_attack_forwards_host_selection(self):
        src = read("src/tcg/duel/PlayerActions.lua")
        start = src.index("function PlayerActions:attack")
        block = src[start:]
        self.assertIn("attack(attackIndex, selection)", block)
        self.assertIn("selection = selection", block)

    def test_destiny_bond_helper_is_available_to_forced_switch_path(self):
        src = read("src/tcg/duel/Status.lua")
        self.assertIn("function Status:handleDestinyBondSubstatus", src)
        self.assertIn("SUBSTATUS1_DESTINY_BOND", src)
        self.assertIn('self.duelVars:set(self.c.DUELVARS_ARENA_CARD_HP, 0)', src)


if __name__ == "__main__":
    unittest.main()
