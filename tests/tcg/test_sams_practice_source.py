"""Sam's practice-duel scripted AI (engine/duel/ai/decks/sams_practice.asm),
closing out the last of the AI-decision-making ledger items (the remainder
of that pending entry's original "presentation and incidental UI state
writes" note was about menu/screen rendering around AIMakeDecision, not the
decision logic itself, which was already substantially translated before
this round -- this adds the missing real-execution proof).

AIPerformScriptedTurn's 7-turn script (turn index = floor(wDuelTurns / 2)):
turn 0 attaches Fighting Energy to the starting Machop; turn 1 plays Rattata
and attaches Fighting Energy to it; turn 2 evolves that Rattata into
Raticate and attaches Lightning Energy; turn 3 attaches a second Lightning
Energy to Raticate; turn 4 plays a second Machop to the Bench, attaches
Fighting Energy to it (scanning from Bench so it can't mismatch the first
Machop), then retreats -- via the source's own genuine bug, comparing the
Arena's DECK INDEX against the MACHOP CARD ID constant (different
namespaces, so it never fires for any realistic deck index, meaning
"normal practice" always retreats into PLAY_AREA_BENCH_1, not BENCH_2);
turns 5-6 repeat turn 0. By turn 4 the Arena is expected to hold Raticate
(AI:_retreatSamPractice's own precondition) -- not because Sam's own script
puts it there directly (it stays on the Bench through Sam's own actions),
but because the tutorial is designed for the player's attacks to knock out
the original Arena Machop first, triggering AI:koSwitch's Sam-specific
fallback (AI:getPlayAreaLocationOfRaticateOrRattata), which privileges
Raticate over Rattata as the replacement.

All of this is exercised for real by
lua_fixtures/sams_practice_smoke.lua under LuaJIT (32 checks, each turn
tested against a directly-constructed Play Area/hand precondition rather
than a full duel-engine replay of the preceding turns) -- see
test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/sams_practice_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class SamsPracticeSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")

    def _block(self, start_marker):
        start = self.ai_src.index(start_marker)
        end = self.ai_src.index("\nend", start)
        return self.ai_src[start:end]

    def test_is_sam_practice_scripted_turn_threshold(self):
        block = self._block("function AI:isSamPracticeScriptedTurn()")
        self.assertIn('self.memory:readSymbol8("wDuelTurns")', block)
        self.assertIn("< 7", block)

    def test_scripted_turn_dispatch_covers_all_seven_turns(self):
        block = self._block("function AI:performSamScriptedTurn()")
        for n in range(5):
            self.assertIn(f"turn == {n}", block)
        self.assertIn("turn == 5 or turn == 6", block)

    def test_turn_four_preserves_deck_index_vs_card_id_bug(self):
        block = self._block("function AI:performSamScriptedTurn()")
        self.assertIn("arenaDeckIndex == self.c.MACHOP", block)
        self.assertIn("-- source bug", block)

    def test_retreat_sam_practice_asserts_raticate_and_shuffles_energy(self):
        block = self._block("function AI:_retreatSamPractice(targetSlot)")
        self.assertIn("arenaId == self.c.RATICATE", block)
        self.assertIn("self.rng:shuffleCards(list, #energies)", block)

    def test_dispatch_wires_scripted_turn_into_do_turn(self):
        self.assertIn(
            'elseif label == "AIActionTable_SamPractice" then\n'
            "    if self:isSamPracticeScriptedTurn() then return self:performSamScriptedTurn() end",
            self.ai_src,
        )

    def test_ko_switch_prefers_sam_scripted_choice(self):
        block = self._block("function AI:koSwitch()")
        self.assertIn('label == "AIActionTable_SamPractice" and self:isSamPracticeScriptedTurn()', block)
        self.assertIn("self:getPlayAreaLocationOfRaticateOrRattata()", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class SamsPracticeExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Sam's practice scripted-turn cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
