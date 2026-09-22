-- Turn-boundary status and Pokemon Power activity routines translated from
-- pret/poketcg src/home/substatus.asm and src/engine/duel/core.asm.

local bit = require("bit")

local Status = {}
Status.__index = Status

local function clearBit(value, bitIndex)
  return bit.band(value, bit.bnot(bit.lshift(1, bitIndex)))
end

function Status.new(memory, duelVars, cardData, duelOps, setup, constants, adapters)
  return setmetatable({
    memory = assert(memory),
    duelVars = assert(duelVars),
    cardData = assert(cardData),
    duelOps = assert(duelOps),
    setup = assert(setup),
    c = assert(constants),
    adapters = adapters or {},
    knockouts = nil,
  }, Status)
end

function Status:setKnockOuts(knockouts)
  self.knockouts = assert(knockouts)
end

function Status:_event(name, payload)
  local fn = self.adapters.event
  if fn then fn(name, payload or {}) end
end

-- ClearDamageReductionSubstatus2::
function Status:clearDamageReductionSubstatus2()
  local value = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_SUBSTATUS2)
  if value == 0 then return end
  if value == self.c.SUBSTATUS2_REDUCE_BY_20
      or value == self.c.SUBSTATUS2_POUNCE
      or value == self.c.SUBSTATUS2_GROWL
      or value == self.c.SUBSTATUS2_TAIL_WAG
      or value == self.c.SUBSTATUS2_LEER then
    self.duelVars:set(self.c.DUELVARS_ARENA_CARD_SUBSTATUS2, 0)
  end
end

function Status:updateSubstatusConditionsStartOfTurn()
  local old = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_SUBSTATUS1)
  self.duelVars:set(self.c.DUELVARS_ARENA_CARD_SUBSTATUS1, 0)
  if old == self.c.SUBSTATUS1_NEXT_TURN_DOUBLE_DAMAGE then
    local sub3 = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_SUBSTATUS3)
    self.duelVars:set(self.c.DUELVARS_ARENA_CARD_SUBSTATUS3,
      bit.bor(sub3, bit.lshift(1, self.c.SUBSTATUS3_THIS_TURN_DOUBLE_DAMAGE_F)))
  end
end

function Status:updateSubstatusConditionsEndOfTurn()
  local sub3 = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_SUBSTATUS3)
  sub3 = clearBit(sub3, self.c.SUBSTATUS3_HEADACHE_F)
  self.duelVars:set(self.c.DUELVARS_ARENA_CARD_SUBSTATUS3, sub3)
  self.duelVars:set(self.c.DUELVARS_ARENA_CARD_SUBSTATUS2, 0)
  local sub1 = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_SUBSTATUS1)
  if sub1 ~= self.c.SUBSTATUS1_NEXT_TURN_DOUBLE_DAMAGE then
    sub3 = clearBit(sub3, self.c.SUBSTATUS3_THIS_TURN_DOUBLE_DAMAGE_F)
    self.duelVars:set(self.c.DUELVARS_ARENA_CARD_SUBSTATUS3, sub3)
  end
end

-- CountTurnDuelistPokemonWithActivePkmnPower::
function Status:countTurnDuelistPokemonWithActivePkmnPower(cardId)
  self.memory:writeSymbol8("wTempPokemonID_ce7c", cardId)
  local count = 0
  local arena = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  if arena ~= 0xff and self.cardData:getCardIDFromDeckIndex(arena) == cardId then
    local status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
    if bit.band(status, self.c.CNF_SLP_PRZ) == 0 then count = count + 1 end
  end

  local slot = self.c.PLAY_AREA_BENCH_1
  while slot < self.c.MAX_PLAY_AREA_POKEMON do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
    if deckIndex == 0xff then break end
    if self.cardData:getCardIDFromDeckIndex(deckIndex) == cardId then count = count + 1 end
    slot = slot + 1
  end
  return count, count ~= 0
end

