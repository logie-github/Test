"""Five small standalone card effects (engine/duel/effect_functions.asm),
part of the broader card-effects sweep.

TransparencyEffect / PrehistoricPowerEffect: pure EFFECTCMDTYPE_INITIAL_
EFFECT_1 stubs (`scf; ret` in the source, always carry) -- confirmed both
real command lists use ONLY that one phase, the exact same "triggered-only
Power, blocks ordinary-attack usage" shape as the already-translated
Quickfreeze/Firegiver/HealingWind/PealOfThunder stubs, so they reuse the
same `triggeredOnly` handler rather than adding new logic.
EarthquakeEffect: 10 damage to every one of the attacker's own Benched
Pokemon only -- reuses the same Combat:dealDamageToAllBenchedPokemon
primitive the Selfdestruct family uses, just once and without recoil.
PayDayEffect: coin heads only, then the same draw-1-card shape as the
already-translated Fetch.
DreamEaterEffect: usable only while the Defending Pokemon is Asleep.

All of this is exercised for real by
lua_fixtures/standalone_effects_batch1_smoke.lua under LuaJIT (15 checks)
-- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/standalone_effects_batch1_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class StandaloneEffectsBatch1SourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def _block(self, start_marker):
        start = self.src.index(start_marker)
        end = self.src.index("\n  end)", start)
        return self.src[start:end]

    def test_transparency_and_prehistoric_power_reuse_triggered_only_stub(self):
        self.assertIn('self:register("TransparencyEffect", triggeredOnly)', self.src)
        self.assertIn('self:register("PrehistoricPowerEffect", triggeredOnly)', self.src)

    def test_earthquake_hits_only_the_attackers_own_bench_once(self):
        block = self._block('self:register("EarthquakeEffect"')
        self.assertIn(
            "combat:dealDamageToAllBenchedPokemon(10, false, { isDamageToSelf = true })", block)
        self.assertNotIn("dealRecoilDamageToSelf", block)

    def test_pay_day_gates_on_a_coin_before_the_fetch_shaped_draw(self):
        block = self._block('self:register("PayDayEffect"')
        self.assertIn("s.setup:tossCoin()", block)
        self.assertIn("if result == s.c.TAILS then return false end", block)
        self.assertIn("actor.duelOps:drawCardFromDeck()", block)

    def test_dream_eater_requires_defender_asleep(self):
        block = self._block('self:register("DreamEaterEffect"')
        self.assertIn("actor.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD_STATUS)", block)
        self.assertIn("bit.band(status, s.c.CNF_SLP_PRZ) ~= s.c.ASLEEP", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class StandaloneEffectsBatch1ExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all standalone effects batch 1 cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
