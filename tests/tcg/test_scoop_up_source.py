"""Scoop Up AI decision + effect (trainer_cards.asm AIDecide_ScoopUp,
AIPlay_ScoopUp; effect_functions.asm ScoopUp_BenchCheck/PlayerSelection/
ReturnToHandEffect).

The real arithmetic (the KO/usability/energy-in-hand short-circuit, the
status/retreat-cost gate, and the 70%-max-HP damage threshold computed via
the source's own integer floor(rawDamage / floor(maxHP/10)) division rather
than a floating-point approximation) is exercised for real by
lua_fixtures/scoop_up_smoke.lua under LuaJIT -- see test_lua_execution_smoke
below. These source-shape checks only confirm the pieces are wired together
and that the Legendary Articuno/Ronald deck branches fail closed rather than
being approximated by the general path.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/scoop_up_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ScoopUpSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")
        self.effects_src = read("src/tcg/duel/EffectCommands.lua")

    def test_is_dispatched_and_marked_supported(self):
        self.assertIn(
            'elseif constantName == "SCOOP_UP" then\n'
            "    return self:_decideScoopUp()",
            self.ai_src,
        )
        self.assertIn('or constantName == "SCOOP_UP"', self.ai_src)
        self.assertIn('[10] = { "POTION", "GUST_OF_WIND", "ENERGY_RETRIEVAL", "MR_FUJI", "SCOOP_UP" },',
                       self.ai_src)

    def test_decide_fails_closed_on_specialized_decks(self):
        block = self.ai_src[self.ai_src.index("function AI:_decideScoopUp"):
                             self.ai_src.index("-- AICheckIfAttackIsHighRecoil")]
        self.assertIn("LEGENDARY_ARTICUNO_DECK_ID", block)
        self.assertIn("LEGENDARY_RONALD_DECK_ID", block)
        self.assertIn('"untranslated_ai_scoop_up_special_deck"', block)
        self.assertIn("checkIfAnyAttackKnocksOutDefendingCard", block)
        self.assertIn("_lookForEnergyNeededInHand", block)
        self.assertIn("countNumberOfEnergyCardsAttached", block)
        self.assertIn("decideBenchPokemonToSwitchTo", block)

    def test_effects_are_registered(self):
        for label in ("ScoopUp_BenchCheck", "ScoopUp_PlayerSelection", "ScoopUp_ReturnToHandEffect"):
            self.assertIn(f'self:register("{label}"', self.effects_src)

    def test_return_to_hand_effect_only_scoops_a_basic_pokemon(self):
        block = self.effects_src[self.effects_src.index('self:register("ScoopUp_ReturnToHandEffect"'):
                                  self.effects_src.index('self:register("Potion_DamageCheck"')]
        self.assertIn("row.stage == s.c.BASIC", block)
        self.assertIn("a.duelOps:movePlayAreaCardToDiscardPile(scoopSlot)", block)
        self.assertIn("a.duelOps:clearAllStatusConditions()", block)
        self.assertIn("a.duelOps:swapPlayAreaPokemon(benchSlot, s.c.PLAY_AREA_ARENA)", block)
        self.assertIn("a.duelOps:shiftAllPokemonToFirstPlayAreaSlots()", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class ScoopUpExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Scoop Up AI decision cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
