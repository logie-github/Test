import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class GeneralAIPokemonPowerSourceTests(unittest.TestCase):
    def test_common_power_ai_families_are_native(self):
        src = read("src/tcg/duel/AI.lua")
        for fn in (
            "handleAIDamageSwap", "handleAIPkmnPowers", "handleAICowardice",
            "_aiHealTarget", "_aiShiftColor", "_aiPeekTarget",
            "_aiStrangeBehaviorTransfers", "_aiCurseTransfer",
        ):
            self.assertIn(f"function AI:{fn}", src)
        for card in ("VILEPLUME", "VENOMOTH", "MANKEY", "SLOWBRO", "GENGAR", "TENTACOOL", "ALAKAZAM"):
            self.assertIn(f"self.c.{card}", src)

    def test_power_rng_and_source_quirks_are_preserved(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:_commonPowerInitialEligible", src)
        self.assertIn("self.rng:random(50) >= 3", src)
        self.assertIn('readSymbol8("wAIPeekedPrizes")', src)
        self.assertIn("return lastNoEnergy or lastCandidate", src)
        self.assertIn("lowestHP == 10", src)
        self.assertIn("slot = self.c.PLAY_AREA_ARENA", src)
        self.assertIn("count = count - 1", src)
        self.assertIn("self:_chooseRandomlyNotToDoAction()", src)

    def test_manual_power_effect_handlers_are_registered(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        labels = (
            "DamageSwap_CheckDamage", "DamageSwap_SelectAndSwapEffect", "DamageSwap_SwapEffect",
            "Cowardice_CheckUseAndBench", "Cowardice_PlayerSelectEffect", "Cowardice_ReturnToHandEffect",
            "Heal_OncePerTurnCheck", "Heal_RemoveDamageEffect",
            "Shift_OncePerTurnCheck", "Shift_PlayerSelectEffect", "Shift_ChangeColorEffect",
            "Peek_OncePerTurnCheck", "Peek_SelectEffect",
            "StrangeBehavior_CheckDamage", "StrangeBehavior_SelectAndSwapEffect", "StrangeBehavior_SwapEffect",
            "Curse_CheckDamageAndBench", "Curse_PlayerSelectEffect", "Curse_TransferDamageEffect",
        )
        for label in labels:
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn("USED_PKMN_POWER_THIS_TURN_F", src)
        self.assertIn("CAN_EVOLVE_THIS_TURN", src)
        self.assertIn("HAS_CHANGED_COLOR_F", src)
        self.assertIn("handlePendingResolution", src)


if __name__ == "__main__":
    unittest.main()