function Status:countPokemonWithActivePkmnPowerInBothPlayAreas(cardId)
  self.memory:writeSymbol8("wTempPokemonID_ce7c", cardId)
  local first = self:countTurnDuelistPokemonWithActivePkmnPower(cardId)
  self.duelVars:swapTurn()
  local second = self:countTurnDuelistPokemonWithActivePkmnPower(cardId)
  self.duelVars:swapTurn()
  local total = (first + second) % 0x100
  return total, total ~= 0
end

function Status:isClairvoyanceActive()
  local _, muk = self:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
  if muk then return false end
  local _, omanyte = self:countTurnDuelistPokemonWithActivePkmnPower(self.c.OMANYTE)
  return omanyte
end

-- GetPlayAreaCardColor:: accounting for Venomoth Shift when its Power is active.
function Status:getPlayAreaCardColor(playAreaOffset)
  local changed = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_CHANGED_TYPE + playAreaOffset)
  if bit.band(changed, bit.lshift(1, self.c.HAS_CHANGED_COLOR_F)) ~= 0
      and not self:checkIsIncapableOfUsingPkmnPower(playAreaOffset) then
    return bit.band(changed, 0x0f)
  end
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + playAreaOffset)
  if deckIndex == 0xff then return nil end
  local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
  local row = assert(self.cardData:get(cardId))
  if row.type == self.c.TYPE_TRAINER then return self.c.COLORLESS end
  return row.type
end

-- IsRainDanceActive:: Blastoise must be present and Power-capable, and Muk's
-- Toxic Gas must not be active anywhere in either Play Area.
function Status:isRainDanceActive()
  local _, blastoise = self:countTurnDuelistPokemonWithActivePkmnPower(self.c.BLASTOISE)
  if not blastoise then return false end
  local _, muk = self:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
  return not muk
end

-- HandleEnergyBurn:: source state transformation used immediately after
-- GetPlayAreaCardAttachedEnergies. Only the colored-energy buckets are zeroed;
-- the source then writes the total attached-energy count into FIRE.
function Status:handleEnergyBurn()
  local arena = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  if arena == 0xff or self.cardData:getCardIDFromDeckIndex(arena) ~= self.c.CHARIZARD then
    return false
  end
  if self:checkIsIncapableOfUsingPkmnPower(self.c.PLAY_AREA_ARENA) then return false end
  local base, bank = self.memory:address("wAttachedEnergies")
  for i = 0, self.c.NUM_COLORED_TYPES - 1 do
    self.memory:write8("wram", base + i, 0, bank)
  end
  self.memory:write8("wram", base + self.c.FIRE,
    self.memory:readSymbol8("wTotalAttachedEnergies"), bank)
  return true
end

-- CheckIsIncapableOfUsingPkmnPower:: boolean carry form.
function Status:checkIsIncapableOfUsingPkmnPower(playAreaOffset)
  if playAreaOffset == self.c.PLAY_AREA_ARENA then
    local arenaStatus = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
    if bit.band(arenaStatus, self.c.CNF_SLP_PRZ) ~= 0 then return true end
  end
  local _, muk = self:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
  return muk
end

-- HandleCantAttackSubstatus::.
function Status:handleCantAttackSubstatus()
  local value = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_SUBSTATUS2)
  return value == self.c.SUBSTATUS2_TAIL_WAG
    or value == self.c.SUBSTATUS2_LEER
    or value == self.c.SUBSTATUS2_BONE_ATTACK
end

-- HandleAmnesiaSubstatus::.
function Status:handleAmnesiaSubstatus()
  local value = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_SUBSTATUS2)
  if value ~= self.c.SUBSTATUS2_AMNESIA then return false end
  return self.memory:readSymbol8("wSelectedAttack")
    == self.duelVars:get(self.c.DUELVARS_ARENA_CARD_DISABLED_ATTACK_INDEX)
end

-- CheckCantUseTrainerDueToEffect::. Headache blocks Trainer cards until the
-- source clears the SUBSTATUS3 bit at the end of the affected turn.
function Status:checkCantUseTrainerDueToEffect()
  local sub3 = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_SUBSTATUS3)
  return bit.band(sub3, bit.lshift(1, self.c.SUBSTATUS3_HEADACHE_F)) ~= 0
