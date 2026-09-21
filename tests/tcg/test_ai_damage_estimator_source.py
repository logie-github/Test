from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
AI = (ROOT / "src/tcg/duel/AI.lua").read_text()


class AIDamageEstimatorSourceTests(unittest.TestCase):
    def test_forward_estimator_uses_defender_poison(self):
        block = AI[AI.index("function AI:estimateDamageVersusDefendingCard"):
                   AI.index("local function clampSourceDamage")]
        self.assertIn("getNonTurn(self.c.DUELVARS_ARENA_CARD_STATUS)", block)
        self.assertIn("poison = 20", block)
        self.assertIn("poison = 10", block)

    def test_bench_forward_clears_switch_sensitive_active_state(self):
        helper = AI[AI.index("function AI:_withClearedArenaSwitchStatuses"):
                    AI.index("function AI:_calculateForwardDamageFromSlot")]
        self.assertIn("DUELVARS_ARENA_CARD_SUBSTATUS1", helper)
        self.assertIn("DUELVARS_ARENA_CARD_SUBSTATUS2", helper)
        self.assertIn("DUELVARS_ARENA_CARD_CHANGED_RESISTANCE", helper)
        bench = AI[AI.index("function AI:_estimateDamageFromPlayArea"):
                   AI.index("function AI:checkIfAnyAttackKnocksOutDefendingCard")]
        self.assertIn("_withClearedArenaSwitchStatuses(calculate)", bench)

    def test_reverse_estimator_is_slot_aware(self):
        block = AI[AI.index("function AI:_calculateReverseDamageToSlot"):
                   AI.index("function AI:estimateDamageFromDefendingPokemon")]
        self.assertIn("CARD_LOCATION_PLAY_AREA, slot", block)
        self.assertIn("if slot == self.c.PLAY_AREA_ARENA then", block)
        self.assertIn("handleDamageReduction", block)
        self.assertIn("poison = 40", block)
        self.assertIn("poison = 20", block)

    def test_reverse_estimator_does_not_use_no_damage_prevention(self):
        start = AI.index("function AI:estimateDamageFromDefendingPokemon")
        end = AI.index("-- CheckIfDefendingPokemonCanKnockOut::", start)
        block = AI[start:end]
        self.assertNotIn("_applyNoDamageOrEffectPrevention", block)
        self.assertIn('writeSymbol8("hTempPlayAreaLocation_ff9d", self.c.PLAY_AREA_ARENA)', block)
        self.assertIn("receiverSlot", block)

    def test_bench_exact_ko_uses_reverse_estimator_directly(self):
        start = AI.index("function AI:_defenderCanExactKOPlayArea")
        end = AI.index("-- SetAIRetreatFlags::", start)
        block = AI[start:end]
        self.assertIn("estimateDamageFromDefendingPokemon(attackIndex, slot)", block)
        self.assertNotIn("DUELVARS_ARENA_CARD_ATTACHED_DEFENDER", block)
        self.assertIn("estimate.damage == hp", block)


if __name__ == "__main__":
    unittest.main()
