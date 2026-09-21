"""Mewtwo Lv53 mill-deck detector (InitAITurnVars /
CheckIfPlayerHasPokemonOtherThanMewtwoLv53, engine/duel/ai/{init,common}.asm).

Before this change, AI:initTurnVars() gated setting the AI_MEWTWO_MILL flag
behind self.adapters.checkPlayerMewtwoMillDeck -- an adapter nothing wired
up, so the flag (already read by Gambler's decision and two other already-
translated spots) could never actually be set. Both real sub-checks the
source performs before setting it -- the Player's Arena Pokemon being
MewtwoLv53, and a full 60-card-deck scan (by physical deck index, not by
current card location) finding no other Pokemon -- are now translated
natively, matching engine/duel/ai/init.asm's InitAITurnVars and
engine/duel/ai/common.asm's CheckIfPlayerHasPokemonOtherThanMewtwoLv53.

All of this is exercised for real by
lua_fixtures/mewtwo_mill_detector_smoke.lua under LuaJIT (13 checks) -- see
test_lua_execution_smoke below. That fixture is also what caught an
authoring bug in an early draft of this same fixture: a "2nd consecutive
Barrier turn" case used a starting counter of 2, which (after the
increment) is not less than 3 and so does *not* skip the arena/deck check
like the test's own label claimed -- CheckAIBarrierFlagCounter's `cp 3;
jr c, .done` only skips the check when the post-increment count is 1 or 2.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/mewtwo_mill_detector_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class MewtwoMillDetectorSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")

    def _block(self, start_marker, end_marker):
        start = self.ai_src.index(start_marker)
        end = self.ai_src.index(end_marker, start)
        return self.ai_src[start:end]

    def test_adapter_indirection_is_gone(self):
        self.assertNotIn("checkPlayerMewtwoMillDeck", self.ai_src)

    def test_init_turn_vars_checks_arena_card_before_scanning_deck(self):
        block = self._block("function AI:initTurnVars", "\nfunction AI:_checkIfPlayerHasPokemonOtherThanMewtwoLv53")
        self.assertIn('self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD)', block)
        arena_pos = block.index("arenaCardId == self.c.MEWTWO_LV53")
        scan_pos = block.index("_checkIfPlayerHasPokemonOtherThanMewtwoLv53()")
        self.assertLess(arena_pos, scan_pos)
        self.assertIn("counter >= 3", block)

    def test_deck_scan_covers_the_full_deck_by_physical_index(self):
        block = self._block("function AI:_checkIfPlayerHasPokemonOtherThanMewtwoLv53", "\nfunction AI:")
        self.assertIn("self.duelVars:swapTurn()", block)
        self.assertIn("for deckIndex = 0, self.c.DECK_SIZE - 1 do", block)
        self.assertIn("row.type < self.c.TYPE_ENERGY", block)
        self.assertIn("cardId ~= self.c.MEWTWO_LV53", block)
        # SwapTurn must be balanced: called once on entry and once before
        # every return (the source calls it both on the early-return "found
        # another Pokemon" path and the fall-through "pure Mewtwo" path).
        self.assertEqual(block.count("self.duelVars:swapTurn()"), 2)

    def test_flag_refresh_writes_exactly_the_flag_value_not_an_increment(self):
        block = self._block("function AI:initTurnVars", "\nfunction AI:_checkIfPlayerHasPokemonOtherThanMewtwoLv53")
        self.assertIn('self.memory:writeSymbol8("wAIBarrierFlagCounter", self.c.AI_MEWTWO_MILL)', block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class MewtwoMillDetectorExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Mewtwo Lv53 mill detector cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
