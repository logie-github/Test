import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class GenericAIEffectSourceTests(unittest.TestCase):
    def test_expected_damage_wrapper_inventory_matches_source_cluster(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        block = src[src.index("local expectedDamage = {"):src.index("local function updateExpectedAIDamage")]
        labels = re.findall(r"^\s+([A-Za-z_][A-Za-z0-9_]*_AIEffect)\s*=\s*\{", block, re.M)
        self.assertEqual(len(labels), 39)
        for token in (
            "SpitPoison_AIEffect = { 5, 0, 10 }",
            "Thrash_AIEffect = { 35, 30, 40 }",
            "StoneBarrage_AIEffect = { 10, 0, 100 }",
            "DragoniteLv41Slam_AIEffect = { 30, 0, 60 }",
        ):
            self.assertIn(token, block)
        self.assertIn('self:register("SetExpectedAIDamage"', src)
        self.assertIn('s:_writeWord("wDamage", average)', src)

    def test_poison_expectation_inventory_preserves_existing_poison_short_circuit(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        block = src[src.index("local poisonExpected = {"):src.index("local function extraWaterEnergyDamageBonus")]
        labels = re.findall(r"^\s+([A-Za-z_][A-Za-z0-9_]*_AIEffect)\s*=\s*\{", block, re.M)
        self.assertEqual(len(labels), 13)
        self.assertIn('self:register("UpdateExpectedAIDamage"', src)
        self.assertIn('self:register("UpdateExpectedAIDamage_AccountForPoison"', src)
        self.assertIn("actor.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD_STATUS)", src)
        self.assertIn("bit.bor(s.c.POISONED, s.c.DOUBLE_POISONED)", src)
        self.assertIn('local current = s:_readWord("wDamage") % 0x100', src)

    def test_water_bonus_family_is_shared_by_before_damage_and_ai(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        block = src[src.index("local waterBonus = {"):src.index("-- effect_functions.asm shared status primitives")]
        labels = re.findall(r"^\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{", block, re.M)
        self.assertEqual(len(labels), 8)
        for token in (
            "OmastarWaterGunEffect = { 1, 1 }",
            "HydroPumpEffect = { 3, 0 }",
            "VaporeonWaterGunEffect = { 2, 1 }",
            "LaprasWaterGunEffect = { 1, 0 }",
        ):
            self.assertIn(token, block)
        self.assertIn('self:register("ApplyExtraWaterEnergyDamageBonus"', src)
        self.assertIn('s.memory:readSymbol8("wMetronomeEnergyCost")', src)
        self.assertIn("if colorlessNeeded ~= 0 and total == water then", src)
        self.assertIn("bonusUnits = math.min(2, bonusUnits)", src)
        self.assertIn("s:_addToDamage(bonusUnits * 10)", src)

    def test_generic_ai_handler_inventory_now_covers_60_of_81_unique_ai_commands(self):
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
            src[src.index("local waterBonus = {"):src.index("-- effect_functions.asm shared status primitives")],
            re.M,
        )
        self.assertEqual(len(set(expected + poison + water)), 60)


if __name__ == "__main__":
    unittest.main()
