"""Computer Search AI decision boundary (trainer_cards.asm AIDecide_
ComputerSearch). The card's effect (ComputerSearch_HandDeckCheck/
PlayerDiscardHandSelection/PlayerDeckSelection/DiscardAddToHandEffect) was
already translated in an earlier round; this only adds the AI decision
side.

AIDecide_ComputerSearch has no general/default path at all -- only four
decks (Rock Crusher, Wonders of Science, Fire Charge, Anger) ever play this
card, each through its own dedicated multi-branch deck-search routine with
no shared logic between them and no fallback for any other deck. Only the
hand-count>=3 gate is deck-agnostic. Translating those four ~100-200 line
routines (each needing several never-before-used card-search primitives)
is left as a dedicated, explicitly tracked gap rather than being rushed or
approximated; the boundary itself is exercised for real by
lua_fixtures/computer_search_smoke.lua under LuaJIT -- see
test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/computer_search_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ComputerSearchSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")

    def test_is_dispatched_and_marked_supported(self):
        self.assertIn(
            'elseif constantName == "COMPUTER_SEARCH" then\n'
            "    return self:_decideComputerSearch()",
            self.ai_src,
        )
        self.assertIn('or constantName == "COMPUTER_SEARCH"', self.ai_src)
        self.assertIn('"MAINTENANCE", "POKE_BALL", "COMPUTER_SEARCH", "POKEMON_TRADER"', self.ai_src)

    def test_play_sets_modified_hand_flag(self):
        block = self.ai_src[self.ai_src.index("function AI:_playTrainerForAI"):
                             self.ai_src.index("local AI_TRAINER_PHASES")]
        # COMPUTER_SEARCH may not be the last name on its line once later
        # cards are appended to the same flag group, so check loosely.
        flag_group_start = block.index('if constantName == "MAINTENANCE"')
        flag_group_end = block.index("then", flag_group_start)
        self.assertIn('constantName == "COMPUTER_SEARCH"', block[flag_group_start:flag_group_end])

    def test_decide_fails_closed_on_all_four_specialized_decks(self):
        block = self.ai_src[self.ai_src.index("function AI:_decideComputerSearch"):
                             self.ai_src.index("-- AICheckIfAttackIsHighRecoil")]
        self.assertIn("handCount < 3", block)
        for deck in ("ROCK_CRUSHER_DECK_ID", "WONDERS_OF_SCIENCE_DECK_ID",
                     "FIRE_CHARGE_DECK_ID", "ANGER_DECK_ID"):
            self.assertIn(deck, block)
        self.assertIn('"untranslated_ai_computer_search_special_deck"', block)

    def test_effect_side_already_registered_from_a_prior_round(self):
        effects_src = read("src/tcg/duel/EffectCommands.lua")
        for label in ("ComputerSearch_HandDeckCheck", "ComputerSearch_PlayerDiscardHandSelection",
                     "ComputerSearch_PlayerDeckSelection", "ComputerSearch_DiscardAddToHandEffect"):
            self.assertIn(f'self:register("{label}"', effects_src)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class ComputerSearchExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Computer Search AI decision cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
