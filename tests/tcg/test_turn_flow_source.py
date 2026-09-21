import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
TURN = ROOT / "src/tcg/duel/TurnFlow.lua"


class TurnFlowSourceTests(unittest.TestCase):
    def text(self):
        return TURN.read_text(encoding="utf-8")

    def test_handle_turn_keeps_deck_empty_loss(self):
        text = self.text()
        self.assertIn('self.c.TURN_PLAYER_LOST', text)
        self.assertIn('self.duelOps:drawCardFromDeck()', text)
        self.assertIn('self.duelOps:addCardToHand(deckIndex)', text)

    def test_clairvoyance_check_swaps_and_restores_turn(self):
        text = self.text()
        start = text.index('local clairvoyance')
        before = text.rfind('self.duelVars:swapTurn()', 0, start)
        after = text.index('self.duelVars:swapTurn()', start)
        self.assertGreaterEqual(before, 0)
        self.assertGreater(after, start)

    def test_main_loop_rng_exchange_points_are_retained(self):
        text = self.text()
        start = text.index('function TurnFlow:runTurnCycle()')
        block = text[start:]
        self.assertEqual(block.count('self.setup:exchangeRNG()'), 3)

    def test_native_turn_dependencies_replace_old_adapters(self):
        text = self.text()
        self.assertIn('self.saveData:saveDuelStateToSRAM()', text)
        self.assertIn('self.status:isClairvoyanceActive()', text)
        self.assertIn('self.status:updateSubstatusConditionsStartOfTurn()', text)
        self.assertIn('self.status:handleBetweenTurnsEvents()', text)
        self.assertIn('self.practice:doAction(self.c.PRACTICEDUEL_PRINT_TURN_INSTRUCTIONS)', text)

    def test_practice_duel_source_limit_is_retained(self):
        text = self.text()
        self.assertIn('turns >= 15', text)
        self.assertIn('self.c.DUEL_WIN', text)


if __name__ == "__main__":
    unittest.main()
