"""Jigglypuff's Friendship Song (engine/duel/effect_functions.asm), part
of the broader card-effects sweep.

FriendshipSong_BenchCheck: fails if the attacker's own Bench is already
full.
FriendshipSong_AddToBench50PercentEffect: on heads, shuffles the
attacker's own Deck and adds the first Basic Pokemon found to the Bench
-- the same shuffle-then-scan shape as Wail_FillBenchEffect's fillBench,
via a new pickRandomBasicCardFromDeck helper that stops at the first
match instead of filling to capacity. The animation plays on heads
regardless of whether a Basic Pokemon turned up, confirmed by the real
ASM calling PlayAttackAnimationOverAttackingPokemon in both its
.put_in_bench and "none came" branches.

Exercised for real by lua_fixtures/friendship_song_effect_smoke.lua under
LuaJIT (21 checks) -- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/friendship_song_effect_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class FriendshipSongEffectSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def test_bench_check_fails_only_when_full(self):
        start = self.src.index('self:register("FriendshipSong_BenchCheck"')
        end = self.src.index("\n  end)", start)
        block = self.src[start:end]
        self.assertIn(
            "return actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) "
            ">= s.c.MAX_PLAY_AREA_POKEMON", block)

    def test_pick_random_basic_card_shuffles_then_scans(self):
        start = self.src.index("local function pickRandomBasicCardFromDeck(s, a, excludeCardId)")
        end = self.src.index("\n  end", start)
        block = self.src[start:end]
        self.assertIn("a.duelOps:createDeckCardList()", block)
        self.assertIn("a.duelOps.rng:shuffleCards(base, #deck)", block)
        self.assertIn("row.type < s.c.TYPE_ENERGY and row.stage == s.c.BASIC", block)

    def test_add_to_bench_sets_animation_before_checking_success(self):
        start = self.src.index('self:register("FriendshipSong_AddToBench50PercentEffect"')
        end = self.src.index("\n  end)", start)
        block = self.src[start:end]
        anim_at = block.index('s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_FRIENDSHIP_SONG)')
        pick_at = block.index("pickRandomBasicCardFromDeck(s, actor)")
        self.assertLess(anim_at, pick_at)
        self.assertIn("if result == s.c.TAILS then return false end", block)
        self.assertIn("actor.duelOps:searchCardInDeckAndAddToHand(deckIndex)", block)
        self.assertIn("actor.duelOps:putHandPokemonCardInPlayArea(deckIndex)", block)
        self.assertEqual(block.count("actor.duelOps:shuffleDeck()"), 2)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class FriendshipSongEffectExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all friendship song effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
