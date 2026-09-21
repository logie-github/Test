from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class AIEnergyPolicySourceTests(unittest.TestCase):
    def test_energy_requirement_scoring_covers_source_branches_and_ko_double_bonus(self):
        src = read("src/tcg/duel/AI.lua")
        block = src[src.index("function AI:_estimateEnergyScoreAttack"):src.index("function AI:_opponentHasBossDeckID")]
        self.assertIn("ATTACHED_ENERGY_BOOST_F", block)
        self.assertIn("DISCARD_ENERGY_F", block)
        self.assertIn("MAX_ENERGY_BOOST_IS_LIMITED", block)
        self.assertIn("self:_surplusEnergyForAttack", block)
        self.assertIn("score = satAdd(satAdd(score, 20), 10)", block)
        self.assertIn("evolutionDeckIndex", block)

    def test_energy_card_selection_preserves_special_dce_and_boss_dce_rules(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:_specialDoubleColorlessForEnergyTarget", src)
        self.assertIn("LEGENDARY_DRAGONITE_DECK_ID", src)
        self.assertIn("FIRE_CHARGE_DECK_ID", src)
        self.assertIn("LEGENDARY_RONALD_DECK_ID", src)
        self.assertIn("function AI:_boostOrDiscardEnergyNeed", src)
        self.assertIn("ZAPDOS_LV64", src)
        self.assertIn("CHARIZARD", src)
        self.assertIn("EXEGGUTOR", src)
        self.assertIn("self:_opponentHasBossDeckID() and cardId == self.c.DOUBLE_COLORLESS_ENERGY", src)

    def test_articuno_and_repeated_bench_energy_scoring_are_native(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:_legendaryArticunoEnergyDeltas", src)
        self.assertIn("self.c.LAPRAS", src)
        self.assertIn("self.c.ARTICUNO_LV35", src)
        self.assertIn("self.c.DEWGONG", src)
        self.assertIn("self.c.SEEL", src)
        self.assertIn("function AI:_repeatedBenchEnergyDeltas", src)
        self.assertIn("self:_countAttachedEnergyCards(slot) * 2", src)
        self.assertIn("slot == bestSlot and 1 or -1", src)

    def test_main_energy_loop_has_source_early_gate_and_generated_bonus_list(self):
        src = read("src/tcg/duel/AI.lua")
        block = src[src.index("function AI:processAndTryToPlayEnergy"):src.index("function AI:_damageAt", src.index("function AI:processAndTryToPlayEnergy"))]
        self.assertIn("if not row or not self:_handHasUsefulEnergyFor(row) then", block)
        self.assertIn('self:_deckAIList("energyBonus")', block)
        self.assertIn("articunoDeltas", block)
        self.assertIn("repeatedDeltas", block)
        self.assertIn("bestScore < 0x85", block)
        self.assertIn("self:_tryToPlayEnergyCard(bestSlot, handEnergy)", block)

    def test_energy_trans_uses_skip_evolution_skip_arena_preview_with_score_restore(self):
        src = read("src/tcg/duel/AI.lua")
        start = src.index("function AI:_previewBenchEnergyTargetSkipEvolution")
        end = src.index("-- GetCardOneStageBelow::", start)
        block = src[start:end]
        self.assertIn('self.memory:address("wPlayAreaAIScore")', block)
        self.assertIn('local savedAIScore = self.memory:readSymbol8("wAIScore")', block)
        self.assertIn("for slot = self.c.PLAY_AREA_ARENA, count - 1 do", block)
        self.assertIn("slot >= self.c.PLAY_AREA_BENCH_1 and score > bestScore", block)
        self.assertNotIn("bestScore < 0x85", block)
        self.assertIn("restore()", block)
        self.assertIn('self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", bestSlot)', block)

    def test_energy_trans_repreviews_before_each_grass_transfer(self):
        src = read("src/tcg/duel/AI.lua")
        start = src.index("function AI:handleAIEnergyTrans")
        end = src.index("function AI:_usePokemonPowerForAI", start)
        block = src[start:end]
        self.assertIn("local previewTarget, previewErr = self:_bestBenchEnergyTransTarget()", block)
        self.assertIn("for _, deckIndex in ipairs(arenaGrass) do", block)
        self.assertIn("local target, targetErr = self:_bestBenchEnergyTransTarget()", block)


if __name__ == "__main__":
    unittest.main()
