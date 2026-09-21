from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class AISelectionRecoverySpecialSourceTests(unittest.TestCase):
    def _read(self, rel):
        return (ROOT / rel).read_text(encoding="utf-8")

    def test_recover_families_check_energy_damage_select_discard_and_heal(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        for prefix in ("StarmieRecover", "KadabraRecover"):
            for suffix in (
                "_CheckEnergyHP", "_PlayerSelectEffect", "_AISelectEffect",
                "_DiscardEffect", "_HealEffect",
            ):
                self.assertIn(f'self:register("{prefix}{suffix}"', src)
        self.assertIn("local function recoverCheck(requiredType)", src)
        self.assertIn("return (damage or 0) < 10", src)
        self.assertIn("local function recoverAISelect(requiredType)", src)
        self.assertIn('writeSymbol8("hTemp_ffa0", values[1])', src)
        self.assertIn("return s:_healAttackingArena(context, damage)", src)

    def test_destiny_bond_uses_hTempList_first_byte_for_selected_psychic_energy(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index('self:register("DestinyBond_CheckEnergy"')
        end = src.index("local function validateDiscardEnergySelection", start)
        block = src[start:end]
        self.assertIn('self:register("DestinyBond_PlayerSelectEffect"', block)
        self.assertIn('self:register("DestinyBond_AISelectEffect"', block)
        self.assertIn("writeTempList(s, { deckIndex })", block)
        self.assertIn("writeTempList(s, { values[1] })", block)
        self.assertIn('s.memory:address("hTempList")', block)
        self.assertIn("actor.duelOps:putCardInDiscardPile", block)

    def test_energy_conversion_preserves_discard_order_and_up_to_two_selection(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        start = src.index('self:register("EnergyConversion_CheckEnergy"')
        end = src.index("local function energyAbsorptionCheck", start)
        block = src[start:end]
        self.assertIn('validateDiscardEnergySelection(s, context, "discardEnergies", 2)', block)
        self.assertIn('self:register("EnergyConversion_AISelectEffect", firstTwoDiscardEnergiesAI)', block)
        self.assertIn("combat:dealRecoilDamageToSelf(10)", block)
        self.assertIn("moveDiscardPileCardToHand(deckIndex)", block)
        self.assertIn("addCardToHand(deckIndex)", block)

    def test_both_mewtwo_energy_absorption_identities_are_registered(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        self.assertIn('{ "MewtwoAltEnergyAbsorption", "MewtwoEnergyAbsorption" }', src)
        for suffix in (
            "_CheckDiscardPile", "_PlayerSelectEffect", "_AISelectEffect", "_AddToHandEffect",
        ):
            self.assertIn(f'prefix .. "{suffix}"', src)
        self.assertIn("actor.duelVars:set(deckIndex, s.c.CARD_LOCATION_ARENA)", src)

    def test_special_energy_absorption_uses_hram_union_and_skips_generic_ai_selection(self):
        src = self._read("src/tcg/duel/AI.lua")
        start = src.index("function AI:_selectSpecialAttackParameters")
        end = src.index("-- AITryUseAttack::", start)
        block = src[start:end]
        self.assertIn("MEWTWO_ALT_LV60", block)
        self.assertIn("MEWTWO_LV60", block)
        self.assertIn('writeSymbol8("hTempPlayAreaLocation_ffa1", 0xff)', block)
        self.assertIn('self.memory:address("hTempRetreatCostCards")', block)
        self.assertIn('writeSymbol8("hTemp_ffa0", psychic)', block)
        self.assertIn('writeSymbol8("hTempPlayAreaLocation_ffa1", energyIndex)', block)
        prep_start = src.index("function AI:_prepareAttackSelections")
        prep_end = src.index("-- AIProcessAndTryToUseAttack::", prep_start)
        prep = src[prep_start:prep_end]
        self.assertIn("if not specialHandled then", prep)
        self.assertIn("EFFECTCMDTYPE_AI_SELECTION", prep)

    def test_energy_spike_special_branch_selects_lightning_and_target_before_generic_phase(self):
        ai = self._read("src/tcg/duel/AI.lua")
        start = ai.index("if self.c.ELECTRODE_LV35")
        end = ai.index("if self.c.MEW_LV23", start)
        block = ai[start:end]
        self.assertIn("self.c.SECOND_ATTACK", block)
        self.assertIn("self.c.LIGHTNING_ENERGY", block)
        self.assertIn('writeSymbol8("hTemp_ffa0", lightning)', block)
        self.assertIn("self:_selectEnergySpikeAttachmentTarget()", block)
        self.assertIn('writeSymbol8("hTempPlayAreaLocation_ffa1", slot)', block)
        effects = self._read("src/tcg/duel/EffectCommands.lua")
        e_start = effects.index('self:register("EnergySpike_AISelectEffect"')
        e_end = effects.index('self:register("EnergySpike_AttachEnergyEffect"', e_start)
        self.assertIn('writeSymbol8("hTemp_ffa0", 0xff)', effects[e_start:e_end])

    def test_devolution_and_teleport_special_branches_are_now_translated(self):
        src = self._read("src/tcg/duel/AI.lua")
        self.assertNotIn('"untranslated_ai_special_attack_parameters:DevolutionBeam"', src)
        self.assertNotIn('"untranslated_ai_special_attack_parameters:Teleport"', src)
        self.assertIn("self:_lookForCardThatIsKnockedOutOnDevolution()", src)
        self.assertIn("self:decideBenchPokemonToSwitchTo()", src)

    def test_energy_spike_player_and_after_damage_paths_are_present(self):
        src = self._read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "EnergySpike_DeckCheck", "EnergySpike_PlayerSelectEffect",
            "EnergySpike_AISelectEffect", "EnergySpike_AttachEnergyEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn("actor.duelOps:searchCardInDeckAndAddToHand(deckIndex)", src)
        self.assertIn("actor.duelOps:putHandCardInPlayArea(deckIndex, slot)", src)
        self.assertIn("actor.duelOps:shuffleDeck()", src)


if __name__ == "__main__":
    unittest.main()
