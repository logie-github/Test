from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class SpecialAttackAIPolicySourceTests(unittest.TestCase):
    def test_high_recoil_policy_preserves_deck_specific_branches(self):
        src = read("src/tcg/duel/AI.lua")
        start = src.index("function AI:_applyRecoilAIScore")
        end = src.index("function AI:_healingAttackBonus", start)
        block = src[start:end]
        for name in ("BOOM_BOOM_SELFDESTRUCT_DECK_ID", "POWER_GENERATOR_DECK_ID",
                     "ZAPPING_SELFDESTRUCT_DECK_ID", "ROCK_CRUSHER_DECK_ID"):
            self.assertIn(name, block)
        self.assertIn("_checkHighRecoilBenchKOs(1, benchDamage)", block)
        self.assertIn("activeId == self.c.CHANSEY", block)
        self.assertIn("activeId == self.c.MAGNEMITE_LV13", block)
        self.assertIn("activeId == self.c.WEEZING", block)

    def test_heal_and_defending_ko_scoring_match_source_shape(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:_healingAttackBonus", src)
        self.assertIn("HEALING_EQUALS_10_HP", src)
        self.assertIn("HEALING_EQUALS_DAMAGE_DEALT", src)
        self.assertIn("score = satAdd(score, 5)", src)
        self.assertIn("if attackIsNonDamaging then score = satSub(score, 5) end", src)

    def test_special_attack_dispatch_covers_every_source_card(self):
        src = read("src/tcg/duel/AI.lua")
        start = src.index("function AI:_handleSpecialAIAttack")
        end = src.index("-- GetAIScoreOfAttack:: complete", start)
        block = src[start:end]
        names = (
            "NIDORANF", "ODDISH", "BELLSPROUT", "EXEGGUTOR", "SCYTHER", "KRABBY",
            "VAPOREON_LV29", "ELECTRODE_LV42", "MAROWAK_LV26", "MEW_LV23",
            "JIGGLYPUFF_LV13", "PORYGON", "MEWTWO_ALT_LV60", "MEWTWO_LV60",
            "NINETALES_LV35", "ZAPDOS_LV68", "KANGASKHAN", "DUGTRIO",
            "ELECTRODE_LV35", "GOLDUCK", "DRAGONAIR",
        )
        for name in names:
            self.assertIn(f"self.c.{name}", block)
        self.assertIn("earthquake_pointer_walk_no_sentinel", block)
        self.assertIn("self.rng:random(3)", block)
        self.assertIn("_countNumberOfSetUpBenchPokemon", block)

    def test_status_scoring_preserves_snorlax_and_poison_quirks(self):
        src = read("src/tcg/duel/AI.lua")
        start = src.index("function AI:getAIScoreOfAttack")
        end = src.index("-- CheckWhetherToSwitchToFirstAttack::.", start)
        block = src[start:end]
        self.assertIn("defenderId ~= self.c.SNORLAX", block)
        self.assertIn("bit.band(poison, 0x40) == 0", block)
        self.assertIn("ENCOURAGE_THIS_ATTACK_F", block)


if __name__ == "__main__":
    unittest.main()
