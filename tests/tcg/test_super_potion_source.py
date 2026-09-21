"""Super Potion AI decision + effect (trainer_cards.asm AIDecide_SuperPotion_
Phase08/Phase11, AIPlay_SuperPotion; core.asm CheckEnergyNeededForAttack
AfterDiscard; common.asm AIPickEnergyCardToDiscard/AICheckIfAttackIsHighRecoil).

The real arithmetic (heal-vs-KO thresholds, Phase11 start-slot selection,
the discard-simulation deficit math) is exercised for real by
lua_fixtures/super_potion_smoke.lua under LuaJIT -- see
test_lua_execution_smoke below, which is what actually caught two real bugs
while this card was being written (a broken discard-unusability
approximation, and an inverted Phase11 skip-vs-bail branch). These source-
shape checks only confirm the pieces are wired together.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/super_potion_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class SuperPotionSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")
        self.effects_src = read("src/tcg/duel/EffectCommands.lua")

    def test_super_potion_is_dispatched_and_marked_supported(self):
        self.assertIn(
            'elseif constantName == "SUPER_POTION" then\n    return self:_decideSuperPotion(phase)',
            self.ai_src,
        )
        self.assertIn('or constantName == "SUPER_POTION"', self.ai_src)
        # AI_TRAINER_PHASES already scaffolded SUPER_POTION at phases 8 and 11
        # before this card's logic existed; confirm it still does.
        self.assertIn('[8] = { "SUPER_POTION" }', self.ai_src)
        self.assertIn('"SUPER_POTION", "SUPER_ENERGY_RETRIEVAL"', self.ai_src)

    def test_decide_super_potion_covers_both_phases(self):
        start = self.ai_src.index("function AI:_decideSuperPotion")
        end = self.ai_src.index("function AI:_activeHasUsableBoostIfTakenDamageAttack", start)
        block = self.ai_src[start:end]
        self.assertIn("if phase == 8 then", block)
        self.assertIn("-- Phase11.", block)
        self.assertIn("discardEnergy = discard", block)

    def test_high_recoil_helper_preserves_source_polarity(self):
        block = self.ai_src[self.ai_src.index("function AI:_checkIfAttackIsHighRecoilForAI"):
                             self.ai_src.index("function AI:_pickEnergyCardToDiscard")]
        self.assertIn("self:processButDontUseAttack()", block)
        self.assertIn("return not self:_attackFlag(attack, 1, self.c.HIGH_RECOIL_F)", block)

    def test_energy_effects_are_registered(self):
        for label in (
            "SuperPotion_DamageCheck", "SuperPotion_PlayerSelection",
            "SuperPotion_HealAndDiscardEffect",
        ):
            self.assertIn(f'self:register("{label}"', self.effects_src)

    def test_effect_applies_heal_and_discards_exactly_the_chosen_card(self):
        block = self.effects_src[self.effects_src.index("SuperPotion_HealAndDiscardEffect"):
                                  self.effects_src.index("SuperPotion_HealAndDiscardEffect") + 700]
        self.assertIn("hTempRetreatCostCards", block)  # heal amount relay
        self.assertIn("hTemp_ffa0", block)              # discard relay
        self.assertIn("hTempPlayAreaLocation_ffa1", block)  # target slot relay
        self.assertIn("actor.duelOps:putCardInDiscardPile(discard)", block)

    def test_after_discard_checker_is_a_real_translation_not_an_approximation(self):
        # A prior draft approximated this by re-deriving totals from
        # checkEnergyNeededForAttack's already-computed fields, which does
        # not correctly model per-color deficits. The real translation
        # mutates the freshly recomputed wAttachedEnergies bytes directly.
        block = self.ai_src[self.ai_src.index("function AI:_checkEnergyNeededForAttackAfterDiscard"):]
        block = block[:block.index("\nend\n") + 5]
        self.assertIn('self.memory:address("wAttachedEnergies")', block)
        self.assertIn("DOUBLE_COLORLESS_ENERGY", block)
        self.assertIn('self.memory:write8("wram", base + color,', block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class SuperPotionExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Super Potion + Phase11 start-slot cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
