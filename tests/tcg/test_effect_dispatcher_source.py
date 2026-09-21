import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class EffectDispatcherSourceTests(unittest.TestCase):
    def test_extractor_verifies_effect_records_against_rom_and_symbols(self):
        src = read("src/tcg/import/RomExtractor.lua")
        block = src[src.index("function RomExtractor:extractEffects()"):
                    src.index("function RomExtractor:extractText()")]
        for token in (
            'self:symbol("EffectCommands")',
            'self.constants[typeName]',
            'self:byteAt(offset)',
            'self:wordAt(offset + 1)',
            'self:symbol(functionLabel)',
            'self:write("tcg_effects", out)',
        ):
            self.assertIn(token, block)
        self.assertIn('manifest.schema == 5', src)

    def test_dispatcher_uses_loaded_pointer_and_fails_closed_per_function(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        self.assertIn('memory:address("wLoadedAttackEffectCommands")', src)
        self.assertIn('self.data.byAddress[pointer]', src)
        self.assertIn('function EffectCommands:checkMatchingCommand', src)
        self.assertIn('function EffectCommands:tryExecute', src)
        self.assertIn('"untranslated_effect:" .. command.functionLabel', src)
        self.assertIn('function EffectCommands:validatePhases', src)

    def test_shared_status_effect_primitives_are_registered(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "PoisonEffect",
            "DoublePoisonEffect",
            "ParalysisEffect",
            "ConfusionEffect",
            "SleepEffect",
            "Poison50PercentEffect",
            "Paralysis50PercentEffect",
            "Confusion50PercentEffect",
            "Sleep50PercentEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn('self.setup:tossCoin()', src)
        self.assertIn('self.status:queueStatusCondition', src)

    def test_player_attack_phase_order_matches_use_attack_source(self):
        src = read("src/tcg/duel/Combat.lua")
        start = src.index("function Combat:useAttack")
        block = src[start:src.index("return Combat", start)]
        ordered = [
            "EFFECTCMDTYPE_INITIAL_EFFECT_1",
            "checkSandAttackOrSmokescreenSubstatus",
            "EFFECTCMDTYPE_INITIAL_EFFECT_2",
            "EFFECTCMDTYPE_DISCARD_ENERGY",
            "checkSelfConfusionDamage",
            "exchangeRNG",
            "EFFECTCMDTYPE_REQUIRE_SELECTION",
            "EFFECTCMDTYPE_BEFORE_DAMAGE",
            "applyDamageModifiers",
            "EFFECTCMDTYPE_AFTER_DAMAGE",
            "applyStatusConditionQueue",
        ]
        positions = [block.index(token) for token in ordered]
        self.assertEqual(positions, sorted(positions))

    def test_star_freeze_no_longer_has_attack_specific_dispatch(self):
        combat = read("src/tcg/duel/Combat.lua")
        effects = read("src/tcg/duel/EffectCommands.lua")
        self.assertNotIn("_translatedEffect", combat)
        self.assertNotIn("starmie_star_freeze", combat)
        self.assertNotIn("self.c.STARMIE", combat)
        self.assertIn('self:register("Paralysis50PercentEffect"', effects)

    def test_runtime_wires_generated_effect_data(self):
        runtime = read("src/tcg/duel/Runtime.lua")
        data = read("src/tcg/Data.lua")
        self.assertIn('local EffectCommands = require(', runtime)
        self.assertIn('data.effects', runtime)
        self.assertIn('effectCommands = effectCommands', runtime)
        self.assertIn('loadGenerated("tcg_effects")', data)


if __name__ == "__main__":
    unittest.main()
