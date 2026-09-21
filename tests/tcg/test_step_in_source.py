"""Slowbro's Step In Power (engine/duel/effect_functions.asm). Part of the
broader card-effects sweep.

Unlike the already-translated Cowardice/Heal/Shift manual Powers (usable
from anywhere in the Play Area), Step In can ONLY be used from the Bench --
the source's own gate fails immediately ("CanOnlyBeUsedOnTheBenchText")
when the card is currently Active. After swapping into Active, the used-
this-turn flag is set unconditionally on PLAY_AREA_ARENA (no +slot offset
in the source), since by then this card IS the Arena occupant, not the
Bench slot it started at.

All of this is exercised for real by lua_fixtures/step_in_smoke.lua under
LuaJIT (9 checks) -- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/step_in_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class StepInSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def _block(self, start_marker):
        start = self.src.index(start_marker)
        end = self.src.index("\n  end)", start)
        return self.src[start:end]

    def test_bench_check_fails_outright_when_already_active(self):
        block = self._block('self:register("StepIn_BenchCheck"')
        self.assertIn("if slot == s.c.PLAY_AREA_ARENA then return true end", block)

    def test_switch_effect_marks_the_new_arena_slot_not_the_old_bench_slot(self):
        block = self._block('self:register("StepIn_SwitchEffect"')
        self.assertIn("actor.duelOps:swapArenaWithBenchPokemon(slot)", block)
        self.assertIn("markPowerUsed(s, actor, s.c.PLAY_AREA_ARENA)", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class StepInExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Step In effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
