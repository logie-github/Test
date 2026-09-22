"""Zapdos' Big Thunder (engine/duel/effect_functions.asm), part of the
final batch of standalone attack effects closing the card-effects sweep.

Introduces a new shared randomlyDamagePlayAreaPokemon helper (the real
ASM's RandomlyDamagePlayAreaPokemon): an UpdateRNGSources coin-like pick
of own vs. opponent Play Area, then Random(count) for the slot within
that side. An own-side pick re-rolls the WHOLE sample (side choice
included, matching the source's `.sample` retry target) if the slot
lands on the attacker itself (hTempPlayAreaLocation_ff9d, which the
shared attack pipeline already sets to PLAY_AREA_ARENA before any
attack's effect commands run); an opponent-side pick never needs to
re-roll. This is a genuinely different primitive from the simpler
PickRandomPlayAreaCard used by CatPunch/SlicingWind/IceBreath, which
always targets the opponent with no side choice or self-exclusion.
Big Thunder itself is then just a fixed 70 damage through that helper,
after the standard ExchangeRNG call already used by several other
translated effects.

Exercised for real by lua_fixtures/big_thunder_effect_smoke.lua under
LuaJIT (22 checks) -- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/big_thunder_effect_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class BigThunderEffectSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def _helper_block(self):
        start = self.src.index("local function randomlyDamagePlayAreaPokemon(s, context, amount)")
        end = self.src.index("\n  end\n", start)
        return self.src[start:end]

    def test_helper_rerolls_the_whole_sample_on_self_collision(self):
        block = self._helper_block()
        self.assertIn("bit.band(s.setup.rng:updateSources(), 1)", block)
        self.assertIn("s.setup.rng:random(count)", block)
        self.assertIn(
            "if slot ~= s.memory:readSymbol8(\"hTempPlayAreaLocation_ff9d\") then", block)
        self.assertIn("{ isDamageToSelf = true }", block)

    def test_helper_opponent_branch_swaps_and_never_reexcludes(self):
        block = self._helper_block()
        self.assertEqual(block.count("combat.duelVars:swapTurn()"), 2)

    def test_big_thunder_exchanges_rng_then_deals_fixed_damage(self):
        start = self.src.index('self:register("BigThunderEffect"')
        end = self.src.index("\n  end)", start)
        block = self.src[start:end]
        self.assertIn("s.setup:exchangeRNG()", block)
        self.assertIn("if failed then return nil, exchangeErr end", block)
        self.assertIn("randomlyDamagePlayAreaPokemon(s, context, 70)", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class BigThunderEffectExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all big thunder effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
