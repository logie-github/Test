"""HandleAIAntiMewtwoDeckStrategy (engine/duel/ai/common.asm) and its wiring
into AIMainTurnLogic / AIDoTurn_GeneralNoRetreat (both call it identically,
right after AI_TRAINER_CARD_PHASE_01, with `jp nc, .try_attack`).

Once the Mewtwo Lv53 mill-deck detector (InitAITurnVars) could actually set
the AI_MEWTWO_MILL flag, mainTurnLogic had a real, previously-invisible gap:
it never consulted the flag at all, so the AI would never take the source's
"my Bench is fully set up against a mill deck, skip straight to attacking
after one more Trainer-card pass" shortcut. This translates
HandleAIAntiMewtwoDeckStrategy natively and wires it into the shared
mainTurnLogic (used by both AIMainTurnLogic and AIDoTurn_GeneralNoRetreat,
and by the eleven boss decks that route .do_turn straight to it).

All of this is exercised for real by
lua_fixtures/anti_mewtwo_mill_strategy_smoke.lua under LuaJIT (24 checks) --
see test_lua_execution_smoke below, which is what actually caught a bug: not
in AI.lua, but in an early draft of the fixture itself, whose `check()`
helper compared two freshly-built phase-log tables with Lua's `~=` (always
true for distinct tables, regardless of contents), silently passing
whatever the phase log actually contained. Fixed with a real array-equality
comparison.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/anti_mewtwo_mill_strategy_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class AntiMewtwoMillStrategySourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")

    def _block(self, start_marker, end_marker):
        start = self.ai_src.index(start_marker)
        end = self.ai_src.index(end_marker, start)
        return self.ai_src[start:end]

    def test_handler_exists_and_checks_flag_staleness_and_bench(self):
        block = self._block("function AI:handleAIAntiMewtwoDeckStrategy", "\nfunction AI:_energyCardIdForColor")
        self.assertIn("AI_MEWTWO_MILL_F", block)
        self.assertIn("counter >= self.c.AI_MEWTWO_MILL + 2", block)
        self.assertIn('self.memory:writeSymbol8("wAIBarrierFlagCounter", 0)', block)
        self.assertIn("_countNumberOfSetUpBenchPokemon() < 4", block)
        self.assertIn("self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_05)", block)

    def test_main_turn_logic_calls_it_right_after_phase_one(self):
        block = self._block("function AI:mainTurnLogic", "\n-- AIDoAction_Turn")
        phase1_pos = block.index("ipairs({1})")
        anti_mill_pos = block.index("self:handleAIAntiMewtwoDeckStrategy()")
        phase234_pos = block.index("ipairs({2,3,4})")
        self.assertLess(phase1_pos, anti_mill_pos)
        self.assertLess(anti_mill_pos, phase234_pos)

    def test_normal_sequence_is_gated_behind_anti_mill_ok_but_to_bench_and_attack_are_not(self):
        block = self._block("function AI:mainTurnLogic", "\n-- AIDoAction_Turn")
        gate_pos = block.index("if antiMillOk then")
        phase234_pos = block.index("ipairs({2,3,4})")
        self.assertLess(gate_pos, phase234_pos)
        # The antiMillOk block closes (two nested "end"s: the Professor Oak
        # repeat's own `if`, then the outer antiMillOk `if`) immediately
        # before the always-runs to_bench Energy Trans + attack tail.
        self.assertIn(
            '    end\n  end\n\n  transOK, transErr = self:handleAIEnergyTrans("to_bench")',
            block,
        )
        to_bench_pos = block.index('self:handleAIEnergyTrans("to_bench")')
        attack_pos = block.index("self:processAndTryToUseAttack()")
        self.assertLess(to_bench_pos, attack_pos)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class AntiMewtwoMillStrategyExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all anti-Mewtwo-mill turn-strategy cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
