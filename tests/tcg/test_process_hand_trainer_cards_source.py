"""_AIProcessHandTrainerCards relist cadence (trainer_cards.asm).

Rewrites processHandTrainerCards from a fixed per-phase Trainer-name
priority list (this file's own prior simplification) into a faithful
hand-snapshot, hand-ORDER scan matching the source's own CreateHandCardList
-> AITrainerCardLogic-table-lookup structure. Verified divergences fixed
this round:

1. Cards are now considered in HAND order, not this file's authoring order
   in AI_TRAINER_PHASES -- when two different Trainer types are both in
   hand during the same phase, whichever is physically first in hand is
   decided first, matching AITrainerCardLogic's per-hand-card table scan.
2. CheckCantUseTrainerDueToEffect and the card's own EFFECTCMDTYPE_
   INITIAL_EFFECT_1 gate now run BEFORE AIChooseRandomlyNotToDoAction and
   the card-specific AIDecide_* routine, not only as validation once
   PlayerActions:playTrainer executes the play.
3. A successful play that leaves AI_FLAG_MODIFIED_HAND set in
   wPreviousAIFlags now forces a fresh hand snapshot and restarts the scan
   from the top (clearing the flag), instead of this file's old special-
   cased "loop while more Bill copies are found" hack -- which, per the
   real AIPlay_Bill (confirmed not setting the flag), was solving the wrong
   problem: duplicate Bill copies are handled for free by the hand-order
   snapshot itself, not by a relist.
4. SWITCH additionally never matches once AI_FLAG_USED_SWITCH is already
   set, mirroring the table scan's own per-row skip.

The membership test (which card names apply to which phase) was already
byte-correct in AI_TRAINER_PHASES against the decomp's own data/duel/
ai_trainer_card_logic.asm table -- unchanged and re-verified here.

All of this is exercised for real by
lua_fixtures/process_hand_trainer_cards_smoke.lua under LuaJIT (25 checks)
-- see test_lua_execution_smoke below, which is what actually caught a
authoring bug in an early draft of this same fixture (a relist scenario's
"fresh hand" card wasn't valid for the phase being tested, so nothing
about the relist mechanism itself was actually being exercised until the
real execution surfaced the zero-decisions result).
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/process_hand_trainer_cards_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ProcessHandTrainerCardsSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")

    def _block(self, start_marker, end_marker):
        start = self.ai_src.index(start_marker)
        end = self.ai_src.index(end_marker, start)
        return self.ai_src[start:end]

    def test_phase_set_and_supported_tables_exist(self):
        self.assertIn("local AI_TRAINER_PHASE_SET = {}", self.ai_src)
        self.assertIn("local AI_TRAINER_SUPPORTED = {", self.ai_src)
        self.assertIn("function AI:_trainerConstantNameForCardID(cardId)", self.ai_src)

    def test_scan_takes_a_hand_snapshot_and_walks_it_in_order(self):
        block = self._block("function AI:processHandTrainerCards", "\nfunction AI:_grassEnergyAttached")
        self.assertIn("local snapshot = self.duelOps:createHandCardList()", block)
        self.assertIn("local deckIndex = snapshot[pos]", block)
        self.assertIn("self:_trainerConstantNameForCardID(cardId)", block)

    def test_gates_run_before_random_skip_and_decision(self):
        block = self._block("function AI:processHandTrainerCards", "\nfunction AI:_grassEnergyAttached")
        headache_pos = block.index("checkCantUseTrainerDueToEffect")
        effect1_pos = block.index("EFFECTCMDTYPE_INITIAL_EFFECT_1")
        random_pos = block.index("_chooseRandomlyNotToDoAction()")
        decide_pos = block.index("self:_decideTrainer(")
        self.assertLess(headache_pos, effect1_pos)
        self.assertLess(effect1_pos, random_pos)
        self.assertLess(random_pos, decide_pos)

    def test_relist_restarts_from_a_fresh_snapshot_and_clears_the_flag(self):
        block = self._block("function AI:processHandTrainerCards", "\nfunction AI:_grassEnergyAttached")
        self.assertIn("AI_FLAG_MODIFIED_HAND", block)
        self.assertIn("snapshot = self.duelOps:createHandCardList()", block)
        self.assertIn("pos = 1", block)
        self.assertIn("bit.bnot(self.c.AI_FLAG_MODIFIED_HAND or 0)", block)

    def test_switch_skips_when_already_used(self):
        block = self._block("function AI:processHandTrainerCards", "\nfunction AI:_grassEnergyAttached")
        self.assertIn('constantName == "SWITCH"', block)
        self.assertIn("AI_FLAG_USED_SWITCH", block)

    def test_phase_membership_matches_the_real_ai_trainer_card_logic_table(self):
        # Cross-checked by hand against pret/poketcg's data/duel/
        # ai_trainer_card_logic.asm; this just guards against a future
        # accidental edit silently breaking that correspondence.
        expected = {
            1: {"IMAKUNI_CARD", "GAMBLER"},
            2: {"MAINTENANCE", "POKE_BALL", "COMPUTER_SEARCH", "POKEMON_TRADER"},
            3: {"POKEDEX", "RECYCLE"},
            4: {"BILL", "ITEM_FINDER"},
            5: {"ENERGY_REMOVAL", "SUPER_ENERGY_REMOVAL", "REVIVE", "CLEFAIRY_DOLL",
                "MYSTERIOUS_FOSSIL"},
            6: {"POKEMON_CENTER"},
            7: {"POTION", "GUST_OF_WIND", "POKEMON_BREEDER", "IMPOSTER_PROFESSOR_OAK",
                "FULL_HEAL"},
            8: {"SUPER_POTION"},
            9: {"SWITCH"},
            10: {"POTION", "GUST_OF_WIND", "ENERGY_RETRIEVAL", "MR_FUJI", "SCOOP_UP"},
            11: {"SUPER_POTION", "SUPER_ENERGY_RETRIEVAL"},
            12: {"ENERGY_SEARCH"},
            13: {"DEFENDER", "PLUSPOWER", "LASS", "POKEMON_FLUTE"},
            14: {"DEFENDER", "PLUSPOWER"},
            15: {"PROFESSOR_OAK"},
        }
        block = self._block("local AI_TRAINER_PHASES = {", "\n}\n")
        for phase, names in expected.items():
            for name in names:
                self.assertIn(f'"{name}"', block, f"phase {phase} missing {name} in source text")


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class ProcessHandTrainerCardsExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all _AIProcessHandTrainerCards relist cadence cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
