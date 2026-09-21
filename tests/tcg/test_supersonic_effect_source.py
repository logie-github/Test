"""Supersonic confusion attack family (Zubat/Nidorina/Lickitung/Shellder/
Tentacruel, engine/duel/effect_functions.asm). Part of the broader card-
effects sweep: adds the last three (Lickitung/Shellder/Tentacruel) to the
pre-existing shared `supersonic` handler Zubat and Nidorina already used --
that handler's own logic needed no changes, only the two extra
registrations. Neither the pre-existing two nor the new three had ever been
exercised under real LuaJIT execution before this change.

Source shape (identical across all five): call Confusion50PercentEffect;
call nc, SetNoEffectFromStatus -- coin heads confuses the Defending
Pokemon, coin tails marks "no effect" rather than silently doing nothing.

All of this is exercised for real by
lua_fixtures/supersonic_effect_smoke.lua under LuaJIT (25 checks) -- see
test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/supersonic_effect_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class SupersonicEffectSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def test_all_five_registered_on_the_shared_handler(self):
        start = self.src.index("local function supersonic(s)")
        end = self.src.index("\n\n", start)
        block = self.src[start:end]
        for name in (
            "ZubatSupersonicEffect", "NidorinaSupersonicEffect",
            "LickitungSupersonicEffect", "ShellderSupersonicEffect", "TentacruelSupersonicEffect",
        ):
            self.assertIn(f'self:register("{name}", supersonic)', block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class SupersonicEffectExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Supersonic effect cases passed", result.stdout)
        # Not a plain "FAIL" substring check: EFFECT_FAILED_NO_EFFECT is a
        # legitimate passing check's expected value and contains "FAIL".
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
