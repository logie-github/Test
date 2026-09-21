"""Clefairy Doll / Mysterious Fossil AI decision + effects (trainer_cards.asm
AIDecide_ClefairyDollOrMysteriousFossil, AIPlay_ClefairyDollOrMysteriousFossil
-- shared by both cards; effect_functions.asm ClefairyDoll_BenchCheck/
PlaceInPlayAreaEffect and MysteriousFossil_BenchCheck/PlaceInPlayAreaEffect).

The real threshold logic (the hard Play Area max, and the Wigglytuff-Active
override that bypasses the ordinary <4-Pokemon rule) is exercised for real
by lua_fixtures/clefairy_doll_smoke.lua under LuaJIT -- see
test_lua_execution_smoke below. These source-shape checks only confirm the
pieces are wired together and that both cards share one decision and one
pair of effect implementations, matching the source's own shared routine.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/clefairy_doll_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ClefairyDollSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")
        self.effects_src = read("src/tcg/duel/EffectCommands.lua")

    def test_both_cards_dispatch_to_the_shared_decision(self):
        self.assertIn(
            'elseif constantName == "CLEFAIRY_DOLL" or constantName == "MYSTERIOUS_FOSSIL" then\n'
            "    return self:_decideClefairyDollOrMysteriousFossil()",
            self.ai_src,
        )
        self.assertIn("CLEFAIRY_DOLL = true", self.ai_src)  # AI_TRAINER_SUPPORTED table
        self.assertIn("MYSTERIOUS_FOSSIL = true", self.ai_src)
        self.assertIn('"CLEFAIRY_DOLL", "MYSTERIOUS_FOSSIL" }', self.ai_src)

    def test_decide_checks_wigglytuff_override_and_threshold(self):
        start = self.ai_src.index("function AI:_decideClefairyDollOrMysteriousFossil")
        end = self.ai_src.index("\nfunction AI:", start + 1)
        block = self.ai_src[start:end]
        self.assertIn("self.c.MAX_PLAY_AREA_POKEMON", block)
        self.assertIn("self.c.WIGGLYTUFF", block)
        self.assertIn("count < 4", block)

    def test_both_cards_share_identical_effect_implementations(self):
        for label in ("MysteriousFossil_BenchCheck", "MysteriousFossil_PlaceInPlayAreaEffect",
                       "ClefairyDoll_BenchCheck", "ClefairyDoll_PlaceInPlayAreaEffect"):
            self.assertIn(f'self:register("{label}"', self.effects_src)
        self.assertIn("self:register(\"MysteriousFossil_BenchCheck\", trainerAsPokemonBenchCheck)",
                       self.effects_src)
        self.assertIn("self:register(\"ClefairyDoll_BenchCheck\", trainerAsPokemonBenchCheck)",
                       self.effects_src)

    def test_place_effect_uses_put_hand_pokemon_card_in_play_area(self):
        start = self.effects_src.index("local function trainerAsPokemonPlaceInPlayAreaEffect")
        end = self.effects_src.index("self:register(\"MysteriousFossil_BenchCheck\"")
        block = self.effects_src[start:end]
        self.assertIn('a.memory:readSymbol8("hTempCardIndex_ff9f")', block)
        self.assertIn("a.duelOps:putHandPokemonCardInPlayArea(deckIndex)", block)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class ClefairyDollExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Clefairy Doll / Mysterious Fossil AI decision cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
