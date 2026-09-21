"""AIDoTurn_LegendaryDragonite (engine/duel/ai/decks/legendary_dragonite.asm),
third of the five Legendary bosses' bespoke turn logic.

Unlike Zapdos's and Moltres's, phase 01 runs *before* the anti-Mewtwo-mill
check here, matching AIMainTurnLogic's own ordering rather than the other
two bosses'. The Energy-attach branch force-attaches directly to the Arena
when it's Kangaskhan with no Energy attached yet (single-card gate, reusing
AI:_tryToPlayEnergyCard, same shape as Zapdos's/Moltres's). It also has its
own short Professor-Oak repeat pass (phases 01/02/07/10/11 again, retreat
and energy again, but no phase 15 on the repeat), distinct from
AIMainTurnLogic's longer one and entirely absent from Zapdos/Moltres.

All of this is exercised for real by
lua_fixtures/legendary_dragonite_turn_smoke.lua under LuaJIT (18 checks) --
see test_lua_execution_smoke below, which is what actually caught an
authoring mistake in the fixture's own first draft: the "Professor Oak
used" case expected decidePlayPokemonCard to be called 3 times, undercounting
by one. AIDoTurn_LegendaryDragonite calls it twice per pass (once before the
energy-attach block, once after) and runs two passes when Professor Oak was
used, for 4 calls total -- recounting the real source line by line confirmed
AI.lua's translation was already correct and only the test's count was off.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/legendary_dragonite_turn_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class LegendaryDragoniteTurnSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")

    def _block(self, start_marker):
        start = self.ai_src.index(start_marker)
        # Any function body here never contains another top-level "function
        # AI:" definition or the file's final "return AI", so the nearer of
        # those two is a stable boundary regardless of what gets inserted or
        # removed after this function in the file.
        candidates = []
        for marker in ("\nfunction AI:", "\nreturn AI"):
            try:
                candidates.append(self.ai_src.index(marker, start + 1))
            except ValueError:
                pass
        end = min(candidates)
        return self.ai_src[start:end]

    def test_phase_01_runs_before_the_anti_mill_check(self):
        block = self._block("function AI:doTurnLegendaryDragonite")
        init_pos = block.index("self:initTurnVars()")
        phase1_pos = block.index("AI_TRAINER_CARD_PHASE_01")
        anti_mill_pos = block.index("self:handleAIAntiMewtwoDeckStrategy()")
        self.assertLess(init_pos, phase1_pos)
        self.assertLess(phase1_pos, anti_mill_pos)

    def test_energy_branch_is_kangaskhan_single_card_gate(self):
        block = self._block("function AI:doTurnLegendaryDragonite")
        self.assertIn("arenaCardId == self.c.KANGASKHAN", block)
        self.assertIn("self:_tryToPlayEnergyCard(self.c.PLAY_AREA_ARENA, handEnergy)", block)

    def test_professor_oak_repeat_pass_has_no_second_phase_15(self):
        block = self._block("function AI:doTurnLegendaryDragonite")
        self.assertEqual(block.count("AI_TRAINER_CARD_PHASE_15"), 1)
        self.assertIn("AI_FLAG_USED_PROFESSOR_OAK", block)
        # 2 decidePlayPokemonCard calls per pass (before/after energy-attach),
        # x2 passes when Professor Oak was used = 4 total call sites.
        self.assertEqual(block.count("self:decidePlayPokemonCard()"), 4)
        self.assertEqual(block.count("self:processRetreat()"), 2)

    def test_dragonite_wired_into_do_turn_dispatch(self):
        block = self._block("function AI:doTurn()")
        self.assertIn('label == "AIActionTable_LegendaryDragonite"', block)
        self.assertIn("self:doTurnLegendaryDragonite()", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class LegendaryDragoniteTurnExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all AIDoTurn_LegendaryDragonite cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
