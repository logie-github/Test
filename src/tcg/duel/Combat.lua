-- Attack execution translated from pret/poketcg duel routines.
--
-- Common target/self damage arithmetic, prevention state, confusion self-hit,
-- status queuing, and KO handoff are generalized beyond Sam's practice duel.
-- Card-specific effect-command execution is routed through the generic
-- EffectCommands dispatcher. Unknown function identities still fail closed.

local bit = require("bit")

local Combat = {}
Combat.__index = Combat

local function lo(v) return bit.band(v, 0xff) end
local function hi(v) return bit.band(bit.rshift(v, 8), 0xff) end

function Combat.new(memory, duelVars, cardData, duelOps, core, status, setup,
    knockouts, practice, effectCommands, constants, adapters)
  return setmetatable({
    memory = assert(memory), duelVars = assert(duelVars),
    cardData = assert(cardData), duelOps = assert(duelOps), core = assert(core),
    status = assert(status), setup = assert(setup), knockouts = assert(knockouts),
    practice = assert(practice), effects = assert(effectCommands),
    c = assert(constants), adapters = adapters or {},
  }, Combat)
end

function Combat:_event(name, payload)
  local fn = self.adapters.event
  if fn then fn(name, payload or {}) end
end

function Combat:_readDamage()
  local address, bank = self.memory:address("wDamage")
  local low = self.memory:read8("wram", address, bank)
  local high = self.memory:read8("wram", address + 1, bank)
  return low + high * 0x100
end

function Combat:_writeDamage(value)
  local address, bank = self.memory:address("wDamage")
  self.memory:write8("wram", address, lo(value), bank)
  self.memory:write8("wram", address + 1, hi(value), bank)
end

-- CopyAttackDataAndDamage_FromDeckIndex::.
function Combat:loadAttack(deckIndex, attackIndex)
  local cardId = self.cardData:loadBuffer1FromDeckIndex(deckIndex)
  local row = assert(self.cardData:get(cardId))
  local attack = assert(row.attacks and row.attacks[attackIndex + 1],
    "attack requested from a non-Pokemon card")

  self.memory:writeSymbol8("wSelectedAttack", attackIndex)
  self.memory:writeSymbol8("hTempCardIndex_ff9f", deckIndex)
  self.memory:writeSymbol8("wTempCardID_ccc2", cardId)

  local loaded, loadedBank = self.memory:address("wLoadedCard1")
  local attackBase = loaded + (attackIndex == self.c.SECOND_ATTACK
    and self.c.CARD_DATA_ATTACK2 or self.c.CARD_DATA_ATTACK1)
  local target, targetBank = self.memory:address("wLoadedAttack")
  local length = self.c.CARD_DATA_ATTACK2 - self.c.CARD_DATA_ATTACK1
  local bytes = self.memory:readBlock("wram", attackBase, length, loadedBank)
  self.memory:writeBlock("wram", target, bytes, targetBank)

  local damage, damageBank = self.memory:address("wDamage")
  self.memory:write8("wram", damage, attack.damage, damageBank)
  self.memory:write8("wram", damage + 1, 0, damageBank)
  self.memory:writeSymbol8("wNoDamageOrEffect", 0)
  local dealt, dealtBank = self.memory:address("wDealtDamage")
  self.memory:write8("wram", dealt, 0, dealtBank)
  self.memory:write8("wram", dealt + 1, 0, dealtBank)
  return row, attack, cardId
end

function Combat:_arenaCardId(nonTurn)
  local deckIndex = nonTurn
    and self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD)
    or self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  if deckIndex == 0xff then return nil end
  if nonTurn then
    self.duelVars:swapTurn()
    local id = self.cardData:getCardIDFromDeckIndex(deckIndex)
    self.duelVars:swapTurn()
    return id
  end
  return self.cardData:getCardIDFromDeckIndex(deckIndex)
end

