"""Pokemon Breeder AI decision + effect (trainer_cards.asm AIDecide_
PokemonBreeder, AIPlay_PokemonBreeder; effect_functions.asm PokemonBreeder_
HandPlayAreaCheck/PlayerSelection/EvolveEffect; home/duel.asm
CheckIfCanEvolveInto_BasicToStage2).

The real arithmetic (the CalculateFitness score's swap-nibble packing, the
Dragonite Lv41 evolution gate, and the two-pass forced-priority/general
fallback scan with its tie-breaking) is exercised for real by
lua_fixtures/pokemon_breeder_smoke.lua under LuaJIT -- see
test_lua_execution_smoke below. These source-shape checks only confirm the
pieces are wired together and that the two-hop Basic-to-Stage2 evolution
check (distinct from the one-hop checkIfCanEvolveInto used elsewhere) exists.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/pokemon_breeder_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class PokemonBreederSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")
        self.effects_src = read("src/tcg/duel/EffectCommands.lua")
        self.duelops_src = read("src/tcg/duel/DuelOps.lua")

    def test_pokemon_breeder_is_dispatched_and_marked_supported(self):
        self.assertIn(
            'elseif constantName == "POKEMON_BREEDER" then\n'
            "    return self:_decidePokemonBreeder()",
            self.ai_src,
        )
        self.assertIn('POKEMON_BREEDER = true', self.ai_src)  # AI_TRAINER_SUPPORTED table
        self.assertIn('"POTION", "GUST_OF_WIND", "POKEMON_BREEDER",', self.ai_src)

    def test_decide_covers_two_pass_structure(self):
        start = self.ai_src.index("function AI:_decidePokemonBreeder")
        end = self.ai_src.index("-- AICheckIfAttackIsHighRecoil", start)
        block = self.ai_src[start:end]
        for name in ("VENUSAUR_LV64", "VENUSAUR_LV67", "BLASTOISE", "VILEPLUME",
                     "ALAKAZAM", "GENGAR"):
            self.assertIn(name, block)
        self.assertIn("_dragoniteLv41Blocks", block)
        self.assertIn("bit.band(s, 0x0f) >= 2", block)

    def test_dragonite_gate_uses_both_thresholds(self):
        block = self.ai_src[self.ai_src.index("function AI:_dragoniteLv41Blocks"):
                             self.ai_src.index("function AI:_decidePokemonBreeder")]
        self.assertIn("damage < 5", block)
        self.assertIn("countNumberOfEnergyCardsAttached(slot) < 3", block)
        self.assertIn("totalCounters < 8", block)

    def test_basic_to_stage2_check_is_a_two_hop_lookup_not_the_one_hop_check(self):
        block = self.duelops_src[
            self.duelops_src.index("function DuelOps:checkIfCanEvolveIntoBasicToStage2"):
            self.duelops_src.index("function DuelOps:evolvePokemonCardIfPossible")]
        self.assertIn("loadBuffer1FromName", block)
        self.assertIn("stage1.preEvolutionTextId ~= current.nameTextId", block)

    def test_evolve_pokemon_card_raw_swap_is_shared_and_extracted(self):
        self.assertIn("function DuelOps:evolvePokemonCard(deckIndex, playAreaOffset)",
                       self.duelops_src)
        ifpossible = self.duelops_src[
            self.duelops_src.index("function DuelOps:evolvePokemonCardIfPossible"):
            self.duelops_src.index("function DuelOps:evolvePokemonCard(")]
        self.assertIn("return self:evolvePokemonCard(deckIndex, playAreaOffset)", ifpossible)

    def test_count_number_of_energy_cards_attached_halves_colorless(self):
        block = self.duelops_src[
            self.duelops_src.index("function DuelOps:countNumberOfEnergyCardsAttached"):]
        block = block[:block.index("\nend\n") + 5]
        self.assertIn("math.floor(colorless / 2)", block)

    def test_effects_are_registered(self):
        for label in (
            "PokemonBreeder_HandPlayAreaCheck", "PokemonBreeder_PlayerSelection",
            "PokemonBreeder_EvolveEffect",
        ):
            self.assertIn(f'self:register("{label}"', self.effects_src)

    def test_evolve_effect_marks_stage2_without_stage1(self):
        block = self.effects_src[self.effects_src.index("PokemonBreeder_EvolveEffect"):
                                  self.effects_src.index("PokemonBreeder_EvolveEffect") + 800]
        self.assertIn("STAGE2_WITHOUT_STAGE1", block)
        self.assertIn("checkPlayedPokemonCardTrigger", block)
        self.assertIn("processPlayedPokemonCard", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class PokemonBreederExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Pokemon Breeder AI decision cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
