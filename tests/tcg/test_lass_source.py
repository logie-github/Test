"""Lass AI decision + effect (trainer_cards.asm AIDecide_Lass, AIPlay_Lass;
effect_functions.asm LassEffect).

The real threshold/scan logic (the opponent-hand-size gate, and the AI's own
hand scan that excludes Lass by card ID rather than hand position) is
exercised for real by lua_fixtures/lass_smoke.lua under LuaJIT -- see
test_lua_execution_smoke below. These source-shape checks only confirm the
pieces are wired together and that the effect discards the played Lass card
itself before scanning for other Trainer cards (source order matters: doing
it after would let Lass re-catch and shuffle itself away), and that both
duelists' hands are processed.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/lass_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class LassSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")
        self.effects_src = read("src/tcg/duel/EffectCommands.lua")

    def test_is_dispatched_and_marked_supported(self):
        self.assertIn(
            'elseif constantName == "LASS" then\n'
            "    return self:_decideLass()",
            self.ai_src,
        )
        self.assertIn('or constantName == "LASS"', self.ai_src)
        self.assertIn('"DEFENDER", "PLUSPOWER", "LASS", "POKEMON_FLUTE"', self.ai_src)

    def test_play_sets_modified_hand_flag(self):
        block = self.ai_src[self.ai_src.index("function AI:_playTrainerForAI"):
                             self.ai_src.index("local AI_TRAINER_PHASES")]
        self.assertIn('or constantName == "LASS"', block)

    def test_decide_reads_non_turn_hand_count_and_excludes_lass_by_id(self):
        block = self.ai_src[self.ai_src.index("function AI:_decideLass"):
                             self.ai_src.index("-- AICheckIfAttackIsHighRecoil")]
        self.assertIn("getNonTurn(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)", block)
        self.assertIn("oppHandCount < 7", block)
        self.assertIn("cardId ~= self.c.LASS", block)
        self.assertIn("row.type == self.c.TYPE_TRAINER", block)

    def test_effect_is_registered_and_discards_itself_before_scanning(self):
        self.assertIn('self:register("LassEffect"', self.effects_src)
        start = self.effects_src.index('self:register("LassEffect"')
        end = self.effects_src.index('self:register(', start + 1)
        block = self.effects_src[start:end]
        discard_pos = block.index("a.duelOps:putCardInDiscardPile(playedDeckIndex)")
        scan_pos = block.index("function shuffleHandTrainersIntoDeck")
        self.assertLess(discard_pos, scan_pos,
            "Lass must discard itself before its own hand-Trainer scan runs")
        self.assertIn("a.duelVars:swapTurn()", block)
        self.assertEqual(block.count("shuffleHandTrainersIntoDeck()"), 3)  # def + 2 calls
        self.assertIn("a.combat.setup:exchangeRNG()", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class LassExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Lass AI decision cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
