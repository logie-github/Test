import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class AISelectionAttachedEnergySourceTests(unittest.TestCase):
    def test_shared_defending_energy_picker_is_translated(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function aiPickEnergyCardToDiscardFromDefendingPokemon")
        end = src.index("local function selectDefendingEnergyForAI", start)
        block = src[start:end]
        self.assertIn("actor.duelVars:swapTurn()", block)
        self.assertIn("getPlayAreaCardAttachedEnergies", block)
        self.assertIn("createArenaOrBenchEnergyCardList", block)
        self.assertIn('actor.memory:address("wDuelTempList")', block)
        self.assertIn("return 0xff", block)

    def test_picker_prioritizes_colorless_then_defending_pokemon_color(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function aiPickEnergyCardToDiscardFromDefendingPokemon")
        end = src.index("local function selectDefendingEnergyForAI", start)
        block = src[start:end]
        self.assertIn("bit.band(energy.type, s.c.TYPE_PKMN)", block)
        self.assertIn("energyColor == s.c.COLORLESS", block)
        self.assertIn("energyColor == defender.type", block)
        self.assertIn("defender.type < s.c.COLORLESS", block)
        self.assertLess(block.index("if colorless ~= nil"), block.index("ownColor ~= nil"))

    def test_picker_uses_source_shuffle_fallback(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function aiPickEnergyCardToDiscardFromDefendingPokemon")
        end = src.index("local function selectDefendingEnergyForAI", start)
        block = src[start:end]
        self.assertIn("actor.duelOps.rng:shuffleCards(base, count)", block)
        self.assertIn('actor.memory:read8("wram", base, bank)', block)

    def test_hyper_beam_and_whirlpool_ai_selectors_store_temp_energy(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "GolduckHyperBeam_AISelectEffect",
            "Whirlpool_AISelectEffect",
            "DragonairHyperBeam_AISelectEffect",
        ):
            self.assertIn(f'self:register("{label}", selectDefendingEnergyForAI)', src)
        block = src[src.index("local function selectDefendingEnergyForAI"):
                    src.index("-- EnergyRemoval_AISelection::")]
        self.assertIn('s.memory:writeSymbol8("hTemp_ffa0", deckIndex)', block)

    def test_energy_removal_ai_selection_preserves_register_only_source_result(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        start = src.index('self:register("EnergyRemoval_AISelection"')
        end = src.index("-- AIFindTargetForBenchAttack::", start)
        block = src[start:end]
        self.assertIn("aiPickEnergyCardToDiscardFromDefendingPokemon", block)
        self.assertNotIn('writeSymbol8("hTemp_ffa0"', block)
        self.assertNotIn('writeSymbol8("hTempPlayAreaLocation_ffa1"', block)


if __name__ == "__main__":
    unittest.main()
