import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class CardEffectFamiliesSourceTests(unittest.TestCase):
    def test_multi_coin_helper_preserves_rng_and_link_boundary(self):
        src = read("src/tcg/duel/DuelSetup.lua")
        block = src[src.index("function DuelSetup:tossCoinATimes"):
                    src.index("local function block", src.index("function DuelSetup:tossCoinATimes"))]
        self.assertIn('"tossCoinATimesLink"', block)
        self.assertIn('self.rng:updateSources()', block)
        self.assertIn('wCoinTossNumHeads', block)
        self.assertIn('count == 0 and 1 or count', block)

    def test_common_substatus_families_are_registered(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "GrimerMinimizeEffect", "WartortleWithdrawEffect", "SeadraAgilityEffect",
            "HideInShellEffect", "FocusEnergyEffect", "DestinyBond_DestinyBondEffect",
            "Barrier_BarrierEffect", "OnixHardenEffect", "LightScreenEffect",
            "HorseaSmokescreenEffect", "SnivelEffect", "LeerEffect",
            "SandAttackEffect", "BoneAttackEffect", "TailWagEffect", "PounceEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn('s.status:applySubstatus1ToAttackingCard', src)
        self.assertIn('s.status:applySubstatus2ToDefendingCard', src)

    def test_multiplier_family_uses_shared_set_definite_damage(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        self.assertIn('function EffectCommands:_setDefiniteDamage', src)
        self.assertIn('function EffectCommands:_tossDamageMultiplier', src)
        for label in (
            "Twineedle_MultiplierEffect", "NidoranFFurySwipes_MultiplierEffect",
            "PoliwhirlDoubleslap_MultiplierEffect", "PinMissile_MultiplierEffect",
            "CometPunch_MultiplierEffect", "DancingEmbers_MultiplierEffect",
        ):
            self.assertIn(label, src)
        self.assertIn('StoneBarrage_MultiplierEffect', src)

    def test_healing_and_recoil_use_common_damage_state(self):
        effects = read("src/tcg/duel/EffectCommands.lua")
        combat = read("src/tcg/duel/Combat.lua")
        for label in (
            "GolbatLeechLifeEffect", "ButterfreeMegaDrainEffect", "AbsorbEffect",
            "TakeDownEffect", "SubmissionEffect", "JigglypuffDoubleEdgeEffect",
            "ChanseyDoubleEdgeEffect",
        ):
            self.assertIn(label, effects)
        self.assertIn('function EffectCommands:_healAttackingArena', effects)
        self.assertIn('function Combat:dealRecoilDamageToSelf', combat)
        self.assertIn('self:applyDamageModifiersToSelf', combat)

    def test_generic_trainer_path_uses_effect_dispatcher_and_discards_card(self):
        src = read("src/tcg/duel/PlayerActions.lua")
        start = src.index("function PlayerActions:playTrainer")
        block = src[start:src.index("function PlayerActions:usePotion", start)]
        ordered = [
            "EFFECTCMDTYPE_INITIAL_EFFECT_1",
            "EFFECTCMDTYPE_INITIAL_EFFECT_2",
            "EFFECTCMDTYPE_DISCARD_ENERGY",
            "EFFECTCMDTYPE_REQUIRE_SELECTION",
            "EFFECTCMDTYPE_BEFORE_DAMAGE",
        ]
        positions = [block.index(token) for token in ordered]
        self.assertEqual(positions, sorted(positions))
        self.assertIn('loadNonPokemonCardEffectCommands', block)
        self.assertIn('checkCantUseTrainerDueToEffect', block)
        self.assertIn('moveHandCardToDiscardPile', block)
        self.assertIn('exchangeRNG', block)

    def test_potion_bill_and_oak_are_dispatcher_handlers(self):
        effects = read("src/tcg/duel/EffectCommands.lua")
        actions = read("src/tcg/duel/PlayerActions.lua")
        for label in (
            "Potion_DamageCheck", "Potion_PlayerSelection", "Potion_HealEffect",
            "BillEffect", "ProfessorOakEffect",
        ):
            self.assertIn(f'self:register("{label}"', effects)
        self.assertIn('self:playTrainer(self.c.POTION, { playArea = slot })', actions)
        self.assertNotIn('function PlayerActions:usePotion(slot)\n  local deckIndex = self:findCardInHand', actions)

    def test_manual_pokemon_power_has_source_phase_subset(self):
        src = read("src/tcg/duel/Combat.lua")
        start = src.index("function Combat:usePokemonPower")
        block = src[start:src.index("-- UseAttackOrPokemonPower", start)]
        execution = block[block.index("local context ="): ]
        ordered = [
            "EFFECTCMDTYPE_INITIAL_EFFECT_2",
            "EFFECTCMDTYPE_REQUIRE_SELECTION",
            "exchangeRNG",
            "EFFECTCMDTYPE_BEFORE_DAMAGE",
        ]
        positions = [execution.index(token) for token in ordered]
        self.assertEqual(positions, sorted(positions))
        self.assertIn('checkIsIncapableOfUsingPkmnPower', block)
        self.assertIn('attack.category ~= self.c.POKEMON_POWER', block)


    def test_played_pokemon_trigger_power_is_preflighted_and_dispatched(self):
        combat = read("src/tcg/duel/Combat.lua")
        actions = read("src/tcg/duel/PlayerActions.lua")
        self.assertIn('function Combat:checkPlayedPokemonCardTrigger', combat)
        self.assertIn('function Combat:processPlayedPokemonCard', combat)
        self.assertIn('EFFECTCMDTYPE_PKMN_POWER_TRIGGER', combat)
        self.assertIn('self.effects:checkMatchingCommand', combat)
        self.assertIn('self.combat:checkPlayedPokemonCardTrigger(deckIndex)', actions)
        self.assertIn('self.combat:processPlayedPokemonCard(deckIndex, slot)', actions)

    def test_triggered_quickfreeze_is_registered_without_weakening_fail_closed_rule(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        self.assertIn('self:register("Quickfreeze_InitialEffect"', src)
        self.assertIn('self:register("Quickfreeze_Paralysis50PercentEffect"', src)
        self.assertIn('"untranslated_effect:" .. command.functionLabel', src)


if __name__ == "__main__":
    unittest.main()
