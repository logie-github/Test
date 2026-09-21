"""A third batch of standalone card effects (engine/duel/effect_functions.
asm), part of the broader card-effects sweep.

ToxicGasEffect/StrikesBackEffect/RetreatAidEffect: pure EFFECTCMDTYPE_
INITIAL_EFFECT_1 stubs (`scf; ret` in the source, always carry) -- confirmed
each real command list uses only that one phase, the same "triggered-only
Power" shape as the already-translated Quickfreeze/Firegiver/HealingWind/
PealOfThunder/Transparency/PrehistoricPower/Clairvoyance/InvisibleWall/
NeutralizingShield/KabutoArmor/ThickSkinned stubs, so all three reuse the
existing triggeredOnly handler.
SingEffect/SleepingGasEffect: coin heads inflicts ASLEEP, tails marks
"no effect" -- the exact same shape as the already-translated Supersonic
family, just Sleep instead of Confused.
HeadacheEffect: sets the SUBSTATUS3_HEADACHE_F bit on the Defending
Pokemon's SUBSTATUS3, unconditional, no coin.
FoulOdorEffect: confuses both active Pokemon unconditionally, reusing the
already-registered plain ConfusionEffect twice (once plain, once bracketed
by SwapTurn).
TantrumEffect: heads does nothing; tails sets the multiple-slash animation
and confuses the attacker's own side (SwapTurn-bracketed ConfusionEffect).

All of this is exercised for real by
lua_fixtures/standalone_effects_batch3_smoke.lua under LuaJIT (27 checks)
-- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/standalone_effects_batch3_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class StandaloneEffectsBatch3SourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def _block(self, start_marker):
        start = self.src.index(start_marker)
        end = self.src.index("\n  end)", start)
        return self.src[start:end]

    def test_three_stubs_reuse_triggered_only_handler(self):
        for name in ("ToxicGasEffect", "StrikesBackEffect", "RetreatAidEffect"):
            self.assertIn(f'self:register("{name}", triggeredOnly)', self.src)

    def test_sing_and_sleeping_gas_share_the_sleep_or_no_effect_helper(self):
        self.assertIn('self:register("SingEffect", sleepOrNoEffect)', self.src)
        self.assertIn('self:register("SleepingGasEffect", sleepOrNoEffect)', self.src)
        start = self.src.index("local function sleepOrNoEffect(s)")
        end = self.src.index("\n  end", start)
        block = self.src[start:end]
        self.assertIn("s.setup:tossCoin()", block)
        self.assertIn("s.status:queueStatusCondition(s.c.PSN_DBLPSN, s.c.ASLEEP)", block)
        self.assertIn("s:_setNoEffectFromStatus()", block)

    def test_headache_sets_substatus3_bit_on_non_turn_side(self):
        block = self._block('self:register("HeadacheEffect"')
        self.assertIn("actor.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD_SUBSTATUS3)", block)
        self.assertIn("actor.duelVars:setNonTurn(s.c.DUELVARS_ARENA_CARD_SUBSTATUS3,", block)
        self.assertIn("bit.bor(sub3, bit.lshift(1, s.c.SUBSTATUS3_HEADACHE_F))", block)

    def test_foul_odor_confuses_both_sides_via_swap_turn_bracket(self):
        block = self._block('self:register("FoulOdorEffect"')
        self.assertEqual(block.count('s.handlers["ConfusionEffect"](s, context)'), 2)
        self.assertEqual(block.count("actor.duelVars:swapTurn()"), 2)

    def test_tantrum_heads_is_a_noop_tails_confuses_own_side(self):
        block = self._block('self:register("TantrumEffect"')
        self.assertIn("if result == s.c.HEADS then return false end", block)
        self.assertIn('s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_MULTIPLE_SLASH)', block)
        self.assertEqual(block.count("actor.duelVars:swapTurn()"), 2)
        self.assertIn('s.handlers["ConfusionEffect"](s, context)', block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class StandaloneEffectsBatch3ExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all standalone effects batch 3 cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