end

-- CheckSandAttackOrSmokescreenSubstatus::.
function Status:checkSandAttackOrSmokescreenSubstatus()
  local value = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_SUBSTATUS2)
  if value ~= self.c.SUBSTATUS2_SAND_ATTACK and value ~= self.c.SUBSTATUS2_SMOKESCREEN then
    return false
  end
  return self.memory:readSymbol8("wGotHeadsFromSandAttackOrSmokescreenCheck") == 0
end

-- HandleSandAttackOrSmokescreenSubstatus::. Carry is returned as true.
function Status:handleSandAttackOrSmokescreenSubstatus()
  if not self:checkSandAttackOrSmokescreenSubstatus() then return false end
  local result, err = self.setup:tossCoin()
  if result == nil then return nil, err end
  self.memory:writeSymbol8("wGotHeadsFromSandAttackOrSmokescreenCheck", result)
  return result == self.c.TAILS
end

-- ApplySubstatus1ToAttackingCard:: state mutation.
function Status:applySubstatus1ToAttackingCard(value)
  self.duelVars:set(self.c.DUELVARS_ARENA_CARD_SUBSTATUS1, value)
  return true
end

-- ApplySubstatus2ToDefendingCard:: state mutation. The source first checks
-- wNoDamageOrEffect, then writes both current and last-turn substatus bytes.
function Status:applySubstatus2ToDefendingCard(value)
  local prevented = self:checkNoDamageOrEffect()
  if prevented then return false end
  self.duelVars:setNonTurn(self.c.DUELVARS_ARENA_CARD_SUBSTATUS2, value)
  self.duelVars:setNonTurn(self.c.DUELVARS_ARENA_CARD_LAST_TURN_SUBSTATUS2, value)
  return true
end

-- HandleDoubleDamageSubstatus:: state behavior.  Swords Dance / Focus Energy
-- promote NEXT_TURN_DOUBLE_DAMAGE into the SUBSTATUS3 flag at turn start; the
-- source doubles DE before weakness/resistance and attached Trainer modifiers.
function Status:handleDoubleDamageSubstatus(damage)
  local sub3 = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_SUBSTATUS3)
  if bit.band(sub3, bit.lshift(1, self.c.SUBSTATUS3_THIS_TURN_DOUBLE_DAMAGE_F)) ~= 0
      and damage ~= 0 then
    return bit.band(damage * 2, 0xffff)
  end
  return damage
end

-- The cartridge's halve-damage helper is intentionally byte-oriented and has
-- a documented `sla d` bug where an arithmetic right shift was expected. Keep
-- those exact byte operations instead of replacing them with damage / 2.
local function sourceHalveDamage(damage)
  local e = bit.band(damage, 0xff)
  local d = bit.band(bit.rshift(damage, 8), 0xff)
  local carry = bit.band(d, 0x80) ~= 0 and 1 or 0
  d = bit.band(bit.lshift(d, 1), 0xff)
  e = bit.bor(bit.rshift(e, 1), carry * 0x80)
  local result = bit.bor(bit.lshift(d, 8), e)
  if bit.band(e, 1) ~= 0 then result = bit.band(result - 5, 0xffff) end
  return result
end

