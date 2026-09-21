"""Gambler AI decision + effect (trainer_cards.asm AIDecide_Gambler,
AIPlay_Gambler; effect_functions.asm GamblerEffect).

The real arithmetic (the Imakuni-deck 2-in-10 roll, the Mewtwo-mill-flag
gate for every other deck, and -- most notably -- the actual mechanical
result of AIPlay_Gambler's RNG-forcing byte-poke) is exercised for real by
lua_fixtures/gambler_smoke.lua under LuaJIT -- see test_lua_execution_smoke
below. That fixture caught a real discrepancy: the source comment claims
forcing wRNG1/wRNG2/wRNGCounter to $50 always yields heads, but running the
already-verified RNG:updateSources() with that exact seed produces an odd
result (tails) under this game's real RNG algorithm. The comment is not
re-implemented; the literal byte-poke mechanics are, so this reproduces
whatever a real cartridge actually computes rather than what a decomp
contributor's prose says it does.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/gambler_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class GamblerSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")
        self.effects_src = read("src/tcg/duel/EffectCommands.lua")

    def test_is_dispatched_and_marked_supported(self):
        self.assertIn(
            'elseif constantName == "GAMBLER" then\n'
            "    return self:_decideGambler()",
            self.ai_src,
        )
        self.assertIn('or constantName == "GAMBLER"', self.ai_src)
        self.assertIn('[1] = { "IMAKUNI_CARD", "GAMBLER" },', self.ai_src)

    def test_decide_covers_imakuni_roll_and_mill_flag(self):
        block = self.ai_src[self.ai_src.index("function AI:_decideGambler"):
                             self.ai_src.index("function AI:_playGamblerWithRNGCheat")]
        self.assertIn("self.c.IMAKUNI_DECK_ID", block)
        self.assertIn("self.rng:random(10) < 2", block)
        self.assertIn('"wAIBarrierFlagCounter"', block)
        self.assertIn("self.c.AI_MEWTWO_MILL", block)
        self.assertIn("self.c.DECK_SIZE - 4", block)

    def test_play_routes_through_rng_cheat_wrapper(self):
        block = self.ai_src[self.ai_src.index("function AI:_playTrainerForAI"):
                             self.ai_src.index("local AI_TRAINER_PHASES")]
        self.assertIn('if constantName == "GAMBLER" then', block)
        self.assertIn("self:_playGamblerWithRNGCheat(cardId, selection)", block)
        # MODIFIED_HAND flag group: GAMBLER may not be the last name on its
        # line once later cards are appended, so check membership loosely.
        flag_group_start = block.index('if constantName == "MAINTENANCE"')
        flag_group_end = block.index("then", flag_group_start)
        self.assertIn('constantName == "GAMBLER"', block[flag_group_start:flag_group_end])

    def test_rng_cheat_pokes_and_restores_all_three_bytes(self):
        block = self.ai_src[self.ai_src.index("function AI:_playGamblerWithRNGCheat"):
                             self.ai_src.index("-- AICheckIfAttackIsHighRecoil")]
        for symbol in ("wRNG1", "wRNG2", "wRNGCounter"):
            self.assertIn(f'"{symbol}"', block)
        self.assertEqual(block.count("0x50"), 3)
        self.assertIn("self.c.IMAKUNI_DECK_ID", block)

    def test_effect_is_registered_and_shuffles_whole_hand_not_just_trainers(self):
        start = self.effects_src.index('self:register("GamblerEffect"')
        end = self.effects_src.index('self:register(', start + 1)
        block = self.effects_src[start:end]
        self.assertIn("s.setup:tossCoin()", block)
        self.assertIn("a.duelOps:returnCardToDeck(deckIndex)", block)
        self.assertNotIn("row.type == s.c.TYPE_TRAINER", block)  # unlike LassEffect
        self.assertIn("drawCount = heads and 8 or 1", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class GamblerExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Gambler AI decision/RNG-cheat cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
