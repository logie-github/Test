"""Farfetch'd's Leek Slap once-per-duel gate and Fetch (a simple "draw 1
card" attack), engine/duel/effect_functions.asm. Part of the broader card-
effects sweep.

Leek Slap: a duel-long flag on the Arena card (USED_LEEK_SLAP_THIS_DUEL_F),
distinct from the per-turn USED_PKMN_POWER_THIS_TURN flags used elsewhere
in this file -- once set, it never clears for the rest of the duel.
Fetch: DrawCardFromDeck then AddCardToHand; does nothing (not an error) if
the deck is empty -- everything past that in the source is presentation.

All of this is exercised for real by
lua_fixtures/leek_slap_fetch_smoke.lua under LuaJIT (10 checks) -- see
test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/leek_slap_fetch_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class LeekSlapFetchSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def _block(self, start_marker):
        start = self.src.index(start_marker)
        end = self.src.index("\n  end)", start)
        return self.src[start:end]

    def test_once_per_duel_flag_is_distinct_from_per_turn_power_flag(self):
        block = self._block('self:register("LeekSlap_OncePerDuelCheck"')
        self.assertIn("USED_LEEK_SLAP_THIS_DUEL_F", block)
        self.assertNotIn("USED_PKMN_POWER_THIS_TURN", block)

    def test_set_used_flag_preserves_other_bits(self):
        block = self._block('self:register("LeekSlap_SetUsedThisDuelFlag"')
        self.assertIn("bit.bor(flags, bit.lshift(1, s.c.USED_LEEK_SLAP_THIS_DUEL_F))", block)

    def test_fetch_draws_and_adds_to_hand_without_erroring_on_empty_deck(self):
        block = self._block('self:register("FetchEffect"')
        self.assertIn("actor.duelOps:drawCardFromDeck()", block)
        self.assertIn("if carry then return false end", block)
        self.assertIn("actor.duelOps:addCardToHand(deckIndex)", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class LeekSlapFetchExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Leek Slap / Fetch effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
