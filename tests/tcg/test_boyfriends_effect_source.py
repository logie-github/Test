"""Nidoqueen's Boyfriends (engine/duel/effect_functions.asm), part of the
broader card-effects sweep.

+20 damage for every Nidoking in the attacker's own Play Area. Scans
DUELVARS_ARENA_CARD across the play area -- the same shape as
_playAreaDamage's other callers -- counts Nidoking, and adds 20 per match
onto the already-loaded printed damage via the shared _addToDamage helper
(AddToDamage in the source), confirmed as the real command list's single
EFFECTCMDTYPE_BEFORE_DAMAGE entry.

Exercised for real by lua_fixtures/boyfriends_effect_smoke.lua under
LuaJIT (12 checks) -- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/boyfriends_effect_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class BoyfriendsEffectSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def test_boyfriends_scans_own_play_area_and_adds_20_per_nidoking(self):
        start = self.src.index('self:register("BoyfriendsEffect"')
        end = self.src.index("\n  end)", start)
        block = self.src[start:end]
        self.assertIn("actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)", block)
        self.assertIn("actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot)", block)
        self.assertIn("actor.cardData:getCardIDFromDeckIndex(deckIndex) == s.c.NIDOKING", block)
        self.assertIn("s:_addToDamage(nidokingCount * 20)", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class BoyfriendsEffectExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all boyfriends effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