-- HandleDamageReductionExceptSubstatus2:: translated state path.  This method
-- is called while the defending duelist is the turn holder, matching the
-- source perspective inside ApplyDamageModifiers_DamageToTarget.
function Status:handleDamageReductionExceptSubstatus2(damage, attackCategory, defenderCardId)
  if self.memory:readSymbol8("wNoDamageOrEffect") ~= 0 then return 0 end

  local sub1 = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_SUBSTATUS1)
  if sub1 == self.c.SUBSTATUS1_NO_DAMAGE_STIFFEN
      or sub1 == self.c.SUBSTATUS1_NO_DAMAGE_WITHDRAW
      or sub1 == self.c.SUBSTATUS1_NO_DAMAGE_HIDE_IN_SHELL
      or sub1 == self.c.SUBSTATUS1_NO_DAMAGE_SCRUNCH then
    return 0
  elseif sub1 == self.c.SUBSTATUS1_REDUCE_BY_10 then
    return bit.band(damage - 10, 0xffff)
  elseif sub1 == self.c.SUBSTATUS1_REDUCE_BY_20 then
    return bit.band(damage - 20, 0xffff)
  elseif sub1 == self.c.SUBSTATUS1_PREVENT_LESS_THAN_40 then
    if damage < 40 then return 0 end
  elseif sub1 == self.c.SUBSTATUS1_HALVE_DAMAGE then
    return sourceHalveDamage(damage)
  end

  if self:checkIsIncapableOfUsingPkmnPower(self.c.PLAY_AREA_ARENA) then
    return damage
  end
  if attackCategory == self.c.POKEMON_POWER then return damage end

  if defenderCardId == self.c.MR_MIME then
    -- Invisible Wall prevents attacks dealing 30 or more damage.
    if damage >= 30 then return 0 end
  elseif defenderCardId == self.c.KABUTO then
    -- Kabuto Armor uses the same buggy halve helper as the source.
    return sourceHalveDamage(damage)
  end
  return damage
end

-- HandleDamageReduction:: adds the attacker's SUBSTATUS2 reduction after the
-- defender's SUBSTATUS1/Pokemon-Power handling.  Because this runs from the
-- defender perspective, GetNonTurnDuelistVariable refers to the attacker.
function Status:handleDamageReduction(damage, attackCategory, defenderCardId)
  damage = self:handleDamageReductionExceptSubstatus2(
    damage, attackCategory, defenderCardId)
  local sub2 = self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_SUBSTATUS2)
  if sub2 == self.c.SUBSTATUS2_REDUCE_BY_20 then
    return bit.band(damage - 20, 0xffff)
  end
  if sub2 == self.c.SUBSTATUS2_POUNCE or sub2 == self.c.SUBSTATUS2_GROWL then
    return bit.band(damage - 10, 0xffff)
  end
  return damage
end


-- HandleDamageReductionOrNoDamageFromPkmnPowerEffects:: play-area branch used
-- by DealDamageToPlayAreaPokemon for Bench damage. Unlike the arena damage
-- path, this checks only Pokemon Power reductions/prevention for the selected
-- slot; SUBSTATUS1/SUBSTATUS2 are arena-only in the source.
function Status:handlePlayAreaPokemonPowerDamage(damage, attackCategory,
    defenderCardId, playAreaSlot, attackerCardId, isDamageToSelf)
  if attackCategory == self.c.POKEMON_POWER then return damage, false end
  local _, muk = self:countPokemonWithActivePkmnPowerInBothPlayAreas(self.c.MUK)
  if muk then return damage, false end
  if self:checkIsIncapableOfUsingPkmnPower(playAreaSlot) then return damage, false end

  if defenderCardId == self.c.MR_MIME then
    if damage >= 30 then damage = 0 end
  elseif defenderCardId == self.c.KABUTO then
    damage = sourceHalveDamage(damage)
  end

  if defenderCardId == self.c.MEW_LV8 and not isDamageToSelf then
    local attacker = assert(self.cardData:get(attackerCardId))
    if attacker.stage ~= self.c.BASIC then
      self.memory:writeSymbol8("wNoDamageOrEffect", self.c.NO_DAMAGE_OR_EFFECT_NSHIELD)
      return 0, true
    end
  elseif defenderCardId == self.c.HAUNTER_LV17 then
    local result, err = self.setup:tossCoin()
    if result == nil then return nil, err end
    if result == self.c.HEADS then
      self.memory:writeSymbol8("wNoDamageOrEffect", self.c.NO_DAMAGE_OR_EFFECT_TRANSPARENCY)
      return 0, true
    end
  end
  return damage, false
end


