"""Electrode's Chain Lightning (engine/duel/effect_functions.asm), part of
the broader card-effects sweep.

Fixed 10 damage, then an extra 10 to every Play Area Pokemon -- both
sides, arena included -- that shares the Defending Pokemon's color
(skipped entirely if the Defending Pokemon is Colorless, confirmed via
the real ASM's `cp COLORLESS / ret z`). Reuses the already-registered
Combat:dealDamageToPlayAreaPokemon and Status:getPlayAreaCardColor rather
than reimplementing color lookups or damage application, and manually
brackets each pass with swapTurn (mirroring the source's own SwapTurn
calls) rather than delegating the swap to dealDamageToPlayAreaPokemon's
targetNonTurn option, since the loop itself needs to read colors on
whichever side is current "turn".

Exercised for real by lua_fixtures/chain_lightning_effect_smoke.lua under
LuaJIT (17 checks) -- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/chain_lightning_effect_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ChainLightningEffectSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def test_chain_lightning_sets_fixed_damage_and_bails_on_colorless(self):
        start = self.src.index('self:register("ChainLightningEffect"')
        end = self.src.index("\n  end)", start)
        self.block = self.src[start:end]
        self.assertIn("s:_setDefiniteDamage(10)", self.block)
        self.assertIn("if defenderColor == s.c.COLORLESS then return false end", self.block)

    def test_chain_lightning_hits_both_sides_with_correct_self_damage_flag(self):
        start = self.src.index('self:register("ChainLightningEffect"')
        end = self.src.index("\n  end)", start)
        block = self.src[start:end]
        self.assertIn("s.status:getPlayAreaCardColor(slot) == defenderColor", block)
        self.assertIn(
            "combat:dealDamageToPlayAreaPokemon(slot, 10, false,", block)
        self.assertIn("damageSameColorBench(false)", block)
        self.assertIn("damageSameColorBench(true)", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class ChainLightningEffectExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all chain lightning effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