-- UpdateArenaCardIDsAndClearTwoTurnDuelVars:: state-relevant portion.
function Combat:updateArenaCardIDsAndClearTwoTurnDuelVars()
  local turnDeck = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  self.memory:writeSymbol8("hTempCardIndex_ff9f", turnDeck)
  self.memory:writeSymbol8("wTempTurnDuelistCardID",
    self.cardData:getCardIDFromDeckIndex(turnDeck))

  self.duelVars:swapTurn()
  local nonTurnDeck = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local nonTurnId = self.cardData:getCardIDFromDeckIndex(nonTurnDeck)
  self.duelVars:swapTurn()
  self.memory:writeSymbol8("wTempNonTurnDuelistCardID", nonTurnId)

  for _, name in ipairs({
    "wSentAttackDataToLinkOpponent", "wStatusConditionQueueIndex", "wEffectFailed",
    "wIsDamageToSelf", "wDefendingWasForcedToSwitch", "wMetronomeEnergyCost",
    "wNoEffectFromWhichStatus",
  }) do
    self.memory:writeSymbol8(name, 0)
  end
  self.core:clearNonTurnTemporaryDuelvarsCopyStatus()
end

-- CheckIfEnoughEnergiesForGivenAttack:: including HandleEnergyBurn:: after
-- attached-energy accounting, matching the cartridge's Charizard Power path.
function Combat:hasEnoughEnergy(deckIndex, attackIndex)
  local row, attack = self:loadAttack(deckIndex, attackIndex)
  if attack.nameTextId == 0 or attack.category == self.c.POKEMON_POWER then
    return false, "no_attack"
  end

  self.duelOps:getPlayAreaCardAttachedEnergies(self.c.PLAY_AREA_ARENA)
  self.status:handleEnergyBurn()
  local base, bank = self.memory:address("wAttachedEnergies")
  local requiredColored = 0
  for energyType = 0, self.c.NUM_COLORED_TYPES - 1 do
    local required = attack.energy[energyType] or 0
    local attached = self.memory:read8("wram", base + energyType, bank)
    requiredColored = requiredColored + required
    if required > attached then return false, "not_enough_energy" end
  end

  local total = self.memory:readSymbol8("wTotalAttachedEnergies")
  local colorless = attack.energy[self.c.COLORLESS] or 0
  if total - requiredColored < colorless then return false, "not_enough_energy" end
  return true, row, attack
end

function Combat:_applyNoDamageOrEffectPrevention(cardId, attack)
  if bit.band(attack.category, self.c.RESIDUAL) ~= 0 then return false end
  self.duelVars:swapTurn()
  local prevented = self.status:handleNoDamageOrEffectSubstatus(
    cardId, attack.category, false)
  self.duelVars:swapTurn()
  return prevented
end

function Combat:_attackColor()
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local changed = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_CHANGED_TYPE)
  if bit.band(changed, bit.lshift(1, self.c.HAS_CHANGED_COLOR_F)) ~= 0 then
    local incapable = self.status:checkIsIncapableOfUsingPkmnPower(
      self.c.PLAY_AREA_ARENA)
    if not incapable then return bit.band(changed, 0x0f) end
  end
  local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
  local cardType = assert(self.cardData:get(cardId)).type
  if cardType == self.c.TYPE_TRAINER then return self.c.COLORLESS end
  return cardType
end

function Combat:_defenderWeaknessResistance()
  self.duelVars:swapTurn()
  local weakness = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_CHANGED_WEAKNESS)
  local resistance = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_CHANGED_RESISTANCE)
  local defenderDeck = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local defenderId = self.cardData:getCardIDFromDeckIndex(defenderDeck)
  local defender = assert(self.cardData:get(defenderId))
  if weakness == 0 then weakness = defender.weakness end
  if resistance == 0 then resistance = defender.resistance end
  self.duelVars:swapTurn()
  return weakness, resistance, defenderId
end

function Combat:_applyAttachedPlusPower(damage)
  local count = self.duelOps:countCardIDInLocation(
    self.c.PLUSPOWER, self.c.CARD_LOCATION_ARENA)
  return bit.band(damage + 10 * count, 0xffff)
end

function Combat:_applyAttachedDefender(damage)
  local count = self.duelOps:countCardIDInLocation(
    self.c.DEFENDER, self.c.CARD_LOCATION_ARENA)
  return bit.band(damage - 20 * count, 0xffff)
end

