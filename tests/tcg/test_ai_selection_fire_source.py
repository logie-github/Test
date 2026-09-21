import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class AISelectionFireSourceTests(unittest.TestCase):
    def test_ai_attack_path_executes_both_source_selection_phases(self):
        src = read("src/tcg/duel/AI.lua")
        start = src.index("function AI:_prepareAttackSelections")
        end = src.index("-- AIProcessAndTryToUseAttack", start)
        block = src[start:end]
        self.assertIn("EFFECTCMDTYPE_AI_SELECTION", block)
        self.assertIn("EFFECTCMDTYPE_AI_SWITCH_DEFENDING_PKMN", block)
        self.assertIn("untranslated_ai_selection_path", block)
        self.assertIn("self.combat:loadAttack(deckIndex, attackIndex)", block)

    def test_ai_attack_uses_prepared_temp_parameters_without_player_menu(self):
        ai = read("src/tcg/duel/AI.lua")
        combat = read("src/tcg/duel/Combat.lua")
        self.assertIn("self:_prepareAttackSelections(active, selected)", ai)
        self.assertIn("aiPreparedSelections = prepared", ai)
        self.assertIn("if not options.aiPreparedSelections then", combat)
        self.assertIn("EFFECTCMDTYPE_INITIAL_EFFECT_2", combat)
        self.assertIn("EFFECTCMDTYPE_REQUIRE_SELECTION", combat)

    def test_single_fire_energy_ai_selectors_share_first_fire_card_logic(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "ArcanineFlamethrower_AISelectEffect",
            "FireBlast_AISelectEffect",
            "Ember_AISelectEffect",
            "FlareonFlamethrower_AISelectEffect",
            "MagmarFlamethrower_AISelectEffect",
            "CharmeleonFlamethrower_AISelectEffect",
        ):
            self.assertIn(f'"{label}"', src)
        self.assertIn("createFilteredArenaEnergyList", src)
        self.assertIn("TYPE_ENERGY_FIRE", src)
        self.assertIn('s.memory:writeSymbol8("hTemp_ffa0", values[1])', src)

    def test_flames_of_rage_preserves_two_fire_energy_temp_list_semantics(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "FlamesOfRage_CheckEnergy",
            "FlamesOfRage_PlayerSelectEffect",
            "FlamesOfRage_AISelectEffect",
            "FlamesOfRage_DiscardEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        block = src[src.index('self:register("FlamesOfRage_AISelectEffect"'):
                    src.index('self:register("FireSpin_CheckEnergy"')]
        self.assertIn("TYPE_ENERGY_FIRE", block)
        self.assertIn("values[1]", block)
        self.assertIn("values[2]", block)
        self.assertIn("writeTempList", block)

    def test_fire_spin_selects_first_two_attached_energy_cards_regardless_of_color(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "FireSpin_CheckEnergy",
            "FireSpin_PlayerSelectEffect",
            "FireSpin_AISelectEffect",
            "FireSpin_DiscardEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        block = src[src.index('self:register("FireSpin_CheckEnergy"'):
                    src.index("-- ThunderboltEffect::")]
        self.assertIn("createArenaOrBenchEnergyCardList", block)
        self.assertIn('actor.memory:read8("wram", base, bank)', block)
        self.assertIn('actor.memory:read8("wram", base + 1, bank)', block)

    def test_double_energy_player_paths_validate_exactly_two_distinct_cards(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        block = src[src.index("local function validateTwoArenaEnergies"):
                    src.index("local function discardTwoTempEnergies")]
        self.assertIn('"energyDeckIndexes"', block)
        self.assertIn('"selectAttachedEnergies"', block)
        self.assertIn("}, 2, 2)", block)
        self.assertIn("CARD_LOCATION_PLAY_AREA", block)
        self.assertIn("TYPE_ENERGY_F", block)


if __name__ == "__main__":
    unittest.main()
