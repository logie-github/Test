"""Magneton's Magnetic Storm (engine/duel/effect_functions.asm), part of
the final batch of standalone attack effects closing the card-effects
sweep.

Gathers every Energy card attached anywhere in the attacker's own Play
Area (a fresh DECK_SIZE scan for CARD_LOCATION_PLAY_AREA-flagged, Energy-
typed cards -- not reusing any existing per-slot energy scan, since this
one spans the whole Play Area at once), shuffles them, and redistributes
them evenly across every Pokemon in that Play Area (floor(totalEnergy /
pokemonCount) each, consumed off the front of the shuffled list in Play
Area order), then randomly hands out the totalEnergy % pokemonCount
leftover cards one each to a random subset of Pokemon via a second
shuffle, this time of the slot indices themselves (reusing the existing
writeTempList helper and the hTempList buffer). Moves cards via
DuelOps:addCardToHand + DuelOps:putHandCardInPlayArea -- Energy
re-attachments to already-occupied slots, not new Pokemon placements,
so PutHandPokemonCardInPlayArea would be wrong here.

Exercised for real by lua_fixtures/magnetic_storm_effect_smoke.lua under
LuaJIT (24 checks) -- see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/magnetic_storm_effect_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class MagneticStormEffectSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def _block(self):
        start = self.src.index('self:register("MagneticStormEffect"')
        end = self.src.index("\n  end)", start)
        return self.src[start:end]

    def test_gathers_energy_cards_across_the_whole_play_area(self):
        block = self._block()
        self.assertIn("for deckIndex = 0, s.c.DECK_SIZE - 1 do", block)
        self.assertIn("bit.band(location, s.c.CARD_LOCATION_PLAY_AREA) ~= 0", block)
        self.assertIn("bit.band(row.type, bit.lshift(1, s.c.TYPE_ENERGY_F)) ~= 0", block)

    def test_computes_even_share_then_attaches_off_the_shuffled_list(self):
        block = self._block()
        self.assertIn("local perShare = math.floor(totalEnergy / pokemonCount)", block)
        self.assertIn("actor.duelOps.rng:shuffleCards(base, totalEnergy)", block)
        self.assertIn("actor.duelOps:addCardToHand(deckIndex)", block)
        self.assertIn("actor.duelOps:putHandCardInPlayArea(deckIndex, slot)", block)
        self.assertNotIn("putHandPokemonCardInPlayArea", block)

    def test_leftover_cards_go_to_a_randomly_shuffled_subset_of_slots(self):
        block = self._block()
        self.assertIn("local remainder = totalEnergy - perShare * pokemonCount", block)
        self.assertIn("if remainder > 0 then", block)
        self.assertIn("writeTempList(s, slots)", block)
        self.assertIn('actor.duelOps.rng:shuffleCards(slotBase, pokemonCount)', block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class MagneticStormEffectExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all magnetic storm effect cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