-- ApplyDamageModifiers_DamageToTarget:: common state behavior.  This is now
-- translated beyond the Sam-only path: double-damage substatus, changed color,
-- weakness/resistance overrides, PlusPower, Defender, common reduction
-- substatuses, Invisible Wall, and Kabuto Armor follow the source ordering.
-- Prevention/Transparency and card-specific effect-command mutation remain
-- separate boundaries until the effect dispatcher is translated.
function Combat:applyDamageModifiers(baseDamage)
  self.memory:writeSymbol8("wDamageEffectiveness", 0)
  if baseDamage == 0 then return 0 end

  local damage = bit.band(baseDamage, 0xffff)
  local high = bit.band(bit.rshift(damage, 8), 0xff)
  local unaffected = bit.band(high,
    bit.lshift(1, self.c.UNAFFECTED_BY_WEAKNESS_RESISTANCE_F)) ~= 0
  if unaffected then
    high = bit.band(high, bit.bnot(bit.lshift(1,
      self.c.UNAFFECTED_BY_WEAKNESS_RESISTANCE_F)))
    damage = bit.bor(bit.lshift(high, 8), bit.band(damage, 0xff))
  end

  damage = self.status:handleDoubleDamageSubstatus(damage)

  if not unaffected and damage ~= 0 then
    local color = self:_attackColor()
    local weakness, resistance = self:_defenderWeaknessResistance()
    local mask = bit.rshift(0x80, color)
    local effectiveness = 0
    if bit.band(weakness, mask) ~= 0 then
      damage = bit.band(damage * 2, 0xffff)
      effectiveness = bit.bor(effectiveness, bit.lshift(1, self.c.WEAKNESS))
    end
    if bit.band(resistance, mask) ~= 0 then
      damage = bit.band(damage - 30, 0xffff)
      effectiveness = bit.bor(effectiveness, bit.lshift(1, self.c.RESISTANCE))
    end
    self.memory:writeSymbol8("wDamageEffectiveness", effectiveness)
  end

  damage = self:_applyAttachedPlusPower(damage)
  self.duelVars:swapTurn()
  damage = self:_applyAttachedDefender(damage)
  local defenderDeck = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local defenderId = self.cardData:getCardIDFromDeckIndex(defenderDeck)
  local attackCategory = self.memory:readSymbol8("wLoadedAttackCategory")
  damage = self.status:handleDamageReduction(damage, attackCategory, defenderId)
  self.duelVars:swapTurn()

  -- Source detects 16-bit underflow with bit 7 of D and clamps it to zero.
  if bit.band(bit.rshift(damage, 8), 0x80) ~= 0 then damage = 0 end
  return damage
end

-- ApplyDamageModifiers_DamageToSelf:: used by confusion/recoil state paths.
function Combat:applyDamageModifiersToSelf(baseDamage)
  self.memory:writeSymbol8("wDamageEffectiveness", 0)
  if baseDamage == 0 then return 0 end
  local damage = bit.band(baseDamage, 0xffff)
  local color = self:_attackColor()
  local changedWeak = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_CHANGED_WEAKNESS)
  local changedRes = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_CHANGED_RESISTANCE)
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
  local card = assert(self.cardData:get(cardId))
  local weakness = changedWeak ~= 0 and changedWeak or card.weakness
  local resistance = changedRes ~= 0 and changedRes or card.resistance
  local mask = bit.rshift(0x80, color)
  local effectiveness = 0
  if bit.band(weakness, mask) ~= 0 then
    damage = bit.band(damage * 2, 0xffff)
    effectiveness = bit.bor(effectiveness, bit.lshift(1, self.c.WEAKNESS))
  end
  if bit.band(resistance, mask) ~= 0 then
    damage = bit.band(damage - 30, 0xffff)
    effectiveness = bit.bor(effectiveness, bit.lshift(1, self.c.RESISTANCE))
  end
  self.memory:writeSymbol8("wDamageEffectiveness", effectiveness)
  damage = self:_applyAttachedPlusPower(damage)
  damage = self:_applyAttachedDefender(damage)
  if bit.band(bit.rshift(damage, 8), 0x80) ~= 0 then damage = 0 end
  return damage
end

