import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
DUEL = ROOT / "src/tcg/duel"


class NativeDuelModuleTests(unittest.TestCase):
    def read(self, name):
        return (DUEL / name).read_text(encoding="utf-8")

    def test_ai_uses_extracted_deck_action_table_and_source_prize_rng(self):
        text = self.read("AI.lua")
        self.assertIn("aiByOpponentDeckId", text)
        self.assertIn('label == "AIActionTable_GeneralDecks"', text)
        self.assertIn('label == "AIActionTable_SamPractice"', text)
        self.assertIn("self.rng:random(6)", text)
        self.assertIn("self.duelOps:addCardToHand(deckIndex)", text)

    def test_ai_generic_ko_policy_still_fails_closed(self):
        text = self.read("AI.lua")
        self.assertIn('"decideBenchPokemonToSwitchTo"', text)
        self.assertNotIn("highestHP", text)

    def test_status_preserves_source_clairvoyance_order(self):
        text = self.read("Status.lua")
        start = text.index("function Status:isClairvoyanceActive()")
        block = text[start:text.index("function Status:isArenaPokemonAsleepOrPoisoned", start)]
        self.assertLess(block.index("self.c.MUK"), block.index("self.c.OMANYTE"))
        self.assertIn("if muk then return false end", block)

    def test_status_turn_boundary_mutations_are_native(self):
        text = self.read("Status.lua")
        self.assertIn("updateSubstatusConditionsStartOfTurn", text)
        self.assertIn("updateSubstatusConditionsEndOfTurn", text)
        self.assertIn("SUBSTATUS3_HEADACHE_F", text)
        self.assertIn("SUBSTATUS3_THIS_TURN_DOUBLE_DAMAGE_F", text)
        self.assertIn("handlePoisonDamage", text)
        self.assertIn("handleSleepCheck", text)

    def test_prize_selection_keeps_source_selected_list_and_mask(self):
        text = self.read("Prizes.lua")
        self.assertIn('"wSelectedPrizeCardListPtr"', text)
        self.assertIn('"hTempPlayAreaLocation_ffa1"', text)
        self.assertIn('self.memory:writeSymbol8("hTemp_ffa0", prizes)', text)
        self.assertIn("self.duelOps:addCardToHand(deckIndex)", text)

    def test_knockout_result_table_is_rom_extracted(self):
        text = self.read("KnockOuts.lua")
        self.assertIn("coreData.duelFinishTable", text)
        self.assertIn("finishTable[finishParam + 1]", text)
        self.assertIn("rollCarry", text)

    def test_play_area_insert_clears_all_source_fields(self):
        text = self.read("DuelOps.lua")
        start = text.index("function DuelOps:putHandPokemonCardInPlayArea")
        block = text[start:text.index("function DuelOps:putCardInDiscardPile", start)]
        for name in [
            "DUELVARS_ARENA_CARD_FLAGS",
            "DUELVARS_ARENA_CARD_CHANGED_TYPE",
            "DUELVARS_ARENA_CARD_ATTACHED_PLUSPOWER",
            "DUELVARS_ARENA_CARD_ATTACHED_DEFENDER",
        ]:
            self.assertIn(name, block)

    def test_save_snapshot_updates_source_temp_card_ids(self):
        text = self.read("SaveData.lua")
        self.assertIn('self.memory:writeSymbol8("wTempTurnDuelistCardID", turnCardId)', text)
        self.assertIn('self.memory:writeSymbol8("wTempNonTurnDuelistCardID", nonTurnCardId)', text)
        self.assertIn('SNAPSHOT_DATA_OFFSET = 0x10', text)

    def test_duel_interface_separates_player_link_and_ai_paths(self):
        text = self.read("DuelInterface.lua")
        self.assertIn('"playerDuelMenu"', text)
        self.assertIn('"linkOpponentTurn"', text)
        self.assertIn('self.ai:doTurn()', text)
        self.assertIn('self.memory:writeSymbol8("wPlayerAttackingCardIndex", 0xff)', text)

    def test_runtime_wires_native_subsystems(self):
        text = self.read("Runtime.lua")
        for module in ["SaveData", "Practice", "AI", "Status", "Prizes", "KnockOuts", "DuelInterface"]:
            self.assertIn(f'local {module} = require(', text)
        self.assertIn("status:setKnockOuts(knockouts)", text)


if __name__ == "__main__":
    unittest.main()
