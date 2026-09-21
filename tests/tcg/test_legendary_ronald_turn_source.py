"""AIDoTurn_LegendaryRonald (engine/duel/ai/decks/legendary_ronald.asm), the
last of the five Legendary bosses' bespoke turn logic.

Unlike all four others, this one has NO anti-Mewtwo-mill check at all -- the
whole turn runs unconditionally, matching the real source's lack of any
HandleAIAntiMewtwoDeckStrategy call. Reuses AI:_tryToPlayMoltresLv37Directly
(factored out of Moltres's own translation once this file needed the exact
same byte-identical gate) TWICE: once in the initial pass and again in its
Professor-Oak repeat pass. No bespoke Energy-attach branch either (plain
processAndTryToPlayEnergy both times, same shape as Articuno's).

With this translation, all 19 confirmed AIActionTable_* labels (3 general +
16 boss/special decks) are natively handled by AI:doTurn; only a future,
unverified label still falls through to the turnSpecial adapter.

All of this is exercised for real by
lua_fixtures/legendary_ronald_turn_smoke.lua under LuaJIT (24 checks) -- see
test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/legendary_ronald_turn_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class LegendaryRonaldTurnSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")

    def _block(self, start_marker):
        start = self.ai_src.index(start_marker)
        candidates = []
        for marker in ("\nfunction AI:", "\nreturn AI"):
            try:
                candidates.append(self.ai_src.index(marker, start + 1))
            except ValueError:
                pass
        end = min(candidates)
        return self.ai_src[start:end]

    def test_no_anti_mill_check_at_all(self):
        block = self._block("function AI:doTurnLegendaryRonald")
        self.assertNotIn("handleAIAntiMewtwoDeckStrategy", block)
        # Phase 01 runs unconditionally, with no wrapping "if ... then" gate
        # around the whole turn (unlike every other Legendary boss).
        self.assertIn("AI_TRAINER_CARD_PHASE_01", block)

    def test_moltres_gate_reused_twice_via_the_shared_helper(self):
        block = self._block("function AI:doTurnLegendaryRonald")
        self.assertEqual(block.count("self:_tryToPlayMoltresLv37Directly()"), 2)
        # Not reimplemented inline here.
        self.assertNotIn("MAX_PLAY_AREA_POKEMON", block)
        self.assertNotIn("playerActions:playBasic", block)

    def test_shared_moltres_helper_used_by_both_moltres_and_ronald(self):
        helper = self._block("function AI:_tryToPlayMoltresLv37Directly")
        self.assertIn("self.playerActions:playBasic(self.c.MOLTRES_LV37)", helper)
        moltres = self._block("function AI:doTurnLegendaryMoltres")
        self.assertIn("self:_tryToPlayMoltresLv37Directly()", moltres)

    def test_professor_oak_repeat_pass_has_no_second_phase_15(self):
        block = self._block("function AI:doTurnLegendaryRonald")
        self.assertEqual(block.count("AI_TRAINER_CARD_PHASE_15"), 1)
        self.assertIn("AI_FLAG_USED_PROFESSOR_OAK", block)
        self.assertEqual(block.count("self:decidePlayPokemonCard()"), 4)

    def test_ronald_wired_into_do_turn_dispatch_and_all_19_labels_are_native(self):
        block = self._block("function AI:doTurn()")
        self.assertIn('label == "AIActionTable_LegendaryRonald"', block)
        self.assertIn("self:doTurnLegendaryRonald()", block)
        self.assertIn("19 confirmed labels", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class LegendaryRonaldTurnExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all AIDoTurn_LegendaryRonald cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