-- CheckSelfConfusionDamage:: returns true when tails causes the attack to hit
-- the attacker for 20 instead.  Heads continues the selected attack.
function Combat:checkSelfConfusionDamage()
  self.memory:writeSymbol8("wConfusionAttackCheckWasUnsuccessful", 0)
  local status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
  if bit.band(status, self.c.CNF_SLP_PRZ) ~= self.c.CONFUSED then return false end
  local result, err = self.setup:tossCoin()
  if result == nil then return nil, err end
  if result == self.c.HEADS then return false end
  self.memory:writeSymbol8("wConfusionAttackCheckWasUnsuccessful", 1)
  return true
end

function Combat:handleConfusionDamageToSelf()
  local savedNoDamage = self.memory:readSymbol8("wNoDamageOrEffect")
  local savedDefender = self.memory:readSymbol8("wTempNonTurnDuelistCardID")
  local attackerId = self.memory:readSymbol8("wTempTurnDuelistCardID")
  self.memory:writeSymbol8("wNoDamageOrEffect", 0)
  self.memory:writeSymbol8("wIsDamageToSelf", 1)
  self.memory:writeSymbol8("wTempNonTurnDuelistCardID", attackerId)
  self:_writeDamage(20)
  local damage = self:applyDamageModifiersToSelf(self:_readDamage())
  local remaining = self.duelOps:subtractHP(self.c.DUELVARS_ARENA_CARD_HP, damage)
  self:_event("confusion_self_damage", { damage = damage, remainingHP = remaining })
  self.memory:writeSymbol8("wTempNonTurnDuelistCardID", savedDefender)
  self.memory:writeSymbol8("wNoDamageOrEffect", savedNoDamage)
  local resolution, err = self.knockouts:handlePendingResolution()
  if err then return false, err end
  self.core:clearNonTurnTemporaryDuelvars()
  return true, resolution and "resolved_knockout" or "confusion_self_damage"
end

-- DealRecoilDamageToSelf:: / DealConfusionDamageToSelf:: shared arithmetic.
-- Recoil is resolved during AFTER_DAMAGE; final KO/prize handling remains in
-- HandleAfterDamageEffects after the effect command returns.
function Combat:dealRecoilDamageToSelf(amount)
  local savedNoDamage = self.memory:readSymbol8("wNoDamageOrEffect")
  local savedDefender = self.memory:readSymbol8("wTempNonTurnDuelistCardID")
  local attackerId = self.memory:readSymbol8("wTempTurnDuelistCardID")
  self.memory:writeSymbol8("wLoadedAttackAnimation", self.c.ATK_ANIM_HIT_RECOIL)
  self.memory:writeSymbol8("wNoDamageOrEffect", 0)
  self.memory:writeSymbol8("wTempNonTurnDuelistCardID", attackerId)
  self:_writeDamage(amount)
  local damage = self:applyDamageModifiersToSelf(self:_readDamage())
  local remaining = self.duelOps:subtractHP(self.c.DUELVARS_ARENA_CARD_HP, damage)
  self:_event("recoil_damage", { requested = amount, damage = damage, remainingHP = remaining })
  self.memory:writeSymbol8("wTempNonTurnDuelistCardID", savedDefender)
  self.memory:writeSymbol8("wNoDamageOrEffect", savedNoDamage)
  return remaining
end


