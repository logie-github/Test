from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class AISelectionFinalNineSourceTests(unittest.TestCase):
    def _read(self, rel):
        return (ROOT / rel).read_text(encoding="utf-8")

    def test_metronome_ai_selectors_are_literal_noops(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function metronomeAINoop")
        end = src.index("-- Mirror Move shared implementation", start)
        block = src[start:end]
        self.assertIn("return false", block)
        self.assertIn('self:register("ClefableMetronome_AISelectEffect", metronomeAINoop)', block)
        self.assertIn('self:register("ClefairyMetronome_AISelectEffect", metronomeAINoop)', block)
        self.assertNotIn("hTemp_ffa0", block)

    def test_mirror_move_ai_selection_handles_discard_and_amnesia(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function mirrorMoveAISelection")
        end = src.index("local function mirrorMoveBeforeDamage", start)
        block = src[start:end]
        self.assertIn('writeSymbol8("hTemp_ffa0", 0xff)', block)
        self.assertIn("LAST_TURN_EFFECT_DISCARD_ENERGY", block)
        self.assertIn("aiPickEnergyCardToDiscardFromDefendingPokemon", block)
        self.assertIn("LAST_TURN_EFFECT_AMNESIA", block)
        self.assertIn("amnesiaAISelect", block)

    def test_mirror_move_replays_damage_status_substatus_and_weakness(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function mirrorMoveBeforeDamage")
        end = src.index("-- Porygon Conversion", start)
        block = src[start:end]
        self.assertIn('s:_writeWord("wDamage", low + 0x100 * high)', block)
        self.assertIn("PSN_DBLPSN", block)
        self.assertIn("CNF_SLP_PRZ", block)
        self.assertIn("DUELVARS_ARENA_CARD_SUBSTATUS2", block)
        self.assertIn("DUELVARS_ARENA_CARD_LAST_TURN_CHANGE_WEAK", block)
        self.assertIn("DUELVARS_ARENA_CARD_CHANGED_WEAKNESS", block)
        self.assertIn('{ "SpearowMirrorMove", "PidgeottoMirrorMove" }', block)

    def test_conversion_ai_scans_bench_then_energy_then_random(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index("local function aiSelectConversionColor")
        end = src.index("local function selectConversionColor", start)
        block = src[start:end]
        self.assertIn("PLAY_AREA_BENCH_1", block)
        self.assertIn("attackHasEnoughEnergy", block)
        self.assertIn('readSymbol8("wTotalAttachedEnergies")', block)
        self.assertIn("actor.setup.rng:random(s.c.NUM_COLORED_TYPES)", block)
        self.assertIn('writeSymbol8("hTemp_ffa0", color)', block)

    def test_conversion2_prefers_defending_noncolorless_type(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index('self:register("Conversion2_AISelectEffect"')
        end = src.index('self:register("Conversion2_ChangeResistanceEffect"', start)
        block = src[start:end]
        self.assertIn("actor.duelVars:swapTurn()", block)
        self.assertIn("row.type ~= s.c.COLORLESS", block)
        self.assertIn('writeSymbol8("hTemp_ffa0", row.type)', block)
        self.assertIn("aiSelectConversionColor(s, actor)", block)

    def test_prophecy_ai_selector_is_ff_and_reorder_is_noop(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index('self:register("Prophecy_AISelectEffect"')
        end = src.index("-- Scavenge.", start)
        block = src[start:end]
        self.assertIn('writeSymbol8("hTemp_ffa0", 0xff)', block)
        self.assertIn("if side == 0xff then return false end", block)
        self.assertIn("searchCardInDeckAndAddToHand", block)
        self.assertIn("returnCardToDeck", block)

    def test_scavenge_ai_selects_first_psychic_and_first_trainer(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index('self:register("Scavenge_AISelectEffect"')
        end = src.index('self:register("Scavenge_DiscardEffect"', start)
        block = src[start:end]
        self.assertIn("createFilteredArenaEnergyList", block)
        self.assertIn("TYPE_ENERGY_PSYCHIC", block)
        self.assertIn("createTrainerDiscardList", block)
        self.assertIn('writeSymbol8("hTemp_ffa0", energies[1])', block)
        self.assertIn('writeSymbol8("hTempPlayAreaLocation_ffa1", trainers[1])', block)

    def test_wildfire_ai_uses_hram_union_zero_and_player_zero_carries(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        pstart = src.index('self:register("Wildfire_PlayerSelectEffect"')
        astart = src.index('self:register("Wildfire_AISelectEffect"', pstart)
        end = src.index('self:register("Wildfire_DiscardEnergyEffect"', astart)
        player = src[pstart:astart]
        ai = src[astart:end]
        self.assertIn("return #selected == 0", player)
        self.assertIn('s.memory:address("hTempList")', ai)
        self.assertIn('s.memory:write8("hram", base, 0, bank)', ai)

    def test_all_final_nine_identities_are_registered(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        explicit = (
            "ClefableMetronome_AISelectEffect", "ClefairyMetronome_AISelectEffect",
            "Conversion1_AISelectEffect", "Conversion2_AISelectEffect",
            "Prophecy_AISelectEffect", "Scavenge_AISelectEffect", "Wildfire_AISelectEffect",
        )
        for label in explicit:
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn('{ "SpearowMirrorMove", "PidgeottoMirrorMove" }', src)
        self.assertIn('prefix .. "_AISelection"', src)


if __name__ == "__main__":
    unittest.main()
