"""Devolution Spray (Trainer, engine/duel/effect_functions.asm). Part of
the broader card-effects sweep -- the last three items closed on this pass
before the Supersonic confusion family.

Unlike Devolution Beam (an attack, either side, single devolution),
Devolution Spray only targets the Turn Duelist's own Play Area, and the
player may repeat the devolution multiple times on the same chosen card in
one use -- the source's own menu loop ("devolve again" vs. "done" after
each step), modeled here as a step count chosen up front (via context.
selection.devolutionSteps) rather than re-implementing that loop, since
this whole port's scope boundary is decision/effect logic, not menu/screen
presentation. Each step reuses the exact same cardOneStageBelow primitive
Devolution Beam already uses, carrying existing damage forward onto the
lower stage's printed max HP. Trainer cards don't fall through the shared
attack AFTER_DAMAGE/KO pipeline, so the source explicitly calls
HandleDestinyBondAndBetweenTurnKnockOuts itself -- reusing the same
combat.status:handleDestinyBondSubstatus + combat.knockouts:
handlePendingResolution pair Curse's damage-transfer effect already calls
for the identical reason.

All of this is exercised for real by
lua_fixtures/devolution_spray_smoke.lua under LuaJIT (16 checks) -- see
test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/devolution_spray_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class DevolutionSpraySourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def _block(self, start_marker):
        start = self.src.index(start_marker)
        end = self.src.index("\n  end)", start)
        return self.src[start:end]

    def test_evolution_check_scans_own_side_only(self):
        block = self._block('self:register("DevolutionSpray_PlayAreaEvolutionCheck"')
        self.assertIn("DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA", block)
        self.assertNotIn("swapTurn", block)

    def test_player_selection_rejects_basic_and_relays_step_count(self):
        block = self._block('self:register("DevolutionSpray_PlayerSelection"')
        self.assertIn("s.c.BASIC", block)
        self.assertIn("selectDevolutionSteps", block)
        self.assertIn("effectState.devolutionPlayArea = slot", block)
        self.assertIn("effectState.devolutionSteps = steps", block)

    def test_devolution_effect_loops_steps_and_calls_knockout_resolution(self):
        block = self._block('self:register("DevolutionSpray_DevolutionEffect"')
        self.assertIn("for _ = 1, steps do", block)
        self.assertIn("cardOneStageBelow(s, actor, slot)", block)
        self.assertIn("actor.duelOps:putCardInDiscardPile(oldDeckIndex)", block)
        self.assertIn("combat.status:handleDestinyBondSubstatus()", block)
        self.assertIn("combat.knockouts:handlePendingResolution()", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class DevolutionSprayExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Devolution Spray effect cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
