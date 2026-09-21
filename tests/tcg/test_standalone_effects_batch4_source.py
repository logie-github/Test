"""CatPunchEffect/SlicingWindEffect/FirstAid_DamageCheck (engine/duel/
effect_functions.asm), part of the broader card-effects sweep.

CatPunchEffect/SlicingWindEffect: PickRandomPlayAreaCard on the opponent's
side -- a plain Random(count), no self-exclusion or re-roll, unlike the
own/opponent-coin-pick RandomlyDamagePlayAreaPokemon primitive the still-
deferred BigThunder/MagneticStorm need -- then straight into
DealDamageToPlayAreaPokemon (Cat Punch: 20 damage with its own animation;
Slicing Wind: 30 damage with the shared "regular anim" bench-hit
animation). Both reuse the already-registered
Combat:dealDamageToPlayAreaPokemon primitive and the RNG.random(maxExclusive)
translation of the cartridge's Random:: routine.
FirstAid_DamageCheck: fails (carry true) unless the attacker's own Arena
Pokemon has at least 10 damage counters -- reuses the same _playAreaDamage
read already used by the paired, already-translated FirstAid_HealEffect.

All of this is exercised for real by
lua_fixtures/standalone_effects_batch4_smoke.lua under LuaJIT (18 checks)
-- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/standalone_effects_batch4_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class StandaloneEffectsBatch4SourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def _block(self, start_marker):
        start = self.src.index(start_marker)
        end = self.src.index("\n  end", start)
        return self.src[start:end]

    def test_cat_punch_and_slicing_wind_share_the_random_opponent_helper(self):
        self.assertIn(
            'self:register("CatPunchEffect",\n'
            '    damageRandomOpponentPlayAreaPokemon(20, self.c.ATK_ANIM_CAT_PUNCH_PLAY_AREA))',
            self.src)
        self.assertIn(
            'self:register("SlicingWindEffect",\n'
            '    damageRandomOpponentPlayAreaPokemon(30, self.c.ATK_ANIM_BENCH_HIT))',
            self.src)
        block = self._block("local function damageRandomOpponentPlayAreaPokemon(amount, animation)")
        self.assertIn("combat.duelVars:getNonTurn(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)", block)
        self.assertIn("s.setup.rng:random(count)", block)
        self.assertIn("combat:dealDamageToPlayAreaPokemon(slot, amount, true)", block)

    def test_first_aid_damage_check_reuses_play_area_damage_read(self):
        block = self._block('self:register("FirstAid_DamageCheck"')
        self.assertIn("s:_playAreaDamage(actor, s.c.PLAY_AREA_ARENA)", block)
        self.assertIn("return (damage or 0) < 10", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class StandaloneEffectsBatch4ExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all standalone effects batch 4 cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