-- HandleDestinyBondSubstatus:: if the defending Arena Pokemon is knocked out
-- under Destiny Bond while the attacker still has HP, knock out the attacker.
function Status:handleDestinyBondSubstatus()
  if self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_SUBSTATUS1)
      ~= self.c.SUBSTATUS1_DESTINY_BOND then return false end
  if self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD) == 0xff then return false end
  if self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_HP) ~= 0 then return false end
  if self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP) == 0 then return false end
  self.duelVars:set(self.c.DUELVARS_ARENA_CARD_HP, 0)
  self:_event("destiny_bond_knockout", {})
  return true
end

-- HandleNoDamageOrEffectSubstatus:: state behavior.  Call this from the
-- defending duelist's perspective before BEFORE_DAMAGE effect commands.
function Status:handleNoDamageOrEffectSubstatus(attackerCardId, attackCategory, isDamageToSelf)
  self.memory:writeSymbol8("wNoDamageOrEffect", 0)
  if attackCategory == self.c.POKEMON_POWER then return false end

  local sub1 = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_SUBSTATUS1)
  local cause = nil
  if sub1 == self.c.SUBSTATUS1_FLY then
    cause = self.c.NO_DAMAGE_OR_EFFECT_FLY
  elseif sub1 == self.c.SUBSTATUS1_BARRIER then
    cause = self.c.NO_DAMAGE_OR_EFFECT_BARRIER
  elseif sub1 == self.c.SUBSTATUS1_AGILITY then
    cause = self.c.NO_DAMAGE_OR_EFFECT_AGILITY
  end
  if cause then
    self.memory:writeSymbol8("wNoDamageOrEffect", cause)
    return true
  end

  if self:checkIsIncapableOfUsingPkmnPower(self.c.PLAY_AREA_ARENA) then
    return false
  end
  local defenderDeck = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local defenderId = self.cardData:getCardIDFromDeckIndex(defenderDeck)
  if defenderId ~= self.c.MEW_LV8 or isDamageToSelf then return false end

  local attacker = assert(self.cardData:get(attackerCardId))
  if attacker.stage == self.c.BASIC then return false end
  self.memory:writeSymbol8("wNoDamageOrEffect", self.c.NO_DAMAGE_OR_EFFECT_NSHIELD)
  return true
end

-- HandleTransparency:: state branch.  This is called from the defending
-- duelist's perspective and preserves the source 50% coin result.
function Status:handleTransparency(attackCategory, defenderCardId)
  if defenderCardId ~= self.c.HAUNTER_LV17 then return false end
  if attackCategory == self.c.POKEMON_POWER then return false end
  if self:checkIsIncapableOfUsingPkmnPower(self.c.PLAY_AREA_ARENA) then
    return false
  end
  local result, err = self.setup:tossCoin()
  if result == nil then return nil, err end
  if result ~= self.c.HEADS then return false end
  self.memory:writeSymbol8("wNoDamageOrEffect",
    self.c.NO_DAMAGE_OR_EFFECT_TRANSPARENCY)
  return true
end

-- CheckNoDamageOrEffect:: state-relevant behavior.  The first check marks the
-- high bit so the source will not present the same prevention text twice.
function Status:checkNoDamageOrEffect()
  local value = self.memory:readSymbol8("wNoDamageOrEffect")
  if value == 0 then return false, false end
  local first = bit.band(value, 0x80) == 0
  if first then self.memory:writeSymbol8("wNoDamageOrEffect", bit.bor(value, 0x80)) end
  return true, first
end

