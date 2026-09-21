import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def text(path):
    return (ROOT / path).read_text(encoding="utf-8")


class PracticePlayableSourceTests(unittest.TestCase):
    def test_boot_ram_matches_zero_ram_ranges(self):
        src = text("src/tcg/memory/Memory.lua")
        self.assertIn('function Memory:zeroBootRAM()', src)
        self.assertIn('self:zero("wram", 0xc000, 0x2000, 0)', src)
        self.assertIn('self:zero("hram", 0xff80, 0x70, 0)', src)

    def test_session_boots_source_practice_decks_and_main_loop_order(self):
        src = text("src/tcg/duel/PracticeSession.lua")
        for token in (
            'wOpponentDeckID", c.SAMS_PRACTICE_DECK_ID',
            'r.deckLoader:loadOpponentDeck()',
            'r.duelSetup:handleDuelSetup()',
            'r.status:updateSubstatusConditionsStartOfTurn()',
            'r.core:initVariablesToBeginTurn()',
            'r.duelOps:drawCardFromDeck()',
            'r.status:updateSubstatusConditionsEndOfTurn()',
            'r.status:handleBetweenTurnsEvents()',
            'r.duelVars:swapTurn()',
        ):
            self.assertIn(token, src)

    def test_player_actions_cover_all_scripted_practice_requirements(self):
        session = text("src/tcg/duel/PracticeSession.lua")
        actions = text("src/tcg/duel/PlayerActions.lua")
        for token in (
            'self.data.constants.GOLDEEN', 'c.SEAKING', 'self.data.constants.STARYU', 'c.STARMIE',
            'c.DROWZEE', 'kind="potion"', 'c.WATER_ENERGY', 'c.PSYCHIC_ENERGY',
            'c.FIRST_ATTACK_OR_PKMN_POWER', 'c.SECOND_ATTACK',
        ):
            self.assertIn(token, session)
        for token in (
            'putHandPokemonCardInPlayArea', 'putHandCardInPlayArea',
            'evolvePokemonCardIfPossible', 'moveHandCardToDiscardPile', 'combat:useAttack',
            'hTempPlayAreaLocation_ffa1', 'self.c.POTION',
        ):
            self.assertIn(token, actions)

    def test_sam_seven_turn_script_and_original_bug_are_native(self):
        src = text("src/tcg/duel/AI.lua")
        self.assertIn('function AI:performSamScriptedTurn()', src)
        for token in ('turn == 0', 'turn == 1', 'turn == 2', 'turn == 3',
                      'turn == 4', 'turn == 5 or turn == 6'):
            self.assertIn(token, src)
        self.assertIn('if arenaDeckIndex == self.c.MACHOP then target = target + 1 end -- source bug', src)
        self.assertIn('self.combat:useAttack(active, self.c.FIRST_ATTACK_OR_PKMN_POWER', src)
        self.assertNotIn('_required("samScriptedTurn")', src)

    def test_combat_routes_effects_through_generic_fail_closed_dispatcher(self):
        src = text("src/tcg/duel/Combat.lua")
        for token in (
            'CopyAttackDataAndDamage_FromDeckIndex',
            'self.effects:validatePhases',
            'self.effects:tryExecute',
            'EFFECTCMDTYPE_BEFORE_DAMAGE',
            'EFFECTCMDTYPE_AFTER_DAMAGE',
            'handleNoDamageOrEffectSubstatus', 'applyTransparencyIfApplicable',
            'checkSelfConfusionDamage', 'handleDamageReduction',
            'hTempPlayAreaLocation_ff9d", self.c.PLAY_AREA_ARENA',
            'self.knockouts:handlePendingResolution()',
        ):
            self.assertIn(token, src)
        self.assertNotIn('starmie_star_freeze', src)

    def test_game_has_explicit_practice_launch_switch(self):
        src = text("src/tcg/Game.lua")
        self.assertIn('POKEPORT_TCG_PRACTICE', src)
        self.assertIn('PracticeSession.new(self.data)', src)
        self.assertIn('PracticePlayable.new(self, session)', src)
        self.assertIn('and not practicePlayable', src)

    def test_practice_state_uses_gen1recomp_input(self):
        src = text("src/tcg/states/PracticePlayable.lua")
        for token in ('wasPressed("up")', 'wasPressed("down")',
                      'wasPressed("a")', 'wasPressed("b")'):
            self.assertIn(token, src)
        self.assertIn('self.session:availableActions()', src)
        self.assertIn('self.session:performAction(action)', src)
        self.assertIn('self.session:repeatTurn()', src)


if __name__ == "__main__":
    unittest.main()
