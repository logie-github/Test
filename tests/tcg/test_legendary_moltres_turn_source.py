"""AIDoTurn_LegendaryMoltres (engine/duel/ai/decks/legendary_moltres.asm),
second of the five Legendary bosses' bespoke turn logic.

Shares the anti-Mewtwo-mill-first ordering and the "force-attach Energy
directly to a specific Arena Pokemon with none attached yet" shape with
Zapdos's (AI:_tryToPlayEnergyCard, factored out for Zapdos, is reused here
unchanged), but adds one further bespoke branch: after phases 2 and 4, if
the Bench isn't full, the deck has more than 9 cards left, no Muk is in
play on either side, and MoltresLv37 is in hand, it's played directly as a
Basic Pokemon via PlayerActions:playBasic, bypassing decidePlayPokemonCard's
own scoring entirely for that card this phase. The Energy-attach branch
itself is gated on a single card ID (MagmarLv31) rather than Zapdos's two.

All of this is exercised for real by
lua_fixtures/legendary_moltres_turn_smoke.lua under LuaJIT (24 checks) --
see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/legendary_moltres_turn_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class LegendaryMoltresTurnSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")

    def _block(self, start_marker, end_marker):
        start = self.ai_src.index(start_marker)
        end = self.ai_src.index(end_marker, start)
        return self.ai_src[start:end]

    def test_anti_mill_check_runs_before_any_phase(self):
        block = self._block("function AI:doTurnLegendaryMoltres", "\n-- AIDoAction_Turn")
        init_pos = block.index("self:initTurnVars()")
        anti_mill_pos = block.index("self:handleAIAntiMewtwoDeckStrategy()")
        phase2_pos = block.index("AI_TRAINER_CARD_PHASE_02")
        self.assertLess(init_pos, anti_mill_pos)
        self.assertLess(anti_mill_pos, phase2_pos)

    def test_phase_list_is_2_4_5_10_11_13(self):
        block = self._block("function AI:doTurnLegendaryMoltres", "\n-- AIDoAction_Turn")
        for present in ("AI_TRAINER_CARD_PHASE_02", "AI_TRAINER_CARD_PHASE_04",
                        "AI_TRAINER_CARD_PHASE_05", "AI_TRAINER_CARD_PHASE_10",
                        "AI_TRAINER_CARD_PHASE_11", "AI_TRAINER_CARD_PHASE_13"):
            self.assertIn(present, block)
        for absent in ("AI_TRAINER_CARD_PHASE_01", "AI_TRAINER_CARD_PHASE_07",
                       "AI_TRAINER_CARD_PHASE_15"):
            self.assertNotIn(absent, block)

    def test_moltres_direct_play_checks_all_four_gates_in_order(self):
        block = self._block("function AI:doTurnLegendaryMoltres", "\n-- AIDoAction_Turn")
        bench_pos = block.index("playAreaCount < self.c.MAX_PLAY_AREA_POKEMON")
        deck_pos = block.index("notInDeck < self.c.DECK_SIZE - 9")
        muk_pos = block.index("countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)")
        hand_pos = block.index("self:_findCardIDInHand(self.c.MOLTRES_LV37)")
        play_pos = block.index("self.playerActions:playBasic(self.c.MOLTRES_LV37)")
        self.assertLess(bench_pos, deck_pos)
        self.assertLess(deck_pos, muk_pos)
        self.assertLess(muk_pos, hand_pos)
        self.assertLess(hand_pos, play_pos)

    def test_energy_branch_is_single_card_gate_reusing_try_to_play_energy_card(self):
        block = self._block("function AI:doTurnLegendaryMoltres", "\n-- AIDoAction_Turn")
        self.assertIn("arenaCardId == self.c.MAGMAR_LV31", block)
        self.assertIn("self:_tryToPlayEnergyCard(self.c.PLAY_AREA_ARENA, handEnergy)", block)
        # Unlike Zapdos's Voltorb/Electrode-in-hand check, Moltres's gate is a
        # single direct card-ID comparison with no hand lookup.
        self.assertNotIn("_findCardIDInHand(self.c.ELECTRODE", block)

    def test_moltres_wired_into_do_turn_dispatch(self):
        block = self._block("function AI:doTurn()", "\nreturn AI")
        self.assertIn('label == "AIActionTable_LegendaryMoltres"', block)
        self.assertIn("self:doTurnLegendaryMoltres()", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class LegendaryMoltresTurnExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all AIDoTurn_LegendaryMoltres cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
