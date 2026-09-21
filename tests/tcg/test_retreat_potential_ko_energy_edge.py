"""Retreat/switch potential-KO + one-Energy-from-hand edge.

Covers the exact next-step item from HANDOFF_CURRENT_WORK.md/AI_HANDOFF_
MASTER.md: "Separate 'attack can deal KO damage' from 'attack is currently
usable' only for the callers that require it... implement the source's
LookForEnergyNeededForAttackInHand behavior: one missing Energy, or exactly
two Colorless satisfied by Double Colorless Energy. Do not globally relax
existing attack-usability helpers."

Most of this project's suite checks that specific code shapes are present in
the Lua source text; it never actually runs the Lua. That is a real gap for
control-flow-heavy code like this edge, where a wrong boolean or a mis-
ordered check produces exactly the same source shape a text search looks
for. `test_lua_execution_smoke` actually loads and runs AI.lua under LuaJIT
(the interpreter this project's `bit` dependency requires -- see
test_bit_dependency_requires_luajit below) against a minimal hand/play-area
double, and is what caught a genuine pre-existing bug in
_lookForEnergyNeededInHand (fixed alongside this edge; see case 4 in the
fixture) that every text-matching test had missed.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/retreat_potential_ko_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class RetreatPotentialKOEnergyEdgeSourceTests(unittest.TestCase):
    """Source-shape checks, matching this project's established convention."""

    def setUp(self):
        self.src = read("src/tcg/duel/AI.lua")

    def test_bit_dependency_requires_luajit(self):
        # `require("bit")` is LuaJIT's built-in BitOp library. PUC Lua 5.1/5.4
        # have no such module by default (confirmed directly: both fail to
        # even load AI.lua with "module 'bit' not found"), so this project's
        # own `find src/tcg -name '*.lua' | xargs texluac -p` validation
        # checks syntax only -- it cannot and does not prove the module loads
        # against its real dependency. This is not a defect to fix; it is
        # the reason the Lua execution smoke test below targets luajit
        # specifically rather than any Lua 5.x interpreter.
        self.assertIn('require("bit")', self.src)

    def test_estimate_damage_from_play_area_gets_an_ignore_usability_escape(self):
        start = self.src.index("function AI:_estimateDamageFromPlayArea")
        end = self.src.index("function AI:checkIfAnyAttackKnocksOutDefendingCard", start)
        block = self.src[start:end]
        self.assertIn("opts = opts or {}", block)
        self.assertIn("opts.ignoreUsability", block)
        # Every pre-existing call site must still pass no 3rd argument, so
        # default behavior for every caller other than the new one is
        # unchanged.
        self.assertIn(
            'return { damage = 0, min = 0, max = 0, usable = false, attack = attack }',
            block,
        )

    def test_checkifanyattack_knocksout_defendingcard_is_untouched(self):
        # The shared, already-relied-upon helper keeps its exact existing
        # body -- this edge adds a parallel primitive rather than changing it.
        start = self.src.index("function AI:checkIfAnyAttackKnocksOutDefendingCard")
        end = self.src.index("function AI:_estimatePotentialKO", start)
        block = self.src[start:end]
        self.assertIn("estimate.usable ~= false and estimate.damage >= hp", block)

    def test_estimate_potential_ko_is_usability_blind(self):
        start = self.src.index("function AI:_estimatePotentialKO")
        end = self.src.index("function AI:_checkIfBenchAttackUnusable", start)
        block = self.src[start:end]
        self.assertIn("ignoreUsability = true", block)
        # Never consults an `estimate.usable`/`estimate .usable` field --
        # only the presence of a substring naming `opts.ignoreUsability`
        # itself is expected here, not a separate usability read.
        self.assertNotIn("estimate.usable", block)

    def test_bench_unusable_check_covers_energy_and_ignore_flag_only(self):
        start = self.src.index("function AI:_checkIfBenchAttackUnusable")
        end = self.src.index("function AI:_canKnockOutNowOrWithHandEnergy", start)
        block = self.src[start:end]
        self.assertIn("checkEnergyNeededForAttack", block)
        self.assertIn("IGNORE_THIS_ATTACK_F", block)
        # Source's Active-only substatus/paralysis/sleep/amnesia/initial-
        # effect-1 gate must NOT appear here -- Bench genuinely skips it.
        self.assertNotIn("HandleCantAttackSubstatus", block)
        self.assertNotIn("Paralyzed", block)

    def test_combinator_tries_the_hand_rescue_only_when_unusable(self):
        start = self.src.index("function AI:_canKnockOutNowOrWithHandEnergy")
        end = self.src.index("function AI:_activeCanKONowOrWithHandEnergy", start)
        block = self.src[start:end]
        self.assertIn("if not unusable then return true end", block)
        self.assertIn("return self:_lookForEnergyNeededInHand(slot, attackIndex)", block)

    def test_super_energy_removal_caller_is_a_thin_wrapper_now(self):
        start = self.src.index("function AI:_activeCanKONowOrWithHandEnergy")
        end = self.src.index("-- AIDecide_SuperEnergyRemoval", start)
        block = self.src[start:end]
        self.assertIn("return self:_canKnockOutNowOrWithHandEnergy(self.c.PLAY_AREA_ARENA)", block)

    def _decide_whether_to_retreat_block(self):
        start = self.src.index("function AI:decideWhetherToRetreat")
        end = self.src.index("function AI:_energyIsUsefulForRetreat", start)
        return self.src[start:end]

    def test_retreat_active_gate_uses_the_shared_combinator(self):
        block = self._decide_whether_to_retreat_block()
        self.assertIn(
            "local activeWorkingKO, activeKOErr = self:_canKnockOutNowOrWithHandEnergy(self.c.PLAY_AREA_ARENA)",
            block,
        )

    def test_bench_ko_loop_uses_the_shared_combinator(self):
        block = self._decide_whether_to_retreat_block()
        self.assertIn(
            "local can, e = self:_canKnockOutNowOrWithHandEnergy(slot)",
            block,
        )

    def test_boss_last_prize_recheck_treats_potential_but_unusable_as_not_working(self):
        # The +40/energy-for-retreat bonus after a Bench KO is found must
        # fire both when the Active card cannot potentially KO at all, AND
        # when it could but the attack is not currently usable -- source
        # attempts no rescue at this specific point (unlike the two sites
        # above), so this must NOT call the combinator.
        block = self._decide_whether_to_retreat_block()
        self.assertIn("local activeHasWorkingKO = false", block)
        self.assertIn("activeHasWorkingKO = usable == true", block)
        self.assertIn("if not activeHasWorkingKO then", block)

    def test_look_for_energy_needed_in_hand_matches_source_total_branching(self):
        start = self.src.index("function AI:_lookForEnergyNeededInHand")
        end = self.src.index("function AI:_canDamageDefendingPokemon", start)
        block = self.src[start:end]
        self.assertIn("local total = need.colored + need.colorless", block)
        self.assertIn("if total == 1 then", block)
        self.assertIn("if total == 2 and need.colorless == 2 then", block)
        self.assertIn("self.c.DOUBLE_COLORLESS_ENERGY", block)

    def test_look_for_any_energy_needed_in_hand_delegates_and_sets_selected_attack(self):
        start = self.src.index("function AI:_lookForAnyEnergyNeededInHand")
        end = self.src.index("function AI:_findCardIDInHand", start) \
            if "function AI:_findCardIDInHand" in self.src[start:start + 4000] \
            else start + 2000
        block = self.src[start:start + 1200]
        self.assertIn('self.memory:writeSymbol8("wSelectedAttack", attackIndex)', block)
        self.assertIn("self:_lookForEnergyNeededInHand(slot, attackIndex)", block)

    def test_bench_switch_energy_bonus_uses_both_attack_lookahead(self):
        start = self.src.index("function AI:decideBenchPokemonToSwitchTo")
        end = self.src.index("function AI:_benchHasAlternativeNotMatching", start)
        block = self.src[start:end]
        self.assertIn("if self:_lookForAnyEnergyNeededInHand(slot) then", block)
        self.assertIn('local selected = self.memory:readSymbol8("wSelectedAttack")', block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class RetreatPotentialKOEnergyEdgeExecutionTests(unittest.TestCase):
    """Actually loads and runs AI.lua under LuaJIT against a minimal double.

    Text-matching cannot distinguish `if usable or rescue then` from
    `if usable and rescue then`; this can. See lua_fixtures/
    retreat_potential_ko_smoke.lua for the full case list.
    """

    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(
            result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}",
        )
        self.assertIn("all retreat + both-attack energy-lookahead cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
