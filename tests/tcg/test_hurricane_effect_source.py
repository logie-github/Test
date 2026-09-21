"""Pidgeotto's Hurricane (engine/duel/effect_functions.asm), part of the
final batch of standalone attack effects closing the card-effects sweep.

Unless the attack was unaffected (Status:checkNoDamageOrEffect) or the
Defending Pokemon was already KO'd (its HP already at 0), returns the
Defending Pokemon and every card attached to it -- anything sharing its
CARD_LOCATION_ARENA slot, i.e. Energy and Trainer cards too, not just the
Pokemon itself -- to the opponent's hand via the already-translated
DuelOps:addCardToHand, then clears the Arena slot outright. Deliberately
does not shift the Bench or touch the play area count, matching the real
ASM, which leaves that to whatever forced-switch flow follows.

Exercised for real by lua_fixtures/hurricane_effect_smoke.lua under
LuaJIT (18 checks) -- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/hurricane_effect_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class HurricaneEffectSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def test_hurricane_bails_on_prevented_or_already_ko(self):
        start = self.src.index('self:register("HurricaneEffect"')
        end = self.src.index("\n  end)", start)
        block = self.src[start:end]
        self.assertIn("if s.status:checkNoDamageOrEffect() then return false end", block)
        self.assertIn(
            "if actor.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD_HP) == 0 then return false end", block)

    def test_hurricane_returns_every_card_at_the_arena_location(self):
        start = self.src.index('self:register("HurricaneEffect"')
        end = self.src.index("\n  end)", start)
        block = self.src[start:end]
        self.assertIn("for deckIndex = 0, s.c.DECK_SIZE - 1 do", block)
        self.assertIn("actor.duelVars:get(deckIndex) == s.c.CARD_LOCATION_ARENA", block)
        self.assertIn("actor.duelOps:addCardToHand(deckIndex)", block)
        self.assertIn("actor.duelVars:set(s.c.DUELVARS_ARENA_CARD, 0xff)", block)
        self.assertIn("actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_HP, 0)", block)
        self.assertEqual(block.count("actor.duelVars:swapTurn()"), 2)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class HurricaneEffectExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all hurricane effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
