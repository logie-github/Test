from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class DeckAIListDataSourceTests(unittest.TestCase):
    def test_manifest_parses_all_specialized_deck_ai_list_families(self):
        src = read("tools/tcg/build_manifest.py")
        for name in (
            "wAICardListAvoidPrize", "wAICardListArenaPriority",
            "wAICardListBenchPriority", "wAICardListPlayFromHandPriority",
            "wAICardListRetreatBonus", "wAICardListEnergyBonus",
        ):
            self.assertIn(name, src)
        self.assertIn("parse_deck_ai_lists", src)
        self.assertIn("ai_retreat", src)
        self.assertIn("ai_energy", src)
        self.assertIn('"aiListsByActionTable": deck_ai_lists', src)

    def test_rom_extractor_cross_checks_list_bytes_and_missing_pointer_semantics(self):
        src = read("src/tcg/import/RomExtractor.lua")
        self.assertIn('spec.aiListsByActionTable', src)
        self.assertIn('aiListsByOpponentDeckId', src)
        self.assertIn('row.kind == "retreat_bonus"', src)
        self.assertIn('row.kind == "energy_bonus"', src)
        self.assertIn('self:byteAt(offset + 2) == entry.scoreByte', src)
        self.assertIn('local sourceLists = aiListSpecs[actionTableLabel] or {}', src)

    def test_play_from_hand_order_uses_generated_deck_pointer_list(self):
        src = read("src/tcg/duel/AI.lua")
        start = src.index("function AI:_handSnapshotForPokemonPlay")
        end = src.index("function AI:_isAttackUsableAtSlot", start)
        block = src[start:end]
        self.assertIn('self:_deckAIList("playFromHandPriority")', block)
        self.assertIn('local priority = list and list.cardIds or nil', block)
        self.assertNotIn('self.adapters.playFromHandPriority', block)

    def test_energy_and_retreat_bonus_lists_are_applied_from_generated_data(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn('self:_deckAIList("energyBonus")', src)
        self.assertIn('attached >= entry.maxEnergy', src)
        self.assertIn('self:_deckAIList("retreatBonus")', src)
        self.assertIn('if entry.cardId == cardId then', src)
        self.assertIn('Source bug/quirk: reaching the list cap subtracts 10', src)


if __name__ == "__main__":
    unittest.main()
