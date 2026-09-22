-- Source-backed AI dispatch primitives translated from pret/poketcg
-- src/home/ai.asm and engine/duel/ai/{init,core,decks/*}.asm.
--
-- Common general-deck turn, attack, energy, retreat, switch and selected
-- Trainer policies are translated directly. Specialized deck tables, some
-- Trainer decisions, deck priority-list data and remaining active-power strategy
-- stay explicit fail-closed boundaries rather than being approximated.

local bit = require("bit")

local AI = {}
AI.__index = AI

function AI.new(memory, duelVars, rng, cardData, duelOps, constants, decks, adapters)
  assert(type(decks) == "table" and type(decks.aiByOpponentDeckId) == "table",
    "generated DeckAIPointerTable mapping is required")
  assert(type(decks.aiListsByOpponentDeckId) == "table",
    "generated deck AI list mapping is required")
  return setmetatable({
    memory = assert(memory),
    duelVars = assert(duelVars),
    rng = assert(rng),
    cardData = assert(cardData),
    duelOps = assert(duelOps),
    c = assert(constants),
    decks = decks,
    adapters = adapters or {},
    combat = nil,
    playerActions = nil,
  }, AI)
end

function AI:setCombat(combat)
  self.combat = assert(combat)
end

function AI:setPlayerActions(playerActions)
  self.playerActions = assert(playerActions)
end

function AI:_event(name, payload)
  local fn = self.adapters.event
  if fn then fn(name, payload or {}) end
end

local function satAdd(score, amount)
  return math.min(0xff, score + amount)
end

local function satSub(score, amount)
  return math.max(0, score - amount)
end

local function hasFlag(byte, bitIndex)
  if byte == nil or bitIndex == nil then return false end
  return bit.band(byte, bit.lshift(1, bitIndex)) ~= 0
end

function AI:_attackFlag(attack, flagByte, bitIndex)
  return attack and attack.flags and hasFlag(attack.flags[flagByte], bitIndex)
end

function AI:_readWord(symbol)
  local address, bank = self.memory:address(symbol)
  return self.memory:read8("wram", address, bank)
    + 0x100 * self.memory:read8("wram", address + 1, bank)
end

function AI:_writeWord(symbol, value)
  local address, bank = self.memory:address(symbol)
  self.memory:write8("wram", address, value % 0x100, bank)
  self.memory:write8("wram", address + 1, math.floor(value / 0x100) % 0x100, bank)
end

function AI:_required(name)
  local fn = self.adapters[name]
  assert(type(fn) == "function", "TCG AI requires untranslated adapter: " .. name)
  return fn
end

function AI:_actionTable()
  local opponentDeckId = self.memory:readSymbol8("wOpponentDeckID")
  local label = self.decks.aiByOpponentDeckId[opponentDeckId]
  assert(type(label) == "string" and label ~= "",
    "DeckAIPointerTable has no entry for wOpponentDeckID=" .. tostring(opponentDeckId))
  return label
end

function AI:_deckAILists()
  local opponentDeckId = self.memory:readSymbol8("wOpponentDeckID")
  return self.decks.aiListsByOpponentDeckId[opponentDeckId] or {}
end

function AI:_deckAIList(name)
  local list = self:_deckAILists()[name]
  if list == nil then return nil end
  assert(type(list) == "table" and type(list.entries) == "table",
    "malformed generated deck AI list: " .. tostring(name))
  return list
end

-- InitAIDuelVars::
function AI:initDuelVars()
  local start, startBank = self.memory:address("wAIDuelVars")
  local finish, finishBank = self.memory:address("wAIDuelVarsEnd")
  assert(startBank == finishBank and finish >= start, "invalid wAIDuelVars range")
  self.memory:zero("wram", start, finish - start, startBank)
  self.memory:writeSymbol8("wAIPokedexCounter", 5)
  self.memory:writeSymbol8("wAIPeekedPrizes", 0xff)
end

-- AIPlayInitialBasicCards:: The source takes a snapshot list of the hand and
-- then plays every actual Basic Pokemon in that list, in list order.
function AI:playInitialBasicCards()
  self.duelOps:createHandCardList()
  local list, bank = self.memory:address("wDuelTempList")
  assert(bank == 0, "wDuelTempList unexpectedly moved out of WRAM0")
  local pos = 0
  while true do
    local deckIndex = self.memory:read8("wram", list + pos, bank)
    if deckIndex == 0xff then return end
    self.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
    self.cardData:loadBuffer1FromDeckIndex(deckIndex)
    local loaded, loadedBank = self.memory:address("wLoadedCard1")
    local cardType = self.memory:read8("wram", loaded + self.c.CARD_DATA_TYPE, loadedBank)
    local stage = self.memory:read8("wram", loaded + self.c.CARD_DATA_STAGE, loadedBank)
    if cardType < self.c.TYPE_ENERGY and stage == self.c.BASIC then
      -- Source ignores carry: a seventh Basic simply cannot be placed once the
      -- six-slot Play Area is full.
      self.duelOps:putHandPokemonCardInPlayArea(deckIndex)
    end
    pos = pos + 1
  end
end

-- SetSamsStartingPlayArea::
function AI:setSamsStartingPlayArea()
  self.duelOps:createHandCardList()
  local list, bank = self.memory:address("wDuelTempList")
  local pos = 0
  while true do
    local deckIndex = self.memory:read8("wram", list + pos, bank)
    self.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
    if deckIndex == 0xff then return end
    local cardId = self.cardData:loadBuffer1FromDeckIndex(deckIndex)
    if cardId == self.c.MACHOP then
      local _, carry = self.duelOps:putHandPokemonCardInPlayArea(deckIndex)
      assert(not carry, "SetSamsStartingPlayArea could not place Machop")
      self.memory:writeSymbol8("wDuelInitialPrizes", 2)
      return
    end
    pos = pos + 1
  end
end

-- All sixteen non-general, non-SamPractice AIActionTable_* labels (verified
-- against every engine/duel/ai/decks/*.asm boss file) share the EXACT same
-- .start_duel/.forced_switch/.ko_switch/.take_prize sequence: only their
-- data lists (already generated per opponent deck ID) and, for 5 of the 16,
-- .do_turn differ.
local AI_BOSS_ACTION_TABLES = {
  AIActionTable_LegendaryMoltres = true, AIActionTable_LegendaryZapdos = true,
  AIActionTable_LegendaryArticuno = true, AIActionTable_LegendaryDragonite = true,
  AIActionTable_FirstStrike = true, AIActionTable_RockCrusher = true,
  AIActionTable_GoGoRainDance = true, AIActionTable_ZappingSelfdestruct = true,
  AIActionTable_FlowerPower = true, AIActionTable_StrangePsyshock = true,
  AIActionTable_WondersOfScience = true, AIActionTable_FireCharge = true,
  AIActionTable_ImRonald = true, AIActionTable_PowerfulRonald = true,
  AIActionTable_InvincibleRonald = true, AIActionTable_LegendaryRonald = true,
}

-- Of the sixteen, these eleven route .do_turn straight to AIMainTurnLogic
-- (== mainTurnLogic(false) below); the remaining five (the Legendary bosses
-- and Legendary Ronald) each have their own bespoke AIDoTurn_<Deck> routine,
-- now all natively translated (doTurnLegendary{Zapdos,Moltres,Dragonite,
-- Articuno,Ronald}) rather than behind the turnSpecial adapter boundary.
local AI_BOSS_GENERAL_TURN_TABLES = {
  AIActionTable_FirstStrike = true, AIActionTable_RockCrusher = true,
  AIActionTable_GoGoRainDance = true, AIActionTable_ZappingSelfdestruct = true,
  AIActionTable_FlowerPower = true, AIActionTable_StrangePsyshock = true,
  AIActionTable_WondersOfScience = true, AIActionTable_FireCharge = true,
  AIActionTable_ImRonald = true, AIActionTable_PowerfulRonald = true,
  AIActionTable_InvincibleRonald = true,
}

-- CountEnergyAndBasicPokemonInDeckRange (inlined section of
-- SetUpBossStartingHandAndDeck): tallies Energy and Basic-stage Pokemon
-- cards across `count` consecutive DUELVARS_DECK_CARDS slots starting at
-- `startOffset`.
function AI:_countEnergyAndBasicInDeckRange(startOffset, count)
  local energy, basic = 0, 0
  for i = startOffset, startOffset + count - 1 do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_DECK_CARDS + i)
    local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
    local row = assert(self.cardData:get(cardId))
    if row.type >= self.c.TYPE_ENERGY and row.type < self.c.TYPE_TRAINER then
      energy = energy + 1
    elseif row.type < self.c.TYPE_ENERGY and row.stage == self.c.BASIC then
      basic = basic + 1
    end
  end
  return energy, basic
end

-- SetUpBossStartingHandAndDeck:: returns the whole starting hand to the deck
-- and reshuffles until the deal has at least 2 Basic Pokemon and 2 Energy
-- among what would become the new 7-card hand, AND at least 4 of each
-- counting the following 6 cards too (what would become the face-down
-- prizes). The source's own prize-avoidance check (.CheckIfIDIsInList) has a
-- real bug -- `cp a` where `or a` was clearly intended -- that makes it
-- unconditionally report "not found" no matter what wAICardListAvoidPrize
-- contains, so that check never actually forces a reshuffle on real
-- hardware; that dead branch is not reproduced as a functioning filter.
function AI:setUpBossStartingHandAndDeck()
  local size = self.c.STARTING_HAND_SIZE
  for _ = 1, size do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_HAND)
    self.duelOps:removeCardFromHand(deckIndex)
    self.duelOps:returnCardToDeck(deckIndex)
  end

  while true do
    local energy1, basic1 = self:_countEnergyAndBasicInDeckRange(0, size)
    if basic1 >= 2 and energy1 >= 2 then
      local energy2, basic2 = self:_countEnergyAndBasicInDeckRange(size, 6)
      if basic1 + basic2 >= 4 and energy1 + energy2 >= 4 then break end
    end
    self.duelOps:shuffleDeck()
  end

  -- The 7 target cards are captured up front rather than re-read after each
  -- draw: SearchCardInDeckAndAddToHand always removes exactly the current
  -- gone-boundary card here (each of these 7 deck indices is, in turn,
  -- always the lowest-index undrawn slot at the moment it's searched for),
  -- so it never needs to shift anything below the next target -- capturing
  -- the list first is behaviorally identical to the source's live re-reads.
  local targets = {}
  for i = 0, size - 1 do
    targets[#targets + 1] = self.duelVars:get(self.c.DUELVARS_DECK_CARDS + i)
  end
  for _, deckIndex in ipairs(targets) do
    self.duelOps:searchCardInDeckAndAddToHand(deckIndex)
    self.duelOps:addCardToHand(deckIndex)
  end
end

-- TrySetUpBossStartingPlayArea:: returns false if wAICardListArenaPriority
-- is unset or none of its card IDs are in hand (no Active could be placed);
-- otherwise places the first hand match from the Arena priority list as
-- Active, then repeatedly places the first remaining hand match from the
-- Bench priority list until either that list is exhausted or the Play Area
-- reaches 3 Pokemon.
function AI:trySetUpBossStartingPlayArea()
  local arenaPriority = self:_deckAIList("arenaPriority")
  local arenaIds = arenaPriority and arenaPriority.cardIds
  if type(arenaIds) ~= "table" or #arenaIds == 0 then return false end

  local hand = self.duelOps:createHandCardList()
  local function playFirstMatch(cardIds)
    for _, wantedId in ipairs(cardIds) do
      for i, deckIndex in ipairs(hand) do
        if self.cardData:getCardIDFromDeckIndex(deckIndex) == wantedId then
          table.remove(hand, i) -- keep `hand` a valid ipairs sequence
          self.duelOps:putHandPokemonCardInPlayArea(deckIndex)
          return true
        end
      end
    end
    return false
  end

  if not playFirstMatch(arenaIds) then return false end

  local benchPriority = self:_deckAIList("benchPriority")
  local benchIds = benchPriority and benchPriority.cardIds
  if type(benchIds) == "table" and #benchIds > 0 then
    local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    while count < 3 and playFirstMatch(benchIds) do
      count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    end
  end
  return true
end

-- AIActionTable_<Boss>'s shared .start_duel sequence.
function AI:bossStartDuel()
  self:initDuelVars()
  self:setUpBossStartingHandAndDeck()
  if not self:trySetUpBossStartingPlayArea() then return end
  self:playInitialBasicCards()
end

-- AIDoAction_StartDuel dispatch for fully translated action tables.
function AI:startDuel()
  local label = self:_actionTable()
  if label == "AIActionTable_GeneralDecks" or label == "AIActionTable_GeneralNoRetreat" then
    self:initDuelVars()
    self:playInitialBasicCards()
    return
  end
  if label == "AIActionTable_SamPractice" then
    self:setSamsStartingPlayArea()
    return
  end
  if AI_BOSS_ACTION_TABLES[label] then
    return self:bossStartDuel()
  end
  -- Any other/future special decks modify starting hand/deck/play area
  -- through their own tables. Do not route them through generic startup.
  return self:_required("startDuelSpecial")(label, self.memory:readSymbol8("wOpponentDeckID"))
end

-- PickRandomBenchPokemon::
function AI:pickRandomBenchPokemon()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  assert(count >= 2, "PickRandomBenchPokemon called without a bench")
  return self.rng:random(count - 1) + 1
end

function AI:_findCardIDInPlayArea(cardId, firstSlot)
  firstSlot = firstSlot or self.c.PLAY_AREA_ARENA
  for slot = firstSlot, self.c.MAX_PLAY_AREA_POKEMON - 1 do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
    if deckIndex == 0xff then return 0xff end
    if self.cardData:getCardIDFromDeckIndex(deckIndex) == cardId then return slot end
  end
  return 0xff
end

-- GetPlayAreaLocationOfRaticateOrRattata::
function AI:getPlayAreaLocationOfRaticateOrRattata()
  local slot = self:_findCardIDInPlayArea(self.c.RATICATE, self.c.PLAY_AREA_BENCH_1)
  if slot == 0xff then
    slot = self:_findCardIDInPlayArea(self.c.RATTATA, self.c.PLAY_AREA_BENCH_1)
  end
  if slot == 0xff then slot = self.c.PLAY_AREA_BENCH_1 end
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
  return slot
end

function AI:isSamPracticeScriptedTurn()
  -- IsAIPracticeScriptedTurn returns carry once AI has taken >= 7 turns.
  return math.floor(self.memory:readSymbol8("wDuelTurns") / 2) < 7
end

-- AIDoAction_ForcedSwitch:: follows the selected deck action table. General
-- decks use the common Bench scorer, while Sam's scripted practice turns use
-- PickRandomBenchPokemon exactly as the source does. All sixteen boss/
-- special deck tables' own .forced_switch handlers were checked directly
-- (engine/duel/ai/decks/*.asm) and every one calls the exact same
-- AIDecideBenchPokemonToSwitchTo with no per-deck override; only a label
-- outside that verified set still falls back to the adapter boundary. The
-- caller is responsible for swapping to the defending AI's duel-variable
-- page before invoking this routine.
function AI:forcedSwitch()
  local label = self:_actionTable()
  local slot, reason
  if label == "AIActionTable_SamPractice" and self:isSamPracticeScriptedTurn() then
    slot = self:pickRandomBenchPokemon()
  elseif label == "AIActionTable_GeneralDecks" or label == "AIActionTable_GeneralNoRetreat"
      or label == "AIActionTable_SamPractice" or AI_BOSS_ACTION_TABLES[label] then
    slot, reason = self:decideBenchPokemonToSwitchTo()
    if not slot then return nil, reason end
  else
    local decide = self.adapters.forcedSwitchSpecial
      or self.adapters.decideBenchPokemonToSwitchTo
    if type(decide) ~= "function" then
      return nil, "untranslated_ai_forced_switch_table:" .. label
    end
    slot = decide(label, "forced_switch")
  end
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if type(slot) ~= "number" or slot < self.c.PLAY_AREA_BENCH_1 or slot >= count
      or self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot) == 0xff
      or self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot) == 0 then
    return nil, "invalid_ai_forced_switch_selection"
  end
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
  return slot
end

-- AIDoAction_KOSwitch:: Sam keeps its scripted choice during the tutorial;
-- general tables and all sixteen verified boss/special tables (see
-- forcedSwitch's comment) use the native common bench scorer. Only a label
-- outside that verified set retains the deck-specific adapter boundary.
function AI:koSwitch()
  local label = self:_actionTable()
  if label == "AIActionTable_SamPractice" and self:isSamPracticeScriptedTurn() then
    return self:getPlayAreaLocationOfRaticateOrRattata()
  end
  if label == "AIActionTable_GeneralDecks" or label == "AIActionTable_GeneralNoRetreat"
      or label == "AIActionTable_SamPractice" or AI_BOSS_ACTION_TABLES[label] then
    local slot, reason = self:decideBenchPokemonToSwitchTo()
    assert(slot, "AIDecideBenchPokemonToSwitchTo failed: " .. tostring(reason))
    self.memory:writeSymbol8("hTemp_ffa0", slot)
    return slot
  end
  local slot = self:_required("decideBenchPokemonToSwitchTo")(label)
  assert(type(slot) == "number" and slot >= self.c.PLAY_AREA_BENCH_1
      and slot < self.c.MAX_PLAY_AREA_POKEMON,
    "AIDecideBenchPokemonToSwitchTo adapter returned invalid play-area slot")
  self.memory:writeSymbol8("hTemp_ffa0", slot)
  return slot
end

-- AIPickPrizeCards:: All referenced deck action tables dispatch TAKE_PRIZE to
-- this common routine. Note the source intentionally uses Random(6), despite an
-- eight-byte local mask table.
function AI:pickPrizeCards()
  local remainingToTake = self.memory:readSymbol8("wNumberPrizeCardsToTake")
  while remainingToTake ~= 0 do
    local prizes = self.duelVars:get(self.c.DUELVARS_PRIZES)
    if prizes == 0 then break end

    local prizeIndex
    while true do
      prizeIndex = self.rng:random(6)
      local mask = 2 ^ prizeIndex
      if prizes % (mask * 2) >= mask then break end
    end

    local mask = 2 ^ prizeIndex
    prizes = prizes - mask
    self.duelVars:set(self.c.DUELVARS_PRIZES, prizes)
    local deckIndex = self.duelVars:get(self.c.DUELVARS_PRIZE_CARDS + prizeIndex)
    self.duelOps:addCardToHand(deckIndex)
    remainingToTake = remainingToTake - 1
  end
end

function AI:takePrize()
  return self:pickPrizeCards()
end

function AI:_findCardIDInHand(cardId)
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  for i = 0, count - 1 do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_HAND + i)
    if self.cardData:getCardIDFromDeckIndex(deckIndex) == cardId then return deckIndex end
  end
  return nil
end

function AI:_playBasicFromHand(cardId)
  local deckIndex = assert(self:_findCardIDInHand(cardId),
    "Sam scripted AI could not find required Basic in hand")
  self.memory:writeSymbol8("hTemp_ffa0", deckIndex)
  self.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
  local slot, carry = self.duelOps:putHandPokemonCardInPlayArea(deckIndex)
  assert(not carry, "Sam scripted AI had no Play Area slot")
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
  self.duelVars:set(self.c.DUELVARS_ARENA_CARD_STAGE + slot, self.c.BASIC)
  return slot
end

-- AIAttachEnergyInHandToCardInPlayArea / ...InBench.
function AI:_attachEnergyToCard(energyCardId, pokemonCardId, firstSlot)
  local energyIndex = self:_findCardIDInHand(energyCardId)
  if energyIndex == nil then return false end
  local slot = self:_findCardIDInPlayArea(pokemonCardId, firstSlot or self.c.PLAY_AREA_ARENA)
  if slot == 0xff then return false end
  self.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", slot)
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
  self.memory:writeSymbol8("hTemp_ffa0", energyIndex)
  self.memory:writeSymbol8("hTempCardIndex_ff98", energyIndex)
  self.duelOps:putHandCardInPlayArea(energyIndex, slot)
  self.memory:writeSymbol8("wAlreadyPlayedEnergy", self.c.TRUE)
  return true
end

function AI:_evolveCardInPlayArea(evolutionCardId, baseCardId)
  local evolutionIndex = assert(self:_findCardIDInHand(evolutionCardId),
    "Sam scripted AI could not find required evolution in hand")
  local slot = self:_findCardIDInPlayArea(baseCardId, self.c.PLAY_AREA_ARENA)
  assert(slot ~= 0xff, "Sam scripted AI could not find evolution target")
  self.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", slot)
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
  self.memory:writeSymbol8("hTemp_ffa0", evolutionIndex)
  self.memory:writeSymbol8("hTempCardIndex_ff98", evolutionIndex)
  local ok, reason = self.duelOps:evolvePokemonCardIfPossible(evolutionIndex, slot)
  assert(ok, "Sam scripted evolution failed: " .. tostring(reason))
  return slot
end

function AI:_attachedEnergyDeckIndices(slot)
  local wanted = bit.bor(self.c.CARD_LOCATION_PLAY_AREA, slot)
  local out = {}
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    if self.duelVars:get(deckIndex) == wanted then
      local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
      local row = assert(self.cardData:get(cardId))
      if row.type >= self.c.TYPE_ENERGY and row.type < self.c.TYPE_TRAINER then
        out[#out + 1] = deckIndex
      end
    end
  end
  return out
end

-- AITryToRetreat:: exact Sam-turn-5 specialization. Raticate's retreat cost is
-- one and its attached basic Fighting/Lightning Energies are all "not useful"
-- to a Colorless Pokemon under CheckIfEnergyIsUseful, so the source shuffles
-- the attached-energy list and discards its first entry.
function AI:_retreatSamPractice(targetSlot)
  local arenaIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local arenaId = self.cardData:getCardIDFromDeckIndex(arenaIndex)
  assert(arenaId == self.c.RATICATE, "Sam scripted retreat expected Raticate")
  local arena = assert(self.cardData:get(arenaId))
  assert(arena.retreatCost == 1, "Sam Raticate retreat cost changed in source data")

  -- AITryToRetreat writes these selection/status scratch values before choosing
  -- retreat-cost cards. Preserve them because DuelDataToSave can observe HRAM.
  self.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", targetSlot)
  self.memory:writeSymbol8("hTemp_ffa0", self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS))
  local retreatList, retreatBank = self.memory:address("hTempRetreatCostCards")
  self.memory:write8("hram", retreatList, 0xff, retreatBank)
  self.memory:writeSymbol8("wTempCardRetreatCost", arena.retreatCost)
  self.memory:writeSymbol8("wTempCardID", arenaId)
  self.memory:writeSymbol8("wTempCardType", bit.bor(arena.type, self.c.TYPE_ENERGY))

  local energies = self:_attachedEnergyDeckIndices(self.c.PLAY_AREA_ARENA)
  assert(#energies >= 1, "Sam scripted retreat has no attached Energy")
  local list, bank = self.memory:address("wDuelTempList")
  for i, value in ipairs(energies) do self.memory:write8("wram", list + i - 1, value, bank) end
  self.memory:write8("wram", list + #energies, 0xff, bank)

  -- For Raticate, CheckIfEnergyIsUseful rejects each attached basic Energy as
  -- not matching TYPE_ENERGY_COLORLESS. Source therefore shuffles the list and
  -- takes its first entry for the one-Energy retreat cost.
  self.rng:shuffleCards(list, #energies)
  local discard = self.memory:read8("wram", list, bank)
  self.memory:write8("hram", retreatList, discard, retreatBank)
  self.memory:write8("hram", retreatList + 1, 0xff, retreatBank)
  self.duelOps:removeCardFromDuelTempList(discard)

  -- AttemptRetreat -> DiscardRetreatCostCards -> SwapArenaWithBenchPokemon.
  self.duelOps:putCardInDiscardPile(discard)
  self.duelOps:swapArenaWithBenchPokemon(targetSlot)
  self.memory:writeSymbol8("wConfusionRetreatCheckWasUnsuccessful", 0)
  return true
end

-- AIPerformScriptedTurn::. Preserve the source's turn-5 bug: it compares the
-- arena deck index against the MACHOP card ID, so normal practice takes BENCH_1.
function AI:performSamScriptedTurn()
  assert(self.combat, "Sam scripted turn requires combat runtime")
  local turn = math.floor(self.memory:readSymbol8("wDuelTurns") / 2)
  assert(turn >= 0 and turn < 7, "AIPerformScriptedTurn called outside scripted range")

  if turn == 0 then
    self:_attachEnergyToCard(self.c.FIGHTING_ENERGY, self.c.MACHOP, self.c.PLAY_AREA_ARENA)
  elseif turn == 1 then
    self:_playBasicFromHand(self.c.RATTATA)
    self:_attachEnergyToCard(self.c.FIGHTING_ENERGY, self.c.RATTATA, self.c.PLAY_AREA_ARENA)
  elseif turn == 2 then
    self:_evolveCardInPlayArea(self.c.RATICATE, self.c.RATTATA)
    self:_attachEnergyToCard(self.c.LIGHTNING_ENERGY, self.c.RATICATE, self.c.PLAY_AREA_ARENA)
  elseif turn == 3 then
    self:_attachEnergyToCard(self.c.LIGHTNING_ENERGY, self.c.RATICATE, self.c.PLAY_AREA_ARENA)
  elseif turn == 4 then
    self:_playBasicFromHand(self.c.MACHOP)
    self:_attachEnergyToCard(self.c.FIGHTING_ENERGY, self.c.MACHOP, self.c.PLAY_AREA_BENCH_1)
    local arenaDeckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
    local target = self.c.PLAY_AREA_BENCH_1
    if arenaDeckIndex == self.c.MACHOP then target = target + 1 end -- source bug
    self:_retreatSamPractice(target)
  elseif turn == 5 or turn == 6 then
    self:_attachEnergyToCard(self.c.FIGHTING_ENERGY, self.c.MACHOP, self.c.PLAY_AREA_ARENA)
  end

  local active = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", self.c.PLAY_AREA_ARENA)
  self.memory:writeSymbol8("wSelectedAttack", self.c.FIRST_ATTACK_OR_PKMN_POWER)
  local usable = self.combat:checkAttackUsable(active, self.c.FIRST_ATTACK_OR_PKMN_POWER)
  if not usable then
    -- OppAction_FinishTurnWithoutAttacking::.
    self.combat.core:clearNonTurnTemporaryDuelvars()
    self.memory:writeSymbol8("wOpponentTurnEnded", 1)
    return true, "finish_no_attack"
  end
  local ok, result = self.combat:useAttack(active, self.c.FIRST_ATTACK_OR_PKMN_POWER,
    { verifyPractice = false })
  if ok then self.memory:writeSymbol8("wOpponentTurnEnded", 1) end
  return ok, result
end

-- InitAITurnVars:: common state, including the Mewtwo-mill deck
-- identification (if Player uses Barrier three turns in a row and its
-- Arena Pokemon is MewtwoLv53, check whether the Player's whole deck is
-- MewtwoLv53-only).
function AI:initTurnVars()
  self.memory:writeSymbol8("wAIPokedexCounter",
    (self.memory:readSymbol8("wAIPokedexCounter") + 1) % 0x100)
  for _, name in ipairs({"wPreviousAIFlags", "wAITriedAttack", "wUnused_cddc",
    "wAIRetreatedThisTurn"}) do
    self.memory:writeSymbol8(name, 0)
  end

  local counter = self.memory:readSymbol8("wAIBarrierFlagCounter")
  local attackIndex = self.memory:readSymbol8("wPlayerAttackingAttackIndex")
  local cardIndex = self.memory:readSymbol8("wPlayerAttackingCardIndex")
  local usedBarrier = false
  if attackIndex ~= 0xff and attackIndex ~= 0 and cardIndex ~= 0xff then
    self.duelVars:swapTurn()
    local cardId = self.cardData:getCardIDFromDeckIndex(cardIndex)
    self.duelVars:swapTurn()
    usedBarrier = cardId == self.c.MEWTWO_LV53
  end
  if usedBarrier then
    if self.c.AI_MEWTWO_MILL_F and hasFlag(counter, self.c.AI_MEWTWO_MILL_F) then
      self.memory:writeSymbol8("wAIBarrierFlagCounter", self.c.AI_MEWTWO_MILL)
    else
      counter = counter + 1
      self.memory:writeSymbol8("wAIBarrierFlagCounter", counter)
      if counter >= 3 then
        local arenaIndex = self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD)
        self.duelVars:swapTurn()
        local arenaCardId = self.cardData:getCardIDFromDeckIndex(arenaIndex)
        self.duelVars:swapTurn()
        if arenaCardId == self.c.MEWTWO_LV53
            and not self:_checkIfPlayerHasPokemonOtherThanMewtwoLv53() then
          self.memory:writeSymbol8("wAIBarrierFlagCounter", self.c.AI_MEWTWO_MILL)
        else
          self.memory:writeSymbol8("wAIBarrierFlagCounter", 0)
        end
      end
    end
  elseif self.c.AI_MEWTWO_MILL_F and hasFlag(counter, self.c.AI_MEWTWO_MILL_F) then
    self.memory:writeSymbol8("wAIBarrierFlagCounter", (counter + 1) % 0x100)
  else
    self.memory:writeSymbol8("wAIBarrierFlagCounter", 0)
  end
end

-- CheckIfPlayerHasPokemonOtherThanMewtwoLv53:: scans the Player's full
-- DECK_SIZE-card deck by physical deck index (not by current card location,
-- and regardless of what has been drawn) for any non-Energy card other than
-- MewtwoLv53.
function AI:_checkIfPlayerHasPokemonOtherThanMewtwoLv53()
  self.duelVars:swapTurn()
  local found = false
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
    local row = self.cardData:get(cardId)
    if row and row.type < self.c.TYPE_ENERGY and cardId ~= self.c.MEWTWO_LV53 then
      found = true
      break
    end
  end
  self.duelVars:swapTurn()
  return found
end

-- HandleAIAntiMewtwoDeckStrategy:: returns true for the source's "return
-- carry" (continue the turn normally: either the Player isn't running a
-- confirmed mill deck, the mill counter-strategy went stale and was reset,
-- or the Bench isn't set up enough yet); returns false, reason for "return
-- no carry" (the Bench is ready, AI_TRAINER_CARD_PHASE_05 was processed, and
-- the caller should skip straight to its to_bench Energy Trans + attack
-- tail); returns nil, err on an untranslated failure from that phase.
function AI:handleAIAntiMewtwoDeckStrategy()
  local counter = self.memory:readSymbol8("wAIBarrierFlagCounter")
  if not (self.c.AI_MEWTWO_MILL_F and hasFlag(counter, self.c.AI_MEWTWO_MILL_F)) then
    return true
  end
  if counter >= self.c.AI_MEWTWO_MILL + 2 then
    self.memory:writeSymbol8("wAIBarrierFlagCounter", 0)
    return true
  end
  if self:_countNumberOfSetUpBenchPokemon() < 4 then
    return true
  end
  local ok, err = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_05)
  if ok == nil then return nil, err end
  return false, "anti_mewtwo_mill_bench_ready"
end

function AI:_energyCardIdForColor(color)
  local ids = {
    [self.c.FIRE] = self.c.FIRE_ENERGY,
    [self.c.GRASS] = self.c.GRASS_ENERGY,
    [self.c.LIGHTNING] = self.c.LIGHTNING_ENERGY,
    [self.c.WATER] = self.c.WATER_ENERGY,
    [self.c.FIGHTING] = self.c.FIGHTING_ENERGY,
    [self.c.PSYCHIC] = self.c.PSYCHIC_ENERGY,
  }
  return ids[color]
end

-- CheckEnergyNeededForAttack:: useful result for the translated common AI.
function AI:checkEnergyNeededForAttack(slot, attackIndex)
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
  if deckIndex == 0xff then return nil, "empty_slot" end
  local _, attack = self.combat:loadAttack(deckIndex, attackIndex)
  if attack.nameTextId == 0 or attack.category == self.c.POKEMON_POWER then
    return nil, "no_attack"
  end
  self.duelOps:getPlayAreaCardAttachedEnergies(slot)
  if slot == self.c.PLAY_AREA_ARENA then self.combat.status:handleEnergyBurn() end
  local base, bank = self.memory:address("wAttachedEnergies")
  local requiredColored, coloredNeeded, neededColor = 0, 0, nil
  for color = 0, self.c.NUM_COLORED_TYPES - 1 do
    local required = attack.energy[color] or 0
    local attached = self.memory:read8("wram", base + color, bank)
    requiredColored = requiredColored + required
    if required > attached then
      coloredNeeded = required - attached
      neededColor = color
    end
  end
  local total = self.memory:readSymbol8("wTotalAttachedEnergies")
  local coloredSatisfied = requiredColored - coloredNeeded
  local colorlessRequired = attack.energy[self.c.COLORLESS] or 0
  local colorlessNeeded = math.max(0, colorlessRequired - math.max(0, total - coloredSatisfied))
  return {
    colored = coloredNeeded, colorless = colorlessNeeded, color = neededColor,
    energyCardId = neededColor and self:_energyCardIdForColor(neededColor) or nil,
    enough = coloredNeeded == 0 and colorlessNeeded == 0, attack = attack,
  }
end

function AI:_validateAIPhase()
  local ok, reason = self.combat.effects:validatePhases({self.c.EFFECTCMDTYPE_AI})
  return ok, reason
end

-- EstimateDamage_VersusDefendingCard:: active-card common path. Unknown AI
-- effect functions fail closed instead of substituting expected damage.
function AI:estimateDamageVersusDefendingCard(attackIndex)
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local _, attack, cardId = self.combat:loadAttack(deckIndex, attackIndex)
  if attack.nameTextId == 0 or attack.category == self.c.POKEMON_POWER then
    return { damage = 0, min = 0, max = 0, attack = attack }
  end
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", self.c.PLAY_AREA_ARENA)
  self.memory:writeSymbol8("wAIMinDamage", attack.damage)
  self.memory:writeSymbol8("wAIMaxDamage", attack.damage)
  local valid, reason = self:_validateAIPhase()
  if not valid then return nil, reason end
  local carry, err = self.combat.effects:tryExecute(self.c.EFFECTCMDTYPE_AI,
    { combat = self.combat, ai = self })
  if carry == nil then return nil, err end
  local base = self:_readWord("wDamage")
  local minBase = self.memory:readSymbol8("wAIMinDamage")
  local maxBase = self.memory:readSymbol8("wAIMaxDamage")
  if minBase == 0 and maxBase == 0 then minBase, maxBase = base, base end

  local function calc(v)
    return self:_calculateForwardDamageFromSlot(
      self.c.PLAY_AREA_ARENA, attack, cardId, v)
  end
  local damage, minDamage, maxDamage = calc(base), calc(minBase), calc(maxBase)

  -- CalculateDamage_VersusDefendingPokemon adds the *defender's* poison
  -- expectation.  From the AI turn-holder perspective that is the non-turn
  -- Arena status: one between-turn tick, +10 regular / +20 double poison.
  local status = self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_STATUS)
  local poison = 0
  if self.c.DOUBLE_POISONED_F and hasFlag(status, self.c.DOUBLE_POISONED_F) then
    poison = 20
  elseif self.c.POISONED_F and hasFlag(status, self.c.POISONED_F) then
    poison = 10
  end
  damage, minDamage, maxDamage = math.min(255, damage + poison),
    math.min(255, minDamage + poison), math.min(255, maxDamage + poison)
  self:_writeWord("wDamage", damage)
  self.memory:writeSymbol8("wAIMinDamage", minDamage)
  self.memory:writeSymbol8("wAIMaxDamage", maxDamage)
  return { damage = damage, min = minDamage, max = maxDamage, attack = attack }
end

local function clampSourceDamage(value)
  value = bit.band(value, 0xffff)
  if bit.band(bit.rshift(value, 8), 0x80) ~= 0 then return 0 end
  if value > 0xff then return 0xff end
  return value
end

function AI:_sourceUnaffectedDamage(value)
  local damage = bit.band(value, 0xffff)
  local high = bit.band(bit.rshift(damage, 8), 0xff)
  local mask = bit.lshift(1, self.c.UNAFFECTED_BY_WEAKNESS_RESISTANCE_F)
  local unaffected = bit.band(high, mask) ~= 0
  if unaffected then
    high = bit.band(high, bit.bnot(mask))
    damage = bit.bor(bit.lshift(high, 8), bit.band(damage, 0xff))
  end
  return damage, unaffected
end

function AI:_withClearedArenaSwitchStatuses(fn)
  local offsets = {
    self.c.DUELVARS_ARENA_CARD_SUBSTATUS1,
    self.c.DUELVARS_ARENA_CARD_SUBSTATUS2,
    self.c.DUELVARS_ARENA_CARD_CHANGED_RESISTANCE,
  }
  local saved = {}
  for _, offset in ipairs(offsets) do
    saved[offset] = self.duelVars:get(offset)
    self.duelVars:set(offset, 0)
  end
  local results = { pcall(fn) }
  for _, offset in ipairs(offsets) do self.duelVars:set(offset, saved[offset]) end
  if not results[1] then error(results[2]) end
  table.remove(results, 1)
  return unpack(results)
end

function AI:_calculateForwardDamageFromSlot(slot, attack, attackerCardId, value)
  local prevented = self.combat:_applyNoDamageOrEffectPrevention(attackerCardId, attack)
  if prevented then return 0 end

  local damage = bit.band(value, 0xffff)
  -- Bench candidates are being estimated as if switched Active, but source
  -- deliberately does not apply the old Arena card's double-damage substatus.
  if slot == self.c.PLAY_AREA_ARENA then
    damage = self.combat.status:handleDoubleDamageSubstatus(damage)
  end
  local unaffected
  damage, unaffected = self:_sourceUnaffectedDamage(damage)

  if not unaffected and damage ~= 0 then
    local color = self.combat.status:getPlayAreaCardColor(slot)
    local weakness, resistance = self.combat:_defenderWeaknessResistance()
    local mask = wrMask(color)
    if bit.band(weakness, mask) ~= 0 then damage = bit.band(damage * 2, 0xffff) end
    if bit.band(resistance, mask) ~= 0 then damage = bit.band(damage - 30, 0xffff) end
  end

  local plusLocation = bit.bor(self.c.CARD_LOCATION_PLAY_AREA, slot)
  damage = bit.band(damage + 10 * self.duelOps:countCardIDInLocation(
    self.c.PLUSPOWER, plusLocation), 0xffff)

  self.duelVars:swapTurn()
  damage = bit.band(damage - 20 * self.duelOps:countCardIDInLocation(
    self.c.DEFENDER, self.c.CARD_LOCATION_ARENA), 0xffff)
  local defenderDeck = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local defenderId = self.cardData:getCardIDFromDeckIndex(defenderDeck)
  damage = self.combat.status:handleDamageReduction(damage, attack.category, defenderId)
  self.duelVars:swapTurn()
  return clampSourceDamage(damage)
end

function AI:_reverseReceiverWeaknessResistance(slot, receiver)
  local weakness, resistance = receiver.weakness or 0, receiver.resistance or 0
  if slot == self.c.PLAY_AREA_ARENA then
    local changedWeak = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_CHANGED_WEAKNESS)
    local changedRes = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_CHANGED_RESISTANCE)
    if changedWeak ~= 0 then weakness = changedWeak end
    if changedRes ~= 0 then resistance = changedRes end
  end
  return weakness, resistance
end

function AI:_calculateReverseDamageToSlot(slot, attack, value)
  local receiverDeck = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
  if receiverDeck == 0xff then return 0 end
  local receiverId = self.cardData:getCardIDFromDeckIndex(receiverDeck)
  local receiver = assert(self.cardData:get(receiverId))

  -- The defending/player attack owns the double-damage substatus. Source is
  -- on the AI turn here, so temporarily swap to the player for this one call.
  self.duelVars:swapTurn()
  local damage = self.combat.status:handleDoubleDamageSubstatus(bit.band(value, 0xffff))
  local attackerColor = self.combat.status:getPlayAreaCardColor(self.c.PLAY_AREA_ARENA)
  self.duelVars:swapTurn()

  local cleaned, unaffected = self:_sourceUnaffectedDamage(damage)
  damage = cleaned
  if not unaffected and damage ~= 0 then
    local weakness, resistance = self:_reverseReceiverWeaknessResistance(slot, receiver)
    local mask = wrMask(attackerColor)
    if bit.band(weakness, mask) ~= 0 then damage = bit.band(damage * 2, 0xffff) end
    if bit.band(resistance, mask) ~= 0 then damage = bit.band(damage - 30, 0xffff) end
  end

  self.duelVars:swapTurn()
  damage = bit.band(damage + 10 * self.duelOps:countCardIDInLocation(
    self.c.PLUSPOWER, self.c.CARD_LOCATION_ARENA), 0xffff)
  self.duelVars:swapTurn()

  local receiverLocation = bit.bor(self.c.CARD_LOCATION_PLAY_AREA, slot)
  damage = bit.band(damage - 20 * self.duelOps:countCardIDInLocation(
    self.c.DEFENDER, receiverLocation), 0xffff)
  if slot == self.c.PLAY_AREA_ARENA then
    damage = self.combat.status:handleDamageReduction(damage, attack.category, receiverId)
  end
  damage = clampSourceDamage(damage)

  -- Reverse estimation counts two poison ticks, but only when the receiver is
  -- the Arena card; Bench candidates do not receive this poison expectation.
  if slot == self.c.PLAY_AREA_ARENA then
    local status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
    local poison = 0
    if self.c.DOUBLE_POISONED_F and hasFlag(status, self.c.DOUBLE_POISONED_F) then
      poison = 40
    elseif self.c.POISONED_F and hasFlag(status, self.c.POISONED_F) then
      poison = 20
    end
    damage = math.min(255, damage + poison)
  end
  return damage
end

-- EstimateDamage_FromDefendingPokemon:: slot-aware reverse estimator. The
-- player Active's AI damage command is run with hTempPlayAreaLocation forced to
-- Arena, then the chosen AI receiver slot is used for weakness/resistance,
-- attached Defender, active-only reduction, and poison exactly as the source.
function AI:estimateDamageFromDefendingPokemon(attackIndex, receiverSlot)
  receiverSlot = receiverSlot or self.c.PLAY_AREA_ARENA
  local savedLocation = self.memory:readSymbol8("hTempPlayAreaLocation_ff9d")

  self.duelVars:swapTurn()
  local playerDeckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local ok, reason = self.combat:checkAttackUsable(playerDeckIndex, attackIndex)
  if not ok then
    self.duelVars:swapTurn()
    self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", savedLocation)
    return { damage = 0, min = 0, max = 0, usable = false }
  end
  local _, attack = self.combat:loadAttack(playerDeckIndex, attackIndex)
  if attack.category == self.c.POKEMON_POWER then
    self.duelVars:swapTurn()
    self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", savedLocation)
    return { damage = 0, min = 0, max = 0, usable = false, attack = attack }
  end
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", self.c.PLAY_AREA_ARENA)
  self.memory:writeSymbol8("wAIMinDamage", attack.damage)
  self.memory:writeSymbol8("wAIMaxDamage", attack.damage)
  local valid, aiReason = self:_validateAIPhase()
  if not valid then
    self.duelVars:swapTurn()
    self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", savedLocation)
    return nil, aiReason
  end
  local carry, err = self.combat.effects:tryExecute(self.c.EFFECTCMDTYPE_AI,
    { combat = self.combat, ai = self })
  if carry == nil then
    self.duelVars:swapTurn()
    self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", savedLocation)
    return nil, err
  end
  local base = self:_readWord("wDamage")
  local minBase = self.memory:readSymbol8("wAIMinDamage")
  local maxBase = self.memory:readSymbol8("wAIMaxDamage")
  if minBase == 0 and maxBase == 0 then minBase, maxBase = base, base end
  self.duelVars:swapTurn()
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", receiverSlot)

  local function calculate()
    return self:_calculateReverseDamageToSlot(receiverSlot, attack, base),
      self:_calculateReverseDamageToSlot(receiverSlot, attack, minBase),
      self:_calculateReverseDamageToSlot(receiverSlot, attack, maxBase)
  end
  local damage, minDamage, maxDamage
  if receiverSlot == self.c.PLAY_AREA_ARENA then
    damage, minDamage, maxDamage = calculate()
  else
    damage, minDamage, maxDamage = self:_withClearedArenaSwitchStatuses(calculate)
  end
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", savedLocation)
  self:_writeWord("wDamage", damage)
  self.memory:writeSymbol8("wAIMinDamage", minDamage)
  self.memory:writeSymbol8("wAIMaxDamage", maxDamage)
  return { damage = damage, min = minDamage, max = maxDamage, usable = true, attack = attack }
end

-- CheckIfDefendingPokemonCanKnockOut:: preserves the source's exact-equality
-- quirk: an overkill estimate does not set carry here; only HP == damage does.
function AI:checkIfDefendingPokemonCanKnockOut()
  local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP)
  local best = 0
  for attackIndex = 0, 1 do
    local estimate, err = self:estimateDamageFromDefendingPokemon(attackIndex)
    if not estimate then return nil, err end
    if estimate.usable and estimate.damage == hp and estimate.damage > best then
      best = estimate.damage
    end
  end
  return best > 0, best
end


function AI:_cardAtPlayArea(slot, nonTurn)
  if nonTurn then self.duelVars:swapTurn() end
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
  local cardId, row
  if deckIndex ~= 0xff then
    cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
    row = self.cardData:get(cardId)
  end
  if nonTurn then self.duelVars:swapTurn() end
  return deckIndex, cardId, row
end

local function wrMask(cardType)
  if type(cardType) ~= "number" then return 0 end
  return bit.rshift(0x80, bit.band(cardType, 0x07))
end

function AI:_loadDefendingPokemonColorWRAndPrizeCards()
  local _, _, defending = self:_cardAtPlayArea(self.c.PLAY_AREA_ARENA, true)
  assert(defending, "AI retreat scoring requires defending active Pokemon")
  local out = {
    color = wrMask(defending.type),
    weakness = defending.weakness or 0,
    resistance = defending.resistance or 0,
  }
  self.duelVars:swapTurn()
  out.playerPrizes = self.duelOps:countPrizes()
  self.duelVars:swapTurn()
  out.aiPrizes = self.duelOps:countPrizes()
  self.memory:writeSymbol8("wAIPlayerColor", out.color)
  self.memory:writeSymbol8("wAIPlayerWeakness", out.weakness)
  self.memory:writeSymbol8("wAIPlayerResistance", out.resistance)
  self.memory:writeSymbol8("wAIPlayerPrizeCount", out.playerPrizes)
  self.memory:writeSymbol8("wAIOpponentPrizeCount", out.aiPrizes)
  return out
end

-- GetLoadedCard1RetreatCost:: including Dodrio Retreat Aid and Muk suppression.
function AI:getPlayAreaCardRetreatCost(slot)
  local _, _, row = self:_cardAtPlayArea(slot, false)
  assert(row, "retreat cost requested for empty Play Area slot")
  local dodrio = 0
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for bench = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + bench)
    if deckIndex ~= 0xff and self.cardData:getCardIDFromDeckIndex(deckIndex) == self.c.DODRIO then
      dodrio = dodrio + 1
    end
  end
  if dodrio == 0 then return row.retreatCost end
  local _, muk = self.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
  if muk then return row.retreatCost end
  return math.max(0, row.retreatCost - dodrio)
end

-- `opts.ignoreUsability` skips the energy-sufficiency/IGNORE_THIS_ATTACK_F
-- gate below, matching the source's EstimateDamage_VersusDefendingCard, which
-- never checks usability at all -- CheckIfAnyAttackKnocksOutDefendingCard is
-- deliberately usability-blind, with usability checked as a separate later
-- step by whichever caller needs it (see _estimatePotentialKO below). Every
-- existing call site omits `opts`, so default behavior is unchanged.
function AI:_estimateDamageFromPlayArea(slot, attackIndex, opts)
  opts = opts or {}
  if slot == self.c.PLAY_AREA_ARENA then
    return self:estimateDamageVersusDefendingCard(attackIndex)
  end
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
  if deckIndex == 0xff then return { damage = 0, min = 0, max = 0, usable = false } end
  local need = self:checkEnergyNeededForAttack(slot, attackIndex)
  if not need then return { damage = 0, min = 0, max = 0, usable = false } end
  if not opts.ignoreUsability and not need.enough then
    return { damage = 0, min = 0, max = 0, usable = false }
  end
  local _, attack, cardId = self.combat:loadAttack(deckIndex, attackIndex)
  if attack.nameTextId == 0 or attack.category == self.c.POKEMON_POWER then
    return { damage = 0, min = 0, max = 0, usable = false, attack = attack }
  end
  if not opts.ignoreUsability and self:_attackFlag(attack, 2, self.c.IGNORE_THIS_ATTACK_F) then
    return { damage = 0, min = 0, max = 0, usable = false, attack = attack }
  end
  local savedLocation = self.memory:readSymbol8("hTempPlayAreaLocation_ff9d")
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
  self.memory:writeSymbol8("wAIMinDamage", attack.damage)
  self.memory:writeSymbol8("wAIMaxDamage", attack.damage)
  local valid, reason = self:_validateAIPhase()
  if not valid then
    self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", savedLocation)
    return nil, reason
  end
  local carry, err = self.combat.effects:tryExecute(self.c.EFFECTCMDTYPE_AI,
    { combat = self.combat, ai = self })
  if carry == nil then
    self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", savedLocation)
    return nil, err
  end
  local base = self:_readWord("wDamage")
  local minBase = self.memory:readSymbol8("wAIMinDamage")
  local maxBase = self.memory:readSymbol8("wAIMaxDamage")
  if minBase == 0 and maxBase == 0 then minBase, maxBase = base, base end

  local function calculate()
    return self:_calculateForwardDamageFromSlot(slot, attack, cardId, base),
      self:_calculateForwardDamageFromSlot(slot, attack, cardId, minBase),
      self:_calculateForwardDamageFromSlot(slot, attack, cardId, maxBase)
  end
  -- The source clears the old Active card's switch-sensitive state while
  -- considering a Bench attacker as the post-switch Arena card.
  local damage, minDamage, maxDamage = self:_withClearedArenaSwitchStatuses(calculate)

  local status = self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_STATUS)
  local poison = 0
  if self.c.DOUBLE_POISONED_F and hasFlag(status, self.c.DOUBLE_POISONED_F) then poison = 20
  elseif self.c.POISONED_F and hasFlag(status, self.c.POISONED_F) then poison = 10 end
  damage, minDamage, maxDamage = math.min(255, damage + poison),
    math.min(255, minDamage + poison), math.min(255, maxDamage + poison)

  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", savedLocation)
  self:_writeWord("wDamage", damage)
  self.memory:writeSymbol8("wAIMinDamage", minDamage)
  self.memory:writeSymbol8("wAIMaxDamage", maxDamage)
  return { damage = damage, min = minDamage, max = maxDamage, usable = true, attack = attack }
end

function AI:checkIfAnyAttackKnocksOutDefendingCard(slot)
  slot = slot or self.c.PLAY_AREA_ARENA
  local hp = self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_HP)
  for attackIndex = 0, 1 do
    local estimate, err = self:_estimateDamageFromPlayArea(slot, attackIndex)
    if not estimate then return nil, err end
    if estimate.usable ~= false and estimate.damage >= hp and estimate.damage > 0 then
      self.memory:writeSymbol8("wSelectedAttack", attackIndex)
      return true, attackIndex, estimate.damage
    end
  end
  return false
end

-- CheckIfAnyAttackKnocksOutDefendingCard:: the source primitive itself is
-- purely damage-vs-HP with no usability gate at all -- EstimateDamage_Versus-
-- DefendingCard only ever zeroes damage for a Pokemon Power, never for
-- insufficient Energy. checkIfAnyAttackKnocksOutDefendingCard above already
-- matches that for the Active slot (estimateDamageVersusDefendingCard never
-- checked usability), but several existing callers pass a Bench slot and rely
-- on _estimateDamageFromPlayArea's default Bench gate folding potential-KO and
-- usability together. This is a separate, genuinely usability-blind primitive
-- for the one caller that needs the source's real two-step shape: retreat and
-- switch-target scoring, where a Bench Pokemon that WOULD KO if only it had
-- its attack's Energy is still relevant if that Energy is sitting in hand.
function AI:_estimatePotentialKO(slot)
  slot = slot or self.c.PLAY_AREA_ARENA
  local hp = self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_HP)
  for attackIndex = 0, 1 do
    local estimate, err = self:_estimateDamageFromPlayArea(slot, attackIndex, { ignoreUsability = true })
    if not estimate then return nil, err end
    if estimate.damage >= hp and estimate.damage > 0 then
      self.memory:writeSymbol8("wSelectedAttack", attackIndex)
      return true, attackIndex, estimate.damage
    end
  end
  return false
end

-- CheckIfSelectedAttackIsUnusable:: Bench-card path. Source skips the
-- Active-only substatus/paralysis/sleep/amnesia/EFFECTCMDTYPE_INITIAL_EFFECT_1
-- gate entirely for a Bench Pokemon (those substatuses only ever apply to the
-- Arena card); only Energy sufficiency and IGNORE_THIS_ATTACK_F apply. The
-- Active case is already covered by _checkAttackUsableForAI.
function AI:_checkIfBenchAttackUnusable(slot, attackIndex)
  local need = self:checkEnergyNeededForAttack(slot, attackIndex)
  if not need or not need.enough then return true end
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
  local _, attack = self.combat:loadAttack(deckIndex, attackIndex)
  return self:_attackFlag(attack, 2, self.c.IGNORE_THIS_ATTACK_F) == true
end

-- Shared combinator for AIDecideWhetherToRetreat's Active gate and Bench-KO
-- loop (retreat.asm), and AIDecide_SuperEnergyRemoval's active-defender check
-- (_activeCanKONowOrWithHandEnergy below, now a thin ARENA-only wrapper):
-- CheckIfAnyAttackKnocksOutDefendingCard (usability-blind) -> if the KO
-- attack is not currently usable, LookForEnergyNeededForAttackInHand may still
-- make it relevant with exactly one Energy from hand.
function AI:_canKnockOutNowOrWithHandEnergy(slot)
  slot = slot or self.c.PLAY_AREA_ARENA
  local canKO, attackIndex = self:_estimatePotentialKO(slot)
  if canKO == nil then return nil, attackIndex end
  if not canKO then return false end
  local unusable
  if slot == self.c.PLAY_AREA_ARENA then
    local usable, reason = self:_checkAttackUsableForAI(attackIndex)
    if reason and reason:match("^untranslated_effect:") then return nil, reason end
    unusable = not usable
  else
    unusable = self:_checkIfBenchAttackUnusable(slot, attackIndex)
  end
  if not unusable then return true end
  return self:_lookForEnergyNeededInHand(slot, attackIndex)
end

-- LookForEnergyNeededForAttackInHand:: exact source branching on the
-- already-selected attack (set by the caller, e.g. via
-- CheckIfAnyAttackKnocksOutDefendingCard or LookForEnergyNeededInHand below).
-- A single missing basic/colored Energy is satisfied only by that specific
-- card; a single missing Colorless is satisfied by ANY Energy card; two
-- missing Colorless are satisfied ONLY by Double Colorless Energy
-- specifically. Any other total (0, or >=2 that is not exactly "2
-- Colorless") fails. Previously this checked the colored and colorless
-- branches independently of each other and of the source's b+c total, so a
-- 2-Colorless requirement could be wrongly satisfied by any single ordinary
-- Energy card in hand.
function AI:_lookForEnergyNeededInHand(slot, attackIndex)
  local need = self:checkEnergyNeededForAttack(slot, attackIndex)
  if not need then return false end
  local total = need.colored + need.colorless
  if total == 1 then
    if need.colored > 0 then
      return need.energyCardId ~= nil and self:_findCardIDInHand(need.energyCardId) ~= nil
    end
    return #self:_energyCardsInHand() > 0
  end
  if total == 2 and need.colorless == 2 then
    return self:_findCardIDInHand(self.c.DOUBLE_COLORLESS_ENERGY) ~= nil
  end
  return false
end

function AI:_canDamageDefendingPokemon(slot)
  for attackIndex = self.c.FIRST_ATTACK_OR_PKMN_POWER, self.c.SECOND_ATTACK do
    if slot == self.c.PLAY_AREA_ARENA then
      local usable, reason = self:_checkAttackUsableForAI(attackIndex)
      if usable then
        local estimate, err = self:estimateDamageVersusDefendingCard(attackIndex)
        if not estimate then return nil, err end
        if estimate.damage > 0 then return true end
      elseif reason and reason:match("^untranslated_effect:") then
        return nil, reason
      end
    else
      local estimate, err = self:_estimateDamageFromPlayArea(slot, attackIndex)
      if not estimate then return nil, err end
      if estimate.usable ~= false and estimate.damage > 0 then return true end
    end
  end
  return false
end

function AI:_defenderCanExactKOPlayArea(slot)
  local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
  if hp == 0 then return false end
  local best = 0
  for attackIndex = self.c.FIRST_ATTACK_OR_PKMN_POWER, self.c.SECOND_ATTACK do
    local estimate, err = self:estimateDamageFromDefendingPokemon(attackIndex, slot)
    if not estimate then return nil, err end
    if estimate.usable and estimate.damage == hp and estimate.damage > best then
      best = estimate.damage
    end
  end
  return best > 0, best
end

-- SetAIRetreatFlags:: on the opponent/AI turn sets bit 7 only before an attack
-- has been attempted. Bit 0 is subsequently set when a Bench card can KO.
function AI:setAIRetreatFlags()
  local flags = 0
  if self.memory:readSymbol8("wAITriedAttack") == 0 then flags = 0x80 end
  self.memory:writeSymbol8("wAIRetreatFlags", flags)
  return flags
end

-- AIDecideBenchPokemonToSwitchTo:: common scoring path, including the
-- deck-specific retreat bonus list when that pointer is actually initialized.
-- Source decks with the documented missing store_list_pointer receive no bonus.
function AI:decideBenchPokemonToSwitchTo()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if count < 2 then return nil, "no_bench" end
  local meta = self:_loadDefendingPokemonColorWRAndPrizeCards()
  local retreatFlags = self:setAIRetreatFlags()
  local defendingStage = select(3, self:_cardAtPlayArea(self.c.PLAY_AREA_ARENA, true)).stage
  local bestSlot, bestScore = self.c.PLAY_AREA_BENCH_1, -1
  local scores = {}
  scores[self.c.PLAY_AREA_ARENA] = 50

  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local score = 50
    local canKO, koAttack, koErr = self:checkIfAnyAttackKnocksOutDefendingCard(slot)
    if canKO == nil then return nil, koAttack end
    if canKO then
      score = satAdd(score, 10)
      retreatFlags = bit.bor(retreatFlags, 0x01)
      self.memory:writeSymbol8("wAIRetreatFlags", retreatFlags)
      if meta.aiPrizes < 2 then score = satAdd(score, 10) end
    end

    for attackIndex = 0, 1 do
      local estimate, err = self:_estimateDamageFromPlayArea(slot, attackIndex)
      if not estimate then return nil, err end
      if estimate.usable ~= false then score = satAdd(score, math.floor(estimate.damage / 10) + 1) end
    end

    -- .check_energy_card: LookForEnergyNeededInHand tries FIRST_ATTACK_OR_
    -- PKMN_POWER then SECOND_ATTACK itself; it is not the already-selected-
    -- attack variant, and does not depend on whatever wSelectedAttack held
    -- from the score loop just above. It leaves wSelectedAttack naming
    -- whichever attack it matched, which the damage bonus below then reads.
    if self:_lookForAnyEnergyNeededInHand(slot) then
      local selected = self.memory:readSymbol8("wSelectedAttack")
      local estimate, err = self:_estimateDamageFromPlayArea(slot, selected)
      if not estimate then return nil, err end
      score = satAdd(score, math.floor(estimate.damage / 20))
    end

    if self.duelOps:getPlayAreaCardAttachedEnergies(slot) == 0 then score = satSub(score, 1) end
    local _, _, defending = self:_cardAtPlayArea(self.c.PLAY_AREA_ARENA, true)
    if defending and defending.id == self.c.MR_MIME then
      local canDamage, err = self:_canDamageDefendingPokemon(slot)
      if canDamage == nil then return nil, err end
      if canDamage then score = satAdd(score, 5) end
    end

    local _, cardId, row = self:_cardAtPlayArea(slot, false)
    local color = self.combat.status:getPlayAreaCardColor(slot)
    local colorMask = wrMask(color)
    if bit.band(meta.weakness, colorMask) ~= 0 then score = satAdd(score, 3) end
    if bit.band(meta.resistance, colorMask) ~= 0 then score = satSub(score, 2) end
    if bit.band(row.resistance or 0, meta.color) ~= 0 then score = satAdd(score, 2) end
    if bit.band(row.weakness or 0, meta.color) ~= 0 then score = satSub(score, 3) end

    local retreatCost = self:getPlayAreaCardRetreatCost(slot)
    if retreatCost < 2 then score = satAdd(score, 1)
    elseif retreatCost > 2 then score = satSub(score, 1) end

    if retreatFlags ~= 0x81 then
      local exactKO, err = self:_defenderCanExactKOPlayArea(slot)
      if exactKO == nil then return nil, err end
      if exactKO then score = satSub(score, meta.playerPrizes == 1 and 10 or 3) end
    end

    local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
    if hp == 0 then score = 0 else score = satAdd(score, math.floor(hp / 40)) end
    if cardId == self.c.MR_MIME or (cardId == self.c.MEW_LV8 and defendingStage ~= self.c.BASIC) then
      score = satAdd(score, 5)
    end
    if row.aiInfo == self.c.AI_INFO_BENCH_UTILITY then score = satSub(score, 2) end
    if cardId == self.c.MYSTERIOUS_FOSSIL or cardId == self.c.CLEFAIRY_DOLL then score = satSub(score, 10) end

    local retreatBonus = self:_deckAIList("retreatBonus")
    if retreatBonus then
      for _, entry in ipairs(retreatBonus.entries) do
        if entry.cardId == cardId then
          if entry.delta >= 0 then score = satAdd(score, entry.delta)
          else score = satSub(score, -entry.delta) end
        end
      end
    end

    scores[slot] = score
    if score >= bestScore then bestScore, bestSlot = score, slot end -- source ties choose later slot
  end

  local base, bank = self.memory:address("wPlayAreaAIScore")
  for slot = 0, self.c.MAX_PLAY_AREA_POKEMON - 1 do
    self.memory:write8("wram", base + slot, scores[slot] or 0, bank)
  end
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", bestSlot)
  self.memory:writeSymbol8("wAIRetreatScore", 0)
  return bestSlot, bestScore
end

function AI:_benchHasAlternativeNotMatching(mask, field)
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local _, _, row = self:_cardAtPlayArea(slot, false)
    if row then
      local value = field == "type" and wrMask(row.type) or (row[field] or 0)
      if bit.band(value, mask) == 0 then return true end
    end
  end
  return false
end

function AI:_benchHasMatching(mask, field)
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local _, _, row = self:_cardAtPlayArea(slot, false)
    if row then
      local value = field == "type" and wrMask(row.type) or (row[field] or 0)
      if bit.band(value, mask) ~= 0 then return true end
    end
  end
  return false
end

-- AIDecideWhetherToRetreat:: universal score path, including the source's
-- boss/progression last-prize gates and fully-powered/setup-count heuristic.
function AI:decideWhetherToRetreat()
  if self.memory:readSymbol8("wConfusionRetreatCheckWasUnsuccessful") ~= 0 then return false, 0 end
  self.memory:writeSymbol8("wAIPlayEnergyCardForRetreat", 0)
  local meta = self:_loadDefendingPokemonColorWRAndPrizeCards()
  local score = 0x80
  local prior = self.memory:readSymbol8("wAIRetreatScore")
  if prior ~= 0 then score = satAdd(score, math.floor(prior / 4) * 2) end -- exact SRL,SRL,SLA sequence

  local status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
  if bit.band(status, self.c.DOUBLE_POISONED) ~= 0 then score = satAdd(score, 2) end
  if bit.band(status, self.c.CNF_SLP_PRZ) == self.c.CONFUSED then score = satAdd(score, 1) end

  -- AIDecideWhetherToRetreat's Active gate: CheckIfAnyAttackKnocksOutDefending-
  -- Card, then CheckIfSelectedAttackIsUnusable, then -- only if unusable --
  -- LookForEnergyNeededForAttackInHand as a rescue. A working KO (now or with
  -- one Energy from hand) discourages retreating.
  local activeWorkingKO, activeKOErr = self:_canKnockOutNowOrWithHandEnergy(self.c.PLAY_AREA_ARENA)
  if activeWorkingKO == nil then return nil, activeKOErr end
  if activeWorkingKO then
    score = satSub(score, 5)
    if meta.aiPrizes < 2 then score = satSub(score, 35) end
  end

  local defendingCanKO, koDamage = self:checkIfDefendingPokemonCanKnockOut()
  if defendingCanKO == nil then return nil, koDamage end
  if defendingCanKO then score = satAdd(score, 2) end
  local notBossDeck = self:_checkIfNotABossDeckID()
  if not notBossDeck then
    if defendingCanKO and meta.playerPrizes < 2 then
      self.memory:writeSymbol8("wAIPlayEnergyCardForRetreat", self.c.TRUE)
    end
    if meta.playerPrizes < 2 then score = satAdd(score, 2) end
    if meta.aiPrizes < 2 then score = satSub(score, 2) end
  end

  local _, activeId, active = self:_cardAtPlayArea(self.c.PLAY_AREA_ARENA, false)
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local activeColor = wrMask(self.combat.status:getPlayAreaCardColor(self.c.PLAY_AREA_ARENA))
  if bit.band(meta.resistance, activeColor) ~= 0 then
    score = satAdd(score, 1)
    if not self:_benchHasAlternativeNotMatching(meta.resistance, "type") then score = satSub(score, 2) end
  end
  if bit.band(active.weakness or 0, meta.color) ~= 0 then
    score = satAdd(score, 2)
    if not self:_benchHasAlternativeNotMatching(meta.color, "weakness") then score = satSub(score, 3) end
  end
  if bit.band(active.resistance or 0, meta.color) ~= 0 then score = satSub(score, 3) end
  local weakBenchSlot
  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local _, _, row = self:_cardAtPlayArea(slot, false)
    if row and bit.band(wrMask(row.type), meta.weakness) ~= 0 then
      weakBenchSlot = slot
      break
    end
  end
  if weakBenchSlot then
    score = satAdd(score, 2)
    -- Source special-case: when Porygon is Active and the matching Bench card
    -- can actually damage the defender, this branch adds ten more and skips the
    -- subsequent Active-color weakness penalty.
    if activeId == self.c.PORYGON then
      local canDamage, porygonErr = self:_canDamageDefendingPokemon(weakBenchSlot)
      if canDamage == nil then return nil, porygonErr end
      if canDamage then
        score = satAdd(score, 10)
      elseif bit.band(meta.weakness, activeColor) ~= 0 then
        score = satSub(score, 3)
      end
    elseif bit.band(meta.weakness, activeColor) ~= 0 then
      score = satSub(score, 3)
    end
  elseif bit.band(meta.weakness, activeColor) ~= 0 then
    score = satSub(score, 3)
  end
  if self:_benchHasMatching(meta.color, "resistance") then score = satAdd(score, 1) end

  -- .check_ko_2/.loop_ko_1/.success: same potential-KO-then-usable-or-rescue
  -- shape as the Active gate above -- a Bench Pokemon missing just one Energy
  -- for its KO attack still counts.
  local benchCanKO = false
  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local can, e = self:_canKnockOutNowOrWithHandEnergy(slot)
    if can == nil then return nil, e end
    if can then benchCanKO = true break end
  end
  if benchCanKO then
    score = satAdd(score, 2)
    if not notBossDeck and meta.aiPrizes < 2 then
      -- Source attempts no rescue here: only a currently-usable Active KO
      -- skips the +40/energy-for-retreat bonus. A potential-but-unusable
      -- Active KO falls through to the bonus exactly like no KO at all.
      local activePotentialKO, activeAttackIndex, activeErr = self:_estimatePotentialKO(self.c.PLAY_AREA_ARENA)
      if activePotentialKO == nil then return nil, activeAttackIndex end
      local activeHasWorkingKO = false
      if activePotentialKO then
        local usable, reason = self:_checkAttackUsableForAI(activeAttackIndex)
        if reason and reason:match("^untranslated_effect:") then return nil, reason end
        activeHasWorkingKO = usable == true
      end
      if not activeHasWorkingKO then
        score = satAdd(score, 40)
        self.memory:writeSymbol8("wAIPlayEnergyCardForRetreat", self.c.TRUE)
      end
    end
  end

  local _, defendingId = self:_cardAtPlayArea(self.c.PLAY_AREA_ARENA, true)
  if defendingId == self.c.MR_MIME or defendingId == self.c.HITMONLEE then
    local activeCanDamage, damageErr = self:_canDamageDefendingPokemon(self.c.PLAY_AREA_ARENA)
    if activeCanDamage == nil then return nil, damageErr end
    if not activeCanDamage then
      for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
        local benchDamage, e = self:_canDamageDefendingPokemon(slot)
        if benchDamage == nil then return nil, e end
        if benchDamage then
          score = satAdd(score, 5)
          self.memory:writeSymbol8("wAIPlayEnergyCardForRetreat", self.c.TRUE)
          break
        end
      end
    end
  end

  local cost = self:getPlayAreaCardRetreatCost(self.c.PLAY_AREA_ARENA)
  if cost == 2 then score = satSub(score, 1)
  elseif cost >= 3 then score = satSub(score, 2) end

  if not self:_checkIfArenaCardIsFullyPowered() then
    local setup = self:_countNumberOfSetUpBenchPokemon()
    if setup >= 2 then score = satAdd(score, setup) end
  end

  local safeBench = false
  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local _, cardId = self:_cardAtPlayArea(slot, false)
    if cardId ~= self.c.MYSTERIOUS_FOSSIL and cardId ~= self.c.CLEFAIRY_DOLL then
      local exact, e = self:_defenderCanExactKOPlayArea(slot)
      if exact == nil then return nil, e end
      if not exact then safeBench = true break end
    end
  end
  if not safeBench then score = satSub(score, 20) end

  if activeId == self.c.MYSTERIOUS_FOSSIL or activeId == self.c.CLEFAIRY_DOLL then
    for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
      local exact, e = self:_defenderCanExactKOPlayArea(slot)
      if exact == nil then return nil, e end
      local canDamage, de = self:_canDamageDefendingPokemon(slot)
      if canDamage == nil then return nil, de end
      if not exact and canDamage then
        self.memory:writeSymbol8("wAIScore", score)
        return true, score
      end
    end
  end

  self.memory:writeSymbol8("wAIScore", score)
  return score >= 131, score
end

function AI:_energyIsUsefulForRetreat(deckIndex, activeId, activeType)
  local energyId = self.cardData:getCardIDFromDeckIndex(deckIndex)
  if energyId == self.c.DOUBLE_COLORLESS_ENERGY then return true end
  if activeType == self.c.TYPE_PKMN_COLORLESS then return true end
  if activeId == self.c.EXEGGCUTE or activeId == self.c.EXEGGUTOR
      or activeId == self.c.PSYDUCK or activeId == self.c.GOLDUCK then
    if energyId == self.c.PSYCHIC_ENERGY then return true end
  end
  if activeId == self.c.SURFING_PIKACHU_LV13 or activeId == self.c.SURFING_PIKACHU_ALT_LV13 then
    if energyId == self.c.WATER_ENERGY then return true end
  end
  if activeId == self.c.EEVEE and (energyId == self.c.WATER_ENERGY
      or energyId == self.c.FIRE_ENERGY or energyId == self.c.LIGHTNING_ENERGY) then return true end
  return energyId == self:_energyCardIdForColor(activeType)
end

-- TrainerCardAsPokemon_DiscardEffect:: used by the retreat AI when Clefairy
-- Doll or Mysterious Fossil occupies the Arena.  The selected Bench slot is
-- supplied through hAIPkmnPowerEffectParam in the original AI action path.
function AI:_discardTrainerCardAsPokemonForRetreat(targetSlot)
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if count < 2 then return false, "no_bench" end
  local activeDeckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  self.memory:writeSymbol8("hTempCardIndex_ff9f", activeDeckIndex)
  self.memory:writeSymbol8("hTemp_ffa0", self.c.PLAY_AREA_ARENA)
  self.memory:writeSymbol8("hAIPkmnPowerEffectParam", targetSlot)
  self.duelOps:movePlayAreaCardToDiscardPile(self.c.PLAY_AREA_ARENA)
  self.duelOps:swapArenaWithBenchPokemon(targetSlot)
  self.duelOps:shiftAllPokemonToFirstPlayAreaSlots()
  self:_event("ai_trainer_as_pokemon_discard", { target = targetSlot })
  return true, "trainer_as_pokemon_discarded"
end

-- AITryToRetreat:: exact common payment order: optional one-energy attachment,
-- DCE first for costs >=2, shuffled non-useful Energy next, then arbitrary
-- Energy. Confusion discards the selected cost before the coin check, as ROM.
function AI:tryToRetreat(targetSlot)
  assert(self.playerActions, "general AI retreat requires PlayerActions")
  if self.memory:readSymbol8("wAIPlayEnergyCardForRetreat") ~= 0
      and self.memory:readSymbol8("wAlreadyPlayedEnergy") == 0 then
    local status = bit.band(self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS), self.c.CNF_SLP_PRZ)
    if status ~= self.c.ASLEEP and status ~= self.c.PARALYZED then
      local cost = self:getPlayAreaCardRetreatCost(self.c.PLAY_AREA_ARENA)
      local total = self.duelOps:getPlayAreaCardAttachedEnergies(self.c.PLAY_AREA_ARENA)
      if cost - total == 1 then
        local hand = self:_energyCardsInHand()
        if #hand > 0 then
          local ok, reason = self.playerActions:attachEnergy(hand[1].cardId, self.c.PLAY_AREA_ARENA)
          if not ok then return nil, reason end
        end
      end
    end
  end

  local activeIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local activeId = self.cardData:getCardIDFromDeckIndex(activeIndex)
  if activeId == self.c.MYSTERIOUS_FOSSIL or activeId == self.c.CLEFAIRY_DOLL then
    return self:_discardTrainerCardAsPokemonForRetreat(targetSlot)
  end

  local status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
  local special = bit.band(status, self.c.CNF_SLP_PRZ)
  if special == self.c.ASLEEP or special == self.c.PARALYZED then return false, "retreat_blocked_status" end
  self.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", targetSlot)
  self.memory:writeSymbol8("hTemp_ffa0", status)
  local retreatBase, retreatBank = self.memory:address("hTempRetreatCostCards")
  self.memory:write8("hram", retreatBase, 0xff, retreatBank)

  local cost = self:getPlayAreaCardRetreatCost(self.c.PLAY_AREA_ARENA)
  self.memory:writeSymbol8("wTempCardRetreatCost", cost)
  local active = assert(self.cardData:get(activeId))
  self.memory:writeSymbol8("wTempCardID", activeId)
  self.memory:writeSymbol8("wTempCardType", bit.bor(active.type, self.c.TYPE_ENERGY))

  local selected = {}
  if cost > 0 then
    local count = self.duelOps:createArenaOrBenchEnergyCardList(self.c.PLAY_AREA_ARENA)
    local total = self.duelOps:getPlayAreaCardAttachedEnergies(self.c.PLAY_AREA_ARENA)
    if total < cost then return false, "not_enough_energy_to_retreat" end
    local listBase, listBank = self.memory:address("wDuelTempList")
    local candidates = {}
    for i = 0, count - 1 do candidates[#candidates + 1] = self.memory:read8("wram", listBase + i, listBank) end
    if total == cost then
      selected = candidates
    else
      local remaining = cost
      local kept = {}
      for _, deckIndex in ipairs(candidates) do
        if remaining >= 2 and self.cardData:getCardIDFromDeckIndex(deckIndex) == self.c.DOUBLE_COLORLESS_ENERGY then
          selected[#selected + 1] = deckIndex
          remaining = remaining - 2
        else
          kept[#kept + 1] = deckIndex
        end
      end
      candidates = kept
      if remaining > 0 and #candidates > 0 then
        for i, value in ipairs(candidates) do self.memory:write8("wram", listBase + i - 1, value, listBank) end
        self.memory:write8("wram", listBase + #candidates, 0xff, listBank)
        self.rng:shuffleCards(listBase, #candidates)
        candidates = {}
        for i = 0, #kept - 1 do candidates[#candidates + 1] = self.memory:read8("wram", listBase + i, listBank) end
        kept = {}
        for _, deckIndex in ipairs(candidates) do
          if remaining > 0 and not self:_energyIsUsefulForRetreat(deckIndex, activeId, active.type) then
            selected[#selected + 1] = deckIndex
            remaining = remaining - (self.cardData:getCardIDFromDeckIndex(deckIndex) == self.c.DOUBLE_COLORLESS_ENERGY and 2 or 1)
          else kept[#kept + 1] = deckIndex end
        end
        candidates = kept
      end
      while remaining > 0 and #candidates > 0 do
        local deckIndex = table.remove(candidates, 1)
        selected[#selected + 1] = deckIndex
        remaining = remaining - (self.cardData:getCardIDFromDeckIndex(deckIndex) == self.c.DOUBLE_COLORLESS_ENERGY and 2 or 1)
      end
      if remaining > 0 then return false, "not_enough_energy_to_retreat" end
    end
  end

  for i, deckIndex in ipairs(selected) do
    self.memory:write8("hram", retreatBase + i - 1, deckIndex, retreatBank)
  end
  self.memory:write8("hram", retreatBase + #selected, 0xff, retreatBank)
  for _, deckIndex in ipairs(selected) do self.duelOps:putCardInDiscardPile(deckIndex) end

  if special == self.c.CONFUSED then
    local result, err = self.combat.setup:tossCoin()
    if result == nil then return nil, err end
    if result ~= self.c.HEADS then
      self.memory:writeSymbol8("wConfusionRetreatCheckWasUnsuccessful", self.c.TRUE)
      return false, "confusion_retreat_failed"
    end
  end
  self.duelOps:swapArenaWithBenchPokemon(targetSlot)
  self.memory:writeSymbol8("wConfusionRetreatCheckWasUnsuccessful", 0)
  return true
end

function AI:processRetreat()
  if self.memory:readSymbol8("wAIRetreatedThisTurn") ~= 0 then return false end
  local should, score = self:decideWhetherToRetreat()
  if should == nil then return nil, score end
  if not should then return false end
  local target, targetScore = self:decideBenchPokemonToSwitchTo()
  if not target then return false, targetScore end
  self.memory:writeSymbol8("wAIPlayAreaCardToSwitch", target)
  self.memory:writeSymbol8("wAIRetreatedThisTurn", self.c.TRUE)

  local trainerOK, trainerResult = self:processHandTrainerCards(9)
  if trainerOK == nil then return nil, trainerResult end
  if self.c.AI_FLAG_USED_SWITCH and
      bit.band(self.memory:readSymbol8("wPreviousAIFlags"), self.c.AI_FLAG_USED_SWITCH) ~= 0 then
    self.memory:writeSymbol8("wPreviousAIFlags",
      bit.band(self.memory:readSymbol8("wPreviousAIFlags"), bit.bnot(self.c.AI_FLAG_USED_SWITCH)))
    local moved, moveErr = self:handleAIEnergyTrans("retreat")
    if moved == nil then return nil, moveErr end
    return true, "switch_trainer"
  end
  return self:tryToRetreat(target)
end

function AI:_checkAttackUsableForAI(attackIndex)
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local ok, reason = self.combat:checkAttackUsable(deckIndex, attackIndex)
  if not ok then return false, reason end
  local valid, aiReason = self:_validateAIPhase()
  if not valid then return false, aiReason end
  return true
end

-- Helpers used by GetAIScoreOfAttack:: and HandleSpecialAIAttacks::.
function AI:_hasCardIDAtLocation(cardId, location)
  if cardId == nil then return false end
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    if self.duelVars:get(deckIndex) == location
        and self.cardData:getCardIDFromDeckIndex(deckIndex) == cardId then
      return true, deckIndex
    end
  end
  return false
end

function AI:_hasBasicPokemonInDeck()
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    if self.duelVars:get(deckIndex) == self.c.CARD_LOCATION_DECK then
      local row = self.cardData:get(self.cardData:getCardIDFromDeckIndex(deckIndex))
      if row and row.type < self.c.TYPE_ENERGY and row.stage == self.c.BASIC then return true end
    end
  end
  return false
end

function AI:_cardCanEvolveFromHandOrDeck(cardId)
  return self:_hasEvolutionForCard(cardId, self.c.CARD_LOCATION_HAND)
    or self:_hasEvolutionForCard(cardId, self.c.CARD_LOCATION_DECK)
end

-- CheckIfArenaCardIsFullyPowered::. More than half HP, no pending evolution
-- when HAS_EVOLUTION is set, and the second attack is currently usable.
function AI:_checkIfArenaCardIsFullyPowered()
  local _, cardId, row = self:_cardAtPlayArea(self.c.PLAY_AREA_ARENA, false)
  if not row then return false end
  local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP)
  if hp <= math.floor((row.hp or 0) / 2) then return false end
  local hasEvolution = bit.band(row.aiInfo or 0, self.c.HAS_EVOLUTION or 0x10) ~= 0
  if hasEvolution and self:_cardCanEvolveFromHandOrDeck(cardId) then return false end
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", self.c.PLAY_AREA_ARENA)
  self.memory:writeSymbol8("wSelectedAttack", self.c.SECOND_ATTACK)
  local usable = self:_checkAttackUsableForAI(self.c.SECOND_ATTACK)
  return usable == true
end

-- CountNumberOfSetUpBenchPokemon::. The source intentionally assumes a second
-- attack exists and only applies the Bench branch of CheckIfSelectedAttackIsUnusable.
function AI:_countNumberOfSetUpBenchPokemon()
  local savedSlot = self.memory:readSymbol8("hTempPlayAreaLocation_ff9d")
  local savedAttack = self.memory:readSymbol8("wSelectedAttack")
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local setup = 0
  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
    local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
    local row = self.cardData:get(cardId)
    local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
    if row and hp > math.floor((row.hp or 0) / 2) then
      local hasEvolutionFlag = bit.band(row.aiInfo or 0, self.c.HAS_EVOLUTION or 0x10) ~= 0
      if not hasEvolutionFlag or not self:_cardCanEvolveFromHandOrDeck(cardId) then
        self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
        self.memory:writeSymbol8("wSelectedAttack", self.c.SECOND_ATTACK)
        local need = self:checkEnergyNeededForAttack(slot, self.c.SECOND_ATTACK)
        if need and need.enough and not self:_attackFlag(need.attack, 2, self.c.IGNORE_THIS_ATTACK_F) then
          setup = setup + 1
        end
      end
    end
  end
  self.memory:writeSymbol8("wSelectedAttack", savedAttack)
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", savedSlot)
  return setup
end

-- .check_if_kos_bench local from GetAIScoreOfAttack::. This is side-relative:
-- it counts KOs on the current turn holder's Bench, then compares the count to
-- the *other* side's remaining prizes.
function AI:_checkHighRecoilBenchKOs(initialKOs, benchDamage)
  local kos = initialKOs
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
    if hp <= benchDamage then kos = kos + 1 end
  end
  self.duelVars:swapTurn()
  local prizes = self.duelOps:countPrizes()
  self.duelVars:swapTurn()
  return kos >= prizes, kos
end

-- Full LOW_RECOIL/HIGH_RECOIL score policy from attacks.asm. A terminal result
-- means the source jumps straight to .done after setting/encouraging wAIScore.
function AI:_applyRecoilAIScore(score, attack)
  local low = self:_attackFlag(attack, 1, self.c.LOW_RECOIL_F)
  local high = self:_attackFlag(attack, 1, self.c.HIGH_RECOIL_F)
  if (not low and not high) or (attack.effectParam or 0) == 0 then return score, false end

  local recoil = self.combat:applyDamageModifiersToSelf(attack.effectParam)
  score = satSub(score, math.floor(recoil / 10))
  if not high then
    if recoil >= self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP) then score = satSub(score, 10) end
    return score, false
  end

  if self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) < 2 then return 0, true end
  local deckId = self.memory:readSymbol8("wOpponentDeckID")
  if deckId == self.c.BOOM_BOOM_SELFDESTRUCT_DECK_ID then return satAdd(score, 20), true end
  if deckId == self.c.POWER_GENERATOR_DECK_ID then return 0, true end

  local _, activeId, active = self:_cardAtPlayArea(self.c.PLAY_AREA_ARENA, false)
  if deckId == self.c.ZAPPING_SELFDESTRUCT_DECK_ID then
    local notInDeck = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)
    local currentHP = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP)
    local damage = math.max(0, (active.hp or currentHP) - currentHP)
    if notInDeck < 31 and damage * 2 >= (active.hp or 0) then
      local benchDamage = activeId == self.c.MAGNEMITE_LV13 and 10 or 20
      local givesPlayerDuel, _ = self:_checkHighRecoilBenchKOs(1, benchDamage)
      if givesPlayerDuel then return 0, true end
      return satAdd(score, 20), true
    end
  end

  if deckId == self.c.ROCK_CRUSHER_DECK_ID then
    if self.duelOps:countPrizes() >= 4 then return 0, true end
    self.duelVars:swapTurn()
    local winsDuel = self:_checkHighRecoilBenchKOs(0, 20)
    self.duelVars:swapTurn()
    if winsDuel then return satAdd(score, 20), true end
    -- Source falls through into the generic checks when this test fails.
  end

  local benchDamage
  if activeId == self.c.CHANSEY then benchDamage = 0
  elseif activeId == self.c.MAGNEMITE_LV13 or activeId == self.c.WEEZING then benchDamage = 10
  else benchDamage = 20 end

  self.duelVars:swapTurn()
  local winsDuel, playerBenchKOs = self:_checkHighRecoilBenchKOs(0, benchDamage)
  self.duelVars:swapTurn()
  if winsDuel then return satAdd(score, 20), true end

  local givesPlayerDuel, ownKOs = self:_checkHighRecoilBenchKOs(1, benchDamage)
  if givesPlayerDuel then return 0, true end
  score = satSub(score, math.max(0, ownKOs - 1))
  score = satAdd(score, playerBenchKOs)
  return score, false
end

function AI:_healingAttackBonus(attack, dealtDamage)
  if not self:_attackFlag(attack, 2, self.c.HEAL_USER_F) then return 0 end
  local param = attack.effectParam or 0
  local potential
  if param == self.c.HEALING_EQUALS_10_HP then
    potential = param -- source constants are damage-counter units: 1 == 10 HP.
  else
    potential = math.floor((dealtDamage or 0) / 10)
    if param ~= self.c.HEALING_EQUALS_DAMAGE_DEALT then
      potential = math.floor((potential + 1) / 2)
    end
    potential = math.min(potential, math.floor(self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP) / 10))
  end
  local damage, _ = self:_damageAt(self.c.PLAY_AREA_ARENA)
  return math.min(potential, math.floor(damage / 10))
end

-- HandleSpecialAIAttacks::. Returns the source's signed-around-$80 score byte.
function AI:_handleSpecialAIAttack(attackIndex)
  local _, cardId = self:_cardAtPlayArea(self.c.PLAY_AREA_ARENA, false)
  local playCount = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local function neutralPlus(n) return 0x80 + n end
  local function hasInDeck(id) return self:_hasCardIDAtLocation(id, self.c.CARD_LOCATION_DECK) end

  if cardId == self.c.NIDORANF then
    if not hasInDeck(self.c.NIDORANM) and not hasInDeck(self.c.NIDORANF) then return 0 end
    if playCount >= self.c.MAX_PLAY_AREA_POKEMON then return 0 end
    return neutralPlus(self.c.MAX_PLAY_AREA_POKEMON - playCount)
  end
  if cardId == self.c.ODDISH or cardId == self.c.BELLSPROUT or cardId == self.c.KRABBY then
    if not hasInDeck(cardId) or playCount >= self.c.MAX_BENCH_POKEMON then return 0 end
    return neutralPlus(self.c.MAX_BENCH_POKEMON - playCount)
  end
  if cardId == self.c.MAROWAK_LV26 then
    local found = false
    for _, id in ipairs({self.c.GEODUDE, self.c.ONIX, self.c.CUBONE, self.c.RHYHORN}) do
      if hasInDeck(id) then found = true break end
    end
    if not found or playCount >= self.c.MAX_BENCH_POKEMON then return 0 end
    return neutralPlus(self.c.MAX_BENCH_POKEMON - playCount)
  end
  if cardId == self.c.JIGGLYPUFF_LV13 then
    if not self:_hasBasicPokemonInDeck() or playCount >= self.c.MAX_PLAY_AREA_POKEMON then return 0 end
    return neutralPlus(self.c.MAX_PLAY_AREA_POKEMON - playCount)
  end
  if cardId == self.c.EXEGGUTOR then
    local should, err = self:decideWhetherToRetreat()
    if should == nil then return nil, err end
    return should and 0x8a or 0
  end
  if cardId == self.c.SCYTHER or cardId == self.c.VAPOREON_LV29 then
    if self.memory:readSymbol8("wAICannotDamage") ~= 0 then return 0x85 end
    self.memory:writeSymbol8("wSelectedAttack", self.c.SECOND_ATTACK)
    local usable, reason = self:_checkAttackUsableForAI(self.c.SECOND_ATTACK)
    if not usable then
      if reason and reason:match("^untranslated_effect:") then return nil, reason end
      return 0x85
    end
    local estimate, err = self:estimateDamageVersusDefendingCard(self.c.SECOND_ATTACK)
    if not estimate then return nil, err end
    return estimate.damage == 0 and 0x85 or 0
  end
  if cardId == self.c.ELECTRODE_LV42 then
    self.duelVars:swapTurn()
    local playerColor = self.combat.status:getPlayAreaCardColor(self.c.PLAY_AREA_ARENA)
    self.duelVars:swapTurn()
    for slot = self.c.PLAY_AREA_BENCH_1, playCount - 1 do
      local _, _, row = self:_cardAtPlayArea(slot, false)
      if row and row.type == playerColor then return 0 end
    end
    return 0x82
  end
  if cardId == self.c.MEW_LV23 then
    local _, findErr, found = self:_lookForCardThatIsKnockedOutOnDevolution()
    if findErr then return nil, findErr end
    return found and 0x85 or 0
  end
  if cardId == self.c.PORYGON then
    local status = bit.band(self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS), self.c.CNF_SLP_PRZ)
    if status == self.c.CONFUSED then return 0 end
    local setup = self:_countNumberOfSetUpBenchPokemon()
    if attackIndex == self.c.FIRST_ATTACK_OR_PKMN_POWER then
      return setup >= 2 and 0x82 or 0x81
    end
    return setup < 2 and 0x82 or 0x81
  end
  if cardId == self.c.MEWTWO_ALT_LV60 or cardId == self.c.MEWTWO_LV60 then
    local found = self:_hasCardIDAtLocation(self.c.PSYCHIC_ENERGY, self.c.CARD_LOCATION_DISCARD_PILE)
    return found and 0x82 or 0
  end
  if cardId == self.c.NINETALES_LV35 then
    local handCount = self.duelVars:getNonTurn(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
    if handCount == 0 then return 0 end
    local roll = self.rng:random(3)
    if roll == 0 then return 0x83 end
    if roll == 1 then return 0 end

    self.duelVars:swapTurn()
    local result = 0
    local playerPlayCount = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    if playerPlayCount < 3 then
      local basics = 0
      for i = 0, self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND) - 1 do
        local deckIndex = self.duelVars:get(self.c.DUELVARS_HAND + i)
        local row = self.cardData:get(self.cardData:getCardIDFromDeckIndex(deckIndex))
        if row and row.type < self.c.TYPE_ENERGY and row.stage == self.c.BASIC then basics = basics + 1 end
      end
      if basics >= 2 then result = 0x83 end
    end
    if result == 0 then
      for slot = self.c.PLAY_AREA_ARENA, playerPlayCount - 1 do
        local _, playId = self:_cardAtPlayArea(slot, false)
        if playId and self:_hasEvolutionForCard(playId, self.c.CARD_LOCATION_HAND) then
          result = 0x83
          break
        end
      end
    end
    self.duelVars:swapTurn()
    return result
  end
  if cardId == self.c.ZAPDOS_LV68 then return 0x83 end
  if cardId == self.c.KANGASKHAN then
    return self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK) >= 41 and 0 or 0x80
  end
  if cardId == self.c.DUGTRIO then
    -- Preserve both Earthquake bugs from the cartridge: GetTurnDuelistVariable
    -- clobbers HL during the Bench walk, and CountPrizes reads the AI's prizes.
    local pointer = self.c.DUELVARS_BENCH
    local d, e = 0, self.c.PLAY_AREA_BENCH_1 - 1
    local terminated = false
    for _ = 1, 0x100 do
      e = (e + 1) % 0x100
      local value = self.duelVars:get(pointer)
      pointer = (pointer + 1) % 0x100
      if value == 0xff then terminated = true break end
      pointer = (self.c.DUELVARS_ARENA_CARD_HP + e) % 0x100
      local hp = self.duelVars:get(pointer)
      if hp < 20 then d = d + 1 end
    end
    if not terminated then return nil, "earthquake_pointer_walk_no_sentinel" end
    return self.duelOps:countPrizes() <= d and 0 or 0x80
  end
  if cardId == self.c.ELECTRODE_LV35 then
    if not hasInDeck(self.c.LIGHTNING_ENERGY) then return 0 end
    local slot, err = self:_selectEnergySpikeAttachmentTarget()
    if slot == nil then return err and nil or 0, err end
    return 0x83
  end
  if cardId == self.c.GOLDUCK or cardId == self.c.DRAGONAIR then
    self.duelVars:swapTurn()
    local total = self.duelOps:getPlayAreaCardAttachedEnergies(self.c.PLAY_AREA_ARENA)
    self.duelVars:swapTurn()
    return total > 0 and 0x83 or 0x80
  end
  return nil, "untranslated_ai_special_attack:" .. tostring(cardId)
end

-- GetAIScoreOfAttack:: complete common scoring path, including the cartridge's
-- deck-specific HIGH_RECOIL policy and SPECIAL_AI_HANDLING dispatcher.
function AI:getAIScoreOfAttack(attackIndex)
  local usable, reason = self:_checkAttackUsableForAI(attackIndex)
  if not usable then
    if reason and reason:match("^untranslated_effect:") then return nil, reason end
    return 0
  end
  local estimate, err = self:estimateDamageVersusDefendingCard(attackIndex)
  if not estimate then return nil, err end
  local attack = estimate.attack

  local score = 0x50
  local defenderHP = self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_HP)
  if estimate.damage >= defenderHP and estimate.damage > 0 then score = satAdd(score, 20) end

  local attackIsNonDamaging = false
  if estimate.damage > 0 then
    score = satAdd(score, math.floor(estimate.damage / 10))
  else
    attackIsNonDamaging = true
    score = satSub(score, 1)
    if estimate.max > 0 then
      score = satAdd(score, 2)
      attackIsNonDamaging = false
    end
    if self:_attackFlag(attack, 1, self.c.DAMAGE_TO_OPPONENT_BENCH_F) then score = satAdd(score, 2) end
  end

  local recoilTerminal
  score, recoilTerminal = self:_applyRecoilAIScore(score, attack)
  if recoilTerminal then return score, estimate end

  local defendingCanKO, koErr = self:checkIfDefendingPokemonCanKnockOut()
  if defendingCanKO == nil then return nil, koErr end
  if defendingCanKO then
    score = satAdd(score, 5)
    if attackIsNonDamaging then score = satSub(score, 5) end
  end

  if self:_attackFlag(attack, 2, self.c.DISCARD_ENERGY_F) then
    score = satSub(score, 1)
    score = satSub(score, attack.effectParam or 0)
  end
  if self:_attackFlag(attack, 2, self.c.ENCOURAGE_THIS_ATTACK_F) then
    score = satAdd(score, attack.effectParam or 0)
  end
  if self:_attackFlag(attack, 2, self.c.NULLIFY_OR_WEAKEN_ATTACK_F) then score = satAdd(score, 1) end
  if self:_attackFlag(attack, 1, self.c.DRAW_CARD_F) then score = satAdd(score, 1) end
  score = satAdd(score, self:_healingAttackBonus(attack, estimate.damage))

  local _, defenderId = self:_cardAtPlayArea(self.c.PLAY_AREA_ARENA, true)
  if defenderId ~= self.c.SNORLAX then
    local targetStatus = self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_STATUS)
    if self:_attackFlag(attack, 1, self.c.INFLICT_POISON_F) then
      local poison = bit.band(targetStatus, self.c.DOUBLE_POISONED)
      if poison == 0 then
        score = satAdd(score, 2)
      elseif bit.band(poison, 0x40) == 0
          and self:_attackFlag(attack, 2, self.c.ENCOURAGE_THIS_ATTACK_F) then
        score = satSub(score, 2)
      end
    end
    local special = bit.band(targetStatus, self.c.CNF_SLP_PRZ)
    if self:_attackFlag(attack, 1, self.c.INFLICT_SLEEP_F) and special ~= self.c.ASLEEP then
      score = satAdd(score, 1)
    end
    if self:_attackFlag(attack, 1, self.c.INFLICT_PARALYSIS_F) then
      score = special == self.c.ASLEEP and satSub(score, 1) or satAdd(score, 1)
    end
    if self:_attackFlag(attack, 1, self.c.INFLICT_CONFUSION_F) then
      if special == self.c.ASLEEP then score = satSub(score, 1)
      elseif special ~= self.c.CONFUSED then score = satAdd(score, 1) end
    end
    local ownStatus = bit.band(self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS), self.c.CNF_SLP_PRZ)
    if ownStatus == self.c.CONFUSED then score = satSub(score, 1) end
  end

  if self:_attackFlag(attack, 3, self.c.SPECIAL_AI_HANDLING_F) then
    local specialScore, specialErr = self:_handleSpecialAIAttack(attackIndex)
    if specialScore == nil then return nil, specialErr end
    if specialScore < 0x80 then score = satSub(score, 0x80 - specialScore)
    else score = satAdd(score, specialScore - 0x80) end
  end
  return score, estimate
end

-- CheckWhetherToSwitchToFirstAttack::.
function AI:checkWhetherToSwitchToFirstAttack(firstScore, selected)
  if selected ~= self.c.SECOND_ATTACK or firstScore < 0x50 then return selected end
  local firstEstimate, err = self:estimateDamageVersusDefendingCard(self.c.FIRST_ATTACK_OR_PKMN_POWER)
  if not firstEstimate then return nil, err end
  local hp = self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_HP)
  if firstEstimate.damage < hp then return selected end
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local _, second = self.combat:loadAttack(deckIndex, self.c.SECOND_ATTACK)
  if self:_attackFlag(second, 2, self.c.HEAL_USER_F) or
      self:_attackFlag(second, 2, self.c.NULLIFY_OR_WEAKEN_ATTACK_F) then
    return selected
  end
  return self.c.FIRST_ATTACK_OR_PKMN_POWER
end

-- AISelectSpecialAttackParameters::. This bridge runs before generic
-- EFFECTCMDTYPE_AI_SELECTION exactly like AITryUseAttack in the cartridge.
-- A carry/true result means the special branch has already populated the HRAM
-- selection bytes and generic AI_SELECTION must be skipped.
function AI:_selectEnergySpikeAttachmentTarget()
  -- Energy Spike calls AIProcessButDontPlayEnergy_SkipEvolution.  That preview
  -- skips only the evolution/hand-color gate; all ordinary slot scoring,
  -- generated deck bonuses, Articuno policy and repeated-bench policy still run.
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local energyBonus = self:_deckAIList("energyBonus")
  local articunoDeltas, articunoErr = self:_legendaryArticunoEnergyDeltas(count)
  if articunoDeltas == nil then return nil, articunoErr end
  local repeatedDeltas = self:_repeatedBenchEnergyDeltas(count)
  local bestSlot, bestScore = nil, -1

  for slot = self.c.PLAY_AREA_ARENA, count - 1 do
    local score = 0x80
    local _, cardId = self:_cardAtPlayArea(slot, false)

    local _, muk = self.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
    if not muk then
      local _, venusaur = self.combat.status:countTurnDuelistPokemonWithActivePkmnPower(self.c.VENUSAUR_LV67)
      if venusaur then score = satAdd(score, 1) end
    end

    if slot == self.c.PLAY_AREA_ARENA then
      local counter = self.memory:readSymbol8("wAIBarrierFlagCounter")
      if self.c.AI_MEWTWO_MILL_F and hasFlag(counter, self.c.AI_MEWTWO_MILL_F) then
        score = satSub(score, 5)
      else
        score = satAdd(score, 4)
      end
      local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP)
      local hpCounters = math.floor(hp / 10)
      local status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
      local atRisk = false
      if hpCounters < 3 then
        if hpCounters == 2 then atRisk = bit.band(status, self.c.DOUBLE_POISONED) ~= 0
        elseif hpCounters <= 1 then atRisk = bit.band(status, self.c.POISONED) ~= 0 end
      end
      if not atRisk then
        local exactKO, koErr = self:_defenderCanExactKOPlayArea(slot)
        if exactKO == nil then return nil, koErr end
        atRisk = exactKO
      end
      if atRisk then
        score = satSub(score, 10)
        if count == 1 then score = satAdd(score, 6) end
      end
    else
      local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
      local hpCounters = math.floor(hp / 10)
      if hpCounters < 3 then score = satSub(score, 3 - hpCounters) end
    end

    local stopScoring = false
    if energyBonus then
      for _, entry in ipairs(energyBonus.entries) do
        if entry.cardId == cardId then
          local attached = self.duelOps:getPlayAreaCardAttachedEnergies(slot)
          if attached >= entry.maxEnergy then
            score = satSub(score, 10)
            stopScoring = true
          elseif entry.delta >= 0 then score = satAdd(score, entry.delta)
          else score = satSub(score, -entry.delta) end
          break
        end
      end
    end

    if not stopScoring then
      local listDelta = (articunoDeltas[slot] or 0) + (repeatedDeltas[slot] or 0)
      if listDelta >= 0 then score = satAdd(score, listDelta)
      else score = satSub(score, -listDelta) end
      score = satAdd(score, 1)
      for attackIndex = self.c.FIRST_ATTACK_OR_PKMN_POWER, self.c.SECOND_ATTACK do
        local delta, err = self:_estimateEnergyScoreAttack(slot, attackIndex, nil)
        if delta == nil then return nil, err end
        if delta >= 0 then score = satAdd(score, delta) else score = satSub(score, -delta) end
      end
    end
    if score > bestScore then bestSlot, bestScore = slot, score end
  end

  if bestSlot == nil or bestScore < 0x85 then return nil end
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", bestSlot)
  return bestSlot
end

-- AIProcessButDontPlayEnergy_SkipEvolutionAndArena::. This preview is used by
-- Energy Trans. The source still scores Arena, but excludes it from the final
-- winner scan; it also skips evolution/hand-color anticipation, has no $85
-- minimum score, and restores wPlayAreaAIScore/wAIScore before return.
function AI:_previewBenchEnergyTargetSkipEvolution()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if count < 2 then return nil end

  local scoreBase, scoreBank = self.memory:address("wPlayAreaAIScore")
  local savedScores = {}
  for slot = 0, self.c.MAX_PLAY_AREA_POKEMON - 1 do
    savedScores[slot] = self.memory:read8("wram", scoreBase + slot, scoreBank)
  end
  local savedAIScore = self.memory:readSymbol8("wAIScore")
  local function restore()
    for slot = 0, self.c.MAX_PLAY_AREA_POKEMON - 1 do
      self.memory:write8("wram", scoreBase + slot, savedScores[slot], scoreBank)
    end
    self.memory:writeSymbol8("wAIScore", savedAIScore)
  end

  local energyBonus = self:_deckAIList("energyBonus")
  local articunoDeltas, articunoErr = self:_legendaryArticunoEnergyDeltas(count)
  if articunoDeltas == nil then restore(); return nil, articunoErr end
  local repeatedDeltas = self:_repeatedBenchEnergyDeltas(count)
  local bestSlot, bestScore = self.c.PLAY_AREA_BENCH_1, 0

  -- AI_ENERGY_FLAG_SKIP_ARENA_CARD only changes the final winner scan in the
  -- source; the ordinary score loop still evaluates Arena before the Bench.
  for slot = self.c.PLAY_AREA_ARENA, count - 1 do
    local score = 0x80
    local _, cardId = self:_cardAtPlayArea(slot, false)

    local _, muk = self.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
    if not muk then
      local _, venusaur = self.combat.status:countTurnDuelistPokemonWithActivePkmnPower(self.c.VENUSAUR_LV67)
      if venusaur then score = satAdd(score, 1) end
    end

    if slot == self.c.PLAY_AREA_ARENA then
      local counter = self.memory:readSymbol8("wAIBarrierFlagCounter")
      if self.c.AI_MEWTWO_MILL_F and hasFlag(counter, self.c.AI_MEWTWO_MILL_F) then
        score = satSub(score, 5)
      else
        score = satAdd(score, 4)
      end
      local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP)
      local hpCounters = math.floor(hp / 10)
      local status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
      local atRisk = false
      if hpCounters < 3 then
        if hpCounters == 2 then atRisk = bit.band(status, self.c.DOUBLE_POISONED) ~= 0
        elseif hpCounters <= 1 then atRisk = bit.band(status, self.c.POISONED) ~= 0 end
      end
      if not atRisk then
        local exactKO, koErr = self:_defenderCanExactKOPlayArea(slot)
        if exactKO == nil then restore(); return nil, koErr end
        atRisk = exactKO
      end
      if atRisk then
        score = satSub(score, 10)
        if count == 1 then score = satAdd(score, 6) end
      end
    else
      local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
      local hpCounters = math.floor(hp / 10)
      if hpCounters < 3 then score = satSub(score, 3 - hpCounters) end
    end

    local stopScoring = false
    if energyBonus then
      for _, entry in ipairs(energyBonus.entries) do
        if entry.cardId == cardId then
          local attached = self.duelOps:getPlayAreaCardAttachedEnergies(slot)
          if attached >= entry.maxEnergy then
            score = satSub(score, 10)
            stopScoring = true
          elseif entry.delta >= 0 then score = satAdd(score, entry.delta)
          else score = satSub(score, -entry.delta) end
          break
        end
      end
    end

    if not stopScoring then
      local listDelta = (articunoDeltas[slot] or 0) + (repeatedDeltas[slot] or 0)
      if listDelta >= 0 then score = satAdd(score, listDelta)
      else score = satSub(score, -listDelta) end
      score = satAdd(score, 1)
      for attackIndex = self.c.FIRST_ATTACK_OR_PKMN_POWER, self.c.SECOND_ATTACK do
        local delta, err = self:_estimateEnergyScoreAttack(slot, attackIndex, nil)
        if delta == nil then restore(); return nil, err end
        if delta >= 0 then score = satAdd(score, delta) else score = satSub(score, -delta) end
      end
    end

    self.memory:write8("wram", scoreBase + slot, score, scoreBank)
    if slot >= self.c.PLAY_AREA_BENCH_1 and score > bestScore then
      -- FindPlayAreaCardWithHighestAIScore.only_bench updates only on strictly
      -- greater score, so equal scores keep the lower/earlier Bench slot.
      bestScore, bestSlot = score, slot
    end
  end

  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", bestSlot)
  restore()
  return bestSlot, bestScore
end

-- GetCardOneStageBelow:: source-shaped helper for AI Devolution Beam target
-- discovery. All Pokemon stages attached to a play-area slot share the same
-- CARD_LOCATION_PLAY_AREA|slot byte, so the lower stage can be reconstructed by
-- scanning deck indices exactly like wAllStagesIndices in the cartridge.
function AI:_getCardOneStageBelow(slot)
  local currentDeckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
  if currentDeckIndex == 0xff then return nil, "empty_slot" end
  local currentId = self.cardData:getCardIDFromDeckIndex(currentDeckIndex)
  local current = self.cardData:get(currentId)
  if not current then return nil, "missing_card_data" end
  if current.stage == self.c.BASIC then return nil, "basic" end

  local stages = {}
  local expected = bit.bor(self.c.CARD_LOCATION_PLAY_AREA, slot)
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    if self.duelVars:get(deckIndex) == expected then
      local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
      local row = self.cardData:get(cardId)
      if row and row.type < self.c.TYPE_ENERGY then stages[row.stage] = deckIndex end
    end
  end

  local stage1 = self.c.STAGE1 or 1
  local stage2WithoutStage1 = self.c.STAGE2_WITHOUT_STAGE1 or 3
  local lowerStage = (current.stage == stage1 or current.stage == stage2WithoutStage1)
    and self.c.BASIC or stage1
  local lower = stages[lowerStage]
  if lower == nil then return nil, "missing_pre_evolution_card" end
  return lower, currentDeckIndex, current
end

-- LookForCardThatIsKnockedOutOnDevolution:: checks the non-turn holder's play
-- area from Arena upward and returns the first evolved Pokemon whose retained
-- damage is at least the max HP of its next-lower stage. When none is found the
-- source returns the saved hTempPlayAreaLocation_ff9d value with carry clear;
-- AISelectSpecialAttackParameters ignores that carry and still stores A, so the
-- value itself is preserved here.
function AI:_lookForCardThatIsKnockedOutOnDevolution()
  local saved = self.memory:readSymbol8("hTempPlayAreaLocation_ff9d")
  self.duelVars:swapTurn()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local found
  for slot = self.c.PLAY_AREA_ARENA, count - 1 do
    self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
    local lower, err, current = self:_getCardOneStageBelow(slot)
    if lower then
      local lowerId = self.cardData:getCardIDFromDeckIndex(lower)
      local lowerRow = self.cardData:get(lowerId)
      local currentHP = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
      local damage = math.max(0, (current.hp or 0) - currentHP)
      if lowerRow and lowerRow.hp <= damage then
        found = slot
        break
      end
    elseif err ~= "basic" then
      self.duelVars:swapTurn()
      self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", saved)
      return nil, err
    end
  end
  self.duelVars:swapTurn()
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", saved)
  return found ~= nil and found or saved, nil, found ~= nil
end

function AI:_selectSpecialAttackParameters(deckIndex, attackIndex)
  local selected = self.memory:readSymbol8("wSelectedAttack")
  local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
  local function finish(value, err)
    self.memory:writeSymbol8("wSelectedAttack", selected)
    return value, err
  end

  if ((self.c.MEWTWO_ALT_LV60 and cardId == self.c.MEWTWO_ALT_LV60)
      or (self.c.MEWTWO_LV60 and cardId == self.c.MEWTWO_LV60))
      and attackIndex == self.c.FIRST_ATTACK_OR_PKMN_POWER then
    -- .EnergyAbsorption: hTemp_ffa0/hTempPlayAreaLocation_ffa1 alias the first
    -- two bytes of hTempList; hTempRetreatCostCards[0] supplies the $ff terminator.
    self.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", 0xff)
    local retreat, retreatBank = self.memory:address("hTempRetreatCostCards")
    self.memory:write8("hram", retreat, 0xff, retreatBank)

    local psychic = 0xff
    for i = 0, self.c.DECK_SIZE - 1 do
      if self.duelVars:get(i) == self.c.CARD_LOCATION_DISCARD_PILE
          and self.cardData:getCardIDFromDeckIndex(i) == self.c.PSYCHIC_ENERGY then
        psychic = i
        break
      end
    end
    self.memory:writeSymbol8("hTemp_ffa0", psychic)

    local discard = self.duelOps:createDiscardPileCardList()
    for _, energyIndex in ipairs(discard) do
      local id = self.cardData:getCardIDFromDeckIndex(energyIndex)
      local row = self.cardData:get(id)
      if energyIndex ~= psychic and row
          and row.type >= self.c.TYPE_ENERGY and row.type < self.c.TYPE_TRAINER then
        self.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", energyIndex)
        break
      end
    end
    return finish(true)
  end

  if self.c.ELECTRODE_LV35 and cardId == self.c.ELECTRODE_LV35
      and attackIndex == self.c.SECOND_ATTACK then
    local lightning
    for i = 0, self.c.DECK_SIZE - 1 do
      if self.duelVars:get(i) == self.c.CARD_LOCATION_DECK
          and self.cardData:getCardIDFromDeckIndex(i) == self.c.LIGHTNING_ENERGY then
        lightning = i
        break
      end
    end
    if lightning == nil then return finish(false) end
    self.memory:writeSymbol8("hTemp_ffa0", lightning)
    local slot, targetErr = self:_selectEnergySpikeAttachmentTarget()
    if slot == nil then return finish(false, targetErr) end
    self.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", slot)
    return finish(true)
  end

  if self.c.MEW_LV23 and cardId == self.c.MEW_LV23
      and attackIndex ~= self.c.FIRST_ATTACK_OR_PKMN_POWER then
    -- .DevolutionBeam always targets the Player's side in hTemp_ffa0. The
    -- helper's carry is intentionally ignored by the source before the special
    -- branch sets carry, so even its no-match A value is committed to ffa1.
    self.memory:writeSymbol8("hTemp_ffa0", 0x01)
    local slot, targetErr = self:_lookForCardThatIsKnockedOutOnDevolution()
    if slot == nil then return finish(nil, targetErr) end
    self.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", slot)
    return finish(true)
  end

  if self.c.EXEGGUTOR and cardId == self.c.EXEGGUTOR
      and attackIndex == self.c.FIRST_ATTACK_OR_PKMN_POWER then
    -- .Teleport uses AIDecideBenchPokemonToSwitchTo, not the random
    -- Teleport_AISelectEffect identity. If there is no Bench the source falls
    -- through with carry clear so generic AI_SELECTION remains eligible.
    local slot, reason = self:decideBenchPokemonToSwitchTo()
    if slot == nil then
      if reason == "no_bench" then return finish(false) end
      return finish(nil, reason)
    end
    self.memory:writeSymbol8("hTemp_ffa0", slot)
    return finish(true)
  end
  return finish(false)
end

-- AITryUseAttack:: AI_SELECTION / AI_SWITCH_DEFENDING_PKMN bridge.
-- The original AI writes menu-equivalent choices into HRAM before handing the
-- attack to the opponent-action path. This single-process runtime performs the
-- same selection phases directly, then tells Combat not to reopen player menus.
function AI:_prepareAttackSelections(deckIndex, attackIndex)
  self.memory:writeSymbol8("hTemp_ffa0", attackIndex)
  self.combat:loadAttack(deckIndex, attackIndex)
  local effects = self.combat.effects

  local initial2, err = effects:checkMatchingCommand(self.c.EFFECTCMDTYPE_INITIAL_EFFECT_2)
  if err then return nil, err end
  local requireSelection, err2 = effects:checkMatchingCommand(self.c.EFFECTCMDTYPE_REQUIRE_SELECTION)
  if err2 then return nil, err2 end
  local aiSelection, err3 = effects:checkMatchingCommand(self.c.EFFECTCMDTYPE_AI_SELECTION)
  if err3 then return nil, err3 end
  local aiSwitch, err4 = effects:checkMatchingCommand(self.c.EFFECTCMDTYPE_AI_SWITCH_DEFENDING_PKMN)
  if err4 then return nil, err4 end

  local specialHandled, specialErr = self:_selectSpecialAttackParameters(deckIndex, attackIndex)
  if specialHandled == nil then return nil, specialErr end

  local hasPlayerSelection = initial2 ~= nil or requireSelection ~= nil
  if hasPlayerSelection and not specialHandled and aiSelection == nil and aiSwitch == nil then
    return nil, "untranslated_ai_selection_path"
  end

  local phases = { self.c.EFFECTCMDTYPE_AI_SWITCH_DEFENDING_PKMN }
  if not specialHandled then
    phases[#phases + 1] = self.c.EFFECTCMDTYPE_AI_SELECTION
  end
  local valid, reason = effects:validatePhases(phases)
  if not valid then return nil, reason end

  if not specialHandled then
    local carry, executeErr = effects:tryExecute(self.c.EFFECTCMDTYPE_AI_SELECTION,
      { combat = self.combat, ai = self })
    if carry == nil then return nil, executeErr end
  end

  -- .use_attack reloads the selected attack whether the special branch carried
  -- or generic AI_SELECTION ran, because either path may clobber shared temps.
  self.combat:loadAttack(deckIndex, attackIndex)
  local carry, executeErr = effects:tryExecute(self.c.EFFECTCMDTYPE_AI_SWITCH_DEFENDING_PKMN,
    { combat = self.combat, ai = self })
  if carry == nil then return nil, executeErr end
  return true, hasPlayerSelection
end
-- AIProcessAndTryToUseAttack::
-- AIProcessButDontUseAttack:: / AIProcessAttacks:: share the same selector.
-- The cartridge has one common selector with an execute flag. Preview callers
-- must leave the play-area/AI score scratch state exactly as they found it.
function AI:_snapshotAttackProcessingScores()
  local snapshot = { playArea = {} }
  local base, bank = self.memory:address("wPlayAreaAIScore")
  for slot = 0, self.c.MAX_PLAY_AREA_POKEMON - 1 do
    local ok, value = pcall(function() return self.memory:read8("wram", base + slot, bank) end)
    snapshot.playArea[slot] = ok and value or 0
  end
  local ok, value = pcall(function() return self.memory:readSymbol8("wAIScore") end)
  snapshot.aiScore = ok and value or 0
  return snapshot
end

function AI:_restoreAttackProcessingScores(snapshot)
  local base, bank = self.memory:address("wPlayAreaAIScore")
  for slot = 0, self.c.MAX_PLAY_AREA_POKEMON - 1 do
    self.memory:write8("wram", base + slot, snapshot.playArea[slot] or 0, bank)
  end
  self.memory:writeSymbol8("wAIScore", snapshot.aiScore or 0)
end

function AI:_selectProcessedAttack()
  -- If PlusPower was already committed, attacks.asm bypasses rescoring and uses
  -- the attack index saved by the Trainer decision routine.
  if self.c.AI_FLAG_USED_PLUSPOWER and bit.band(
      self.memory:readSymbol8("wPreviousAIFlags"), self.c.AI_FLAG_USED_PLUSPOWER) ~= 0 then
    local selected = self.memory:readSymbol8("wAIPlusPowerAttack")
    self.memory:writeSymbol8("wSelectedAttack", selected)
    return selected, 0x50
  end

  if self.c.AI_MEWTWO_MILL and
      self.memory:readSymbol8("wAIBarrierFlagCounter") == self.c.AI_MEWTWO_MILL then
    return false, "finish_no_attack"
  end

  local first, err = self:getAIScoreOfAttack(self.c.FIRST_ATTACK_OR_PKMN_POWER)
  if first == nil then return nil, err end
  self.memory:writeSymbol8("wFirstAttackAIScore", first)
  local second, err2 = self:getAIScoreOfAttack(self.c.SECOND_ATTACK)
  if second == nil then return nil, err2 end

  -- Ties stay on the second attack, matching `cp b / jr nc`.
  local selected, score = self.c.SECOND_ATTACK, second
  if first > second then selected, score = self.c.FIRST_ATTACK_OR_PKMN_POWER, first end
  self.memory:writeSymbol8("wAIScore", score)
  if score < 0x50 then return false, "finish_no_attack" end

  local switched, switchErr = self:checkWhetherToSwitchToFirstAttack(first, selected)
  if switched == nil then return nil, switchErr end
  self.memory:writeSymbol8("wSelectedAttack", switched)
  return switched, score
end

function AI:_processAttacks(execute)
  local selected, detail = self:_selectProcessedAttack()
  if selected == nil then return nil, detail end
  if selected == false then
    if execute then
      self.memory:writeSymbol8("wAIRetreatScore",
        (self.memory:readSymbol8("wAIRetreatScore") + 1) % 0x100)
    end
    return false, detail
  end
  if not execute then return true, selected end

  local trainerOK, trainerErr = self:processHandTrainerCards(14)
  if trainerOK == nil then return nil, trainerErr end

  -- attacks.asm estimates the selected attack again after phase 14. A direct
  -- hit or a bench-damage flag resets retreat pressure; otherwise it increments.
  local estimate, estimateErr = self:estimateDamageVersusDefendingCard(selected)
  if not estimate then return nil, estimateErr end
  if estimate.damage ~= 0 or self:_attackFlag(estimate.attack, 1, self.c.DAMAGE_TO_OPPONENT_BENCH_F) then
    self.memory:writeSymbol8("wAIRetreatScore", 0)
  else
    self.memory:writeSymbol8("wAIRetreatScore",
      (self.memory:readSymbol8("wAIRetreatScore") + 1) % 0x100)
  end

  self.memory:writeSymbol8("wAITriedAttack", self.c.TRUE)
  local active = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local prepared, selectionErr = self:_prepareAttackSelections(active, selected)
  if prepared == nil then return nil, selectionErr end
  local ok, result = self.combat:useAttack(active, selected, {
    verifyPractice = false,
    aiPreparedSelections = prepared,
  })
  if ok then self.memory:writeSymbol8("wOpponentTurnEnded", 1) end
  -- AIProcessAndTryToUseAttack returns carry once an attack was chosen/attempted;
  -- preserve execution failure as the second result while keeping that distinction.
  return true, ok and result or (result or "attack_attempt_failed")
end

function AI:processButDontUseAttack()
  local snapshot = self:_snapshotAttackProcessingScores()
  local chosen, detail = self:_processAttacks(false)
  self:_restoreAttackProcessingScores(snapshot)
  return chosen, detail
end

function AI:processAndTryToUseAttack()
  return self:_processAttacks(true)
end

function AI:_hasEvolutionForCard(cardId, location)
  local baseRow = assert(self.cardData:get(cardId))
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    if self.duelVars:get(deckIndex) == location then
      local row = self.cardData:get(self.cardData:getCardIDFromDeckIndex(deckIndex))
      if row and row.kind == "pokemon" and row.stage ~= self.c.BASIC
          and row.preEvolutionTextId == baseRow.nameTextId then
        return true, deckIndex
      end
    end
  end
  return false
end

function AI:_handHasUsefulEnergyFor(row)
  local needsAnyEnergy = false
  local colored = {}
  for _, attack in ipairs(row.attacks or {}) do
    if (attack.energy[self.c.COLORLESS] or 0) > 0 then needsAnyEnergy = true end
    for color = 0, self.c.NUM_COLORED_TYPES - 1 do
      if (attack.energy[color] or 0) > 0 then colored[self:_energyCardIdForColor(color)] = true end
    end
  end
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  for i = 0, count - 1 do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_HAND + i)
    local id = self.cardData:getCardIDFromDeckIndex(deckIndex)
    local energy = self.cardData:get(id)
    local location = self.duelVars:get(deckIndex)
    if bit.band(location, self.c.CARD_LOCATION_JUST_DRAWN or 0) == 0
        and energy and energy.type >= self.c.TYPE_ENERGY and energy.type < self.c.TYPE_TRAINER then
      if needsAnyEnergy or colored[id] then return true end
    end
  end
  return false
end

function AI:_handSnapshotForPokemonPlay()
  local out = {}
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  for i = 0, count - 1 do out[#out + 1] = self.duelVars:get(self.c.DUELVARS_HAND + i) end

  -- SortTempHandByIDList:: only reorders cards named by the deck-specific list.
  -- The generated mapping contains only pointers the source actually stores;
  -- a missing pointer therefore leaves CreateHandCardList order untouched.
  local list = self:_deckAIList("playFromHandPriority")
  local priority = list and list.cardIds or nil
  if type(priority) ~= "table" or #priority == 0 then return out end
  local front, used = {}, {}
  for _, wantedId in ipairs(priority) do
    for i, deckIndex in ipairs(out) do
      if not used[i] and self.cardData:getCardIDFromDeckIndex(deckIndex) == wantedId then
        front[#front + 1] = deckIndex
        used[i] = true
      end
    end
  end
  for i, deckIndex in ipairs(out) do if not used[i] then front[#front + 1] = deckIndex end end
  return front
end

function AI:_isAttackUsableAtSlot(slot, attackIndex)
  if slot == self.c.PLAY_AREA_ARENA then
    local ok, reason = self:_checkAttackUsableForAI(attackIndex)
    if not ok and reason and reason:match("^untranslated_effect:") then return nil, reason end
    return ok
  end
  local need = self:checkEnergyNeededForAttack(slot, attackIndex)
  if not need or not need.enough then return false end
  return not self:_attackFlag(need.attack, 2, self.c.IGNORE_THIS_ATTACK_F)
end

function AI:_canUseAnyAttackAtSlot(slot)
  for attackIndex = self.c.FIRST_ATTACK_OR_PKMN_POWER, self.c.SECOND_ATTACK do
    local ok, err = self:_isAttackUsableAtSlot(slot, attackIndex)
    if ok == nil then return nil, err end
    if ok then return true, attackIndex end
  end
  return false
end

-- LookForEnergyNeededInHand:: tries FIRST_ATTACK_OR_PKMN_POWER then
-- SECOND_ATTACK, delegating the one-Energy/two-Colorless rule itself to
-- _lookForEnergyNeededInHand (LookForEnergyNeededForAttackInHand) above so
-- the two source routines share one implementation of that rule. Source
-- writes wSelectedAttack before each CheckEnergyNeededForAttack call
-- regardless of outcome, so by the time either check succeeds the variable
-- already names that attack; AIDecideBenchPokemonToSwitchTo reads
-- wSelectedAttack right after calling this to score the matching damage.
function AI:_lookForAnyEnergyNeededInHand(slot)
  for attackIndex = self.c.FIRST_ATTACK_OR_PKMN_POWER, self.c.SECOND_ATTACK do
    self.memory:writeSymbol8("wSelectedAttack", attackIndex)
    if self:_lookForEnergyNeededInHand(slot, attackIndex) then return true end
  end
  return false
end

function AI:_canArenaUseNonResidualAttack()
  for attackIndex = self.c.FIRST_ATTACK_OR_PKMN_POWER, self.c.SECOND_ATTACK do
    local usable, reason = self:_checkAttackUsableForAI(attackIndex)
    if usable then
      local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
      local _, attack = self.combat:loadAttack(deckIndex, attackIndex)
      if bit.band(attack.category or 0, self.c.RESIDUAL or 0) == 0 then return true end
    elseif reason and reason:match("^untranslated_effect:") then
      return nil, reason
    end
  end
  return false
end

-- AIDecidePlayLegendaryBirds::. Returns the signed score delta.
function AI:_legendaryBirdPlayScore(cardId)
  local deckId = self.memory:readSymbol8("wOpponentDeckID")
  if deckId ~= self.c.LEGENDARY_ZAPDOS_DECK_ID
      and deckId ~= self.c.LEGENDARY_ARTICUNO_DECK_ID
      and deckId ~= self.c.LEGENDARY_RONALD_DECK_ID then return 0 end

  if cardId == self.c.ARTICUNO_LV37 then
    local playCount = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    if playCount < 2 then return -100 end
    local canKO, koErr = self:checkIfAnyAttackKnocksOutDefendingCard(self.c.PLAY_AREA_ARENA)
    if canKO == nil then return nil, koErr end
    if canKO then return -100 end
    local nonResidual, nrErr = self:_canArenaUseNonResidualAttack()
    if nonResidual == nil then return nil, nrErr end
    if not nonResidual then return -100 end
    local retreat, retreatErr = self:decideWhetherToRetreat()
    if retreat == nil then return nil, retreatErr end
    if retreat then return -100 end

    local playerStatus = bit.band(self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_STATUS), self.c.CNF_SLP_PRZ)
    if playerStatus ~= 0 then return -100 end
    local _, playerId, player = self:_cardAtPlayArea(self.c.PLAY_AREA_ARENA, true)
    local first = player and player.attacks and player.attacks[1]
    if not first or first.category ~= self.c.POKEMON_POWER then
      -- Preserve source comparison against MAX_BENCH_POKEMON, not MAX_PLAY_AREA_POKEMON.
      if playCount >= self.c.MAX_BENCH_POKEMON then return 0 end
    end
    local _, muk = self.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
    if muk or playerId == self.c.SNORLAX then return -100 end
    return 70
  elseif cardId == self.c.MOLTRES_LV37 then
    return self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK) >= 56 and -100 or 0
  elseif cardId == self.c.ZAPDOS_LV68 then
    local _, muk = self.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
    return muk and -100 or 0
  end
  return 0
end

function AI:_isPrehistoricPowerActive()
  local _, aero = self.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.AERODACTYL)
  if not aero then return false end
  local _, muk = self.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
  return not muk
end

function AI:_countAttachedEnergyCards(slot)
  local count = self.duelOps:createArenaOrBenchEnergyCardList(slot)
  return count
end

function AI:_specialEvolutionScore(baseId, slot)
  local deckId = self.memory:readSymbol8("wOpponentDeckID")
  if deckId == self.c.LEGENDARY_DRAGONITE_DECK_ID then
    if baseId == self.c.CHARMELEON then
      local attached = self:_countAttachedEnergyCards(slot)
      if attached < 3 then return -10 end
      return attached + #self:_energyCardsInHand() >= 6 and 3 or -10
    elseif baseId == self.c.MAGIKARP then
      if slot ~= self.c.PLAY_AREA_ARENA and self:_countAttachedEnergyCards(slot) >= 2 then return 3 end
      return 0
    elseif baseId ~= self.c.DRAGONAIR then
      return 0
    end
  elseif deckId == self.c.INVINCIBLE_RONALD_DECK_ID then
    if baseId == self.c.GRIMER and slot ~= self.c.PLAY_AREA_ARENA then return 10 end
    return 0
  elseif deckId ~= self.c.LEGENDARY_RONALD_DECK_ID or baseId ~= self.c.DRAGONAIR then
    return 0
  end

  -- Shared Dragonair policy for Legendary Dragonite/Ronald decks.
  if baseId == self.c.DRAGONAIR then
    if slot == self.c.PLAY_AREA_ARENA then
      local damage = select(1, self:_damageAt(slot))
      if damage < 50 or self.duelOps:getPlayAreaCardAttachedEnergies(slot) < 3 then return -10 end
    else
      local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
      local totalDamage = 0
      for s = self.c.PLAY_AREA_ARENA, count - 1 do totalDamage = totalDamage + select(1, self:_damageAt(s)) end
      -- `ld a,70 / cp c / jr c` is strict: exactly 70 still lowers the score.
      if totalDamage <= 70 then return -10 end
    end
    local _, muk = self.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
    return muk and -10 or 10
  end
  return 0
end

function AI:_scoreEvolution(evolutionDeckIndex, slot)
  local currentDeckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
  local currentId = self.cardData:getCardIDFromDeckIndex(currentDeckIndex)
  local current = assert(self.cardData:get(currentId))
  local evolutionId = self.cardData:getCardIDFromDeckIndex(evolutionDeckIndex)
  local evolution = assert(self.cardData:get(evolutionId))
  local score = 0x80
  local specialDelta = self:_specialEvolutionScore(currentId, slot)
  score = specialDelta >= 0 and satAdd(score, specialDelta) or satSub(score, -specialDelta)

  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
  local currentCanAttack, attackErr = self:_canUseAnyAttackAtSlot(slot)
  if currentCanAttack == nil then return nil, attackErr end
  local currentCanKO = false
  if currentCanAttack then
    local canKO, koErr = self:checkIfAnyAttackKnocksOutDefendingCard(slot)
    if canKO == nil then return nil, koErr end
    currentCanKO = canKO
  end

  -- Source temporarily replaces only the deck index. HP remains the pre-evolution
  -- value; this intentionally preserves the documented evolution-KO scoring bug.
  self.duelVars:set(self.c.DUELVARS_ARENA_CARD + slot, evolutionDeckIndex)
  local evolvedCanAttack, evolvedErr = self:_canUseAnyAttackAtSlot(slot)
  if evolvedCanAttack == nil then
    self.duelVars:set(self.c.DUELVARS_ARENA_CARD + slot, currentDeckIndex)
    return nil, evolvedErr
  end
  if evolvedCanAttack then
    score = satAdd(score, 5)
  elseif currentCanAttack then
    score = satSub(score, 2)
    if self.memory:readSymbol8("wAlreadyPlayedEnergy") == 0 and self:_lookForAnyEnergyNeededInHand(slot) then
      score = satAdd(score, 7)
    end
  end

  if currentCanAttack and slot == self.c.PLAY_AREA_ARENA then
    local evolvedCanKO, koErr = self:checkIfAnyAttackKnocksOutDefendingCard(slot)
    if evolvedCanKO == nil then
      self.duelVars:set(self.c.DUELVARS_ARENA_CARD + slot, currentDeckIndex)
      return nil, koErr
    end
    if evolvedCanKO then score = satAdd(score, 5)
    elseif currentCanKO then score = satSub(score, 20) end
  end

  if slot == self.c.PLAY_AREA_ARENA then
    local defenderCanKO, koErr = self:checkIfDefendingPokemonCanKnockOut()
    if defenderCanKO == nil then
      self.duelVars:set(self.c.DUELVARS_ARENA_CARD + slot, currentDeckIndex)
      return nil, koErr
    end
    if defenderCanKO then score = satSub(score, 5) end
  end

  local _, defenderId = self:_cardAtPlayArea(self.c.PLAY_AREA_ARENA, true)
  if defenderId == self.c.MR_MIME then
    local canDamage, mimeErr = self:_canDamageDefendingPokemon(slot)
    if canDamage == nil then
      self.duelVars:set(self.c.DUELVARS_ARENA_CARD + slot, currentDeckIndex)
      return nil, mimeErr
    end
    if not canDamage then score = satSub(score, 20) end
  end

  self.duelVars:set(self.c.DUELVARS_ARENA_CARD + slot, currentDeckIndex)

  if slot == self.c.PLAY_AREA_ARENA then
    local defenderCanKO, koErr = self:checkIfDefendingPokemonCanKnockOut()
    if defenderCanKO == nil then return nil, koErr end
    if defenderCanKO then score = satAdd(score, 5) end
    if self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS) ~= 0 then score = satAdd(score, 4) end
  end

  if self:_hasEvolutionForCard(evolutionId, self.c.CARD_LOCATION_HAND) then score = satAdd(score, 2)
  elseif self:_hasEvolutionForCard(evolutionId, self.c.CARD_LOCATION_DECK) then score = satAdd(score, 1) end

  local damage = select(1, self:_damageAt(slot))
  score = satSub(score, math.floor(damage / 40))
  if currentId == self.c.MYSTERIOUS_FOSSIL then
    score = satAdd(score, 5)
  elseif current.aiInfo == self.c.AI_INFO_ENCOURAGE_EVO then
    -- Preserve cartridge bug: HAS_EVOLUTION is not masked before comparison.
    score = satAdd(score, 2)
  end

  if self.memory:readSymbol8("wOpponentDeckID") == self.c.PIKACHU_DECK_ID
      and (currentId == self.c.PIKACHU_LV12 or currentId == self.c.PIKACHU_LV14
        or currentId == self.c.PIKACHU_LV16 or currentId == self.c.PIKACHU_ALT_LV16) then
    score = satSub(score, 3)
  end
  self.memory:writeSymbol8("wAIScore", score)
  return score
end

-- AIDecideEvolution:: full common score path and its deck/card modifiers.
function AI:decideEvolution()
  if self:_isPrehistoricPowerActive() then return true end
  local snapshot = self:_handSnapshotForPokemonPlay()
  for _, evolutionDeckIndex in ipairs(snapshot) do
    local evolutionId = self.cardData:getCardIDFromDeckIndex(evolutionDeckIndex)
    local evolution = self.cardData:get(evolutionId)
    if evolution and evolution.kind == "pokemon" and evolution.stage ~= self.c.BASIC then
      local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
      for slot = self.c.PLAY_AREA_ARENA, count - 1 do
        if self.duelOps:checkIfCanEvolveInto(evolutionDeckIndex, slot) then
          local score, scoreErr = self:_scoreEvolution(evolutionDeckIndex, slot)
          if score == nil then return nil, scoreErr end
          if score >= 133 then
            local ok, reason = self.playerActions:evolve(evolutionId, slot)
            if not ok then return nil, reason end
            break -- source advances to the next hand card after one target succeeds
          end
        end
      end
    end
  end
  return true
end

-- AIDecidePlayPokemonCard:: full common Basic scoring, followed by evolution.
function AI:decidePlayPokemonCard()
  assert(self.playerActions, "general AI requires PlayerActions")
  local snapshot = self:_handSnapshotForPokemonPlay()
  for _, deckIndex in ipairs(snapshot) do
    local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
    local row = self.cardData:get(cardId)
    if row and row.kind == "pokemon" and row.stage == self.c.BASIC then
      local score = 130
      local birdDelta, birdErr = self:_legendaryBirdPlayScore(cardId)
      if birdDelta == nil then return nil, birdErr end
      score = birdDelta >= 0 and satAdd(score, birdDelta) or satSub(score, -birdDelta)

      local playCount = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
      score = playCount < 4 and satAdd(score, 50) or satSub(score, 20)
      local defenderCanKO, koErr = self:checkIfDefendingPokemonCanKnockOut()
      if defenderCanKO == nil then return nil, koErr end
      if defenderCanKO then score = satAdd(score, 20) end
      if self:_handHasUsefulEnergyFor(row) then score = satAdd(score, 20) end
      if self:_hasEvolutionForCard(cardId, self.c.CARD_LOCATION_HAND) then score = satAdd(score, 20) end
      if self:_hasEvolutionForCard(cardId, self.c.CARD_LOCATION_DECK) then score = satAdd(score, 10) end
      self.memory:writeSymbol8("wAIScore", score)

      if score >= 180 then
        local ok, reason = self.playerActions:playBasic(cardId)
        if not ok and reason ~= "bench_full" then return nil, reason end
        -- AIMakeDecision carry exits immediately if the duel ended via a played
        -- Pokemon trigger; translated PlayerActions reports those failures above.
      end
    end
  end
  return self:decideEvolution()
end

function AI:_energyCardsInHand()
  local out = {}
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  for i = 0, count - 1 do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_HAND + i)
    local id = self.cardData:getCardIDFromDeckIndex(deckIndex)
    local row = self.cardData:get(id)
    if row and row.type >= self.c.TYPE_ENERGY and row.type < self.c.TYPE_TRAINER then
      out[#out + 1] = { deckIndex = deckIndex, cardId = id }
    end
  end
  return out
end

-- CheckIfNoSurplusEnergyForAttack:: returns the number of Energy units beyond
-- the selected attack's printed cost.  Nil means the source routine would set
-- carry (no attack/Power, insufficient Energy, or exactly the printed cost).
function AI:_surplusEnergyForAttack(slot, attackIndex)
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
  if deckIndex == 0xff then return nil end
  local _, attack = self.combat:loadAttack(deckIndex, attackIndex)
  if attack.nameTextId == 0 or attack.category == self.c.POKEMON_POWER then return nil end
  self.duelOps:getPlayAreaCardAttachedEnergies(slot)
  if slot == self.c.PLAY_AREA_ARENA then self.combat.status:handleEnergyBurn() end
  local required = 0
  for color = 0, self.c.COLORLESS do required = required + (attack.energy[color] or 0) end
  local surplus = self.memory:readSymbol8("wTotalAttachedEnergies") - required
  if surplus <= 0 then return nil end
  return surplus
end

function AI:_estimateEnergyScoreAttack(slot, attackIndex, evolutionDeckIndex)
  local score = 0
  self.memory:writeSymbol8("wSelectedAttack", attackIndex)
  local need = self:checkEnergyNeededForAttack(slot, attackIndex)
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
  if deckIndex == 0xff then return score, nil end
  local _, attack, cardId = self.combat:loadAttack(deckIndex, attackIndex)

  if need and need.enough then
    if self:_attackFlag(attack, 2, self.c.ATTACHED_ENERGY_BOOST_F) then
      if (attack.effectParam or 0) == self.c.MAX_ENERGY_BOOST_IS_LIMITED then
        local surplus = self:_surplusEnergyForAttack(slot, attackIndex)
        if surplus == nil or surplus < 3 then score = satAdd(score, 2)
        else score = satSub(score, 5) end
      else
        -- MAX_ENERGY_BOOST_IS_NOT_LIMITED is 3 on cartridge; A is still the
        -- effect parameter when AIEncourage is called.
        score = satAdd(score, attack.effectParam or 0)
      end

      local estimate, err
      if slot == self.c.PLAY_AREA_ARENA then estimate, err = self:estimateDamageVersusDefendingCard(attackIndex)
      else estimate, err = self:_estimateDamageFromPlayArea(slot, attackIndex) end
      if not estimate then return nil, err end
      local hp = self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_HP)
      if estimate.damage < hp and estimate.damage + 10 >= hp then
        score = satAdd(score, 20)
        if slot == self.c.PLAY_AREA_ARENA then score = satAdd(score, 10) end
      end
    elseif self:_attackFlag(attack, 2, self.c.DISCARD_ENERGY_F) then
      if cardId ~= self.c.ZAPDOS_LV64 then
        local surplus = self:_surplusEnergyForAttack(slot, attackIndex)
        score = surplus == nil and satAdd(score, 2) or satSub(score, 5)
      end
    end
  else
    if self:_attackFlag(attack, 2, self.c.IGNORE_THIS_ATTACK_F) then score = satSub(score, 5) end
    if need then
      local continueNeedScoring = false
      if (need.colored or 0) > 0 and need.energyCardId and self:_findCardIDInHand(need.energyCardId) then
        score = satAdd(score, 4)
        continueNeedScoring = true
      elseif (need.colorless or 0) > 0 then
        score = satAdd(score, 3)
        continueNeedScoring = true
      end
      if continueNeedScoring then
        if (need.colored or 0) + (need.colorless or 0) == 1 then score = satAdd(score, 3) end

        -- Cartridge bug: on the Active card this KO incentive is followed by an
        -- identical Active-card check, so a KO gets +20 and then +10 again.
        if slot == self.c.PLAY_AREA_ARENA then
          local estimate, err = self:estimateDamageVersusDefendingCard(attackIndex)
          if not estimate then return nil, err end
          local hp = self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_HP)
          if estimate.damage >= hp then score = satAdd(satAdd(score, 20), 10) end
        end
      end
    end
  end

  -- wTempAI contains only an evolution found in hand.  The source temporarily
  -- swaps that deck index into the Play Area, checks the same selected attack,
  -- and then restores the original card without changing HP.
  if evolutionDeckIndex ~= nil then
    local offset = self.c.DUELVARS_ARENA_CARD + slot
    local original = self.duelVars:get(offset)
    self.duelVars:set(offset, evolutionDeckIndex)
    local evoNeed = self:checkEnergyNeededForAttack(slot, attackIndex)
    self.duelVars:set(offset, original)
    if evoNeed and not evoNeed.enough
        and not self:_attackFlag(evoNeed.attack, 2, self.c.IGNORE_THIS_ATTACK_F) then
      if (evoNeed.colored or 0) > 0 and evoNeed.energyCardId
          and self:_findCardIDInHand(evoNeed.energyCardId) then
        score = satAdd(score, 2)
      elseif (evoNeed.colorless or 0) > 0 then
        score = satAdd(score, 1)
      end
    end
  end
  return score, need
end

function AI:_opponentHasBossDeckID()
  local deckId = self.memory:readSymbol8("wOpponentDeckID")
  return deckId >= self.c.LEGENDARY_MOLTRES_DECK_ID
    and deckId < self.c.MUSCLES_FOR_BRAINS_DECK_ID
end

-- CheckIfNotABossDeckID::. Carry/true only before the Legendary Cards are
-- received and when the opponent deck is outside the boss-deck ID range.
function AI:_checkIfNotABossDeckID()
  local receivedLegendaryCards = 0
  local ok, value = pcall(function() return self.memory:readSymbol8("sReceivedLegendaryCards") end)
  if ok then receivedLegendaryCards = value end
  if receivedLegendaryCards ~= 0 then return false end
  return not self:_opponentHasBossDeckID()
end

function AI:_specialDoubleColorlessForEnergyTarget(slot)
  local deckId = self.memory:readSymbol8("wOpponentDeckID")
  local _, cardId = self:_cardAtPlayArea(slot, false)
  local applies = (deckId == self.c.LEGENDARY_DRAGONITE_DECK_ID
      and (cardId == self.c.CHARMANDER or cardId == self.c.DRATINI))
    or (deckId == self.c.FIRE_CHARGE_DECK_ID and cardId == self.c.GROWLITHE)
    or (deckId == self.c.LEGENDARY_RONALD_DECK_ID and cardId == self.c.DRATINI)
  if not applies then return nil end
  self.duelOps:getPlayAreaCardAttachedEnergies(slot)
  local base, bank = self.memory:address("wAttachedEnergies")
  if self.memory:read8("wram", base + self.c.COLORLESS, bank) ~= 0 then return nil end
  if self:_findCardIDInHand(self.c.DOUBLE_COLORLESS_ENERGY) then
    return self.c.DOUBLE_COLORLESS_ENERGY
  end
  return nil
end

function AI:_shuffledFallbackEnergy(handEnergy)
  local list, bank = self.memory:address("wDuelTempList")
  for i, entry in ipairs(handEnergy) do self.memory:write8("wram", list + i - 1, entry.deckIndex, bank) end
  self.memory:write8("wram", list + #handEnergy, 0xff, bank)
  self.rng:shuffleCards(list, #handEnergy)
  for i = 0, #handEnergy - 1 do
    local picked = self.memory:read8("wram", list + i, bank)
    local cardId = self.cardData:getCardIDFromDeckIndex(picked)
    if not (self:_opponentHasBossDeckID() and cardId == self.c.DOUBLE_COLORLESS_ENERGY) then
      return cardId
    end
  end
  return nil
end

function AI:_chooseEnergyForNeed(slot, need, handEnergy)
  local special = self:_specialDoubleColorlessForEnergyTarget(slot)
  if special then return special end
  if need and (need.colored or 0) > 0 and need.energyCardId
      and self:_findCardIDInHand(need.energyCardId) then
    return need.energyCardId
  end
  if need and (need.colorless or 0) > 0 then
    if slot == self.c.PLAY_AREA_ARENA and (need.colorless or 0) == 2
        and self:_findCardIDInHand(self.c.DOUBLE_COLORLESS_ENERGY) then
      return self.c.DOUBLE_COLORLESS_ENERGY
    end
    return self:_shuffledFallbackEnergy(handEnergy)
  end
  return nil
end

function AI:_boostOrDiscardEnergyNeed(slot, attackIndex, attack, cardId)
  if attackIndex == self.c.SECOND_ATTACK and cardId == self.c.ZAPDOS_LV64 then return false end
  if attackIndex == self.c.SECOND_ATTACK
      and (cardId == self.c.CHARIZARD or cardId == self.c.EXEGGUTOR) then
    return { colored = 0, colorless = 1 }
  end
  for color = 0, self.c.PSYCHIC do
    if (attack.energy[color] or 0) > 0 then
      return { colored = 1, colorless = 0, energyCardId = self:_energyCardIdForColor(color) }
    end
  end
  -- Source falls through to Psychic if none of the earlier colors matched.
  return { colored = 1, colorless = 0, energyCardId = self.c.PSYCHIC_ENERGY }
end

function AI:_evolutionNeedsSecondAttackEnergy(slot)
  local _, cardId = self:_cardAtPlayArea(slot, false)
  local evolutionDeckIndex
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    local location = self.duelVars:get(deckIndex)
    if location == self.c.CARD_LOCATION_HAND or location == self.c.CARD_LOCATION_DECK then
      local row = self.cardData:get(self.cardData:getCardIDFromDeckIndex(deckIndex))
      local base = self.cardData:get(cardId)
      if row and base and row.kind == "pokemon" and row.stage ~= self.c.BASIC
          and row.preEvolutionTextId == base.nameTextId then
        evolutionDeckIndex = deckIndex
        break
      end
    end
  end
  if not evolutionDeckIndex then return nil end
  local offset = self.c.DUELVARS_ARENA_CARD + slot
  local original = self.duelVars:get(offset)
  self.duelVars:set(offset, evolutionDeckIndex)
  local need = self:checkEnergyNeededForAttack(slot, self.c.SECOND_ATTACK)
  self.duelVars:set(offset, original)
  if need and not need.enough then return need end
  return nil
end

function AI:_benchSlotsWithCardId(cardId)
  local out = {}
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
    if deckIndex ~= 0xff and self.cardData:getCardIDFromDeckIndex(deckIndex) == cardId then
      out[#out + 1] = slot
    end
  end
  return out
end

function AI:_benchIdAtHalfHPAndCanUseSecondAttack(cardId)
  for _, slot in ipairs(self:_benchSlotsWithCardId(cardId)) do
    local _, _, row = self:_cardAtPlayArea(slot, false)
    local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
    if row and hp > math.floor((row.hp or 0) / 2) then
      local usable, err = self:_isAttackUsableAtSlot(slot, self.c.SECOND_ATTACK)
      if usable == nil then return nil, err end
      if usable then return true end
    end
  end
  return false
end

function AI:_legendaryArticunoEnergyDeltas(count)
  local out = {}
  for slot = 0, count - 1 do out[slot] = 0 end
  if self.memory:readSymbol8("wOpponentDeckID") ~= self.c.LEGENDARY_ARTICUNO_DECK_ID then return out end

  self.duelVars:swapTurn()
  local playerPrizes = self.duelOps:countPrizes()
  self.duelVars:swapTurn()
  if playerPrizes < 3 then return out end

  local laprasReady, err = self:_benchIdAtHalfHPAndCanUseSecondAttack(self.c.LAPRAS)
  if laprasReady == nil then return nil, err end
  local target = self.c.ARTICUNO_LV35
  if not laprasReady then
    local articunoReady, err2 = self:_benchIdAtHalfHPAndCanUseSecondAttack(self.c.ARTICUNO_LV35)
    if articunoReady == nil then return nil, err2 end
    local dewgongReady, err3 = self:_benchIdAtHalfHPAndCanUseSecondAttack(self.c.DEWGONG)
    if dewgongReady == nil then return nil, err3 end
    if articunoReady or dewgongReady then target = self.c.LAPRAS end
  end

  local function raiseAll(cardId)
    local slots = self:_benchSlotsWithCardId(cardId)
    if #slots == 0 then return false end
    for _, slot in ipairs(slots) do out[slot] = (out[slot] or 0) + 5 end
    return true
  end

  if target == self.c.LAPRAS then
    local lapras = self:_benchSlotsWithCardId(self.c.LAPRAS)
    if #lapras > 0 then
      -- LookForCardIDInPlayArea_Bank5 returns the first matching Bench slot;
      -- only that Lapras is checked against the three-card attachment cap.
      if self:_countAttachedEnergyCards(lapras[1]) < 3 then
        raiseAll(self.c.LAPRAS)
        return out
      end
    end
  end
  if raiseAll(self.c.ARTICUNO_LV35) then return out end
  if raiseAll(self.c.DEWGONG) then return out end
  raiseAll(self.c.SEEL)
  return out
end

function AI:_shouldScoreRepeatedBenchEnergy()
  local receivedLegendaryCards = 0
  local ok, value = pcall(function() return self.memory:readSymbol8("sReceivedLegendaryCards") end)
  if ok then receivedLegendaryCards = value end
  if receivedLegendaryCards ~= 0 then return true end
  return self:_opponentHasBossDeckID()
end

function AI:_repeatedBenchEnergyDeltas(count)
  local out = {}
  for slot = 0, count - 1 do out[slot] = 0 end
  if not self:_shouldScoreRepeatedBenchEnergy() then return out end

  local groups = {}
  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
    if deckIndex ~= 0xff then
      local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
      local group = groups[cardId] or {}
      group[#group + 1] = slot
      groups[cardId] = group
    end
  end

  for _, slots in pairs(groups) do
    if #slots >= 2 then
      local bestSlot, bestMetric
      -- Source scans Bench 5 -> Bench 1 and updates on equality, so the lower
      -- Play Area location wins ties.
      for i = #slots, 1, -1 do
        local slot = slots[i]
        local damage = select(1, self:_damageAt(slot))
        local metric = 0x80 + self:_countAttachedEnergyCards(slot) * 2 - math.floor(damage / 10)
        if bestMetric == nil or metric >= bestMetric then
          bestMetric, bestSlot = metric, slot
        end
      end
      for _, slot in ipairs(slots) do
        out[slot] = (out[slot] or 0) + (slot == bestSlot and 1 or -1)
      end
    end
  end
  return out
end


-- AITryToPlayEnergyCard (choose step):: source ordering for choosing the
-- actual Energy card after the target Play Area slot has already won the
-- score comparison.
function AI:_chooseEnergyCardForSlot(slot, handEnergy)
  for attackIndex = self.c.FIRST_ATTACK_OR_PKMN_POWER, self.c.SECOND_ATTACK do
    self.memory:writeSymbol8("wSelectedAttack", attackIndex)
    local need = self:checkEnergyNeededForAttack(slot, attackIndex)
    if need and not need.enough and ((need.colored or 0) > 0 or (need.colorless or 0) > 0) then
      local chosen = self:_chooseEnergyForNeed(slot, need, handEnergy)
      if chosen then return chosen end
    end
  end

  for attackIndex = self.c.FIRST_ATTACK_OR_PKMN_POWER, self.c.SECOND_ATTACK do
    self.memory:writeSymbol8("wSelectedAttack", attackIndex)
    local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
    local _, attack, cardId = self.combat:loadAttack(deckIndex, attackIndex)
    if self:_attackFlag(attack, 2, self.c.ATTACHED_ENERGY_BOOST_F)
        or self:_attackFlag(attack, 2, self.c.DISCARD_ENERGY_F) then
      local need = self:_boostOrDiscardEnergyNeed(slot, attackIndex, attack, cardId)
      if need == false then return nil end -- Zapdos Lv64 Thunderbolt exits immediately.
      return self:_chooseEnergyForNeed(slot, need, handEnergy)
    end
  end

  local evolutionNeed = self:_evolutionNeedsSecondAttackEnergy(slot)
  if evolutionNeed then return self:_chooseEnergyForNeed(slot, evolutionNeed, handEnergy) end
  return nil
end

-- AITryToPlayEnergyCard:: choose and attach an Energy card for an
-- already-decided target Play Area slot, skipping the score comparison
-- across all slots that AIProcessAndTryToPlayEnergy does. Returns true on a
-- successful attach, false if no Energy card could be chosen for the slot
-- (source's "return carry": nothing attached).
function AI:_tryToPlayEnergyCard(slot, handEnergy)
  local cardId = self:_chooseEnergyCardForSlot(slot, handEnergy)
  if cardId == nil then return false end
  local ok, reason = self.playerActions:attachEnergy(cardId, slot)
  if not ok then return nil, reason end
  return true
end

-- AIProcessAndTryToPlayEnergy / AIProcessEnergyCards:: common scoring path.
function AI:processAndTryToPlayEnergy()
  assert(self.playerActions, "general AI requires PlayerActions")
  if self.memory:readSymbol8("wAlreadyPlayedEnergy") ~= 0 then return false end
  local handEnergy = self:_energyCardsInHand()
  if #handEnergy == 0 then return false end
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local bestSlot, bestScore = nil, -1
  local energyBonus = self:_deckAIList("energyBonus")
  local articunoDeltas, articunoErr = self:_legendaryArticunoEnergyDeltas(count)
  if articunoDeltas == nil then return nil, articunoErr end
  local repeatedDeltas = self:_repeatedBenchEnergyDeltas(count)
  for slot = 0, count - 1 do
    local score = 0x80
    local _, cardId, row = self:_cardAtPlayArea(slot, false)
    local evolutionDeckIndex

    -- Normal mode does the source's early energy-color gate before any other
    -- slot scoring.  If no Energy in hand matches either attack's cost, this
    -- slot is stored at the baseline $80 and processing jumps to the next slot.
    if not row or not self:_handHasUsefulEnergyFor(row) then
      if score > bestScore then bestSlot, bestScore = slot, score end
      goto continue_energy_slot
    end
    local inHand, handEvolution = self:_hasEvolutionForCard(cardId, self.c.CARD_LOCATION_HAND)
    if inHand then
      evolutionDeckIndex = handEvolution
      score = satAdd(score, 2)
    elseif self:_hasEvolutionForCard(cardId, self.c.CARD_LOCATION_DECK) then
      score = satAdd(score, 1)
    end

    local _, muk = self.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
    if not muk then
      local _, venusaur = self.combat.status:countTurnDuelistPokemonWithActivePkmnPower(self.c.VENUSAUR_LV67)
      if venusaur then score = satAdd(score, 1) end
    end

    if slot == self.c.PLAY_AREA_ARENA then
      local counter = self.memory:readSymbol8("wAIBarrierFlagCounter")
      if self.c.AI_MEWTWO_MILL_F and hasFlag(counter, self.c.AI_MEWTWO_MILL_F) then
        score = satSub(score, 5)
      else
        score = satAdd(score, 4)
      end

      local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP)
      local hpCounters = math.floor(hp / 10)
      local status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
      local atRisk = false
      -- Preserve the cartridge's mask behavior: DOUBLE_POISONED is used as a
      -- bit mask at 20 HP, so ordinary Poison also satisfies this test.
      if hpCounters < 3 then
        if hpCounters == 2 then atRisk = bit.band(status, self.c.DOUBLE_POISONED) ~= 0
        elseif hpCounters <= 1 then atRisk = bit.band(status, self.c.POISONED) ~= 0 end
      end
      if not atRisk then
        local exactKO, koErr = self:_defenderCanExactKOPlayArea(slot)
        if exactKO == nil then return nil, koErr end
        atRisk = exactKO
      end
      if atRisk then
        score = satSub(score, 10)
        if count == 1 then score = satAdd(score, 6) end
      end
    else
      local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
      local hpCounters = math.floor(hp / 10)
      if hpCounters < 3 then score = satSub(score, 3 - hpCounters) end
    end

    local stopScoring = false
    if energyBonus then
      for _, entry in ipairs(energyBonus.entries) do
        if entry.cardId == cardId then
          local attached = self.duelOps:getPlayAreaCardAttachedEnergies(slot)
          if attached >= entry.maxEnergy then
            -- Source bug/quirk: reaching the list cap subtracts 10 and jumps
            -- directly to .store_score, skipping boss and attack score terms.
            score = satSub(score, 10)
            stopScoring = true
          elseif entry.delta >= 0 then
            score = satAdd(score, entry.delta)
          else
            score = satSub(score, -entry.delta)
          end
          break
        end
      end
    end

    if not stopScoring then
      local listDelta = (articunoDeltas[slot] or 0) + (repeatedDeltas[slot] or 0)
      if listDelta >= 0 then score = satAdd(score, listDelta)
      else score = satSub(score, -listDelta) end
      score = satAdd(score, 1)
      for attackIndex = self.c.FIRST_ATTACK_OR_PKMN_POWER, self.c.SECOND_ATTACK do
        local delta, err = self:_estimateEnergyScoreAttack(slot, attackIndex, evolutionDeckIndex)
        if delta == nil then return nil, err end
        if delta >= 0 then score = satAdd(score, delta) else score = satSub(score, -delta) end
      end
    end

    if score > bestScore then bestSlot, bestScore = slot, score end
    ::continue_energy_slot::
  end
  if bestSlot == nil or bestScore < 0x85 then return false end
  return self:_tryToPlayEnergyCard(bestSlot, handEnergy)
end


function AI:_damageAt(slot)
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
  if deckIndex == 0xff then return 0, 0 end
  local row = assert(self.cardData:get(self.cardData:getCardIDFromDeckIndex(deckIndex)))
  local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
  return row.hp - hp, row.hp
end

function AI:_setPreviousAIFlag(mask)
  if not mask then return end
  self.memory:writeSymbol8("wPreviousAIFlags",
    bit.bor(self.memory:readSymbol8("wPreviousAIFlags"), mask))
end

function AI:_firstBasicEnergyInDeck(preferredId)
  local fallback
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    if self.duelVars:get(deckIndex) == self.c.CARD_LOCATION_DECK then
      local id = self.cardData:getCardIDFromDeckIndex(deckIndex)
      local row = self.cardData:get(id)
      if row and row.type >= self.c.TYPE_ENERGY and row.type < self.c.TYPE_ENERGY_DOUBLE_COLORLESS then
        if id == preferredId then return deckIndex end
        fallback = fallback or deckIndex
      end
    end
  end
  return fallback
end

function AI:_pickAttachedEnergyToRemove(slot, nonTurn)
  if nonTurn then self.duelVars:swapTurn() end
  local count = self.duelOps:createArenaOrBenchEnergyCardList(slot)
  local _, activeId, active = self:_cardAtPlayArea(slot, false)
  local base, bank = self.memory:address("wDuelTempList")
  local first, useful
  for i = 0, count - 1 do
    local deckIndex = self.memory:read8("wram", base + i, bank)
    first = first or deckIndex
    local id = self.cardData:getCardIDFromDeckIndex(deckIndex)
    if id == self.c.DOUBLE_COLORLESS_ENERGY then
      if nonTurn then self.duelVars:swapTurn() end
      return deckIndex
    end
    if not useful and self:_energyIsUsefulForRetreat(deckIndex, activeId, active.type) then useful = deckIndex end
  end
  if nonTurn then self.duelVars:swapTurn() end
  return useful or first
end

function AI:_bestAttackChoice()
  local first, err = self:getAIScoreOfAttack(self.c.FIRST_ATTACK_OR_PKMN_POWER)
  if first == nil then return nil, err end
  local second, err2 = self:getAIScoreOfAttack(self.c.SECOND_ATTACK)
  if second == nil then return nil, err2 end
  local selected, score = self.c.SECOND_ATTACK, second
  if first > second then selected, score = self.c.FIRST_ATTACK_OR_PKMN_POWER, first end
  local switched, switchErr = self:checkWhetherToSwitchToFirstAttack(first, selected)
  if switched == nil then return nil, switchErr end
  return switched, score
end

-- CheckIfOpponentHasBossDeckID / CheckIfNotABossDeckID /
-- AIChooseRandomlyNotToDoAction:: The cartridge suppresses this random skip
-- after the player has received the Legendary Cards, and never applies it to
-- the Grandmaster/Club Master/Ronald boss-deck ID range.  Fresh SRAM is zeroed
-- on hardware; sparse SRAM in the translated runtime therefore treats an
-- uninitialized progress byte as zero here.
function AI:_chooseRandomlyNotToDoAction()
  local receivedLegendaryCards = 0
  local ok, value = pcall(function() return self.memory:readSymbol8("sReceivedLegendaryCards") end)
  if ok then receivedLegendaryCards = value end
  if receivedLegendaryCards ~= 0 then return false end

  local deckId = self.memory:readSymbol8("wOpponentDeckID")
  if deckId >= self.c.LEGENDARY_MOLTRES_DECK_ID
      and deckId < self.c.MUSCLES_FOR_BRAINS_DECK_ID then
    return false
  end

  local fiftyPercent = {
    [self.c.MUSCLES_FOR_BRAINS_DECK_ID] = true,
    [self.c.BLISTERING_POKEMON_DECK_ID] = true,
    [self.c.WATERFRONT_POKEMON_DECK_ID] = true,
    [self.c.BOOM_BOOM_SELFDESTRUCT_DECK_ID] = true,
    [self.c.KALEIDOSCOPE_DECK_ID] = true,
    [self.c.RESHUFFLE_DECK_ID] = true,
  }
  local roll = self.rng:random(4)
  return roll < (fiftyPercent[deckId] and 2 or 1)
end

function AI:_cardListWithout(list, unwanted)
  local out, removed = {}, false
  for _, deckIndex in ipairs(list) do
    if not removed and deckIndex == unwanted then
      removed = true
    else
      out[#out + 1] = deckIndex
    end
  end
  return out
end

-- FindDuplicateCards:: Prefer a Pokemon duplicate over an Energy/Trainer
-- duplicate and preserve the source's "later matching deck index" result.
function AI:_findDuplicateCard(list)
  local pokemonDuplicate, nonPokemonDuplicate
  for i = 1, #list do
    local id = self.cardData:getCardIDFromDeckIndex(list[i])
    for j = i + 1, #list do
      if self.cardData:getCardIDFromDeckIndex(list[j]) == id then
        local row = assert(self.cardData:get(id))
        if row.type < self.c.TYPE_ENERGY then pokemonDuplicate = list[j]
        else nonPokemonDuplicate = list[j] end
        break
      end
    end
  end
  return pokemonDuplicate or nonPokemonDuplicate
end

function AI:_firstDeckIndexWithCardID(list, cardId)
  for _, deckIndex in ipairs(list) do
    if self.cardData:getCardIDFromDeckIndex(deckIndex) == cardId then return deckIndex end
  end
  return nil
end

-- AIDecide_Pokedex / PickPokedexCards:: 30% use chance once the six-turn
-- counter matures.  Preserve the source ordering bug/behavior: Energy first,
-- then Pokemon, then Trainers, with relative order retained inside each class.
function AI:_decidePokedex()
  if self.memory:readSymbol8("wAIPokedexCounter") < 6 then return false end
  local gone = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)
  if gone >= self.c.DECK_SIZE - 4 then return false end
  if self.rng:random(10) >= 3 then return false end

  local energy, pokemon, trainer = {}, {}, {}
  for i = 0, 4 do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_DECK_CARDS + gone + i)
    local row = assert(self.cardData:get(self.cardData:getCardIDFromDeckIndex(deckIndex)))
    if row.type >= self.c.TYPE_ENERGY and row.type < self.c.TYPE_TRAINER then
      energy[#energy + 1] = deckIndex
    elseif row.type < self.c.TYPE_ENERGY then
      pokemon[#pokemon + 1] = deckIndex
    else
      trainer[#trainer + 1] = deckIndex
    end
  end
  local order = {}
  for _, group in ipairs({energy, pokemon, trainer}) do
    for _, deckIndex in ipairs(group) do order[#order + 1] = deckIndex end
  end
  self.memory:writeSymbol8("wAIPokedexCounter", 0)
  return true, { topDeckOrder = order }
end

function AI:_decideRecycle()
  local discard, empty = self.duelOps:createDiscardPileCardList()
  if empty then return false end
  local deckId = self.memory:readSymbol8("wOpponentDeckID")
  local priorities
  if deckId == self.c.GHOST_DECK_ID then
    priorities = { self.c.GASTLY_LV17, self.c.GASTLY_LV8, self.c.ZUBAT,
      self.c.DITTO, self.c.MEOWTH_LV15 }
  else
    priorities = { self.c.DOUBLE_COLORLESS_ENERGY, self.c.CHANSEY,
      self.c.TAUROS, self.c.JIGGLYPUFF_LV12 }
  end
  for _, cardId in ipairs(priorities) do
    local deckIndex = self:_firstDeckIndexWithCardID(discard, cardId)
    if deckIndex then return true, { discardCard = deckIndex } end
  end
  return false
end

function AI:_decideRevive()
  local discard, empty = self.duelOps:createDiscardPileCardList()
  if empty then return false end
  if self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) >= 4 then return false end
  -- Preserve the source branch bug: Kangaskhan is unreachable; Tauros is used.
  local wanted = {
    [self.c.HITMONCHAN] = true,
    [self.c.HITMONLEE] = true,
    [self.c.TAUROS] = true,
  }
  for _, deckIndex in ipairs(discard) do
    if wanted[self.cardData:getCardIDFromDeckIndex(deckIndex)] then
      return true, { discardBasicPokemon = deckIndex }
    end
  end
  return false
end

function AI:_decidePokemonFlute()
  self.duelVars:swapTurn()
  local discard, empty = self.duelOps:createDiscardPileCardList()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  self.duelVars:swapTurn()
  if empty or count >= self.c.MAX_PLAY_AREA_POKEMON then return false end

  local deckId = self.memory:readSymbol8("wOpponentDeckID")
  if deckId == self.c.IMAKUNI_DECK_ID and self.rng:random(10) >= 2 then return false end
  local selected, lowestHP
  for _, deckIndex in ipairs(discard) do
    local row = assert(self.cardData:get(self.cardData:getCardIDFromDeckIndex(deckIndex)))
    if row.type < self.c.TYPE_ENERGY and row.stage == self.c.BASIC then
      if deckId == self.c.IMAKUNI_DECK_ID then
        return true, { opponentDiscardBasicPokemon = deckIndex }
      end
      if lowestHP == nil or row.hp < lowestHP then selected, lowestHP = deckIndex, row.hp end
    end
  end
  if selected and lowestHP < 50 then
    return true, { opponentDiscardBasicPokemon = selected }
  end
  return false
end

function AI:_decideMaintenance(currentTrainerDeckIndex)
  local hand = self.duelOps:createHandCardList()
  local deckId = self.memory:readSymbol8("wOpponentDeckID")
  if deckId == self.c.IMAKUNI_DECK_ID then
    if self.rng:random(10) >= 2 then return false end
    if self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND) < 3 then return false end
    local base = self.memory:address("wDuelTempList")
    self.rng:shuffleCards(base, #hand)
    hand = {}
    local _, bank = self.memory:address("wDuelTempList")
    for i = 0, self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND) - 1 do
      local deckIndex = self.memory:read8("wram", base + i, bank)
      if deckIndex == 0xff then break end
      if deckIndex ~= currentTrainerDeckIndex then hand[#hand + 1] = deckIndex end
      if #hand == 2 then return true, { handDiscards = hand } end
    end
    return false
  end

  if self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND) < 4 then return false end
  hand = self:_cardListWithout(hand, currentTrainerDeckIndex)
  local first = self:_findDuplicateCard(hand)
  if not first then return false end
  hand = self:_cardListWithout(hand, first)
  local second = self:_findDuplicateCard(hand)
  if not second then return false end
  return true, { handDiscards = { first, second } }
end

function AI:_decideItemFinder(currentTrainerDeckIndex)
  local discard, empty = self.duelOps:createDiscardPileCardList()
  if empty then return false end
  local energyRemoval = self:_firstDeckIndexWithCardID(discard, self.c.ENERGY_REMOVAL)
  if not energyRemoval then return false end

  local hand = self.duelOps:createHandCardList()
  local filtered = {}
  for _, deckIndex in ipairs(hand) do
    local id = self.cardData:getCardIDFromDeckIndex(deckIndex)
    if deckIndex ~= currentTrainerDeckIndex and id ~= self.c.MR_MIME and id ~= self.c.POKEMON_TRADER then
      filtered[#filtered + 1] = deckIndex
    end
  end
  local first = self:_findDuplicateCard(filtered)
  if not first then return false end
  filtered = self:_cardListWithout(filtered, first)
  local second = self:_findDuplicateCard(filtered)
  if not second then return false end
  return true, { handDiscards = { first, second }, discardTrainer = energyRemoval }
end

function AI:_decidePokemonCenter()
  local canKO, attackIndex = self:checkIfAnyAttackKnocksOutDefendingCard(self.c.PLAY_AREA_ARENA)
  if canKO == nil then return nil, attackIndex end
  if canKO then
    local usable, reason = self:_checkAttackUsableForAI(attackIndex)
    if usable then return false end
    if reason and reason:match("^untranslated_effect:") then return nil, reason end
    if self:_lookForEnergyNeededInHand(self.c.PLAY_AREA_ARENA, attackIndex) then return false end
  end

  local hpCounters, damageCounters, attachedEnergy = 0, 0, 0
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for slot = self.c.PLAY_AREA_ARENA, count - 1 do
    local damage, maxHP = self:_damageAt(slot)
    hpCounters = hpCounters + math.floor(maxHP / 10)
    damageCounters = damageCounters + math.floor(damage / 10)
    attachedEnergy = attachedEnergy + self.duelOps:getPlayAreaCardAttachedEnergies(slot)
  end
  if math.floor(damageCounters / 2) < attachedEnergy then return false end
  if math.floor(hpCounters * 6 / 10) >= damageCounters then return false end
  return true
end

function AI:_decideMrFuji()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if count <= 1 then return false end
  local selected, bestRatio
  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local damage, maxHP = self:_damageAt(slot)
    local counters = math.floor(damage / 10)
    if counters > 0 then
      local ratio = math.floor(maxHP / counters)
      if ratio < 20 and (bestRatio == nil or ratio < bestRatio) then
        selected, bestRatio = slot, ratio
      end
    end
  end
  if selected == nil then return false end
  return true, { bench = selected }
end

-- CalculateFitness (AIDecide_PokemonBreeder, trainer_cards.asm): 4 high bits
-- of the returned byte are the candidate's remaining HP counters (via the
-- source's `swap a` on floor(HP/10), replicated bit-for-bit including its
-- unclamped overflow if HP counters ever exceed 15), 4 low bits are its
-- attached-energy-card count capped at 15.
function AI:_breederFitnessScore(slot)
  local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
  local hpCounters = bit.band(math.floor(hp / 10), 0xff)
  local swapped = bit.bor(bit.lshift(bit.band(hpCounters, 0x0f), 4), bit.rshift(hpCounters, 4))
  local energyCount = self.duelOps:getPlayAreaCardAttachedEnergies(slot)
  if energyCount > 15 then energyCount = 15 end
  return bit.bor(swapped, energyCount)
end

-- HandleDragoniteLv41Evolution (AIDecide_PokemonBreeder, trainer_cards.asm):
-- gates evolving into Dragonite Lv41 specifically -- bench candidates are
-- blocked unless the WHOLE play area already carries >=8 damage counters;
-- the Active candidate is blocked unless it individually has >=5 raw damage
-- AND >=3 energy cards attached. Every other evolution target is unaffected.
function AI:_dragoniteLv41Blocks(evolutionCardId, slot)
  if evolutionCardId ~= self.c.DRAGONITE_LV41 then return false end
  if slot == self.c.PLAY_AREA_ARENA then
    local damage = select(1, self:_damageAt(slot))
    if damage < 5 then return true end
    return self.duelOps:countNumberOfEnergyCardsAttached(slot) < 3
  end
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local totalCounters = 0
  for s = self.c.PLAY_AREA_ARENA, count - 1 do
    local damage = select(1, self:_damageAt(s))
    totalCounters = totalCounters + math.floor(damage / 10)
  end
  return totalCounters < 8
end

-- AIDecide_PokemonBreeder (trainer_cards.asm). Two passes: first, only the
-- hardcoded priority Stage2 set (Venusaur/Blastoise/Vileplume/Alakazam/Gengar)
-- against any compatible Basic, picking the highest-fitness Play Area slot
-- with no minimum-energy requirement; if none of those fit anywhere, fall
-- back to any Stage2 card in hand (subject to the Dragonite Lv41 gate above)
-- but only accept a candidate slot with >=2 Energy already attached. Per the
-- source's storage-then-scan structure, ties keep the first (lowest-index)
-- slot rather than the latest.
function AI:_decidePokemonBreeder()
  if self:_isPrehistoricPowerActive() then return false end

  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local hand = self.duelOps:createHandCardList()

  local forcedIds = {
    [self.c.VENUSAUR_LV64] = true, [self.c.VENUSAUR_LV67] = true,
    [self.c.BLASTOISE] = true, [self.c.VILEPLUME] = true,
    [self.c.ALAKAZAM] = true, [self.c.GENGAR] = true,
  }

  local score, stage2ForSlot, found = {}, {}, 0
  for _, deckIndex in ipairs(hand) do
    local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
    if forcedIds[cardId] then
      for slot = self.c.PLAY_AREA_ARENA, count - 1 do
        if self.duelOps:checkIfCanEvolveIntoBasicToStage2(deckIndex, slot) then
          score[slot] = self:_breederFitnessScore(slot)
          stage2ForSlot[slot] = deckIndex
          found = found + 1
        end
      end
    end
  end

  if found > 0 then
    local bestSlot, bestScore
    for slot = self.c.PLAY_AREA_ARENA, count - 1 do
      local s = score[slot] or 0
      if bestScore == nil or s > bestScore then bestScore, bestSlot = s, slot end
    end
    return true, { playArea = bestSlot, handStage2Pokemon = stage2ForSlot[bestSlot] }
  end

  score, stage2ForSlot = {}, {}
  local foundAny = false
  for _, deckIndex in ipairs(hand) do
    local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
    local row = self.cardData:get(cardId)
    if row and row.type < self.c.TYPE_ENERGY and row.stage == self.c.STAGE2 then
      for slot = self.c.PLAY_AREA_ARENA, count - 1 do
        if self.duelOps:checkIfCanEvolveIntoBasicToStage2(deckIndex, slot)
            and not self:_dragoniteLv41Blocks(cardId, slot) then
          score[slot] = self:_breederFitnessScore(slot)
          stage2ForSlot[slot] = deckIndex
          foundAny = true
        end
      end
    end
  end
  if not foundAny then return false end

  local bestSlot, bestScore
  for slot = self.c.PLAY_AREA_ARENA, count - 1 do
    local s = score[slot]
    if s ~= nil and bit.band(s, 0x0f) >= 2 and (bestScore == nil or s > bestScore) then
      bestScore, bestSlot = s, slot
    end
  end
  if bestSlot == nil then return false end
  return true, { playArea = bestSlot, handStage2Pokemon = stage2ForSlot[bestSlot] }
end

-- AIDecide_ImposterProfessorOak:: both counts are read from the NON-turn
-- duelist (the human opponent), since this card shuffles their hand back
-- into their deck and redraws it, not the AI's own.
function AI:_decideImposterProfessorOak()
  local notInDeck = self.duelVars:getNonTurn(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)
  local handCount = self.duelVars:getNonTurn(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  if notInDeck < self.c.DECK_SIZE - 14 then
    return handCount >= 9
  end
  return handCount < 6
end

-- .decide_switch shared tail from AIDecide_ScoopUp: scoop the Arena card,
-- replacing it from the Bench via the common switch-target scorer.
function AI:_decideScoopUpArenaSwitch()
  local slot, reason = self:decideBenchPokemonToSwitchTo()
  if not slot then return false, reason end
  return true, { playArea = self.c.PLAY_AREA_ARENA, replacement = slot }
end

-- .check_attached_energy / .no_energy shared tail from AIDecide_ScoopUp's
-- LegendaryArticuno/LegendaryRonald handlers: scoop a found Bench card only
-- if it has no Energy attached (stripping a card that has Energy invested
-- in it is never worth it for these decks). No replacement Bench slot is
-- needed -- the Arena stays as-is.
function AI:_scoopBenchSlotIfNoEnergy(slot)
  if self.duelOps:countNumberOfEnergyCardsAttached(slot) ~= 0 then return false end
  return true, { playArea = slot }
end

-- AIDecide_ScoopUp:: general path. Scoops the Active card exactly when it
-- can neither attack for lethal nor retreat away from danger AND it has
-- already taken at least 70% of its max HP in damage -- otherwise ordinary
-- attacking/retreating is preferred over spending the Trainer card.
function AI:_decideScoopUp()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if count < 2 then return false end

  local deckId = self.memory:readSymbol8("wOpponentDeckID")
  if deckId == self.c.LEGENDARY_ARTICUNO_DECK_ID then return self:_decideScoopUpLegendaryArticuno() end
  if deckId == self.c.LEGENDARY_RONALD_DECK_ID then return self:_decideScoopUpLegendaryRonald() end

  local canKO, attackIndex = self:checkIfAnyAttackKnocksOutDefendingCard(self.c.PLAY_AREA_ARENA)
  if canKO == nil then return nil, attackIndex end
  if canKO then
    local usable, reason = self:_checkAttackUsableForAI(attackIndex)
    if usable then return false end
    if reason and reason:match("^untranslated_effect:") then return nil, reason end
    if self:_lookForEnergyNeededInHand(self.c.PLAY_AREA_ARENA, attackIndex) then return false end
  end

  local status = bit.band(self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS), self.c.CNF_SLP_PRZ)
  if status ~= self.c.PARALYZED and status ~= self.c.ASLEEP then
    local retreatCost = self:getPlayAreaCardRetreatCost(self.c.PLAY_AREA_ARENA)
    local energyCards = self.duelOps:countNumberOfEnergyCardsAttached(self.c.PLAY_AREA_ARENA)
    if energyCards >= retreatCost then return false end
  end

  local damage, maxHP = self:_damageAt(self.c.PLAY_AREA_ARENA)
  if damage == 0 then return false end
  local maxHPCounters = math.floor(maxHP / 10)
  if math.floor(damage / maxHPCounters) < 7 then return false end

  return self:_decideScoopUpArenaSwitch()
end

-- AIDecide_ScoopUp's .HandleLegendaryArticuno: will use Scoop Up on a
-- benched ArticunoLv37 (skipping this if the Player's Active is Snorlax --
-- source comment notes it interestingly does not check for Muk in play
-- here), or on an Arena ArticunoLv37/Chansey if it will be KO'd by the
-- Player and the AI itself has no lethal this turn.
function AI:_decideScoopUpLegendaryArticuno()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if count < 3 then return false end

  local benchSlot = self:_findCardIDInPlayArea(self.c.ARTICUNO_LV37, self.c.PLAY_AREA_BENCH_1)
  if benchSlot ~= 0xff then
    local playerArenaIndex = self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD)
    self.duelVars:swapTurn()
    local playerArenaId = self.cardData:getCardIDFromDeckIndex(playerArenaIndex)
    self.duelVars:swapTurn()
    if playerArenaId == self.c.SNORLAX then return false end
    return self:_scoopBenchSlotIfNoEnergy(benchSlot)
  end

  local arenaIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local arenaId = self.cardData:getCardIDFromDeckIndex(arenaIndex)
  if arenaId ~= self.c.ARTICUNO_LV37 and arenaId ~= self.c.CHANSEY then return false end

  local canKO, attackIndex = self:checkIfAnyAttackKnocksOutDefendingCard(self.c.PLAY_AREA_ARENA)
  if canKO == nil then return nil, attackIndex end
  local threatened = true
  if canKO then
    local usable, reason = self:_checkAttackUsableForAI(attackIndex)
    if usable then
      threatened = false
    elseif reason and reason:match("^untranslated_effect:") then
      return nil, reason
    elseif self:_lookForEnergyNeededInHand(self.c.PLAY_AREA_ARENA, attackIndex) then
      threatened = false
    end
  end
  if threatened then
    local playerCanKO, koErr = self:checkIfDefendingPokemonCanKnockOut()
    if playerCanKO == nil then return nil, koErr end
    threatened = playerCanKO
  end
  if not threatened then return false end
  return self:_decideScoopUpArenaSwitch()
end

-- AIDecide_ScoopUp's .HandleLegendaryRonald: will use Scoop Up on a benched
-- ArticunoLv37, ZapdosLv68, or MoltresLv37 -- source comment notes it
-- interestingly does not check for Muk in either Play Area. Unlike
-- Articuno's own handler, this one has no Arena-card branch at all.
function AI:_decideScoopUpLegendaryRonald()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if count < 3 then return false end

  local articunoSlot = self:_findCardIDInPlayArea(self.c.ARTICUNO_LV37, self.c.PLAY_AREA_BENCH_1)
  if articunoSlot ~= 0xff then
    local playerArenaIndex = self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD)
    self.duelVars:swapTurn()
    local playerArenaId = self.cardData:getCardIDFromDeckIndex(playerArenaIndex)
    self.duelVars:swapTurn()
    if playerArenaId == self.c.SNORLAX then return false end
    return self:_scoopBenchSlotIfNoEnergy(articunoSlot)
  end

  local zapdosSlot = self:_findCardIDInPlayArea(self.c.ZAPDOS_LV68, self.c.PLAY_AREA_BENCH_1)
  if zapdosSlot ~= 0xff then return self:_scoopBenchSlotIfNoEnergy(zapdosSlot) end

  local moltresSlot = self:_findCardIDInPlayArea(self.c.MOLTRES_LV37, self.c.PLAY_AREA_BENCH_1)
  if moltresSlot ~= 0xff then return self:_scoopBenchSlotIfNoEnergy(moltresSlot) end

  return false
end

-- AIDecide_Lass:: only worth using against a well-stocked opponent hand
-- (>=7 cards), and only when the AI's OWN hand holds no other Trainer card
-- (by card ID, not hand position -- other copies of Lass itself don't
-- count), since Lass shuffles both duelists' remaining Trainer cards back
-- into their own deck and the AI doesn't want to give up its own.
function AI:_decideLass()
  local oppHandCount = self.duelVars:getNonTurn(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  if oppHandCount < 7 then return false end

  local hand = self.duelOps:createHandCardList()
  for _, deckIndex in ipairs(hand) do
    local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
    if cardId ~= self.c.LASS then
      local row = self.cardData:get(cardId)
      if row and row.type == self.c.TYPE_TRAINER then
        return false
      end
    end
  end
  return true
end

-- AIDecide_Imakuni:: plays whenever the Active isn't already Confused --
-- the card's own AI makes no attempt to avoid the self-inflicted downside.
function AI:_decideImakuni()
  local status = bit.band(self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS), self.c.CNF_SLP_PRZ)
  return status ~= self.c.CONFUSED
end

-- AIDecide_Gambler:: Imakuni?'s deck has its own 2-in-10 roll (matching the
-- same idiom used elsewhere, e.g. _decidePokemonFlute/_decideMaintenance).
-- Every other deck only plays it once wAIBarrierFlagCounter's AI_MEWTWO_MILL
-- bit is raised by the Mewtwo Lv53 mill detector (not yet implemented
-- elsewhere in this file) -- until that detector ever sets the bit, this
-- branch is correctly always false, matching real hardware with the flag
-- never raised; it needs no changes once the detector lands.
function AI:_decideGambler()
  local deckId = self.memory:readSymbol8("wOpponentDeckID")
  if deckId == self.c.IMAKUNI_DECK_ID then
    return self.rng:random(10) < 2
  end

  local flag = bit.band(self.memory:readSymbol8("wAIBarrierFlagCounter"), self.c.AI_MEWTWO_MILL or 0)
  if flag == 0 then return false end

  local notInDeck = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)
  return notInDeck >= self.c.DECK_SIZE - 4
end

-- AIPlay_Gambler:: for every deck except Imakuni?'s own, GamblerEffect's coin
-- toss (and the deck reshuffle after it) runs against wRNG1/wRNG2/wRNGCounter
-- temporarily forced to $50/$50/$50, restored to their real values once the
-- whole Trainer play completes. This is preserved as the literal mechanical
-- byte-poke regardless of outcome: verified directly against RNG:update
-- Sources(), seeding all three to $50 actually yields an odd result (TAILS,
-- one card drawn) under this game's real RNG algorithm, which contradicts
-- the source's own comment claiming it forces heads -- the comment appears
-- to be simply wrong; the mechanical behavior (confirmed by running the
-- already-verified RNG module, not just derived by hand) is what a real
-- cartridge actually produces, so that is what is reproduced here.
function AI:_playGamblerWithRNGCheat(cardId, selection)
  local deckId = self.memory:readSymbol8("wOpponentDeckID")
  if deckId == self.c.IMAKUNI_DECK_ID then
    return self.playerActions:playTrainer(cardId, selection)
  end

  local rng1 = self.memory:readSymbol8("wRNG1")
  local rng2 = self.memory:readSymbol8("wRNG2")
  local counter = self.memory:readSymbol8("wRNGCounter")
  self.memory:writeSymbol8("wRNG1", 0x50)
  self.memory:writeSymbol8("wRNG2", 0x50)
  self.memory:writeSymbol8("wRNGCounter", 0x50)

  local ok, reason = self.playerActions:playTrainer(cardId, selection)

  self.memory:writeSymbol8("wRNG1", rng1)
  self.memory:writeSymbol8("wRNG2", rng2)
  self.memory:writeSymbol8("wRNGCounter", counter)
  return ok, reason
end

-- AIDecide_ClefairyDollOrMysteriousFossil:: shared by both cards (played as
-- a Basic Pokemon). Plays whenever the Active is Wigglytuff (regardless of
-- how full the Bench already is, short of the hard max), otherwise only
-- while the Play Area has fewer than 4 Pokemon.
function AI:_decideClefairyDollOrMysteriousFossil()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if count >= self.c.MAX_PLAY_AREA_POKEMON then return false end

  local activeDeckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local activeId = self.cardData:getCardIDFromDeckIndex(activeDeckIndex)
  if activeId == self.c.WIGGLYTUFF then return true end

  return count < 4
end

-- RemoveFromListDifferentCardOfGivenType:: shuffles `list` (an array of
-- deck indices) via the real RNG, then returns the first entry (in
-- shuffled order) whose card type matches `cardType` (0=Trainer,
-- 1=Pokemon, 2=Energy) and isn't `avoidDeckIndex`. Always returns the
-- (possibly-unchanged) list as a second value so callers can chain further
-- removals against the remainder, matching the source's own in-place list
-- mutation across repeated calls.
function AI:_removeFromListDifferentCardOfGivenType(list, cardType, avoidDeckIndex)
  if #list == 0 then return nil, list end
  local base, bank = self.memory:address("wDuelTempList")
  for i, deckIndex in ipairs(list) do self.memory:write8("wram", base + i - 1, deckIndex, bank) end
  self.rng:shuffleCards(base, #list)
  local shuffled = {}
  for i = 1, #list do shuffled[i] = self.memory:read8("wram", base + i - 1, bank) end

  for i, deckIndex in ipairs(shuffled) do
    if deckIndex ~= avoidDeckIndex then
      local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
      local row = self.cardData:get(cardId)
      local matches
      if not row then matches = false
      elseif row.type < self.c.TYPE_ENERGY then matches = (cardType == 1)
      elseif row.type == self.c.TYPE_TRAINER then matches = (cardType == 0)
      else matches = (cardType == 2) end
      if matches then
        table.remove(shuffled, i)
        return deckIndex, shuffled
      end
    end
  end
  return nil, shuffled
end

-- Shared "only discard Trainer cards from hand; need exactly 2" tail used
-- by ComputerSearch's WondersOfScience/FireCharge/Anger branches.
function AI:_findTwoTrainerDiscardsExcept(avoidDeckIndex)
  local list = self.duelOps:createHandCardList()
  local first, remaining = self:_removeFromListDifferentCardOfGivenType(list, 0, avoidDeckIndex)
  if not first then return nil end
  local second = self:_removeFromListDifferentCardOfGivenType(remaining, 0, avoidDeckIndex)
  if not second then return nil end
  return { first, second }
end

-- ComputerSearch_RockCrusher's Graveler/Golem/Dugtrio tail: same shuffled
-- per-type search, but advances Trainer -> Pokemon -> Energy on failure,
-- and carries whatever type it last succeeded at into the second pick
-- rather than resetting to Trainer.
function AI:_findTwoDiscardsAdvancingType(list, avoidDeckIndex)
  local cardType, first = 0, nil
  while cardType <= 2 do
    first, list = self:_removeFromListDifferentCardOfGivenType(list, cardType, avoidDeckIndex)
    if first then break end
    cardType = cardType + 1
  end
  if not first then return nil end
  local second
  while cardType <= 2 do
    second, list = self:_removeFromListDifferentCardOfGivenType(list, cardType, avoidDeckIndex)
    if second then break end
    cardType = cardType + 1
  end
  if not second then return nil end
  return { first, second }
end

-- ComputerSearch_RockCrusher's 3-hand-card/Professor-Oak branch: no
-- shuffle at all, just the first 2 hand cards (in hand order) that aren't
-- the played card and aren't in this fixed blocklist.
local ROCK_CRUSHER_OAK_DISCARD_BLOCKLIST = {
  "PROFESSOR_OAK", "FIGHTING_ENERGY", "DOUBLE_COLORLESS_ENERGY",
  "DIGLETT", "GEODUDE", "ONIX", "RHYHORN",
}
function AI:_rockCrusherOakDiscards(avoidDeckIndex)
  local found = {}
  for _, deckIndex in ipairs(self.duelOps:createHandCardList()) do
    if deckIndex ~= avoidDeckIndex then
      local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
      local blocked = false
      for _, name in ipairs(ROCK_CRUSHER_OAK_DISCARD_BLOCKLIST) do
        if self.c[name] and cardId == self.c[name] then blocked = true break end
      end
      if not blocked then
        found[#found + 1] = deckIndex
        if #found == 2 then break end
      end
    end
  end
  if #found < 2 then return nil end
  return found
end

-- AIDecide_ComputerSearch_RockCrusher:: at exactly 3 hand cards, target
-- Professor Oak in deck (discarding any 2 hand cards outside the
-- blocklist); with more, walk the Geodude/Graveler/Golem/Dugtrio evolution
-- chain looking for the next evolution to fetch.
function AI:_decideComputerSearchRockCrusher(avoidDeckIndex)
  local handCount = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  if handCount == 3 then
    local oakDeckIndex = self:_findCardIDInDeck(self.c.PROFESSOR_OAK)
    if not oakDeckIndex then return false end
    local discards = self:_rockCrusherOakDiscards(avoidDeckIndex)
    if not discards then return false end
    return true, { deckCard = oakDeckIndex, handDiscards = discards }
  end

  local list = self.duelOps:createHandCardList()
  local target
  local graverDeckIndex = self:_findCardIDInDeck(self.c.GRAVELER)
  if graverDeckIndex and self:_cardIDInHandAndPlayArea(self.c.GEODUDE)
      and not self:_cardIDInHand(self.c.GRAVELER) then
    target = graverDeckIndex
    list = self:_cardListWithout(list, self:_findCardIDInHand(self.c.GEODUDE))
  else
    local golemDeckIndex = self:_findCardIDInDeck(self.c.GOLEM)
    if golemDeckIndex and self:_findCardIDInPlayArea(self.c.GRAVELER, self.c.PLAY_AREA_ARENA) ~= 0xff
        and not self:_cardIDInHand(self.c.GOLEM) then
      target = golemDeckIndex
    else
      local dugtrioDeckIndex = self:_findCardIDInDeck(self.c.DUGTRIO)
      if dugtrioDeckIndex and self:_findCardIDInPlayArea(self.c.DIGLETT, self.c.PLAY_AREA_ARENA) ~= 0xff
          and not self:_cardIDInHand(self.c.DUGTRIO) then
        target = dugtrioDeckIndex
      else
        return false
      end
    end
  end

  local discards = self:_findTwoDiscardsAdvancingType(list, avoidDeckIndex)
  if not discards then return false end
  return true, { deckCard = target, handDiscards = discards }
end

-- AIDecide_ComputerSearch_WondersOfScience:: fewer than 5 hand cards
-- targets Professor Oak; otherwise targets Grimer (or, failing that, Muk)
-- only when the AI does NOT already have one in hand.
function AI:_decideComputerSearchWondersOfScience(avoidDeckIndex)
  local handCount = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  local target
  if handCount < 5 then
    target = self:_findCardIDInDeck(self.c.PROFESSOR_OAK)
  end
  if not target then
    if not self:_cardIDInHand(self.c.GRIMER) then
      target = self:_findCardIDInDeck(self.c.GRIMER)
    end
    if not target and not self:_cardIDInHand(self.c.MUK) then
      target = self:_findCardIDInDeck(self.c.MUK)
    end
  end
  if not target then return false end
  local discards = self:_findTwoTrainerDiscardsExcept(avoidDeckIndex)
  if not discards then return false end
  return true, { deckCard = target, handDiscards = discards }
end

-- AIDecide_ComputerSearch_FireCharge:: priority target order Chansey,
-- Tauros, JigglypuffLv12 -- first one not already in hand that's actually
-- in the deck.
function AI:_decideComputerSearchFireCharge(avoidDeckIndex)
  local target
  for _, cardId in ipairs({ self.c.CHANSEY, self.c.TAUROS, self.c.JIGGLYPUFF_LV12 }) do
    if not self:_cardIDInHand(cardId) then
      target = self:_findCardIDInDeck(cardId)
      if target then break end
    end
  end
  if not target then return false end
  local discards = self:_findTwoTrainerDiscardsExcept(avoidDeckIndex)
  if not discards then return false end
  return true, { deckCard = target, handDiscards = discards }
end

-- AIDecide_ComputerSearch_Anger:: for each of Rattata/Raticate,
-- Growlithe/ArcanineLv34, Doduo/Dodrio: prefer fetching the evolution
-- (wanted) when the pre-evolution is already out (hand or Play Area);
-- failing that, fetch the pre-evolution itself when the evolution is
-- already in hand. Reuses the same LookForCardIDInDeck_GivenCardIDInHand
-- [AndPlayArea] primitives as AIDecide_Pokeball.
function AI:_decideComputerSearchAnger(avoidDeckIndex)
  local target
  for _, pair in ipairs({
    { self.c.RATICATE, self.c.RATTATA }, { self.c.ARCANINE_LV34, self.c.GROWLITHE },
    { self.c.DODRIO, self.c.DODUO },
  }) do
    local evolution, preEvolution = pair[1], pair[2]
    target = self:_pokeBallGivenCardInHandAndPlayArea(evolution, preEvolution)
    if not target then target = self:_pokeBallGivenCardInHand(preEvolution, evolution) end
    if target then break end
  end
  if not target then return false end
  local discards = self:_findTwoTrainerDiscardsExcept(avoidDeckIndex)
  if not discards then return false end
  return true, { deckCard = target, handDiscards = discards }
end

-- AIDecide_ComputerSearch:: the hand-count>=3 gate is the only deck-agnostic
-- part of this decision -- every deck that can play it at all (Rock
-- Crusher, Wonders of Science, Fire Charge, Anger) has its own dedicated,
-- multi-branch card-search routine with no shared/general fallback; every
-- other deck never plays it.
function AI:_decideComputerSearch(avoidDeckIndex)
  local handCount = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  if handCount < 3 then return false end

  local deckId = self.memory:readSymbol8("wOpponentDeckID")
  if deckId == self.c.ROCK_CRUSHER_DECK_ID then
    return self:_decideComputerSearchRockCrusher(avoidDeckIndex)
  elseif deckId == self.c.WONDERS_OF_SCIENCE_DECK_ID then
    return self:_decideComputerSearchWondersOfScience(avoidDeckIndex)
  elseif deckId == self.c.FIRE_CHARGE_DECK_ID then
    return self:_decideComputerSearchFireCharge(avoidDeckIndex)
  elseif deckId == self.c.ANGER_DECK_ID then
    return self:_decideComputerSearchAnger(avoidDeckIndex)
  end
  return false
end

-- CheckIfHasCardIDInHand:: despite the name, requires TWO copies of the
-- card in hand to return the second one's deck index -- the first match
-- only marks "seen once" and keeps scanning. Used by decks that only want
-- to trade away a spare copy of a specific card, never their only one.
function AI:_checkIfHasCardIDInHand(cardId)
  local seenOnce = false
  for _, deckIndex in ipairs(self.duelOps:createHandCardList()) do
    if self.cardData:getCardIDFromDeckIndex(deckIndex) == cardId then
      if seenOnce then return deckIndex end
      seenOnce = true
    end
  end
  return nil
end

-- FindDuplicatePokemonCards:: nested nothing-skipped hand-pair scan for any
-- two Pokemon cards sharing a card ID. Keeps looping after a match --a
-- documented source quirk ("for some reason loop still continues... it
-- overwrites the result") -- so the LAST duplicate pair found in this
-- (i,j) i<j scan order wins, not the first.
function AI:_findDuplicatePokemonCards()
  local hand = self.duelOps:createHandCardList()
  local result
  for i = 1, #hand do
    local idI = self.cardData:getCardIDFromDeckIndex(hand[i])
    for j = i + 1, #hand do
      local idJ = self.cardData:getCardIDFromDeckIndex(hand[j])
      if idJ == idI then
        local row = self.cardData:get(idJ)
        if row and row.type < self.c.TYPE_ENERGY then result = hand[j] end
      end
    end
  end
  return result
end

-- CountPokemonCardsInHandAndInPlayArea::
function AI:_countPokemonCardsInHandAndInPlayArea()
  local total = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for _, deckIndex in ipairs(self.duelOps:createHandCardList()) do
    local row = self.cardData:get(self.cardData:getCardIDFromDeckIndex(deckIndex))
    if row and row.type < self.c.TYPE_ENERGY then total = total + 1 end
  end
  return total
end

-- CountOppEnergyCardsInHandAndAttached::
function AI:_countEnergyCardsInHandAndAttached()
  local total = #self:_energyCardsInHand()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for slot = self.c.PLAY_AREA_ARENA, count - 1 do
    total = total + self.duelOps:countNumberOfEnergyCardsAttached(slot)
  end
  return total
end

-- LookForCardIDToTradeWithDifferentHandCard:: wantedCardId must not already
-- be in hand, and must be in deck; then returns the first Pokemon card in
-- hand (hand order) whose card ID isn't avoidCardId, to trade away.
function AI:_lookForCardIDToTradeWithDifferentHandCard(wantedCardId, avoidCardId)
  if self:_cardIDInHand(wantedCardId) then return nil end
  local target = self:_findCardIDInDeck(wantedCardId)
  if not target then return nil end
  for _, deckIndex in ipairs(self.duelOps:createHandCardList()) do
    local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
    if cardId ~= avoidCardId then
      local row = self.cardData:get(cardId)
      if row and row.type < self.c.TYPE_ENERGY then return target, deckIndex end
    end
  end
  return nil
end

-- Shared evolution-chain walk used by 7 of Pokemon Trader's 10 deck
-- routines: for each "line" (an evolution family, given as an array of
-- {preEvolution, evolution} stage-transition pairs, checked in order),
-- first try every stage transition's "pre-evolution already out (hand or
-- Play Area)" case, then -- only if none of that line's transitions
-- matched -- every transition's "evolution already in hand" case, before
-- moving to the next line. A line may instead be given as
-- {andPlayArea = {...}, hand = {...}} when the source's own two passes use
-- a different pair order (PowerGenerator's Magnemite line does).
function AI:_pokemonTraderEvolutionChainTarget(lines)
  for _, line in ipairs(lines) do
    for _, pair in ipairs(line.andPlayArea or line) do
      local target = self:_pokeBallGivenCardInHandAndPlayArea(pair[2], pair[1])
      if target then return target end
    end
    for _, pair in ipairs(line.hand or line) do
      local target = self:_pokeBallGivenCardInHand(pair[1], pair[2])
      if target then return target end
    end
  end
  return nil
end

function AI:_decidePokemonTraderLegendaryMoltres()
  local target, tradeAway = self:_lookForCardIDToTradeWithDifferentHandCard(
    self.c.MOLTRES_LV37, self.c.MOLTRES_LV35)
  if not target then return false end
  return true, { deckPokemon = target, handPokemon = tradeAway }
end

-- AIDecide_PokemonTrader_LegendaryArticuno:: skips entirely if the AI
-- already has ArticunoLv35 or Lapras out; otherwise prefers fetching Seel
-- (if not already out), falling back to Dewgong (if not already out).
-- Trading away requires a SPARE copy (CheckIfHasCardIDInHand's own
-- 2-copies-required semantics) of Chansey, Ditto, or ArticunoLv37, in
-- that priority order.
function AI:_decidePokemonTraderLegendaryArticuno()
  if self:_cardIDInHandAndPlayArea(self.c.ARTICUNO_LV35) then return false end
  if self:_cardIDInHandAndPlayArea(self.c.LAPRAS) then return false end

  local target
  if not self:_cardIDInHandAndPlayArea(self.c.SEEL) then
    target = self:_findCardIDInDeck(self.c.SEEL)
  end
  if not target then
    if self:_cardIDInHandAndPlayArea(self.c.DEWGONG) then return false end
    target = self:_findCardIDInDeck(self.c.DEWGONG)
    if not target then return false end
  end

  for _, cardId in ipairs({ self.c.CHANSEY, self.c.DITTO, self.c.ARTICUNO_LV37 }) do
    local tradeAway = self:_checkIfHasCardIDInHand(cardId)
    if tradeAway then return true, { deckPokemon = target, handPokemon = tradeAway } end
  end
  return false
end

-- AIDecide_PokemonTrader_LegendaryDragonite:: with fewer than 5 total
-- Energy cards (hand + attached) OR fewer than 5 total Pokemon cards (hand
-- + Play Area, only checked when Energy count is already >=5), targets
-- Kangaskhan directly; otherwise walks the Magikarp/Gyarados,
-- Dratini/Dragonair/DragoniteLv41, Charmander/Charmeleon/Charizard chain.
function AI:_decidePokemonTraderLegendaryDragonite()
  local useKangaskhan = true
  if self:_countEnergyCardsInHandAndAttached() >= 5 then
    useKangaskhan = self:_countPokemonCardsInHandAndInPlayArea() < 5
  end
  local target
  if useKangaskhan then
    target = self:_findCardIDInDeck(self.c.KANGASKHAN)
  else
    target = self:_pokemonTraderEvolutionChainTarget({
      { { self.c.MAGIKARP, self.c.GYARADOS } },
      { { self.c.DRATINI, self.c.DRAGONAIR }, { self.c.DRAGONAIR, self.c.DRAGONITE_LV41 } },
      { { self.c.CHARMANDER, self.c.CHARMELEON }, { self.c.CHARMELEON, self.c.CHARIZARD } },
    })
  end
  if not target then return false end
  for _, cardId in ipairs({ self.c.DRAGONAIR, self.c.CHARMELEON, self.c.GYARADOS,
      self.c.MAGIKARP, self.c.CHARMANDER, self.c.DRATINI }) do
    local tradeAway = self:_checkIfHasCardIDInHand(cardId)
    if tradeAway then return true, { deckPokemon = target, handPokemon = tradeAway } end
  end
  return false
end

-- AIDecide_PokemonTrader_LegendaryRonald:: walks Eevee's three
-- Eeveelutions (each its own single-transition line) then the Dratini
-- chain. Trading away only needs a single copy (LookForCardIDInHandList_
-- Bank8, not the 2-copies CheckIfHasCardIDInHand) of ZapdosLv68,
-- ArticunoLv37, or MoltresLv37.
function AI:_decidePokemonTraderLegendaryRonald()
  local target = self:_pokemonTraderEvolutionChainTarget({
    { { self.c.EEVEE, self.c.FLAREON_LV22 } },
    { { self.c.EEVEE, self.c.VAPOREON_LV29 } },
    { { self.c.EEVEE, self.c.JOLTEON_LV24 } },
    { { self.c.DRATINI, self.c.DRAGONAIR }, { self.c.DRAGONAIR, self.c.DRAGONITE_LV41 } },
  })
  if not target then return false end
  for _, cardId in ipairs({ self.c.ZAPDOS_LV68, self.c.ARTICUNO_LV37, self.c.MOLTRES_LV37 }) do
    local tradeAway = self:_findCardIDInHand(cardId)
    if tradeAway then return true, { deckPokemon = target, handPokemon = tradeAway } end
  end
  return false
end

function AI:_decidePokemonTraderBlisteringPokemon()
  local target = self:_pokemonTraderEvolutionChainTarget({
    { { self.c.RHYHORN, self.c.RHYDON } },
    { { self.c.CUBONE, self.c.MAROWAK_LV26 } },
    { { self.c.PONYTA, self.c.RAPIDASH } },
  })
  if not target then return false end
  local tradeAway = self:_findDuplicatePokemonCards()
  if not tradeAway then return false end
  return true, { deckPokemon = target, handPokemon = tradeAway }
end

function AI:_decidePokemonTraderSoundOfTheWaves()
  local target = self:_pokemonTraderEvolutionChainTarget({
    { { self.c.SEEL, self.c.DEWGONG } },
    { { self.c.KRABBY, self.c.KINGLER } },
    { { self.c.SHELLDER, self.c.CLOYSTER } },
    { { self.c.HORSEA, self.c.SEADRA } },
    { { self.c.TENTACOOL, self.c.TENTACRUEL } },
  })
  if not target then return false end
  for _, cardId in ipairs({ self.c.SEEL, self.c.KRABBY, self.c.HORSEA,
      self.c.SHELLDER, self.c.TENTACOOL }) do
    local tradeAway = self:_checkIfHasCardIDInHand(cardId)
    if tradeAway then return true, { deckPokemon = target, handPokemon = tradeAway } end
  end
  return false
end

-- AIDecide_PokemonTrader_PowerGenerator:: the Magnemite line's own second
-- (hand-only) pass checks pairs in a different order (Lv15 before Lv13)
-- than its first (Play-Area) pass (Lv13 before Lv15) -- a literal source
-- asymmetry, not a transcription slip. The real source is also missing a
-- `jr .no_carry` after this whole chain fails, falling through into
-- .find_duplicates with leftover register garbage (from whichever of the
-- three internal exit paths the last failed lookup took) treated as the
-- target card -- not deterministically reproducible, and not
-- reimplemented; this fails closed exactly where the chain search itself
-- comes up empty instead.
function AI:_decidePokemonTraderPowerGenerator()
  local target = self:_pokemonTraderEvolutionChainTarget({
    { { self.c.PIKACHU_LV14, self.c.RAICHU_LV40 }, { self.c.PIKACHU_LV12, self.c.RAICHU_LV40 } },
    { { self.c.VOLTORB, self.c.ELECTRODE_LV42 }, { self.c.VOLTORB, self.c.ELECTRODE_LV35 } },
    {
      andPlayArea = {
        { self.c.MAGNEMITE_LV13, self.c.MAGNETON_LV35 }, { self.c.MAGNEMITE_LV15, self.c.MAGNETON_LV35 },
        { self.c.MAGNEMITE_LV13, self.c.MAGNETON_LV28 }, { self.c.MAGNEMITE_LV15, self.c.MAGNETON_LV28 },
      },
      hand = {
        { self.c.MAGNEMITE_LV15, self.c.MAGNETON_LV35 }, { self.c.MAGNEMITE_LV13, self.c.MAGNETON_LV35 },
        { self.c.MAGNEMITE_LV15, self.c.MAGNETON_LV28 }, { self.c.MAGNEMITE_LV13, self.c.MAGNETON_LV28 },
      },
    },
  })
  if not target then return false end
  local tradeAway = self:_findDuplicatePokemonCards()
  if not tradeAway then return false end
  return true, { deckPokemon = target, handPokemon = tradeAway }
end

function AI:_decidePokemonTraderFlowerGarden()
  local target = self:_pokemonTraderEvolutionChainTarget({
    { { self.c.BULBASAUR, self.c.IVYSAUR }, { self.c.IVYSAUR, self.c.VENUSAUR_LV67 } },
    { { self.c.BELLSPROUT, self.c.WEEPINBELL }, { self.c.WEEPINBELL, self.c.VICTREEBEL } },
    { { self.c.ODDISH, self.c.GLOOM }, { self.c.GLOOM, self.c.VILEPLUME } },
  })
  if not target then return false end
  local tradeAway = self:_findDuplicatePokemonCards()
  if not tradeAway then return false end
  return true, { deckPokemon = target, handPokemon = tradeAway }
end

-- AIDecide_PokemonTrader_StrangePower:: inputting MrMime as both the
-- wanted and avoid card ID is redundant (per the source's own comment)
-- since the wanted-card-already-in-hand check already covers it.
function AI:_decidePokemonTraderStrangePower()
  local target, tradeAway = self:_lookForCardIDToTradeWithDifferentHandCard(
    self.c.MR_MIME, self.c.MR_MIME)
  if not target then return false end
  return true, { deckPokemon = target, handPokemon = tradeAway }
end

function AI:_decidePokemonTraderFlamethrower()
  local target = self:_pokemonTraderEvolutionChainTarget({
    { { self.c.CHARMANDER, self.c.CHARMELEON }, { self.c.CHARMELEON, self.c.CHARIZARD } },
    { { self.c.VULPIX, self.c.NINETALES_LV32 } },
    { { self.c.GROWLITHE, self.c.ARCANINE_LV45 } },
    { { self.c.EEVEE, self.c.FLAREON_LV28 } },
  })
  if not target then return false end
  local tradeAway = self:_findDuplicatePokemonCards()
  if not tradeAway then return false end
  return true, { deckPokemon = target, handPokemon = tradeAway }
end

-- AIDecide_PokemonTrader:: has no deck-agnostic path at all -- every one of
-- the ten decks that can ever play this card (Legendary Moltres/Articuno/
-- Dragonite/Ronald, Blistering Pokemon, Sound of the Waves, Power
-- Generator, Flower Garden, Strange Power, Flamethrower) dispatches to its
-- own dedicated card-search routine, and every other deck never plays it
-- at all (a straight `or a; ret`).
function AI:_decidePokemonTrader()
  local deckId = self.memory:readSymbol8("wOpponentDeckID")
  if deckId == self.c.LEGENDARY_MOLTRES_DECK_ID then
    return self:_decidePokemonTraderLegendaryMoltres()
  elseif deckId == self.c.LEGENDARY_ARTICUNO_DECK_ID then
    return self:_decidePokemonTraderLegendaryArticuno()
  elseif deckId == self.c.LEGENDARY_DRAGONITE_DECK_ID then
    return self:_decidePokemonTraderLegendaryDragonite()
  elseif deckId == self.c.LEGENDARY_RONALD_DECK_ID then
    return self:_decidePokemonTraderLegendaryRonald()
  elseif deckId == self.c.BLISTERING_POKEMON_DECK_ID then
    return self:_decidePokemonTraderBlisteringPokemon()
  elseif deckId == self.c.SOUND_OF_THE_WAVES_DECK_ID then
    return self:_decidePokemonTraderSoundOfTheWaves()
  elseif deckId == self.c.POWER_GENERATOR_DECK_ID then
    return self:_decidePokemonTraderPowerGenerator()
  elseif deckId == self.c.FLOWER_GARDEN_DECK_ID then
    return self:_decidePokemonTraderFlowerGarden()
  elseif deckId == self.c.STRANGE_POWER_DECK_ID then
    return self:_decidePokemonTraderStrangePower()
  elseif deckId == self.c.FLAMETHROWER_DECK_ID then
    return self:_decidePokemonTraderFlamethrower()
  end
  return false
end

-- AICheckIfAttackIsHighRecoil:: despite the name, the source routine's final
-- carry (after its `ccf`) means "there IS a usable attack AND it is NOT
-- flagged High Recoil" -- i.e. a normal, safe attack is available. Every
-- caller of this routine bails (does not need this specific KO-avoidance
-- branch) exactly when that is true, and only continues when either no
-- attack is usable at all or the usable one is itself a recoil risk.
-- Preserved literally rather than renamed/re-derived, matching the project's
-- rule against silently substituting cleaner-looking behavior for source.
function AI:_checkIfAttackIsHighRecoilForAI()
  local usable, selected = self:processButDontUseAttack()
  if usable == nil then return nil, selected end
  if not usable then return false end
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local _, attack = self.combat:loadAttack(deckIndex, selected)
  return not self:_attackFlag(attack, 1, self.c.HIGH_RECOIL_F)
end

-- AIPickEnergyCardToDiscard:: finds an attached Energy that is not useful to
-- the card's own attacks per CheckIfEnergyIsUseful (already translated and
-- shared with the retreat-payment picker as _energyIsUsefulForRetreat);
-- defaults to the first attached Energy card if every attached card is
-- useful, or nil if none is attached. Distinct from _pickAttachedEnergyToRemove
-- (PickAttachedEnergyCardToRemove), which prioritizes Double Colorless
-- Energy first -- this routine has no such DCE-first case.
function AI:_pickEnergyCardToDiscard(slot)
  local count = self.duelOps:createArenaOrBenchEnergyCardList(slot)
  if not count or count == 0 then return nil end
  local _, activeId, active = self:_cardAtPlayArea(slot, false)
  local base, bank = self.memory:address("wDuelTempList")
  local first, notUseful
  for i = 0, count - 1 do
    local deckIndex = self.memory:read8("wram", base + i, bank)
    first = first or deckIndex
    if not notUseful and not self:_energyIsUsefulForRetreat(deckIndex, activeId, active.type) then
      notUseful = deckIndex
    end
  end
  return notUseful or first
end

-- AIDecide_SuperPotion_Phase08/Phase11 (trainer_cards.asm). Phase08 is the
-- emergency defensive heal: only relevant when the Active card has no safe
-- usable attack of its own, has at least one Energy attached (Super Potion's
-- discard cost requires one), and healing would let it survive an otherwise
-- exactly-lethal hit. Phase11 is the general opportunistic heal: scan every
-- Play Area slot with >=40 damage (skipping cards whose attacks would become
-- unusable after the discard, or that have a BOOST_IF_TAKEN_DAMAGE attack),
-- starting from the Active card unless healing it would specifically have
-- prevented the Phase08 scenario's KO -- in which case Phase08 already owns
-- that decision and Phase11 starts from the Bench instead.
function AI:_decideSuperPotion(phase)
  if phase == 8 then
    local retreat, retreatErr = self:decideWhetherToRetreat()
    if retreat == nil then return nil, retreatErr end
    if retreat then return false end
    local safeAttack, safeErr = self:_checkIfAttackIsHighRecoilForAI()
    if safeAttack == nil then return nil, safeErr end
    if safeAttack then return false end
    local attached = self.duelOps:getPlayAreaCardAttachedEnergies(self.c.PLAY_AREA_ARENA)
    if not attached or attached == 0 then return false end
    local canKO, koDamage = self:checkIfDefendingPokemonCanKnockOut()
    if canKO == nil then return nil, koDamage end
    if not canKO then return false end
    local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP)
    local damage = self:_damageAt(self.c.PLAY_AREA_ARENA)
    local heal = math.min(40, damage or 0)
    -- Literal source arithmetic (hp + heal - koDamage), even though
    -- koDamage always equals hp here by construction of the exact-KO check
    -- just above -- see the AI.lua comment history for why this is kept
    -- mechanical rather than simplified to "heal > 0".
    if heal == 0 or hp + heal <= koDamage then return false end
    local discard = self:_pickEnergyCardToDiscard(self.c.PLAY_AREA_ARENA)
    if discard == nil then return false end
    return true, { playArea = self.c.PLAY_AREA_ARENA, discardEnergy = discard }
  end

  -- Phase11.
  local canKO, koDamage = self:checkIfDefendingPokemonCanKnockOut()
  if canKO == nil then return nil, koDamage end
  local startSlot = self.c.PLAY_AREA_ARENA
  if canKO then
    local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP)
    local damage = self:_damageAt(self.c.PLAY_AREA_ARENA)
    local heal = math.min(40, damage or 0)
    -- "; return if using healing prevents KO." Source returns (bails the
    -- whole call) unconditionally here -- it does not merely skip the
    -- Active card and keep scanning. Phase08 above owns this specific
    -- emergency-heal scenario; Phase11's general scan never runs this turn.
    if not (heal == 0 or hp + heal <= koDamage) then return false end
    -- Healing would NOT have prevented the KO -- the Active card dies
    -- regardless of Super Potion this turn ("using Super Potion on active
    -- card does not prevent a KO"). Skip it and start the general scan at
    -- Bench, unless the defending player is on their last prize card, in
    -- which case source still starts from Active.
    self.duelVars:swapTurn()
    local playerPrizes = self.duelOps:countPrizes()
    self.duelVars:swapTurn()
    if playerPrizes ~= 1 then startSlot = self.c.PLAY_AREA_BENCH_1 end
  end

  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for slot = startSlot, count - 1 do
    local attached = self.duelOps:getPlayAreaCardAttachedEnergies(slot)
    if attached and attached > 0 then
      local boosted, boostedErr = self:_activeHasUsableBoostIfTakenDamageAttack(slot)
      if boosted == nil then return nil, boostedErr end
      if not boosted then
        local unusableAfterDiscard, unusableErr = self:_discardingMakesAttacksUnusable(slot)
        if unusableAfterDiscard == nil then return nil, unusableErr end
        if not unusableAfterDiscard then
          local damage = self:_damageAt(slot)
          if damage and damage >= 40 then
            local discard = self:_pickEnergyCardToDiscard(slot)
            if discard == nil then goto superPotionNextSlot end
            if slot == self.c.PLAY_AREA_ARENA then
              local safeAttack, safeErr = self:_checkIfAttackIsHighRecoilForAI()
              if safeAttack == nil then return nil, safeErr end
              if not safeAttack then goto superPotionNextSlot end
              return true, { playArea = slot, discardEnergy = discard }
            end
            self.duelVars:swapTurn()
            local playerPrizes = self.duelOps:countPrizes()
            self.duelVars:swapTurn()
            if playerPrizes == 1 or self.rng:random(10) >= 3 then
              return true, { playArea = slot, discardEnergy = discard }
            end
            return false
          end
        end
      end
    end
    ::superPotionNextSlot::
  end
  return false
end

-- AIDecide_SuperPotion_Phase11's ".CheckIfHasAttackWithBoostIfTakenDamageFlag":
-- carry (true here) if either attack is currently usable and flagged
-- BOOST_IF_TAKEN_DAMAGE_F -- healing such a card would remove its own damage
-- bonus, so Super Potion skips it.
function AI:_activeHasUsableBoostIfTakenDamageAttack(slot)
  local saved = self.memory:readSymbol8("hTempPlayAreaLocation_ff9d")
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
  local found = false
  for attackIndex = 0, 1 do
    local unusable = self:_checkIfBenchAttackUnusable(slot, attackIndex)
    if slot == self.c.PLAY_AREA_ARENA then
      local usable = self:_checkAttackUsableForAI(attackIndex)
      unusable = not usable
    end
    if not unusable then
      local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
      local _, attack = self.combat:loadAttack(deckIndex, attackIndex)
      if self:_attackFlag(attack, 3, self.c.BOOST_IF_TAKEN_DAMAGE_F) then
        found = true
        break
      end
    end
  end
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", saved)
  return found
end

-- ".CheckIfDiscardingMakesAttacksUnusable": carry (true here) if, for either
-- attack that currently has enough Energy, discarding the chosen card would
-- drop it below what that attack needs. Checks both attacks unconditionally
-- (source falls through .second_attack_2 regardless of the first attack's
-- outcome unless it already found a "becomes unusable" case), returning true
-- the first time a currently-usable attack would stop being usable.
function AI:_discardingMakesAttacksUnusable(slot)
  for attackIndex = 0, 1 do
    local before = self:checkEnergyNeededForAttack(slot, attackIndex)
    if before and before.enough then
      local after, err = self:_checkEnergyNeededForAttackAfterDiscard(slot, attackIndex)
      if after == nil then return nil, err end
      if not after.enough then return true end
    end
  end
  return false
end

-- CheckEnergyNeededForAttackAfterDiscard:: mirrors checkEnergyNeededForAttack
-- exactly (same recompute-then-deficit arithmetic, matching the source's own
-- near-duplicate routine), except the Energy AIPickEnergyCardToDiscard would
-- discard (one colored Energy, or two Colorless for Double Colorless Energy)
-- is removed from the freshly recomputed totals before the deficit check.
function AI:_checkEnergyNeededForAttackAfterDiscard(slot, attackIndex)
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
  if deckIndex == 0xff then return nil, "empty_slot" end
  local _, attack = self.combat:loadAttack(deckIndex, attackIndex)
  if attack.nameTextId == 0 or attack.category == self.c.POKEMON_POWER then
    return nil, "no_attack"
  end
  local discard = self:_pickEnergyCardToDiscard(slot)
  self.duelOps:getPlayAreaCardAttachedEnergies(slot)
  if slot == self.c.PLAY_AREA_ARENA then self.combat.status:handleEnergyBurn() end
  local base, bank = self.memory:address("wAttachedEnergies")

  if discard ~= nil then
    local discardId = self.cardData:getCardIDFromDeckIndex(discard)
    local totalNow = self.memory:readSymbol8("wTotalAttachedEnergies")
    if discardId == self.c.DOUBLE_COLORLESS_ENERGY then
      local colorless = self.memory:read8("wram", base + self.c.COLORLESS, bank)
      self.memory:write8("wram", base + self.c.COLORLESS, math.max(0, colorless - 2), bank)
      self.memory:writeSymbol8("wTotalAttachedEnergies", math.max(0, totalNow - 2))
    else
      for color = 0, self.c.NUM_COLORED_TYPES - 1 do
        if self:_energyCardIdForColor(color) == discardId then
          local attached = self.memory:read8("wram", base + color, bank)
          self.memory:write8("wram", base + color, math.max(0, attached - 1), bank)
          break
        end
      end
      self.memory:writeSymbol8("wTotalAttachedEnergies", math.max(0, totalNow - 1))
    end
  end

  local requiredColored, coloredNeeded, neededColor = 0, 0, nil
  for color = 0, self.c.NUM_COLORED_TYPES - 1 do
    local required = attack.energy[color] or 0
    local attached = self.memory:read8("wram", base + color, bank)
    requiredColored = requiredColored + required
    if required > attached then
      coloredNeeded = required - attached
      neededColor = color
    end
  end
  local total = self.memory:readSymbol8("wTotalAttachedEnergies")
  local coloredSatisfied = requiredColored - coloredNeeded
  local colorlessRequired = attack.energy[self.c.COLORLESS] or 0
  local colorlessNeeded = math.max(0, colorlessRequired - math.max(0, total - coloredSatisfied))
  return {
    colored = coloredNeeded, colorless = colorlessNeeded, color = neededColor,
    enough = coloredNeeded == 0 and colorlessNeeded == 0,
  }
end

function AI:_decidePotion(phase)
  if phase == 7 then
    local retreat, err = self:decideWhetherToRetreat()
    if retreat == nil then return nil, err end
    if retreat then return false end
    local canKO, damage = self:checkIfDefendingPokemonCanKnockOut()
    if canKO == nil then return nil, damage end
    if not canKO then return false end
    local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP)
    local dealt = select(1, self:_damageAt(self.c.PLAY_AREA_ARENA))
    local heal = math.min(20, dealt)
    if heal == 0 or hp + heal <= damage then return false end
    return true, { playArea = self.c.PLAY_AREA_ARENA }
  end

  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for slot = self.c.PLAY_AREA_ARENA, count - 1 do
    local damage = select(1, self:_damageAt(slot))
    if damage >= 20 then
      if slot == self.c.PLAY_AREA_ARENA then return true, { playArea = slot } end
      self.duelVars:swapTurn()
      local humanPrizes = self.duelOps:countPrizes()
      self.duelVars:swapTurn()
      if humanPrizes == 1 or self.rng:random(10) >= 3 then return true, { playArea = slot } end
    end
  end
  return false
end

function AI:_decideDefender(phase)
  local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP)
  if phase == 13 then
    local exact, damage = self:checkIfDefendingPokemonCanKnockOut()
    if exact == nil then return nil, damage end
    if exact and math.max(0, damage - 20) < hp then return true, { playArea = self.c.PLAY_AREA_ARENA } end
    return false
  end
  local selected = self.memory:readSymbol8("wSelectedAttack")
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local _, attack = self.combat:loadAttack(deckIndex, selected)
  if not self:_attackFlag(attack, 1, self.c.HIGH_RECOIL_F)
      and not self:_attackFlag(attack, 1, self.c.LOW_RECOIL_F) then return false end
  local recoil = self.combat:applyDamageModifiersToSelf(attack.effectParam or 0)
  if recoil > 0 and recoil >= hp and math.max(0, recoil - 20) < hp then
    return true, { playArea = self.c.PLAY_AREA_ARENA }
  end
  return false
end

function AI:_decidePlusPower(phase)
  local defenderHP = self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_HP)
  local alreadyKO, koDetail = self:checkIfAnyAttackKnocksOutDefendingCard(self.c.PLAY_AREA_ARENA)
  if alreadyKO == nil then return nil, koDetail end
  if alreadyKO then return false end
  for attackIndex = 0, 1 do
    local usable, reason = self:_checkAttackUsableForAI(attackIndex)
    if usable then
      local estimate, err = self:estimateDamageVersusDefendingCard(attackIndex)
      if not estimate then return nil, err end
      if estimate.damage > 0 and estimate.damage < defenderHP then
        local boosted = estimate.damage + 10
        local _, defenderId = self:_cardAtPlayArea(self.c.PLAY_AREA_ARENA, true)
        local mrMimeOK = boosted < 30 or defenderId ~= self.c.MR_MIME
        if mrMimeOK and ((phase == 13 and boosted >= defenderHP)
            or (phase == 14 and estimate.min >= 10 and self.rng:random(10) < 3)) then
          self.memory:writeSymbol8("wAIPlusPowerAttack", attackIndex)
          return true, nil, attackIndex
        end
      end
    elseif reason and reason:match("^untranslated_effect:") then
      return nil, reason
    end
  end
  return false
end

function AI:_decideSwitch()
  local target = self.memory:readSymbol8("wAIPlayAreaCardToSwitch")
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if target < self.c.PLAY_AREA_BENCH_1 or target >= count then
    local slot, reason = self:decideBenchPokemonToSwitchTo()
    if not slot then return false, reason end
    target = slot
  end
  local cost = self:getPlayAreaCardRetreatCost(self.c.PLAY_AREA_ARENA)
  local attached = self.duelOps:getPlayAreaCardAttachedEnergies(self.c.PLAY_AREA_ARENA)
  local should = cost >= 3 or attached < cost
  if self.memory:readSymbol8("wAIPlayEnergyCardForRetreat") ~= 0 and cost - attached >= 2 then should = true end
  if not should then return false end
  return true, { bench = target }
end

function AI:_decideFullHeal()
  local status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
  if status == self.c.NO_STATUS then return false end
  -- Poison/double poison is the source's unconditional path.
  if bit.band(status, self.c.DOUBLE_POISONED) ~= 0 then return true end
  local special = bit.band(status, self.c.CNF_SLP_PRZ)
  if special == self.c.ASLEEP then
    -- Preserve the source bug: it checks the AI's own Play Area for these cards.
    for _, id in ipairs({self.c.GASTLY_LV8, self.c.GASTLY_LV17, self.c.HAUNTER_LV22}) do
      if id and self:_findCardIDInPlayArea(id, self.c.PLAY_AREA_ARENA) ~= 0xff then return true end
    end
  elseif special == self.c.CONFUSED then
    local canDamage, err = self:_canDamageDefendingPokemon(self.c.PLAY_AREA_ARENA)
    if canDamage == nil then return nil, err end
    if canDamage and self.memory:readSymbol8("wAIPlayEnergyCardForRetreat") ~= 0 then return true end
  end
  return false
end

function AI:_decideEnergySearch()
  local hand = self:_energyCardsInHand()
  local preferred
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for slot = self.c.PLAY_AREA_ARENA, count - 1 do
    for attackIndex = 0, 1 do
      local need = self:checkEnergyNeededForAttack(slot, attackIndex)
      if need and need.colored > 0 and need.energyCardId then
        local have = false
        for _, e in ipairs(hand) do if e.cardId == need.energyCardId then have = true break end end
        if not have then preferred = preferred or need.energyCardId end
      end
    end
  end
  if #hand > 0 and not preferred then return false end
  local deckIndex = self:_firstBasicEnergyInDeck(preferred)
  if not deckIndex then return false end
  return true, { deckBasicEnergy = deckIndex }
end

-- CheckIfCardCanBePlayed:: an evolution card's own playability additionally
-- consults IsPrehistoricPowerActive and CheckIfCanEvolveInto against every
-- Play Area slot; a Trainer defers to CheckCantUseTrainerDueToEffect and its
-- own INITIAL_EFFECT_1 handler (the same pair processHandTrainerCards uses).
-- Branch order mirrors the source's own `cp TYPE_ENERGY` / `cp TYPE_TRAINER`
-- dispatch: card kinds below TYPE_ENERGY are Pokemon, exactly TYPE_TRAINER is
-- Trainer, everything else is Energy.
function AI:_checkIfCardCanBePlayed(deckIndex)
  local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
  local row = self.cardData:get(cardId)
  if not row then return false end

  if row.type < self.c.TYPE_ENERGY then
    if row.stage == self.c.BASIC then
      local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
      return count < self.c.MAX_PLAY_AREA_POKEMON
    end
    if self:_isPrehistoricPowerActive() then return false end
    local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    for slot = self.c.PLAY_AREA_ARENA, count - 1 do
      if self.duelOps:checkIfCanEvolveInto(deckIndex, slot) then return true end
    end
    return false
  end

  if row.type == self.c.TYPE_TRAINER then
    if self.combat.status:checkCantUseTrainerDueToEffect() then return false end
    self.playerActions.effects:loadNonPokemonCardEffectCommands(deckIndex, self.cardData)
    local carry, err = self.playerActions.effects:tryExecute(
      self.c.EFFECTCMDTYPE_INITIAL_EFFECT_1, { playerActions = self.playerActions })
    if carry == nil then return nil, err end
    return not carry
  end

  -- Energy card: playable only if this turn's one-Energy-per-turn slot is free.
  return self.memory:readSymbol8("wAlreadyPlayedEnergy") == 0
end

-- CheckForEvolutionInList:: the real routine temporarily overwrites
-- PLAY_AREA_ARENA's own arena-card byte with `cardId` so it can reuse
-- CheckIfCanEvolveInto, which means the CAN_EVOLVE_THIS_TURN flag it
-- consults is always PLAY_AREA_ARENA's real flag, regardless of which
-- Play Area slot's card `cardId` actually came from. Reproduced here as a
-- pure read (no memory mutation) with the identical net result.
function AI:_checkForEvolutionInList(cardId, list)
  local current = self.cardData:get(cardId)
  if not current then return nil end
  local flags = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_FLAGS + self.c.PLAY_AREA_ARENA)
  if bit.band(flags, self.c.CAN_EVOLVE_THIS_TURN) == 0 then return nil end
  for _, deckIndex in ipairs(list) do
    local evolution = self.cardData:get(self.cardData:getCardIDFromDeckIndex(deckIndex))
    if evolution and evolution.preEvolutionTextId == current.nameTextId then
      return deckIndex
    end
  end
  return nil
end

-- .LookForEvolution:: scans every deck index (any location) for a card that
-- can evolve the Play Area Pokemon at `slot`. Returns (foundInHand,
-- foundAnywhere) -- foundInHand short-circuits the scan the moment a hand
-- copy turns up, exactly like the source's early `scf; ret`.
function AI:_lookForEvolutionForPlayArea(slot)
  local foundAnywhere = false
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    if self.duelOps:checkIfCanEvolveInto(deckIndex, slot) then
      foundAnywhere = true
      local location = self.duelVars:get(self.c.DUELVARS_CARD_LOCATIONS + deckIndex)
      if location == self.c.CARD_LOCATION_HAND then
        return true, true
      end
    end
  end
  return false, foundAnywhere
end

-- AIDecide_ProfessorOak's `.general_logic` tail (from `.general_logic_got_
-- initial_score` onward), shared verbatim by the plain default-deck path,
-- WondersOfScience's own Grimer/Muk-miss fallthrough, and Excavation's
-- Mysterious-Fossil-scored entry -- all three reach this same scoring body,
-- differing only in `initialScore` (always 30 for the first two).
function AI:_decideProfessorOakGeneral(initialScore)
  local notInDeck = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)
  if notInDeck >= self.c.DECK_SIZE - 14 then return false end

  local score = initialScore
  local handCount = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  if handCount < 4 then score = score + 50 elseif handCount >= 9 then score = score - 30 end
  if #self:_energyCardsInHand() == 0 then score = score + 40 end

  -- Blastoise Lv52's Rain Dance power is neutralized by Muk's Toxic Gas;
  -- only encourage holding/drawing Water Energy when Rain Dance would work.
  local _, mukActive = self.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
  if not mukActive then
    local blastoiseCount = self.combat.status:countTurnDuelistPokemonWithActivePkmnPower(self.c.BLASTOISE)
    if blastoiseCount > 0 and not self:_findCardIDInHand(self.c.WATER_ENERGY) then
      score = score + 10
    end
  end

  -- Source bug: `cp TYPE_ENERGY; jr c, .loop_hand` skips every card whose
  -- type is BELOW TYPE_ENERGY (i.e. every Pokemon card), the opposite of the
  -- intended "skip Energy cards"; only Trainer/Energy cards' raw stage byte
  -- (never meaningfully BASIC for them) actually gets checked below.
  for _, deckIndex in ipairs(self.duelOps:createHandCardList()) do
    local row = self.cardData:get(self.cardData:getCardIDFromDeckIndex(deckIndex))
    if row and row.type >= self.c.TYPE_ENERGY and row.stage == self.c.BASIC then
      score = score + 10
    end
  end

  local foundEvolutionAnywhere, foundEvolutionInHand = false, false
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for slot = self.c.PLAY_AREA_ARENA, count - 1 do
    local inHand, anywhere = self:_lookForEvolutionForPlayArea(slot)
    if inHand then foundEvolutionInHand = true end
    if anywhere then foundEvolutionAnywhere = true end
  end
  if foundEvolutionAnywhere and not foundEvolutionInHand then score = score + 10 end

  return score >= 60
end

-- .HandleExcavationDeck:: same DECK_SIZE-14 gate as the general path, but the
-- initial score depends on whether Mysterious Fossil is already out (hand or
-- Play Area) -- already out means less urgency (30), missing means strong
-- encouragement to dig for it (80).
function AI:_decideProfessorOakExcavation(notInDeck)
  if notInDeck >= self.c.DECK_SIZE - 14 then return false end
  local initialScore = self:_cardIDInHandAndPlayArea(self.c.MYSTERIOUS_FOSSIL) and 30 or 80
  return self:_decideProfessorOakGeneral(initialScore)
end

-- .HandleWondersOfScienceDeck:: never play Oak while Grimer or Muk is
-- already in hand; otherwise falls through to the plain general path.
function AI:_decideProfessorOakWondersOfScience()
  if self:_cardIDInHand(self.c.GRIMER) or self:_cardIDInHand(self.c.MUK) then return false end
  return self:_decideProfessorOakGeneral(30)
end

-- .HandleLegendaryArticunoDeck:: with fewer than 3 Play Area Pokemon, first
-- checks whether any of them already has an evolution available in hand
-- (CheckForEvolutionInList against PLAY_AREA_ARENA's own evolve-this-turn
-- flag, not each slot's own -- see _checkForEvolutionInList); if NONE do,
-- play Oak immediately without the playable-cards check below. Otherwise
-- (>=3 Play Area Pokemon, or an in-hand evolution was found) falls into the
-- energy-count/hand-playability gate: >=4 Energy cards in hand cancels Oak
-- outright; else Oak is played only if every remaining hand card (both
-- Professor Oak copies excluded) is currently unplayable, meaning nothing of
-- value would be lost by discarding the whole hand.
function AI:_decideProfessorOakLegendaryArticuno()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if count < 3 then
    local hand = self.duelOps:createHandCardList()
    local foundEvolution = false
    for slot = self.c.PLAY_AREA_ARENA, count - 1 do
      local realDeckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
      local realCardId = self.cardData:getCardIDFromDeckIndex(realDeckIndex)
      if self:_checkForEvolutionInList(realCardId, hand) then
        foundEvolution = true
        break
      end
    end
    if not foundEvolution then return true end
  end

  if #self:_energyCardsInHand() >= 4 then return false end

  local filtered, removed = {}, 0
  for _, deckIndex in ipairs(self.duelOps:createHandCardList()) do
    if removed < 2 and self.cardData:getCardIDFromDeckIndex(deckIndex) == self.c.PROFESSOR_OAK then
      removed = removed + 1
    else
      filtered[#filtered + 1] = deckIndex
    end
  end

  for _, deckIndex in ipairs(filtered) do
    if self:_checkIfCardCanBePlayed(deckIndex) then return false end
  end
  return true
end

function AI:_decideProfessorOak()
  local notInDeck = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)
  if notInDeck >= self.c.DECK_SIZE - 6 then return false end

  local deckId = self.memory:readSymbol8("wOpponentDeckID")
  if deckId == self.c.LEGENDARY_ARTICUNO_DECK_ID then
    return self:_decideProfessorOakLegendaryArticuno()
  elseif deckId == self.c.EXCAVATION_DECK_ID then
    return self:_decideProfessorOakExcavation(notInDeck)
  elseif deckId == self.c.WONDERS_OF_SCIENCE_DECK_ID then
    return self:_decideProfessorOakWondersOfScience()
  end

  return self:_decideProfessorOakGeneral(30)
end

-- CheckIfNotEnoughEnergyToAttack:: true when neither attack currently has
-- enough Energy, or the second attack has enough but with surplus Energy
-- beyond its printed cost (stripping one Energy card wouldn't actually
-- disable an attack that has energy to spare).
function AI:_checkIfNotEnoughEnergyToAttack(slot)
  local need1 = self:checkEnergyNeededForAttack(slot, self.c.FIRST_ATTACK_OR_PKMN_POWER)
  if need1 and need1.enough then return false end
  local need2 = self:checkEnergyNeededForAttack(slot, self.c.SECOND_ATTACK)
  if not (need2 and need2.enough) then return true end
  local surplus = self:_surplusEnergyForAttack(slot, self.c.SECOND_ATTACK)
  return surplus ~= nil
end

-- .FindHighestDamagingAttack local from AIDecide_EnergyRemoval:: best of
-- both attacks' damage estimate for a Bench slot, ignoring usability
-- entirely (matches EstimateDamage_VersusDefendingCard's own usability-
-- blind behavior, same as _estimatePotentialKO's ignoreUsability use).
function AI:_findHighestDamagingBenchAttack(slot)
  local best = 0
  for _, attackIndex in ipairs({self.c.FIRST_ATTACK_OR_PKMN_POWER, self.c.SECOND_ATTACK}) do
    local estimate, err = self:_estimateDamageFromPlayArea(slot, attackIndex, { ignoreUsability = true })
    if not estimate then return nil, err end
    if estimate.damage > best then best = estimate.damage end
  end
  return best
end

-- AIDecide_EnergyRemoval:: picks a target in the Player's Play Area to
-- strip an Energy card from.
--
-- First, decide where to start scanning: if the AI's own Active can
-- already KO the Player's Active this turn and that attack is usable now
-- (or would become usable by playing Energy already in hand), the
-- Player's Active isn't worth stripping -- start from the Bench instead.
-- Otherwise start from the Player's Active card.
--
-- Scan from that point for the first card with Energy attached that
-- currently has enough Energy for either attack (stripping it would
-- disable an attack the Player could otherwise make right now).
--
-- If nothing qualifies, fall back to a Bench-only pass picking whichever
-- card (with Energy attached) has the single highest-damage attack
-- estimate, ignoring whether it currently has enough Energy.
--
-- A third fallback in the source -- re-checking the Player's Active card
-- specifically, only reached when the scan started from the Active -- is a
-- dead branch, not reimplemented: by the time it runs, the scan has always
-- already advanced past the Play Area's real slots to the first empty one,
-- so it probes an out-of-range Play Area location code (CARD_LOCATION_
-- PLAY_AREA | count) that no card is ever assigned (real location codes
-- are DECK=$00/HAND=$01/DISCARD_PILE=$02, all outside the Play Area
-- range), and so can never find Energy there.
function AI:_decideEnergyRemoval()
  local startFromBench = false
  local canKO, koAttack, koErr = self:checkIfAnyAttackKnocksOutDefendingCard(self.c.PLAY_AREA_ARENA)
  if canKO == nil then return nil, koAttack end
  if canKO then
    if self:_checkAttackUsableForAI(koAttack) then
      startFromBench = true
    else
      startFromBench = self:_lookForEnergyNeededInHand(self.c.PLAY_AREA_ARENA, koAttack) == true
    end
  end

  self.duelVars:swapTurn()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local startSlot = startFromBench and self.c.PLAY_AREA_BENCH_1 or self.c.PLAY_AREA_ARENA
  local pickedSlot
  for slot = startSlot, count - 1 do
    if self.duelOps:getPlayAreaCardAttachedEnergies(slot) > 0
        and not self:_checkIfNotEnoughEnergyToAttack(slot) then
      pickedSlot = slot
      break
    end
  end

  if not pickedSlot then
    local bestDamage, bestSlot = 0, nil
    for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
      if self.duelOps:getPlayAreaCardAttachedEnergies(slot) > 0 then
        local damage, err = self:_findHighestDamagingBenchAttack(slot)
        if damage == nil then
          self.duelVars:swapTurn()
          return nil, err
        end
        if damage > bestDamage then bestDamage, bestSlot = damage, slot end
      end
    end
    pickedSlot = bestSlot
  end

  if not pickedSlot then
    self.duelVars:swapTurn()
    return false
  end
  local energy = self:_pickAttachedEnergyToRemove(pickedSlot, false)
  self.duelVars:swapTurn()
  if not energy then return false end
  return true, { opponentPlayArea = pickedSlot, opponentEnergyDeckIndex = energy }
end


function AI:_basicEnergyCardsAtLocation(location)
  local out = {}
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    if self.duelVars:get(deckIndex) == location then
      local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
      local row = self.cardData:get(cardId)
      if row and row.type >= self.c.TYPE_ENERGY and row.type < self.c.TYPE_TRAINER
          and cardId ~= self.c.DOUBLE_COLORLESS_ENERGY then
        out[#out + 1] = deckIndex
      end
    end
  end
  return out
end

function AI:_energyIsUsefulForPokemon(energyDeckIndex, pokemonCardId, pokemonType)
  local energyId = self.cardData:getCardIDFromDeckIndex(energyDeckIndex)
  if energyId == self.c.DOUBLE_COLORLESS_ENERGY then return true end
  if pokemonType == self.c.TYPE_PKMN_COLORLESS then return true end
  if pokemonCardId == self.c.EXEGGCUTE or pokemonCardId == self.c.EXEGGUTOR
      or pokemonCardId == self.c.PSYDUCK or pokemonCardId == self.c.GOLDUCK then
    if energyId == self.c.PSYCHIC_ENERGY then return true end
  end
  if pokemonCardId == self.c.SURFING_PIKACHU_LV13
      or pokemonCardId == self.c.SURFING_PIKACHU_ALT_LV13 then
    if energyId == self.c.WATER_ENERGY then return true end
  end
  if pokemonCardId == self.c.EEVEE and (energyId == self.c.WATER_ENERGY
      or energyId == self.c.FIRE_ENERGY or energyId == self.c.LIGHTNING_ENERGY) then
    return true
  end
  return energyId == self:_energyCardIdForColor(pokemonType)
end

function AI:_rainDanceRetrievalAllowed()
  if self.memory:readSymbol8("wOpponentDeckID") ~= self.c.GO_GO_RAIN_DANCE_DECK_ID then
    return true
  end
  local _, muk = self.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
  if muk then return true end
  local _, blastoise = self.combat.status:countTurnDuelistPokemonWithActivePkmnPower(self.c.BLASTOISE)
  return blastoise
end

function AI:_pickUsefulBasicEnergiesFromDiscard(limit)
  local available = self:_basicEnergyCardsAtLocation(self.c.CARD_LOCATION_DISCARD_PILE)
  local picked = {}
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for slot = self.c.PLAY_AREA_ARENA, count - 1 do
    local _, cardId, row = self:_cardAtPlayArea(slot, false)
    if row then
      for i, deckIndex in ipairs(available) do
        if self:_energyIsUsefulForPokemon(deckIndex, cardId, row.type) then
          picked[#picked + 1] = deckIndex
          table.remove(available, i)
          break
        end
      end
      if #picked >= limit then return picked end
    end
  end
  while #picked < limit and #available > 0 do
    picked[#picked + 1] = table.remove(available, 1)
  end
  return picked
end

-- AIDecide_EnergyRetrieval:: play only when the AI currently has no Energy in
-- hand, can discard a duplicate, and can recover at least one Basic Energy.
-- Useful Energy is chosen first, one per Pokemon in Play Area, then remaining
-- discard-pile Basic Energy is consumed in deck-index order.
function AI:_decideEnergyRetrieval(currentTrainerDeckIndex)
  if #self:_energyCardsInHand() ~= 0 then return false end
  if not self:_rainDanceRetrievalAllowed() then return false end
  local hand = self.duelOps:createHandCardList()
  local discardFromHand = self:_findDuplicateCard(hand)
  if not discardFromHand then return false end
  local energies = self:_pickUsefulBasicEnergiesFromDiscard(2)
  if #energies == 0 then return false end
  return true, { handDiscards = { discardFromHand }, discardBasicEnergies = energies }
end

-- AIDecide_SuperEnergyRetrieval:: same source priority as Energy Retrieval,
-- but requires two independently found duplicates and recovers up to four
-- Basic Energy cards.
function AI:_decideSuperEnergyRetrieval(currentTrainerDeckIndex)
  if #self:_energyCardsInHand() ~= 0 then return false end
  if not self:_rainDanceRetrievalAllowed() then return false end
  local hand = self.duelOps:createHandCardList()
  local first = self:_findDuplicateCard(hand)
  if not first then return false end
  hand = self:_cardListWithout(hand, first)
  local second = self:_findDuplicateCard(hand)
  if not second then return false end
  local energies = self:_pickUsefulBasicEnergiesFromDiscard(4)
  if #energies == 0 then return false end
  return true, { handDiscards = { first, second }, discardBasicEnergies = energies }
end

function AI:_findCardIDInDeck(cardId)
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    if self.duelVars:get(deckIndex) == self.c.CARD_LOCATION_DECK
        and self.cardData:getCardIDFromDeckIndex(deckIndex) == cardId then
      return deckIndex
    end
  end
  return nil
end

function AI:_cardIDInHand(cardId)
  return self:_findCardIDInHand(cardId) ~= nil
end

function AI:_cardIDInHandAndPlayArea(cardId)
  if self:_cardIDInHand(cardId) then return true end
  return self:_findCardIDInPlayArea(cardId, self.c.PLAY_AREA_ARENA) ~= 0xff
end

function AI:_pokeBallGivenCardInHandAndPlayArea(wantedCardId, prerequisiteCardId)
  local found = self:_findCardIDInDeck(wantedCardId)
  if not found then return nil end
  if not self:_cardIDInHandAndPlayArea(prerequisiteCardId) then return nil end
  if self:_cardIDInHandAndPlayArea(wantedCardId) then return nil end
  return found
end

function AI:_pokeBallGivenCardInHand(wantedCardId, prerequisiteCardId)
  local found = self:_findCardIDInDeck(wantedCardId)
  if not found then return nil end
  if not self:_cardIDInHand(prerequisiteCardId) then return nil end
  if self:_cardIDInHandAndPlayArea(wantedCardId) then return nil end
  return found
end

-- AIDecide_Pokeball:: only the source-listed decks use Poke Ball.  Each branch
-- retains its exact card-priority order and redundancy checks; other decks
-- return no-carry rather than inventing a generic Pokemon search policy.
function AI:_decidePokeBall()
  local deckId = self.memory:readSymbol8("wOpponentDeckID")
  local function firstInDeck(ids)
    for _, cardId in ipairs(ids) do
      local deckIndex = self:_findCardIDInDeck(cardId)
      if deckIndex then return true, { deckPokemon = deckIndex } end
    end
    return false
  end
  if deckId == self.c.FIRE_CHARGE_DECK_ID then
    return firstInDeck({ self.c.CHANSEY, self.c.TAUROS, self.c.JIGGLYPUFF_LV12 })
  elseif deckId == self.c.HARD_POKEMON_DECK_ID then
    return firstInDeck({ self.c.RHYHORN, self.c.RHYDON, self.c.ONIX })
  elseif deckId == self.c.PIKACHU_DECK_ID then
    return firstInDeck({ self.c.PIKACHU_LV14, self.c.PIKACHU_LV16,
      self.c.PIKACHU_ALT_LV16, self.c.PIKACHU_LV12, self.c.FLYING_PIKACHU })
  elseif deckId == self.c.ETCETERA_DECK_ID then
    local groups = {
      { self.c.FIRE_ENERGY, { self.c.CHARMANDER, self.c.MAGMAR_LV31 } },
      { self.c.LIGHTNING_ENERGY, { self.c.PIKACHU_LV12, self.c.MAGNEMITE_LV13 } },
      { self.c.FIGHTING_ENERGY, { self.c.DIGLETT, self.c.MACHOP } },
      { self.c.PSYCHIC_ENERGY, { self.c.GASTLY_LV8, self.c.JYNX } },
    }
    for _, group in ipairs(groups) do
      local energyId, ids = group[1], group[2]
      if self:_cardIDInHand(energyId) and not self:_cardIDInHand(ids[1])
          and not self:_cardIDInHand(ids[2]) then
        local result = self:_findCardIDInDeck(ids[1]) or self:_findCardIDInDeck(ids[2])
        if result then return true, { deckPokemon = result } end
      end
    end
    return false
  elseif deckId == self.c.LOVELY_NIDORAN_DECK_ID then
    local checks = {
      { "play", self.c.NIDORINO, self.c.NIDORANM },
      { "play", self.c.NIDOKING, self.c.NIDORINO },
      { "hand", self.c.NIDORANM, self.c.NIDORINO },
      { "hand", self.c.NIDORINO, self.c.NIDOKING },
      { "play", self.c.NIDORINA, self.c.NIDORANF },
      { "play", self.c.NIDOQUEEN, self.c.NIDORINA },
      { "hand", self.c.NIDORANF, self.c.NIDORINA },
      { "hand", self.c.NIDORINA, self.c.NIDOQUEEN },
    }
    for _, check in ipairs(checks) do
      local result
      if check[1] == "play" then
        result = self:_pokeBallGivenCardInHandAndPlayArea(check[2], check[3])
      else
        result = self:_pokeBallGivenCardInHand(check[2], check[3])
      end
      if result then return true, { deckPokemon = result } end
    end
  end
  return false
end

function AI:_hasBasicEnergyAttached(slot)
  local count = self.duelOps:createArenaOrBenchEnergyCardList(slot)
  local base, bank = self.memory:address("wDuelTempList")
  for i = 0, count - 1 do
    local deckIndex = self.memory:read8("wram", base + i, bank)
    if self.cardData:getCardIDFromDeckIndex(deckIndex) ~= self.c.DOUBLE_COLORLESS_ENERGY then
      return true
    end
  end
  return false
end

function AI:_pickEnergyCardToDiscard(slot)
  local count = self.duelOps:createArenaOrBenchEnergyCardList(slot)
  if count == 0 then return nil end
  local _, cardId, row = self:_cardAtPlayArea(slot, false)
  local base, bank = self.memory:address("wDuelTempList")
  local first
  for i = 0, count - 1 do
    local deckIndex = self.memory:read8("wram", base + i, bank)
    first = first or deckIndex
    if not self:_energyIsUsefulForPokemon(deckIndex, cardId, row.type) then return deckIndex end
  end
  return first
end

function AI:_pickTwoAttachedEnergyCards(slot)
  local count = self.duelOps:createArenaOrBenchEnergyCardList(slot)
  if count < 2 then return nil end
  local base, bank = self.memory:address("wDuelTempList")
  local list = {}
  for i = 0, count - 1 do list[#list + 1] = self.memory:read8("wram", base + i, bank) end
  local _, cardId, row = self:_cardAtPlayArea(slot, false)
  local first
  for _, deckIndex in ipairs(list) do
    if self.cardData:getCardIDFromDeckIndex(deckIndex) == self.c.DOUBLE_COLORLESS_ENERGY then
      if first then return { first, deckIndex } end
      first = deckIndex
    end
  end
  for _, deckIndex in ipairs(list) do
    if self:_energyIsUsefulForPokemon(deckIndex, cardId, row.type) then
      if first then
        -- Preserve PickTwoAttachedEnergyCards' source quirk: when exactly one
        -- DCE was chosen above, the useful-energy pass may select it again.
        return { first, deckIndex }
      end
      first = deckIndex
    end
  end
  if first then
    for _, deckIndex in ipairs(list) do if deckIndex ~= first then return { first, deckIndex } end end
  end
  return { list[1], list[2] }
end

function AI:_attackEnergySurplus(slot, attackIndex)
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
  if deckIndex == 0xff then return 0 end
  local _, attack = self.combat:loadAttack(deckIndex, attackIndex)
  self.duelOps:getPlayAreaCardAttachedEnergies(slot)
  local total = self.memory:readSymbol8("wTotalAttachedEnergies")
  local required = 0
  for color = 0, self.c.NUM_TYPES - 1 do required = required + (attack.energy[color] or 0) end
  return math.max(0, total - required)
end

function AI:_superRemovalTargetCanAttack(slot)
  local total = self.duelOps:getPlayAreaCardAttachedEnergies(slot)
  local cardCount = self.duelOps:createArenaOrBenchEnergyCardList(slot)
  if total < 2 or cardCount < 2 then return false end
  local first = self:checkEnergyNeededForAttack(slot, self.c.FIRST_ATTACK_OR_PKMN_POWER)
  if first and first.enough then return true end
  local second = self:checkEnergyNeededForAttack(slot, self.c.SECOND_ATTACK)
  if not second or not second.enough then return false end
  return self:_attackEnergySurplus(slot, self.c.SECOND_ATTACK) < 2
end

function AI:_activeCanKONowOrWithHandEnergy()
  return self:_canKnockOutNowOrWithHandEnergy(self.c.PLAY_AREA_ARENA)
end

-- AIDecide_SuperEnergyRemoval:: source target policy.  The discard cost is
-- taken from the first Benched AI Pokemon carrying a Basic Energy.  If the AI
-- can KO the current defender now (or after its pending Energy attachment), the
-- opponent Active is skipped; otherwise it is considered before the Bench.
function AI:_decideSuperEnergyRemoval()
  local ownCount = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local ownSlot
  for slot = self.c.PLAY_AREA_BENCH_1, ownCount - 1 do
    if self:_hasBasicEnergyAttached(slot) then ownSlot = slot; break end
  end
  if ownSlot == nil then return false end

  local canKO, koErr = self:_activeCanKONowOrWithHandEnergy()
  if canKO == nil then return nil, koErr end
  self.duelVars:swapTurn()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local start = canKO and self.c.PLAY_AREA_BENCH_1 or self.c.PLAY_AREA_ARENA
  local firstEligible
  for slot = start, count - 1 do
    if self:_superRemovalTargetCanAttack(slot) then firstEligible = slot; break end
  end
  if firstEligible == nil then self.duelVars:swapTurn(); return false end

  local target = firstEligible
  if target ~= self.c.PLAY_AREA_ARENA then
    local bestDamage, bestSlot = 0, nil
    for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
      if self:_superRemovalTargetCanAttack(slot) then
        for attackIndex = self.c.FIRST_ATTACK_OR_PKMN_POWER, self.c.SECOND_ATTACK do
          local estimate, err = self:_estimateDamageFromPlayArea(slot, attackIndex)
          if not estimate then self.duelVars:swapTurn(); return nil, err end
          if estimate.damage > bestDamage then bestDamage, bestSlot = estimate.damage, slot end
        end
      end
    end
    target = bestSlot
  end
  if target == nil then self.duelVars:swapTurn(); return false end
  local opponentEnergies = self:_pickTwoAttachedEnergyCards(target)
  self.duelVars:swapTurn()
  if not opponentEnergies then return false end
  local ownEnergy = self:_pickEnergyCardToDiscard(ownSlot)
  if not ownEnergy then return false end
  return true, {
    ownPlayArea = ownSlot,
    ownEnergyDeckIndex = ownEnergy,
    opponentPlayArea = target,
    opponentEnergyDeckIndexes = opponentEnergies,
  }
end

function AI:_canArenaCardUseNonResidualAttack()
  for attackIndex = self.c.FIRST_ATTACK_OR_PKMN_POWER, self.c.SECOND_ATTACK do
    local usable, reason = self:_checkAttackUsableForAI(attackIndex)
    if usable then
      local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
      local _, attack = self.combat:loadAttack(deckIndex, attackIndex)
      if bit.band(attack.category, self.c.RESIDUAL) == 0 then return true end
    elseif reason and reason:match("^untranslated_effect:") then
      return nil, reason
    end
  end
  return false
end

function AI:_withNonTurnArenaCard(slot, fn)
  self.duelVars:swapTurn()
  local oldCard = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local oldHP = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP)
  self.duelVars:set(self.c.DUELVARS_ARENA_CARD, self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot))
  self.duelVars:set(self.c.DUELVARS_ARENA_CARD_HP, self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot))
  self.duelVars:swapTurn()
  local ok, a, b, c = pcall(fn)
  self.duelVars:swapTurn()
  self.duelVars:set(self.c.DUELVARS_ARENA_CARD, oldCard)
  self.duelVars:set(self.c.DUELVARS_ARENA_CARD_HP, oldHP)
  self.duelVars:swapTurn()
  if not ok then error(a) end
  return a, b, c
end

function AI:_gustCanDamageCurrentDefender()
  return self:_canDamageDefendingPokemon(self.c.PLAY_AREA_ARENA)
end

function AI:_gustBenchWeaknessTarget(colorMask)
  self.duelVars:swapTurn()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  self.duelVars:swapTurn()
  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local _, _, row = self:_cardAtPlayArea(slot, true)
    if row and bit.band(row.weakness or 0, colorMask) ~= 0 then
      local canDamage, err = self:_withNonTurnArenaCard(slot, function()
        return self:_gustCanDamageCurrentDefender()
      end)
      if canDamage == nil then return nil, err end
      if canDamage then return slot end
    end
  end
  return false
end

function AI:_gustBenchKOTarget()
  self.duelVars:swapTurn()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  self.duelVars:swapTurn()
  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local found, err = self:_withNonTurnArenaCard(slot, function()
      local canKO, attackIndex = self:checkIfAnyAttackKnocksOutDefendingCard(self.c.PLAY_AREA_ARENA)
      if canKO == nil then return nil, attackIndex end
      if not canKO then return false end
      local usable, reason = self:_checkAttackUsableForAI(attackIndex)
      if usable then return true end
      if reason and reason:match("^untranslated_effect:") then return nil, reason end
      return self:_lookForEnergyNeededInHand(self.c.PLAY_AREA_ARENA, attackIndex)
    end)
    if found == nil then return nil, err end
    if found then return slot end
  end
  return false
end

function AI:_gustNoAttackDealsDamage()
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  for attackIndex = self.c.FIRST_ATTACK_OR_PKMN_POWER, self.c.SECOND_ATTACK do
    local _, attack = self.combat:loadAttack(deckIndex, attackIndex)
    if attack.category ~= self.c.POKEMON_POWER and attack.damage ~= 0 then
      local estimate, err = self:estimateDamageVersusDefendingCard(attackIndex)
      if not estimate then return nil, err end
      if estimate.max ~= 0 then return false end
    end
  end
  return true
end

-- AIDecide_GustOfWind:: preserves source priority: immediate Bench KO, Bench
-- weakness, zero-Energy damageable Bench target, then the lowest-HP damageable
-- Bench target.  Mew Lv23/Mewtwo Lv53 and an already-used Gust are skipped.
function AI:_decideGustOfWind()
  self.duelVars:swapTurn()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  self.duelVars:swapTurn()
  if count <= 1 then return false end
  if self.c.AI_FLAG_USED_GUST_OF_WIND and bit.band(self.memory:readSymbol8("wPreviousAIFlags"),
      self.c.AI_FLAG_USED_GUST_OF_WIND) ~= 0 then return false end

  local nonResidual, nrErr = self:_canArenaCardUseNonResidualAttack()
  if nonResidual == nil then return nil, nrErr end
  if not nonResidual then return false end

  local currentKO, attackIndex = self:checkIfAnyAttackKnocksOutDefendingCard(self.c.PLAY_AREA_ARENA)
  if currentKO == nil then return nil, attackIndex end
  if currentKO then
    local usable, reason = self:_checkAttackUsableForAI(attackIndex)
    if usable then return false end
    if reason and reason:match("^untranslated_effect:") then return nil, reason end
    if self:_lookForEnergyNeededInHand(self.c.PLAY_AREA_ARENA, attackIndex) then return false end
  end

  local _, activeId, active = self:_cardAtPlayArea(self.c.PLAY_AREA_ARENA, false)
  if activeId == self.c.MEW_LV23 or activeId == self.c.MEWTWO_LV53 then return false end

  local koTarget, koErr = self:_gustBenchKOTarget()
  if koTarget == nil then return nil, koErr end
  if koTarget then return true, { opponentBench = koTarget } end

  local noDamage, noDamageErr = self:_gustNoAttackDealsDamage()
  if noDamage == nil then return nil, noDamageErr end
  local colorMask = wrMask(active.type)
  if not noDamage then
    local _, _, defender = self:_cardAtPlayArea(self.c.PLAY_AREA_ARENA, true)
    if defender and bit.band(defender.weakness or 0, colorMask) ~= 0 then return false end
    local weakTarget, weakErr = self:_gustBenchWeaknessTarget(colorMask)
    if weakTarget == nil then return nil, weakErr end
    if weakTarget then return true, { opponentBench = weakTarget } end
    return false
  end

  local weakTarget, weakErr = self:_gustBenchWeaknessTarget(colorMask)
  if weakTarget == nil then return nil, weakErr end
  if weakTarget then return true, { opponentBench = weakTarget } end

  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    self.duelVars:swapTurn()
    local attached = self.duelOps:getPlayAreaCardAttachedEnergies(slot)
    self.duelVars:swapTurn()
    if attached == 0 then
      local canDamage, err = self:_withNonTurnArenaCard(slot, function()
        return self:_gustCanDamageCurrentDefender()
      end)
      if canDamage == nil then return nil, err end
      if canDamage then return true, { opponentBench = slot } end
    end
  end

  local bestHP, bestSlot = 0xff, nil
  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    self.duelVars:swapTurn()
    local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
    self.duelVars:swapTurn()
    if hp < bestHP then
      local canDamage, err = self:_withNonTurnArenaCard(slot, function()
        return self:_gustCanDamageCurrentDefender()
      end)
      if canDamage == nil then return nil, err end
      if canDamage then bestHP, bestSlot = hp, slot end
    end
  end
  if bestSlot then return true, { opponentBench = bestSlot } end
  return false
end

function AI:_decideTrainer(constantName, phase, currentTrainerDeckIndex)
  if constantName == "BILL" then
    return self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK) < self.c.DECK_SIZE - 9
  elseif constantName == "POTION" then
    return self:_decidePotion(phase)
  elseif constantName == "SUPER_POTION" then
    return self:_decideSuperPotion(phase)
  elseif constantName == "DEFENDER" then
    return self:_decideDefender(phase)
  elseif constantName == "PLUSPOWER" then
    return self:_decidePlusPower(phase)
  elseif constantName == "SWITCH" then
    return self:_decideSwitch()
  elseif constantName == "FULL_HEAL" then
    return self:_decideFullHeal()
  elseif constantName == "ENERGY_SEARCH" then
    return self:_decideEnergySearch()
  elseif constantName == "PROFESSOR_OAK" then
    return self:_decideProfessorOak()
  elseif constantName == "ENERGY_REMOVAL" then
    return self:_decideEnergyRemoval()
  elseif constantName == "ENERGY_RETRIEVAL" then
    return self:_decideEnergyRetrieval(currentTrainerDeckIndex)
  elseif constantName == "SUPER_ENERGY_RETRIEVAL" then
    return self:_decideSuperEnergyRetrieval(currentTrainerDeckIndex)
  elseif constantName == "SUPER_ENERGY_REMOVAL" then
    return self:_decideSuperEnergyRemoval()
  elseif constantName == "GUST_OF_WIND" then
    return self:_decideGustOfWind()
  elseif constantName == "POKE_BALL" then
    return self:_decidePokeBall()
  elseif constantName == "POKEDEX" then
    return self:_decidePokedex()
  elseif constantName == "RECYCLE" then
    return self:_decideRecycle()
  elseif constantName == "MAINTENANCE" then
    return self:_decideMaintenance(currentTrainerDeckIndex)
  elseif constantName == "ITEM_FINDER" then
    return self:_decideItemFinder(currentTrainerDeckIndex)
  elseif constantName == "REVIVE" then
    return self:_decideRevive()
  elseif constantName == "POKEMON_FLUTE" then
    return self:_decidePokemonFlute()
  elseif constantName == "POKEMON_CENTER" then
    return self:_decidePokemonCenter()
  elseif constantName == "MR_FUJI" then
    return self:_decideMrFuji()
  elseif constantName == "POKEMON_BREEDER" then
    return self:_decidePokemonBreeder()
  elseif constantName == "IMPOSTER_PROFESSOR_OAK" then
    return self:_decideImposterProfessorOak()
  elseif constantName == "SCOOP_UP" then
    return self:_decideScoopUp()
  elseif constantName == "LASS" then
    return self:_decideLass()
  elseif constantName == "IMAKUNI_CARD" then
    return self:_decideImakuni()
  elseif constantName == "GAMBLER" then
    return self:_decideGambler()
  elseif constantName == "CLEFAIRY_DOLL" or constantName == "MYSTERIOUS_FOSSIL" then
    return self:_decideClefairyDollOrMysteriousFossil()
  elseif constantName == "COMPUTER_SEARCH" then
    return self:_decideComputerSearch(currentTrainerDeckIndex)
  elseif constantName == "POKEMON_TRADER" then
    return self:_decidePokemonTrader()
  end
  return nil, "untranslated_ai_trainer:" .. constantName
end

function AI:_playTrainerForAI(constantName, selection, parameter)
  local cardId = self.c[constantName]
  local ok, reason
  if constantName == "GAMBLER" then
    ok, reason = self:_playGamblerWithRNGCheat(cardId, selection)
  else
    ok, reason = self.playerActions:playTrainer(cardId, selection)
  end
  if not ok then return nil, reason end
  if constantName == "SWITCH" then self:_setPreviousAIFlag(self.c.AI_FLAG_USED_SWITCH) end
  if constantName == "GUST_OF_WIND" then self:_setPreviousAIFlag(self.c.AI_FLAG_USED_GUST_OF_WIND) end
  if constantName == "PLUSPOWER" then
    self:_setPreviousAIFlag(self.c.AI_FLAG_USED_PLUSPOWER)
    if parameter ~= nil then self.memory:writeSymbol8("wAIPlusPowerAttack", parameter) end
  end
  if constantName == "PROFESSOR_OAK" then
    self:_setPreviousAIFlag(bit.bor(self.c.AI_FLAG_USED_PROFESSOR_OAK or 0,
      self.c.AI_FLAG_MODIFIED_HAND or 0))
  end
  if constantName == "MAINTENANCE" or constantName == "ITEM_FINDER"
      or constantName == "ENERGY_RETRIEVAL" or constantName == "SUPER_ENERGY_RETRIEVAL"
      or constantName == "LASS" or constantName == "GAMBLER" or constantName == "COMPUTER_SEARCH" then
    self:_setPreviousAIFlag(self.c.AI_FLAG_MODIFIED_HAND)
  end
  return true
end

local AI_TRAINER_PHASES = {
  [1] = { "IMAKUNI_CARD", "GAMBLER" },
  [2] = { "MAINTENANCE", "POKE_BALL", "COMPUTER_SEARCH", "POKEMON_TRADER" },
  [3] = { "POKEDEX", "RECYCLE" },
  [4] = { "BILL", "ITEM_FINDER" },
  [5] = { "ENERGY_REMOVAL", "SUPER_ENERGY_REMOVAL", "REVIVE",
    "CLEFAIRY_DOLL", "MYSTERIOUS_FOSSIL" },
  [6] = { "POKEMON_CENTER" },
  [7] = { "POTION", "GUST_OF_WIND", "POKEMON_BREEDER",
    "IMPOSTER_PROFESSOR_OAK", "FULL_HEAL" },
  [8] = { "SUPER_POTION" },
  [9] = { "SWITCH" },
  [10] = { "POTION", "GUST_OF_WIND", "ENERGY_RETRIEVAL", "MR_FUJI", "SCOOP_UP" },
  [11] = { "SUPER_POTION", "SUPER_ENERGY_RETRIEVAL" },
  [12] = { "ENERGY_SEARCH" },
  [13] = { "DEFENDER", "PLUSPOWER", "LASS", "POKEMON_FLUTE" },
  [14] = { "DEFENDER", "PLUSPOWER" },
  [15] = { "PROFESSOR_OAK" },
}

-- AITrainerCardLogic is keyed by (phase, cardID) pairs; membership per phase
-- exactly mirrors AI_TRAINER_PHASES above (verified against the decomp's own
-- data/duel/ai_trainer_card_logic.asm table), so the per-phase name sets
-- double as that membership test.
local AI_TRAINER_PHASE_SET = {}
local AI_TRAINER_CARD_NAMES = {}
for phase, names in pairs(AI_TRAINER_PHASES) do
  local set = {}
  for _, name in ipairs(names) do
    set[name] = true
    AI_TRAINER_CARD_NAMES[name] = true
  end
  AI_TRAINER_PHASE_SET[phase] = set
end

-- Keep unsupported Trainer policies fail-closed instead of allowing the
-- random skip gate to hide an untranslated branch.
local AI_TRAINER_SUPPORTED = {
  BILL = true, POTION = true, DEFENDER = true, PLUSPOWER = true, SWITCH = true,
  FULL_HEAL = true, ENERGY_SEARCH = true, PROFESSOR_OAK = true, ENERGY_REMOVAL = true,
  POKEDEX = true, RECYCLE = true, MAINTENANCE = true, ITEM_FINDER = true, REVIVE = true,
  POKEMON_FLUTE = true, POKEMON_CENTER = true, MR_FUJI = true, ENERGY_RETRIEVAL = true,
  SUPER_ENERGY_RETRIEVAL = true, SUPER_ENERGY_REMOVAL = true, GUST_OF_WIND = true,
  POKE_BALL = true, SUPER_POTION = true, POKEMON_BREEDER = true,
  IMPOSTER_PROFESSOR_OAK = true, SCOOP_UP = true, LASS = true, IMAKUNI_CARD = true,
  GAMBLER = true, CLEFAIRY_DOLL = true, MYSTERIOUS_FOSSIL = true, COMPUTER_SEARCH = true,
  POKEMON_TRADER = true,
}

-- CardID -> AI_TRAINER_PHASES constant name. Built lazily since it depends on
-- the generated constants table, and cached since that table never changes
-- for the lifetime of an AI instance.
function AI:_trainerConstantNameForCardID(cardId)
  if not self._trainerCardIdToName then
    local map = {}
    for name in pairs(AI_TRAINER_CARD_NAMES) do
      local id = self.c[name]
      if id then map[id] = name end
    end
    self._trainerCardIdToName = map
  end
  return self._trainerCardIdToName[cardId]
end

-- _AIProcessHandTrainerCards:: takes one hand snapshot per pass and walks it
-- in HAND order (not this file's authoring order), matching the source's own
-- CreateHandCardList-then-scan structure rather than a fixed per-phase name
-- priority. For each snapshotted card that maps to this phase, the source
-- runs CheckCantUseTrainerDueToEffect and the card's own EFFECTCMDTYPE_
-- INITIAL_EFFECT_1 gate BEFORE AIChooseRandomlyNotToDoAction and the card-
-- specific AIDecide_* routine -- not only as validation once PlayerActions:
-- playTrainer executes it. A successful play that leaves AI_FLAG_MODIFIED_
-- HAND set in wPreviousAIFlags forces a fresh snapshot and restarts from the
-- top (clearing the flag); otherwise the scan just continues to the next
-- snapshot position. SWITCH additionally never matches once AI_FLAG_USED_
-- SWITCH is already set, mirroring the table scan's own per-row skip.
function AI:processHandTrainerCards(phase)
  assert(self.playerActions, "general AI requires PlayerActions")
  assert(self.combat, "general AI requires Combat")
  local phaseSet = AI_TRAINER_PHASE_SET[phase]
  if not phaseSet then return true end

  local snapshot = self.duelOps:createHandCardList()
  local pos = 1
  while pos <= #snapshot do
    local deckIndex = snapshot[pos]
    local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
    local constantName = self:_trainerConstantNameForCardID(cardId)
    local matches = constantName ~= nil and phaseSet[constantName]
    if matches and constantName == "SWITCH" and self.c.AI_FLAG_USED_SWITCH
        and bit.band(self.memory:readSymbol8("wPreviousAIFlags"), self.c.AI_FLAG_USED_SWITCH) ~= 0 then
      matches = false
    end

    if not matches then
      pos = pos + 1
    else
      if not AI_TRAINER_SUPPORTED[constantName] then
        return nil, "untranslated_ai_trainer:" .. constantName
      end

      if self.combat.status:checkCantUseTrainerDueToEffect() then
        pos = pos + 1
      else
        self.playerActions.effects:loadNonPokemonCardEffectCommands(deckIndex, self.cardData)
        local carry, err = self.playerActions.effects:tryExecute(
          self.c.EFFECTCMDTYPE_INITIAL_EFFECT_1, { playerActions = self.playerActions })
        if carry == nil then return nil, err end

        if carry then
          pos = pos + 1
        elseif self:_chooseRandomlyNotToDoAction() then
          pos = pos + 1
        else
          local decision, selectionOrErr, parameter = self:_decideTrainer(constantName, phase, deckIndex)
          if decision == nil then return nil, selectionOrErr end
          if not decision then
            pos = pos + 1
          else
            local played, playErr = self:_playTrainerForAI(constantName, selectionOrErr, parameter)
            if not played then return nil, playErr end

            local modified = bit.band(self.memory:readSymbol8("wPreviousAIFlags"),
              self.c.AI_FLAG_MODIFIED_HAND or 0) ~= 0
            if modified then
              self.memory:writeSymbol8("wPreviousAIFlags",
                bit.band(self.memory:readSymbol8("wPreviousAIFlags"),
                  bit.bnot(self.c.AI_FLAG_MODIFIED_HAND or 0)))
              snapshot = self.duelOps:createHandCardList()
              pos = 1
            else
              pos = pos + 1
            end
          end
        end
      end
    end
  end
  return true
end


function AI:_grassEnergyAttached(slot)
  local wanted = bit.bor(self.c.CARD_LOCATION_PLAY_AREA, slot)
  local out = {}
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    if self.duelVars:get(deckIndex) == wanted
        and self.cardData:getCardIDFromDeckIndex(deckIndex) == self.c.GRASS_ENERGY then
      out[#out + 1] = deckIndex
    end
  end
  return out
end

function AI:_transferAttachedEnergy(deckIndex, targetSlot)
  self.duelOps:addCardToHand(deckIndex)
  self.duelOps:putHandCardInPlayArea(deckIndex, targetSlot)
  self:_event("ai_energy_trans", { deckIndex = deckIndex, target = targetSlot })
end

function AI:_energyTransPowerSlot()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for slot = count - 1, self.c.PLAY_AREA_ARENA, -1 do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
    if deckIndex ~= 0xff and self.cardData:getCardIDFromDeckIndex(deckIndex) == self.c.VENUSAUR_LV67 then
      return slot, deckIndex
    end
  end
  return nil
end

function AI:_bestBenchEnergyTransTarget()
  return self:_previewBenchEnergyTargetSkipEvolution()
end

-- HandleAIEnergyTrans:: common Venusaur Lv67 policy. Transfer-to-Bench uses
-- the same Bench-only Energy preview as the cartridge, including its initial
-- viability pass and a fresh score pass before every transferred Grass Energy.
function AI:handleAIEnergyTrans(mode)
  if self:_chooseRandomlyNotToDoAction() then return false end
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if count < 2 then return false end
  local powerSlot = self:_energyTransPowerSlot()
  if powerSlot == nil then return false end
  local _, muk = self.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
  if muk then return false end

  if mode == "attack" then
    local arenaIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
    local arenaId = self.cardData:getCardIDFromDeckIndex(arenaIndex)
    local benchGrass = {}
    for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
      for _, deckIndex in ipairs(self:_grassEnergyAttached(slot)) do benchGrass[#benchGrass + 1] = deckIndex end
    end
    if #benchGrass == 0 then return false end
    local needed
    if arenaId == self.c.EXEGGUTOR then
      needed = #benchGrass
    else
      local need = self:checkEnergyNeededForAttack(self.c.PLAY_AREA_ARENA, self.c.SECOND_ATTACK)
      if not need or need.enough then return false end
      if need.colorless > 0 then needed = need.colorless
      elseif need.colored > 0 and need.energyCardId == self.c.GRASS_ENERGY then needed = need.colored
      else return false end
    end
    if #benchGrass < needed then return false end
    for i = 1, needed do self:_transferAttachedEnergy(benchGrass[i], self.c.PLAY_AREA_ARENA) end
    return true
  elseif mode == "retreat" then
    local cost = self:getPlayAreaCardRetreatCost(self.c.PLAY_AREA_ARENA)
    local attached = self.duelOps:getPlayAreaCardAttachedEnergies(self.c.PLAY_AREA_ARENA)
    local needed = cost - attached
    if needed <= 0 then return false end
    local benchGrass = {}
    for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
      for _, deckIndex in ipairs(self:_grassEnergyAttached(slot)) do benchGrass[#benchGrass + 1] = deckIndex end
    end
    if #benchGrass < needed then return false end
    for i = 1, needed do self:_transferAttachedEnergy(benchGrass[i], self.c.PLAY_AREA_ARENA) end
    return true
  elseif mode == "to_bench" then
    local exact, err = self:checkIfDefendingPokemonCanKnockOut()
    if exact == nil then return nil, err end
    if not exact then return false end
    local selected, scoreOrErr = self:_bestAttackChoice()
    if selected == nil then return nil, scoreOrErr end
    if scoreOrErr >= 0x50 then return false end
    local arenaGrass = self:_grassEnergyAttached(self.c.PLAY_AREA_ARENA)
    if #arenaGrass == 0 then return false end
    local previewTarget, previewErr = self:_bestBenchEnergyTransTarget()
    if previewTarget == nil then
      if previewErr then return nil, previewErr end
      return false
    end
    local moved = false
    for _, deckIndex in ipairs(arenaGrass) do
      local target, targetErr = self:_bestBenchEnergyTransTarget()
      if target == nil then
        if targetErr then return nil, targetErr end
        break
      end
      self:_transferAttachedEnergy(deckIndex, target)
      moved = true
    end
    return moved
  end
  error("unknown Energy Trans AI mode: " .. tostring(mode))
end


function AI:_usePokemonPowerForAI(slot, selection)
  assert(self.playerActions, "general AI requires PlayerActions")
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
  if deckIndex == 0xff then return false, "empty_power_slot" end
  self.memory:writeSymbol8("hTemp_ffa0", slot)
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
  self.memory:writeSymbol8("hTempCardIndex_ff9f", deckIndex)
  return self.playerActions:usePokemonPower(slot, self.c.FIRST_ATTACK_OR_PKMN_POWER, selection)
end

function AI:_damageSwapTarget(simulatedHP)
  local allowed = {
    [self.c.CHANSEY] = true,
    [self.c.KANGASKHAN] = true,
    [self.c.SNORLAX] = true,
    [self.c.MR_MIME] = true,
  }
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local lastCandidate, lastNoEnergy
  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local _, cardId = self:_cardAtPlayArea(slot, false)
    local hp = simulatedHP and simulatedHP[slot]
      or self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
    if allowed[cardId] and hp >= 20 then
      lastCandidate = slot
      if self.duelOps:getPlayAreaCardAttachedEnergies(slot) == 0 then
        lastNoEnergy = slot
      end
    end
  end
  -- Preserve the assembly quirk: if no zero-Energy target exists, the final
  -- otherwise-eligible candidate is still returned through register d.
  return lastNoEnergy or lastCandidate
end

-- HandleAIDamageSwap:: Alakazam moves damage off Abra/Kadabra/Alakazam/Mr Mime
-- in the Arena, one counter at a time, onto the source's restricted Bench list.
function AI:handleAIDamageSwap()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if count < 2 then return false end
  if self:_chooseRandomlyNotToDoAction() then return false end
  local _, alakazam = self.combat.status:countTurnDuelistPokemonWithActivePkmnPower(self.c.ALAKAZAM)
  if not alakazam then return false end
  local _, muk = self.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
  if muk then return false end

  local _, activeId = self:_cardAtPlayArea(self.c.PLAY_AREA_ARENA, false)
  if activeId ~= self.c.ALAKAZAM and activeId ~= self.c.KADABRA
      and activeId ~= self.c.ABRA and activeId ~= self.c.MR_MIME then return false end
  local damage = self:_damageAt(self.c.PLAY_AREA_ARENA)
  if damage <= 0 then return false end

  local powerSlot = self:_findCardIDInPlayArea(self.c.ALAKAZAM, self.c.PLAY_AREA_BENCH_1)
  if powerSlot == 0xff then powerSlot = self.c.PLAY_AREA_ARENA end
  local simulatedHP = {}
  for slot = 0, count - 1 do
    simulatedHP[slot] = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
  end
  local transfers = {}
  for _ = 1, math.floor(damage / 10) do
    local target = self:_damageSwapTarget(simulatedHP)
    if not target then break end
    transfers[#transfers + 1] = {
      fromPlayArea = self.c.PLAY_AREA_ARENA,
      toPlayArea = target,
    }
    simulatedHP[self.c.PLAY_AREA_ARENA] = simulatedHP[self.c.PLAY_AREA_ARENA] + 10
    simulatedHP[target] = simulatedHP[target] - 10
  end
  if #transfers == 0 then return false end
  local ok, err = self:_usePokemonPowerForAI(powerSlot, { damageTransfers = transfers })
  if not ok and err ~= "pokemon_power_initial_rejected" then return nil, err end
  return ok
end

function AI:_aiHealTarget()
  local activeDamage = self:_damageAt(self.c.PLAY_AREA_ARENA)
  if activeDamage > 0 then
    local canKO, strongest = self:checkIfDefendingPokemonCanKnockOut()
    if canKO == nil then return nil, strongest end
    if not canKO then return self.c.PLAY_AREA_ARENA end
    local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP)
    if hp + math.min(10, activeDamage) > strongest then return self.c.PLAY_AREA_ARENA end
  end

  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local bestSlot, bestDamage = nil, 0
  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local d = self:_damageAt(slot)
    if d > bestDamage then bestDamage, bestSlot = d, slot end
  end
  return bestSlot
end

function AI:_rawSideHasWeaknessColor(mask, nonTurn)
  if nonTurn then self.duelVars:swapTurn() end
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local found = false
  for slot = 0, count - 1 do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
    if deckIndex ~= 0xff then
      local row = self.cardData:get(self.cardData:getCardIDFromDeckIndex(deckIndex))
      if row and bit.band(wrMask(row.type), mask) ~= 0 then found = true break end
    end
  end
  if nonTurn then self.duelVars:swapTurn() end
  return found
end

function AI:_colorFromWRMask(mask)
  for color = 0, 7 do
    if bit.band(mask, bit.rshift(0x80, color)) ~= 0 then return color end
  end
  return nil
end

function AI:_aiShiftColor(slot)
  if slot ~= self.c.PLAY_AREA_ARENA then return nil end
  local _, _, defender = self:_cardAtPlayArea(self.c.PLAY_AREA_ARENA, true)
  if not defender or (defender.weakness or 0) == 0 then return nil end
  local weakness = defender.weakness
  local current = self.combat.status:getPlayAreaCardColor(self.c.PLAY_AREA_ARENA)
  if bit.band(weakness, wrMask(current)) ~= 0 then return nil end
  if not self:_rawSideHasWeaknessColor(weakness, false)
      and not self:_rawSideHasWeaknessColor(weakness, true) then return nil end
  return self:_colorFromWRMask(weakness)
end

function AI:_commonPowerInitialEligible(cardId, slot)
  if self.combat.status:checkIsIncapableOfUsingPkmnPower(slot) then return false end
  local usedMask = bit.lshift(1, self.c.USED_PKMN_POWER_THIS_TURN_F)
  local flags = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_FLAGS + slot)

  if cardId == self.c.VILEPLUME then
    if bit.band(flags, usedMask) ~= 0 then return false end
    local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    for playArea = self.c.PLAY_AREA_ARENA, count - 1 do
      if self:_damageAt(playArea) > 0 then return true end
    end
    return false
  elseif cardId == self.c.VENOMOTH or cardId == self.c.MANKEY then
    return bit.band(flags, usedMask) == 0
  elseif cardId == self.c.SLOWBRO then
    local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    local anyDamage = false
    for playArea = self.c.PLAY_AREA_ARENA, count - 1 do
      if self:_damageAt(playArea) > 0 then anyDamage = true break end
    end
    return anyDamage and self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot) >= 20
  elseif cardId == self.c.GENGAR then
    if bit.band(flags, usedMask) ~= 0 then return false end
    self.duelVars:swapTurn()
    local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    local anyDamage = false
    for playArea = self.c.PLAY_AREA_ARENA, count - 1 do
      if self:_damageAt(playArea) > 0 then anyDamage = true break end
    end
    self.duelVars:swapTurn()
    return count >= 2 and anyDamage
  end
  return false
end

function AI:_aiPeekTarget()
  if self.rng:random(50) >= 3 then return nil end
  local which = self.rng:random(3)
  if which == 0 then
    local prizes = self.duelVars:get(self.c.DUELVARS_PRIZES)
    local unseen = bit.band(prizes, self.memory:readSymbol8("wAIPeekedPrizes"))
    self.memory:writeSymbol8("wAIPeekedPrizes", unseen)
    if unseen == 0 then return nil end
    for i = 0, 7 do
      local flag = bit.lshift(1, i)
      if bit.band(unseen, flag) ~= 0 then
        self.memory:writeSymbol8("wAIPeekedPrizes", unseen - flag)
        return self.c.AI_PEEK_TARGET_PRIZE + i
      end
    end
    return nil
  elseif which == 1 then
    self.duelVars:swapTurn()
    local cards = self.duelOps:createHandCardList()
    self.duelVars:swapTurn()
    if #cards == 0 then return nil end
    local base = self.memory:address("wDuelTempList")
    self.rng:shuffleCards(base, #cards)
    local deckIndex = self.memory:read8("wram", base, 0)
    return bit.bor(deckIndex, self.c.AI_PEEK_TARGET_HAND)
  else
    local notInDeck = self.duelVars:getNonTurn(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)
    if notInDeck >= self.c.DECK_SIZE - 1 then return nil end
    return self.c.AI_PEEK_TARGET_DECK
  end
end

function AI:_aiStrangeBehaviorTransfers(slot)
  if slot == self.c.PLAY_AREA_ARENA then return nil end
  local damage = self:_damageAt(self.c.PLAY_AREA_ARENA)
  if damage <= 0 then return nil end
  local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
  local amount = math.min(damage, hp - 10)
  if amount <= 0 then return nil end
  local transfers = {}
  for _ = 1, math.floor(amount / 10) do
    transfers[#transfers + 1] = {
      fromPlayArea = self.c.PLAY_AREA_ARENA,
      toPlayArea = slot,
    }
  end
  return transfers
end

function AI:_aiCurseTransfer()
  self.duelVars:swapTurn()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local damaged, lowestSlot, lowestHP = 0, nil, 0xff
  for slot = self.c.PLAY_AREA_ARENA, count - 1 do
    local damage = self:_damageAt(slot)
    if damage > 0 then
      damaged = damaged + 1
      local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
      if hp < lowestHP then lowestHP, lowestSlot = hp, slot end
    end
  end
  if damaged < 2 then self.duelVars:swapTurn(); return nil end
  local first = lowestHP == 10 and self.c.PLAY_AREA_ARENA or self.c.PLAY_AREA_BENCH_1
  local donor
  for slot = first, count - 1 do
    if slot ~= lowestSlot and self:_damageAt(slot) > 0 then donor = slot break end
  end
  self.duelVars:swapTurn()
  if donor == nil then return nil end
  return { fromPlayArea = donor, toPlayArea = lowestSlot }
end

-- HandleAIPkmnPowers:: Heal, Shift, Peek, Strange Behavior and Curse.
-- Return value is (turnEnded, error). Only Curse can end the duel here.
function AI:handleAIPkmnPowers()
  local _, muk = self.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
  if muk then return false end
  if self:_chooseRandomlyNotToDoAction() then return false end

  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local start = self.c.PLAY_AREA_ARENA
  local status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
  if bit.band(status, self.c.CNF_SLP_PRZ) ~= 0 then start = self.c.PLAY_AREA_BENCH_1 end

  for slot = start, count - 1 do
    local deckIndex, cardId, row = self:_cardAtPlayArea(slot, false)
    if deckIndex ~= 0xff and row and row.attacks and row.attacks[1]
        and row.attacks[1].category == self.c.POKEMON_POWER
        and self:_commonPowerInitialEligible(cardId, slot) then
      local selection
      if cardId == self.c.VILEPLUME then
        local target, err = self:_aiHealTarget()
        if target == nil and err then return nil, err end
        if target ~= nil then selection = { playArea = target } end
      elseif cardId == self.c.VENOMOTH then
        local color = self:_aiShiftColor(slot)
        if color ~= nil then selection = { color = color } end
      elseif cardId == self.c.MANKEY then
        local target = self:_aiPeekTarget()
        if target ~= nil then selection = { peekTarget = target } end
      elseif cardId == self.c.SLOWBRO then
        local transfers = self:_aiStrangeBehaviorTransfers(slot)
        if transfers then selection = { damageTransfers = transfers } end
      elseif cardId == self.c.GENGAR then
        local transfer = self:_aiCurseTransfer()
        if transfer then selection = transfer end
      end

      if selection then
        local ok, result = self:_usePokemonPowerForAI(slot, selection)
        if not ok then
          if result ~= "pokemon_power_initial_rejected" and result ~= "pokemon_power_incapable" then
            return nil, result
          end
        elseif cardId == self.c.GENGAR and self.memory:readSymbol8("wDuelFinished") ~= 0 then
          return true
        end
      end
    end
  end
  return false
end

-- HandleAICowardice:: repeatedly returns damaged Tentacool to hand, rescanning
-- the compacted Play Area after each use as the assembly does.
function AI:handleAICowardice()
  local _, muk = self.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
  if muk then return false end
  if self:_chooseRandomlyNotToDoAction() then return false end
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if count <= 1 then return false end

  local slot = self.c.PLAY_AREA_ARENA
  if bit.band(self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS), self.c.CNF_SLP_PRZ) ~= 0 then
    slot = self.c.PLAY_AREA_BENCH_1
  end
  local usedAny = false
  while slot < count do
    local _, cardId = self:_cardAtPlayArea(slot, false)
    if cardId == self.c.TENTACOOL and self:_damageAt(slot) > 0 then
      local flags = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_FLAGS + slot)
      if bit.band(flags, self.c.CAN_EVOLVE_THIS_TURN) ~= 0
          and not self.combat.status:checkIsIncapableOfUsingPkmnPower(slot) then
        local selection = {}
        if slot == self.c.PLAY_AREA_ARENA then
          local replacement, err = self:decideBenchPokemonToSwitchTo()
          if replacement == nil then return nil, err end
          selection.replacement = replacement
        end
        local ok, result = self:_usePokemonPowerForAI(slot, selection)
        if not ok then
          if result ~= "pokemon_power_initial_rejected" and result ~= "pokemon_power_incapable" then
            return nil, result
          end
        else
          usedAny = true
          count = count - 1
          if count <= 1 then return usedAny end
          slot = self.c.PLAY_AREA_ARENA
          goto continue_cowardice
        end
      end
    end
    slot = slot + 1
    ::continue_cowardice::
  end
  return usedAny
end

function AI:_checkActivePowerBoundary(includeCowardice)
  local used, err = self:handleAIDamageSwap()
  if used == nil then return nil, err end
  local ended, powerErr = self:handleAIPkmnPowers()
  if ended == nil then return nil, powerErr end
  if ended then return false, "pokemon_power_ended_turn" end
  if includeCowardice then
    local cow, cowErr = self:handleAICowardice()
    if cow == nil then return nil, cowErr end
  end
  return true
end
-- AIMainTurnLogic:: / AIDoTurn_GeneralNoRetreat:: common ordering. Supported
-- Trainer phases, common retreat, and the common active Power families are
-- native; remaining deck-specific policies still fail closed.
function AI:mainTurnLogic(noRetreat)
  self:initTurnVars()
  local function trainer(phase)
    local ok, err = self:processHandTrainerCards(phase)
    if ok == nil then return nil, err end
    return true
  end
  for _, phase in ipairs({1}) do local ok,err=trainer(phase); if not ok then return nil,err end end

  -- HandleAIAntiMewtwoDeckStrategy:: if the Player is running a confirmed
  -- MewtwoLv53 mill deck and the AI's Bench is already fully set up, the
  -- source skips the rest of this turn's normal processing entirely (after
  -- handling phase 05) and jumps straight to the to_bench Energy Trans +
  -- attack tail below.
  local antiMillOk, antiMillErr = self:handleAIAntiMewtwoDeckStrategy()
  if antiMillOk == nil then return nil, antiMillErr end
  local ok, err
  local transOK, transErr
  if antiMillOk then
    local powerOk, powerErr = self:_checkActivePowerBoundary(true)
    if powerOk == nil then return nil, powerErr end
    if powerOk == false then return true, powerErr end
    for _, phase in ipairs({2,3,4}) do local a,b=trainer(phase); if not a then return nil,b end end
    ok, err = self:decidePlayPokemonCard(); if ok == nil then return nil, err end
    for _, phase in ipairs({5,6,7,8}) do local a,b=trainer(phase); if not a then return nil,b end end
    if not noRetreat then
      local r, e = self:processRetreat()
      if r == nil then return nil, e end
    end
    for _, phase in ipairs({10,11,12}) do local a,b=trainer(phase); if not a then return nil,b end end
    local energyOk, energyErr = self:processAndTryToPlayEnergy()
    if energyOk == nil then return nil, energyErr end
    ok, err = self:decidePlayPokemonCard(); if ok == nil then return nil, err end
    powerOk, powerErr = self:_checkActivePowerBoundary(); if powerOk == nil then return nil,powerErr elseif powerOk == false then return true,powerErr end
    transOK, transErr = self:handleAIEnergyTrans("attack"); if transOK == nil then return nil,transErr end
    for _, phase in ipairs({13,15}) do local a,b=trainer(phase); if not a then return nil,b end end

    -- AIMainTurnLogic repeats the hand-processing sequence once when Professor
    -- Oak was used, but deliberately skips phase 15 on the second pass.
    if self.c.AI_FLAG_USED_PROFESSOR_OAK and bit.band(
        self.memory:readSymbol8("wPreviousAIFlags"), self.c.AI_FLAG_USED_PROFESSOR_OAK) ~= 0 then
      for _, phase in ipairs({1,2,3,4}) do local a,b=trainer(phase); if not a then return nil,b end end
      ok, err = self:decidePlayPokemonCard(); if ok == nil then return nil, err end
      for _, phase in ipairs({5,6,7,8}) do local a,b=trainer(phase); if not a then return nil,b end end
      if not noRetreat then
        local r, e = self:processRetreat(); if r == nil then return nil, e end
      end
      for _, phase in ipairs({10,11,12}) do local a,b=trainer(phase); if not a then return nil,b end end
      if self.memory:readSymbol8("wAlreadyPlayedEnergy") == 0 then
        local eok, eerr = self:processAndTryToPlayEnergy(); if eok == nil then return nil, eerr end
      end
      ok, err = self:decidePlayPokemonCard(); if ok == nil then return nil, err end
      powerOk, powerErr = self:_checkActivePowerBoundary(); if powerOk == nil then return nil,powerErr elseif powerOk == false then return true,powerErr end
      transOK, transErr = self:handleAIEnergyTrans("attack"); if transOK == nil then return nil,transErr end
      local a,b=trainer(13); if not a then return nil,b end
    end
  end

  transOK, transErr = self:handleAIEnergyTrans("to_bench"); if transOK == nil then return nil,transErr end
  local attacked, attackResult = self:processAndTryToUseAttack()
  if attacked == nil then return nil, attackResult end
  if attacked then return true, attackResult end
  self.combat.core:clearNonTurnTemporaryDuelvars()
  self.memory:writeSymbol8("wOpponentTurnEnded", 1)
  return true, "finish_no_attack"
end

-- AIDoTurn_LegendaryZapdos:: bespoke turn logic for the Legendary Zapdos
-- boss deck (engine/duel/ai/decks/legendary_zapdos.asm). Structurally a
-- trimmed AIMainTurnLogic (no Pkmn Power/Cowardice/GoGoRainDance/EnergyTrans
-- calls, no Professor-Oak repeat pass, and a shorter phase list) plus one
-- bespoke branch: if the Arena Pokemon is Voltorb (with ElectrodeLv35 in
-- hand) or Electabuzz, and the Arena has no Energy attached yet, force-
-- attach an Energy card directly to the Arena; otherwise fall back to the
-- normal scoring-based attach (AIProcessAndTryToPlayEnergy), which becomes a
-- guaranteed no-op after a successful forced attach since that already set
-- wAlreadyPlayedEnergy.
function AI:doTurnLegendaryZapdos()
  self:initTurnVars()
  local antiMillOk, antiMillErr = self:handleAIAntiMewtwoDeckStrategy()
  if antiMillOk == nil then return nil, antiMillErr end
  if antiMillOk then
    for _, phase in ipairs({self.c.AI_TRAINER_CARD_PHASE_01, self.c.AI_TRAINER_CARD_PHASE_04}) do
      local ok, err = self:processHandTrainerCards(phase)
      if ok == nil then return nil, err end
    end
    local playOk, playErr = self:decidePlayPokemonCard()
    if playOk == nil then return nil, playErr end
    local ok7, err7 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_07)
    if ok7 == nil then return nil, err7 end
    local retreatOk, retreatErr = self:processRetreat()
    if retreatOk == nil then return nil, retreatErr end
    local ok10, err10 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_10)
    if ok10 == nil then return nil, err10 end

    if self.memory:readSymbol8("wAlreadyPlayedEnergy") == 0 then
      local arenaIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
      local arenaCardId = self.cardData:getCardIDFromDeckIndex(arenaIndex)
      local isVoltorbOrElectabuzz = false
      if arenaCardId == self.c.VOLTORB then
        isVoltorbOrElectabuzz = self:_findCardIDInHand(self.c.ELECTRODE_LV35) ~= nil
      elseif arenaCardId == self.c.ELECTABUZZ_LV35 then
        isVoltorbOrElectabuzz = true
      end
      if isVoltorbOrElectabuzz then
        local handEnergy = self:_energyCardsInHand()
        if #handEnergy > 0 then
          if self.duelOps:countNumberOfEnergyCardsAttached(self.c.PLAY_AREA_ARENA) ~= 0 then
            local energyOk, energyErr = self:processAndTryToPlayEnergy()
            if energyOk == nil then return nil, energyErr end
          else
            local attachOk, attachErr = self:_tryToPlayEnergyCard(self.c.PLAY_AREA_ARENA, handEnergy)
            if attachOk == nil then return nil, attachErr end
          end
        end
      else
        local energyOk, energyErr = self:processAndTryToPlayEnergy()
        if energyOk == nil then return nil, energyErr end
      end
    end

    local playOk2, playErr2 = self:decidePlayPokemonCard()
    if playOk2 == nil then return nil, playErr2 end
    local ok13, err13 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_13)
    if ok13 == nil then return nil, err13 end
  end

  local attacked, attackResult = self:processAndTryToUseAttack()
  if attacked == nil then return nil, attackResult end
  if attacked then return true, attackResult end
  self.combat.core:clearNonTurnTemporaryDuelvars()
  self.memory:writeSymbol8("wOpponentTurnEnded", 1)
  return true, "finish_no_attack"
end

-- Shared "check if AI can play MoltresLv37 from hand and if so, play it"
-- gate: byte-identical in both AIDoTurn_LegendaryMoltres and
-- AIDoTurn_LegendaryRonald (the latter calls it twice, once per pass).
-- Requires Bench space, more than 9 cards left in the deck, no Muk in play
-- on either side, and MoltresLv37 actually in hand.
function AI:_tryToPlayMoltresLv37Directly()
  local playAreaCount = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if playAreaCount >= self.c.MAX_PLAY_AREA_POKEMON then return true end
  local notInDeck = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)
  if notInDeck >= self.c.DECK_SIZE - 9 then return true end
  local _, muk = self.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
  if muk then return true end
  if not self:_findCardIDInHand(self.c.MOLTRES_LV37) then return true end
  local ok, reason = self.playerActions:playBasic(self.c.MOLTRES_LV37)
  if not ok and reason ~= "bench_full" then return nil, reason end
  return true
end

-- AIDoTurn_LegendaryMoltres:: bespoke turn logic for the Legendary Moltres
-- boss deck (engine/duel/ai/decks/legendary_moltres.asm). Like Zapdos's, the
-- anti-Mewtwo-mill check runs immediately after InitAITurnVars, before any
-- phase. Two bespoke branches: (1) after phases 2 and 4, if the Bench isn't
-- full, the deck has more than 9 cards left, no Muk is in play on either
-- side, and MoltresLv37 is in hand, play it directly as a Basic Pokemon
-- (bypassing the normal scoring in decidePlayPokemonCard entirely); (2) the
-- Energy-attach step force-attaches directly to the Arena when it's
-- MagmarLv31 with no Energy attached yet, same shape as Zapdos's
-- Voltorb/Electabuzz branch but gated on a single card ID.
function AI:doTurnLegendaryMoltres()
  self:initTurnVars()
  local antiMillOk, antiMillErr = self:handleAIAntiMewtwoDeckStrategy()
  if antiMillOk == nil then return nil, antiMillErr end
  if antiMillOk then
    for _, phase in ipairs({self.c.AI_TRAINER_CARD_PHASE_02, self.c.AI_TRAINER_CARD_PHASE_04}) do
      local ok, err = self:processHandTrainerCards(phase)
      if ok == nil then return nil, err end
    end

    local moltresOk, moltresErr = self:_tryToPlayMoltresLv37Directly()
    if moltresOk == nil then return nil, moltresErr end

    local playOk, playErr = self:decidePlayPokemonCard()
    if playOk == nil then return nil, playErr end
    local ok5, err5 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_05)
    if ok5 == nil then return nil, err5 end
    local retreatOk, retreatErr = self:processRetreat()
    if retreatOk == nil then return nil, retreatErr end
    for _, phase in ipairs({self.c.AI_TRAINER_CARD_PHASE_10, self.c.AI_TRAINER_CARD_PHASE_11}) do
      local a, b = self:processHandTrainerCards(phase)
      if a == nil then return nil, b end
    end

    if self.memory:readSymbol8("wAlreadyPlayedEnergy") == 0 then
      local arenaIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
      local arenaCardId = self.cardData:getCardIDFromDeckIndex(arenaIndex)
      if arenaCardId == self.c.MAGMAR_LV31 then
        local handEnergy = self:_energyCardsInHand()
        if #handEnergy > 0 then
          if self.duelOps:countNumberOfEnergyCardsAttached(self.c.PLAY_AREA_ARENA) ~= 0 then
            local energyOk, energyErr = self:processAndTryToPlayEnergy()
            if energyOk == nil then return nil, energyErr end
          else
            local attachOk, attachErr = self:_tryToPlayEnergyCard(self.c.PLAY_AREA_ARENA, handEnergy)
            if attachOk == nil then return nil, attachErr end
          end
        end
      else
        local energyOk, energyErr = self:processAndTryToPlayEnergy()
        if energyOk == nil then return nil, energyErr end
      end
    end

    local playOk2, playErr2 = self:decidePlayPokemonCard()
    if playOk2 == nil then return nil, playErr2 end
    local ok13, err13 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_13)
    if ok13 == nil then return nil, err13 end
  end

  local attacked2, attackResult2 = self:processAndTryToUseAttack()
  if attacked2 == nil then return nil, attackResult2 end
  if attacked2 then return true, attackResult2 end
  self.combat.core:clearNonTurnTemporaryDuelvars()
  self.memory:writeSymbol8("wOpponentTurnEnded", 1)
  return true, "finish_no_attack"
end

-- AIDoTurn_LegendaryDragonite:: bespoke turn logic for the Legendary
-- Dragonite boss deck (engine/duel/ai/decks/legendary_dragonite.asm).
-- Unlike Zapdos's and Moltres's, phase 01 runs *before* the anti-Mewtwo-mill
-- check here, matching AIMainTurnLogic's own ordering. The Energy-attach
-- branch force-attaches directly to the Arena when it's Kangaskhan with no
-- Energy attached yet (single-card gate, no hand-search precondition, since
-- the check is purely "is the Arena Pokemon Kangaskhan"). Also has its own
-- short Professor-Oak repeat pass (phases 01/02/07/10/11 again, no phase 15
-- on the repeat), distinct from AIMainTurnLogic's longer one.
function AI:doTurnLegendaryDragonite()
  self:initTurnVars()
  local ok1, err1 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_01)
  if ok1 == nil then return nil, err1 end
  local antiMillOk, antiMillErr = self:handleAIAntiMewtwoDeckStrategy()
  if antiMillOk == nil then return nil, antiMillErr end
  if antiMillOk then
    local ok2, err2 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_02)
    if ok2 == nil then return nil, err2 end
    local playOk, playErr = self:decidePlayPokemonCard()
    if playOk == nil then return nil, playErr end
    local ok7, err7 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_07)
    if ok7 == nil then return nil, err7 end
    local retreatOk, retreatErr = self:processRetreat()
    if retreatOk == nil then return nil, retreatErr end
    for _, phase in ipairs({self.c.AI_TRAINER_CARD_PHASE_10, self.c.AI_TRAINER_CARD_PHASE_11}) do
      local a, b = self:processHandTrainerCards(phase)
      if a == nil then return nil, b end
    end

    if self.memory:readSymbol8("wAlreadyPlayedEnergy") == 0 then
      local arenaIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
      local arenaCardId = self.cardData:getCardIDFromDeckIndex(arenaIndex)
      if arenaCardId == self.c.KANGASKHAN then
        local handEnergy = self:_energyCardsInHand()
        if #handEnergy > 0 then
          if self.duelOps:countNumberOfEnergyCardsAttached(self.c.PLAY_AREA_ARENA) ~= 0 then
            local energyOk, energyErr = self:processAndTryToPlayEnergy()
            if energyOk == nil then return nil, energyErr end
          else
            local attachOk, attachErr = self:_tryToPlayEnergyCard(self.c.PLAY_AREA_ARENA, handEnergy)
            if attachOk == nil then return nil, attachErr end
          end
        end
      else
        local energyOk, energyErr = self:processAndTryToPlayEnergy()
        if energyOk == nil then return nil, energyErr end
      end
    end

    local playOk2, playErr2 = self:decidePlayPokemonCard()
    if playOk2 == nil then return nil, playErr2 end
    local ok15, err15 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_15)
    if ok15 == nil then return nil, err15 end

    -- Short Professor-Oak repeat pass, specific to this deck's own phase
    -- list: 01/02, play, 07, retreat, 10/11, energy (no Kangaskhan re-check
    -- on this pass), play again. No phase 15 the second time.
    if bit.band(self.memory:readSymbol8("wPreviousAIFlags"), self.c.AI_FLAG_USED_PROFESSOR_OAK) ~= 0 then
      local rok1, rerr1 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_01)
      if rok1 == nil then return nil, rerr1 end
      local rok2, rerr2 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_02)
      if rok2 == nil then return nil, rerr2 end
      local rplayOk, rplayErr = self:decidePlayPokemonCard()
      if rplayOk == nil then return nil, rplayErr end
      local rok7, rerr7 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_07)
      if rok7 == nil then return nil, rerr7 end
      local rretreatOk, rretreatErr = self:processRetreat()
      if rretreatOk == nil then return nil, rretreatErr end
      for _, phase in ipairs({self.c.AI_TRAINER_CARD_PHASE_10, self.c.AI_TRAINER_CARD_PHASE_11}) do
        local a, b = self:processHandTrainerCards(phase)
        if a == nil then return nil, b end
      end
      if self.memory:readSymbol8("wAlreadyPlayedEnergy") == 0 then
        local renergyOk, renergyErr = self:processAndTryToPlayEnergy()
        if renergyOk == nil then return nil, renergyErr end
      end
      local rplayOk2, rplayErr2 = self:decidePlayPokemonCard()
      if rplayOk2 == nil then return nil, rplayErr2 end
    end
  end

  local attacked3, attackResult3 = self:processAndTryToUseAttack()
  if attacked3 == nil then return nil, attackResult3 end
  if attacked3 then return true, attackResult3 end
  self.combat.core:clearNonTurnTemporaryDuelvars()
  self.memory:writeSymbol8("wOpponentTurnEnded", 1)
  return true, "finish_no_attack"
end

-- AIDoTurn_LegendaryArticuno:: bespoke turn logic for the Legendary
-- Articuno boss deck (engine/duel/ai/decks/legendary_articuno.asm). Phase
-- 01 runs before the anti-Mewtwo-mill check, same as Dragonite's. Unlike
-- Zapdos/Moltres/Dragonite, this one has no bespoke Energy-attach branch of
-- its own at all: Articuno's whole specialization
-- (ScoreLegendaryArticunoCards -- prioritizing Lapras to 3 Energy, then
-- Articuno, then Dewgong, then Seel, gated on the Player having 3+ prizes
-- left) already lives inside the common energy-scoring pipeline via
-- AI:_legendaryArticunoEnergyDeltas, so plain processAndTryToPlayEnergy is
-- always used. It does have a Professor-Oak repeat pass (phases 01/02, play,
-- retreat, 10, energy, play again -- no phase 13/15 on the repeat).
function AI:doTurnLegendaryArticuno()
  self:initTurnVars()
  local ok1, err1 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_01)
  if ok1 == nil then return nil, err1 end
  local antiMillOk, antiMillErr = self:handleAIAntiMewtwoDeckStrategy()
  if antiMillOk == nil then return nil, antiMillErr end
  if antiMillOk then
    local ok2, err2 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_02)
    if ok2 == nil then return nil, err2 end
    local playOk, playErr = self:decidePlayPokemonCard()
    if playOk == nil then return nil, playErr end
    local retreatOk, retreatErr = self:processRetreat()
    if retreatOk == nil then return nil, retreatErr end
    local ok10, err10 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_10)
    if ok10 == nil then return nil, err10 end
    if self.memory:readSymbol8("wAlreadyPlayedEnergy") == 0 then
      local energyOk, energyErr = self:processAndTryToPlayEnergy()
      if energyOk == nil then return nil, energyErr end
    end
    local playOk2, playErr2 = self:decidePlayPokemonCard()
    if playOk2 == nil then return nil, playErr2 end
    local ok13, err13 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_13)
    if ok13 == nil then return nil, err13 end
    local ok15, err15 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_15)
    if ok15 == nil then return nil, err15 end

    if bit.band(self.memory:readSymbol8("wPreviousAIFlags"), self.c.AI_FLAG_USED_PROFESSOR_OAK) ~= 0 then
      local rok1, rerr1 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_01)
      if rok1 == nil then return nil, rerr1 end
      local rok2, rerr2 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_02)
      if rok2 == nil then return nil, rerr2 end
      local rplayOk, rplayErr = self:decidePlayPokemonCard()
      if rplayOk == nil then return nil, rplayErr end
      local rretreatOk, rretreatErr = self:processRetreat()
      if rretreatOk == nil then return nil, rretreatErr end
      local rok10, rerr10 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_10)
      if rok10 == nil then return nil, rerr10 end
      if self.memory:readSymbol8("wAlreadyPlayedEnergy") == 0 then
        local renergyOk, renergyErr = self:processAndTryToPlayEnergy()
        if renergyOk == nil then return nil, renergyErr end
      end
      local rplayOk2, rplayErr2 = self:decidePlayPokemonCard()
      if rplayOk2 == nil then return nil, rplayErr2 end
    end
  end

  local attacked4, attackResult4 = self:processAndTryToUseAttack()
  if attacked4 == nil then return nil, attackResult4 end
  if attacked4 then return true, attackResult4 end
  self.combat.core:clearNonTurnTemporaryDuelvars()
  self.memory:writeSymbol8("wOpponentTurnEnded", 1)
  return true, "finish_no_attack"
end

-- AIDoTurn_LegendaryRonald:: bespoke turn logic for the Legendary Ronald
-- boss deck (engine/duel/ai/decks/legendary_ronald.asm), the last of the
-- five Legendary bosses. Unlike all four others, this one has NO
-- anti-Mewtwo-mill check at all -- the whole turn runs unconditionally.
-- Reuses the MoltresLv37-direct-play gate (AI:_tryToPlayMoltresLv37Directly,
-- shared with Moltres's own translation) TWICE: once in the initial pass
-- and again in its Professor-Oak repeat pass. No bespoke Energy-attach
-- branch (plain processAndTryToPlayEnergy both times, like Articuno's).
function AI:doTurnLegendaryRonald()
  self:initTurnVars()
  for _, phase in ipairs({self.c.AI_TRAINER_CARD_PHASE_01, self.c.AI_TRAINER_CARD_PHASE_02,
      self.c.AI_TRAINER_CARD_PHASE_04}) do
    local ok, err = self:processHandTrainerCards(phase)
    if ok == nil then return nil, err end
  end
  local moltresOk, moltresErr = self:_tryToPlayMoltresLv37Directly()
  if moltresOk == nil then return nil, moltresErr end
  local playOk, playErr = self:decidePlayPokemonCard()
  if playOk == nil then return nil, playErr end
  for _, phase in ipairs({self.c.AI_TRAINER_CARD_PHASE_05, self.c.AI_TRAINER_CARD_PHASE_07}) do
    local a, b = self:processHandTrainerCards(phase)
    if a == nil then return nil, b end
  end
  local retreatOk, retreatErr = self:processRetreat()
  if retreatOk == nil then return nil, retreatErr end
  local ok10, err10 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_10)
  if ok10 == nil then return nil, err10 end
  if self.memory:readSymbol8("wAlreadyPlayedEnergy") == 0 then
    local energyOk, energyErr = self:processAndTryToPlayEnergy()
    if energyOk == nil then return nil, energyErr end
  end
  local playOk2, playErr2 = self:decidePlayPokemonCard()
  if playOk2 == nil then return nil, playErr2 end
  local ok15, err15 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_15)
  if ok15 == nil then return nil, err15 end

  if bit.band(self.memory:readSymbol8("wPreviousAIFlags"), self.c.AI_FLAG_USED_PROFESSOR_OAK) ~= 0 then
    for _, phase in ipairs({self.c.AI_TRAINER_CARD_PHASE_01, self.c.AI_TRAINER_CARD_PHASE_02,
        self.c.AI_TRAINER_CARD_PHASE_04}) do
      local a, b = self:processHandTrainerCards(phase)
      if a == nil then return nil, b end
    end
    local rmoltresOk, rmoltresErr = self:_tryToPlayMoltresLv37Directly()
    if rmoltresOk == nil then return nil, rmoltresErr end
    local rplayOk, rplayErr = self:decidePlayPokemonCard()
    if rplayOk == nil then return nil, rplayErr end
    for _, phase in ipairs({self.c.AI_TRAINER_CARD_PHASE_05, self.c.AI_TRAINER_CARD_PHASE_07}) do
      local a, b = self:processHandTrainerCards(phase)
      if a == nil then return nil, b end
    end
    local rretreatOk, rretreatErr = self:processRetreat()
    if rretreatOk == nil then return nil, rretreatErr end
    local rok10, rerr10 = self:processHandTrainerCards(self.c.AI_TRAINER_CARD_PHASE_10)
    if rok10 == nil then return nil, rerr10 end
    if self.memory:readSymbol8("wAlreadyPlayedEnergy") == 0 then
      local renergyOk, renergyErr = self:processAndTryToPlayEnergy()
      if renergyOk == nil then return nil, renergyErr end
    end
    local rplayOk2, rplayErr2 = self:decidePlayPokemonCard()
    if rplayOk2 == nil then return nil, rplayErr2 end
  end

  local attacked, attackResult = self:processAndTryToUseAttack()
  if attacked == nil then return nil, attackResult end
  if attacked then return true, attackResult end
  self.combat.core:clearNonTurnTemporaryDuelvars()
  self.memory:writeSymbol8("wOpponentTurnEnded", 1)
  return true, "finish_no_attack"
end

-- AIDoAction_Turn:: dispatches through the source DeckAIPointerTable. Generic
-- tables now use the native common core; special/boss tables remain adapters.
function AI:doTurn()
  local label = self:_actionTable()
  if label == "AIActionTable_GeneralDecks" then
    return self:mainTurnLogic(false)
  elseif label == "AIActionTable_GeneralNoRetreat" then
    return self:mainTurnLogic(true)
  elseif label == "AIActionTable_SamPractice" then
    if self:isSamPracticeScriptedTurn() then return self:performSamScriptedTurn() end
    return self:mainTurnLogic(false)
  elseif AI_BOSS_GENERAL_TURN_TABLES[label] then
    -- Eleven of the sixteen boss/special tables route .do_turn straight to
    -- AIMainTurnLogic with no wrapper of their own (verified directly
    -- against engine/duel/ai/decks/*.asm); the remaining five (the
    -- Legendary bosses) each have their own bespoke AIDoTurn_<Deck>, handled
    -- below.
    return self:mainTurnLogic(false)
  elseif label == "AIActionTable_LegendaryZapdos" then
    return self:doTurnLegendaryZapdos()
  elseif label == "AIActionTable_LegendaryMoltres" then
    return self:doTurnLegendaryMoltres()
  elseif label == "AIActionTable_LegendaryDragonite" then
    return self:doTurnLegendaryDragonite()
  elseif label == "AIActionTable_LegendaryArticuno" then
    return self:doTurnLegendaryArticuno()
  elseif label == "AIActionTable_LegendaryRonald" then
    return self:doTurnLegendaryRonald()
  end
  -- Every one of the 19 confirmed labels (3 general + 16 boss/special) is
  -- now native; only a future/unverified AIActionTable_* label outside that
  -- set still falls through to the adapter.
  return self:_required("turnSpecial")(label, self.memory:readSymbol8("wOpponentDeckID"))
end

return AI
