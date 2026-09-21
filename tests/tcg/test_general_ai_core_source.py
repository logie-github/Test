import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class GeneralAICoreSourceTests(unittest.TestCase):
    def test_manifest_v5_includes_deck_ai_constants(self):
        manifest = read("tools/tcg/build_manifest.py")
        data = read("src/tcg/Data.lua")
        installer = read("tools/tcg/apply_foundation.py")
        self.assertIn('src/constants/deck_ai_constants.asm', manifest)
        self.assertIn('"schema": 5', manifest)
        self.assertIn('schema == 5', data)
        self.assertIn('tcg-rom-cache-v5:', installer)

    def test_runtime_wires_player_actions_back_into_ai(self):
        src = read("src/tcg/duel/Runtime.lua")
        self.assertIn("ai:setPlayerActions(playerActions)", src)

    def test_generic_action_tables_use_native_main_turn_core(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn('label == "AIActionTable_GeneralDecks"', src)
        self.assertIn("return self:mainTurnLogic(false)", src)
        self.assertIn('label == "AIActionTable_GeneralNoRetreat"', src)
        self.assertIn("return self:mainTurnLogic(true)", src)
        self.assertNotIn('self:_required("mainTurnLogic")', src)
        self.assertNotIn('self:_required("mainTurnLogicNoRetreat")', src)

    def test_init_ai_turn_vars_preserves_source_scratch_reset(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:initTurnVars()", src)
        for name in ("wPreviousAIFlags", "wAITriedAttack", "wUnused_cddc", "wAIRetreatedThisTurn"):
            self.assertIn(name, src)
        self.assertIn("wAIPokedexCounter", src)
        self.assertIn("wAIBarrierFlagCounter", src)
        self.assertIn("MEWTWO_LV53", src)

    def test_attack_scoring_keeps_source_thresholds_and_second_attack_tie(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:getAIScoreOfAttack", src)
        self.assertIn("local score = 0x50", src)
        self.assertIn("local selected, score = self.c.SECOND_ATTACK, second", src)
        self.assertIn("if first > second then", src)
        self.assertIn("if score < 0x50 then", src)
        self.assertIn("function AI:checkWhetherToSwitchToFirstAttack", src)

    def test_ai_damage_estimator_executes_ai_phase_and_common_modifiers(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:estimateDamageVersusDefendingCard", src)
        self.assertIn("EFFECTCMDTYPE_AI", src)
        self.assertIn("self.combat:applyDamageModifiers", src)
        self.assertIn("wAIMinDamage", src)
        self.assertIn("wAIMaxDamage", src)
        self.assertIn("function AI:_handleSpecialAIAttack", src)
        self.assertIn("function AI:_applyRecoilAIScore", src)
        self.assertNotIn('return nil, "untranslated_ai_high_recoil"', src)

    def test_reverse_damage_and_exact_ko_quirk_feed_common_scoring(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:estimateDamageFromDefendingPokemon", src)
        self.assertIn("function AI:checkIfDefendingPokemonCanKnockOut", src)
        self.assertIn("estimate.damage == hp", src)
        self.assertIn("poison = 40", src)
        self.assertIn("poison = 20", src)
        self.assertIn("score = satAdd(score, 5)", src)


    def test_energy_requirement_and_attachment_use_source_common_threshold(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:checkEnergyNeededForAttack", src)
        self.assertIn("self.combat.status:handleEnergyBurn()", src)
        self.assertIn("function AI:processAndTryToPlayEnergy", src)
        self.assertIn("bestScore < 0x85", src)
        self.assertIn("DOUBLE_COLORLESS_ENERGY", src)
        self.assertIn("self.rng:shuffleCards", src)

    def test_basic_and_evolution_play_are_native_but_bounded(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:decidePlayPokemonCard", src)
        self.assertIn("local score = 130", src)
        self.assertIn("score >= 180", src)
        self.assertIn("self.playerActions:playBasic", src)
        self.assertIn("self.playerActions:evolve", src)
        self.assertIn("checkIfCanEvolveInto", src)

    def test_trainer_phase_scanner_has_native_high_frequency_set_and_fails_closed_elsewhere(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("local AI_TRAINER_PHASES", src)
        self.assertIn('[4] = { "BILL", "ITEM_FINDER" }', src)
        for name in ("POTION", "DEFENDER", "PLUSPOWER", "SWITCH", "FULL_HEAL",
                     "ENERGY_SEARCH", "ENERGY_REMOVAL", "PROFESSOR_OAK"):
            self.assertIn(f'constantName == "{name}"', src)
        self.assertIn('"untranslated_ai_trainer:" .. constantName', src)
        self.assertIn("self:processHandTrainerCards(14)", src)

    def test_common_retreat_and_active_power_policy_are_native(self):
        src = read("src/tcg/duel/AI.lua")
        self.assertIn("function AI:decideWhetherToRetreat", src)
        self.assertIn("function AI:decideBenchPokemonToSwitchTo", src)
        self.assertIn("function AI:tryToRetreat", src)
        self.assertIn("function AI:processRetreat", src)
        self.assertNotIn('"untranslated_ai_retreat"', src)
        self.assertNotIn("self.adapters.processRetreat", src)
        self.assertIn("function AI:handleAIDamageSwap", src)
        self.assertIn("function AI:handleAIPkmnPowers", src)
        self.assertIn("function AI:handleAICowardice", src)
        self.assertNotIn('"untranslated_ai_pokemon_power"', src)
        self.assertNotIn("self.adapters.handlePokemonPowers", src)


if __name__ == "__main__":
    unittest.main()
