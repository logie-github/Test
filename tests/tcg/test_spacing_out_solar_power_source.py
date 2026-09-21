"""Slowpoke's Spacing Out and Venusaur's Solar Power (engine/duel/
effect_functions.asm), closing the last grouped card-effects backlog
entries.

SpacingOut_CheckDamage: same damage-check shape as FirstAid_DamageCheck.
SpacingOut_Success50PercentEffect: coin flip; heads sets the Recover
animation, tails marks the attack unsuccessful -- either way the raw coin
result is stashed in hTemp_ffa0 for the later heal phase.
SpacingOut_HealEffect: skips on a stashed tails result or on no remaining
damage; otherwise a raw +10 HP add rather than the clamped
_healAttackingArena helper, safe because CheckDamage already guaranteed
damage >= 10 before this phase can run.
SolarPower_CheckUse: usable once per turn (reusing the shared
powerUsedMask/powerActor/powerSlot Pokemon Power helpers), and only while
at least one active Pokemon (either side) has a status condition.
SolarPower_RemoveStatusEffect: marks the Power used and clears both
sides' status unconditionally.

Exercised for real by lua_fixtures/spacing_out_solar_power_smoke.lua
under LuaJIT (25 checks) -- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/spacing_out_solar_power_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class SpacingOutSolarPowerSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def _block(self, start_marker):
        start = self.src.index(start_marker)
        end = self.src.index("\n  end)", start)
        return self.src[start:end]

    def test_spacing_out_check_damage_reuses_play_area_damage_read(self):
        block = self._block('self:register("SpacingOut_CheckDamage"')
        self.assertIn("s:_playAreaDamage(actor, s.c.PLAY_AREA_ARENA)", block)
        self.assertIn("return (damage or 0) < 10", block)

    def test_spacing_out_success_stashes_coin_result_either_way(self):
        block = self._block('self:register("SpacingOut_Success50PercentEffect"')
        self.assertIn('s.memory:writeSymbol8("hTemp_ffa0", result)', block)
        self.assertIn("if result == s.c.TAILS then return s:_setWasUnsuccessful() end", block)
        self.assertIn('s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_RECOVER)', block)

    def test_spacing_out_heal_is_a_raw_add_not_the_clamped_helper(self):
        block = self._block('self:register("SpacingOut_HealEffect"')
        self.assertIn('if s.memory:readSymbol8("hTemp_ffa0") == s.c.TAILS then return false end', block)
        self.assertIn("actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_HP, hp + 10)", block)
        self.assertNotIn("_healAttackingArena", block)

    def test_solar_power_check_use_gates_on_used_flag_incapable_and_status(self):
        block = self._block('self:register("SolarPower_CheckUse"')
        self.assertIn("if bit.band(flags, powerUsedMask(s)) ~= 0 then return true end", block)
        self.assertIn("if s.status:checkIsIncapableOfUsingPkmnPower(slot) then return true end", block)
        self.assertIn("actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_STATUS) ~= 0", block)
        self.assertIn("actor.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD_STATUS) == 0", block)

    def test_solar_power_remove_status_marks_used_and_clears_both_sides(self):
        block = self._block('self:register("SolarPower_RemoveStatusEffect"')
        self.assertIn("markPowerUsed(s, actor, slot)", block)
        self.assertIn("actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_STATUS, s.c.NO_STATUS)", block)
        self.assertIn("actor.duelVars:setNonTurn(s.c.DUELVARS_ARENA_CARD_STATUS, s.c.NO_STATUS)", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class SpacingOutSolarPowerExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all spacing out / solar power effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
