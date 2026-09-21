"""Pokemon Trader AI decision (trainer_cards.asm AIDecide_PokemonTrader and
its ten deck-specific branches). The card's effect (PokemonTrader_
HandDeckCheck/PlayerHandSelection/PlayerDeckSelection/TradeCardsEffect) was
already translated in an earlier round; this replaces an earlier
placeholder (which only implemented the "no general path" boundary and
failed closed for all ten decks that can actually play the card) with the
real per-deck search logic.

AIDecide_PokemonTrader has no general/default path at all -- only ten
decks (Legendary Moltres/Articuno/Dragonite/Ronald, Blistering Pokemon,
Sound of the Waves, Power Generator, Flower Garden, Strange Power,
Flamethrower) ever play this card. Seven of the ten share an evolution-
chain search shape (AI:_pokemonTraderEvolutionChainTarget): for each
evolution family in priority order, first try every stage transition's
"pre-evolution already out" case (hand or Play Area), then -- only if the
whole family's transitions missed -- every transition's "evolution already
in hand" case, before moving to the next family. PowerGenerator's own
Magnemite family uses a genuinely different pair order between its two
passes (Lv15-before-Lv13 on the Hand pass vs Lv13-before-Lv15 on the
Play-Area pass) -- a literal source asymmetry, confirmed against the real
ASM rather than assumed to be a transcription slip.

Trading a card away uses one of three different mechanisms depending on
the deck: AI:_checkIfHasCardIDInHand (Dragonite, Sound of the Waves,
Articuno's own hand-priority list -- despite its name, requires a SPARE
copy, only returning the *second* match found), AI:_findCardIDInHand
(Ronald -- a single copy is enough), or AI:_findDuplicatePokemonCards
(Blistering Pokemon, PowerGenerator, FlowerGarden, Flamethrower -- any
Pokemon duplicate anywhere in hand, with a documented source quirk where a
nested hand-pair scan keeps looping after a match so the LAST duplicate
pair found wins, not the first). Moltres and StrangePower instead use
AI:_lookForCardIDToTradeWithDifferentHandCard, a single combined primitive.

PowerGenerator's own evolution-chain search has a genuine source bug (a
missing `jr .no_carry`) that, when the whole chain misses, falls through
into the discard step with leftover register garbage from whichever of
three internal exit paths the last failed lookup took, standing in for the
target card -- not deterministically reproducible without emulating
registers, and not reimplemented; AI.lua instead fails closed exactly
where the chain search itself comes up empty.

All of this is exercised for real by
lua_fixtures/pokemon_trader_smoke.lua under LuaJIT (35 checks) -- see
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

    def _block(self, start_marker):
        start = self.ai_src.index(start_marker)
        candidates = []
        for marker in ("\nfunction AI:", "\nlocal function", "\nreturn AI"):
            try:
                candidates.append(self.ai_src.index(marker, start + 1))
            except ValueError:
                pass
        return self.ai_src[start:min(candidates)]

    def test_is_dispatched_and_marked_supported(self):
        self.assertIn(
            'elseif constantName == "POKEMON_TRADER" then\n'
            "    return self:_decidePokemonTrader()",
            self.ai_src,
        )
        self.assertIn('POKEMON_TRADER = true', self.ai_src)  # AI_TRAINER_SUPPORTED table
        self.assertIn('"MAINTENANCE", "POKE_BALL", "COMPUTER_SEARCH", "POKEMON_TRADER"', self.ai_src)

    def test_decide_dispatches_to_all_ten_specialized_decks(self):
        block = self._block("function AI:_decidePokemonTrader()")
        for deck, fn in (
            ("LEGENDARY_MOLTRES_DECK_ID", "LegendaryMoltres"),
            ("LEGENDARY_ARTICUNO_DECK_ID", "LegendaryArticuno"),
            ("LEGENDARY_DRAGONITE_DECK_ID", "LegendaryDragonite"),
            ("LEGENDARY_RONALD_DECK_ID", "LegendaryRonald"),
            ("BLISTERING_POKEMON_DECK_ID", "BlisteringPokemon"),
            ("SOUND_OF_THE_WAVES_DECK_ID", "SoundOfTheWaves"),
            ("POWER_GENERATOR_DECK_ID", "PowerGenerator"),
            ("FLOWER_GARDEN_DECK_ID", "FlowerGarden"),
            ("STRANGE_POWER_DECK_ID", "StrangePower"),
            ("FLAMETHROWER_DECK_ID", "Flamethrower"),
        ):
            self.assertIn(deck, block)
            self.assertIn(f"self:_decidePokemonTrader{fn}()", block)

    def test_evolution_chain_helper_tries_play_area_pass_before_hand_pass(self):
        block = self._block("function AI:_pokemonTraderEvolutionChainTarget")
        and_play_area_pos = block.index("_pokeBallGivenCardInHandAndPlayArea")
        hand_pos = block.index("_pokeBallGivenCardInHand(pair[1], pair[2])")
        self.assertLess(and_play_area_pos, hand_pos)
        self.assertIn("line.andPlayArea or line", block)
        self.assertIn("line.hand or line", block)

    def test_power_generator_magnemite_line_has_asymmetric_pass_order(self):
        block = self._block("function AI:_decidePokemonTraderPowerGenerator")
        and_play_area = self._extract_list(block, "andPlayArea = {", "},")
        hand = self._extract_list(block, "hand = {", "},")
        self.assertEqual(and_play_area[:2], ["self.c.MAGNEMITE_LV13", "self.c.MAGNETON_LV35"])
        self.assertEqual(hand[:2], ["self.c.MAGNEMITE_LV15", "self.c.MAGNETON_LV35"])
        self.assertNotIn("jr .no_carry", block)  # not reimplementing the source's fallthrough bug

    def _extract_list(self, block, start_marker, end_marker):
        start = block.index(start_marker) + len(start_marker)
        end = block.index(end_marker, start)
        return [t.strip() for t in block[start:end].replace("{", "").replace("}", "").split(",")
                if t.strip()]

    def test_check_if_has_card_id_in_hand_requires_a_spare_copy(self):
        block = self._block("function AI:_checkIfHasCardIDInHand")
        self.assertIn("seenOnce", block)
        self.assertIn("if seenOnce then return deckIndex end", block)

    def test_find_duplicate_pokemon_cards_keeps_the_last_match(self):
        block = self._block("function AI:_findDuplicatePokemonCards")
        self.assertIn("for j = i + 1, #hand do", block)
        self.assertIn("result = hand[j]", block)
        # No early return/break inside either loop on a match -- the scan
        # must run to completion so a later pair can overwrite `result`,
        # matching the documented "keeps looping" source quirk.
        self.assertNotIn("break", block)
        self.assertEqual(block.count("return"), 1)

    def test_dragonite_uses_spare_copy_and_ronald_uses_single_copy(self):
        dragonite = self._block("function AI:_decidePokemonTraderLegendaryDragonite")
        self.assertIn("self:_checkIfHasCardIDInHand(cardId)", dragonite)
        ronald = self._block("function AI:_decidePokemonTraderLegendaryRonald")
        self.assertIn("self:_findCardIDInHand(cardId)", ronald)
        self.assertNotIn("_checkIfHasCardIDInHand", ronald)

    def test_moltres_and_strange_power_share_the_trade_with_different_card_primitive(self):
        moltres = self._block("function AI:_decidePokemonTraderLegendaryMoltres")
        self.assertIn(
            "self:_lookForCardIDToTradeWithDifferentHandCard(\n    self.c.MOLTRES_LV37, self.c.MOLTRES_LV35)",
            moltres,
        )
        strange_power = self._block("function AI:_decidePokemonTraderStrangePower")
        self.assertIn(
            "self:_lookForCardIDToTradeWithDifferentHandCard(\n    self.c.MR_MIME, self.c.MR_MIME)",
            strange_power,
        )

    def test_dragonite_kangaskhan_gate_checks_energy_before_pokemon_count(self):
        block = self._block("function AI:_decidePokemonTraderLegendaryDragonite")
        energy_pos = block.index("_countEnergyCardsInHandAndAttached()")
        pokemon_pos = block.index("_countPokemonCardsInHandAndInPlayArea()")
        self.assertLess(energy_pos, pokemon_pos)

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
