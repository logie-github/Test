"""Mew/Voltorb's Psywave (engine/duel/effect_functions.asm), part of the
broader card-effects sweep.

GetEnergyAttachedMultiplierDamage swaps to the Defending Pokemon, counts
the Energy CARDS attached to its Arena card, swaps back, and writes 10x
that count directly into wDamage. This reuses the already-translated
DuelOps:countNumberOfEnergyCardsAttached (which folds Double Colorless
Energy's doubled point count back down to 1 card) rather than the raw
energy-POINT count. Unlike SetDefiniteDamage, it does not touch the AI
damage hint fields -- the real command list has no separate AI_EFFECT
entry for this attack, so the AI cannot preview the exact damage.

Exercised for real by lua_fixtures/psywave_effect_smoke.lua under LuaJIT
(20 checks) -- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/psywave_effect_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class PsywaveEffectSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def test_psywave_swaps_counts_swaps_and_writes_word_damage_directly(self):
        start = self.src.index('self:register("PsywaveEffect"')
        end = self.src.index("\n  end)", start)
        block = self.src[start:end]
        self.assertEqual(block.count("actor.duelVars:swapTurn()"), 2)
        self.assertIn("actor.duelOps:countNumberOfEnergyCardsAttached(s.c.PLAY_AREA_ARENA)", block)
        self.assertIn('s:_writeWord("wDamage", count * 10)', block)
        self.assertNotIn("_setDefiniteDamage", block)
        self.assertNotIn("wAIMinDamage", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class PsywaveEffectExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all psywave effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
