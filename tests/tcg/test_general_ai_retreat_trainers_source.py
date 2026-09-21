import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

class GeneralAIRetreatTrainerSourceTests(unittest.TestCase):
    def test_retreat_cost_includes_dodrio_and_muk(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:getPlayAreaCardRetreatCost", src)
        self.assertIn("self.c.DODRIO", src)
        self.assertIn("countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)", src)
        self.assertIn("math.max(0, row.retreatCost - dodrio)", src)

    def test_retreat_score_keeps_source_threshold_and_matchup_terms(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("local score = 0x80", src)
        self.assertIn("return score >= 131, score", src)
        self.assertIn("wAIRetreatFlags", src)
        self.assertIn("meta.resistance", src)
        self.assertIn("meta.weakness", src)
        self.assertIn("safeBench", src)

    def test_retreat_score_includes_boss_last_prize_and_setup_branches(self):
        src = read("src/tcg/duel/AI.lua")
        start = src.index("function AI:decideWhetherToRetreat")
        end = src.index("function AI:_energyIsUsefulForRetreat", start)
        block = src[start:end]
        self.assertIn("local notBossDeck = self:_checkIfNotABossDeckID()", block)
        self.assertIn('self.memory:writeSymbol8("wAIPlayEnergyCardForRetreat", self.c.TRUE)', block)
        self.assertIn("score = satAdd(score, 40)", block)
        self.assertIn("self:_checkIfArenaCardIsFullyPowered()", block)
        self.assertIn("local setup = self:_countNumberOfSetUpBenchPokemon()", block)
        self.assertIn("score = satAdd(score, setup)", block)
        self.assertIn("activeId == self.c.PORYGON", block)

    def test_fossil_and_doll_retreat_use_trainer_as_pokemon_discard_effect(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:_discardTrainerCardAsPokemonForRetreat", src)
        self.assertIn("self.duelOps:movePlayAreaCardToDiscardPile(self.c.PLAY_AREA_ARENA)", src)
        self.assertIn("self.duelOps:swapArenaWithBenchPokemon(targetSlot)", src)
        self.assertIn("self.duelOps:shiftAllPokemonToFirstPlayAreaSlots()", src)
        self.assertIn('self.memory:writeSymbol8("hAIPkmnPowerEffectParam", targetSlot)', src)
        self.assertNotIn('return nil, "untranslated_ai_fossil_retreat_power"', src)

    def test_bench_switch_score_keeps_50_baseline_and_later_tie(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:decideBenchPokemonToSwitchTo", src)
        self.assertIn("local score = 50", src)
        self.assertIn("if score >= bestScore then bestScore, bestSlot = score, slot end", src)
        self.assertIn("math.floor(estimate.damage / 10) + 1", src)
        self.assertIn("AI_INFO_BENCH_UTILITY", src)

    def test_retreat_payment_uses_dce_nonuseful_then_any_energy(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:tryToRetreat", src)
        self.assertIn("DOUBLE_COLORLESS_ENERGY", src)
        self.assertIn("self.rng:shuffleCards", src)
        self.assertIn("_energyIsUsefulForRetreat", src)
        self.assertIn("hTempRetreatCostCards", src)
        self.assertIn("confusion_retreat_failed", src)
        self.assertIn("self.duelOps:swapArenaWithBenchPokemon(targetSlot)", src)

    def test_switch_substitutes_for_normal_retreat(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:processRetreat", src)
        self.assertIn("self:processHandTrainerCards(9)", src)
        self.assertIn("AI_FLAG_USED_SWITCH", src)
        self.assertIn('return true, "switch_trainer"', src)

    def test_high_frequency_trainer_decisions_are_native(self):
        src = read("src/tcg/duel/AI.lua")
        for fn in ("_decidePotion", "_decideDefender", "_decidePlusPower", "_decideSwitch",
                   "_decideFullHeal", "_decideEnergySearch", "_decideProfessorOak",
                   "_decideEnergyRemoval"):
            self.assertIn(f"function AI:{fn}", src)
        self.assertIn("playerActions:playTrainer", src)
        self.assertIn("AI_FLAG_USED_PLUSPOWER", src)
        self.assertIn("AI_FLAG_USED_PROFESSOR_OAK", src)

    def test_oak_repeats_common_sequence_but_skips_second_phase15(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("AIMainTurnLogic repeats the hand-processing sequence once", src)
        self.assertIn("AI_FLAG_USED_PROFESSOR_OAK", src)
        self.assertIn("local a,b=trainer(13)", src)

    def test_energy_trans_ai_modes_are_native_and_not_manual_power_blockers(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:handleAIEnergyTrans", src)
        self.assertIn('mode == "attack"', src)
        self.assertIn('mode == "retreat"', src)
        self.assertIn('mode == "to_bench"', src)
        self.assertIn('self:handleAIEnergyTrans("attack")', src)
        self.assertIn('self:handleAIEnergyTrans("to_bench")', src)
        self.assertIn('function AI:handleAIDamageSwap', src)
        self.assertIn('function AI:handleAIPkmnPowers', src)
        self.assertIn('function AI:handleAICowardice', src)
        self.assertNotIn('local activePowerIds = { self.c.ALAKAZAM, self.c.TENTACOOL }', src)

    def test_random_action_skip_gate_matches_source_deck_classes(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:_chooseRandomlyNotToDoAction", src)
        self.assertIn('readSymbol8("sReceivedLegendaryCards")', src)
        self.assertIn("LEGENDARY_MOLTRES_DECK_ID", src)
        self.assertIn("MUSCLES_FOR_BRAINS_DECK_ID", src)
        for name in ("BLISTERING_POKEMON_DECK_ID", "WATERFRONT_POKEMON_DECK_ID",
                     "BOOM_BOOM_SELFDESTRUCT_DECK_ID", "KALEIDOSCOPE_DECK_ID",
                     "RESHUFFLE_DECK_ID"):
            self.assertIn(name, src)
        self.assertIn("self.rng:random(4)", src)
        # processHandTrainerCards calls this before the card-specific decision
        # (elseif form, since it also gates on the headache/INITIAL_EFFECT_1
        # checks that now run ahead of it); other call sites use the plain
        # early-return form.
        self.assertIn("elseif self:_chooseRandomlyNotToDoAction() then", src)
        self.assertIn("if self:_chooseRandomlyNotToDoAction() then return false end", src)

    def test_next_common_trainer_decision_set_is_native(self):
        src = read("src/tcg/duel/AI.lua")
        for fn in ("_decidePokedex", "_decideRecycle", "_decideMaintenance",
                   "_decideItemFinder", "_decideRevive", "_decidePokemonFlute",
                   "_decidePokemonCenter", "_decideMrFuji"):
            self.assertIn(f"function AI:{fn}", src)
        self.assertIn("Preserve the source branch bug: Kangaskhan is unreachable", src)
        self.assertIn("topDeckOrder = order", src)
        self.assertIn("discardTrainer = energyRemoval", src)
        self.assertIn("opponentDiscardBasicPokemon = selected", src)
        self.assertIn("self.c.AI_FLAG_MODIFIED_HAND", src)

    def test_remaining_common_trainer_priority_batch_is_native(self):
        src = read("src/tcg/duel/AI.lua")
        for fn in ("_decideEnergyRetrieval", "_decideSuperEnergyRetrieval",
                   "_decideSuperEnergyRemoval", "_decideGustOfWind",
                   "_decidePokeBall"):
            self.assertIn(f"function AI:{fn}", src)
        self.assertIn("GO_GO_RAIN_DANCE_DECK_ID", src)
        self.assertIn("FIRE_CHARGE_DECK_ID", src)
        self.assertIn("LOVELY_NIDORAN_DECK_ID", src)
        self.assertIn("PickTwoAttachedEnergyCards' source quirk", src)
        self.assertIn("AI_FLAG_USED_GUST_OF_WIND", src)
        self.assertIn("opponentEnergyDeckIndexes = opponentEnergies", src)
        self.assertIn("discardBasicEnergies = energies", src)
        self.assertIn("deckPokemon = deckIndex", src)

if __name__ == "__main__":
    unittest.main()
