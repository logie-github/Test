"""Wail (engine/duel/effect_functions.asm), part of the broader
card-effects sweep.

Wail_BenchCheck: fails only if BOTH players' Benches are already full.
Wail_FillBenchEffect: fills each player's Bench -- opponent first, then
the attacker's own, matching the source's SwapTurn/.FillBench/SwapTurn/
.FillBench order for RNG parity -- with Basic Pokemon shuffled out of
that player's own Deck (reusing the already-translated
DuelOps:createDeckCardList/rng:shuffleCards/searchCardInDeckAndAddToHand/
addCardToHand/putHandPokemonCardInPlayArea/shuffleDeck), stopping once
the Bench is full or the shuffled Deck list runs out, and always
reshuffling the remaining Deck afterward unless that side's Deck was
empty to begin with.

Exercised for real by lua_fixtures/wail_effect_smoke.lua under LuaJIT
(20 checks) -- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/wail_effect_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class WailEffectSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def test_bench_check_only_fails_when_both_sides_are_full(self):
        start = self.src.index('self:register("Wail_BenchCheck"')
        end = self.src.index("\n  end)", start)
        block = self.src[start:end]
        self.assertIn(
            "if actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) < s.c.MAX_PLAY_AREA_POKEMON then\n"
            "      return false\n    end", block)
        self.assertIn(
            "return actor.duelVars:getNonTurn(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) "
            ">= s.c.MAX_PLAY_AREA_POKEMON", block)

    def test_fill_bench_processes_opponent_before_own_side(self):
        start = self.src.index('self:register("Wail_FillBenchEffect"')
        end = self.src.index("\n  end)", start)
        block = self.src[start:end]
        swap_at = block.index("actor.duelVars:swapTurn()")
        first_fill_at = block.index("fillBench(actor)", swap_at)
        second_swap_at = block.index("actor.duelVars:swapTurn()", first_fill_at)
        second_fill_at = block.index("fillBench(actor)", second_swap_at)
        self.assertLess(swap_at, first_fill_at)
        self.assertLess(first_fill_at, second_swap_at)
        self.assertLess(second_swap_at, second_fill_at)
        self.assertEqual(block.count("actor.duelVars:swapTurn()"), 2)

    def test_fill_bench_filters_to_basic_pokemon_and_reuses_primitives(self):
        start = self.src.index("local function fillBench(a)")
        end = self.src.index("\n    end\n\n", start)
        block = self.src[start:end]
        self.assertIn("a.duelOps:createDeckCardList()", block)
        self.assertIn("a.duelOps.rng:shuffleCards(base, #deck)", block)
        self.assertIn("row.type < s.c.TYPE_ENERGY and row.stage == s.c.BASIC", block)
        self.assertIn("a.duelOps:searchCardInDeckAndAddToHand(deckIndex)", block)
        self.assertIn("a.duelOps:addCardToHand(deckIndex)", block)
        self.assertIn("a.duelOps:putHandPokemonCardInPlayArea(deckIndex)", block)
        self.assertIn("a.duelOps:shuffleDeck()", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class WailEffectExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all wail effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
