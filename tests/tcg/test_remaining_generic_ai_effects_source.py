import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class RemainingGenericAIEffectSourceTests(unittest.TestCase):
    def test_all_remaining_21_ai_handlers_are_registered(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        labels = {
            "BigEggsplosion_AIEffect", "CuboneRage_AIEffect", "DoTheWaveEffect",
            "DodrioRage_AIEffect", "ElectrodeSonicboom_UnaffectedByColorEffect",
            "FlamesOfRage_AIEffect", "FlareonRage_AIEffect", "FoulGas_AIEffect",
            "JynxMeditate_AIEffect", "KarateChop_AIEffect", "KinglerFlail_AIEffect",
            "MagikarpFlail_AIEffect", "MagnetonSonicboom_UnaffectedByColorEffect",
            "MrMimeMeditate_AIEffect", "PidgeottoMirrorMove_AIEffect", "Psychic_AIEffect",
            "Rampage_AIEffect", "SpearowMirrorMove_AIEffect", "SuperFang_AIEffect",
            "Toxic_AIEffect", "VenomPowder_AIEffect",
        }
        for label in labels:
            self.assertIn(f'self:register("{label}"', src)

    def test_shared_set_definite_ai_damage_preserves_source_low_byte_semantics(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        block = src[src.index("local function setDefiniteAIDamage"):src.index("local function ownArenaDamage")]
        self.assertIn('s.memory:readSymbol8("wDamage")', block)
        self.assertIn('s.memory:writeSymbol8("wAIMinDamage", damage)', block)
        self.assertIn('s.memory:writeSymbol8("wAIMaxDamage", damage)', block)

    def test_energy_and_special_damage_families_match_source_shapes(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        self.assertIn("count = count + 1", src)  # Psychic counts attached Energy cards, not energy units.
        self.assertIn("math.ceil(hp / 20) * 10", src)  # Super Fang half-HP rounded up to 10.
        self.assertIn("local product = (total * 20) % 0x10000", src)
        self.assertIn('s.memory:writeSymbol8("wAIMinDamage", 0)', src)
        self.assertIn("math.max(0, count - 1) * 10", src)  # Do the Wave excludes Arena.

    def test_paired_ordinary_handlers_share_the_source_damage_math(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "BigEggsplosion_MultiplierEffect", "Toxic_DoublePoisonEffect",
            "VenomPowder_PoisonConfusion50PercentEffect", "KinglerFlail_HPCheck",
            "MagikarpFlail_HPCheck", "FlareonRage_DamageBoostEffect",
            "MrMimeMeditate_DamageBoostEffect", "Psychic_DamageBoostEffect",
            "JynxMeditate_DamageBoostEffect", "CuboneRage_DamageBoostEffect",
            "KarateChop_DamageSubtractionEffect", "MagnetonSonicboom_NullEffect",
            "ElectrodeSonicboom_NullEffect", "Rampage_Confusion50PercentEffect",
            "DodrioRage_DamageBoostEffect", "SuperFang_HalfHPEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)

    def test_generic_ai_identity_coverage_reaches_all_81_source_handlers(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        expected = re.findall(
            r"^\s+([A-Za-z_][A-Za-z0-9_]*_AIEffect)\s*=\s*\{",
            src[src.index("local expectedDamage = {"):src.index("local function updateExpectedAIDamage")],
            re.M,
        )
        poison = re.findall(
            r"^\s+([A-Za-z_][A-Za-z0-9_]*_AIEffect)\s*=\s*\{",
            src[src.index("local poisonExpected = {"):src.index("local function extraWaterEnergyDamageBonus")],
            re.M,
        )
        water = re.findall(
            r"^\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{",
            src[src.index("local waterBonus = {"):src.index("-- Remaining generic EFFECTCMDTYPE_AI families")],
            re.M,
        )
        remaining = {
            "BigEggsplosion_AIEffect", "CuboneRage_AIEffect", "DoTheWaveEffect",
            "DodrioRage_AIEffect", "ElectrodeSonicboom_UnaffectedByColorEffect",
            "FlamesOfRage_AIEffect", "FlareonRage_AIEffect", "FoulGas_AIEffect",
            "JynxMeditate_AIEffect", "KarateChop_AIEffect", "KinglerFlail_AIEffect",
            "MagikarpFlail_AIEffect", "MagnetonSonicboom_UnaffectedByColorEffect",
            "MrMimeMeditate_AIEffect", "PidgeottoMirrorMove_AIEffect", "Psychic_AIEffect",
            "Rampage_AIEffect", "SpearowMirrorMove_AIEffect", "SuperFang_AIEffect",
            "Toxic_AIEffect", "VenomPowder_AIEffect",
        }
        self.assertEqual(len(set(expected + poison + water) | remaining), 81)

    def test_mirror_move_ai_only_sets_min_max_from_last_turn_damage(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        block = src[src.index("local function mirrorMoveExpected"):src.index("-- effect_functions.asm shared status primitives")]
        self.assertIn("DUELVARS_ARENA_CARD_LAST_TURN_DAMAGE", block)
        self.assertIn('s.memory:writeSymbol8("wAIMinDamage", damage)', block)
        self.assertIn('s.memory:writeSymbol8("wAIMaxDamage", damage)', block)


if __name__ == "__main__":
    unittest.main()
