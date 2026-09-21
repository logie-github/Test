import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def text(path):
    return (ROOT / path).read_text(encoding="utf-8")


class CommonDamageSourceTests(unittest.TestCase):
    def test_target_damage_modifier_order_matches_source(self):
        src = text("src/tcg/duel/Combat.lua")
        start = src.index("function Combat:applyDamageModifiers(baseDamage)")
        end = src.index("function Combat:applyDamageModifiersToSelf", start)
        block = src[start:end]
        ordered = [
            "handleDoubleDamageSubstatus",
            "_attackColor()",
            "weakness, resistance",
            "_applyAttachedPlusPower",
            "_applyAttachedDefender",
            "handleDamageReduction",
        ]
        positions = [block.index(token) for token in ordered]
        self.assertEqual(positions, sorted(positions))
        self.assertIn("UNAFFECTED_BY_WEAKNESS_RESISTANCE_F", block)
        self.assertIn('wDamageEffectiveness', block)

    def test_common_reduction_substatuses_and_power_quirks_are_native(self):
        src = text("src/tcg/duel/Status.lua")
        for token in (
            "SUBSTATUS1_NO_DAMAGE_STIFFEN",
            "SUBSTATUS1_NO_DAMAGE_WITHDRAW",
            "SUBSTATUS1_NO_DAMAGE_HIDE_IN_SHELL",
            "SUBSTATUS1_NO_DAMAGE_SCRUNCH",
            "SUBSTATUS1_REDUCE_BY_10",
            "SUBSTATUS1_REDUCE_BY_20",
            "SUBSTATUS1_PREVENT_LESS_THAN_40",
            "SUBSTATUS1_HALVE_DAMAGE",
            "SUBSTATUS2_REDUCE_BY_20",
            "SUBSTATUS2_POUNCE",
            "SUBSTATUS2_GROWL",
            "self.c.MR_MIME",
            "self.c.KABUTO",
            "sourceHalveDamage",
        ):
            self.assertIn(token, src)
        self.assertIn("documented `sla d` bug", src)

    def test_prevention_confusion_and_status_queue_filter_are_translated(self):
        combat = text("src/tcg/duel/Combat.lua")
        status = text("src/tcg/duel/Status.lua")
        for token in (
            "CheckSelfConfusionDamage::",
            "_writeDamage(20)",
            "applyDamageModifiersToSelf(self:_readDamage())",
            "ApplyTransparencyIfApplicable::",
            "getNonTurn(self.c.DUELVARS_ARENA_CARD_SUBSTATUS2)",
        ):
            self.assertIn(token, combat)
        for token in (
            "HandleNoDamageOrEffectSubstatus::",
            "NO_DAMAGE_OR_EFFECT_FLY",
            "NO_DAMAGE_OR_EFFECT_BARRIER",
            "NO_DAMAGE_OR_EFFECT_AGILITY",
            "NO_DAMAGE_OR_EFFECT_NSHIELD",
            "NO_DAMAGE_OR_EFFECT_TRANSPARENCY",
            "side == self.duelVars:turn()",
        ):
            self.assertIn(token, status)
        self.assertNotIn('untranslated_confusion', combat)
        self.assertNotIn('untranslated_pluspower_defender', combat)

    def test_pluspower_defender_counts_source_location_bytes(self):
        src = text("src/tcg/duel/DuelOps.lua")
        start = src.index("function DuelOps:countCardIDInLocation")
        block = src[start:src.index("function DuelOps:moveCardToDiscardPileIfInPlayArea", start)]
        self.assertIn("self:_read(deckIndex) == location", block)
        self.assertIn("self.cardData:getCardIDFromDeckIndex(deckIndex) == cardId", block)


if __name__ == "__main__":
    unittest.main()
