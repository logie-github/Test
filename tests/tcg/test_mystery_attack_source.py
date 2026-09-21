"""Porygon's Mystery Attack (engine/duel/effect_functions.asm). Part of the
broader card-effects sweep.

An 8-way RNG pick (UpdateRNGSources & %111 -- NOT a coin flip, unlike most
random-effect attacks in this game): rolls 0-3 reuse the four
unconditional status handlers (Paralysis/Poison/Sleep/Confusion, already
translated) directly by name; roll 4 ("recover") does nothing in the
random-pick phase itself -- a separate, later phase
(MysteryAttack_RecoverEffect) checks the relayed roll and only then heals
10; roll 5 is a pure no-op; roll 6 overrides the initial 10 damage to 20;
roll 7 zeroes damage and marks EFFECT_FAILED_NO_EFFECT.

All of this is exercised for real by
lua_fixtures/mystery_attack_smoke.lua under LuaJIT (26 checks) -- see
test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/mystery_attack_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class MysteryAttackSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def _block(self, start_marker):
        start = self.src.index(start_marker)
        end = self.src.index("\n  end)", start)
        return self.src[start:end]

    def test_random_effect_uses_raw_rng_byte_not_a_coin_flip(self):
        block = self._block('self:register("MysteryAttack_RandomEffect"')
        self.assertIn("s.setup.rng:updateSources()", block)
        self.assertIn("bit.band(", block)
        self.assertNotIn("tossCoin", block)

    def test_random_effect_reuses_the_four_status_handlers_by_name(self):
        block = self._block('self:register("MysteryAttack_RandomEffect"')
        for name in ("ParalysisEffect", "PoisonEffect", "SleepEffect", "ConfusionEffect"):
            self.assertIn(f's.handlers["{name}"]', block)

    def test_recover_effect_only_acts_on_roll_four(self):
        block = self._block('self:register("MysteryAttack_RecoverEffect"')
        self.assertIn('if s.memory:readSymbol8("hTemp_ffa0") ~= 4 then return false end', block)
        self.assertIn("s:_healAttackingArena(context, 10)", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class MysteryAttackExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Mystery Attack effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
