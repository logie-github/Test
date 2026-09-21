"""Articuno's Ice Breath (engine/duel/effect_functions.asm), part of the
broader card-effects sweep.

IceBreath_ZeroDamage: 0 printed damage from the normal attack pipeline.
IceBreath_RandomPokemonDamageEffect: 40 damage to a random opponent Play
Area Pokemon -- reuses the exact same damageRandomOpponentPlayAreaPokemon
helper as CatPunch/SlicingWind (PickRandomPlayAreaCard, no self-exclusion
or re-roll, then DealDamageToPlayAreaPokemon_RegularAnim).

Exercised for real by lua_fixtures/ice_breath_effect_smoke.lua under
LuaJIT (9 checks) -- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/ice_breath_effect_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class IceBreathEffectSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def test_zero_damage_sets_definite_damage_to_zero(self):
        start = self.src.index('self:register("IceBreath_ZeroDamage"')
        end = self.src.index("\n  end)", start)
        block = self.src[start:end]
        self.assertIn("s:_setDefiniteDamage(0)", block)

    def test_random_pokemon_damage_reuses_the_cat_punch_helper(self):
        self.assertIn(
            'self:register("IceBreath_RandomPokemonDamageEffect",\n'
            '    damageRandomOpponentPlayAreaPokemon(40, self.c.ATK_ANIM_BENCH_HIT))',
            self.src)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class IceBreathEffectExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all ice breath effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