-- DealDamageToPlayAreaPokemon:: state path used by bench/residual effects.
-- `targetNonTurn` means the selected Play Area belongs to the defending side.
-- The routine intentionally omits Weakness/Resistance, matching the source.
function Combat:dealDamageToPlayAreaPokemon(playAreaSlot, requestedDamage, targetNonTurn, options)
  options = options or {}
  if targetNonTurn then self.duelVars:swapTurn() end

  local function finish(value, err)
    if targetNonTurn then self.duelVars:swapTurn() end
    return value, err
  end

  if playAreaSlot == self.c.PLAY_AREA_ARENA
      and self.memory:readSymbol8("wNoDamageOrEffect") ~= 0 then
    return finish(0)
  end
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + playAreaSlot)
  if deckIndex == 0xff then return finish(0) end
  local defenderId = self.cardData:getCardIDFromDeckIndex(deckIndex)
  local attackCategory = self.memory:readSymbol8("wLoadedAttackCategory")
  local isDamageToSelf = options.isDamageToSelf == true
  local attackerId = self.memory:readSymbol8("wTempTurnDuelistCardID")
  self.memory:writeSymbol8("wTempPlayAreaLocation_cceb", playAreaSlot)
  self.memory:writeSymbol8("wTempNonTurnDuelistCardID", defenderId)
  self.memory:writeSymbol8("wNoDamageOrEffect", 0)
  self.memory:writeSymbol8("wIsDamageToSelf", isDamageToSelf and self.c.TRUE or self.c.FALSE)

  local damage = bit.band(requestedDamage, 0xffff)
  if playAreaSlot == self.c.PLAY_AREA_ARENA then
    if isDamageToSelf then
      damage = bit.band(damage + 10 * self.duelOps:countCardIDInLocation(
        self.c.PLUSPOWER, self.c.CARD_LOCATION_ARENA), 0xffff)
    else
      self.duelVars:swapTurn()
      damage = bit.band(damage + 10 * self.duelOps:countCardIDInLocation(
        self.c.PLUSPOWER, self.c.CARD_LOCATION_ARENA), 0xffff)
      self.duelVars:swapTurn()
    end
  end

  if attackCategory ~= self.c.POKEMON_POWER then
    local location = bit.bor(self.c.CARD_LOCATION_PLAY_AREA, playAreaSlot)
    local defenders = self.duelOps:countCardIDInLocation(self.c.DEFENDER, location)
    damage = bit.band(damage - defenders * 20, 0xffff)
  end

  if playAreaSlot == self.c.PLAY_AREA_ARENA then
    self.status:handleNoDamageOrEffectSubstatus(attackerId, attackCategory, isDamageToSelf)
    damage = self.status:handleDamageReduction(damage, attackCategory, defenderId)
  else
    local adjusted, err = self.status:handlePlayAreaPokemonPowerDamage(
      damage, attackCategory, defenderId, playAreaSlot, attackerId, isDamageToSelf)
    if adjusted == nil then return finish(nil, err) end
    damage = adjusted
  end
  if bit.band(bit.rshift(damage, 8), 0x80) ~= 0 then damage = 0 end

  if playAreaSlot == self.c.PLAY_AREA_ARENA then
    local dealtAddr, dealtBank = self.memory:address("wDealtDamage")
    local dealt = self.memory:read8("wram", dealtAddr, dealtBank)
      + 0x100 * self.memory:read8("wram", dealtAddr + 1, dealtBank)
    dealt = bit.band(dealt + damage, 0xffff)
    self.memory:write8("wram", dealtAddr, lo(dealt), dealtBank)
    self.memory:write8("wram", dealtAddr + 1, hi(dealt), dealtBank)
  end

  local hpOffset = self.c.DUELVARS_ARENA_CARD_HP + playAreaSlot
  local remaining = self.duelOps:subtractHP(hpOffset, damage)
  self:_event("play_area_damage", { slot = playAreaSlot, damage = damage,
    requested = requestedDamage, remainingHP = remaining, cardId = defenderId,
    targetNonTurn = targetNonTurn == true })

  -- HandleStrikesBack_AgainstDamagingAttack:: Machamp bounces 10 damage to the
  -- attacker when its Power is active. Bench Machamp does not perform the arena
  -- status-incapability check in the original routine.
  if damage ~= 0 and not isDamageToSelf and defenderId == self.c.MACHAMP
      and attackCategory ~= self.c.POKEMON_POWER then
    local _, muk = self.status:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
    local capable = true
    if playAreaSlot == self.c.PLAY_AREA_ARENA then
      capable = not self.status:checkIsIncapableOfUsingPkmnPower(self.c.PLAY_AREA_ARENA)
    end
    if not muk and capable then
      self.duelVars:swapTurn()
      local attackerRemaining = self.duelOps:subtractHP(self.c.DUELVARS_ARENA_CARD_HP, 10)
      self.duelVars:swapTurn()
      self:_event("strikes_back", { damage = 10, remainingHP = attackerRemaining })
    end
  end
  return finish(damage)
end

function Combat:dealDamageToAllBenchedPokemon(amount, targetNonTurn, options)
  if targetNonTurn then self.duelVars:swapTurn() end
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if targetNonTurn then self.duelVars:swapTurn() end
  for slot = self.c.PLAY_AREA_BENCH_1, count - 1 do
    local damage, err = self:dealDamageToPlayAreaPokemon(slot, amount, targetNonTurn, options)
    if damage == nil then return nil, err end
  end
  return true
