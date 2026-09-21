"""AIDecide_EnergyRemoval's real target-priority logic
(engine/duel/ai/trainer_cards.asm).

AI:_decideEnergyRemoval() used to be a placeholder: grab the first Play Area
slot (starting from Arena) with ANY energy attached on the Player's side,
ignoring the source's real priority cascade. Now translated:

1. Decide a starting point: if the AI's own Active can already KO the
   Player's Active this turn AND that attack is usable now (or would become
   usable with Energy already in hand), the Player's Active isn't worth
   stripping -- start from the Bench. Otherwise start from the Active.
2. Scan from that point for the first card with Energy attached that
   currently has enough Energy for either attack (stripping it would
   disable an attack it could otherwise make right now) --
   AI:_checkIfNotEnoughEnergyToAttack (new). The "usable now, or would
   become usable with Energy in hand" check itself reuses the existing
   AI:_lookForEnergyNeededInHand rather than a new helper -- an earlier
   draft duplicated that logic under a new name before this was noticed.
3. If nothing qualifies, fall back to a Bench-only pass picking the card
   with the single highest-damage attack estimate, ignoring usability --
   AI:_findHighestDamagingBenchAttack (new).
4. A third source fallback -- re-checking the Player's Active specifically,
   reached only when the scan started from the Active -- is a dead branch:
   by the time it runs, the scan has always already advanced past the real
   Play Area slots to the first empty one, so it probes an out-of-range
   Play Area location code (CARD_LOCATION_PLAY_AREA | count) that no card
   is ever assigned (real location codes are DECK=$00/HAND=$01/
   DISCARD_PILE=$02, all outside the Play Area's own $10.. range), and so
   can never find Energy there. Documented in AI.lua, not reimplemented.

All of this is exercised for real by
lua_fixtures/energy_removal_target_smoke.lua under LuaJIT (22 checks) --
see test_lua_execution_smoke below. Part A runs the two new small helpers
against the real, already-existing checkEnergyNeededForAttack/
_surplusEnergyForAttack pipeline and a real memory-backed wAttachedEnergies
block; Part B isolates _decideEnergyRemoval's own control flow with those
already-proven-elsewhere collaborators stubbed.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/energy_removal_target_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class EnergyRemovalTargetSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")

    def _block(self, start_marker):
        start = self.ai_src.index(start_marker)
        candidates = []
        for marker in ("\nfunction AI:", "\nlocal function", "\nreturn AI"):
            try:
                candidates.append(self.ai_src.index(marker, start + 1))
            except ValueError:
                pass
        end = min(candidates)
        return self.ai_src[start:end]

    def test_look_for_energy_needed_handles_one_and_two_colorless_cases(self):
        # Pre-existing helper (LookForEnergyNeededForAttackInHand), already
        # used by _canKnockOutNowOrWithHandEnergy -- _decideEnergyRemoval
        # reuses it rather than duplicating the same logic under a new name.
        block = self._block("function AI:_lookForEnergyNeededInHand")
        self.assertIn("total == 1", block)
        self.assertIn("need.colored > 0", block)
        self.assertIn("self:_findCardIDInHand(need.energyCardId)", block)
        self.assertIn("#self:_energyCardsInHand() > 0", block)
        self.assertIn("total == 2 and need.colorless == 2", block)
        self.assertIn("self.c.DOUBLE_COLORLESS_ENERGY", block)

    def test_not_enough_energy_checks_surplus_on_the_second_attack(self):
        block = self._block("function AI:_checkIfNotEnoughEnergyToAttack")
        self.assertIn("self.c.FIRST_ATTACK_OR_PKMN_POWER", block)
        self.assertIn("self.c.SECOND_ATTACK", block)
        self.assertIn("self:_surplusEnergyForAttack(slot, self.c.SECOND_ATTACK)", block)
        self.assertIn("surplus ~= nil", block)

    def test_dead_arena_fallback_branch_is_documented_not_reimplemented(self):
        block = self._block("function AI:_decideEnergyRemoval")
        comment_start = self.ai_src.index("-- AIDecide_EnergyRemoval::")
        comment = self.ai_src[comment_start:self.ai_src.index("function AI:_decideEnergyRemoval")]
        self.assertIn("dead branch", comment)
        self.assertIn("CARD_LOCATION_", comment)
        self.assertNotIn("CARD_LOCATION_", block)

    def test_decide_energy_removal_wires_starting_point_then_scan_then_fallback(self):
        block = self._block("function AI:_decideEnergyRemoval")
        ko_pos = block.index("self:checkIfAnyAttackKnocksOutDefendingCard")
        usable_pos = block.index("self:_checkAttackUsableForAI")
        hand_pos = block.index("self:_lookForEnergyNeededInHand")
        swap_pos = block.index("self.duelVars:swapTurn()")
        scan_pos = block.index("self:_checkIfNotEnoughEnergyToAttack(slot)")
        fallback_pos = block.index("self:_findHighestDamagingBenchAttack(slot)")
        pick_pos = block.index("self:_pickAttachedEnergyToRemove(pickedSlot, false)")
        self.assertLess(ko_pos, usable_pos)
        self.assertLess(usable_pos, hand_pos)
        self.assertLess(hand_pos, swap_pos)
        self.assertLess(swap_pos, scan_pos)
        self.assertLess(scan_pos, fallback_pos)
        self.assertLess(fallback_pos, pick_pos)

    def test_decide_energy_removal_is_wired_into_the_trainer_dispatch(self):
        self.assertIn("self:_decideEnergyRemoval()", self.ai_src)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class EnergyRemovalTargetExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Energy Removal target-priority cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
