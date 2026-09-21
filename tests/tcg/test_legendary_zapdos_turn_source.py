"""AIDoTurn_LegendaryZapdos (engine/duel/ai/decks/legendary_zapdos.asm), the
first of the five Legendary bosses' bespoke turn logic to be translated.

Structurally a trimmed AIMainTurnLogic (no Pkmn Power/Cowardice/
GoGoRainDance/EnergyTrans calls, no Professor-Oak repeat pass, a shorter
phase list of 1/4/7/10/13) plus one genuinely bespoke branch: if the Arena
Pokemon is Voltorb (with ElectrodeLv35 in hand) or Electabuzz, and the Arena
has no Energy attached yet, force-attach an Energy card directly to the
Arena via the newly factored-out AI:_tryToPlayEnergyCard (the real
AITryToPlayEnergyCard, previously only inlined at the tail of
AIProcessAndTryToPlayEnergy) rather than the normal scoring-based attach.

All of this is exercised for real by
lua_fixtures/legendary_zapdos_turn_smoke.lua under LuaJIT (28 checks) -- see
test_lua_execution_smoke below, which is what actually caught a genuine
authoring mistake, not in AI.lua but in the fixture's own first draft: its
"anti-Mewtwo-mill special path" case expected AI_TRAINER_CARD_PHASE_01 to
have been processed, copying the assumption from AIMainTurnLogic's own
fixture -- but AIDoTurn_LegendaryZapdos calls HandleAIAntiMewtwoDeckStrategy
*immediately* after InitAITurnVars, before phase 01 (general.asm's
AIMainTurnLogic does it the other way around, phase 01 first). Once the
mismatch surfaced as a real failing check, cross-checking both source files
side by side confirmed AI.lua's ordering was already correct and only the
test's expectation was wrong.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/legendary_zapdos_turn_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class LegendaryZapdosTurnSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")

    def _block(self, start_marker, end_marker=None):
        start = self.ai_src.index(start_marker)
        # Any function body here never contains another top-level "function
        # AI:" definition or the file's final "return AI", so the nearer of
        # those two is a stable boundary regardless of what gets inserted or
        # removed after this function in the file.
        candidates = []
        for marker in ("\nfunction AI:", "\nreturn AI"):
            try:
                candidates.append(self.ai_src.index(marker, start + 1))
            except ValueError:
                pass
        end = min(candidates)
        return self.ai_src[start:end]

    def test_anti_mill_check_runs_before_any_phase(self):
        block = self._block("function AI:doTurnLegendaryZapdos")
        init_pos = block.index("self:initTurnVars()")
        anti_mill_pos = block.index("self:handleAIAntiMewtwoDeckStrategy()")
        phase1_pos = block.index("AI_TRAINER_CARD_PHASE_01")
        self.assertLess(init_pos, anti_mill_pos)
        self.assertLess(anti_mill_pos, phase1_pos)

    def test_phase_list_is_1_4_7_10_13_not_the_general_deck_list(self):
        block = self._block("function AI:doTurnLegendaryZapdos")
        self.assertIn("AI_TRAINER_CARD_PHASE_01, self.c.AI_TRAINER_CARD_PHASE_04", block)
        self.assertIn("AI_TRAINER_CARD_PHASE_07", block)
        self.assertIn("AI_TRAINER_CARD_PHASE_10", block)
        self.assertIn("AI_TRAINER_CARD_PHASE_13", block)
        # These phases are only in the general deck's longer list, not Zapdos's.
        for absent in ("AI_TRAINER_CARD_PHASE_02", "AI_TRAINER_CARD_PHASE_05",
                       "AI_TRAINER_CARD_PHASE_15"):
            self.assertNotIn(absent, block)

    def test_voltorb_electabuzz_branch_checks_arena_then_hand_then_attached_count(self):
        block = self._block("function AI:doTurnLegendaryZapdos")
        self.assertIn("self.c.VOLTORB", block)
        self.assertIn("self:_findCardIDInHand(self.c.ELECTRODE_LV35)", block)
        self.assertIn("self.c.ELECTABUZZ_LV35", block)
        self.assertIn("self.duelOps:countNumberOfEnergyCardsAttached(self.c.PLAY_AREA_ARENA)", block)
        self.assertIn("self:_tryToPlayEnergyCard(self.c.PLAY_AREA_ARENA, handEnergy)", block)

    def test_try_to_play_energy_card_helper_is_reused_by_the_generic_attach_path(self):
        # AITryToPlayEnergyCard (choose + attach) is now a standalone helper
        # that AIProcessAndTryToPlayEnergy's own tail calls too, rather than
        # duplicating the choose-then-attach sequence inline.
        helper = self._block("function AI:_tryToPlayEnergyCard", "\n-- AIProcessAndTryToPlayEnergy")
        self.assertIn("self:_chooseEnergyCardForSlot(slot, handEnergy)", helper)
        self.assertIn("self.playerActions:attachEnergy(cardId, slot)", helper)
        generic = self._block("function AI:processAndTryToPlayEnergy", "\nfunction AI:_damageAt")
        self.assertIn("return self:_tryToPlayEnergyCard(bestSlot, handEnergy)", generic)

    def test_zapdos_wired_into_do_turn_dispatch(self):
        block = self._block("function AI:doTurn()")
        self.assertIn('label == "AIActionTable_LegendaryZapdos"', block)
        self.assertIn("self:doTurnLegendaryZapdos()", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class LegendaryZapdosTurnExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all AIDoTurn_LegendaryZapdos cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
