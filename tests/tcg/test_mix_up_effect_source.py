"""Ninetales' Mix Up (engine/duel/effect_functions.asm), part of the
final batch of standalone attack effects closing the card-effects sweep.

Sorts the opponent's Hand by card ID (reusing DuelOps:createHandCardList
and DuelOps:sortCardsInDuelTempListByID), moves every Pokemon card found
there back into the Deck (removeCardFromHand + returnCardToDeck), always
reshuffles the Deck and rebuilds the Deck list -- matching the real ASM's
unconditional ShuffleCardsInDeck/CreateDeckCardList, which run even when
no Pokemon turned up in Hand -- then, only if any cards moved, draws back
exactly that many Pokemon cards from the freshly shuffled Deck
(searchCardInDeckAndAddToHand + addCardToHand), stopping once satisfied.

Exercised for real by lua_fixtures/mix_up_effect_smoke.lua under LuaJIT
(20 checks) -- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/mix_up_effect_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class MixUpEffectSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def _block(self):
        start = self.src.index('self:register("MixUpEffect"')
        end = self.src.index("\n  end)", start)
        return self.src[start:end]

    def test_mix_up_sorts_hand_and_returns_pokemon_cards_to_deck(self):
        block = self._block()
        self.assertIn("actor.duelOps:createHandCardList()", block)
        self.assertIn("actor.duelOps:sortCardsInDuelTempListByID()", block)
        self.assertIn("row.type < s.c.TYPE_ENERGY", block)
        self.assertIn("actor.duelOps:removeCardFromHand(deckIndex)", block)
        self.assertIn("actor.duelOps:returnCardToDeck(deckIndex)", block)

    def test_mix_up_always_reshuffles_before_checking_whether_anything_moved(self):
        block = self._block()
        shuffle_at = block.index("actor.duelOps:shuffleDeck()")
        deck_list_at = block.index("actor.duelOps:createDeckCardList()")
        gate_at = block.index("if movedToDeck > 0 then")
        self.assertLess(shuffle_at, gate_at)
        self.assertLess(deck_list_at, gate_at)

    def test_mix_up_redraw_loop_stops_once_the_moved_count_is_satisfied(self):
        block = self._block()
        self.assertIn("while remaining > 0 and i < #deck do", block)
        self.assertIn("actor.duelOps:searchCardInDeckAndAddToHand(deckIndex)", block)
        self.assertIn("actor.duelOps:addCardToHand(deckIndex)", block)
        self.assertEqual(block.count("actor.duelVars:swapTurn()"), 2)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class MixUpEffectExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all mix up effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
