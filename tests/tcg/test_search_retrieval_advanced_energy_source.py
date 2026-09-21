import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class SearchRetrievalAdvancedEnergySourceTests(unittest.TestCase):
    def test_search_helpers_validate_locations_and_basic_energy(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        self.assertIn("function EffectCommands:_isBasicEnergy", src)
        self.assertIn("TYPE_ENERGY_DOUBLE_COLORLESS", src)
        self.assertIn("function EffectCommands:_cardsAtLocation", src)
        self.assertIn("function EffectCommands:_selectionList", src)
        self.assertIn("function EffectCommands:_validateHandSelection", src)

    def test_energy_search_uses_deck_selection_and_source_shuffle(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "EnergySearch_DeckCheck", "EnergySearch_PlayerSelection",
            "EnergySearch_AddToHandEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn('"deckBasicEnergy"', src)
        self.assertIn('CARD_LOCATION_DECK', src)
        self.assertIn('searchCardInDeckAndAddToHand', src)
        self.assertIn('actor.duelOps:shuffleDeck()', src)

    def test_energy_retrieval_translates_hand_cost_and_discard_recovery(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "EnergyRetrieval_HandEnergyCheck", "EnergyRetrieval_PlayerHandSelection",
            "EnergyRetrieval_PlayerDiscardPileSelection",
            "EnergyRetrieval_DiscardAndAddToHandEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn('"handDiscard"', src)
        self.assertIn('"discardBasicEnergies"', src)
        self.assertIn('moveDiscardPileCardToHand', src)

    def test_computer_search_and_item_finder_share_two_hand_card_cost(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        self.assertIn("local function selectTwoHandCards", src)
        self.assertIn("local function discardHandCards", src)
        for label in (
            "ComputerSearch_HandDeckCheck", "ComputerSearch_PlayerDiscardHandSelection",
            "ComputerSearch_PlayerDeckSelection", "ComputerSearch_DiscardAddToHandEffect",
            "ItemFinder_HandDiscardPileCheck", "ItemFinder_PlayerSelection",
            "ItemFinder_DiscardAddToHandEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn('"deckCard"', src)
        self.assertIn('"discardTrainer"', src)

    def test_super_energy_retrieval_and_removal_support_multi_selection(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "SuperEnergyRetrieval_HandEnergyCheck",
            "SuperEnergyRetrieval_PlayerHandSelection",
            "SuperEnergyRetrieval_PlayerDiscardPileSelection",
            "SuperEnergyRetrieval_DiscardAndAddToHandEffect",
            "SuperEnergyRemoval_EnergyCheck", "SuperEnergyRemoval_PlayerSelection",
            "SuperEnergyRemoval_DiscardEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn('"opponentEnergyDeckIndexes"', src)
        self.assertIn('"ownEnergyDeckIndex"', src)
        self.assertIn('{ basicEnergy = true, max = 4 }', src)

    def test_rain_dance_is_integrated_into_energy_attachment(self):
        actions = read("src/tcg/duel/PlayerActions.lua")
        status = read("src/tcg/duel/Status.lua")
        effects = read("src/tcg/duel/EffectCommands.lua")
        self.assertIn("function Status:isRainDanceActive", status)
        self.assertIn("BLASTOISE", status)
        self.assertIn("function Status:getPlayAreaCardColor", status)
        self.assertIn("TYPE_ENERGY_WATER", actions)
        self.assertIn("TYPE_PKMN_WATER", actions)
        self.assertIn("if not rainDance then self.memory:writeSymbol8", actions)
        self.assertIn('self:register("RainDanceEffect"', effects)

    def test_energy_trans_accepts_repeated_host_transfer_sequence(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "EnergyTrans_CheckPlayArea", "EnergyTrans_PrintProcedure",
            "EnergyTrans_TransferEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn('"energyTransfers"', src)
        self.assertIn('TYPE_ENERGY_GRASS', src)
        self.assertIn('addCardToHand(deckIndex)', src)
        self.assertIn('putHandCardInPlayArea(deckIndex, dest)', src)

    def test_energy_burn_is_no_longer_a_hard_fail(self):
        combat = read("src/tcg/duel/Combat.lua")
        status = read("src/tcg/duel/Status.lua")
        effects = read("src/tcg/duel/EffectCommands.lua")
        self.assertNotIn('"untranslated_energy_burn"', combat)
        self.assertIn("self.status:handleEnergyBurn()", combat)
        self.assertIn("function Status:handleEnergyBurn", status)
        self.assertIn('self:register("EnergyBurnEffect"', effects)

    def test_pokemon_trader_and_pokedex_use_validated_deck_state(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "PokemonTrader_HandDeckCheck", "PokemonTrader_PlayerHandSelection",
            "PokemonTrader_PlayerDeckSelection", "PokemonTrader_TradeCardsEffect",
            "Pokedex_DeckCheck", "Pokedex_PlayerSelection",
            "Pokedex_OrderDeckCardsEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn('"handPokemon"', src)
        self.assertIn('"deckPokemon"', src)
        self.assertIn('"topDeckOrder"', src)
        self.assertIn('for i = #order, 1, -1', src)

    def test_maintenance_recycle_full_heal_and_pokeball_are_translated(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "Maintenance_HandCheck", "Maintenance_PlayerSelection",
            "Maintenance_ReturnToDeckAndDrawEffect",
            "Recycle_DiscardPileCheck", "Recycle_PlayerSelection",
            "Recycle_AddToHandEffect",
            "FullHeal_StatusCheck", "FullHeal_ClearStatusEffect",
            "PokeBall_DeckCheck", "PokeBall_PlayerSelection",
            "PokeBall_AddToHandEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn('actor.duelOps:returnCardToDeck(deckIndex)', src)
        self.assertIn('actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_STATUS, s.c.NO_STATUS)', src)
        self.assertIn('st.pokeBallHeads', src)

    def test_attached_trainers_and_play_area_return_heal_effects(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "PlusPowerEffect", "Defender_PlayerSelection", "Defender_AttachDefenderEffect",
            "MrFuji_BenchCheck", "MrFuji_PlayerSelection", "MrFuji_ReturnToDeckEffect",
            "PokemonCenter_DamageCheck", "PokemonCenter_HealDiscardEnergyEffect",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn('DUELVARS_ARENA_CARD_ATTACHED_PLUSPOWER', src)
        self.assertIn('DUELVARS_ARENA_CARD_ATTACHED_DEFENDER', src)
        self.assertIn('shiftAllPokemonToFirstPlayAreaSlots', src)
        self.assertIn('createArenaOrBenchEnergyCardList(slot)', src)

    def test_revive_and_pokemon_flute_restore_basic_pokemon_from_discard(self):
        src = read("src/tcg/duel/EffectCommands.lua")
        for label in (
            "Revive_BenchCheck", "Revive_PlayerSelection", "Revive_PlaceInPlayAreaEffect",
            "PokemonFlute_BenchCheck", "PokemonFlute_PlayerSelection",
            "PokemonFlute_PlaceInPlayAreaText",
        ):
            self.assertIn(f'self:register("{label}"', src)
        self.assertIn('local function basicPokemonInDiscard', src)
        self.assertIn('row.stage == s.c.BASIC', src)
        self.assertIn('"opponentDiscardBasicPokemon"', src)
        self.assertIn('local half = math.floor(actor.duelVars:get(hpOffset) / 2)', src)


if __name__ == "__main__":
    unittest.main()
