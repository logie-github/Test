"""AI:_chooseRandomlyNotToDoAction (engine/duel/ai/core.asm
AIChooseRandomlyNotToDoAction / CheckIfNotABossDeckID /
CheckIfOpponentHasBossDeckID), closing out the "exact random-skip cadence"
half of the last open item on the shared Potion/Defender/PlusPower/Switch/
FullHeal/EnergySearch trainer_cards.asm ledger entry.

The source's probability table: 0% (never skip) once sReceivedLegendaryCards
is nonzero, or while wOpponentDeckID falls in the boss range
[LEGENDARY_MOLTRES_DECK_ID, MUSCLES_FOR_BRAINS_DECK_ID) -- note
MUSCLES_FOR_BRAINS_DECK_ID itself is the exclusive upper bound, so it is NOT
suppressed and instead falls into the 50% list below; 50% (Random(4) < 2) for
MusclesForBrains/BlisteringPokemon/WaterfrontPokemon/BoomBoomSelfdestruct/
Kaleidoscope/Reshuffle; 25% (Random(4) < 1, i.e. only roll==0) for every
other deck. AI:_chooseRandomlyNotToDoAction reproduces all three tiers and
the exact boundary, plus treats a pcall failure reading
sReceivedLegendaryCards (fresh/sparse SRAM) as zero rather than erroring,
matching zeroed hardware SRAM.

All of this is exercised for real by
lua_fixtures/random_action_skip_smoke.lua under LuaJIT (19 checks) -- see
test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/random_action_skip_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class RandomActionSkipSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")

    def _block(self, start_marker):
        start = self.ai_src.index(start_marker)
        end = self.ai_src.index("\nend", start)
        return self.ai_src[start:end]

    def test_suppressed_for_boss_deck_range_and_after_legendary_cards(self):
        block = self._block("function AI:_chooseRandomlyNotToDoAction()")
        self.assertIn('pcall(function() return self.memory:readSymbol8("sReceivedLegendaryCards") end)', block)
        self.assertIn("if receivedLegendaryCards ~= 0 then return false end", block)
        self.assertIn("deckId >= self.c.LEGENDARY_MOLTRES_DECK_ID", block)
        self.assertIn("deckId < self.c.MUSCLES_FOR_BRAINS_DECK_ID", block)
        self.assertIn("return false", block)

    def test_fifty_percent_list_matches_source_exactly(self):
        block = self._block("function AI:_chooseRandomlyNotToDoAction()")
        for name in ("MUSCLES_FOR_BRAINS_DECK_ID", "BLISTERING_POKEMON_DECK_ID",
                     "WATERFRONT_POKEMON_DECK_ID", "BOOM_BOOM_SELFDESTRUCT_DECK_ID",
                     "KALEIDOSCOPE_DECK_ID", "RESHUFFLE_DECK_ID"):
            self.assertIn(f"self.c.{name}] = true", block)

    def test_roll_thresholds_match_source_random_4(self):
        block = self._block("function AI:_chooseRandomlyNotToDoAction()")
        self.assertIn("self.rng:random(4)", block)
        self.assertIn("roll < (fiftyPercent[deckId] and 2 or 1)", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class RandomActionSkipExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all random action-skip cadence cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