end

-- ApplyTransparencyIfApplicable:: state behavior after damage modifiers.  It
-- only runs when the attack would otherwise change damage/substatus/status.
function Combat:applyTransparencyIfApplicable(damage, attackCategory)
  if bit.band(attackCategory, self.c.RESIDUAL) ~= 0 then return damage end
  if self.memory:readSymbol8("wNoDamageOrEffect") ~= 0 then return damage end
  local defenderSub2 = self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_SUBSTATUS2)
  local queueIndex = self.memory:readSymbol8("wStatusConditionQueueIndex")
  if damage == 0 and defenderSub2 == 0 and queueIndex == 0 then return damage end

  self.duelVars:swapTurn()
  local defenderDeck = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local defenderId = self.cardData:getCardIDFromDeckIndex(defenderDeck)
  local prevented, err = self.status:handleTransparency(attackCategory, defenderId)
  self.duelVars:swapTurn()
  if prevented == nil then return nil, err end
  if not prevented then return damage end
  self.duelVars:setNonTurn(self.c.DUELVARS_ARENA_CARD_SUBSTATUS2, 0)
  return 0
end

function Combat:checkAttackUsable(deckIndex, attackIndex, options)
  options = options or {}
  local row, attack, cardId = self:loadAttack(deckIndex, attackIndex)
  if attack.nameTextId == 0 or attack.category == self.c.POKEMON_POWER then
    return false, "no_attack"
  end
  if self.status:handleCantAttackSubstatus() then return false, "cant_attack_substatus" end

  local status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
  local condition = bit.band(status, self.c.CNF_SLP_PRZ)
  if condition == self.c.PARALYZED or condition == self.c.ASLEEP then
    return false, "status"
  end
  if self.status:handleAmnesiaSubstatus() then return false, "amnesia" end

  local enough, reason = self:hasEnoughEnergy(deckIndex, attackIndex)
  if not enough then return false, reason end
  local phases = {
    self.c.EFFECTCMDTYPE_INITIAL_EFFECT_1,
    self.c.EFFECTCMDTYPE_DISCARD_ENERGY,
    self.c.EFFECTCMDTYPE_BEFORE_DAMAGE,
    self.c.EFFECTCMDTYPE_AFTER_DAMAGE,
  }
  if not options.aiPreparedSelections then
    phases[#phases + 1] = self.c.EFFECTCMDTYPE_INITIAL_EFFECT_2
    phases[#phases + 1] = self.c.EFFECTCMDTYPE_REQUIRE_SELECTION
  end
  local translated, effectReason = self.effects:validatePhases(phases)
  if not translated then return false, effectReason end
  return true, row, attack
end

function Combat:_executeEffectPhase(phase, context)
  context = context or {}
  context.combat = self
  local carry, err = self.effects:tryExecute(phase, context)
  if carry == nil then return nil, err end
  return carry
end

-- Preflight the ProcessPlayedPokemonCard trigger before mutating hand/play-area
-- state. A missing trigger command is normal; a present untranslated function
-- fails closed so placement never leaves a half-executed Pokemon Power.
function Combat:checkPlayedPokemonCardTrigger(deckIndex)
  local _, attack = self:loadAttack(deckIndex, self.c.FIRST_ATTACK_OR_PKMN_POWER)
  if attack.category ~= self.c.POKEMON_POWER then return true end
  return self.effects:validatePhases({ self.c.EFFECTCMDTYPE_PKMN_POWER_TRIGGER })
end

-- ProcessPlayedPokemonCard::. This is the trigger-only Pokemon Power path used
-- when a Pokemon enters play. Presentation is adapter-owned; source RAM and
-- effect-dispatch ordering are preserved.
function Combat:processPlayedPokemonCard(deckIndex, playAreaSlot)
  local _, attack, cardId = self:loadAttack(deckIndex, self.c.FIRST_ATTACK_OR_PKMN_POWER)
  self:updateArenaCardIDsAndClearTwoTurnDuelVars()
  self.memory:writeSymbol8("hTempCardIndex_ff9f", deckIndex)
  self.memory:writeSymbol8("wTempTurnDuelistCardID", cardId)
  if attack.category ~= self.c.POKEMON_POWER then return true, "no_trigger_power" end

  local failed, exchangeErr = self.setup:exchangeRNG()
  if failed then return false, exchangeErr end
  if cardId ~= self.c.MUK
      and self.status:checkIsIncapableOfUsingPkmnPower(self.c.PLAY_AREA_BENCH_1) then
    failed, exchangeErr = self.setup:exchangeRNG()
    if failed then return false, exchangeErr end
    return true, "pokemon_power_suppressed"
  end

  local command, lookupErr = self.effects:checkMatchingCommand(self.c.EFFECTCMDTYPE_PKMN_POWER_TRIGGER)
  if lookupErr then return false, lookupErr end
  if not command then return true, "no_trigger_command" end

  failed, exchangeErr = self.setup:exchangeRNG()
  if failed then return false, exchangeErr end
  local carry, err = self:_executeEffectPhase(self.c.EFFECTCMDTYPE_PKMN_POWER_TRIGGER,
    { powerSlot = playAreaSlot, triggered = true })
  if carry == nil then return false, err end
  self:_event("pokemon_power_trigger", { cardId = cardId, slot = playAreaSlot,
    functionLabel = command.functionLabel })
  return true, carry and "trigger_carried" or "triggered"
end

-- UsePokemonPower::. Manual Pokemon Powers use their own phase subset and do
-- not enter the ordinary damage pipeline. Selection remains a host boundary.
function Combat:usePokemonPower(deckIndex, attackIndex, playAreaSlot, options)
  options = options or {}
  local row, attack, cardId = self:loadAttack(deckIndex, attackIndex)
  if attack.category ~= self.c.POKEMON_POWER then return false, "not_pokemon_power" end
  playAreaSlot = playAreaSlot or self.c.PLAY_AREA_ARENA
  if self.status:checkIsIncapableOfUsingPkmnPower(playAreaSlot) then
    return false, "pokemon_power_incapable"
  end
  local translated, reason = self.effects:validatePhases({
    self.c.EFFECTCMDTYPE_INITIAL_EFFECT_2,
    self.c.EFFECTCMDTYPE_REQUIRE_SELECTION,
    self.c.EFFECTCMDTYPE_BEFORE_DAMAGE,
  })
  if not translated then return false, reason end

  self.memory:writeSymbol8("wPlayerAttackingAttackIndex", attackIndex)
  self.memory:writeSymbol8("wPlayerAttackingCardIndex", deckIndex)
  self.memory:writeSymbol8("wPlayerAttackingCardID", cardId)
  local context = { selection = options.selection, powerSlot = playAreaSlot }
  local carry, err = self:_executeEffectPhase(self.c.EFFECTCMDTYPE_INITIAL_EFFECT_2, context)
  if carry == nil then return false, err end
  if carry then return false, "pokemon_power_initial_rejected" end
  carry, err = self:_executeEffectPhase(self.c.EFFECTCMDTYPE_REQUIRE_SELECTION, context)
  if carry == nil then return false, err end
  if carry then return false, "pokemon_power_selection_rejected" end
  local failed, exchangeErr = self.setup:exchangeRNG()
  if failed then return false, exchangeErr end
  carry, err = self:_executeEffectPhase(self.c.EFFECTCMDTYPE_BEFORE_DAMAGE, context)
  if carry == nil then return false, err end
  self:_event("pokemon_power", { cardId = cardId, attack = attackIndex, slot = playAreaSlot })
  return true, "pokemon_power"
end

-- UseAttackOrPokemonPower:: + PlayAttackAnimation_DealAttackDamage::. The
-- command-phase order now follows the cartridge generically; only individual
-- function identities absent from EffectCommands.lua remain fail-closed.
function Combat:useAttack(deckIndex, attackIndex, options)
  options = options or {}
  local _, loadedAttack = self:loadAttack(deckIndex, attackIndex)
  if loadedAttack.category == self.c.POKEMON_POWER then
    return self:usePokemonPower(deckIndex, attackIndex, options.playAreaSlot, options)
  end
  local usable, reason = self:checkAttackUsable(deckIndex, attackIndex, options)
  if not usable then return false, reason end

  local row, attack, cardId = self:loadAttack(deckIndex, attackIndex)
  local effectContext = { selection = options.selection }
  self.memory:writeSymbol8("wPlayerAttackingAttackIndex", attackIndex)
  self.memory:writeSymbol8("wPlayerAttackingCardIndex", deckIndex)
  self.memory:writeSymbol8("wPlayerAttackingCardID", cardId)

  if options.verifyPractice ~= false then
    local repeatTurn = self.practice:doAction(self.c.PRACTICEDUEL_VERIFY_PLAYER_TURN_ACTIONS)
    if repeatTurn then return false, "repeat_practice" end
  end

  self:updateArenaCardIDsAndClearTwoTurnDuelVars()
  local carry, effectErr = self:_executeEffectPhase(self.c.EFFECTCMDTYPE_INITIAL_EFFECT_1, effectContext)
  if carry == nil then return false, effectErr end
  if carry then return false, "initial_effect_1_rejected" end

  if self.status:checkSandAttackOrSmokescreenSubstatus() then
    local failed, err = self.status:handleSandAttackOrSmokescreenSubstatus()
    if failed == nil then return false, err end
    if failed then
      self.core:clearNonTurnTemporaryDuelvars()
      return true, "attack_unsuccessful"
    end
  end

  if not options.aiPreparedSelections then
    carry, effectErr = self:_executeEffectPhase(self.c.EFFECTCMDTYPE_INITIAL_EFFECT_2, effectContext)
    if carry == nil then return false, effectErr end
    if carry then return false, "initial_effect_2_rejected" end
  end

  -- INITIAL_EFFECT_2 may replace the loaded attack (Metronome). Re-read the
  -- cartridge buffer so residual/prevention/Transparency use the copied attack.
  local activeAttackCategory = self.memory:readSymbol8("wLoadedAttackCategory")

  carry, effectErr = self:_executeEffectPhase(self.c.EFFECTCMDTYPE_DISCARD_ENERGY, effectContext)
  if carry == nil then return false, effectErr end

  local confused, confusionErr = self:checkSelfConfusionDamage()
  if confused == nil then return false, confusionErr end
  if confused then return self:handleConfusionDamageToSelf() end

  local transmission, exchangeErr = self.setup:exchangeRNG()
  if transmission then return false, exchangeErr end

  if not options.aiPreparedSelections then
    carry, effectErr = self:_executeEffectPhase(self.c.EFFECTCMDTYPE_REQUIRE_SELECTION, effectContext)
    if carry == nil then return false, effectErr end
  end

  self:_applyNoDamageOrEffectPrevention(cardId, { category = activeAttackCategory })
  self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", self.c.PLAY_AREA_ARENA)
  carry, effectErr = self:_executeEffectPhase(self.c.EFFECTCMDTYPE_BEFORE_DAMAGE, effectContext)
  if carry == nil then return false, effectErr end

  local damage, damageErr = self:applyDamageModifiers(self:_readDamage())
  if damage == nil then return false, damageErr end
  damage, damageErr = self:applyTransparencyIfApplicable(damage, activeAttackCategory)
  if damage == nil then return false, damageErr end
  local dealt, dealtBank = self.memory:address("wDealtDamage")
  self.memory:write8("wram", dealt, lo(damage), dealtBank)
  self.memory:write8("wram", dealt + 1, hi(damage), dealtBank)

  self.duelVars:swapTurn()
  local remaining = self.duelOps:subtractHP(self.c.DUELVARS_ARENA_CARD_HP, damage)
  self.duelVars:swapTurn()
  self:_event("attack_damage", { cardId = cardId, attack = attackIndex,
    damage = damage, remainingHP = remaining })

  carry, effectErr = self:_executeEffectPhase(self.c.EFFECTCMDTYPE_AFTER_DAMAGE, effectContext)
  if carry == nil then return false, effectErr end
  self.status:applyStatusConditionQueue()
  self.core:updateArenaCardLastTurnDamage()
  local resolution, err = self.knockouts:handlePendingResolution()
  if err then return false, err end
  return true, resolution and "resolved_knockout" or "attacked"
end

return Combat
