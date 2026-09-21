"""AIDoTurn_LegendaryArticuno (engine/duel/ai/decks/legendary_articuno.asm),
fourth of the five Legendary bosses' bespoke turn logic, and the simplest.

Phase 01 runs before the anti-Mewtwo-mill check (like Dragonite's), but
unlike Zapdos/Moltres/Dragonite, this one has NO bespoke Energy-attach
branch of its own: Articuno's whole specialization
(ScoreLegendaryArticunoCards -- prioritizing Lapras to 3 Energy, then
Articuno, then Dewgong, then Seel, gated on the Player having 3+ prizes
left) already lives inside the common energy-scoring pipeline via the
already-translated AI:_legendaryArticunoEnergyDeltas (used by plain
AIProcessAndTryToPlayEnergy for every deck, not just this one). So this
routine is just the turn-flow skeleton plus a Professor-Oak repeat pass
(phases 01/02, play, retreat, 10, energy, play again -- no phase 13/15 on
the repeat).

All of this is exercised for real by
lua_fixtures/legendary_articuno_turn_smoke.lua under LuaJIT (14 checks) --
see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/legendary_articuno_turn_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class LegendaryArticunoTurnSourceTests(unittest.TestCase):
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

    def test_phase_01_runs_before_the_anti_mill_check(self):
        block = self._block("function AI:doTurnLegendaryArticuno")
        init_pos = block.index("self:initTurnVars()")
        phase1_pos = block.index("AI_TRAINER_CARD_PHASE_01")
        anti_mill_pos = block.index("self:handleAIAntiMewtwoDeckStrategy()")
        self.assertLess(init_pos, phase1_pos)
        self.assertLess(phase1_pos, anti_mill_pos)

    def test_no_bespoke_energy_branch_reuses_the_common_articuno_scoring(self):
        block = self._block("function AI:doTurnLegendaryArticuno")
        self.assertIn("self:processAndTryToPlayEnergy()", block)
        self.assertNotIn("_tryToPlayEnergyCard", block)
        self.assertNotIn("ARTICUNO", block)
        # The real specialization is already wired generically.
        pipeline = self._block("function AI:processAndTryToPlayEnergy")
        self.assertIn("_legendaryArticunoEnergyDeltas", pipeline)

    def test_professor_oak_repeat_pass_has_no_second_phase_13_or_15(self):
        block = self._block("function AI:doTurnLegendaryArticuno")
        self.assertEqual(block.count("AI_TRAINER_CARD_PHASE_13"), 1)
        self.assertEqual(block.count("AI_TRAINER_CARD_PHASE_15"), 1)
        self.assertIn("AI_FLAG_USED_PROFESSOR_OAK", block)
        self.assertEqual(block.count("self:decidePlayPokemonCard()"), 4)

    def test_articuno_wired_into_do_turn_dispatch(self):
        block = self._block("function AI:doTurn()")
        self.assertIn('label == "AIActionTable_LegendaryArticuno"', block)
        self.assertIn("self:doTurnLegendaryArticuno()", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class LegendaryArticunoTurnExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all AIDoTurn_LegendaryArticuno cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