-- QueueStatusCondition::. This is the shared queue used by Star Freeze and by
-- the full effect engine. Its target-page byte is the defending duel page.
function Status:queueStatusCondition(mask, condition)
  local attackTurn = self.duelVars:turn()
  local sourceTurn = self.memory:readSymbol8("wWhoseTurn")
  if attackTurn == sourceTurn then
    local defending = self.memory:readSymbol8("wTempNonTurnDuelistCardID")
    if defending == self.c.CLEFAIRY_DOLL or defending == self.c.MYSTERIOUS_FOSSIL then
      self.memory:writeSymbol8("wNoEffectFromWhichStatus", condition)
      self.memory:writeSymbol8("wEffectFailed", self.c.EFFECT_FAILED_NO_EFFECT)
      return false
    end
    if defending == self.c.SNORLAX then
      self.duelVars:swapTurn()
      local incapable = self:checkIsIncapableOfUsingPkmnPower(self.c.PLAY_AREA_ARENA)
      self.duelVars:swapTurn()
      if not incapable then
        self.memory:writeSymbol8("wNoEffectFromWhichStatus", condition)
        self.memory:writeSymbol8("wEffectFailed", self.c.EFFECT_FAILED_NO_EFFECT)
        return false
      end
    end
  end

  local index = self.memory:readSymbol8("wStatusConditionQueueIndex")
  local base, bank = self.memory:address("wStatusConditionQueue")
  local targetSide = self.duelVars:nonTurnHigh()
  self.memory:write8("wram", base + index, targetSide, bank)
  self.memory:write8("wram", base + index + 1, mask, bank)
  self.memory:write8("wram", base + index + 2, condition, bank)
  self.memory:writeSymbol8("wStatusConditionQueueIndex", bit.band(index + 3, 0xff))
  return true
end

-- ApplyStatusConditionQueue::. Each 3-byte item is side, preserve-mask, new
-- condition; the source clears both arena LAST_TURN_STATUS bytes first.
function Status:applyStatusConditionQueue()
  -- Source clears both LAST_TURN_STATUS bytes even when the queue is empty.
  local playerLast = self.c.PLAYER_TURN * 0x100 + self.c.DUELVARS_ARENA_CARD_LAST_TURN_STATUS
  local opponentLast = self.c.OPPONENT_TURN * 0x100 + self.c.DUELVARS_ARENA_CARD_LAST_TURN_STATUS
  self.memory:write8("wram", playerLast, 0, 0)
  self.memory:write8("wram", opponentLast, 0, 0)

  local index = self.memory:readSymbol8("wStatusConditionQueueIndex")
  if index == 0 then return false end
  local base, bank = self.memory:address("wStatusConditionQueue")
  self.memory:write8("wram", base + index, 0, bank)

  local noDamageOrEffect = self:checkNoDamageOrEffect()
  local applied = false
  local pos = 0
  while pos < index do
    local side = self.memory:read8("wram", base + pos, bank)
    if side == 0 then break end
    local mask = self.memory:read8("wram", base + pos + 1, bank)
    local condition = self.memory:read8("wram", base + pos + 2, bank)
    -- With No Damage or Effect active, the cartridge keeps only status entries
    -- whose target side is the turn duelist (self-inflicted effects).
    if not noDamageOrEffect or side == self.duelVars:turn() then
      local statusAddress = side * 0x100 + self.c.DUELVARS_ARENA_CARD_STATUS
      local lastAddress = side * 0x100 + self.c.DUELVARS_ARENA_CARD_LAST_TURN_STATUS
      local status = self.memory:read8("wram", statusAddress, 0)
      local last = self.memory:read8("wram", lastAddress, 0)
      self.memory:write8("wram", statusAddress,
        bit.bor(bit.band(status, mask), condition), 0)
      self.memory:write8("wram", lastAddress,
        bit.bor(bit.band(last, mask), condition), 0)
      applied = true
    end
    pos = pos + 3
  end
  return applied
end

-- IsArenaPokemonAsleepOrPoisoned:: returns (a, carry).
function Status:isArenaPokemonAsleepOrPoisoned()
  local status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
  if status == 0 then return 0, false end
  local poison = bit.band(status, bit.bor(self.c.POISONED, self.c.DOUBLE_POISONED))
  if poison ~= 0 then return poison, true end
  local condition = bit.band(status, self.c.CNF_SLP_PRZ)
  return condition, condition == self.c.ASLEEP
end

function Status:_setTempArenaCardID()
  local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  if deckIndex == 0xff then return nil end
  local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
  self.memory:writeSymbol8("wTempNonTurnDuelistCardID", cardId)
  return cardId
end

