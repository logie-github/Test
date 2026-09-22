"""Zapdos' Thunderstorm (engine/duel/effect_functions.asm) -- the last
entry of the whole card-effects backlog.

Coin-flips every one of the opponent's Benched Pokemon (Arena excluded,
the loop runs from PLAY_AREA_BENCH_1 through count-1), takes 10 recoil
damage per tails via the already-registered Combat:dealRecoilDamageToSelf,
then deals 20 damage to every Benched Pokemon that came up heads via
Combat:dealDamageToPlayAreaPokemon. The real ASM stages the per-slot coin
results through an HRAM buffer (hTempList) purely so a later loop can
re-read them under a different alias name; a plain Lua array captures the
same one-result-per-bench-slot data with no memory round-trip needed. The
source's own SwapTurn bracketing around the coin toss itself is a
presentation-only concern (whose toss animation plays) with no effect on
RNG order or duel state, so it is dropped here -- only the three
state-relevant SwapTurn brackets (bench-count read, recoil, and damage
application) are kept.

Exercised for real by lua_fixtures/thunderstorm_effect_smoke.lua under
LuaJIT (19 checks) -- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/thunderstorm_effect_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ThunderstormEffectSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def _block(self):
        start = self.src.index('self:register("ThunderstormEffect"')
        end = self.src.index("\n  end)", start)
        return self.src[start:end]

    def test_coin_flips_bench_only_and_counts_tails(self):
        block = self._block()
        self.assertIn("for benchSlot = 1, count - 1 do", block)
        self.assertIn("s.setup:tossCoin()", block)
        self.assertIn("if result == s.c.HEADS then", block)
        self.assertIn("tails = tails + 1", block)

    def test_recoil_scales_with_tails_and_only_fires_when_nonzero(self):
        block = self._block()
        self.assertIn("if tails > 0 then", block)
        self.assertIn("combat:dealRecoilDamageToSelf(tails * 10)", block)

    def test_damages_only_the_heads_slots_without_asking_for_a_swap(self):
        block = self._block()
        self.assertIn("if headsBySlot[benchSlot] then", block)
        self.assertIn("combat:dealDamageToPlayAreaPokemon(benchSlot, 20, false)", block)
        self.assertEqual(block.count("combat.duelVars:swapTurn()"), 4)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class ThunderstormEffectExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all thunderstorm effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
