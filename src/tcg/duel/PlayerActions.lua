-- State-changing player actions used by the playable Sam practice slice.
-- These are translations of the corresponding DuelMenu_Hand/PlayPokemonCard,
-- PlayEnergyCard and Potion effect paths. UI selection is handled by the host
-- state; all card movement remains in original duel RAM.

local PlayerActions = {}
PlayerActions.__index = PlayerActions

function PlayerActions.new(memory, duelVars, cardData, duelOps, combat, effectCommands, constants, adapters)
  return setmetatable({
    memory = assert(memory), duelVars = assert(duelVars),
    cardData = assert(cardData), duelOps = assert(duelOps),
    combat = assert(combat), effects = assert(effectCommands),
    c = assert(constants), adapters = adapters or {},
  }, PlayerActions)
end

function PlayerActions:_event(name, payload)
  local fn = self.adapters.event
  if fn then fn(name, payload or {}) end
end

function PlayerActions:findCardInHand(cardId)
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  for i = 0, count - 1 do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_HAND + i)
    if self.cardData:getCardIDFromDeckIndex(deckIndex) == cardId then return deckIndex end
  end
  return nil
end

-- PlayPokemonCard BASIC branch.
function PlayerActions:playBasic(cardId)
  local deckIndex = self:findCardInHand(cardId)
  if deckIndex == nil then return false, "not_in_hand" end
  local row = assert(self.cardData:get(cardId))
  if row.type >= self.c.TYPE_ENERGY or row.stage ~= self.c.BASIC then
    return false, "not_basic"
  end
  local triggerReady, triggerReason = self.combat:checkPlayedPokemonCardTrigger(deckIndex)
  if not triggerReady then return false, triggerReason end
  self.memory:writeSymbol8("hTemp_ffa0", deckIndex)
  self.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
  local slot, carry = self.duelOps:putHandPokemonCardInPlayArea(deckIndex)
  if carry then return false, "bench_full" end
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
  self.duelVars:set(self.c.DUELVARS_ARENA_CARD_STAGE + slot, self.c.BASIC)
  local triggered, triggerResult = self.combat:processPlayedPokemonCard(deckIndex, slot)
  if not triggered then return false, triggerResult end
  self:_event("play_basic", { cardId = cardId, deckIndex = deckIndex, slot = slot })
  return true, slot
end

-- PlayEnergyCard::. Water Energy may bypass the once-per-turn flag when
-- Rain Dance is active and the selected target is a Water Pokemon. A Water
-- Energy aimed at any other color follows the ordinary once-per-turn branch.
function PlayerActions:attachEnergy(cardId, slot)
  local deckIndex = self:findCardInHand(cardId)
  if deckIndex == nil then return false, "not_in_hand" end
  local row = assert(self.cardData:get(cardId))
  if row.type < self.c.TYPE_ENERGY or row.type >= self.c.TYPE_TRAINER then
    return false, "not_energy"
  end
  if self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot) == 0xff then
    return false, "empty_slot"
  end

  local rainDance = false
  if row.type == self.c.TYPE_ENERGY_WATER and self.combat.status:isRainDanceActive() then
    rainDance = self.combat.status:getPlayAreaCardColor(slot) == self.c.TYPE_PKMN_WATER
  end
  if not rainDance and self.memory:readSymbol8("wAlreadyPlayedEnergy") ~= 0 then
    return false, "already_played_energy"
  end

  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
  self.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", slot)
  self.memory:writeSymbol8("hTemp_ffa0", deckIndex)
  self.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
  self.duelOps:putHandCardInPlayArea(deckIndex, slot)
  if not rainDance then self.memory:writeSymbol8("wAlreadyPlayedEnergy", self.c.TRUE) end
  self:_event("attach_energy", { cardId = cardId, deckIndex = deckIndex, slot = slot,
    rainDance = rainDance })
  return true
end

