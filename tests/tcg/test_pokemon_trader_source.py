"""Pokemon Trader AI decision boundary (trainer_cards.asm AIDecide_
PokemonTrader). The card's effect (PokemonTrader_HandDeckCheck/
PlayerHandSelection/PlayerDeckSelection/TradeCardsEffect) was already
translated in an earlier round; this only adds the AI decision side.

AIDecide_PokemonTrader has no general/default path at all -- only ten decks
(Legendary Moltres/Articuno/Dragonite/Ronald, Blistering Pokemon, Sound of
the Waves, Power Generator, Flower Garden, Strange Power, Flamethrower) ever
play this card, each through its own dedicated card-search routine (16 to
~100 ASM lines apiece) with no shared logic between most of them and no
fallback for any other deck. Translating those ten routines -- several
needing never-before-used card-search primitives shared with Computer
Search's own still-pending specialized-deck branches -- is left as a
dedicated, explicitly tracked gap rather than being rushed or approximated;
the boundary itself is exercised for real by
lua_fixtures/pokemon_trader_smoke.lua under LuaJIT -- see
test_lua_execution_smoke below.
"""

import pathlib
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/tcg/lua_fixtures/pokemon_trader_smoke.lua"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class PokemonTraderSourceTests(unittest.TestCase):
    def setUp(self):
        self.ai_src = read("src/tcg/duel/AI.lua")

    def test_is_dispatched_and_marked_supported(self):
        self.assertIn(
            'elseif constantName == "POKEMON_TRADER" then\n'
            "    return self:_decidePokemonTrader()",
            self.ai_src,
        )
        self.assertIn('POKEMON_TRADER = true', self.ai_src)  # AI_TRAINER_SUPPORTED table
        self.assertIn('"MAINTENANCE", "POKE_BALL", "COMPUTER_SEARCH", "POKEMON_TRADER"', self.ai_src)

    def test_decide_fails_closed_on_all_ten_specialized_decks(self):
        start = self.ai_src.index("POKEMON_TRADER_SPECIAL_DECKS")
        end = self.ai_src.index("function AI:_decidePokemonTrader")
        block = self.ai_src[start:end]
        for deck in (
            "LEGENDARY_MOLTRES_DECK_ID", "LEGENDARY_ARTICUNO_DECK_ID",
            "LEGENDARY_DRAGONITE_DECK_ID", "LEGENDARY_RONALD_DECK_ID",
            "BLISTERING_POKEMON_DECK_ID", "SOUND_OF_THE_WAVES_DECK_ID",
            "POWER_GENERATOR_DECK_ID", "FLOWER_GARDEN_DECK_ID",
            "STRANGE_POWER_DECK_ID", "FLAMETHROWER_DECK_ID",
        ):
            self.assertIn(deck, block)
        func_block = self.ai_src[self.ai_src.index("function AI:_decidePokemonTrader"):
                                  self.ai_src.index("-- AICheckIfAttackIsHighRecoil")]
        self.assertIn('"untranslated_ai_pokemon_trader_special_deck"', func_block)

    def test_effect_side_already_registered_from_a_prior_round(self):
        effects_src = read("src/tcg/duel/EffectCommands.lua")
        for label in ("PokemonTrader_HandDeckCheck", "PokemonTrader_PlayerHandSelection",
                     "PokemonTrader_PlayerDeckSelection", "PokemonTrader_TradeCardsEffect"):
            self.assertIn(f'self:register("{label}"', effects_src)


@unittest.skipUnless(shutil.which("luajit"), "luajit not available in this environment")
class PokemonTraderExecutionTests(unittest.TestCase):
    def test_lua_execution_smoke(self):
        result = subprocess.run(
            ["luajit", str(FIXTURE)], cwd=str(ROOT),
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
        self.assertIn("all Pokemon Trader AI decision cases passed", result.stdout)
        self.assertNotIn("FAIL", result.stdout)


if __name__ == "__main__":
    unittest.main()
