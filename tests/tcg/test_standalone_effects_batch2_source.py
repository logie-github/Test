"""A second batch of standalone card effects (engine/duel/effect_functions.
asm), part of the broader card-effects sweep.

Clairvoyance/InvisibleWall/NeutralizingShield/KabutoArmor/ThickSkinned:
pure EFFECTCMDTYPE_INITIAL_EFFECT_1 stubs (`scf; ret` in the source, always
carry) -- confirmed each real command list uses only that one phase, the
same "triggered-only Power" shape as the already-translated Quickfreeze/
Firegiver/HealingWind/PealOfThunder/Transparency/PrehistoricPower stubs, so
all five reuse the existing triggeredOnly handler.
Clamp: heads keeps the printed damage and jumps straight into the plain
(unconditional) ParalysisEffect, already registered elsewhere in this file
and reused directly by name; tails zeroes damage and marks the attack
unsuccessful.

All of this is exercised for real by
lua_fixtures/standalone_effects_batch2_smoke.lua under LuaJIT (12 checks)
-- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/standalone_effects_batch2_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class StandaloneEffectsBatch2SourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def test_five_stubs_reuse_triggered_only_handler(self):
        for name in (
            "ClairvoyanceEffect", "InvisibleWallEffect", "NeutralizingShieldEffect",
            "KabutoArmorEffect", "ThickSkinnedEffect",
        ):
            self.assertIn(f'self:register("{name}", triggeredOnly)', self.src)

    def test_clamp_reuses_paralysis_effect_on_heads(self):
        start = self.src.index('self:register("ClampEffect"')
        end = self.src.index("\n  end)", start)
        block = self.src[start:end]
        self.assertIn('s.handlers["ParalysisEffect"](s, context)', block)
        self.assertIn("s:_setDefiniteDamage(0)", block)
        self.assertIn("s:_setWasUnsuccessful()", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class StandaloneEffectsBatch2ExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all standalone effects batch 2 cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