-- PlayPokemonCard evolution branch through EvolvePokemonCardIfPossible::.
function PlayerActions:evolve(cardId, slot)
  local deckIndex = self:findCardInHand(cardId)
  if deckIndex == nil then return false, "not_in_hand" end
  local triggerReady, triggerReason = self.combat:checkPlayedPokemonCardTrigger(deckIndex)
  if not triggerReady then return false, triggerReason end
  self.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
  self.memory:writeSymbol8("hTemp_ffa0", deckIndex)
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
  self.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", slot)
  local ok, reason = self.duelOps:evolvePokemonCardIfPossible(deckIndex, slot)
  if not ok then return false, reason end
  local triggered, triggerResult = self.combat:processPlayedPokemonCard(deckIndex, slot)
  if not triggered then return false, triggerResult end
  self:_event("evolve", { cardId = cardId, deckIndex = deckIndex, slot = slot })
  return true
end

-- PlayTrainerCard::. The effect pointer and phase order are generic; individual
-- effect functions remain fail-closed in EffectCommands. `selection` is host
-- supplied state for effects whose cartridge path opened an interactive menu.
function PlayerActions:playTrainer(cardId, selection)
  if self.combat.status:checkCantUseTrainerDueToEffect() then
    return false, "trainer_blocked_by_headache"
  end
  local deckIndex = self:findCardInHand(cardId)
  if deckIndex == nil then return false, "not_in_hand" end
  local row = assert(self.cardData:get(cardId))
  if row.type ~= self.c.TYPE_TRAINER then return false, "not_trainer" end

  self.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
  self.memory:writeSymbol8("hTempCardIndex_ff9f", deckIndex)
  self.effects:loadNonPokemonCardEffectCommands(deckIndex, self.cardData)
  local phases = {
    self.c.EFFECTCMDTYPE_INITIAL_EFFECT_1,
    self.c.EFFECTCMDTYPE_INITIAL_EFFECT_2,
    self.c.EFFECTCMDTYPE_DISCARD_ENERGY,
    self.c.EFFECTCMDTYPE_REQUIRE_SELECTION,
    self.c.EFFECTCMDTYPE_BEFORE_DAMAGE,
  }
  local translated, reason = self.effects:validatePhases(phases)
  if not translated then return false, reason end
  local context = { playerActions = self, selection = selection }

  local carry, err = self.effects:tryExecute(self.c.EFFECTCMDTYPE_INITIAL_EFFECT_1, context)
  if carry == nil then return false, err end
  if carry then return false, "trainer_initial_rejected" end
  carry, err = self.effects:tryExecute(self.c.EFFECTCMDTYPE_INITIAL_EFFECT_2, context)
  if carry == nil then return false, err end
  if carry then return false, "trainer_selection_cancelled" end

  local failed, exchangeErr = self.combat.setup:exchangeRNG()
  if failed then return false, exchangeErr end
  for _, phase in ipairs({
    self.c.EFFECTCMDTYPE_DISCARD_ENERGY,
    self.c.EFFECTCMDTYPE_REQUIRE_SELECTION,
    self.c.EFFECTCMDTYPE_BEFORE_DAMAGE,
  }) do
    carry, err = self.effects:tryExecute(phase, context)
    if carry == nil then return false, err end
  end

  self.duelOps:moveHandCardToDiscardPile(deckIndex)
  failed, exchangeErr = self.combat.setup:exchangeRNG()
  if failed then return false, exchangeErr end
  self:_event("trainer", { cardId = cardId, deckIndex = deckIndex })
  return true, "trainer_played"
end

-- Potion remains the practice-facing convenience wrapper, but now goes through
-- the same generic PlayTrainerCard/effect-command path as every other Trainer.
function PlayerActions:usePotion(slot)
  local before = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
  local ok, result = self:playTrainer(self.c.POTION, { playArea = slot })
  if not ok then return false, result end
  local after = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
  return true, after - before
end

function PlayerActions:usePokemonPower(slot, attackIndex, selection)
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
  if deckIndex == 0xff then return false, "empty_slot" end
  return self.combat:usePokemonPower(deckIndex, attackIndex, slot, { selection = selection })
end

function PlayerActions:attack(attackIndex, selection)
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  if deckIndex == 0xff then return false, "no_active" end
  return self.combat:useAttack(deckIndex, attackIndex, {
    verifyPractice = true, selection = selection,
  })
end

return PlayerActions