-- HandlePoisonDamage:: returns carry=true when the Pokemon reaches 0 HP.
function Status:handlePoisonDamage()
  local status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
  local poisoned = bit.band(status, bit.lshift(1, self.c.POISONED_F)) ~= 0
  if not poisoned then return false end
  local double = bit.band(status, bit.lshift(1, self.c.DOUBLE_POISONED_F)) ~= 0
  local damage = double and self.c.DBLPSN_DAMAGE or self.c.PSN_DAMAGE
  local anim, bank = self.memory:address("wDuelAnimDamage")
  self.memory:write8("wram", anim, damage, bank)
  self.memory:write8("wram", anim + 1, 0, bank)
  self:_event("poison_damage", { damage = damage, double = double })
  local remaining = self.duelOps:subtractHP(self.c.DUELVARS_ARENA_CARD_HP, damage)
  return remaining == 0
end

function Status:handleSleepCheck()
  local status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
  if bit.band(status, self.c.CNF_SLP_PRZ) ~= self.c.ASLEEP then return false end
  local result, err = self.setup:tossCoin()
  if result == nil then return nil, err end
  if result == self.c.HEADS then
    self.duelVars:set(self.c.DUELVARS_ARENA_CARD_STATUS,
      bit.band(status, self.c.DOUBLE_POISONED))
    self:_event("sleep_cured", {})
  else
    self:_event("still_asleep", {})
  end
  return false
end

function Status:_healParalysisIfNeeded()
  local status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
  if bit.band(status, self.c.CNF_SLP_PRZ) == self.c.PARALYZED then
    self.duelVars:set(self.c.DUELVARS_ARENA_CARD_STATUS,
      bit.band(status, self.c.DOUBLE_POISONED))
    self:_event("paralysis_cured", {})
  end
end

function Status:discardAttachedPlusPowers()
  for slot = 0, self.c.MAX_PLAY_AREA_POKEMON - 1 do
    self.duelVars:set(self.c.DUELVARS_ARENA_CARD_ATTACHED_PLUSPOWER + slot, 0)
  end
  self.duelOps:moveCardToDiscardPileIfInPlayArea(self.c.PLUSPOWER)
end

function Status:discardAttachedDefenders()
  for slot = 0, self.c.MAX_PLAY_AREA_POKEMON - 1 do
    self.duelVars:set(self.c.DUELVARS_ARENA_CARD_ATTACHED_DEFENDER + slot, 0)
  end
  self.duelOps:moveCardToDiscardPileIfInPlayArea(self.c.DEFENDER)
end

-- HandleBetweenTurnsEvents:: presentation calls are emitted as optional events;
-- state mutation and perspective order are source-exact.
function Status:handleBetweenTurnsEvents()
  local currentA, currentCarry = self:isArenaPokemonAsleepOrPoisoned()
  local something = currentCarry or currentA == self.c.PARALYZED
  if not something then
    self.duelVars:swapTurn()
    local _, otherCarry = self:isArenaPokemonAsleepOrPoisoned()
    self.duelVars:swapTurn()
    something = otherCarry
  end

  if not something then
    self:discardAttachedPlusPowers()
    self.duelVars:swapTurn()
    self:discardAttachedDefenders()
    self.duelVars:swapTurn()
    return false
  end

  self:_event("between_turns", {})
  self:_setTempArenaCardID()
  local status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
  if status ~= 0 then
    local knockedOut = self:handlePoisonDamage()
    if not knockedOut then
      local ok, err = self:handleSleepCheck()
      if ok == nil then return true, err end
      self:_healParalysisIfNeeded()
    end
  end

  self:discardAttachedPlusPowers()
  self.duelVars:swapTurn()
  self:_setTempArenaCardID()
  status = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_STATUS)
  if status ~= 0 then
    local knockedOut = self:handlePoisonDamage()
    if not knockedOut then
      local ok, err = self:handleSleepCheck()
      if ok == nil then
        self.duelVars:swapTurn()
        return true, err
      end
    end
  end
  self:discardAttachedDefenders()
  self.duelVars:swapTurn()

  assert(self.knockouts, "HandleBetweenTurnsEvents requires knockout resolver")
  return self.knockouts:handlePendingResolution()
end

return Status
