"""Imposter Professor Oak AI decision + effect (trainer_cards.asm AIDecide_
ImposterProfessorOak, AIPlay_ImposterProfessorOak; effect_functions.asm
ImposterProfessorOakEffect).

The real threshold arithmetic (which of the two card-count branches applies,
and the exact-boundary case) is exercised for real by
lua_fixtures/imposter_professor_oak_smoke.lua under LuaJIT -- see
test_lua_execution_smoke below. These source-shape checks only confirm the
pieces are wired together and that the effect targets the opponent's hand
via ReturnCardToDeck (not PutCardInDiscardPile, unlike ordinary Professor
Oak) with the source's own SwapTurn/ExchangeRNG/ShuffleDeck ordering.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/imposter_professor_oak_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ImposterProfessorOakSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")
        self.effects_src = read("src/tcg/duel/EffectCommands.lua")

    def test_is_dispatched_and_marked_supported(self):
        self.assertIn(
            'elseif constantName == "IMPOSTER_PROFESSOR_OAK" then\n'
            "    return self:_decideImposterProfessorOak()",
            self.ai_src,
        )
        self.assertIn('IMPOSTER_PROFESSOR_OAK = true', self.ai_src)  # AI_TRAINER_SUPPORTED table
        self.assertIn('"POKEMON_BREEDER",\n    "IMPOSTER_PROFESSOR_OAK", "FULL_HEAL" }', self.ai_src)

    def test_decide_reads_non_turn_duelist_and_matches_both_branches(self):
        block = self.ai_src[self.ai_src.index("function AI:_decideImposterProfessorOak"):
                             self.ai_src.index("-- AICheckIfAttackIsHighRecoil")]
        self.assertIn("getNonTurn(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)", block)
        self.assertIn("getNonTurn(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)", block)
        self.assertIn("self.c.DECK_SIZE - 14", block)
        self.assertIn("handCount >= 9", block)
        self.assertIn("handCount < 6", block)

    def test_effect_is_registered_and_returns_to_deck_not_discard(self):
        self.assertIn('self:register("ImposterProfessorOakEffect"', self.effects_src)
        start = self.effects_src.index('self:register("ImposterProfessorOakEffect"')
        end = self.effects_src.index('self:register(', start + 1)
        block = self.effects_src[start:end]
        self.assertIn("a.duelVars:swapTurn()", block)
        self.assertIn("a.duelOps:returnCardToDeck(deckIndex)", block)
        self.assertNotIn("putCardInDiscardPile", block)
        self.assertIn("a.combat.setup:exchangeRNG()", block)
        self.assertIn("a.duelOps:shuffleDeck()", block)
        # SwapTurn into the effect, plus a swap-back on both the normal exit
        # and the ExchangeRNG-failure early-return path.
        self.assertEqual(block.count("a.duelVars:swapTurn()"), 3)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class ImposterProfessorOakExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Imposter Professor Oak AI decision cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
