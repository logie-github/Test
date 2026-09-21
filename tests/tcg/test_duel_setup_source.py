import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SETUP = ROOT / "src/tcg/duel/DuelSetup.lua"


class DuelSetupSourceTests(unittest.TestCase):
    def text(self):
        return SETUP.read_text(encoding="utf-8")

    def test_missing_policy_dependencies_fail_closed(self):
        text = self.text()
        self.assertIn('untranslated adapter:', text)
        self.assertIn('"selectInitialActive"', text)
        self.assertIn('"selectInitialBench"', text)
        self.assertIn('self.ai:startDuel()', text)
        self.assertIn('self.practice:doAction(action)', text)
        self.assertIn('"serialExchange"', text)
        self.assertIn('"tossCoinLink"', text)

    def test_source_setup_order_is_present(self):
        text = self.text()
        establish = text.index("self:_establishStartingHands()")
        select = text.index("self:chooseInitialArenaAndBenchPokemon()", establish)
        prizes = text.index("self:_placePrizes(savedTurn)", select)
        toss = text.index("self:_decideFirstPlayer()", prizes)
        self.assertLess(establish, select)
        self.assertLess(select, prizes)
        self.assertLess(prizes, toss)

    def test_serial_duelvars_preserves_two_half_page_exchanges(self):
        text = self.text()
        self.assertIn("for chunkIndex = 0, 1 do", text)
        self.assertIn("math.floor((opponent - player) / 2)", text)

    def test_initial_placement_uses_second_return_as_carry(self):
        text = self.text()
        self.assertGreaterEqual(text.count('local _, carry = self.duelOps:putHandPokemonCardInPlayArea'), 2)

    def test_coin_toss_uses_rng_lsb_as_tails(self):
        text = self.text()
        self.assertIn("bit.band(value, 1) ~= 0", text)
        self.assertIn("tails and self.c.TAILS or self.c.HEADS", text)

    def test_prize_rng_exchange_precedes_saved_turn_restore(self):
        text = self.text()
        start = text.index("function DuelSetup:_placePrizes(savedTurn)")
        end = text.index("function DuelSetup:_decideFirstPlayer()", start)
        block = text[start:end]
        self.assertLess(block.index("self:exchangeRNG()"), block.index("self.duelVars:setTurn(savedTurn)"))



if __name__ == "__main__":
    unittest.main()
