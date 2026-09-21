"""Mysterious Fossil / Clefairy Doll's synthetic "Discard" Power
(engine/duel/core.asm's TrainerToPkmnData patch and effect_commands.asm's
TrainerCardAsPokemonEffectCommands). Part of the broader card-effects
sweep.

The engine injects fake card data for these two Trainer-as-Pokemon cards
once placed in the Play Area (10 HP, UNABLE_RETREAT, a single fake Power
pointing at this effect list) since they have no printed attacks/Powers of
their own and can't retreat normally. Confirmed the exact same shape as the
already-translated Cowardice Power by reading both bodies directly: gate on
Play Area count alone (>=2, unlike Cowardice which also checks
CAN_EVOLVE_THIS_TURN), prompt for a Bench replacement only when the card is
the Active one (no prompt at all when Benched -- the source's own `ret nz`
on its stashed slot), then discard straight to the discard pile rather than
back to hand.

All of this is exercised for real by
lua_fixtures/trainer_card_as_pokemon_smoke.lua under LuaJIT (19 checks) --
see test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/trainer_card_as_pokemon_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class TrainerCardAsPokemonSourceTests(unittest.TestCase):
    def setUp(self):
        self.src = read("src/tcg/duel/EffectCommands.lua")

    def _block(self, start_marker):
        start = self.src.index(start_marker)
        end = self.src.index("\n  end)", start)
        return self.src[start:end]

    def test_bench_check_gates_on_play_area_count_only(self):
        block = self._block('self:register("TrainerCardAsPokemon_BenchCheck"')
        self.assertIn("DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) < 2", block)
        self.assertNotIn("CAN_EVOLVE_THIS_TURN", block)

    def test_player_select_switch_skips_prompt_when_not_active(self):
        block = self._block('self:register("TrainerCardAsPokemon_PlayerSelectSwitch"')
        self.assertIn("if slot ~= s.c.PLAY_AREA_ARENA then return false end", block)

    def test_discard_effect_discards_and_swaps_only_if_active(self):
        block = self._block('self:register("TrainerCardAsPokemon_DiscardEffect"')
        self.assertIn("actor.duelOps:movePlayAreaCardToDiscardPile(slot)", block)
        self.assertIn("actor.duelOps:swapArenaWithBenchPokemon(replacement)", block)
        self.assertIn("actor.duelOps:shiftAllPokemonToFirstPlayAreaSlots()", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class TrainerCardAsPokemonExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Trainer-card-as-Pokemon Discard Power cases passed", result.stdout)
        self.assertNotIn("FAIL  ", result.stdout)


if __name__ == "__main__":
    unittest.main()
