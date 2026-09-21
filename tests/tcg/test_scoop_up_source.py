"""Scoop Up AI decision + effect (trainer_cards.asm AIDecide_ScoopUp,
AIPlay_ScoopUp; effect_functions.asm ScoopUp_BenchCheck/PlayerSelection/
ReturnToHandEffect).

The real arithmetic (the KO/usability/energy-in-hand short-circuit, the
status/retreat-cost gate, and the 70%-max-HP damage threshold computed via
the source's own integer floor(rawDamage / floor(maxHP/10)) division rather
than a floating-point approximation) is exercised for real by
lua_fixtures/scoop_up_smoke.lua under LuaJIT -- see test_lua_execution_smoke
below. These source-shape checks confirm the pieces are wired together,
including the general path's dispatch to the Legendary Articuno/Ronald
deck-specific handlers (AI:_decideScoopUpLegendaryArticuno/Ronald) rather
than the earlier fail-closed boundary.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/scoop_up_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ScoopUpSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")
        self.effects_src = read("src/tcg/duel/EffectCommands.lua")

    def test_is_dispatched_and_marked_supported(self):
        self.assertIn(
            'elseif constantName == "SCOOP_UP" then\n'
            "    return self:_decideScoopUp()",
            self.ai_src,
        )
        self.assertIn('SCOOP_UP = true', self.ai_src)  # AI_TRAINER_SUPPORTED table
        self.assertIn('[10] = { "POTION", "GUST_OF_WIND", "ENERGY_RETRIEVAL", "MR_FUJI", "SCOOP_UP" },',
                       self.ai_src)

    def _block(self, start_marker):
        start = self.ai_src.index(start_marker)
        candidates = []
        for marker in ("\nfunction AI:", "\nlocal function", "\nreturn AI"):
            try:
                candidates.append(self.ai_src.index(marker, start + 1))
            except ValueError:
                pass
        return self.ai_src[start:min(candidates)]

    def test_decide_dispatches_to_legendary_deck_handlers(self):
        block = self._block("function AI:_decideScoopUp()")
        self.assertIn("LEGENDARY_ARTICUNO_DECK_ID", block)
        self.assertIn("self:_decideScoopUpLegendaryArticuno()", block)
        self.assertIn("LEGENDARY_RONALD_DECK_ID", block)
        self.assertIn("self:_decideScoopUpLegendaryRonald()", block)
        self.assertIn("checkIfAnyAttackKnocksOutDefendingCard", block)
        self.assertIn("_lookForEnergyNeededInHand", block)
        self.assertIn("countNumberOfEnergyCardsAttached", block)
        self.assertIn("self:_decideScoopUpArenaSwitch()", block)

    def test_legendary_articuno_checks_snorlax_before_scooping_bench(self):
        block = self._block("function AI:_decideScoopUpLegendaryArticuno")
        self.assertIn("self.c.ARTICUNO_LV37, self.c.PLAY_AREA_BENCH_1", block)
        snorlax_pos = block.index("self.c.SNORLAX")
        scoop_pos = block.index("self:_scoopBenchSlotIfNoEnergy(benchSlot)")
        self.assertLess(snorlax_pos, scoop_pos)
        self.assertIn("self.c.CHANSEY", block)
        self.assertIn("self:checkIfDefendingPokemonCanKnockOut()", block)
        self.assertIn("self:_decideScoopUpArenaSwitch()", block)

    def test_legendary_ronald_checks_articuno_then_zapdos_then_moltres(self):
        block = self._block("function AI:_decideScoopUpLegendaryRonald")
        articuno_pos = block.index("self.c.ARTICUNO_LV37")
        zapdos_pos = block.index("self.c.ZAPDOS_LV68")
        moltres_pos = block.index("self.c.MOLTRES_LV37")
        self.assertLess(articuno_pos, zapdos_pos)
        self.assertLess(zapdos_pos, moltres_pos)
        # Only the Articuno case re-checks Snorlax; Zapdos/Moltres go
        # straight to the no-energy-attached check.
        self.assertEqual(block.count("self.c.SNORLAX"), 1)
        self.assertEqual(block.count("self:_scoopBenchSlotIfNoEnergy"), 3)

    def test_scoop_bench_helper_checks_energy_and_omits_replacement(self):
        block = self._block("function AI:_scoopBenchSlotIfNoEnergy")
        self.assertIn("countNumberOfEnergyCardsAttached(slot) ~= 0", block)
        self.assertIn("{ playArea = slot }", block)
        self.assertNotIn("replacement", block)

    def test_effects_are_registered(self):
        for label in ("ScoopUp_BenchCheck", "ScoopUp_PlayerSelection", "ScoopUp_ReturnToHandEffect"):
            self.assertIn(f'self:register("{label}"', self.effects_src)

    def test_return_to_hand_effect_only_scoops_a_basic_pokemon(self):
        start = self.effects_src.index('self:register("ScoopUp_ReturnToHandEffect"')
        end = self.effects_src.index('self:register(', start + 1)
        block = self.effects_src[start:end]
        self.assertIn("row.stage == s.c.BASIC", block)
        self.assertIn("a.duelOps:movePlayAreaCardToDiscardPile(scoopSlot)", block)
        self.assertIn("a.duelOps:clearAllStatusConditions()", block)
        self.assertIn("a.duelOps:swapPlayAreaPokemon(benchSlot, s.c.PLAY_AREA_ARENA)", block)
        self.assertIn("a.duelOps:shiftAllPokemonToFirstPlayAreaSlots()", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class ScoopUpExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Scoop Up AI decision cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
