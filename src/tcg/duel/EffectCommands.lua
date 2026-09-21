-- Generic effect-command dispatcher translated from pret/poketcg
-- src/home/effect_commands.asm.  The generated effect table is extracted from
-- the validated ROM and cross-checked against engine/duel/effect_commands.asm.
-- Unknown function identities fail closed; command phases with no matching
-- record return normally, matching CheckMatchingCommand/TryExecute semantics.

local bit = require("bit")

local EffectCommands = {}
EffectCommands.__index = EffectCommands

function EffectCommands.new(memory, setup, status, constants, effectData, adapters)
  assert(type(effectData) == "table" and effectData.schema == 1,
    "unsupported generated TCG effect-data schema")
  local self = setmetatable({
    memory = assert(memory), setup = assert(setup), status = assert(status),
    c = assert(constants), data = effectData, adapters = adapters or {},
    handlers = {},
  }, EffectCommands)
  self:_installSharedHandlers()
  return self
end

function EffectCommands:setAI(ai)
  self.ai = assert(ai)
end

function EffectCommands:_event(name, payload)
  local fn = self.adapters.event
  if fn then fn(name, payload or {}) end
end

function EffectCommands:_effectPointer()
  local address, bank = self.memory:address("wLoadedAttackEffectCommands")
  local low = self.memory:read8("wram", address, bank)
  local high = self.memory:read8("wram", address + 1, bank)
  return low + high * 0x100
end

function EffectCommands:currentList()
  local pointer = self:_effectPointer()
  if pointer == 0 then return nil, pointer end
  return self.data.byAddress[pointer], pointer
end

-- CheckMatchingCommand:: source-equivalent lookup.  The cartridge scans the
-- zero-terminated list and stops at the first record with the requested type.
function EffectCommands:checkMatchingCommand(commandType)
  local list, pointer = self:currentList()
  if pointer == 0 then return nil end
  if not list then
    return nil, ("effect_command_pointer_not_extracted:$%04x"):format(pointer)
  end
  for _, command in ipairs(list.commands) do
    if command.type == commandType then return command end
  end
  return nil
end

function EffectCommands:register(functionLabel, fn)
  assert(type(functionLabel) == "string" and functionLabel ~= "")
  assert(type(fn) == "function")
  self.handlers[functionLabel] = fn
end

function EffectCommands:isTranslated(functionLabel)
  return self.handlers[functionLabel] ~= nil
end

-- Preflight only the phases the current execution path will actually request.
-- AI-only records do not block player attacks when their AI handler is absent.
function EffectCommands:validatePhases(phases)
  for _, phase in ipairs(phases) do
    local command, lookupErr = self:checkMatchingCommand(phase)
    if lookupErr then return false, lookupErr end
    if command and not self.handlers[command.functionLabel] then
      return false, "untranslated_effect:" .. command.functionLabel
    end
  end
  return true
end

-- TryExecuteEffectCommandFunction::.  Return values are (carry, error, command).
-- No matching command is source success with carry clear.  A translated handler
-- returns its source carry state.  Missing handlers fail closed before mutation
-- when callers use validatePhases, and are guarded again here.
function EffectCommands:tryExecute(commandType, context)
  local command, lookupErr = self:checkMatchingCommand(commandType)
  if lookupErr then return nil, lookupErr end
  if not command then return false, nil, nil end
  local handler = self.handlers[command.functionLabel]
  if not handler then
    return nil, "untranslated_effect:" .. command.functionLabel, command
  end
  self:_event("effect_command", {
    phase = command.type,
    phaseName = command.typeName,
    functionLabel = command.functionLabel,
  })
  local carry, err = handler(self, context or {}, command)
  if carry == nil then return nil, err or ("effect_failed:" .. command.functionLabel), command end
  return carry == true, err, command
end

function EffectCommands:_tossThen(mask, condition)
  local result, err = self.setup:tossCoin()
  if result == nil then return nil, err end
  if result == self.c.TAILS then return false end
  return self.status:queueStatusCondition(mask, condition)
end

function EffectCommands:_setNoEffectFromStatus()
  self.memory:writeSymbol8("wEffectFailed", self.c.EFFECT_FAILED_NO_EFFECT)
  return false
end

function EffectCommands:_setWasUnsuccessful()
  self.memory:writeSymbol8("wEffectFailed", self.c.EFFECT_FAILED_UNSUCCESSFUL)
  return false
end

local function lo(value) return value % 0x100 end
local function hi(value) return math.floor(value / 0x100) % 0x100 end

function EffectCommands:_readWord(symbol)
  local address, bank = self.memory:address(symbol)
  return self.memory:read8("wram", address, bank)
    + 0x100 * self.memory:read8("wram", address + 1, bank)
end

function EffectCommands:_writeWord(symbol, value)
  local address, bank = self.memory:address(symbol)
  self.memory:write8("wram", address, lo(value), bank)
  self.memory:write8("wram", address + 1, hi(value), bank)
end

-- LoadNonPokemonCardEffectCommands:: useful state: trainer/energy card effect
-- pointers become the current wLoadedAttackEffectCommands pointer.
function EffectCommands:loadNonPokemonCardEffectCommands(deckIndex, cardData)
  local cardId = cardData:loadBuffer1FromDeckIndex(deckIndex)
  local row = assert(cardData:get(cardId))
  self:_writeWord("wLoadedAttackEffectCommands", row.effectCommands or 0)
  return row.effectCommands or 0, cardId
end

function EffectCommands:_setDefiniteDamage(value)
  value = value % 0x10000
  self:_writeWord("wDamage", value)
  self.memory:writeSymbol8("wAIMinDamage", lo(value))
  self.memory:writeSymbol8("wAIMaxDamage", lo(value))
  return false
end

function EffectCommands:_addToDamage(amount)
  self:_writeWord("wDamage", (self:_readWord("wDamage") + amount) % 0x10000)
  return false
end

function EffectCommands:_tossDamageMultiplier(coins, perHead)
  local heads, err = self.setup:tossCoinATimes(coins)
  if heads == nil then return nil, err end
  return self:_setDefiniteDamage(heads * perHead)
end

function EffectCommands:_actor(context)
  return context.combat or context.playerActions
end

function EffectCommands:_healAttackingArena(context, amount)
  local actor = self:_actor(context)
  if not actor then return nil, "effect_context_missing_actor" end
  local duelVars, cardData = actor.duelVars, actor.cardData
  local deckIndex = duelVars:get(self.c.DUELVARS_ARENA_CARD)
  if deckIndex == 0xff then return false end
  local cardId = cardData:getCardIDFromDeckIndex(deckIndex)
  local row = assert(cardData:get(cardId))
  local hp = duelVars:get(self.c.DUELVARS_ARENA_CARD_HP)
  local damage = row.hp - hp
  self:_writeWord("wUnused_HPRecoverAmount", amount)
  if damage <= 0 then return false end
  local heal = math.min(amount, damage)
  duelVars:set(self.c.DUELVARS_ARENA_CARD_HP, hp + heal)
  self:_event("heal_arena", { amount = heal, requested = amount, cardId = cardId })
  return false
end

function EffectCommands:_playAreaDamage(actor, slot)
  local deckIndex = actor.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
  if deckIndex == 0xff then return nil end
  local cardId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
  local row = assert(actor.cardData:get(cardId))
  local hp = actor.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
  return row.hp - hp, row.hp, hp, cardId
end

function EffectCommands:_selectPlayArea(context)
  if context.selection and context.selection.playArea ~= nil then
    return context.selection.playArea
  end
  local select = self.adapters.selectPlayArea
  if select then return select(context) end
  return nil, "selection_required:play_area"
end


function EffectCommands:_selection(context, key, adapterName, spec)
  if context.selection and context.selection[key] ~= nil then
    return context.selection[key]
  end
  local select = self.adapters[adapterName]
  if select then return select(context, spec or {}) end
  return nil, "selection_required:" .. key
end

function EffectCommands:_selectBench(context, actor, nonTurn, key)
  local slot, err = self:_selection(context, key,
    nonTurn and "selectOpponentBench" or "selectBench", { nonTurn = nonTurn })
  if slot == nil then return nil, err end
  if nonTurn then actor.duelVars:swapTurn() end
  local count = actor.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local valid = type(slot) == "number" and slot >= self.c.PLAY_AREA_BENCH_1
    and slot < count
    and actor.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot) ~= 0xff
    and actor.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot) ~= 0
  if nonTurn then actor.duelVars:swapTurn() end
  if not valid then return nil, "invalid_selection:" .. key end
  return slot
end

function EffectCommands:_selectAttachedEnergy(context, actor, nonTurn, playAreaSlot,
    key, requiredType)
  local deckIndex, err = self:_selection(context, key,
    nonTurn and "selectOpponentAttachedEnergy" or "selectAttachedEnergy", {
      nonTurn = nonTurn, playArea = playAreaSlot, energyType = requiredType,
    })
  if deckIndex == nil then return nil, err end
  if nonTurn then actor.duelVars:swapTurn() end
  local expected = bit.bor(self.c.CARD_LOCATION_PLAY_AREA, playAreaSlot)
  local valid = type(deckIndex) == "number" and deckIndex >= 0
    and deckIndex < self.c.DECK_SIZE and actor.duelVars:get(deckIndex) == expected
  if valid then
    local cardId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
    local row = actor.cardData:get(cardId)
    valid = row ~= nil and bit.band(row.type, bit.lshift(1, self.c.TYPE_ENERGY_F)) ~= 0
      and (requiredType == nil or row.type == requiredType)
  end
  if nonTurn then actor.duelVars:swapTurn() end
  if not valid then return nil, "invalid_selection:" .. key end
  return deckIndex
end

function EffectCommands:_hasBench(actor, nonTurn)
  if nonTurn then actor.duelVars:swapTurn() end
  local count = actor.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  if nonTurn then actor.duelVars:swapTurn() end
  return count >= 2
end

function EffectCommands:_hasAttachedEnergy(actor, nonTurn, playAreaSlot, requiredType)
  if nonTurn then actor.duelVars:swapTurn() end
  local count = actor.duelOps:createArenaOrBenchEnergyCardList(playAreaSlot)
  local found = false
  if count > 0 then
    local base, bank = actor.memory:address("wDuelTempList")
    for i = 0, count - 1 do
      local deckIndex = actor.memory:read8("wram", base + i, bank)
      local cardId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
      local row = actor.cardData:get(cardId)
      if requiredType == nil or (row and row.type == requiredType) then found = true break end
    end
  end
  if nonTurn then actor.duelVars:swapTurn() end
  return found
end

function EffectCommands:_isBasicEnergy(actor, deckIndex)
  if type(deckIndex) ~= "number" or deckIndex < 0 or deckIndex >= self.c.DECK_SIZE then
    return false
  end
  local cardId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
  local row = actor.cardData:get(cardId)
  return row ~= nil and row.type >= self.c.TYPE_ENERGY
    and row.type < self.c.TYPE_ENERGY_DOUBLE_COLORLESS
end

function EffectCommands:_cardsAtLocation(actor, location, predicate)
  local out = {}
  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    if actor.duelVars:get(deckIndex) == location
        and (predicate == nil or predicate(deckIndex)) then
      out[#out + 1] = deckIndex
    end
  end
  return out
end

function EffectCommands:_selectionList(context, key, adapterName, spec, minCount, maxCount)
  local values, err = self:_selection(context, key, adapterName, spec)
  if values == nil then return nil, err end
  if type(values) ~= "table" then return nil, "invalid_selection:" .. key end
  if minCount and #values < minCount then return nil, "invalid_selection:" .. key end
  if maxCount and #values > maxCount then return nil, "invalid_selection:" .. key end
  local seen = {}
  for _, value in ipairs(values) do
    if type(value) ~= "number" or seen[value] then
      return nil, "invalid_selection:" .. key
    end
    seen[value] = true
  end
  return values
end

function EffectCommands:_validateHandSelection(actor, deckIndex, trainerIndex)
  return type(deckIndex) == "number" and deckIndex >= 0 and deckIndex < self.c.DECK_SIZE
    and deckIndex ~= trainerIndex
    and actor.duelVars:get(deckIndex) == self.c.CARD_LOCATION_HAND
end

function EffectCommands:_installSharedHandlers()
  -- Generic AI damage-estimation primitives from effect_functions.asm.
  -- These are deliberately registered by source label rather than inferred
  -- from attack shape so EFFECTCMDTYPE_AI remains identity-exact.
  local function setExpectedAIDamage(s, average, minimum, maximum)
    s:_writeWord("wDamage", average)
    s.memory:writeSymbol8("wAIMinDamage", minimum)
    s.memory:writeSymbol8("wAIMaxDamage", maximum)
    return false
  end

  self:register("SetExpectedAIDamage", function(s, context)
    local spec = context and context.expectedAIDamage
    if type(spec) ~= "table" then return nil, "effect_context_missing_expected_ai_damage" end
    return setExpectedAIDamage(s, spec.average or 0, spec.minimum or 0, spec.maximum or 0)
  end)

  local expectedDamage = {
    SpitPoison_AIEffect = { 5, 0, 10 },
    Twineedle_AIEffect = { 30, 0, 60 },
    Thrash_AIEffect = { 35, 30, 40 },
    NidoranFFurySwipes_AIEffect = { 15, 0, 30 },
    HornHazard_AIEffect = { 15, 0, 30 },
    NidorinaDoubleKick_AIEffect = { 30, 0, 60 },
    NidorinoDoubleKick_AIEffect = { 30, 0, 60 },
    PetalDance_AIEffect = { 60, 0, 120 },
    OmastarSpikeCannon_AIEffect = { 30, 0, 60 },
    PsyduckFurySwipes_AIEffect = { 15, 0, 30 },
    VaporeonQuickAttack_AIEffect = { 20, 10, 30 },
    PoliwhirlDoubleslap_AIEffect = { 30, 0, 60 },
    CloysterSpikeCannon_AIEffect = { 30, 0, 60 },
    ArcanineQuickAttack_AIEffect = { 20, 10, 30 },
    RapidashStomp_AIEffect = { 25, 20, 30 },
    MoltresLv35DiveBomb_AIEffect = { 40, 0, 80 },
    FlareonQuickAttack_AIEffect = { 20, 10, 30 },
    DancingEmbers_AIEffect = { 40, 0, 80 },
    MoltresLv37DiveBomb_AIEffect = { 35, 0, 70 },
    JynxDoubleslap_AIEffect = { 10, 0, 20 },
    MysteryAttack_AIEffect = { 10, 0, 20 },
    StoneBarrage_AIEffect = { 10, 0, 100 },
    PrimeapeFurySwipes_AIEffect = { 30, 0, 60 },
    Bonemerang_AIEffect = { 30, 0, 60 },
    SandslashFurySwipes_AIEffect = { 30, 0, 60 },
    Thunderpunch_AIEffect = { 35, 30, 40 },
    ElectabuzzQuickAttack_AIEffect = { 20, 10, 30 },
    JolteonQuickAttack_AIEffect = { 20, 10, 30 },
    PinMissile_AIEffect = { 40, 0, 80 },
    Fly_AIEffect = { 15, 0, 30 },
    JolteonDoubleKick_AIEffect = { 20, 0, 40 },
    EeveeQuickAttack_AIEffect = { 20, 10, 30 },
    DragoniteLv45Slam_AIEffect = { 40, 0, 80 },
    LeekSlap_AIEffect = { 15, 0, 30 },
    CometPunch_AIEffect = { 40, 0, 80 },
    TaurosStomp_AIEffect = { 25, 20, 30 },
    FuryAttack_AIEffect = { 10, 0, 20 },
    DragonairSlam_AIEffect = { 30, 0, 60 },
    DragoniteLv41Slam_AIEffect = { 30, 0, 60 },
  }
  for label, values in pairs(expectedDamage) do
    local average, minimum, maximum = values[1], values[2], values[3]
    self:register(label, function(s)
      return setExpectedAIDamage(s, average, minimum, maximum)
    end)
  end

  local function updateExpectedAIDamage(s, averageAdd, minimumAdd, maximumAdd, accountForPoison, context)
    if accountForPoison then
      local actor = s:_actor(context or {})
      if not actor then return nil, "effect_context_missing_actor" end
      local status = actor.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD_STATUS)
      if bit.band(status, bit.bor(s.c.POISONED, s.c.DOUBLE_POISONED)) ~= 0 then
        local current = s:_readWord("wDamage") % 0x100
        s.memory:writeSymbol8("wAIMinDamage", current)
        s.memory:writeSymbol8("wAIMaxDamage", current)
        return false
      end
    end
    local address, bank = s.memory:address("wDamage")
    local current = s.memory:read8("wram", address, bank)
    s.memory:writeSymbol8("wAIMinDamage", (current + minimumAdd) % 0x100)
    s.memory:writeSymbol8("wAIMaxDamage", (current + maximumAdd) % 0x100)
    s.memory:write8("wram", address, (current + averageAdd) % 0x100, bank)
    return false
  end

  self:register("UpdateExpectedAIDamage", function(s, context)
    local spec = context and context.expectedAIDamage
    if type(spec) ~= "table" then return nil, "effect_context_missing_expected_ai_damage" end
    return updateExpectedAIDamage(s, spec.average or 0, spec.minimum or 0, spec.maximum or 0, false, context)
  end)
  self:register("UpdateExpectedAIDamage_AccountForPoison", function(s, context)
    local spec = context and context.expectedAIDamage
    if type(spec) ~= "table" then return nil, "effect_context_missing_expected_ai_damage" end
    return updateExpectedAIDamage(s, spec.average or 0, spec.minimum or 0, spec.maximum or 0, true, context)
  end)

  local poisonExpected = {
    PoisonFang_AIEffect = { 10, 10, 10 },
    WeepinbellPoisonPowder_AIEffect = { 5, 0, 10 },
    GloomPoisonPowder_AIEffect = { 10, 10, 10 },
    KakunaPoisonPowder_AIEffect = { 5, 0, 10 },
    BeedrillPoisonSting_AIEffect = { 5, 0, 10 },
    WeedlePoisonSting_AIEffect = { 5, 0, 10 },
    IvysaurPoisonPowder_AIEffect = { 10, 10, 10 },
    Sludge_AIEffect = { 5, 0, 10 },
    WeezingSmog_AIEffect = { 5, 0, 10 },
    TangelaPoisonPowder_AIEffect = { 5, 0, 10 },
    PoisonWhip_AIEffect = { 10, 10, 10 },
    JellyfishSting_AIEffect = { 10, 10, 10 },
    MagmarSmog_AIEffect = { 5, 0, 10 },
  }
  for label, values in pairs(poisonExpected) do
    local averageAdd, minimumAdd, maximumAdd = values[1], values[2], values[3]
    self:register(label, function(s, context)
      return updateExpectedAIDamage(s, averageAdd, minimumAdd, maximumAdd, true, context)
    end)
  end

  local function extraWaterEnergyDamageBonus(s, context, waterNeeded, colorlessNeeded)
    local actor = s:_actor(context or {})
    if not actor then return nil, "effect_context_missing_actor" end
    local metronome = s.memory:readSymbol8("wMetronomeEnergyCost")
    if metronome ~= 0 then colorlessNeeded, waterNeeded = metronome, 0 end
    local slot = s.memory:readSymbol8("hTempPlayAreaLocation_ff9d")
    actor.duelOps:getPlayAreaCardAttachedEnergies(slot)
    local base, bank = s.memory:address("wAttachedEnergies")
    local water = s.memory:read8("wram", base + s.c.WATER, bank)
    local total = s.memory:readSymbol8("wTotalAttachedEnergies")
    if colorlessNeeded ~= 0 and total == water then
      waterNeeded = waterNeeded + colorlessNeeded
    end
    local bonusUnits = water - waterNeeded
    if bonusUnits > 0 then
      bonusUnits = math.min(2, bonusUnits)
      s:_addToDamage(bonusUnits * 10)
    end
    local damage = s:_readWord("wDamage") % 0x100
    s.memory:writeSymbol8("wAIMinDamage", damage)
    s.memory:writeSymbol8("wAIMaxDamage", damage)
    return false
  end

  self:register("ApplyExtraWaterEnergyDamageBonus", function(s, context)
    local spec = context and context.waterEnergyBonus
    if type(spec) ~= "table" then return nil, "effect_context_missing_water_energy_bonus" end
    return extraWaterEnergyDamageBonus(s, context, spec.waterNeeded or 0, spec.colorlessNeeded or 0)
  end)

  local waterBonus = {
    OmastarWaterGunEffect = { 1, 1 },
    OmanyteWaterGunEffect = { 1, 0 },
    HydroPumpEffect = { 3, 0 },
    SeadraWaterGunEffect = { 1, 1 },
    VaporeonWaterGunEffect = { 2, 1 },
    PoliwrathWaterGunEffect = { 2, 1 },
    PoliwagWaterGunEffect = { 1, 0 },
    LaprasWaterGunEffect = { 1, 0 },
  }
  for label, values in pairs(waterBonus) do
    local waterNeeded, colorlessNeeded = values[1], values[2]
    self:register(label, function(s, context)
      return extraWaterEnergyDamageBonus(s, context, waterNeeded, colorlessNeeded)
    end)
  end

  -- Remaining generic EFFECTCMDTYPE_AI families from effect_functions.asm.
  -- These complete the cartridge's 81 unique generic AI-effect handlers.
  local function setDefiniteAIDamage(s)
    local damage = s.memory:readSymbol8("wDamage")
    s.memory:writeSymbol8("wAIMinDamage", damage)
    s.memory:writeSymbol8("wAIMaxDamage", damage)
    return false
  end
  self:register("SetDefiniteAIDamage", function(s)
    return setDefiniteAIDamage(s)
  end)

  local function ownArenaDamage(s, context)
    local actor = s:_actor(context or {})
    if not actor then return nil, "effect_context_missing_actor" end
    local damage = s:_playAreaDamage(actor, s.c.PLAY_AREA_ARENA)
    return damage or 0
  end

  local function defendingArenaDamage(s, context)
    local actor = s:_actor(context or {})
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelVars:swapTurn()
    local damage = s:_playAreaDamage(actor, s.c.PLAY_AREA_ARENA)
    actor.duelVars:swapTurn()
    return damage or 0
  end

  local function rageExpected(s, context)
    local damage, err = ownArenaDamage(s, context)
    if damage == nil then return nil, err end
    s:_addToDamage(damage)
    return setDefiniteAIDamage(s)
  end
  self:register("CuboneRage_AIEffect", rageExpected)
  self:register("DodrioRage_AIEffect", rageExpected)
  self:register("FlamesOfRage_AIEffect", rageExpected)
  self:register("FlareonRage_AIEffect", rageExpected)

  local function meditateExpected(s, context)
    local damage, err = defendingArenaDamage(s, context)
    if damage == nil then return nil, err end
    s:_addToDamage(damage)
    return setDefiniteAIDamage(s)
  end
  self:register("JynxMeditate_AIEffect", meditateExpected)
  self:register("MrMimeMeditate_AIEffect", meditateExpected)

  local function flailExpected(s, context)
    local damage, err = ownArenaDamage(s, context)
    if damage == nil then return nil, err end
    s:_setDefiniteDamage(damage)
    return setDefiniteAIDamage(s)
  end
  self:register("KinglerFlail_AIEffect", flailExpected)
  self:register("MagikarpFlail_AIEffect", flailExpected)

  self:register("KarateChop_AIEffect", function(s, context)
    local damage, err = ownArenaDamage(s, context)
    if damage == nil then return nil, err end
    local current = s:_readWord("wDamage")
    if damage >= current then s:_setDefiniteDamage(0)
    else s:_writeWord("wDamage", current - damage) end
    return setDefiniteAIDamage(s)
  end)

  self:register("Psychic_AIEffect", function(s, context)
    local actor = s:_actor(context or {})
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelVars:swapTurn()
    local count = 0
    for deckIndex = 0, s.c.DECK_SIZE - 1 do
      if actor.duelVars:get(deckIndex) == s.c.CARD_LOCATION_ARENA then
        local cardId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
        local row = actor.cardData:get(cardId)
        if row and bit.band(row.type, bit.lshift(1, s.c.TYPE_ENERGY_F)) ~= 0 then
          count = count + 1
        end
      end
    end
    actor.duelVars:swapTurn()
    s:_addToDamage(count * 10)
    return setDefiniteAIDamage(s)
  end)

  self:register("SuperFang_AIEffect", function(s, context)
    local actor = s:_actor(context or {})
    if not actor then return nil, "effect_context_missing_actor" end
    local hp = actor.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD_HP)
    local damage = math.ceil(hp / 20) * 10
    s:_setDefiniteDamage(damage)
    return setDefiniteAIDamage(s)
  end)

  self:register("Rampage_AIEffect", rageExpected)

  self:register("BigEggsplosion_AIEffect", function(s, context)
    local actor = s:_actor(context or {})
    if not actor then return nil, "effect_context_missing_actor" end
    local slot = s.memory:readSymbol8("hTempPlayAreaLocation_ff9d")
    local total = actor.duelOps:getPlayAreaCardAttachedEnergies(slot)
    local product = (total * 20) % 0x10000
    s:_writeWord("wDamage", product)
    local maximum = product % 0x100
    -- Preserve the source's reachable behavior. The INC H / JR NZ sequence
    -- only substitutes $ff when H was already $ff.
    if math.floor(product / 0x100) == 0xff then maximum = 0xff end
    s.memory:writeSymbol8("wAIMaxDamage", maximum)
    s.memory:writeSymbol8("wDamage", math.floor(maximum / 2))
    s.memory:writeSymbol8("wAIMinDamage", 0)
    return false
  end)

  self:register("DoTheWaveEffect", function(s, context)
    local actor = s:_actor(context or {})
    if not actor then return nil, "effect_context_missing_actor" end
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    s:_addToDamage(math.max(0, count - 1) * 10)
    return false
  end)

  local function sonicboomUnaffected(s)
    local address, bank = s.memory:address("wDamage")
    local high = s.memory:read8("wram", address + 1, bank)
    high = bit.bor(high, bit.lshift(1, s.c.UNAFFECTED_BY_WEAKNESS_RESISTANCE_F))
    s.memory:write8("wram", address + 1, high, bank)
    return false
  end
  self:register("ElectrodeSonicboom_UnaffectedByColorEffect", sonicboomUnaffected)
  self:register("MagnetonSonicboom_UnaffectedByColorEffect", sonicboomUnaffected)

  self:register("FoulGas_AIEffect", function(s, context)
    return updateExpectedAIDamage(s, 5, 0, 10, false, context)
  end)
  self:register("Toxic_AIEffect", function(s, context)
    return updateExpectedAIDamage(s, 20, 20, 20, false, context)
  end)
  self:register("VenomPowder_AIEffect", function(s, context)
    return updateExpectedAIDamage(s, 5, 0, 10, false, context)
  end)

  -- Paired ordinary attack handlers for the same source cluster.  These
  -- share the exact deterministic damage math with their AI counterparts.
  local function addOwnArenaDamage(s, context)
    local damage, err = ownArenaDamage(s, context)
    if damage == nil then return nil, err end
    s:_addToDamage(damage)
    return false
  end
  self:register("CuboneRage_DamageBoostEffect", addOwnArenaDamage)
  self:register("DodrioRage_DamageBoostEffect", addOwnArenaDamage)
  self:register("FlamesOfRage_DamageBoostEffect", addOwnArenaDamage)
  self:register("FlareonRage_DamageBoostEffect", addOwnArenaDamage)

  local function addDefendingArenaDamage(s, context)
    local damage, err = defendingArenaDamage(s, context)
    if damage == nil then return nil, err end
    s:_addToDamage(damage)
    return false
  end
  self:register("JynxMeditate_DamageBoostEffect", addDefendingArenaDamage)
  self:register("MrMimeMeditate_DamageBoostEffect", addDefendingArenaDamage)

  local function setDamageToOwnDamage(s, context)
    local damage, err = ownArenaDamage(s, context)
    if damage == nil then return nil, err end
    return s:_setDefiniteDamage(damage)
  end
  self:register("KinglerFlail_HPCheck", setDamageToOwnDamage)
  self:register("MagikarpFlail_HPCheck", setDamageToOwnDamage)

  self:register("KarateChop_DamageSubtractionEffect", function(s, context)
    local damage, err = ownArenaDamage(s, context)
    if damage == nil then return nil, err end
    local current = s:_readWord("wDamage")
    if damage >= current then return s:_setDefiniteDamage(0) end
    s:_writeWord("wDamage", current - damage)
    return false
  end)

  self:register("Psychic_DamageBoostEffect", function(s, context)
    local actor = s:_actor(context or {})
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelVars:swapTurn()
    local count = 0
    for deckIndex = 0, s.c.DECK_SIZE - 1 do
      if actor.duelVars:get(deckIndex) == s.c.CARD_LOCATION_ARENA then
        local cardId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
        local row = actor.cardData:get(cardId)
        if row and bit.band(row.type, bit.lshift(1, s.c.TYPE_ENERGY_F)) ~= 0 then
          count = count + 1
        end
      end
    end
    actor.duelVars:swapTurn()
    s:_addToDamage(count * 10)
    return false
  end)

  self:register("SuperFang_HalfHPEffect", function(s, context)
    local actor = s:_actor(context or {})
    if not actor then return nil, "effect_context_missing_actor" end
    local hp = actor.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD_HP)
    return s:_setDefiniteDamage(math.ceil(hp / 20) * 10)
  end)

  self:register("BigEggsplosion_MultiplierEffect", function(s, context)
    local actor = s:_actor(context or {})
    if not actor then return nil, "effect_context_missing_actor" end
    local slot = s.memory:readSymbol8("hTempPlayAreaLocation_ff9d")
    local total = actor.duelOps:getPlayAreaCardAttachedEnergies(slot)
    local heads, err = s.setup:tossCoinATimes(total)
    if heads == nil then return nil, err end
    s:_writeWord("wDamage", (heads * 20) % 0x10000)
    return false
  end)

  self:register("Toxic_DoublePoisonEffect", function(s)
    return s.status:queueStatusCondition(s.c.CNF_SLP_PRZ, s.c.DOUBLE_POISONED)
  end)

  self:register("VenomPowder_PoisonConfusion50PercentEffect", function(s)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    if result == s.c.TAILS then return false end
    s.status:queueStatusCondition(s.c.CNF_SLP_PRZ, s.c.POISONED)
    s.status:queueStatusCondition(s.c.PSN_DBLPSN, s.c.CONFUSED)
    s.memory:writeSymbol8("wNoEffectFromWhichStatus", bit.bor(s.c.CONFUSED, s.c.POISONED))
    return false
  end)

  self:register("Rampage_Confusion50PercentEffect", function(s, context)
    local carry, err = addOwnArenaDamage(s, context)
    if carry == nil then return nil, err end
    local result, tossErr = s.setup:tossCoin()
    if result == nil then return nil, tossErr end
    if result == s.c.TAILS then
      local actor = s:_actor(context or {})
      if not actor then return nil, "effect_context_missing_actor" end
      actor.duelVars:swapTurn()
      s.status:queueStatusCondition(s.c.PSN_DBLPSN, s.c.CONFUSED)
      actor.duelVars:swapTurn()
    end
    return false
  end)

  self:register("MagnetonSonicboom_NullEffect", function() return false end)
  self:register("ElectrodeSonicboom_NullEffect", function() return false end)

  local function mirrorMoveExpected(s, context)
    local actor = s:_actor(context or {})
    if not actor then return nil, "effect_context_missing_actor" end
    local damage = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_LAST_TURN_DAMAGE)
    s.memory:writeSymbol8("wAIMinDamage", damage)
    s.memory:writeSymbol8("wAIMaxDamage", damage)
    return false
  end
  self:register("MirrorMove_AIEffect", mirrorMoveExpected)
  self:register("SpearowMirrorMove_AIEffect", mirrorMoveExpected)
  self:register("PidgeottoMirrorMove_AIEffect", mirrorMoveExpected)

  -- effect_functions.asm shared status primitives.  These labels fan out to a
  -- large number of card command lists, so translating them immediately makes
  -- the generic dispatcher useful beyond the practice duel.
  self:register("PoisonEffect", function(s)
    return s.status:queueStatusCondition(s.c.CNF_SLP_PRZ, s.c.POISONED)
  end)
  self:register("DoublePoisonEffect", function(s)
    return s.status:queueStatusCondition(s.c.CNF_SLP_PRZ, s.c.DOUBLE_POISONED)
  end)
  self:register("ParalysisEffect", function(s)
    return s.status:queueStatusCondition(s.c.PSN_DBLPSN, s.c.PARALYZED)
  end)
  self:register("ConfusionEffect", function(s)
    return s.status:queueStatusCondition(s.c.PSN_DBLPSN, s.c.CONFUSED)
  end)
  self:register("SleepEffect", function(s)
    return s.status:queueStatusCondition(s.c.PSN_DBLPSN, s.c.ASLEEP)
  end)

  -- Porygon: Mystery Attack. An 8-way RNG pick (UpdateRNGSources & %111, not
  -- a coin flip), reusing the four unconditional status handlers above
  -- directly by name for options 0-3. Option 4 (recover) does nothing here
  -- -- MysteryAttack_RecoverEffect (a separate, later phase) checks the
  -- relayed roll itself and heals only then.
  self:register("MysteryAttack_RandomEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    s:_setDefiniteDamage(10)
    local roll = bit.band(s.setup.rng:updateSources(), 7)
    s.memory:writeSymbol8("hTemp_ffa0", roll)
    if roll == 0 then return s.handlers["ParalysisEffect"](s, context)
    elseif roll == 1 then return s.handlers["PoisonEffect"](s, context)
    elseif roll == 2 then return s.handlers["SleepEffect"](s, context)
    elseif roll == 3 then return s.handlers["ConfusionEffect"](s, context)
    elseif roll == 4 or roll == 5 then return false -- .recover / .no_effect
    elseif roll == 6 then
      s:_setDefiniteDamage(20)
      return false
    else -- roll == 7: .no_damage
      s:_setDefiniteDamage(0)
      s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_GLOW_EFFECT)
      return s:_setNoEffectFromStatus()
    end
  end)
  self:register("MysteryAttack_RecoverEffect", function(s, context)
    if s.memory:readSymbol8("hTemp_ffa0") ~= 4 then return false end
    return s:_healAttackingArena(context, 10)
  end)

  self:register("Poison50PercentEffect", function(s)
    return s:_tossThen(s.c.CNF_SLP_PRZ, s.c.POISONED)
  end)
  self:register("Paralysis50PercentEffect", function(s)
    return s:_tossThen(s.c.PSN_DBLPSN, s.c.PARALYZED)
  end)
  self:register("Confusion50PercentEffect", function(s)
    return s:_tossThen(s.c.PSN_DBLPSN, s.c.CONFUSED)
  end)
  self:register("Sleep50PercentEffect", function(s)
    return s:_tossThen(s.c.PSN_DBLPSN, s.c.ASLEEP)
  end)

  -- Small card-specific wrappers that are source-exact compositions of the
  -- shared primitives above. These materially widen the generic player attack
  -- path without introducing selection/AI approximations.
  self:register("SpitPoison_Poison50PercentEffect", function(s)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    if result == s.c.HEADS then
      return s.status:queueStatusCondition(s.c.CNF_SLP_PRZ, s.c.POISONED)
    end
    s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_SPIT_POISON_SUCCESS)
    return s:_setNoEffectFromStatus()
  end)

  self:register("FoulGas_PoisonOrConfusionEffect", function(s)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    if result == s.c.HEADS then
      return s.status:queueStatusCondition(s.c.CNF_SLP_PRZ, s.c.POISONED)
    end
    return s.status:queueStatusCondition(s.c.PSN_DBLPSN, s.c.CONFUSED)
  end)

  local function stiffen(s)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    if result == s.c.TAILS then return s:_setWasUnsuccessful() end
    s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_PROTECT)
    s.status:applySubstatus1ToAttackingCard(s.c.SUBSTATUS1_NO_DAMAGE_STIFFEN)
    return false
  end
  self:register("KakunaStiffenEffect", stiffen)
  self:register("MetapodStiffenEffect", stiffen)

  self:register("SwordsDanceEffect", function(s)
    if s.memory:readSymbol8("wTempTurnDuelistCardID") == s.c.SCYTHER then
      s.status:applySubstatus1ToAttackingCard(s.c.SUBSTATUS1_NEXT_TURN_DOUBLE_DAMAGE)
    end
    return false
  end)

  self:register("AcidEffect", function(s)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    if result == s.c.HEADS then
      s.status:applySubstatus2ToDefendingCard(s.c.SUBSTATUS2_ACID)
    end
    return false
  end)

  local function supersonic(s)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    if result == s.c.HEADS then
      return s.status:queueStatusCondition(s.c.PSN_DBLPSN, s.c.CONFUSED)
    end
    return s:_setNoEffectFromStatus()
  end
  self:register("ZubatSupersonicEffect", supersonic)
  self:register("NidorinaSupersonicEffect", supersonic)
  self:register("LickitungSupersonicEffect", supersonic)
  self:register("ShellderSupersonicEffect", supersonic)
  self:register("TentacruelSupersonicEffect", supersonic)

  -- Clefairy/Gastly: Sing/Sleeping Gas -- the exact same shape as Supersonic
  -- above (coin heads inflicts the status, tails marks "no effect"), just
  -- Sleep instead of Confused.
  local function sleepOrNoEffect(s)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    if result == s.c.HEADS then
      return s.status:queueStatusCondition(s.c.PSN_DBLPSN, s.c.ASLEEP)
    end
    return s:_setNoEffectFromStatus()
  end
  self:register("SingEffect", sleepOrNoEffect)
  self:register("SleepingGasEffect", sleepOrNoEffect)

  -- Psyduck: Headache -- sets a SUBSTATUS3 flag on the Defending Pokemon,
  -- unconditional, no coin.
  self:register("HeadacheEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local sub3 = actor.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD_SUBSTATUS3)
    actor.duelVars:setNonTurn(s.c.DUELVARS_ARENA_CARD_SUBSTATUS3,
      bit.bor(sub3, bit.lshift(1, s.c.SUBSTATUS3_HEADACHE_F)))
    return false
  end)

  -- Gloom: Foul Odor -- confuses BOTH active Pokemon unconditionally (no
  -- coin), reusing the already-registered plain ConfusionEffect by name.
  self:register("FoulOdorEffect", function(s, context)
    local carry, err = s.handlers["ConfusionEffect"](s, context)
    if carry == nil then return nil, err end
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelVars:swapTurn()
    local ownCarry, ownErr = s.handlers["ConfusionEffect"](s, context)
    actor.duelVars:swapTurn()
    if ownCarry == nil then return nil, ownErr end
    return false
  end)

  -- Primeape: Tantrum -- heads does nothing; tails confuses PRIMEAPE'S OWN
  -- side (SwapTurn before calling the plain ConfusionEffect, which always
  -- targets whichever side is currently non-turn).
  self:register("TantrumEffect", function(s, context)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    if result == s.c.HEADS then return false end
    s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_MULTIPLE_SLASH)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelVars:swapTurn()
    local carry, confErr = s.handlers["ConfusionEffect"](s, context)
    actor.duelVars:swapTurn()
    if carry == nil then return nil, confErr end
    return false
  end)

  -- Common SUBSTATUS1 families. These are direct translations of the small
  -- wrappers in effect_functions.asm and feed the already-translated common
  -- damage/prevention engine.
  local function setSub1(value)
    return function(s) s.status:applySubstatus1ToAttackingCard(value); return false end
  end
  self:register("GrimerMinimizeEffect", setSub1(self.c.SUBSTATUS1_REDUCE_BY_20))
  self:register("ClefableMinimizeEffect", setSub1(self.c.SUBSTATUS1_REDUCE_BY_20))
  self:register("ExpandEffect", setSub1(self.c.SUBSTATUS1_REDUCE_BY_10))
  self:register("DestinyBond_DestinyBondEffect", setSub1(self.c.SUBSTATUS1_DESTINY_BOND))
  self:register("Barrier_BarrierEffect", setSub1(self.c.SUBSTATUS1_BARRIER))
  self:register("OnixHardenEffect", setSub1(self.c.SUBSTATUS1_PREVENT_LESS_THAN_40))
  self:register("GravelerHardenEffect", setSub1(self.c.SUBSTATUS1_PREVENT_LESS_THAN_40))
  self:register("LightScreenEffect", setSub1(self.c.SUBSTATUS1_HALVE_DAMAGE))

  self:register("FocusEnergyEffect", function(s)
    if s.memory:readSymbol8("wTempTurnDuelistCardID") == s.c.VAPOREON_LV29 then
      s.status:applySubstatus1ToAttackingCard(s.c.SUBSTATUS1_NEXT_TURN_DOUBLE_DAMAGE)
    end
    return false
  end)

  local function protectCoin(substatus, animation, markFailure)
    return function(s)
      local result, err = s.setup:tossCoin()
      if result == nil then return nil, err end
      if result == s.c.TAILS then
        return markFailure and s:_setWasUnsuccessful() or false
      end
      s.memory:writeSymbol8("wLoadedAttackAnimation", animation)
      s.status:applySubstatus1ToAttackingCard(substatus)
      return false
    end
  end
  self:register("WartortleWithdrawEffect", protectCoin(
    self.c.SUBSTATUS1_NO_DAMAGE_WITHDRAW, self.c.ATK_ANIM_PROTECT, true))
  self:register("SquirtleWithdrawEffect", protectCoin(
    self.c.SUBSTATUS1_NO_DAMAGE_WITHDRAW, self.c.ATK_ANIM_PROTECT, true))
  self:register("HideInShellEffect", protectCoin(
    self.c.SUBSTATUS1_NO_DAMAGE_HIDE_IN_SHELL, self.c.ATK_ANIM_PROTECT, true))
  self:register("ScrunchEffect", protectCoin(
    self.c.SUBSTATUS1_NO_DAMAGE_SCRUNCH, self.c.ATK_ANIM_SCRUNCH, true))
  self:register("SeadraAgilityEffect", protectCoin(
    self.c.SUBSTATUS1_AGILITY, self.c.ATK_ANIM_AGILITY_PROTECT, false))
  self:register("RapidashAgilityEffect", protectCoin(
    self.c.SUBSTATUS1_AGILITY, self.c.ATK_ANIM_AGILITY_PROTECT, false))
  self:register("RaichuAgilityEffect", protectCoin(
    self.c.SUBSTATUS1_AGILITY, self.c.ATK_ANIM_AGILITY_PROTECT, false))
  self:register("FearowAgilityEffect", protectCoin(
    self.c.SUBSTATUS1_AGILITY, self.c.ATK_ANIM_AGILITY_PROTECT, false))

  -- Common SUBSTATUS2 families.
  local function setSub2(value)
    return function(s) s.status:applySubstatus2ToDefendingCard(value); return false end
  end
  self:register("HorseaSmokescreenEffect", setSub2(self.c.SUBSTATUS2_SMOKESCREEN))
  self:register("MagmarSmokescreenEffect", setSub2(self.c.SUBSTATUS2_SMOKESCREEN))
  self:register("SnivelEffect", setSub2(self.c.SUBSTATUS2_REDUCE_BY_20))
  self:register("SandAttackEffect", setSub2(self.c.SUBSTATUS2_SAND_ATTACK))
  self:register("PikachuLv16GrowlEffect", setSub2(self.c.SUBSTATUS2_GROWL))
  self:register("PikachuAltLv16GrowlEffect", setSub2(self.c.SUBSTATUS2_GROWL))
  self:register("PounceEffect", setSub2(self.c.SUBSTATUS2_POUNCE))

  self:register("LeerEffect", function(s)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    if result == s.c.TAILS then return s:_setWasUnsuccessful() end
    s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_LEER)
    s.status:applySubstatus2ToDefendingCard(s.c.SUBSTATUS2_LEER)
    return false
  end)
  self:register("BoneAttackEffect", function(s)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    if result == s.c.HEADS then
      s.status:applySubstatus2ToDefendingCard(s.c.SUBSTATUS2_BONE_ATTACK)
    end
    return false
  end)
  self:register("TailWagEffect", function(s)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    if result == s.c.TAILS then return s:_setWasUnsuccessful() end
    s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_LURE)
    s.status:applySubstatus2ToDefendingCard(s.c.SUBSTATUS2_TAIL_WAG)
    return false
  end)

  -- Fixed-count multi-coin damage families. SetDefiniteDamage is shared by a
  -- large number of attacks whose only variation is toss count/damage per head.
  local multipliers = {
    Twineedle_MultiplierEffect = {2, 30},
    NidoranFFurySwipes_MultiplierEffect = {3, 10},
    NidorinaDoubleKick_MultiplierEffect = {2, 30},
    NidorinoDoubleKick_MultiplierEffect = {2, 30},
    OmastarSpikeCannon_MultiplierEffect = {2, 30},
    PsyduckFurySwipes_MultiplierEffect = {3, 10},
    PoliwhirlDoubleslap_MultiplierEffect = {2, 30},
    CloysterSpikeCannon_MultiplierEffect = {2, 30},
    JynxDoubleslap_MultiplierEffect = {2, 10},
    PrimeapeFurySwipes_MultiplierEffect = {3, 20},
    Bonemerang_MultiplierEffect = {2, 30},
    SandslashFurySwipes_MultiplierEffect = {3, 20},
    PinMissile_MultiplierEffect = {4, 20},
    JolteonDoubleKick_MultiplierEffect = {2, 20},
    DragoniteLv45Slam_MultiplierEffect = {2, 40},
    CometPunch_MultiplierEffect = {4, 20},
    FuryAttack_MultiplierEffect = {2, 10},
    DragonairSlam_MultiplierEffect = {2, 30},
    DragoniteLv41Slam_MultiplierEffect = {2, 30},
    DancingEmbers_MultiplierEffect = {8, 10},
  }
  for label, spec in pairs(multipliers) do
    self:register(label, function(s) return s:_tossDamageMultiplier(spec[1], spec[2]) end)
  end

  self:register("PetalDance_MultiplierEffect", function(s, context)
    local carry, err = s:_tossDamageMultiplier(3, 40)
    if carry == nil then return nil, err end
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelVars:swapTurn()
    local queued = s.status:queueStatusCondition(s.c.PSN_DBLPSN, s.c.CONFUSED)
    actor.duelVars:swapTurn()
    return queued == nil and nil or false
  end)

  self:register("StoneBarrage_MultiplierEffect", function(s)
    local heads = 0
    while true do
      local result, err = s.setup:tossCoin()
      if result == nil then return nil, err end
      if result == s.c.TAILS then break end
      heads = heads + 1
    end
    s.memory:writeSymbol8("hTemp_ffa0", heads)
    return s:_setDefiniteDamage(heads * 10)
  end)

  -- Coin-gated bonus damage and no-damage-on-tails families.
  local function damageBoost(amount)
    return function(s)
      local result, err = s.setup:tossCoin()
      if result == nil then return nil, err end
      if result == s.c.HEADS then s:_addToDamage(amount) end
      return false
    end
  end
  for _, label in ipairs({
    "VaporeonQuickAttack_DamageBoostEffect", "ArcanineQuickAttack_DamageBoostEffect",
    "FlareonQuickAttack_DamageBoostEffect", "ElectabuzzQuickAttack_DamageBoostEffect",
    "JolteonQuickAttack_DamageBoostEffect", "EeveeQuickAttack_DamageBoostEffect",
  }) do self:register(label, damageBoost(20)) end
  self:register("RapidashStomp_DamageBoostEffect", damageBoost(10))
  self:register("TaurosStomp_DamageBoostEffect", damageBoost(10))

  local function coinZeroDamage(animation, markFailure)
    return function(s)
      local result, err = s.setup:tossCoin()
      if result == nil then return nil, err end
      if result == s.c.TAILS then
        s:_setDefiniteDamage(0)
        if markFailure then s:_setWasUnsuccessful() end
      elseif animation then
        s.memory:writeSymbol8("wLoadedAttackAnimation", animation)
      end
      return false
    end
  end
  self:register("HornHazard_NoDamage50PercentEffect",
    coinZeroDamage(self.c.ATK_ANIM_HIT, true))
  self:register("MoltresLv35DiveBomb_Success50PercentEffect",
    coinZeroDamage(self.c.ATK_ANIM_DIVE_BOMB, true))
  self:register("MoltresLv37DiveBomb_Success50PercentEffect",
    coinZeroDamage(self.c.ATK_ANIM_DIVE_BOMB, true))
  self:register("LeekSlap_NoDamage50PercentEffect", coinZeroDamage(nil, false))

  -- Cloyster: Clamp. Heads keeps the printed damage and jumps straight into
  -- the plain (unconditional) ParalysisEffect; tails zeroes damage and
  -- marks the attack unsuccessful instead.
  self:register("ClampEffect", function(s, context)
    s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_HIT_EFFECT)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    if result == s.c.HEADS then
      return s.handlers["ParalysisEffect"](s, context)
    end
    s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_NONE)
    s:_setDefiniteDamage(0)
    return s:_setWasUnsuccessful()
  end)

  -- Farfetch'd: Leek Slap can only ever be used once per duel (a duel-long
  -- flag on the Arena card, distinct from the per-turn USED_PKMN_POWER_
  -- THIS_TURN flags elsewhere in this file).
  self:register("LeekSlap_OncePerDuelCheck", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local flags = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_FLAGS)
    return bit.band(flags, bit.lshift(1, s.c.USED_LEEK_SLAP_THIS_DUEL_F)) ~= 0
  end)
  self:register("LeekSlap_SetUsedThisDuelFlag", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local flags = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_FLAGS)
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_FLAGS,
      bit.bor(flags, bit.lshift(1, s.c.USED_LEEK_SLAP_THIS_DUEL_F)))
    return false
  end)

  -- Fetch: draw 1 card from the deck; doing nothing when the deck is empty.
  self:register("FetchEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local deckIndex, carry = actor.duelOps:drawCardFromDeck()
    if carry then return false end
    actor.duelOps:addCardToHand(deckIndex)
    return false
  end)

  -- Meowth: Pay Day. Coin heads only: same draw-1-card shape as Fetch.
  self:register("PayDayEffect", function(s, context)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    if result == s.c.TAILS then return false end
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local deckIndex, carry = actor.duelOps:drawCardFromDeck()
    if carry then return false end
    actor.duelOps:addCardToHand(deckIndex)
    return false
  end)

  -- Snorlax: Dream Eater -- usable only while the Defending Pokemon is
  -- Asleep.
  self:register("DreamEaterEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local status = actor.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD_STATUS)
    return bit.band(status, s.c.CNF_SLP_PRZ) ~= s.c.ASLEEP
  end)

  -- Drain/healing families. ApplyAndAnimateHPRecovery caps recovery at max HP;
  -- presentation is surfaced as an event while RAM state follows the source.
  local function dealtDamage(s) return s:_readWord("wDealtDamage") end
  for _, label in ipairs({"GolbatLeechLifeEffect", "VenonatLeechLifeEffect", "ZubatLeechLifeEffect"}) do
    self:register(label, function(s, context)
      return s:_healAttackingArena(context, dealtDamage(s))
    end)
  end
  for _, label in ipairs({"ExeggcuteLeechSeedEffect", "BulbasaurLeechSeedEffect"}) do
    self:register(label, function(s, context)
      if dealtDamage(s) == 0 then return false end
      return s:_healAttackingArena(context, 10)
    end)
  end
  for _, label in ipairs({"ButterfreeMegaDrainEffect", "VenusaurMegaDrainEffect", "AbsorbEffect"}) do
    self:register(label, function(s, context)
      local damage = dealtDamage(s)
      local heal = math.floor(damage / 2)
      if heal % 10 ~= 0 then heal = heal + 5 end
      return s:_healAttackingArena(context, heal)
    end)
  end
  self:register("FirstAid_DamageCheck", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local damage = s:_playAreaDamage(actor, s.c.PLAY_AREA_ARENA)
    return (damage or 0) < 10
  end)
  self:register("FirstAid_HealEffect", function(s, context)
    return s:_healAttackingArena(context, 10)
  end)

  -- Slowpoke's Spacing Out: same damage-check shape as First Aid above,
  -- but a coin flip gates the heal, and the heal itself is a raw +10 add
  -- rather than the clamped _healAttackingArena helper -- safe because
  -- SpacingOut_CheckDamage already guarantees damage >= 10 before this
  -- phase can run, so hp + 10 can never exceed the card's max HP.
  self:register("SpacingOut_CheckDamage", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local damage = s:_playAreaDamage(actor, s.c.PLAY_AREA_ARENA)
    return (damage or 0) < 10
  end)
  self:register("SpacingOut_Success50PercentEffect", function(s)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    s.memory:writeSymbol8("hTemp_ffa0", result)
    if result == s.c.TAILS then return s:_setWasUnsuccessful() end
    s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_RECOVER)
    return false
  end)
  self:register("SpacingOut_HealEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if s.memory:readSymbol8("hTemp_ffa0") == s.c.TAILS then return false end
    local damage = s:_playAreaDamage(actor, s.c.PLAY_AREA_ARENA)
    if not damage or damage <= 0 then return false end
    local hp = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_HP)
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_HP, hp + 10)
    return false
  end)

  -- Fixed recoil families delegate through the source-equivalent self-damage
  -- modifier path in Combat so weakness/resistance and attached Trainers stay
  -- consistent with DealRecoilDamageToSelf::.
  local function recoil(amount)
    return function(_, context)
      if not context.combat then return nil, "effect_context_missing_combat" end
      context.combat:dealRecoilDamageToSelf(amount)
      return false
    end
  end
  self:register("TakeDownEffect", recoil(30))
  self:register("SubmissionEffect", recoil(20))
  self:register("JigglypuffDoubleEdgeEffect", recoil(20))
  self:register("ChanseyDoubleEdgeEffect", recoil(80))

  self:register("Thrash_ModifierEffect", function(s)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    s.memory:writeSymbol8("hTemp_ffa0", result)
    if result == s.c.HEADS then s:_addToDamage(10) end
    return false
  end)
  self:register("Thunderpunch_ModifierEffect", self.handlers["Thrash_ModifierEffect"])
  local function storeRecoilCoin(s)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    s.memory:writeSymbol8("hTemp_ffa0", result)
    return false
  end
  self:register("ZapdosThunder_Recoil50PercentEffect", storeRecoilCoin)
  self:register("ThunderJolt_Recoil50PercentEffect", storeRecoilCoin)
  self:register("RaichuThunder_Recoil50PercentEffect", storeRecoilCoin)
  local function conditionalRecoil(amount)
    return function(_, context)
      if not context.combat then return nil, "effect_context_missing_combat" end
      if context.combat.memory:readSymbol8("hTemp_ffa0") == context.combat.c.TAILS then
        context.combat:dealRecoilDamageToSelf(amount)
      end
      return false
    end
  end
  self:register("Thrash_RecoilEffect", conditionalRecoil(10))
  self:register("Thunderpunch_RecoilEffect", conditionalRecoil(10))
  self:register("ZapdosThunder_RecoilEffect", conditionalRecoil(30))
  self:register("ThunderJolt_RecoilEffect", conditionalRecoil(10))
  self:register("RaichuThunder_RecoilEffect", conditionalRecoil(30))

  -- PlayTrainerCard integration: these first Trainer families exercise all
  -- three important cases: no-selection draw, whole-hand mutation, and a host
  -- supplied play-area selection.
  self:register("BillEffect", function(_, context)
    local a = context.playerActions
    if not a then return nil, "effect_context_missing_player_actions" end
    for _ = 1, 2 do
      local deckIndex, carry = a.duelOps:drawCardFromDeck()
      if carry then break end
      a.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
      a.duelOps:addCardToHand(deckIndex)
    end
    return false
  end)

  self:register("ProfessorOakEffect", function(_, context)
    local a = context.playerActions
    if not a then return nil, "effect_context_missing_player_actions" end
    a.duelOps:createHandCardList()
    a.duelOps:sortCardsInDuelTempListByID()
    local base, bank = a.memory:address("wDuelTempList")
    local pos = 0
    while true do
      local deckIndex = a.memory:read8("wram", base + pos, bank)
      if deckIndex == 0xff then break end
      a.duelOps:removeCardFromHand(deckIndex)
      a.duelOps:putCardInDiscardPile(deckIndex)
      pos = pos + 1
    end
    for _ = 1, 7 do
      local deckIndex, carry = a.duelOps:drawCardFromDeck()
      if carry then break end
      a.duelOps:addCardToHand(deckIndex)
    end
    return false
  end)

  -- Imposter Professor Oak targets the NON-turn duelist: their whole hand is
  -- returned to their deck (not discarded, unlike ordinary Professor Oak),
  -- the deck is reshuffled, and they draw a fresh 7. ShuffleCardsInDeck's
  -- ExchangeRNG call happens while still swapped to the opponent, matching
  -- the source's own turn-swapped RNG exchange.
  self:register("ImposterProfessorOakEffect", function(_, context)
    local a = context.playerActions
    if not a then return nil, "effect_context_missing_player_actions" end
    a.duelVars:swapTurn()
    a.duelOps:createHandCardList()
    a.duelOps:sortCardsInDuelTempListByID()
    local base, bank = a.memory:address("wDuelTempList")
    local pos = 0
    while true do
      local deckIndex = a.memory:read8("wram", base + pos, bank)
      if deckIndex == 0xff then break end
      a.duelOps:removeCardFromHand(deckIndex)
      a.duelOps:returnCardToDeck(deckIndex)
      pos = pos + 1
    end
    local failed, exchangeErr = a.combat.setup:exchangeRNG()
    if failed then
      a.duelVars:swapTurn()
      return nil, exchangeErr
    end
    a.duelOps:shuffleDeck()
    for _ = 1, 7 do
      local deckIndex, carry = a.duelOps:drawCardFromDeck()
      if carry then break end
      a.duelOps:addCardToHand(deckIndex)
    end
    a.duelVars:swapTurn()
    return false
  end)

  -- Scoop Up returns a chosen Basic Pokemon from the Play Area to hand,
  -- discarding everything attached/evolved on top of it (via
  -- MovePlayAreaCardToDiscardPile). A Bench pick just shifts slots down; an
  -- Active pick additionally requires a Bench replacement and swaps it in.
  self:register("ScoopUp_BenchCheck", function(s, context)
    local a = context.playerActions
    if not a then return nil, "effect_context_missing_player_actions" end
    return a.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) < 2
  end)
  self:register("ScoopUp_PlayerSelection", function(s, context)
    local a = context.playerActions
    if not a then return nil, "effect_context_missing_player_actions" end
    local slot, err = s:_selectPlayArea(context)
    if slot == nil then return nil, err end
    local count = a.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    if type(slot) ~= "number" or slot < 0 or slot >= count
        or a.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot) == 0xff then
      return nil, "invalid_selection:playArea"
    end
    a.memory:writeSymbol8("hTemp_ffa0", slot)
    if slot ~= s.c.PLAY_AREA_ARENA then return false end

    local replacement, replErr = s:_selection(context, "replacement", "selectBench",
      { trainer = "scoop_up" })
    if replacement == nil then return nil, replErr end
    if type(replacement) ~= "number" or replacement < s.c.PLAY_AREA_BENCH_1
        or replacement >= count then return nil, "invalid_selection:replacement" end
    a.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", replacement)
    return false
  end)
  self:register("ScoopUp_ReturnToHandEffect", function(s, context)
    local a = context.playerActions
    if not a then return nil, "effect_context_missing_player_actions" end
    local scoopSlot = a.memory:readSymbol8("hTemp_ffa0")
    local location = bit.bor(s.c.CARD_LOCATION_PLAY_AREA, scoopSlot)

    local found
    for deckIndex = 0, s.c.DECK_SIZE - 1 do
      if a.duelVars:get(deckIndex) == location then
        local cardId = a.cardData:getCardIDFromDeckIndex(deckIndex)
        local row = a.cardData:get(cardId)
        if row and row.type < s.c.TYPE_ENERGY and row.stage == s.c.BASIC then
          found = deckIndex
          break
        end
      end
    end
    if found == nil then return nil, "invalid_selection:no_basic_pokemon_at_location" end

    a.memory:writeSymbol8("hTempCardIndex_ff98", found)
    a.duelOps:addCardToHand(found)
    a.duelOps:movePlayAreaCardToDiscardPile(scoopSlot)

    if scoopSlot == s.c.PLAY_AREA_ARENA then
      a.duelOps:clearAllStatusConditions()
      local benchSlot = a.memory:readSymbol8("hTempPlayAreaLocation_ffa1")
      a.duelOps:swapPlayAreaPokemon(benchSlot, s.c.PLAY_AREA_ARENA)
    else
      a.duelOps:shiftAllPokemonToFirstPlayAreaSlots()
    end
    s:_event("scoop_up", { slot = scoopSlot, deckIndex = found })
    return false
  end)

  -- Lass discards itself FIRST (so its own hand-scan below never re-catches
  -- it), then shuffles every remaining Trainer card in BOTH duelists' hands
  -- back into their own deck -- non-turn duelist first (swapped), then the
  -- turn duelist -- shuffling (with the source's own ExchangeRNG call) only
  -- when that duelist actually had a Trainer card to return.
  self:register("LassEffect", function(s, context)
    local a = context.playerActions
    if not a then return nil, "effect_context_missing_player_actions" end

    local playedDeckIndex = a.memory:readSymbol8("hTempCardIndex_ff9f")
    a.duelOps:removeCardFromHand(playedDeckIndex)
    a.duelOps:putCardInDiscardPile(playedDeckIndex)

    local function shuffleHandTrainersIntoDeck()
      a.duelOps:createHandCardList()
      a.duelOps:sortCardsInDuelTempListByID()
      local base, bank = a.memory:address("wDuelTempList")
      local pos, moved = 0, 0
      while true do
        local deckIndex = a.memory:read8("wram", base + pos, bank)
        if deckIndex == 0xff then break end
        local cardId = a.cardData:getCardIDFromDeckIndex(deckIndex)
        local row = a.cardData:get(cardId)
        if row and row.type == s.c.TYPE_TRAINER then
          a.duelOps:removeCardFromHand(deckIndex)
          a.duelOps:returnCardToDeck(deckIndex)
          moved = moved + 1
        end
        pos = pos + 1
      end
      if moved > 0 then
        local failed, exchangeErr = a.combat.setup:exchangeRNG()
        if failed then return nil, exchangeErr end
        a.duelOps:shuffleDeck()
      end
      return true
    end

    a.duelVars:swapTurn()
    local ok, err = shuffleHandTrainersIntoDeck()
    a.duelVars:swapTurn()
    if not ok then return nil, err end

    local ok2, err2 = shuffleHandTrainersIntoDeck()
    if not ok2 then return nil, err2 end

    return false
  end)

  -- Imakuni? confuses the player's OWN Active Pokemon (a self-inflicted
  -- downside card). Clefairy Doll and Mysterious Fossil are always immune;
  -- Snorlax is immune only while its own Pkmn Power (Thick Skinned) is
  -- active, i.e. not already incapable of using it.
  self:register("ImakuniEffect", function(s, context)
    local a = context.playerActions
    if not a then return nil, "effect_context_missing_player_actions" end
    local deckIndex = a.duelVars:get(s.c.DUELVARS_ARENA_CARD)
    local cardId = a.cardData:getCardIDFromDeckIndex(deckIndex)

    if cardId == s.c.CLEFAIRY_DOLL or cardId == s.c.MYSTERIOUS_FOSSIL then
      return false
    end
    if cardId == s.c.SNORLAX then
      local incapable = a.combat.status:checkIsIncapableOfUsingPkmnPower(s.c.PLAY_AREA_ARENA)
      if not incapable then return false end
    end

    local status = a.duelVars:get(s.c.DUELVARS_ARENA_CARD_STATUS)
    a.duelVars:set(s.c.DUELVARS_ARENA_CARD_STATUS,
      bit.bor(bit.band(status, s.c.PSN_DBLPSN), s.c.CONFUSED))
    s:_event("imakuni_confuse", { deckIndex = deckIndex })
    return false
  end)

  -- Gambler tosses a coin, discards itself, shuffles the WHOLE remaining
  -- hand into the deck (every card, not just Trainers -- unlike Lass), then
  -- draws 8 on heads or 1 on tails. Against every deck but Imakuni?'s own,
  -- the AI plays this with wRNG1/wRNG2/wRNGCounter forced by
  -- _playGamblerWithRNGCheat before this effect runs, so the coin toss below
  -- consumes that forced state.
  self:register("GamblerEffect", function(s, context)
    local a = context.playerActions
    if not a then return nil, "effect_context_missing_player_actions" end

    local result, tossErr = s.setup:tossCoin()
    if result == nil then return nil, tossErr end
    local heads = result == s.c.HEADS

    local playedDeckIndex = a.memory:readSymbol8("hTempCardIndex_ff9f")
    a.duelOps:removeCardFromHand(playedDeckIndex)
    a.duelOps:putCardInDiscardPile(playedDeckIndex)

    a.duelOps:createHandCardList()
    a.duelOps:sortCardsInDuelTempListByID()
    local base, bank = a.memory:address("wDuelTempList")
    local pos = 0
    while true do
      local deckIndex = a.memory:read8("wram", base + pos, bank)
      if deckIndex == 0xff then break end
      a.duelOps:removeCardFromHand(deckIndex)
      a.duelOps:returnCardToDeck(deckIndex)
      pos = pos + 1
    end

    local failed, exchangeErr = a.combat.setup:exchangeRNG()
    if failed then return nil, exchangeErr end
    a.duelOps:shuffleDeck()

    local drawCount = heads and 8 or 1
    for _ = 1, drawCount do
      local deckIndex, carry = a.duelOps:drawCardFromDeck()
      if carry then break end
      a.duelOps:addCardToHand(deckIndex)
    end
    s:_event("gambler", { heads = heads, drawCount = drawCount })
    return false
  end)

  -- Clefairy Doll and Mysterious Fossil are Trainer cards played AS a Basic
  -- Pokemon; both share identical bench-space-check/placement logic.
  -- putHandPokemonCardInPlayArea already applies the Trainer-to-Pokemon data
  -- conversion via CardData's own loadBuffer2FromDeckIndex path.
  local function trainerAsPokemonBenchCheck(s, context)
    local a = context.playerActions
    if not a then return nil, "effect_context_missing_player_actions" end
    return a.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) >= s.c.MAX_PLAY_AREA_POKEMON
  end
  local function trainerAsPokemonPlaceInPlayAreaEffect(s, context)
    local a = context.playerActions
    if not a then return nil, "effect_context_missing_player_actions" end
    local deckIndex = a.memory:readSymbol8("hTempCardIndex_ff9f")
    local slot, carry = a.duelOps:putHandPokemonCardInPlayArea(deckIndex)
    if carry then return nil, "bench_full" end
    s:_event("place_trainer_as_pokemon", { deckIndex = deckIndex, slot = slot })
    return false
  end
  self:register("MysteriousFossil_BenchCheck", trainerAsPokemonBenchCheck)
  self:register("MysteriousFossil_PlaceInPlayAreaEffect", trainerAsPokemonPlaceInPlayAreaEffect)
  self:register("ClefairyDoll_BenchCheck", trainerAsPokemonBenchCheck)
  self:register("ClefairyDoll_PlaceInPlayAreaEffect", trainerAsPokemonPlaceInPlayAreaEffect)

  self:register("Potion_DamageCheck", function(s, context)
    local a = context.playerActions
    if not a then return nil, "effect_context_missing_player_actions" end
    local count = a.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    for slot = 0, count - 1 do
      local damage = s:_playAreaDamage(a, slot)
      if damage and damage > 0 then return false end
    end
    return true
  end)
  self:register("Potion_PlayerSelection", function(s, context)
    local a = context.playerActions
    if not a then return nil, "effect_context_missing_player_actions" end
    local slot, err = s:_selectPlayArea(context)
    if slot == nil then return nil, err end
    local damage = s:_playAreaDamage(a, slot)
    if not damage or damage <= 0 then return nil, "invalid_selection:no_damage" end
    a.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
    a.memory:writeSymbol8("hTemp_ffa0", slot)
    a.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", math.min(20, damage))
    return false
  end)
  self:register("Potion_HealEffect", function(s, context)
    local a = context.playerActions
    if not a then return nil, "effect_context_missing_player_actions" end
    local slot = a.memory:readSymbol8("hTemp_ffa0")
    local heal = a.memory:readSymbol8("hTempPlayAreaLocation_ffa1")
    local hpOffset = s.c.DUELVARS_ARENA_CARD_HP + slot
    a.duelVars:set(hpOffset, a.duelVars:get(hpOffset) + heal)
    s:_event("heal_play_area", { slot = slot, amount = heal })
    return false
  end)


  -- Attached-Energy selection/discard families. Host adapters provide the same
  -- deck-index choice the cartridge menus write into hTemp_ffa0; validation is
  -- performed against the live duel page before any mutation occurs.
  local function checkArenaEnergy(energyType)
    return function(s, context)
      local actor = s:_actor(context)
      if not actor then return nil, "effect_context_missing_actor" end
      return not s:_hasAttachedEnergy(actor, false, s.c.PLAY_AREA_ARENA, energyType)
    end
  end
  local function selectArenaEnergy(energyType, key)
    return function(s, context)
      local actor = s:_actor(context)
      if not actor then return nil, "effect_context_missing_actor" end
      local deckIndex, err = s:_selectAttachedEnergy(context, actor, false,
        s.c.PLAY_AREA_ARENA, key or "energyDeckIndex", energyType)
      if deckIndex == nil then return nil, err end
      s.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
      s.memory:writeSymbol8("hTemp_ffa0", deckIndex)
      return false
    end
  end
  local function discardTempEnergy(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelOps:putCardInDiscardPile(s.memory:readSymbol8("hTemp_ffa0"))
    return false
  end

  for _, prefix in ipairs({
    "ArcanineFlamethrower", "FlareonFlamethrower", "MagmarFlamethrower",
    "CharmeleonFlamethrower",
  }) do
    self:register(prefix .. "_CheckEnergy", checkArenaEnergy(self.c.TYPE_ENERGY_FIRE))
    self:register(prefix .. "_PlayerSelectEffect",
      selectArenaEnergy(self.c.TYPE_ENERGY_FIRE, "energyDeckIndex"))
    self:register(prefix .. "_DiscardEffect", discardTempEnergy)
  end
  self:register("FireBlast_CheckEnergy", checkArenaEnergy(self.c.TYPE_ENERGY_FIRE))
  self:register("FireBlast_PlayerSelectEffect",
    selectArenaEnergy(self.c.TYPE_ENERGY_FIRE, "energyDeckIndex"))
  self:register("FireBlast_DiscardEffect", discardTempEnergy)
  self:register("Ember_CheckEnergy", checkArenaEnergy(self.c.TYPE_ENERGY_FIRE))
  self:register("Ember_PlayerSelectEffect",
    selectArenaEnergy(self.c.TYPE_ENERGY_FIRE, "energyDeckIndex"))
  self:register("Ember_DiscardEffect", discardTempEnergy)

  -- AITryUseAttack:: selection bridge. On cartridge AI turns, these handlers
  -- write the same HRAM temp bytes that the player-facing selection routines
  -- would fill through menus/opponent-action transport. Keep wDuelTempList in
  -- the source scan order because Flames of Rage consumes its second entry.
  local function createFilteredArenaEnergyList(s, actor, requiredType)
    local count = actor.duelOps:createArenaOrBenchEnergyCardList(s.c.PLAY_AREA_ARENA)
    local base, bank = actor.memory:address("wDuelTempList")
    local values = {}
    for i = 0, count - 1 do
      local deckIndex = actor.memory:read8("wram", base + i, bank)
      local cardId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
      local row = actor.cardData:get(cardId)
      if row and bit.band(row.type, bit.lshift(1, s.c.TYPE_ENERGY_F)) ~= 0
          and (requiredType == nil or row.type == requiredType) then
        values[#values + 1] = deckIndex
      end
    end
    for i, deckIndex in ipairs(values) do
      actor.memory:write8("wram", base + i - 1, deckIndex, bank)
    end
    actor.memory:write8("wram", base + #values, 0xff, bank)
    return values
  end

  local function writeTempList(s, values)
    local base, bank = s.memory:address("hTempList")
    for i, value in ipairs(values) do
      s.memory:write8("hram", base + i - 1, value, bank)
    end
  end

  local function aiPickFireEnergyCardToDiscard(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local values = createFilteredArenaEnergyList(s, actor, s.c.TYPE_ENERGY_FIRE)
    if #values < 1 then return nil, "ai_selection_missing_fire_energy" end
    s.memory:writeSymbol8("hTemp_ffa0", values[1])
    return false
  end

  for _, label in ipairs({
    "ArcanineFlamethrower_AISelectEffect",
    "FireBlast_AISelectEffect",
    "Ember_AISelectEffect",
    "FlareonFlamethrower_AISelectEffect",
    "MagmarFlamethrower_AISelectEffect",
    "CharmeleonFlamethrower_AISelectEffect",
  }) do
    self:register(label, aiPickFireEnergyCardToDiscard)
  end

  local function validateTwoArenaEnergies(s, context, requiredType)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local values, err = s:_selectionList(context, "energyDeckIndexes",
      "selectAttachedEnergies", {
        nonTurn = false, playArea = s.c.PLAY_AREA_ARENA, energyType = requiredType,
      }, 2, 2)
    if values == nil then return nil, err end
    local expected = bit.bor(s.c.CARD_LOCATION_PLAY_AREA, s.c.PLAY_AREA_ARENA)
    for _, deckIndex in ipairs(values) do
      local valid = deckIndex >= 0 and deckIndex < s.c.DECK_SIZE
        and actor.duelVars:get(deckIndex) == expected
      if valid then
        local cardId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
        local row = actor.cardData:get(cardId)
        valid = row ~= nil
          and bit.band(row.type, bit.lshift(1, s.c.TYPE_ENERGY_F)) ~= 0
          and (requiredType == nil or row.type == requiredType)
      end
      if not valid then return nil, "invalid_selection:energyDeckIndexes" end
    end
    writeTempList(s, values)
    return false
  end

  local function discardTwoTempEnergies(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local base, bank = s.memory:address("hTempList")
    local first = s.memory:read8("hram", base, bank)
    local second = s.memory:read8("hram", base + 1, bank)
    actor.duelOps:putCardInDiscardPile(first)
    actor.duelOps:putCardInDiscardPile(second)
    return false
  end

  self:register("FlamesOfRage_CheckEnergy", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    return #createFilteredArenaEnergyList(s, actor, s.c.TYPE_ENERGY_FIRE) < 2
  end)
  self:register("FlamesOfRage_PlayerSelectEffect", function(s, context)
    return validateTwoArenaEnergies(s, context, s.c.TYPE_ENERGY_FIRE)
  end)
  self:register("FlamesOfRage_AISelectEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local values = createFilteredArenaEnergyList(s, actor, s.c.TYPE_ENERGY_FIRE)
    if #values < 2 then return nil, "ai_selection_missing_fire_energy" end
    -- hTemp_ffa0 aliases hTempList[0] in hram.asm.
    s.memory:writeSymbol8("hTemp_ffa0", values[1])
    writeTempList(s, { values[1], values[2] })
    return false
  end)
  self:register("FlamesOfRage_DiscardEffect", discardTwoTempEnergies)

  self:register("FireSpin_CheckEnergy", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local count = actor.duelOps:createArenaOrBenchEnergyCardList(s.c.PLAY_AREA_ARENA)
    return count < 2
  end)
  self:register("FireSpin_PlayerSelectEffect", function(s, context)
    return validateTwoArenaEnergies(s, context, nil)
  end)
  self:register("FireSpin_AISelectEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local count = actor.duelOps:createArenaOrBenchEnergyCardList(s.c.PLAY_AREA_ARENA)
    if count < 2 then return nil, "ai_selection_missing_energy" end
    local base, bank = actor.memory:address("wDuelTempList")
    writeTempList(s, {
      actor.memory:read8("wram", base, bank),
      actor.memory:read8("wram", base + 1, bank),
    })
    return false
  end)
  self:register("FireSpin_DiscardEffect", discardTwoTempEnergies)

  -- AIPickEnergyCardToDiscardFromDefendingPokemon::. The attack selector
  -- temporarily swaps to the Defending Pokemon, prefers an attached Colorless
  -- Energy, otherwise prefers Energy matching that Pokemon's own color, and
  -- uses the cartridge ShuffleCards fallback when neither preference applies.
  local function aiPickEnergyCardToDiscardFromDefendingPokemon(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end

    actor.duelVars:swapTurn()
    actor.duelOps:getPlayAreaCardAttachedEnergies(s.c.PLAY_AREA_ARENA)
    local count = actor.duelOps:createArenaOrBenchEnergyCardList(s.c.PLAY_AREA_ARENA)
    if count == 0 then
      actor.duelVars:swapTurn()
      return 0xff
    end

    local defenderDeckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD)
    local defenderCardId = actor.cardData:getCardIDFromDeckIndex(defenderDeckIndex)
    local defender = actor.cardData:get(defenderCardId)
    if not defender then
      actor.duelVars:swapTurn()
      return nil, "ai_selection_missing_defending_card"
    end

    local base, bank = actor.memory:address("wDuelTempList")
    local colorless, ownColor
    for i = 0, count - 1 do
      local deckIndex = actor.memory:read8("wram", base + i, bank)
      local energyId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
      local energy = actor.cardData:get(energyId)
      if energy then
        local energyColor = bit.band(energy.type, s.c.TYPE_PKMN)
        if colorless == nil and energyColor == s.c.COLORLESS then
          colorless = deckIndex
        end
        if ownColor == nil and energyColor == defender.type then
          ownColor = deckIndex
        end
      end
    end

    local picked
    if colorless ~= nil then
      picked = colorless
    elseif defender.type < s.c.COLORLESS and ownColor ~= nil then
      picked = ownColor
    else
      actor.duelOps.rng:shuffleCards(base, count)
      picked = actor.memory:read8("wram", base, bank)
    end
    actor.duelVars:swapTurn()
    return picked
  end

  local function selectDefendingEnergyForAI(s, context)
    local deckIndex, err = aiPickEnergyCardToDiscardFromDefendingPokemon(s, context)
    if deckIndex == nil then return nil, err end
    s.memory:writeSymbol8("hTemp_ffa0", deckIndex)
    return false
  end

  self:register("GolduckHyperBeam_AISelectEffect", selectDefendingEnergyForAI)
  self:register("Whirlpool_AISelectEffect", selectDefendingEnergyForAI)
  self:register("DragonairHyperBeam_AISelectEffect", selectDefendingEnergyForAI)

  -- EnergyRemoval_AISelection:: is present in the source command table but the
  -- cartridge's actual AI Trainer path supplies its chosen play-area slot and
  -- Energy through AIPlay_EnergyRemoval. Preserve this routine's only live
  -- behavior here: run the shared defending-Pokemon picker and leave its result
  -- otherwise uncommitted, matching the source routine's register-A return.
  self:register("EnergyRemoval_AISelection", function(s, context)
    local deckIndex, err = aiPickEnergyCardToDiscardFromDefendingPokemon(s, context)
    if deckIndex == nil then return nil, err end
    return false
  end)

  -- AIFindTargetForBenchAttack:: choose the opposing Bench Pokemon with the
  -- lowest remaining HP. Source updates the winner on equal HP, so ties resolve
  -- to the highest PLAY_AREA_* (the later Bench slot). With no Bench Pokemon
  -- the helper itself returns PLAY_AREA_ARENA; Spark/Dark Mind guard that case.
  local function aiFindTargetForBenchAttack(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelVars:swapTurn()
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    local bestSlot = s.c.PLAY_AREA_ARENA
    local bestHP = 0xff
    for slot = s.c.PLAY_AREA_BENCH_1, count - 1 do
      local hp = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_HP + slot)
      if hp <= bestHP then
        bestHP = hp
        bestSlot = slot
      end
    end
    actor.duelVars:swapTurn()
    return bestSlot
  end

  local function nonTurnPlayAreaCount(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelVars:swapTurn()
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    actor.duelVars:swapTurn()
    return count
  end

  local function selectLowestBenchForAI(setNoBenchSentinel)
    return function(s, context)
      if setNoBenchSentinel then
        s.memory:writeSymbol8("hTemp_ffa0", 0xff)
        local count, err = nonTurnPlayAreaCount(s, context)
        if count == nil then return nil, err end
        if count < 2 then return false end
      end
      local slot, err = aiFindTargetForBenchAttack(s, context)
      if slot == nil then return nil, err end
      s.memory:writeSymbol8("hTemp_ffa0", slot)
      return false
    end
  end

  self:register("Spark_AISelectEffect", selectLowestBenchForAI(true))
  self:register("GengarDarkMind_AISelectEffect", selectLowestBenchForAI(true))
  self:register("HypnoDarkMind_AISelectEffect", selectLowestBenchForAI(true))
  self:register("StretchKick_AISelectEffect", selectLowestBenchForAI(false))
  self:register("NinetalesLure_AISelectEffect", selectLowestBenchForAI(false))
  self:register("VictreebelLure_GetBenchPokemonWithLowestHP", selectLowestBenchForAI(false))

  -- Gigashock selection is a multi-target hTempList path. For <=3 opposing
  -- Bench Pokemon the source chooses them all. For 4-5 Bench Pokemon its actual
  -- compare/swap instructions order by *highest* remaining HP first (despite
  -- the source comment saying lowest first), with later slots winning HP ties,
  -- then truncate the list after three targets. Preserve executable behavior.
  local function gigashockAISelect(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local count, err = nonTurnPlayAreaCount(s, context)
    if count == nil then return nil, err end

    if count < s.c.MAX_PLAY_AREA_POKEMON - 1 then
      local values = {}
      for slot = s.c.PLAY_AREA_BENCH_1, count - 1 do
        values[#values + 1] = slot
      end
      values[#values + 1] = 0xff
      writeTempList(s, values)
      return false
    end

    local values = {}
    for slot = s.c.PLAY_AREA_BENCH_1, count - 1 do
      values[#values + 1] = slot
    end
    actor.duelVars:swapTurn()
    for i = 1, #values do
      local bestHP = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_HP + values[i])
      for j = i + 1, #values do
        local hp = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_HP + values[j])
        if hp >= bestHP then
          bestHP = hp
          values[i], values[j] = values[j], values[i]
        end
      end
    end
    actor.duelVars:swapTurn()
    writeTempList(s, { values[1], values[2], values[3], 0xff })
    return false
  end

  self:register("Gigashock_AISelectEffect", gigashockAISelect)

  self:register("Gigashock_PlayerSelectEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local count, err = nonTurnPlayAreaCount(s, context)
    if count == nil then return nil, err end
    if count < 2 then
      writeTempList(s, { 0xff })
      return false
    end

    local slots, selectErr = s:_selectionList(context, "opponentBenchSlots",
      "selectOpponentBenchCards", { nonTurn = true, max = 3 }, 1, 3)
    if slots == nil then return nil, selectErr end
    actor.duelVars:swapTurn()
    local valid = true
    for _, slot in ipairs(slots) do
      if slot < s.c.PLAY_AREA_BENCH_1 or slot >= count
          or actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot) == 0xff
          or actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_HP + slot) == 0 then
        valid = false
        break
      end
    end
    actor.duelVars:swapTurn()
    if not valid then return nil, "invalid_selection:opponentBenchSlots" end

    local values = {}
    for _, slot in ipairs(slots) do values[#values + 1] = slot end
    values[#values + 1] = 0xff
    writeTempList(s, values)
    return false
  end)

  self:register("Gigashock_BenchDamageEffect", function(s, context)
    local combat = context.combat
    if not combat then return nil, "effect_context_missing_combat" end
    local base, bank = s.memory:address("hTempList")
    for i = 0, 3 do
      local slot = s.memory:read8("hram", base + i, bank)
      if slot == 0xff then return false end
      local damage, damageErr = combat:dealDamageToPlayAreaPokemon(slot, 10, true)
      if damage == nil then return nil, damageErr end
    end
    return nil, "unterminated_gigashock_temp_list"
  end)

  -- ThunderboltEffect:: discards every Energy attached to the user's Arena.
  self:register("ThunderboltEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local count = actor.duelOps:createArenaOrBenchEnergyCardList(s.c.PLAY_AREA_ARENA)
    local base, bank = actor.memory:address("wDuelTempList")
    local indexes = {}
    for i = 0, count - 1 do
      indexes[#indexes + 1] = actor.memory:read8("wram", base + i, bank)
    end
    for _, deckIndex in ipairs(indexes) do actor.duelOps:putCardInDiscardPile(deckIndex) end
    return false
  end)

  -- Hyper Beam / Whirlpool family: select one Energy attached to the Defending
  -- Arena, then discard it only if No Damage or Effect did not prevent the hit.
  local function selectDefendingArenaEnergy(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if not s:_hasAttachedEnergy(actor, true, s.c.PLAY_AREA_ARENA, nil) then
      s.memory:writeSymbol8("hTemp_ffa0", 0xff)
      return false
    end
    local deckIndex, err = s:_selectAttachedEnergy(context, actor, true,
      s.c.PLAY_AREA_ARENA, "opponentEnergyDeckIndex", nil)
    if deckIndex == nil then return nil, err end
    s.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
    s.memory:writeSymbol8("hTemp_ffa0", deckIndex)
    return false
  end
  local function discardDefendingEnergy(updateLastTurn)
    return function(s, context)
      local actor = s:_actor(context)
      if not actor then return nil, "effect_context_missing_actor" end
      local prevented = s.status:checkNoDamageOrEffect()
      if prevented then return false end
      local deckIndex = s.memory:readSymbol8("hTemp_ffa0")
      if deckIndex == 0xff then return false end
      actor.duelVars:swapTurn()
      actor.duelOps:putCardInDiscardPile(deckIndex)
      if updateLastTurn then
        actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_LAST_TURN_EFFECT,
          s.c.LAST_TURN_EFFECT_DISCARD_ENERGY)
      end
      actor.duelVars:swapTurn()
      return false
    end
  end
  self:register("GolduckHyperBeam_PlayerSelectEffect", selectDefendingArenaEnergy)
  self:register("GolduckHyperBeam_DiscardEffect", discardDefendingEnergy(true))
  self:register("Whirlpool_PlayerSelectEffect", selectDefendingArenaEnergy)
  self:register("Whirlpool_DiscardEffect", discardDefendingEnergy(false))
  self:register("DragonairHyperBeam_PlayerSelectEffect", selectDefendingArenaEnergy)
  self:register("DragonairHyperBeam_DiscardEffect", discardDefendingEnergy(true))

  -- Switch/Gust/Whirlwind families use explicit Bench selections but the state
  -- mutation is the already-translated SwapArenaWithBenchPokemon routine.
  self:register("Switch_BenchCheck", function(s, context)
    local actor = context.playerActions
    if not actor then return nil, "effect_context_missing_player_actions" end
    return not s:_hasBench(actor, false)
  end)
  self:register("Switch_PlayerSelection", function(s, context)
    local actor = context.playerActions
    if not actor then return nil, "effect_context_missing_player_actions" end
    local slot, err = s:_selectBench(context, actor, false, "bench")
    if slot == nil then return nil, err end
    s.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    return false
  end)
  self:register("Switch_SwitchEffect", function(s, context)
    local actor = context.playerActions
    if not actor then return nil, "effect_context_missing_player_actions" end
    actor.duelOps:swapArenaWithBenchPokemon(s.memory:readSymbol8("hTemp_ffa0"))
    return false
  end)

  self:register("GustOfWind_BenchCheck", function(s, context)
    local actor = context.playerActions
    if not actor then return nil, "effect_context_missing_player_actions" end
    return not s:_hasBench(actor, true)
  end)
  self:register("GustOfWind_PlayerSelection", function(s, context)
    local actor = context.playerActions
    if not actor then return nil, "effect_context_missing_player_actions" end
    local slot, err = s:_selectBench(context, actor, true, "opponentBench")
    if slot == nil then return nil, err end
    s.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    return false
  end)
  self:register("GustOfWind_SwitchEffect", function(s, context)
    local actor = context.playerActions
    if not actor then return nil, "effect_context_missing_player_actions" end
    actor.duelVars:swapTurn()
    actor.duelOps:swapArenaWithBenchPokemon(s.memory:readSymbol8("hTemp_ffa0"))
    actor.duelVars:swapTurn()
    s.status:clearDamageReductionSubstatus2()
    return false
  end)

  -- DuelistSelectForcedSwitch:: selection belongs to the defending duelist.
  -- Human defenders retain the explicit host-selection boundary; link defenders
  -- retain a transport boundary; AI defenders dispatch through AIDoAction_ForcedSwitch
  -- while temporarily becoming the turn duelist. After an AI selection, reload
  -- the attack state exactly as the source does because the AI scorer clobbers
  -- attack-selection scratch variables.
  local function validateNonTurnBenchSlot(s, actor, slot, key)
    actor.duelVars:swapTurn()
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    local valid = type(slot) == "number" and slot >= s.c.PLAY_AREA_BENCH_1
      and slot < count
      and actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot) ~= 0xff
      and actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_HP + slot) ~= 0
    actor.duelVars:swapTurn()
    if not valid then return nil, "invalid_selection:" .. key end
    return slot
  end

  local function duelistSelectForcedSwitch(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local dtype = actor.duelVars:getNonTurn(s.c.DUELVARS_DUELIST_TYPE)

    if dtype == s.c.DUELIST_TYPE_LINK_OPP then
      local slot, err = s:_selection(context, "forcedSwitchLink",
        "receiveForcedSwitch", { nonTurn = true, duelistType = dtype })
      if slot == nil then return nil, err end
      slot, err = validateNonTurnBenchSlot(s, actor, slot, "forcedSwitchLink")
      if slot == nil then return nil, err end
      s.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
      return slot
    end

    if dtype == s.c.DUELIST_TYPE_PLAYER then
      local slot, err = s:_selectBench(context, actor, true, "opponentBench")
      if slot == nil then return nil, err end
      s.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
      return slot
    end

    local ai = context.ai or s.ai
    if not ai then return nil, "effect_context_missing_ai" end
    actor.duelVars:swapTurn()
    local slot, err = ai:forcedSwitch()
    actor.duelVars:swapTurn()
    if slot == nil then return nil, err end

    local combat = context.combat
    if combat then
      local attackIndex = s.memory:readSymbol8("wPlayerAttackingAttackIndex")
      local cardIndex = s.memory:readSymbol8("wPlayerAttackingCardIndex")
      if attackIndex ~= 0xff and cardIndex ~= 0xff then
        combat:loadAttack(cardIndex, attackIndex)
        combat:updateArenaCardIDsAndClearTwoTurnDuelVars()
      end
    end
    s.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
    return slot
  end

  local function forcedSwitchSelection(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if not s:_hasBench(actor, true) then
      s.memory:writeSymbol8("hTemp_ffa0", 0xff)
      return false
    end
    local slot, err = duelistSelectForcedSwitch(s, context)
    if slot == nil then return nil, err end
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    return false
  end

  local function forcedSwitchEffect(s, context, slot)
    local combat = context.combat
    if not combat then return nil, "effect_context_missing_combat" end
    -- Direct dispatcher calls pass the command record as argument 3; only an
    -- explicit numeric override (Terror Strike's hTempPlayAreaLocation_ffa1)
    -- replaces the ordinary hTemp_ffa0 source slot.
    if type(slot) ~= "number" then slot = s.memory:readSymbol8("hTemp_ffa0") end
    if slot == 0xff then return false end
    if combat.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD_HP) == 0 then
      combat.status:handleDestinyBondSubstatus()
    end
    local prevented = s.status:checkNoDamageOrEffect()
    if prevented then return false end
    combat.duelVars:swapTurn()
    combat.duelOps:swapArenaWithBenchPokemon(slot)
    combat.duelVars:swapTurn()
    s.memory:writeSymbol8("wUnused_DefendingPkmnStatus", 0)
    s.memory:writeSymbol8("wDuelDisplayedScreen", 0)
    s.memory:writeSymbol8("wDefendingWasForcedToSwitch", s.c.TRUE)
    return false
  end

  self:register("ButterfreeWhirlwind_CheckBench", forcedSwitchSelection)
  self:register("ButterfreeWhirlwind_SwitchEffect", forcedSwitchEffect)
  self:register("PidgeottoWhirlwind_SelectEffect", forcedSwitchSelection)
  self:register("PidgeottoWhirlwind_SwitchEffect", forcedSwitchEffect)
  self:register("PidgeyWhirlwind_SelectEffect", forcedSwitchSelection)
  self:register("PidgeyWhirlwind_SwitchEffect", forcedSwitchEffect)

  self:register("Ram_SelectSwitchEffect", forcedSwitchSelection)
  self:register("Ram_RecoilSwitchEffect", function(s, context)
    if not context.combat then return nil, "effect_context_missing_combat" end
    context.combat:dealRecoilDamageToSelf(20)
    return forcedSwitchEffect(s, context)
  end)

  self:register("TerrorStrike_50PercentSelectSwitchPokemon", function(s, context)
    s.memory:writeSymbol8("hTemp_ffa0", s.c.TAILS)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if not s:_hasBench(actor, true) then return false end
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    s.memory:writeSymbol8("hTemp_ffa0", result)
    if result == s.c.TAILS then return false end
    local slot, selectErr = duelistSelectForcedSwitch(s, context)
    if slot == nil then return nil, selectErr end
    s.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", slot)
    return false
  end)
  self:register("TerrorStrike_SwitchDefendingPokemon", function(s, context)
    if s.memory:readSymbol8("hTemp_ffa0") == s.c.TAILS then return false end
    return forcedSwitchEffect(s, context,
      s.memory:readSymbol8("hTempPlayAreaLocation_ffa1"))
  end)

  -- Ninetales/Victreebel Lure use the attacker's chosen opposing Bench target,
  -- but their switch path is intentionally distinct from Whirlwind: the selected
  -- Bench Pokemon itself may block the effect with Neutralizing Shield or
  -- Transparency, and the source does not set wDefendingWasForcedToSwitch.
  local function lureBenchCheck(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    return not s:_hasBench(actor, true)
  end

  local function lurePlayerSelect(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local slot, err = s:_selectBench(context, actor, true, "opponentBench")
    if slot == nil then return nil, err end
    s.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    return false
  end

  local function lureSwitch(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local slot = s.memory:readSymbol8("hTemp_ffa0")
    actor.duelVars:swapTurn()
    local deckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot)
    local cardId = deckIndex ~= 0xff and actor.cardData:getCardIDFromDeckIndex(deckIndex) or nil
    local prevented = false
    if cardId == s.c.MEW_LV8 then
      local attackerStage = actor.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD_STAGE)
      if attackerStage ~= s.c.BASIC then
        s.memory:writeSymbol8("wNoDamageOrEffect", s.c.NO_DAMAGE_OR_EFFECT_NSHIELD)
        prevented = true
      end
    elseif cardId == s.c.HAUNTER_LV17 then
      local result, err = s.setup:tossCoin()
      if result == nil then actor.duelVars:swapTurn(); return nil, err end
      if result == s.c.HEADS then
        s.memory:writeSymbol8("wNoDamageOrEffect", s.c.NO_DAMAGE_OR_EFFECT_TRANSPARENCY)
        prevented = true
      end
    end
    if not prevented then actor.duelOps:swapArenaWithBenchPokemon(slot) end
    actor.duelVars:swapTurn()
    s.memory:writeSymbol8("wDuelDisplayedScreen", 0)
    return false
  end

  self:register("NinetalesLure_CheckBench", lureBenchCheck)
  self:register("NinetalesLure_PlayerSelectEffect", lurePlayerSelect)
  self:register("NinetalesLure_SwitchEffect", lureSwitch)
  self:register("VictreebelLure_AssertPokemonInBench", lureBenchCheck)
  self:register("VictreebelLure_SelectSwitchPokemon", lurePlayerSelect)
  self:register("VictreebelLure_SwitchDefendingPokemon", lureSwitch)

  -- Recover / discard-pile Energy selection families. These routines preserve
  -- the cartridge's source list order: attached Energy scans use deck-index
  -- order, while Discard Pile scans begin with CreateDiscardPileCardList's
  -- newest-to-oldest order and filter without re-sorting.
  local function createDiscardEnergyList(s, actor)
    local discard = actor.duelOps:createDiscardPileCardList()
    local values = {}
    for _, deckIndex in ipairs(discard) do
      local cardId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
      local row = actor.cardData:get(cardId)
      if row and bit.band(row.type, bit.lshift(1, s.c.TYPE_ENERGY_F)) ~= 0 then
        values[#values + 1] = deckIndex
      end
    end
    local base, bank = actor.memory:address("wDuelTempList")
    for i, deckIndex in ipairs(values) do
      actor.memory:write8("wram", base + i - 1, deckIndex, bank)
    end
    actor.memory:write8("wram", base + #values, 0xff, bank)
    return values
  end

  local function recoverCheck(requiredType)
    return function(s, context)
      local actor = s:_actor(context)
      if not actor then return nil, "effect_context_missing_actor" end
      actor.duelOps:getPlayAreaCardAttachedEnergies(s.c.PLAY_AREA_ARENA)
      local attachedBase, attachedBank = s.memory:address("wAttachedEnergies")
      if s.memory:read8("wram", attachedBase + bit.band(requiredType, s.c.TYPE_PKMN), attachedBank) < 1 then
        return true
      end
      local damage = s:_playAreaDamage(actor, s.c.PLAY_AREA_ARENA)
      return (damage or 0) < 10
    end
  end

  local function recoverPlayerSelect(requiredType)
    return function(s, context)
      local actor = s:_actor(context)
      if not actor then return nil, "effect_context_missing_actor" end
      local deckIndex, err = s:_selectAttachedEnergy(context, actor, false,
        s.c.PLAY_AREA_ARENA, "energyDeckIndex", requiredType)
      if deckIndex == nil then return nil, err end
      s.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
      s.memory:writeSymbol8("hTemp_ffa0", deckIndex)
      return false
    end
  end

  local function recoverAISelect(requiredType)
    return function(s, context)
      local actor = s:_actor(context)
      if not actor then return nil, "effect_context_missing_actor" end
      local values = createFilteredArenaEnergyList(s, actor, requiredType)
      if #values < 1 then return nil, "ai_selection_missing_recover_energy" end
      s.memory:writeSymbol8("hTemp_ffa0", values[1])
      return false
    end
  end

  local function recoverHeal(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local damage = s:_playAreaDamage(actor, s.c.PLAY_AREA_ARENA) or 0
    if damage <= 0 then return false end
    return s:_healAttackingArena(context, damage)
  end

  self:register("StarmieRecover_CheckEnergyHP", recoverCheck(self.c.TYPE_ENERGY_WATER))
  self:register("StarmieRecover_PlayerSelectEffect", recoverPlayerSelect(self.c.TYPE_ENERGY_WATER))
  self:register("StarmieRecover_AISelectEffect", recoverAISelect(self.c.TYPE_ENERGY_WATER))
  self:register("StarmieRecover_DiscardEffect", discardTempEnergy)
  self:register("StarmieRecover_HealEffect", recoverHeal)
  self:register("KadabraRecover_CheckEnergyHP", recoverCheck(self.c.TYPE_ENERGY_PSYCHIC))
  self:register("KadabraRecover_PlayerSelectEffect", recoverPlayerSelect(self.c.TYPE_ENERGY_PSYCHIC))
  self:register("KadabraRecover_AISelectEffect", recoverAISelect(self.c.TYPE_ENERGY_PSYCHIC))
  self:register("KadabraRecover_DiscardEffect", discardTempEnergy)
  self:register("KadabraRecover_HealEffect", recoverHeal)

  self:register("DestinyBond_CheckEnergy", checkArenaEnergy(self.c.TYPE_ENERGY_PSYCHIC))
  self:register("DestinyBond_PlayerSelectEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local deckIndex, err = s:_selectAttachedEnergy(context, actor, false,
      s.c.PLAY_AREA_ARENA, "energyDeckIndex", s.c.TYPE_ENERGY_PSYCHIC)
    if deckIndex == nil then return nil, err end
    s.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
    writeTempList(s, { deckIndex })
    return false
  end)
  self:register("DestinyBond_AISelectEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local values = createFilteredArenaEnergyList(s, actor, s.c.TYPE_ENERGY_PSYCHIC)
    if #values < 1 then return nil, "ai_selection_missing_destiny_bond_energy" end
    writeTempList(s, { values[1] })
    return false
  end)
  self:register("DestinyBond_DiscardEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local base, bank = s.memory:address("hTempList")
    actor.duelOps:putCardInDiscardPile(s.memory:read8("hram", base, bank))
    return false
  end)

  local function validateDiscardEnergySelection(s, context, key, maxCount)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local values, err = s:_selectionList(context, key, "selectDiscardCards",
      { energy = true, max = maxCount }, 0, maxCount)
    if values == nil then return nil, err end
    for _, deckIndex in ipairs(values) do
      if actor.duelVars:get(deckIndex) ~= s.c.CARD_LOCATION_DISCARD_PILE then
        return nil, "invalid_selection:" .. key
      end
      local cardId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
      local row = actor.cardData:get(cardId)
      if not row or bit.band(row.type, bit.lshift(1, s.c.TYPE_ENERGY_F)) == 0 then
        return nil, "invalid_selection:" .. key
      end
    end
    local temp = {}
    for _, deckIndex in ipairs(values) do temp[#temp + 1] = deckIndex end
    temp[#temp + 1] = 0xff
    writeTempList(s, temp)
    return false
  end

  local function firstTwoDiscardEnergiesAI(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local values = createDiscardEnergyList(s, actor)
    local chosen = {}
    if values[1] ~= nil then chosen[#chosen + 1] = values[1] end
    if values[2] ~= nil then chosen[#chosen + 1] = values[2] end
    chosen[#chosen + 1] = 0xff
    writeTempList(s, chosen)
    return false
  end

  self:register("EnergyConversion_CheckEnergy", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    return #createDiscardEnergyList(s, actor) == 0
  end)
  self:register("EnergyConversion_PlayerSelectEffect", function(s, context)
    return validateDiscardEnergySelection(s, context, "discardEnergies", 2)
  end)
  self:register("EnergyConversion_AISelectEffect", firstTwoDiscardEnergiesAI)
  self:register("EnergyConversion_AddToHandEffect", function(s, context)
    local combat = context.combat
    if not combat then return nil, "effect_context_missing_combat" end
    combat:dealRecoilDamageToSelf(10)
    local base, bank = s.memory:address("hTempList")
    local i = 0
    while true do
      local deckIndex = s.memory:read8("hram", base + i, bank)
      if deckIndex == 0xff then break end
      combat.duelOps:moveDiscardPileCardToHand(deckIndex)
      combat.duelOps:addCardToHand(deckIndex)
      i = i + 1
    end
    return false
  end)

  local function energyAbsorptionCheck(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    return #createDiscardEnergyList(s, actor) == 0
  end
  local function energyAbsorptionPlayerSelect(s, context)
    return validateDiscardEnergySelection(s, context, "discardEnergies", 2)
  end
  local function energyAbsorptionAttach(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local base, bank = s.memory:address("hTempList")
    local i = 0
    while true do
      local deckIndex = s.memory:read8("hram", base + i, bank)
      if deckIndex == 0xff then break end
      actor.duelOps:moveDiscardPileCardToHand(deckIndex)
      actor.duelVars:set(deckIndex, s.c.CARD_LOCATION_ARENA)
      i = i + 1
    end
    return false
  end
  for _, prefix in ipairs({ "MewtwoAltEnergyAbsorption", "MewtwoEnergyAbsorption" }) do
    self:register(prefix .. "_CheckDiscardPile", energyAbsorptionCheck)
    self:register(prefix .. "_PlayerSelectEffect", energyAbsorptionPlayerSelect)
    self:register(prefix .. "_AISelectEffect", firstTwoDiscardEnergiesAI)
    self:register(prefix .. "_AddToHandEffect", energyAbsorptionAttach)
  end

  -- Electrode Lv35 Energy Spike. The AI's actual choice is prepared by
  -- AISelectSpecialAttackParameters; its AI_SELECTION identity deliberately
  -- clears hTemp_ffa0 when that special branch did not claim the attack.
  self:register("EnergySpike_DeckCheck", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    return actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK) >= s.c.DECK_SIZE
  end)
  self:register("EnergySpike_PlayerSelectEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local basics = s:_cardsAtLocation(actor, s.c.CARD_LOCATION_DECK,
      function(deckIndex) return s:_isBasicEnergy(actor, deckIndex) end)
    if #basics == 0 then
      s.memory:writeSymbol8("hTemp_ffa0", 0xff)
      return false
    end
    local deckIndex, err = s:_selection(context, "deckBasicEnergy", "selectDeckCard",
      { basicEnergy = true })
    if deckIndex == nil then return nil, err end
    if actor.duelVars:get(deckIndex) ~= s.c.CARD_LOCATION_DECK
        or not s:_isBasicEnergy(actor, deckIndex) then
      return nil, "invalid_selection:deckBasicEnergy"
    end
    local slot, slotErr = s:_selection(context, "playArea", "selectPlayArea", {})
    if slot == nil then return nil, slotErr end
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    if type(slot) ~= "number" or slot < s.c.PLAY_AREA_ARENA or slot >= count
        or actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot) == 0xff
        or actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_HP + slot) == 0 then
      return nil, "invalid_selection:playArea"
    end
    s.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
    s.memory:writeSymbol8("hTemp_ffa0", deckIndex)
    s.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
    s.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", slot)
    return false
  end)
  self:register("EnergySpike_AISelectEffect", function(s)
    s.memory:writeSymbol8("hTemp_ffa0", 0xff)
    return false
  end)
  self:register("EnergySpike_AttachEnergyEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local deckIndex = s.memory:readSymbol8("hTemp_ffa0")
    if deckIndex ~= 0xff then
      local slot = s.memory:readSymbol8("hTempPlayAreaLocation_ffa1")
      actor.duelOps:searchCardInDeckAndAddToHand(deckIndex)
      actor.duelOps:addCardToHand(deckIndex)
      actor.duelOps:putHandCardInPlayArea(deckIndex, slot)
    end
    actor.duelOps:shuffleDeck()
    return false
  end)


  -- Barrier:: discard one Psychic Energy, then apply the already-translated
  -- SUBSTATUS1_BARRIER prevention state. Attached-energy list order is the
  -- source deck-index scan order and AI selects its first entry.
  self:register("Barrier_CheckEnergy", checkArenaEnergy(self.c.TYPE_ENERGY_PSYCHIC))
  self:register("Barrier_PlayerSelectEffect",
    selectArenaEnergy(self.c.TYPE_ENERGY_PSYCHIC, "energyDeckIndex"))
  self:register("Barrier_AISelectEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local values = createFilteredArenaEnergyList(s, actor, s.c.TYPE_ENERGY_PSYCHIC)
    if #values < 1 then return nil, "ai_selection_missing_barrier_energy" end
    s.memory:writeSymbol8("hTemp_ffa0", values[1])
    return false
  end)
  self:register("Barrier_DiscardEffect", discardTempEnergy)

  -- Amnesia selection. AIPickAttackForAmnesia first tests whether the Defending
  -- Pokemon can currently pay its second attack; otherwise it prefers attack 1
  -- unless that slot is a Pokemon Power, in which case attack 2 is selected.
  local function defendingPokemonHasAnyAttack(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelVars:swapTurn()
    local deckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD)
    local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
    actor.duelVars:swapTurn()
    if not row or not row.attacks then return true end
    local first = row.attacks[1] or {}
    local second = row.attacks[2] or {}
    return first.category == s.c.POKEMON_POWER and (second.nameTextId or 0) == 0
  end

  local function amnesiaPlayerSelect(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local attackIndex, err = s:_selection(context, "opponentAttackIndex",
      "selectOpponentAttack", { nonTurn = true })
    if attackIndex == nil then return nil, err end
    if attackIndex ~= s.c.FIRST_ATTACK_OR_PKMN_POWER and attackIndex ~= s.c.SECOND_ATTACK then
      return nil, "invalid_selection:opponentAttackIndex"
    end
    actor.duelVars:swapTurn()
    local deckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD)
    local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
    local attack = row and row.attacks and row.attacks[attackIndex + 1]
    actor.duelVars:swapTurn()
    if not attack or (attack.nameTextId or 0) == 0 or attack.category == s.c.POKEMON_POWER then
      return nil, "invalid_selection:opponentAttackIndex"
    end
    s.memory:writeSymbol8("hTemp_ffa0", attackIndex)
    return false
  end

  local function amnesiaAISelect(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelVars:swapTurn()
    local deckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD)
    local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
    if not row or not row.attacks then
      actor.duelVars:swapTurn()
      return nil, "ai_selection_missing_defending_attack"
    end
    actor.duelOps:getPlayAreaCardAttachedEnergies(s.c.PLAY_AREA_ARENA)
    actor.status:handleEnergyBurn()
    local first = row.attacks[1] or {}
    local second = row.attacks[2] or {}
    local chosen = s.c.FIRST_ATTACK_OR_PKMN_POWER
    if (first.nameTextId or 0) ~= 0 then
      local attachedBase, attachedBank = s.memory:address("wAttachedEnergies")
      local enoughSecond = (second.nameTextId or 0) ~= 0 and second.category ~= s.c.POKEMON_POWER
      local requiredColored = 0
      if enoughSecond then
        for color = 0, s.c.NUM_COLORED_TYPES - 1 do
          local required = second.energy[color] or 0
          requiredColored = requiredColored + required
          if required > s.memory:read8("wram", attachedBase + color, attachedBank) then
            enoughSecond = false
            break
          end
        end
      end
      if enoughSecond then
        local total = s.memory:readSymbol8("wTotalAttachedEnergies")
        local colorless = second.energy[s.c.COLORLESS] or 0
        enoughSecond = total - requiredColored >= colorless
      end
      if enoughSecond then
        chosen = s.c.SECOND_ATTACK
      elseif first.category == s.c.POKEMON_POWER then
        chosen = s.c.SECOND_ATTACK
      end
    end
    actor.duelVars:swapTurn()
    s.memory:writeSymbol8("hTemp_ffa0", chosen)
    return false
  end

  local function amnesiaDisable(s)
    local applied = s.status:applySubstatus2ToDefendingCard(s.c.SUBSTATUS2_AMNESIA)
    if not applied or s.memory:readSymbol8("wNoDamageOrEffect") ~= 0 then return false end
    local attackIndex = s.memory:readSymbol8("hTemp_ffa0")
    s.status.duelVars:setNonTurn(s.c.DUELVARS_ARENA_CARD_DISABLED_ATTACK_INDEX, attackIndex)
    s.status.duelVars:setNonTurn(s.c.DUELVARS_ARENA_CARD_LAST_TURN_EFFECT,
      s.c.LAST_TURN_EFFECT_AMNESIA)
    return false
  end

  for _, prefix in ipairs({ "PoliwhirlAmnesia", "SlowpokeAmnesia" }) do
    self:register(prefix .. "_CheckAttacks", defendingPokemonHasAnyAttack)
    self:register(prefix .. "_PlayerSelectEffect", amnesiaPlayerSelect)
    self:register(prefix .. "_AISelectEffect", amnesiaAISelect)
    self:register(prefix .. "_DisableEffect", amnesiaDisable)
  end

  -- Call for Family / Sprout deck search families. The initial check only tests
  -- deck non-emptiness and Bench space; absence of a matching Pokemon is a
  -- legal no-op followed by a shuffle. AI scans CreateDeckCardList in source
  -- order and stores every candidate in hTemp_ffa0 before testing it.
  local function familyCheckDeckAndPlayArea(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK) >= s.c.DECK_SIZE then
      return true
    end
    return actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
      >= s.c.MAX_PLAY_AREA_POKEMON
  end

  local function familyPlayerSelect(predicate, spec)
    return function(s, context)
      local actor = s:_actor(context)
      if not actor then return nil, "effect_context_missing_actor" end
      s.memory:writeSymbol8("hTemp_ffa0", 0xff)
      local deck = actor.duelOps:createDeckCardList()
      local hasMatch = false
      for _, deckIndex in ipairs(deck) do
        if predicate(s, actor, deckIndex) then hasMatch = true break end
      end
      if not hasMatch then return false end
      local chosen, err = s:_selection(context, "deckFamilyPokemon", "selectDeckCard", spec or {})
      if chosen == nil then return nil, err end
      if actor.duelVars:get(chosen) ~= s.c.CARD_LOCATION_DECK
          or not predicate(s, actor, chosen) then
        return nil, "invalid_selection:deckFamilyPokemon"
      end
      s.memory:writeSymbol8("hTempCardIndex_ff98", chosen)
      s.memory:writeSymbol8("hTemp_ffa0", chosen)
      return false
    end
  end

  local function familyAISelect(predicate)
    return function(s, context)
      local actor = s:_actor(context)
      if not actor then return nil, "effect_context_missing_actor" end
      local deck = actor.duelOps:createDeckCardList()
      for _, deckIndex in ipairs(deck) do
        s.memory:writeSymbol8("hTemp_ffa0", deckIndex)
        if predicate(s, actor, deckIndex) then return false end
      end
      s.memory:writeSymbol8("hTemp_ffa0", 0xff)
      return false
    end
  end

  local function familyPutInPlayArea(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local deckIndex = s.memory:readSymbol8("hTemp_ffa0")
    if deckIndex ~= 0xff then
      actor.duelOps:searchCardInDeckAndAddToHand(deckIndex)
      actor.duelOps:addCardToHand(deckIndex)
      actor.duelOps:putHandPokemonCardInPlayArea(deckIndex)
    end
    actor.duelOps:shuffleDeck()
    return false
  end

  local function exactCard(cardId)
    return function(_, actor, deckIndex)
      return actor.cardData:getCardIDFromDeckIndex(deckIndex) == cardId
    end
  end
  local function nidoranFamily(s, actor, deckIndex)
    local cardId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
    return cardId == s.c.NIDORANF or cardId == s.c.NIDORANM
  end
  local function basicFighting(s, actor, deckIndex)
    local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
    return row ~= nil and row.type == s.c.FIGHTING and row.stage == s.c.BASIC
  end

  local families = {
    { "Sprout", exactCard(self.c.ODDISH), { cardId = self.c.ODDISH } },
    { "BellsproutCallForFamily", exactCard(self.c.BELLSPROUT), { cardId = self.c.BELLSPROUT } },
    { "KrabbyCallForFamily", exactCard(self.c.KRABBY), { cardId = self.c.KRABBY } },
    { "NidoranFCallForFamily", nidoranFamily, { cardIds = { self.c.NIDORANF, self.c.NIDORANM } } },
    { "MarowakCallForFamily", basicFighting, { pokemon = true, basic = true, type = self.c.FIGHTING } },
  }
  for _, family in ipairs(families) do
    local prefix, predicate, spec = family[1], family[2], family[3]
    self:register(prefix .. "_CheckDeckAndPlayArea", familyCheckDeckAndPlayArea)
    self:register(prefix .. "_PlayerSelectEffect", familyPlayerSelect(predicate, spec))
    self:register(prefix .. "_AISelectEffect", familyAISelect(predicate))
    self:register(prefix .. "_PutInPlayAreaEffect", familyPutInPlayArea)
  end

  -- Teleport has two AI paths in the source. The generic AI_SELECTION identity
  -- calls Random(number-in-play), which can produce Arena slot 0 despite the
  -- source comment saying it selects a Bench card. The real Exeggutor AI path
  -- normally bypasses this via AISelectSpecialAttackParameters.
  self:register("Teleport_CheckBench", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    return actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) < 2
  end)
  self:register("Teleport_PlayerSelectEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local slot, err = s:_selectBench(context, actor, false, "bench")
    if slot == nil then return nil, err end
    s.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    return false
  end)
  self:register("Teleport_AISelectEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    s.memory:writeSymbol8("hTemp_ffa0", actor.setup.rng:random(count))
    return false
  end)
  self:register("Teleport_SwitchEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local slot = s.memory:readSymbol8("hTemp_ffa0")
    actor.duelOps:swapArenaWithBenchPokemon(slot)
    s.memory:writeSymbol8("wDuelDisplayedScreen", 0)
    return false
  end)

  -- Devolution Beam helpers. GetCardOneStageBelow reconstructs the attached
  -- evolution stack by CARD_LOCATION_PLAY_AREA|slot and stage exactly like the
  -- cartridge's wAllStagesIndices scratch array.
  local function cardOneStageBelow(s, actor, slot)
    local currentDeckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot)
    if currentDeckIndex == 0xff then return nil, "empty_slot" end
    local currentId = actor.cardData:getCardIDFromDeckIndex(currentDeckIndex)
    local current = actor.cardData:get(currentId)
    if not current then return nil, "missing_card_data" end
    if current.stage == s.c.BASIC then return nil, "basic" end
    local expected = bit.bor(s.c.CARD_LOCATION_PLAY_AREA, slot)
    local stages = {}
    for deckIndex = 0, s.c.DECK_SIZE - 1 do
      if actor.duelVars:get(deckIndex) == expected then
        local cardId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
        local row = actor.cardData:get(cardId)
        if row and row.type < s.c.TYPE_ENERGY then stages[row.stage] = deckIndex end
      end
    end
    local stage1 = s.c.STAGE1 or 1
    local stage2WithoutStage1 = s.c.STAGE2_WITHOUT_STAGE1 or 3
    local lowerStage = (current.stage == stage1 or current.stage == stage2WithoutStage1)
      and s.c.BASIC or stage1
    local lower = stages[lowerStage]
    if lower == nil then return nil, "missing_pre_evolution_card" end
    return lower, currentDeckIndex, current
  end

  local function firstNonBasic(s, actor, nonTurn)
    if nonTurn then actor.duelVars:swapTurn() end
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    local result
    for slot = s.c.PLAY_AREA_ARENA, count - 1 do
      if actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_STAGE + slot) ~= s.c.BASIC then
        result = slot
        break
      end
    end
    if nonTurn then actor.duelVars:swapTurn() end
    return result
  end

  self:register("DevolutionBeam_CheckPlayArea", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if firstNonBasic(s, actor, false) ~= nil then return false end
    return firstNonBasic(s, actor, true) == nil
  end)

  self:register("DevolutionBeam_PlayerSelectEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local side, sideErr = s:_selection(context, "devolutionSide", "selectDuelist",
      { own = true, opponent = true })
    if side == nil then return nil, sideErr end
    if side ~= 0 and side ~= 1 then return nil, "invalid_selection:devolutionSide" end
    local slot, slotErr = s:_selection(context, "devolutionPlayArea", "selectPlayArea",
      { nonTurn = side == 1, evolved = true })
    if slot == nil then return nil, slotErr end
    if side == 1 then actor.duelVars:swapTurn() end
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    local valid = type(slot) == "number" and slot >= s.c.PLAY_AREA_ARENA and slot < count
      and actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot) ~= 0xff
      and actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_STAGE + slot) ~= s.c.BASIC
    if side == 1 then actor.duelVars:swapTurn() end
    if not valid then return nil, "invalid_selection:devolutionPlayArea" end
    s.memory:writeSymbol8("hTemp_ffa0", side)
    s.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", slot)
    return false
  end)

  self:register("DevolutionBeam_AISelectEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local slot = firstNonBasic(s, actor, true)
    if slot ~= nil then
      s.memory:writeSymbol8("hTemp_ffa0", 1)
    else
      slot = firstNonBasic(s, actor, false)
      s.memory:writeSymbol8("hTemp_ffa0", 0)
    end
    if slot == nil then return nil, "ai_selection_missing_evolved_pokemon" end
    s.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", slot)
    return false
  end)

  self:register("DevolutionBeam_LoadAnimation", function(s)
    s.memory:writeSymbol8("wLoadedAttackAnimation", 0)
    return false
  end)

  self:register("DevolutionBeam_DevolveEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local side = s.memory:readSymbol8("hTemp_ffa0")
    if side == 0xff then return false end
    local slot = s.memory:readSymbol8("hTempPlayAreaLocation_ffa1")
    local swapped = side ~= 0
    if swapped then actor.duelVars:swapTurn() end

    local function finish(carry, err)
      if swapped then actor.duelVars:swapTurn() end
      return carry, err
    end

    local currentDeckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot)
    if currentDeckIndex == 0xff then return finish(nil, "devolution_target_empty") end
    local currentId = actor.cardData:getCardIDFromDeckIndex(currentDeckIndex)
    local current = actor.cardData:get(currentId)
    if not current then return finish(nil, "missing_card_data") end

    if swapped then
      local attackerDeck = actor.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD)
      local attackerId = actor.cardData:getCardIDFromDeckIndex(attackerDeck)
      local attackCategory = s.memory:readSymbol8("wLoadedAttackCategory")
      local prevented = false
      if slot == s.c.PLAY_AREA_ARENA then
        prevented = s.status:handleNoDamageOrEffectSubstatus(attackerId, attackCategory, false)
      end
      if not prevented then
        local adjustedDamage, powerPrevented = s.status:handlePlayAreaPokemonPowerDamage(
          0, attackCategory, currentId, slot, attackerId, false)
        if adjustedDamage == nil then return finish(nil, powerPrevented) end
        prevented = powerPrevented
      end
      if prevented or s.memory:readSymbol8("wNoDamageOrEffect") ~= 0 then
        return finish(false)
      end
    end

    local lower, lowerErr = cardOneStageBelow(s, actor, slot)
    if lower == nil then return finish(nil, lowerErr) end
    local lowerId = actor.cardData:getCardIDFromDeckIndex(lower)
    local lowerRow = actor.cardData:get(lowerId)
    if not lowerRow then return finish(nil, "missing_card_data") end
    local remaining = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_HP + slot)
    local damage = math.max(0, (current.hp or 0) - remaining)

    s.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD + slot, lower)
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_HP + slot, math.max(0, lowerRow.hp - damage))
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_STAGE + slot, lowerRow.stage)
    if slot == s.c.PLAY_AREA_ARENA then actor.duelOps:clearAllStatusConditions() end
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_CHANGED_TYPE + slot, 0)
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_FLAGS + slot, 0)
    actor.duelOps:addCardToHand(currentDeckIndex)
    s.memory:writeSymbol8("wDuelDisplayedScreen", 0)
    return finish(false)
  end)

  -- Devolution Spray (Trainer): unlike Devolution Beam, only the Turn
  -- Duelist's own side, and the player may repeat the devolution multiple
  -- times on the SAME chosen Play Area card in one use (source: a menu loop
  -- offering "devolve again" vs. "done" after each step, tracked here as a
  -- single step count rather than re-modeling that loop). Each step reuses
  -- cardOneStageBelow (the same primitive Devolution Beam uses) and carries
  -- existing damage forward onto the lower stage's max HP, then the source
  -- explicitly runs HandleDestinyBondAndBetweenTurnKnockOuts itself (Trainer
  -- cards, unlike attacks, don't fall through a shared AFTER_DAMAGE/KO
  -- pipeline) -- reusing the same combat.status:handleDestinyBondSubstatus/
  -- combat.knockouts:handlePendingResolution pair Curse's own damage-
  -- transfer effect already calls for the identical reason.
  self:register("DevolutionSpray_PlayAreaEvolutionCheck", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    for slot = 0, count - 1 do
      local deckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot)
      if deckIndex ~= 0xff then
        local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
        if row and row.stage ~= s.c.BASIC then return false end
      end
    end
    return true
  end)
  self:register("DevolutionSpray_PlayerSelection", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local slot, err = s:_selectPlayArea(context)
    if slot == nil then return nil, err end
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    if type(slot) ~= "number" or slot < s.c.PLAY_AREA_ARENA or slot >= count
        or actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot) == 0xff
        or actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_STAGE + slot) == s.c.BASIC then
      return nil, "invalid_selection:devolutionPlayArea"
    end
    local steps, stepsErr = s:_selection(context, "devolutionSteps", "selectDevolutionSteps",
      { playArea = slot })
    if steps == nil then return nil, stepsErr end
    if type(steps) ~= "number" or steps < 1 then
      return nil, "invalid_selection:devolutionSteps"
    end
    context.effectState = context.effectState or {}
    context.effectState.devolutionPlayArea = slot
    context.effectState.devolutionSteps = steps
    return false
  end)
  self:register("DevolutionSpray_DevolutionEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local st = context.effectState or {}
    local slot = st.devolutionPlayArea
    local steps = st.devolutionSteps or 0
    if slot == nil then return nil, "effect_context_missing_devolution_selection" end
    s.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
    for _ = 1, steps do
      local lower, lowerErr = cardOneStageBelow(s, actor, slot)
      if lower == nil then return nil, lowerErr end
      local oldDeckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot)
      local oldId = actor.cardData:getCardIDFromDeckIndex(oldDeckIndex)
      local old = actor.cardData:get(oldId)
      local lowerId = actor.cardData:getCardIDFromDeckIndex(lower)
      local lowerRow = actor.cardData:get(lowerId)
      if not old or not lowerRow then return nil, "missing_card_data" end
      local remaining = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_HP + slot)
      local damage = math.max(0, (old.hp or 0) - remaining)
      actor.duelVars:set(s.c.DUELVARS_ARENA_CARD + slot, lower)
      actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_HP + slot, math.max(0, lowerRow.hp - damage))
      actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_STAGE + slot, lowerRow.stage)
      actor.duelOps:putCardInDiscardPile(oldDeckIndex)
    end
    if slot == s.c.PLAY_AREA_ARENA then actor.duelOps:clearAllStatusConditions() end
    local combat = context.combat
    if combat then
      combat.status:handleDestinyBondSubstatus()
      local finished, koErr = combat.knockouts:handlePendingResolution()
      if koErr then return nil, koErr end
      context.powerEndedDuel = finished == true
    end
    return false
  end)

  -- Final AI-selection families. These preserve source quirks rather than
  -- normalizing them: Metronome's AI selector is a literal no-op, Prophecy's
  -- AI always declines to reorder, and Wildfire's AI chooses zero discards.

  -- Clefairy/Clefable Metronome. The AI selector remains a literal no-op, but
  -- the player-facing INITIAL_EFFECT_2 path loads and executes the selected
  -- Defending Pokemon attack exactly like HandlePlayerMetronomeEffect.
  self:register("ClefableMetronome_CheckAttacks", defendingPokemonHasAnyAttack)
  self:register("ClefairyMetronome_CheckAttacks", defendingPokemonHasAnyAttack)

  local function handlePlayerMetronomeEffect(s, context, energyCost)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    s.memory:writeSymbol8("wMetronomeEnergyCost", energyCost)

    local originalName = s:_readWord("wLoadedAttackName")
    local selection = context.selection or {}
    local attackIndex = selection.metronomeAttack
    if attackIndex == nil then
      local select = s.adapters.selectOpponentAttack
      if select then
        attackIndex = select(context, { nonTurn = true, metronome = true })
      else
        return nil, "selection_required:metronomeAttack"
      end
    end
    if attackIndex ~= s.c.FIRST_ATTACK_OR_PKMN_POWER and attackIndex ~= s.c.SECOND_ATTACK then
      return nil, "invalid_selection:metronomeAttack"
    end

    actor.duelVars:swapTurn()
    local defendingDeckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD)
    local defendingCardId = actor.cardData:getCardIDFromDeckIndex(defendingDeckIndex)
    local defendingRow = actor.cardData:get(defendingCardId)
    local copied = defendingRow and defendingRow.attacks and defendingRow.attacks[attackIndex + 1]
    actor.duelVars:swapTurn()
    if not copied or (copied.nameTextId or 0) == 0 or copied.category == s.c.POKEMON_POWER then
      return nil, "invalid_selection:metronomeAttack"
    end
    if copied.nameTextId == originalName then return true end

    local selected, selectedBank = s.memory:address("wMetronomeSelectedAttack")
    s.memory:write8("wram", selected, defendingDeckIndex, selectedBank)
    s.memory:write8("wram", selected + 1, attackIndex, selectedBank)

    actor.duelVars:swapTurn()
    actor:loadAttack(defendingDeckIndex, attackIndex)
    actor.duelVars:swapTurn()

    local phases = {
      s.c.EFFECTCMDTYPE_INITIAL_EFFECT_1,
      s.c.EFFECTCMDTYPE_INITIAL_EFFECT_2,
      s.c.EFFECTCMDTYPE_DISCARD_ENERGY,
      s.c.EFFECTCMDTYPE_REQUIRE_SELECTION,
      s.c.EFFECTCMDTYPE_BEFORE_DAMAGE,
      s.c.EFFECTCMDTYPE_AFTER_DAMAGE,
    }
    local translated, reason = s:validatePhases(phases)
    if not translated then return nil, reason end

    local nestedSelection = selection.metronomeEffect
    local copiedContext = { combat = actor, selection = nestedSelection }
    local carry, err = s:tryExecute(s.c.EFFECTCMDTYPE_INITIAL_EFFECT_1, copiedContext)
    if carry == nil then return nil, err end
    if carry then return true end
    carry, err = s:tryExecute(s.c.EFFECTCMDTYPE_INITIAL_EFFECT_2, copiedContext)
    if carry == nil then return nil, err end
    if carry then return true end

    -- The outer Combat pipeline will now execute the copied attack's later
    -- command phases. Point its shared context at the copied attack's own input.
    context.selection = nestedSelection

    local send = s.adapters.sendMetronomeAttack
    if send then
      local ok, sendErr = send({
        cardIndex = defendingDeckIndex,
        attackIndex = attackIndex,
        energyCost = energyCost,
      })
      if ok == false then return nil, sendErr or "metronome_transport_failed" end
    end

    s.memory:writeSymbol8("wPlayerAttackingCardIndex", defendingDeckIndex)
    s.memory:writeSymbol8("wPlayerAttackingAttackIndex", attackIndex)
    s.memory:writeSymbol8("wPlayerAttackingCardID", defendingCardId)
    return false
  end

  self:register("ClefableMetronome_UseAttackEffect", function(s, context)
    return handlePlayerMetronomeEffect(s, context, 1)
  end)
  self:register("ClefairyMetronome_UseAttackEffect", function(s, context)
    return handlePlayerMetronomeEffect(s, context, 3)
  end)

  local function metronomeAINoop()
    return false
  end
  self:register("ClefableMetronome_AISelectEffect", metronomeAINoop)
  self:register("ClefairyMetronome_AISelectEffect", metronomeAINoop)

  -- Mirror Move shared implementation. The two card-specific labels are thin
  -- aliases in source, so keep one common state machine and register both sets.
  local function mirrorMoveInitial1(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local low = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_LAST_TURN_DAMAGE)
    local high = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_LAST_TURN_DAMAGE + 1)
    local status = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_LAST_TURN_STATUS)
    local sub2 = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_LAST_TURN_SUBSTATUS2)
    return low == 0 and high == 0 and status == 0 and sub2 == 0
  end

  local function mirrorMoveInitial2(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    s.memory:writeSymbol8("hTemp_ffa0", 0xff)
    local effect = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_LAST_TURN_EFFECT)
    if effect == s.c.LAST_TURN_EFFECT_AMNESIA then
      return amnesiaPlayerSelect(s, context)
    end
    return false
  end

  local function mirrorMovePlayerSelection(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local effect = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_LAST_TURN_EFFECT)
    if effect == s.c.LAST_TURN_EFFECT_DISCARD_ENERGY then
      return selectDefendingArenaEnergy(s, context)
    end
    return false
  end

  local function mirrorMoveAISelection(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    s.memory:writeSymbol8("hTemp_ffa0", 0xff)
    local effect = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_LAST_TURN_EFFECT)
    if effect == s.c.LAST_TURN_EFFECT_DISCARD_ENERGY then
      local picked, err = aiPickEnergyCardToDiscardFromDefendingPokemon(s, context)
      if picked == nil then return nil, err end
      s.memory:writeSymbol8("hTemp_ffa0", picked)
    elseif effect == s.c.LAST_TURN_EFFECT_AMNESIA then
      return amnesiaAISelect(s, context)
    end
    return false
  end

  local function mirrorMoveBeforeDamage(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local effect = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_LAST_TURN_EFFECT)
    if effect == s.c.LAST_TURN_EFFECT_AMNESIA then
      return amnesiaDisable(s, context)
    end

    local low = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_LAST_TURN_DAMAGE)
    local high = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_LAST_TURN_DAMAGE + 1)
    s:_writeWord("wDamage", low + 0x100 * high)
    if low ~= 0 or high ~= 0 then
      s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_HIT)
    end

    local status = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_LAST_TURN_STATUS)
    local poison = bit.band(status, s.c.PSN_DBLPSN)
    if poison == s.c.DOUBLE_POISONED then
      s.status:queueStatusCondition(s.c.CNF_SLP_PRZ, s.c.DOUBLE_POISONED)
    elseif poison == s.c.POISONED then
      s.status:queueStatusCondition(s.c.CNF_SLP_PRZ, s.c.POISONED)
    end
    local condition = bit.band(status, s.c.CNF_SLP_PRZ)
    if condition == s.c.CONFUSED or condition == s.c.ASLEEP or condition == s.c.PARALYZED then
      s.status:queueStatusCondition(s.c.PSN_DBLPSN, condition)
    end

    local sub2 = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_LAST_TURN_SUBSTATUS2)
    actor.duelVars:setNonTurn(s.c.DUELVARS_ARENA_CARD_SUBSTATUS2, sub2)
    return false
  end

  local function mirrorMoveAfterDamage(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if s.memory:readSymbol8("wNoDamageOrEffect") ~= 0 then return false end

    local effect = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_LAST_TURN_EFFECT)
    if effect == s.c.LAST_TURN_EFFECT_DISCARD_ENERGY then
      local selected = s.memory:readSymbol8("hTemp_ffa0")
      if selected ~= 0xff then
        actor.duelVars:swapTurn()
        actor.duelOps:putCardInDiscardPile(selected)
        actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_LAST_TURN_EFFECT,
          s.c.LAST_TURN_EFFECT_DISCARD_ENERGY)
        actor.duelVars:swapTurn()
      end
    end

    local changedWeak = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_LAST_TURN_CHANGE_WEAK)
    if changedWeak == 0 then return false end
    actor.duelVars:swapTurn()
    local deckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD)
    local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
    actor.duelVars:swapTurn()
    if not row or (row.weakness or 0) == 0 then return false end
    actor.duelVars:setNonTurn(s.c.DUELVARS_ARENA_CARD_CHANGED_WEAKNESS, changedWeak)
    return false
  end

  for _, prefix in ipairs({ "SpearowMirrorMove", "PidgeottoMirrorMove" }) do
    self:register(prefix .. "_InitialEffect1", mirrorMoveInitial1)
    self:register(prefix .. "_InitialEffect2", mirrorMoveInitial2)
    self:register(prefix .. "_PlayerSelection", mirrorMovePlayerSelection)
    self:register(prefix .. "_AISelection", mirrorMoveAISelection)
    self:register(prefix .. "_BeforeDamage", mirrorMoveBeforeDamage)
    self:register(prefix .. "_AfterDamage", mirrorMoveAfterDamage)
  end

  -- Porygon Conversion. AISelectConversionColor scans Bench only: first for a
  -- non-colorless Pokemon that can currently attack, then for one with any
  -- attached Energy, and finally falls back to Random(NUM_COLORED_TYPES).
  local function attackHasEnoughEnergy(s, actor, slot, attack)
    if not attack or (attack.nameTextId or 0) == 0 or attack.category == s.c.POKEMON_POWER then
      return false
    end
    actor.duelOps:getPlayAreaCardAttachedEnergies(slot)
    actor.status:handleEnergyBurn()
    local base, bank = s.memory:address("wAttachedEnergies")
    local colored = 0
    for color = 0, s.c.NUM_COLORED_TYPES - 1 do
      local required = attack.energy[color] or 0
      colored = colored + required
      if required > s.memory:read8("wram", base + color, bank) then return false end
    end
    local total = s.memory:readSymbol8("wTotalAttachedEnergies")
    return total - colored >= (attack.energy[s.c.COLORLESS] or 0)
  end

  local function aiSelectConversionColor(s, actor)
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    for slot = s.c.PLAY_AREA_BENCH_1, count - 1 do
      local deckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot)
      local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
      if row and row.type ~= s.c.COLORLESS then
        local attacks = row.attacks or {}
        if attackHasEnoughEnergy(s, actor, slot, attacks[1])
            or attackHasEnoughEnergy(s, actor, slot, attacks[2]) then
          local color = bit.band(row.type, s.c.TYPE_PKMN)
          s.memory:writeSymbol8("hTemp_ffa0", color)
          return color
        end
      end
    end
    for slot = s.c.PLAY_AREA_BENCH_1, count - 1 do
      actor.duelOps:getPlayAreaCardAttachedEnergies(slot)
      local total = s.memory:readSymbol8("wTotalAttachedEnergies")
      if total ~= 0 then
        local deckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot)
        local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
        if row and row.type ~= s.c.COLORLESS then
          local color = bit.band(row.type, s.c.TYPE_PKMN)
          s.memory:writeSymbol8("hTemp_ffa0", color)
          return color
        end
      end
    end
    local color = actor.setup.rng:random(s.c.NUM_COLORED_TYPES)
    s.memory:writeSymbol8("hTemp_ffa0", color)
    return color
  end

  local function selectConversionColor(s, context, key, ownSide)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local color, err = s:_selection(context, key, "selectColor",
      { own = ownSide, opponent = not ownSide, excludeColorless = true })
    if color == nil then return nil, err end
    if type(color) ~= "number" or color < s.c.FIRE or color >= s.c.NUM_COLORED_TYPES then
      return nil, "invalid_selection:" .. key
    end
    s.memory:writeSymbol8("hTemp_ffa0", color)
    return false
  end

  self:register("Conversion1_WeaknessCheck", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelVars:swapTurn()
    local deckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD)
    local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
    actor.duelVars:swapTurn()
    return not row or (row.weakness or 0) == 0
  end)
  self:register("Conversion1_PlayerSelectEffect", function(s, context)
    return selectConversionColor(s, context, "conversionWeaknessColor", false)
  end)
  self:register("Conversion1_AISelectEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    aiSelectConversionColor(s, actor)
    return false
  end)
  self:register("Conversion1_ChangeWeaknessEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if s.status:checkNoDamageOrEffect() then return false end
    local color = s.memory:readSymbol8("hTemp_ffa0")
    local wr = bit.rshift(0x80, color)
    actor.duelVars:setNonTurn(s.c.DUELVARS_ARENA_CARD_CHANGED_WEAKNESS, wr)
    actor.duelVars:setNonTurn(s.c.DUELVARS_ARENA_CARD_LAST_TURN_CHANGE_WEAK, wr)
    s.status:applySubstatus2ToDefendingCard(s.c.SUBSTATUS2_CONVERSION2)
    return false
  end)

  self:register("Conversion2_ResistanceCheck", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local deckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD)
    local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
    return not row or (row.resistance or 0) == 0
  end)
  self:register("Conversion2_PlayerSelectEffect", function(s, context)
    return selectConversionColor(s, context, "conversionResistanceColor", true)
  end)
  self:register("Conversion2_AISelectEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelVars:swapTurn()
    local deckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD)
    local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
    actor.duelVars:swapTurn()
    if row and row.type ~= s.c.COLORLESS then
      s.memory:writeSymbol8("hTemp_ffa0", row.type)
      return false
    end
    actor.duelVars:swapTurn()
    aiSelectConversionColor(s, actor)
    actor.duelVars:swapTurn()
    return false
  end)
  self:register("Conversion2_ChangeResistanceEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local color = s.memory:readSymbol8("hTemp_ffa0")
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_CHANGED_RESISTANCE,
      bit.rshift(0x80, color))
    return false
  end)

  -- Prophecy. AI never chooses this attack in source, so its selector stores
  -- $ff and the AFTER_DAMAGE routine returns immediately. The player path keeps
  -- the selected side plus up to the top three cards in hTempList.
  self:register("Prophecy_CheckDeck", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local ownEmpty = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK) >= s.c.DECK_SIZE
    local otherEmpty = actor.duelVars:getNonTurn(s.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK) >= s.c.DECK_SIZE
    return ownEmpty and otherEmpty
  end)
  self:register("Prophecy_PlayerSelectEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local side, sideErr = s:_selection(context, "prophecySide", "selectDuelist",
      { own = true, opponent = true })
    if side == nil then return nil, sideErr end
    if side ~= 0 and side ~= 1 then return nil, "invalid_selection:prophecySide" end
    if side == 1 then actor.duelVars:swapTurn() end
    local gone = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)
    local count = math.min(3, math.max(0, s.c.DECK_SIZE - gone))
    local top = {}
    for i = 0, count - 1 do
      top[#top + 1] = actor.duelVars:get(s.c.DUELVARS_DECK_CARDS + gone + i)
    end
    if side == 1 then actor.duelVars:swapTurn() end
    if #top == 0 then return nil, "invalid_selection:prophecySide" end
    local order, orderErr = s:_selectionList(context, "prophecyOrder", "selectCardOrder",
      { cards = top, side = side }, #top, #top)
    if order == nil then return nil, orderErr end
    local expected = {}
    for _, v in ipairs(top) do expected[v] = (expected[v] or 0) + 1 end
    for _, v in ipairs(order) do
      if not expected[v] or expected[v] == 0 then return nil, "invalid_selection:prophecyOrder" end
      expected[v] = expected[v] - 1
    end
    local temp = { side }
    for _, v in ipairs(order) do temp[#temp + 1] = v end
    temp[#temp + 1] = 0xff
    writeTempList(s, temp)
    return false
  end)
  self:register("Prophecy_AISelectEffect", function(s)
    s.memory:writeSymbol8("hTemp_ffa0", 0xff)
    return false
  end)
  self:register("Prophecy_ReorderDeckEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local base, bank = s.memory:address("hTempList")
    local side = s.memory:read8("hram", base, bank)
    if side == 0xff then return false end
    if side ~= 0 and side ~= 1 then return nil, "invalid_prophecy_side" end
    if side == 1 then actor.duelVars:swapTurn() end
    local chosen = {}
    for i = 1, 3 do
      local deckIndex = s.memory:read8("hram", base + i, bank)
      if deckIndex == 0xff then break end
      chosen[#chosen + 1] = deckIndex
      actor.duelOps:searchCardInDeckAndAddToHand(deckIndex)
    end
    for i = #chosen, 1, -1 do actor.duelOps:returnCardToDeck(chosen[i]) end
    if side == 1 then actor.duelVars:swapTurn() end
    return false
  end)

  -- Scavenge. Discard-list order is newest to oldest; AI chooses the first
  -- Psychic Energy attached to the Arena and first Trainer in that list.
  local function createTrainerDiscardList(s, actor)
    local discard = actor.duelOps:createDiscardPileCardList()
    local values = {}
    for _, deckIndex in ipairs(discard) do
      local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
      if row and row.type == s.c.TYPE_TRAINER then values[#values + 1] = deckIndex end
    end
    local base, bank = s.memory:address("wDuelTempList")
    for i, deckIndex in ipairs(values) do s.memory:write8("wram", base + i - 1, deckIndex, bank) end
    s.memory:write8("wram", base + #values, 0xff, bank)
    return values
  end

  self:register("Scavenge_CheckDiscardPile", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelOps:getPlayAreaCardAttachedEnergies(s.c.PLAY_AREA_ARENA)
    local base, bank = s.memory:address("wAttachedEnergies")
    if s.memory:read8("wram", base + s.c.PSYCHIC, bank) < 1 then return true end
    return #createTrainerDiscardList(s, actor) == 0
  end)
  self:register("Scavenge_PlayerSelectEnergyEffect",
    selectArenaEnergy(self.c.TYPE_ENERGY_PSYCHIC, "energyDeckIndex"))
  self:register("Scavenge_PlayerSelectTrainerEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local trainers = createTrainerDiscardList(s, actor)
    local deckIndex, err = s:_selection(context, "discardTrainer", "selectDiscardCard",
      { trainer = true, cards = trainers })
    if deckIndex == nil then return nil, err end
    local valid = false
    for _, v in ipairs(trainers) do if v == deckIndex then valid = true break end end
    if not valid then return nil, "invalid_selection:discardTrainer" end
    s.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
    s.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", deckIndex)
    return false
  end)
  self:register("Scavenge_AISelectEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local energies = createFilteredArenaEnergyList(s, actor, s.c.TYPE_ENERGY_PSYCHIC)
    if #energies < 1 then return nil, "ai_selection_missing_scavenge_energy" end
    local trainers = createTrainerDiscardList(s, actor)
    if #trainers < 1 then return nil, "ai_selection_missing_scavenge_trainer" end
    s.memory:writeSymbol8("hTemp_ffa0", energies[1])
    s.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", trainers[1])
    return false
  end)
  self:register("Scavenge_DiscardEffect", discardTempEnergy)
  self:register("Scavenge_AddToHandEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local deckIndex = s.memory:readSymbol8("hTempPlayAreaLocation_ffa1")
    actor.duelOps:moveDiscardPileCardToHand(deckIndex)
    actor.duelOps:addCardToHand(deckIndex)
    return false
  end)

  -- Wildfire. Player selection stores only a count; discard order is rebuilt
  -- from attached Fire Energy in source deck-index order. AI always stores 0.
  self:register("Wildfire_CheckEnergy", checkArenaEnergy(self.c.TYPE_ENERGY_FIRE))
  self:register("Wildfire_PlayerSelectEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local fire = createFilteredArenaEnergyList(s, actor, s.c.TYPE_ENERGY_FIRE)
    local selected, err = s:_selectionList(context, "wildfireFireEnergies",
      "selectAttachedEnergies", { cards = fire, type = s.c.TYPE_ENERGY_FIRE }, 0, #fire)
    if selected == nil then return nil, err end
    local allowed = {}
    for _, v in ipairs(fire) do allowed[v] = true end
    for _, v in ipairs(selected) do
      if not allowed[v] then return nil, "invalid_selection:wildfireFireEnergies" end
    end
    s.memory:writeSymbol8("hTemp_ffa0", #selected)
    return #selected == 0
  end)
  self:register("Wildfire_AISelectEffect", function(s)
    local base, bank = s.memory:address("hTempList")
    s.memory:write8("hram", base, 0, bank)
    return false
  end)
  self:register("Wildfire_DiscardEnergyEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local fire = createFilteredArenaEnergyList(s, actor, s.c.TYPE_ENERGY_FIRE)
    local count = math.min(s.memory:readSymbol8("hTemp_ffa0"), #fire)
    for i = 1, count do actor.duelOps:putCardInDiscardPile(fire[i]) end
    return false
  end)
  self:register("Wildfire_DiscardDeckEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local requested = s.memory:readSymbol8("hTemp_ffa0")
    actor.duelVars:swapTurn()
    local remaining = s.c.DECK_SIZE - actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)
    local count = math.min(requested, math.max(0, remaining))
    for _ = 1, count do
      local deckIndex, carry = actor.duelOps:drawCardFromDeck()
      if not carry then actor.duelOps:putCardInDiscardPile(deckIndex) end
    end
    actor.duelVars:swapTurn()
    return false
  end)

  -- Energy Removal Trainer: choose a Pokemon and an attached Energy on the
  -- opponent's Play Area. The host supplies both selections explicitly.
  self:register("EnergyRemoval_EnergyCheck", function(s, context)
    local actor = context.playerActions
    if not actor then return nil, "effect_context_missing_player_actions" end
    actor.duelVars:swapTurn()
    local _, carry = actor.duelOps:checkIfThereAreAnyEnergyCardsAttached()
    actor.duelVars:swapTurn()
    return carry
  end)
  self:register("EnergyRemoval_PlayerSelection", function(s, context)
    local actor = context.playerActions
    if not actor then return nil, "effect_context_missing_player_actions" end
    local slot, err = s:_selection(context, "opponentPlayArea", "selectOpponentPlayArea", { nonTurn = true })
    if slot == nil then return nil, err end
    actor.duelVars:swapTurn()
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    local valid = type(slot) == "number" and slot >= s.c.PLAY_AREA_ARENA and slot < count
      and actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot) ~= 0xff
    actor.duelVars:swapTurn()
    if not valid then return nil, "invalid_selection:opponentPlayArea" end
    local deckIndex, energyErr = s:_selectAttachedEnergy(context, actor, true, slot,
      "opponentEnergyDeckIndex", nil)
    if deckIndex == nil then return nil, energyErr end
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    s.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", deckIndex)
    return false
  end)
  self:register("EnergyRemoval_DiscardEffect", function(s, context)
    local actor = context.playerActions
    if not actor then return nil, "effect_context_missing_player_actions" end
    actor.duelVars:swapTurn()
    actor.duelOps:putCardInDiscardPile(s.memory:readSymbol8("hTempPlayAreaLocation_ffa1"))
    actor.duelVars:swapTurn()
    return false
  end)

  -- Selectable Bench damage families share DealDamageToPlayAreaPokemon::.
  local function selectOpponentBenchOrNone(s, context, key)
    local combat = context.combat
    if not combat then return nil, "effect_context_missing_combat" end
    if not s:_hasBench(combat, true) then
      s.memory:writeSymbol8("hTemp_ffa0", 0xff)
      return false
    end
    local slot, err = s:_selectBench(context, combat, true, key or "opponentBench")
    if slot == nil then return nil, err end
    s.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", slot)
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    return false
  end
  local function damageSelectedBench(amount)
    return function(s, context)
      local combat = context.combat
      if not combat then return nil, "effect_context_missing_combat" end
      local slot = s.memory:readSymbol8("hTemp_ffa0")
      if slot == 0xff then return false end
      local damage, err = combat:dealDamageToPlayAreaPokemon(slot, amount, true)
      if damage == nil then return nil, err end
      return false
    end
  end
  self:register("StretchKick_CheckBench", function(s, context)
    local combat = context.combat
    if not combat then return nil, "effect_context_missing_combat" end
    return not s:_hasBench(combat, true)
  end)
  self:register("StretchKick_PlayerSelectEffect", selectOpponentBenchOrNone)
  self:register("StretchKick_BenchDamageEffect", damageSelectedBench(20))
  self:register("Spark_PlayerSelectEffect", selectOpponentBenchOrNone)
  self:register("Spark_BenchDamageEffect", damageSelectedBench(10))
  self:register("GengarDarkMind_PlayerSelectEffect", selectOpponentBenchOrNone)
  self:register("GengarDarkMind_DamageBenchEffect", damageSelectedBench(10))
  self:register("HypnoDarkMind_PlayerSelectEffect", selectOpponentBenchOrNone)
  self:register("HypnoDarkMind_DamageBenchEffect", damageSelectedBench(10))

  -- Meowth/Persian's Cat Punch and Slicing Wind: PickRandomPlayAreaCard on
  -- the opponent's side (Random(count), no self-exclusion or re-roll, unlike
  -- the own/opponent-coin-pick RandomlyDamagePlayAreaPokemon primitive used
  -- by BigThunder/MagneticStorm), then straight into DealDamageToPlayAreaPokemon.
  local function damageRandomOpponentPlayAreaPokemon(amount, animation)
    return function(s, context)
      local combat = context.combat
      if not combat then return nil, "effect_context_missing_combat" end
      local count = combat.duelVars:getNonTurn(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
      local slot = s.setup.rng:random(count)
      s.memory:writeSymbol8("wLoadedAttackAnimation", animation)
      local damage, err = combat:dealDamageToPlayAreaPokemon(slot, amount, true)
      if damage == nil then return nil, err end
      return false
    end
  end
  self:register("CatPunchEffect",
    damageRandomOpponentPlayAreaPokemon(20, self.c.ATK_ANIM_CAT_PUNCH_PLAY_AREA))
  self:register("SlicingWindEffect",
    damageRandomOpponentPlayAreaPokemon(30, self.c.ATK_ANIM_BENCH_HIT))

  -- Mew/Voltorb's Psywave: damage is 10x however many Energy cards are
  -- attached to the Defending Pokemon's Arena card. GetEnergyAttachedMulti
  -- plierDamage swaps to the defender, counts, swaps back, and writes wDamage
  -- directly -- unlike SetDefiniteDamage, it does not touch the AI damage
  -- hint fields (the real command list has no separate AI_EFFECT entry).
  self:register("PsywaveEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelVars:swapTurn()
    local count = actor.duelOps:countNumberOfEnergyCardsAttached(s.c.PLAY_AREA_ARENA)
    actor.duelVars:swapTurn()
    s:_writeWord("wDamage", count * 10)
    return false
  end)

  -- NidoranF/NidoranM's Boyfriends: +20 damage for every Nidoking in the
  -- attacker's own Play Area (scans DUELVARS_ARENA_CARD across the play
  -- area the same way _playAreaDamage's callers do, rather than
  -- countCardIDInLocation's single-slot bitmask match).
  self:register("BoyfriendsEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    local nidokingCount = 0
    for slot = 0, count - 1 do
      local deckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot)
      if actor.cardData:getCardIDFromDeckIndex(deckIndex) == s.c.NIDOKING then
        nidokingCount = nidokingCount + 1
      end
    end
    return s:_addToDamage(nidokingCount * 20)
  end)

  -- Articuno's Ice Breath: 0 printed damage from the normal attack
  -- pipeline, plus a separate 40 damage to a random opponent Play Area
  -- Pokemon -- the exact same PickRandomPlayAreaCard/DealDamageToPlayArea
  -- Pokemon_RegularAnim shape as CatPunch/SlicingWind above.
  self:register("IceBreath_ZeroDamage", function(s)
    return s:_setDefiniteDamage(0)
  end)
  self:register("IceBreath_RandomPokemonDamageEffect",
    damageRandomOpponentPlayAreaPokemon(40, self.c.ATK_ANIM_BENCH_HIT))

  -- Electrode's Chain Lightning: fixed 10 damage, then an extra 10 to
  -- every Play Area Pokemon -- both sides, arena included -- that shares
  -- the Defending Pokemon's color (skipped entirely if the Defending
  -- Pokemon is Colorless). Reuses the already-registered
  -- Combat:dealDamageToPlayAreaPokemon and Status:getPlayAreaCardColor.
  self:register("ChainLightningEffect", function(s, context)
    local combat = context.combat
    if not combat then return nil, "effect_context_missing_combat" end
    s:_setDefiniteDamage(10)

    combat.duelVars:swapTurn()
    local defenderColor = s.status:getPlayAreaCardColor(s.c.PLAY_AREA_ARENA)
    combat.duelVars:swapTurn()
    if defenderColor == s.c.COLORLESS then return false end

    local function damageSameColorBench(isDamageToSelf)
      local count = combat.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
      for slot = s.c.PLAY_AREA_ARENA, count - 1 do
        if s.status:getPlayAreaCardColor(slot) == defenderColor then
          local damage, err = combat:dealDamageToPlayAreaPokemon(slot, 10, false,
            { isDamageToSelf = isDamageToSelf })
          if damage == nil then return nil, err end
        end
      end
      return true
    end

    combat.duelVars:swapTurn()
    local ok, err = damageSameColorBench(false)
    combat.duelVars:swapTurn()
    if ok == nil then return nil, err end

    local ok2, err2 = damageSameColorBench(true)
    if ok2 == nil then return nil, err2 end
    return false
  end)

  -- Pidgeotto's Hurricane: unless the attack was unaffected or the
  -- Defending Pokemon was already KO'd, returns the Defending Pokemon and
  -- every card attached to it (Energy, Trainers) to the opponent's hand,
  -- then clears the Arena slot outright -- deliberately not shifting the
  -- Bench or touching the play area count, matching the real ASM, which
  -- leaves that to whatever forced-switch flow follows.
  self:register("HurricaneEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if s.status:checkNoDamageOrEffect() then return false end
    if actor.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD_HP) == 0 then return false end

    actor.duelVars:swapTurn()
    for deckIndex = 0, s.c.DECK_SIZE - 1 do
      if actor.duelVars:get(deckIndex) == s.c.CARD_LOCATION_ARENA then
        actor.duelOps:addCardToHand(deckIndex)
      end
    end
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD, 0xff)
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_HP, 0)
    actor.duelVars:swapTurn()
    return false
  end)

  -- Ninetales' Mix Up: sorts the opponent's Hand by card ID, moves every
  -- Pokemon card found there back into the Deck, always reshuffles the
  -- Deck and rebuilds the Deck list (RNG parity, matching the real ASM's
  -- unconditional ShuffleCardsInDeck/CreateDeckCardList even when no cards
  -- moved), then -- only if any cards did move -- draws back exactly that
  -- many Pokemon cards from the freshly shuffled Deck.
  self:register("MixUpEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelVars:swapTurn()

    local hand = actor.duelOps:createHandCardList()
    actor.duelOps:sortCardsInDuelTempListByID()
    local base, bank = actor.memory:address("wDuelTempList")

    local movedToDeck = 0
    for i = 0, #hand - 1 do
      local deckIndex = actor.memory:read8("wram", base + i, bank)
      local cardId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
      local row = actor.cardData:get(cardId)
      if row and row.type < s.c.TYPE_ENERGY then
        movedToDeck = movedToDeck + 1
        actor.duelOps:removeCardFromHand(deckIndex)
        actor.duelOps:returnCardToDeck(deckIndex)
      end
    end

    actor.duelOps:shuffleDeck()
    local deck = actor.duelOps:createDeckCardList()
    if movedToDeck > 0 then
      local remaining = movedToDeck
      local i = 0
      while remaining > 0 and i < #deck do
        local deckIndex = actor.memory:read8("wram", base + i, bank)
        i = i + 1
        local cardId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
        local row = actor.cardData:get(cardId)
        if row and row.type < s.c.TYPE_ENERGY then
          remaining = remaining - 1
          actor.duelOps:searchCardInDeckAndAddToHand(deckIndex)
          actor.duelOps:addCardToHand(deckIndex)
        end
      end
    end

    actor.duelVars:swapTurn()
    return false
  end)

  -- Pidgeot's Gale: switches the Defending Pokemon to a random Bench slot
  -- (unless the attack was unaffected), then always switches the
  -- Attacking Pokemon to a random Bench slot too. Shares
  -- Combat:_applyNoDamageOrEffectPrevention's Status:checkNoDamageOrEffect
  -- and DuelOps:swapArenaWithBenchPokemon with the existing forcedSwitch
  -- Effect helper, but keeps its own body since the real ASM's check
  -- order (prevented, then Destiny Bond, then the switch itself) differs
  -- from forcedSwitchEffect's (Destiny Bond, then prevented).
  local function switchToRandomBenchPokemon(s, actor)
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    if count < 2 then return true end
    local benchSlot = s.setup.rng:random(count - 1) + 1
    actor.duelOps:swapArenaWithBenchPokemon(benchSlot)
    return false
  end
  self:register("Gale_LoadAnimation", function(s)
    s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_GALE)
    return false
  end)
  self:register("Gale_SwitchEffect", function(s, context)
    local combat = context.combat
    if not combat then return nil, "effect_context_missing_combat" end
    if not s.status:checkNoDamageOrEffect() then
      if combat.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD_HP) == 0 then
        combat.status:handleDestinyBondSubstatus()
      end
      combat.duelVars:swapTurn()
      local noBench = switchToRandomBenchPokemon(s, combat)
      if not noBench then s:_writeWord("wDealtDamage", 0) end
      combat.duelVars:swapTurn()
    end
    switchToRandomBenchPokemon(s, combat)
    return false
  end)

  -- Wail: fails only if BOTH players' Benches are already full; otherwise
  -- fills each player's Bench, opponent first (matching the source's
  -- SwapTurn/.FillBench/SwapTurn/.FillBench order for RNG parity), with
  -- Basic Pokemon shuffled out of that player's own Deck.
  self:register("Wail_BenchCheck", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) < s.c.MAX_PLAY_AREA_POKEMON then
      return false
    end
    return actor.duelVars:getNonTurn(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) >= s.c.MAX_PLAY_AREA_POKEMON
  end)
  self:register("Wail_FillBenchEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end

    local function fillBench(a)
      local deck, empty = a.duelOps:createDeckCardList()
      if empty then return end
      local base, bank = a.memory:address("wDuelTempList")
      a.duelOps.rng:shuffleCards(base, #deck)
      local count = a.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
      for i = 0, #deck - 1 do
        if count >= s.c.MAX_PLAY_AREA_POKEMON then break end
        local deckIndex = a.memory:read8("wram", base + i, bank)
        local cardId = a.cardData:getCardIDFromDeckIndex(deckIndex)
        local row = a.cardData:get(cardId)
        if row and row.type < s.c.TYPE_ENERGY and row.stage == s.c.BASIC then
          a.duelOps:searchCardInDeckAndAddToHand(deckIndex)
          a.duelOps:addCardToHand(deckIndex)
          a.duelOps:putHandPokemonCardInPlayArea(deckIndex)
          count = count + 1
        end
      end
      a.duelOps:shuffleDeck()
    end

    actor.duelVars:swapTurn()
    fillBench(actor)
    actor.duelVars:swapTurn()
    fillBench(actor)
    return false
  end)

  -- Jigglypuff's Friendship Song: fails if the attacker's own Bench is
  -- already full; on heads, shuffles the attacker's own Deck and adds the
  -- first Basic Pokemon found to the Bench (the same shuffle-then-scan
  -- shape as Wail_FillBenchEffect's fillBench, just stopping at the first
  -- match rather than filling to capacity). The animation plays either
  -- way on heads, whether or not a Basic Pokemon turned up.
  self:register("FriendshipSong_BenchCheck", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    return actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) >= s.c.MAX_PLAY_AREA_POKEMON
  end)
  local function pickRandomBasicCardFromDeck(s, a, excludeCardId)
    local deck, empty = a.duelOps:createDeckCardList()
    if empty then return nil end
    local base, bank = a.memory:address("wDuelTempList")
    a.duelOps.rng:shuffleCards(base, #deck)
    for i = 0, #deck - 1 do
      local deckIndex = a.memory:read8("wram", base + i, bank)
      local cardId = a.cardData:getCardIDFromDeckIndex(deckIndex)
      local row = a.cardData:get(cardId)
      if row and row.type < s.c.TYPE_ENERGY and row.stage == s.c.BASIC
          and cardId ~= excludeCardId then
        return deckIndex
      end
    end
    return nil
  end
  self:register("FriendshipSong_AddToBench50PercentEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    if result == s.c.TAILS then return false end

    s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_FRIENDSHIP_SONG)
    local deckIndex = pickRandomBasicCardFromDeck(s, actor)
    if deckIndex == nil then
      actor.duelOps:shuffleDeck()
      return false
    end
    actor.duelOps:searchCardInDeckAndAddToHand(deckIndex)
    actor.duelOps:addCardToHand(deckIndex)
    actor.duelOps:putHandPokemonCardInPlayArea(deckIndex)
    actor.duelOps:shuffleDeck()
    return false
  end)

  -- Ditto's Morph: shuffles the attacker's own Deck (excluding other
  -- Dittos) for a random Basic Pokemon, then transforms the Attacking
  -- Pokemon into it -- unlike Devolution Beam's slot-content swap, this
  -- permanently overwrites the arena's OWN deck slot's card-identity
  -- entry via the new CardData:setCardIDForDeckIndex, leaving the picked
  -- deck card itself untouched and still in the deck. If the Attacking
  -- Pokemon isn't already Basic (e.g. when copied via Metronome from an
  -- evolved Pokemon), first discards its pre-evolution card and resets
  -- its own stage to Basic, reusing the Devolution Spray/Beam family's
  -- cardOneStageBelow helper.
  self:register("MorphEffect", function(s, context)
    local actor = s:_actor(context)
    if not actor then return nil, "effect_context_missing_actor" end

    local pickedDeckIndex = pickRandomBasicCardFromDeck(s, actor, s.c.DITTO)
    if pickedDeckIndex == nil then return false end

    local ownStage = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_STAGE)
    if ownStage ~= s.c.BASIC then
      local lower, lowerErr = cardOneStageBelow(s, actor, s.c.PLAY_AREA_ARENA)
      if lower == nil then return nil, lowerErr end
      actor.duelOps:putCardInDiscardPile(lower)
      actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_STAGE, s.c.BASIC)
    end

    local newCardId = actor.cardData:getCardIDFromDeckIndex(pickedDeckIndex)
    local newRow = actor.cardData:get(newCardId)
    if not newRow then return nil, "missing_card_data" end

    local ownDeckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD)
    actor.cardData:setCardIDForDeckIndex(ownDeckIndex, newCardId)
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_HP, newRow.hp)
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_CHANGED_TYPE, 0)
    actor.duelOps:clearAllStatusConditions()
    return false
  end)

  self:register("Blizzard_BenchDamage50PercentEffect", function(s)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    s.memory:writeSymbol8("hTemp_ffa0", result)
    return false
  end)
  self:register("Blizzard_BenchDamageEffect", function(s, context)
    local combat = context.combat
    if not combat then return nil, "effect_context_missing_combat" end
    local heads = s.memory:readSymbol8("hTemp_ffa0") == s.c.HEADS
    local ok, err = combat:dealDamageToAllBenchedPokemon(10, heads,
      { isDamageToSelf = not heads })
    if ok == nil then return nil, err end
    return false
  end)

  -- Selfdestruct family (Weezing/Golem/Magnemite/Magneton x2): recoil to
  -- self, then the same bench-damage amount to every Benched Pokemon on
  -- BOTH sides -- own bench first (no swap), then the opponent's (source
  -- brackets that half with SwapTurn/SwapTurn, matching targetNonTurn=true
  -- here). Recoil/bench amounts read straight off each card's real body.
  local function registerSelfdestruct(name, recoilAmount, benchAmount)
    self:register(name, function(s, context)
      local combat = context.combat
      if not combat then return nil, "effect_context_missing_combat" end
      combat:dealRecoilDamageToSelf(recoilAmount)
      local ok, err = combat:dealDamageToAllBenchedPokemon(benchAmount, false, { isDamageToSelf = true })
      if ok == nil then return nil, err end
      ok, err = combat:dealDamageToAllBenchedPokemon(benchAmount, true, { isDamageToSelf = false })
      if ok == nil then return nil, err end
      return false
    end)
  end
  registerSelfdestruct("WeezingSelfdestructEffect", 60, 10)
  registerSelfdestruct("GolemSelfdestructEffect", 100, 20)
  registerSelfdestruct("MagnemiteSelfdestructEffect", 40, 10)
  registerSelfdestruct("MagnetonLv28SelfdestructEffect", 80, 20)
  registerSelfdestruct("MagnetonLv35SelfdestructEffect", 100, 20)

  -- Dugtrio/Onix: Earthquake -- 10 damage to every one of the ATTACKER's
  -- own Benched Pokemon only (no recoil, no opponent's bench, unlike the
  -- Selfdestruct family above which shares the same underlying primitive).
  self:register("EarthquakeEffect", function(s, context)
    local combat = context.combat
    if not combat then return nil, "effect_context_missing_combat" end
    local ok, err = combat:dealDamageToAllBenchedPokemon(10, false, { isDamageToSelf = true })
    if ok == nil then return nil, err end
    return false
  end)

  -- Triggered Power primitives. INITIAL_EFFECT_1 stubs intentionally carry so
  -- the powers cannot be used as ordinary attacks, while the trigger phase is
  -- independently executable by the generic dispatcher.
  local function triggeredOnly() return true end
  self:register("Quickfreeze_InitialEffect", triggeredOnly)
  self:register("Firegiver_InitialEffect", triggeredOnly)
  self:register("HealingWind_InitialEffect", triggeredOnly)
  self:register("PealOfThunder_InitialEffect", triggeredOnly)
  self:register("TransparencyEffect", triggeredOnly)
  self:register("PrehistoricPowerEffect", triggeredOnly)
  self:register("ClairvoyanceEffect", triggeredOnly)
  self:register("InvisibleWallEffect", triggeredOnly)
  self:register("NeutralizingShieldEffect", triggeredOnly)
  self:register("KabutoArmorEffect", triggeredOnly)
  self:register("ThickSkinnedEffect", triggeredOnly)
  self:register("ToxicGasEffect", triggeredOnly)
  self:register("StrikesBackEffect", triggeredOnly)
  self:register("RetreatAidEffect", triggeredOnly)
  self:register("Quickfreeze_Paralysis50PercentEffect", function(s)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    if result == s.c.TAILS then return s:_setWasUnsuccessful() end
    s.status:queueStatusCondition(s.c.PSN_DBLPSN, s.c.PARALYZED)
    s.status:applyStatusConditionQueue()
    return false
  end)


  self:register("Firegiver_AddToHandEffect", function(s, context)
    local combat = context.combat
    if not combat then return nil, "effect_context_missing_combat" end
    local energies = {}
    for deckIndex = 0, s.c.DECK_SIZE - 1 do
      if combat.duelVars:get(deckIndex) == s.c.CARD_LOCATION_DECK then
        local cardId = combat.cardData:getCardIDFromDeckIndex(deckIndex)
        local row = combat.cardData:get(cardId)
        if row and row.type == s.c.TYPE_ENERGY_FIRE then energies[#energies + 1] = deckIndex end
      end
    end
    if #energies == 0 then
      combat.duelOps:shuffleDeck()
      return false
    end
    local count = math.min(combat.duelOps.rng:random(4) + 1, #energies)
    s.memory:writeSymbol8("hCurSelectionItem", count)
    for i = 1, count do
      combat.duelOps:searchCardInDeckAndAddToHand(energies[i])
      combat.duelOps:addCardToHand(energies[i])
    end
    combat.duelOps:shuffleDeck()
    s:_event("firegiver", { count = count })
    return false
  end)

  self:register("HealingWind_PlayAreaHealEffect", function(s, context)
    local combat = context.combat
    if not combat then return nil, "effect_context_missing_combat" end
    local count = combat.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    for slot = s.c.PLAY_AREA_ARENA, count - 1 do
      local damage = s:_playAreaDamage(combat, slot)
      if damage and damage > 0 then
        local heal = math.min(20, damage)
        local hpOffset = s.c.DUELVARS_ARENA_CARD_HP + slot
        combat.duelVars:set(hpOffset, combat.duelVars:get(hpOffset) + heal)
        s:_event("healing_wind", { slot = slot, amount = heal })
      end
    end
    return false
  end)

  self:register("PealOfThunder_RandomlyDamageEffect", function(s, context)
    local combat = context.combat
    if not combat then return nil, "effect_context_missing_combat" end
    local failed, exchangeErr = combat.setup:exchangeRNG()
    if failed then return nil, exchangeErr end
    local excluded = context.powerSlot or s.memory:readSymbol8("hTempPlayAreaLocation_ff9d")
    while true do
      local targetNonTurn = bit.band(combat.duelOps.rng:updateSources(), 1) ~= 0
      if targetNonTurn then combat.duelVars:swapTurn() end
      local count = combat.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
      if targetNonTurn then combat.duelVars:swapTurn() end
      if count > 0 then
        local slot = combat.duelOps.rng:random(count)
        if targetNonTurn or slot ~= excluded then
          local damage, err = combat:dealDamageToPlayAreaPokemon(slot, 30, targetNonTurn,
            { isDamageToSelf = not targetNonTurn })
          if damage == nil then return nil, err end
          local _, koErr = combat.knockouts:handlePendingResolution()
          if koErr then return nil, koErr end
          return false
        end
      end
    end
  end)


  -- Passive Energy Powers. Their command-table stubs carry when invoked as
  -- ordinary attacks; their actual behavior is consumed by Energy attachment
  -- and attack-cost accounting.
  self:register("RainDanceEffect", function() return true end)
  self:register("EnergyBurnEffect", function() return true end)

  local function state(context)
    context.effectState = context.effectState or {}
    return context.effectState
  end
  local function actorForTrainer(context)
    return context.playerActions or context.combat
  end
  local function basicEnergyInDiscard(s, actor)
    local cards = s:_cardsAtLocation(actor, s.c.CARD_LOCATION_DISCARD_PILE,
      function(deckIndex) return s:_isBasicEnergy(actor, deckIndex) end)
    return cards
  end
  local function trainerInDiscard(s, actor)
    return s:_cardsAtLocation(actor, s.c.CARD_LOCATION_DISCARD_PILE, function(deckIndex)
      local cardId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
      local row = actor.cardData:get(cardId)
      return row ~= nil and row.type == s.c.TYPE_TRAINER
    end)
  end
  local function selectTwoHandCards(s, context, key)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local cards, err = s:_selectionList(context, key or "handDiscards",
      "selectHandCards", { count = 2, exclude = s.memory:readSymbol8("hTempCardIndex_ff9f") }, 2, 2)
    if not cards then return nil, err end
    local trainer = s.memory:readSymbol8("hTempCardIndex_ff9f")
    for _, deckIndex in ipairs(cards) do
      if not s:_validateHandSelection(actor, deckIndex, trainer) then
        return nil, "invalid_selection:" .. (key or "handDiscards")
      end
    end
    return cards
  end
  local function discardHandCards(actor, cards)
    for _, deckIndex in ipairs(cards or {}) do
      actor.duelOps:removeCardFromHand(deckIndex)
      actor.duelOps:putCardInDiscardPile(deckIndex)
    end
  end

  -- Energy Search: deck can be nonempty yet contain no Basic Energy; in that
  -- source case hTemp_ffa0 remains $ff and the deck is simply shuffled.
  self:register("EnergySearch_DeckCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    return actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK) >= s.c.DECK_SIZE
  end)
  self:register("EnergySearch_PlayerSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local matches = s:_cardsAtLocation(actor, s.c.CARD_LOCATION_DECK,
      function(deckIndex) return s:_isBasicEnergy(actor, deckIndex) end)
    if #matches == 0 then
      s.memory:writeSymbol8("hTemp_ffa0", 0xff)
      state(context).deckBasicEnergy = 0xff
      return false
    end
    local deckIndex, err = s:_selection(context, "deckBasicEnergy", "selectDeckCard",
      { basicEnergy = true })
    if deckIndex == nil then return nil, err end
    if actor.duelVars:get(deckIndex) ~= s.c.CARD_LOCATION_DECK
        or not s:_isBasicEnergy(actor, deckIndex) then
      return nil, "invalid_selection:deckBasicEnergy"
    end
    s.memory:writeSymbol8("hTemp_ffa0", deckIndex)
    state(context).deckBasicEnergy = deckIndex
    return false
  end)
  self:register("EnergySearch_AddToHandEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local deckIndex = state(context).deckBasicEnergy
    if deckIndex == nil then deckIndex = s.memory:readSymbol8("hTemp_ffa0") end
    if deckIndex ~= 0xff then
      actor.duelOps:searchCardInDeckAndAddToHand(deckIndex)
      actor.duelOps:addCardToHand(deckIndex)
    end
    actor.duelOps:shuffleDeck()
    return false
  end)

  -- Energy Retrieval: discard one other hand card, then recover up to two Basic
  -- Energy cards chosen from the Discard Pile.
  self:register("EnergyRetrieval_HandEnergyCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND) < 2 then return true end
    return #basicEnergyInDiscard(s, actor) == 0
  end)
  self:register("EnergyRetrieval_PlayerHandSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local deckIndex, err = s:_selection(context, "handDiscard", "selectHandCard",
      { exclude = s.memory:readSymbol8("hTempCardIndex_ff9f") })
    if deckIndex == nil then return nil, err end
    if not s:_validateHandSelection(actor, deckIndex, s.memory:readSymbol8("hTempCardIndex_ff9f")) then
      return nil, "invalid_selection:handDiscard"
    end
    state(context).handDiscards = { deckIndex }
    return false
  end)
  self:register("EnergyRetrieval_PlayerDiscardPileSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local cards, err = s:_selectionList(context, "discardBasicEnergies",
      "selectDiscardCards", { basicEnergy = true, max = 2 }, 0, 2)
    if not cards then return nil, err end
    for _, deckIndex in ipairs(cards) do
      if actor.duelVars:get(deckIndex) ~= s.c.CARD_LOCATION_DISCARD_PILE
          or not s:_isBasicEnergy(actor, deckIndex) then
        return nil, "invalid_selection:discardBasicEnergies"
      end
    end
    state(context).discardBasicEnergies = cards
    return false
  end)
  self:register("EnergyRetrieval_DiscardAndAddToHandEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local st = state(context)
    discardHandCards(actor, st.handDiscards)
    for _, deckIndex in ipairs(st.discardBasicEnergies or {}) do
      actor.duelOps:moveDiscardPileCardToHand(deckIndex)
      actor.duelOps:addCardToHand(deckIndex)
    end
    return false
  end)

  -- Computer Search: discard exactly two other hand cards and search any one
  -- card from the remaining deck; the source does not permit cancelling the
  -- final deck selection.
  self:register("ComputerSearch_HandDeckCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND) < 3 then return true end
    return actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK) >= s.c.DECK_SIZE
  end)
  self:register("ComputerSearch_PlayerDiscardHandSelection", function(s, context)
    local cards, err = selectTwoHandCards(s, context, "handDiscards")
    if not cards then return nil, err end
    state(context).handDiscards = cards
    return false
  end)
  self:register("ComputerSearch_PlayerDeckSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local deckIndex, err = s:_selection(context, "deckCard", "selectDeckCard", {})
    if deckIndex == nil then return nil, err end
    if actor.duelVars:get(deckIndex) ~= s.c.CARD_LOCATION_DECK then
      return nil, "invalid_selection:deckCard"
    end
    state(context).deckCard = deckIndex
    return false
  end)
  self:register("ComputerSearch_DiscardAddToHandEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local st = state(context)
    discardHandCards(actor, st.handDiscards)
    local deckIndex = st.deckCard
    actor.duelOps:searchCardInDeckAndAddToHand(deckIndex)
    actor.duelOps:addCardToHand(deckIndex)
    actor.duelOps:shuffleDeck()
    return false
  end)

  -- Item Finder: same two-card hand cost as Computer Search, but the selected
  -- reward must be a Trainer already in the Discard Pile.
  self:register("ItemFinder_HandDiscardPileCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND) < 3 then return true end
    return #trainerInDiscard(s, actor) == 0
  end)
  self:register("ItemFinder_PlayerSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local cards, err = selectTwoHandCards(s, context, "handDiscards")
    if not cards then return nil, err end
    local trainer, trainerErr = s:_selection(context, "discardTrainer",
      "selectDiscardCard", { trainer = true })
    if trainer == nil then return nil, trainerErr end
    if actor.duelVars:get(trainer) ~= s.c.CARD_LOCATION_DISCARD_PILE then
      return nil, "invalid_selection:discardTrainer"
    end
    local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(trainer))
    if not row or row.type ~= s.c.TYPE_TRAINER then return nil, "invalid_selection:discardTrainer" end
    local st = state(context)
    st.handDiscards, st.discardTrainer = cards, trainer
    return false
  end)
  self:register("ItemFinder_DiscardAddToHandEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local st = state(context)
    discardHandCards(actor, st.handDiscards)
    actor.duelOps:moveDiscardPileCardToHand(st.discardTrainer)
    actor.duelOps:addCardToHand(st.discardTrainer)
    return false
  end)

  -- Super Energy Retrieval expands the same pattern to two hand discards and
  -- up to four Basic Energy cards from the Discard Pile.
  self:register("SuperEnergyRetrieval_HandEnergyCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND) < 3 then return true end
    return #basicEnergyInDiscard(s, actor) == 0
  end)
  self:register("SuperEnergyRetrieval_PlayerHandSelection", function(s, context)
    local cards, err = selectTwoHandCards(s, context, "handDiscards")
    if not cards then return nil, err end
    state(context).handDiscards = cards
    return false
  end)
  self:register("SuperEnergyRetrieval_PlayerDiscardPileSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local cards, err = s:_selectionList(context, "discardBasicEnergies",
      "selectDiscardCards", { basicEnergy = true, max = 4 }, 0, 4)
    if not cards then return nil, err end
    for _, deckIndex in ipairs(cards) do
      if actor.duelVars:get(deckIndex) ~= s.c.CARD_LOCATION_DISCARD_PILE
          or not s:_isBasicEnergy(actor, deckIndex) then
        return nil, "invalid_selection:discardBasicEnergies"
      end
    end
    state(context).discardBasicEnergies = cards
    return false
  end)
  self:register("SuperEnergyRetrieval_DiscardAndAddToHandEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local st = state(context)
    discardHandCards(actor, st.handDiscards)
    for _, deckIndex in ipairs(st.discardBasicEnergies or {}) do
      actor.duelOps:moveDiscardPileCardToHand(deckIndex)
      actor.duelOps:addCardToHand(deckIndex)
    end
    return false
  end)

  -- Super Energy Removal: discard one Energy from any of your Pokemon, then up
  -- to two Energy cards attached to one selected opposing Pokemon.
  self:register("SuperEnergyRemoval_EnergyCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local _, ownCarry = actor.duelOps:checkIfThereAreAnyEnergyCardsAttached()
    if ownCarry then return true end
    actor.duelVars:swapTurn()
    local _, oppCarry = actor.duelOps:checkIfThereAreAnyEnergyCardsAttached()
    actor.duelVars:swapTurn()
    return oppCarry
  end)
  self:register("SuperEnergyRemoval_PlayerSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local ownSlot, err = s:_selection(context, "ownPlayArea", "selectPlayArea", { energyRequired = true })
    if ownSlot == nil then return nil, err end
    local ownCount = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    if type(ownSlot) ~= "number" or ownSlot < 0 or ownSlot >= ownCount
        or not s:_hasAttachedEnergy(actor, false, ownSlot, nil) then
      return nil, "invalid_selection:ownPlayArea"
    end
    local ownEnergy, energyErr = s:_selectAttachedEnergy(context, actor, false, ownSlot,
      "ownEnergyDeckIndex", nil)
    if ownEnergy == nil then return nil, energyErr end

    local oppSlot, oppErr = s:_selection(context, "opponentPlayArea",
      "selectOpponentPlayArea", { nonTurn = true, energyRequired = true })
    if oppSlot == nil then return nil, oppErr end
    actor.duelVars:swapTurn()
    local oppCount = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    local oppValid = type(oppSlot) == "number" and oppSlot >= 0 and oppSlot < oppCount
      and actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + oppSlot) ~= 0xff
    actor.duelVars:swapTurn()
    if not oppValid or not s:_hasAttachedEnergy(actor, true, oppSlot, nil) then
      return nil, "invalid_selection:opponentPlayArea"
    end
    local oppEnergies, listErr = s:_selectionList(context, "opponentEnergyDeckIndexes",
      "selectOpponentAttachedEnergies", { nonTurn = true, playArea = oppSlot, max = 2 }, 0, 2)
    if not oppEnergies then return nil, listErr end
    for _, deckIndex in ipairs(oppEnergies) do
      actor.duelVars:swapTurn()
      local expected = bit.bor(s.c.CARD_LOCATION_PLAY_AREA, oppSlot)
      local valid = actor.duelVars:get(deckIndex) == expected
      if valid then
        local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
        valid = row and bit.band(row.type, bit.lshift(1, s.c.TYPE_ENERGY_F)) ~= 0
      end
      actor.duelVars:swapTurn()
      if not valid then return nil, "invalid_selection:opponentEnergyDeckIndexes" end
    end
    local st = state(context)
    st.ownEnergy, st.opponentEnergies, st.ownPlayArea, st.opponentPlayArea =
      ownEnergy, oppEnergies, ownSlot, oppSlot
    return false
  end)
  self:register("SuperEnergyRemoval_DiscardEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local st = state(context)
    actor.duelOps:putCardInDiscardPile(st.ownEnergy)
    actor.duelVars:swapTurn()
    for _, deckIndex in ipairs(st.opponentEnergies or {}) do
      actor.duelOps:putCardInDiscardPile(deckIndex)
    end
    actor.duelVars:swapTurn()
    return false
  end)

  -- Pokemon Trader: choose a Pokemon from hand and one Pokemon from the Deck.
  -- The cartridge temporarily returns the hand Pokemon before deck selection so
  -- that trading it for itself is legal; validation below preserves that case.
  self:register("PokemonTrader_HandDeckCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND) < 2 then return true end
    local trainer = s.memory:readSymbol8("hTempCardIndex_ff9f")
    for deckIndex = 0, s.c.DECK_SIZE - 1 do
      if deckIndex ~= trainer and actor.duelVars:get(deckIndex) == s.c.CARD_LOCATION_HAND then
        local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
        if row and row.type < s.c.TYPE_ENERGY then return false end
      end
    end
    return true
  end)
  self:register("PokemonTrader_PlayerHandSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local deckIndex, err = s:_selection(context, "handPokemon", "selectHandCard",
      { pokemon = true, exclude = s.memory:readSymbol8("hTempCardIndex_ff9f") })
    if deckIndex == nil then return nil, err end
    if not s:_validateHandSelection(actor, deckIndex, s.memory:readSymbol8("hTempCardIndex_ff9f")) then
      return nil, "invalid_selection:handPokemon"
    end
    local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
    if not row or row.type >= s.c.TYPE_ENERGY then return nil, "invalid_selection:handPokemon" end
    state(context).handPokemon = deckIndex
    s.memory:writeSymbol8("hTemp_ffa0", deckIndex)
    return false
  end)
  self:register("PokemonTrader_PlayerDeckSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local chosen, err = s:_selection(context, "deckPokemon", "selectDeckCard", { pokemon = true })
    if chosen == nil then return nil, err end
    local st = state(context)
    local location = actor.duelVars:get(chosen)
    if location ~= s.c.CARD_LOCATION_DECK and chosen ~= st.handPokemon then
      return nil, "invalid_selection:deckPokemon"
    end
    local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(chosen))
    if not row or row.type >= s.c.TYPE_ENERGY then return nil, "invalid_selection:deckPokemon" end
    st.deckPokemon = chosen
    s.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", chosen)
    return false
  end)
  self:register("PokemonTrader_TradeCardsEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local st = state(context)
    actor.duelOps:removeCardFromHand(st.handPokemon)
    actor.duelOps:returnCardToDeck(st.handPokemon)
    actor.duelOps:searchCardInDeckAndAddToHand(st.deckPokemon)
    actor.duelOps:addCardToHand(st.deckPokemon)
    actor.duelOps:shuffleDeck()
    return false
  end)

  -- Pokedex: host provides the desired top-to-bottom order of the current top
  -- min(5, cards-left) deck entries. Source mutation is remove-in-order then
  -- ReturnCardToDeck in reverse order.
  self:register("Pokedex_DeckCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    return actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK) >= s.c.DECK_SIZE
  end)
  self:register("Pokedex_PlayerSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local gone = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)
    local count = math.min(5, s.c.DECK_SIZE - gone)
    local current, expected = {}, {}
    for i = 0, count - 1 do
      local deckIndex = actor.duelVars:get(s.c.DUELVARS_DECK_CARDS + gone + i)
      current[#current + 1] = deckIndex
      expected[deckIndex] = (expected[deckIndex] or 0) + 1
    end
    local order, err = s:_selection(context, "topDeckOrder", "orderDeckCards",
      { cards = current, count = count })
    if order == nil then return nil, err end
    if type(order) ~= "table" or #order ~= count then return nil, "invalid_selection:topDeckOrder" end
    local actual = {}
    for _, deckIndex in ipairs(order) do actual[deckIndex] = (actual[deckIndex] or 0) + 1 end
    for k, v in pairs(expected) do if actual[k] ~= v then return nil, "invalid_selection:topDeckOrder" end end
    for k, v in pairs(actual) do if expected[k] ~= v then return nil, "invalid_selection:topDeckOrder" end end
    state(context).topDeckOrder = order
    return false
  end)
  self:register("Pokedex_OrderDeckCardsEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local order = state(context).topDeckOrder or {}
    for _, deckIndex in ipairs(order) do actor.duelOps:searchCardInDeckAndAddToHand(deckIndex) end
    for i = #order, 1, -1 do actor.duelOps:returnCardToDeck(order[i]) end
    return false
  end)

  -- Maintenance: return two selected hand cards, shuffle, then draw one.
  self:register("Maintenance_HandCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    return actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND) < 3
  end)
  self:register("Maintenance_PlayerSelection", function(s, context)
    local cards, err = selectTwoHandCards(s, context, "handDiscards")
    if not cards then return nil, err end
    state(context).maintenanceCards = cards
    return false
  end)
  self:register("Maintenance_ReturnToDeckAndDrawEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    for _, deckIndex in ipairs(state(context).maintenanceCards or {}) do
      actor.duelOps:removeCardFromHand(deckIndex)
      actor.duelOps:returnCardToDeck(deckIndex)
    end
    actor.duelOps:shuffleDeck()
    local deckIndex, carry = actor.duelOps:drawCardFromDeck()
    if not carry then
      s.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
      actor.duelOps:addCardToHand(deckIndex)
    end
    return false
  end)

  -- Recycle: one coin toss; on heads choose any Discard Pile card and return it
  -- to the top of the deck. Tails stores the source $ff sentinel.
  self:register("Recycle_DiscardPileCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    return actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_CARDS_IN_DISCARD_PILE) < 1
  end)
  self:register("Recycle_PlayerSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local result, tossErr = s.setup:tossCoin()
    if result == nil then return nil, tossErr end
    if result == s.c.TAILS then
      state(context).recycleCard = 0xff
      return false
    end
    local deckIndex, err = s:_selection(context, "discardCard", "selectDiscardCard", {})
    if deckIndex == nil then return nil, err end
    if actor.duelVars:get(deckIndex) ~= s.c.CARD_LOCATION_DISCARD_PILE then
      return nil, "invalid_selection:discardCard"
    end
    state(context).recycleCard = deckIndex
    return false
  end)
  self:register("Recycle_AddToHandEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local deckIndex = state(context).recycleCard
    if deckIndex == nil or deckIndex == 0xff then return false end
    actor.duelOps:moveDiscardPileCardToHand(deckIndex)
    actor.duelOps:returnCardToDeck(deckIndex)
    return false
  end)

  -- Full Heal is state-only once the animation/UI is removed.
  self:register("FullHeal_StatusCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    return actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_STATUS) == 0
  end)
  self:register("FullHeal_ClearStatusEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_STATUS, s.c.NO_STATUS)
    return false
  end)

  -- Poke Ball: heads permits one Pokemon deck selection; tails does nothing.
  self:register("PokeBall_DeckCheck", self.handlers["EnergySearch_DeckCheck"])
  self:register("PokeBall_PlayerSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local result, tossErr = s.setup:tossCoin()
    if result == nil then return nil, tossErr end
    local st = state(context)
    st.pokeBallHeads = result == s.c.HEADS
    if not st.pokeBallHeads then st.pokeBallCard = 0xff; return false end
    local pokemon = s:_cardsAtLocation(actor, s.c.CARD_LOCATION_DECK, function(deckIndex)
      local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
      return row ~= nil and row.type < s.c.TYPE_ENERGY
    end)
    if #pokemon == 0 then st.pokeBallCard = 0xff; return false end
    local deckIndex, err = s:_selection(context, "deckPokemon", "selectDeckCard", { pokemon = true })
    if deckIndex == nil then return nil, err end
    local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
    if actor.duelVars:get(deckIndex) ~= s.c.CARD_LOCATION_DECK
        or not row or row.type >= s.c.TYPE_ENERGY then
      return nil, "invalid_selection:deckPokemon"
    end
    st.pokeBallCard = deckIndex
    return false
  end)
  self:register("PokeBall_AddToHandEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local st = state(context)
    if not st.pokeBallHeads then return false end
    if st.pokeBallCard ~= 0xff then
      actor.duelOps:searchCardInDeckAndAddToHand(st.pokeBallCard)
      actor.duelOps:addCardToHand(st.pokeBallCard)
    end
    actor.duelOps:shuffleDeck()
    return false
  end)

  local function basicPokemonInDiscard(s, actor)
    return s:_cardsAtLocation(actor, s.c.CARD_LOCATION_DISCARD_PILE, function(deckIndex)
      local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
      return row ~= nil and row.type < s.c.TYPE_ENERGY and row.stage == s.c.BASIC
    end)
  end

  -- PlusPower / Defender attach the Trainer card itself rather than discarding
  -- it immediately. PlayTrainerCard's final hand-discard attempt therefore
  -- becomes a no-op, exactly as MoveHandCardToDiscardPile does in the source.
  self:register("PlusPowerEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local trainer = s.memory:readSymbol8("hTempCardIndex_ff9f")
    actor.duelOps:putHandCardInPlayArea(trainer, s.c.PLAY_AREA_ARENA)
    local offset = s.c.DUELVARS_ARENA_CARD_ATTACHED_PLUSPOWER
    actor.duelVars:set(offset, (actor.duelVars:get(offset) + 1) % 0x100)
    return false
  end)
  self:register("Defender_PlayerSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local slot, err = s:_selectPlayArea(context)
    if slot == nil then return nil, err end
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    if type(slot) ~= "number" or slot < 0 or slot >= count
        or actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot) == 0xff then
      return nil, "invalid_selection:play_area"
    end
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    state(context).defenderSlot = slot
    return false
  end)
  self:register("Defender_AttachDefenderEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local slot = state(context).defenderSlot or s.memory:readSymbol8("hTemp_ffa0")
    local trainer = s.memory:readSymbol8("hTempCardIndex_ff9f")
    actor.duelOps:putHandCardInPlayArea(trainer, slot)
    local offset = s.c.DUELVARS_ARENA_CARD_ATTACHED_DEFENDER + slot
    actor.duelVars:set(offset, (actor.duelVars:get(offset) + 1) % 0x100)
    return false
  end)

  -- Mr. Fuji returns a chosen Benched Pokemon and every card sharing that Play
  -- Area location (evolutions, Energy, attached Trainers) to the deck.
  self:register("MrFuji_BenchCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    return actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) < 2
  end)
  self:register("MrFuji_PlayerSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local slot, err = s:_selectBench(context, actor, false, "bench")
    if slot == nil then return nil, err end
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    state(context).mrFujiSlot = slot
    return false
  end)
  self:register("MrFuji_ReturnToDeckEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local slot = state(context).mrFujiSlot or s.memory:readSymbol8("hTemp_ffa0")
    local location = bit.bor(s.c.CARD_LOCATION_PLAY_AREA, slot)
    local cards = s:_cardsAtLocation(actor, location)
    for _, deckIndex in ipairs(cards) do actor.duelOps:returnCardToDeck(deckIndex) end
    actor.duelOps:emptyPlayAreaSlot(slot)
    actor.duelVars:set(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA,
      actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) - 1)
    actor.duelOps:shiftAllPokemonToFirstPlayAreaSlots()
    actor.duelOps:shuffleDeck()
    return false
  end)

  -- Pokemon Center heals every damaged Pokemon and discards only Energy cards
  -- attached to Pokemon that actually had damage counters.
  self:register("PokemonCenter_DamageCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    for slot = 0, count - 1 do
      local damage = s:_playAreaDamage(actor, slot)
      if damage and damage > 0 then return false end
    end
    return true
  end)
  self:register("PokemonCenter_HealDiscardEnergyEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    for slot = 0, count - 1 do
      local damage, maxHP = s:_playAreaDamage(actor, slot)
      if damage and damage > 0 then
        actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_HP + slot, maxHP)
        local energyCount = actor.duelOps:createArenaOrBenchEnergyCardList(slot)
        local base, bank = actor.memory:address("wDuelTempList")
        local energies = {}
        for i = 0, energyCount - 1 do
          energies[#energies + 1] = actor.memory:read8("wram", base + i, bank)
        end
        for _, deckIndex in ipairs(energies) do actor.duelOps:putCardInDiscardPile(deckIndex) end
      end
    end
    return false
  end)

  -- Super Potion heals up to 40 damage counters on one chosen Play Area
  -- Pokemon (any card with damage, not just the Active) and discards one
  -- chosen attached Energy card as its cost. AIPlay_SuperPotion/AIDecide_
  -- SuperPotion_Phase08/Phase11 (trainer_cards.asm) select the target slot
  -- and the Energy to discard; this effect only applies whatever the
  -- decision/selection layer already chose, matching Potion_HealEffect's
  -- split between selection and effect above.
  -- SuperPotion_DamageEnergyCheck:: CheckIfPlayAreaHasAnyDamage and
  -- CheckIfThereAreAnyEnergyCardsAttached are independent whole-play-area
  -- scans in the source (damage on one card, Energy on a different card,
  -- still passes) -- NOT a same-slot requirement. The per-card pairing is
  -- enforced later, during SuperPotion_PlayerSelectEffect's own selection.
  self:register("SuperPotion_DamageEnergyCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    local anyDamage = false
    for slot = 0, count - 1 do
      local damage = s:_playAreaDamage(actor, slot)
      if damage and damage > 0 then anyDamage = true break end
    end
    if not anyDamage then return true end
    local anyEnergy = false
    for slot = 0, count - 1 do
      if actor.duelOps:createArenaOrBenchEnergyCardList(slot) > 0 then anyEnergy = true break end
    end
    if not anyEnergy then return true end
    return false
  end)
  self:register("SuperPotion_PlayerSelectEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local slot, err = s:_selectPlayArea(context)
    if slot == nil then return nil, err end
    local damage = s:_playAreaDamage(actor, slot)
    if not damage or damage <= 0 then return nil, "invalid_selection:no_damage" end
    local energyCount = actor.duelOps:createArenaOrBenchEnergyCardList(slot)
    if energyCount == 0 then return nil, "invalid_selection:no_energy" end
    local discard, discardErr =
      s:_selection(context, "discardEnergy", "selectDiscardEnergy", { playArea = slot })
    if discard == nil then return nil, discardErr end
    actor.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", slot)
    actor.memory:writeSymbol8("hTemp_ffa0", discard)
    actor.memory:writeSymbol8("hTempRetreatCostCards", math.min(40, damage))
    return false
  end)
  self:register("SuperPotion_HealEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local slot = actor.memory:readSymbol8("hTempPlayAreaLocation_ffa1")
    local discard = actor.memory:readSymbol8("hTemp_ffa0")
    local heal = actor.memory:readSymbol8("hTempRetreatCostCards")
    local hpOffset = s.c.DUELVARS_ARENA_CARD_HP + slot
    actor.duelVars:set(hpOffset, actor.duelVars:get(hpOffset) + heal)
    actor.duelOps:putCardInDiscardPile(discard)
    s:_event("heal_play_area", { slot = slot, amount = heal, discardedEnergy = discard })
    return false
  end)

  -- Pokemon Breeder evolves a Basic Pokemon in the Play Area directly into a
  -- Stage2 Pokemon chosen from hand, skipping Stage1. The evolved card is
  -- marked STAGE2_WITHOUT_STAGE1 (rather than the printed STAGE2) so it still
  -- devolves correctly under Devolution Spray, which only knows how to step
  -- back one stage at a time. AIDecide_PokemonBreeder picks the Basic/Stage2
  -- pair; this effect only applies whatever the decision/selection layer
  -- already chose.
  local function prehistoricPowerActive(s, actor)
    local _, aero = actor.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(s.c.AERODACTYL)
    if not aero then return false end
    local _, muk = actor.combat.status:countPokemonWithActivePkmnPowerInBothPlayAreas(s.c.MUK)
    return not muk
  end
  local function playableStage2FromHand(s, actor)
    local hand = actor.duelOps:createHandCardList()
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    local playable = {}
    for _, deckIndex in ipairs(hand) do
      local cardId = actor.cardData:getCardIDFromDeckIndex(deckIndex)
      local row = actor.cardData:get(cardId)
      if row and row.type < s.c.TYPE_ENERGY and row.stage == s.c.STAGE2 then
        for slot = s.c.PLAY_AREA_ARENA, count - 1 do
          if actor.duelOps:checkIfCanEvolveIntoBasicToStage2(deckIndex, slot) then
            playable[#playable + 1] = deckIndex
            break
          end
        end
      end
    end
    return playable
  end
  self:register("PokemonBreeder_HandPlayAreaCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if #playableStage2FromHand(s, actor) == 0 then return true end
    return prehistoricPowerActive(s, actor)
  end)
  self:register("PokemonBreeder_PlayerSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local playable = playableStage2FromHand(s, actor)
    if #playable == 0 then return nil, "invalid_selection:no_playable_stage2" end

    local stage2, err = s:_selection(context, "handStage2Pokemon", "selectHandCard",
      { choices = playable, stage2Breeder = true })
    if stage2 == nil then return nil, err end
    local validChoice = false
    for _, deckIndex in ipairs(playable) do
      if deckIndex == stage2 then validChoice = true break end
    end
    if not validChoice then return nil, "invalid_selection:handStage2Pokemon" end

    local slot, slotErr = s:_selectPlayArea(context)
    if slot == nil then return nil, slotErr end
    if not actor.duelOps:checkIfCanEvolveIntoBasicToStage2(stage2, slot) then
      return nil, "invalid_selection:playArea"
    end

    actor.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", slot)
    actor.memory:writeSymbol8("hTemp_ffa0", stage2)
    return false
  end)
  self:register("PokemonBreeder_EvolveEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local slot = actor.memory:readSymbol8("hTempPlayAreaLocation_ffa1")
    local stage2 = actor.memory:readSymbol8("hTemp_ffa0")

    local ready, triggerErr = actor.combat:checkPlayedPokemonCardTrigger(stage2)
    if not ready then return nil, triggerErr end

    actor.duelOps:evolvePokemonCard(stage2, slot)
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_STAGE + slot, s.c.STAGE2_WITHOUT_STAGE1 or 3)

    local triggered, triggerResult = actor.combat:processPlayedPokemonCard(stage2, slot)
    if not triggered then return nil, triggerResult end
    s:_event("evolve", { deckIndex = stage2, slot = slot, breeder = true })
    return false
  end)

  -- Revive places a chosen Basic Pokemon from the user's Discard Pile on the
  -- Bench with half HP rounded up to the nearest 10.
  self:register("Revive_BenchCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    if actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) >= s.c.MAX_PLAY_AREA_POKEMON then
      return true
    end
    return #basicPokemonInDiscard(s, actor) == 0
  end)
  self:register("Revive_PlayerSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local deckIndex, err = s:_selection(context, "discardBasicPokemon",
      "selectDiscardCard", { basicPokemon = true })
    if deckIndex == nil then return nil, err end
    local valid = actor.duelVars:get(deckIndex) == s.c.CARD_LOCATION_DISCARD_PILE
    local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
    valid = valid and row and row.type < s.c.TYPE_ENERGY and row.stage == s.c.BASIC
    if not valid then return nil, "invalid_selection:discardBasicPokemon" end
    state(context).revivePokemon = deckIndex
    s.memory:writeSymbol8("hTemp_ffa0", deckIndex)
    return false
  end)
  self:register("Revive_PlaceInPlayAreaEffect", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local deckIndex = state(context).revivePokemon or s.memory:readSymbol8("hTemp_ffa0")
    actor.duelOps:moveDiscardPileCardToHand(deckIndex)
    actor.duelOps:addCardToHand(deckIndex)
    local slot, carry = actor.duelOps:putHandPokemonCardInPlayArea(deckIndex)
    if carry then return nil, "revive_bench_full" end
    local hpOffset = s.c.DUELVARS_ARENA_CARD_HP + slot
    local half = math.floor(actor.duelVars:get(hpOffset) / 2)
    if half % 10 ~= 0 then half = half + 5 end
    actor.duelVars:set(hpOffset, half)
    return false
  end)

  -- Pokemon Flute mirrors Revive on the non-turn side but restores the Basic
  -- Pokemon at full HP.
  self:register("PokemonFlute_BenchCheck", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    actor.duelVars:swapTurn()
    local full = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
      >= s.c.MAX_PLAY_AREA_POKEMON
    local basics = full and {} or basicPokemonInDiscard(s, actor)
    actor.duelVars:swapTurn()
    return full or #basics == 0
  end)
  self:register("PokemonFlute_PlayerSelection", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local deckIndex, err = s:_selection(context, "opponentDiscardBasicPokemon",
      "selectOpponentDiscardCard", { nonTurn = true, basicPokemon = true })
    if deckIndex == nil then return nil, err end
    actor.duelVars:swapTurn()
    local valid = actor.duelVars:get(deckIndex) == s.c.CARD_LOCATION_DISCARD_PILE
    local row = actor.cardData:get(actor.cardData:getCardIDFromDeckIndex(deckIndex))
    valid = valid and row and row.type < s.c.TYPE_ENERGY and row.stage == s.c.BASIC
    actor.duelVars:swapTurn()
    if not valid then return nil, "invalid_selection:opponentDiscardBasicPokemon" end
    state(context).flutePokemon = deckIndex
    s.memory:writeSymbol8("hTemp_ffa0", deckIndex)
    return false
  end)
  self:register("PokemonFlute_PlaceInPlayAreaText", function(s, context)
    local actor = actorForTrainer(context)
    if not actor then return nil, "effect_context_missing_actor" end
    local deckIndex = state(context).flutePokemon or s.memory:readSymbol8("hTemp_ffa0")
    actor.duelVars:swapTurn()
    actor.duelOps:moveDiscardPileCardToHand(deckIndex)
    actor.duelOps:addCardToHand(deckIndex)
    local _, carry = actor.duelOps:putHandPokemonCardInPlayArea(deckIndex)
    actor.duelVars:swapTurn()
    if carry then return nil, "pokemon_flute_bench_full" end
    return false
  end)

  -- Energy Trans: the cartridge UI loops until the user exits. The host passes
  -- that exact sequence as `energyTransfers`, each entry containing an attached
  -- Grass Energy deck index and destination Play Area slot.
  self:register("EnergyTrans_CheckPlayArea", function(s, context)
    local combat = context.combat
    if not combat then return nil, "effect_context_missing_combat" end
    local slot = context.powerSlot or s.c.PLAY_AREA_ARENA
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    if s.status:checkIsIncapableOfUsingPkmnPower(slot) then return true end
    for deckIndex = 0, s.c.DECK_SIZE - 1 do
      local location = combat.duelVars:get(deckIndex)
      if bit.band(location, s.c.CARD_LOCATION_PLAY_AREA) ~= 0 then
        local row = combat.cardData:get(combat.cardData:getCardIDFromDeckIndex(deckIndex))
        if row and row.type == s.c.TYPE_ENERGY_GRASS then return false end
      end
    end
    return true
  end)
  self:register("EnergyTrans_PrintProcedure", function() return false end)
  self:register("EnergyTrans_AIEffect", function(s, context)
    local combat = context.combat
    if not combat then return nil, "effect_context_missing_combat" end
    local dest = s.memory:readSymbol8("hAIEnergyTransPlayAreaLocation")
    local deckIndex = s.memory:readSymbol8("hAIEnergyTransEnergyCard")
    local row = combat.cardData:get(combat.cardData:getCardIDFromDeckIndex(deckIndex))
    local count = combat.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    if not row or row.type ~= s.c.TYPE_ENERGY_GRASS or dest < 0 or dest >= count
        or bit.band(combat.duelVars:get(deckIndex), s.c.CARD_LOCATION_PLAY_AREA) == 0 then
      return nil, "invalid_ai_energy_trans_state"
    end
    combat.duelOps:addCardToHand(deckIndex)
    combat.duelOps:putHandCardInPlayArea(deckIndex, dest)
    return false
  end)
  self:register("EnergyTrans_TransferEffect", function(s, context)
    local combat = context.combat
    if not combat then return nil, "effect_context_missing_combat" end
    local transfers, err = s:_selection(context, "energyTransfers",
      "selectEnergyTransfers", { energyType = s.c.TYPE_ENERGY_GRASS })
    if transfers == nil then return nil, err end
    if type(transfers) ~= "table" then return nil, "invalid_selection:energyTransfers" end
    for _, transfer in ipairs(transfers) do
      if type(transfer) ~= "table" then return nil, "invalid_selection:energyTransfers" end
      local deckIndex, dest = transfer.energyDeckIndex, transfer.toPlayArea
      if type(deckIndex) ~= "number" or type(dest) ~= "number" then
        return nil, "invalid_selection:energyTransfers"
      end
      local location = combat.duelVars:get(deckIndex)
      local row = combat.cardData:get(combat.cardData:getCardIDFromDeckIndex(deckIndex))
      local count = combat.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
      if bit.band(location, s.c.CARD_LOCATION_PLAY_AREA) == 0
          or not row or row.type ~= s.c.TYPE_ENERGY_GRASS
          or dest < 0 or dest >= count
          or combat.duelVars:get(s.c.DUELVARS_ARENA_CARD + dest) == 0xff then
        return nil, "invalid_selection:energyTransfers"
      end
      combat.duelOps:addCardToHand(deckIndex)
      combat.duelOps:putHandCardInPlayArea(deckIndex, dest)
      s:_event("energy_trans", { deckIndex = deckIndex, toPlayArea = dest })
    end
    return false
  end)

  -- Manual Pokemon Power families used by the common AI. Presentation loops
  -- are host-owned, but the cartridge's state validation, once-per-turn flags,
  -- damage-counter movement, card movement and knockout resolution are native.
  local function powerActor(s, context)
    local actor = context.combat or context.playerActions
    if not actor then return nil, "effect_context_missing_actor" end
    return actor
  end
  local function powerSlot(s, context)
    return context.powerSlot or s.memory:readSymbol8("hTemp_ffa0")
  end
  local function powerUsedMask(s)
    return bit.lshift(1, s.c.USED_PKMN_POWER_THIS_TURN_F)
  end
  local function markPowerUsed(s, actor, slot)
    local off = s.c.DUELVARS_ARENA_CARD_FLAGS + slot
    actor.duelVars:set(off, bit.bor(actor.duelVars:get(off), powerUsedMask(s)))
  end
  local function anyPlayAreaDamage(s, actor, nonTurn)
    if nonTurn then actor.duelVars:swapTurn() end
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    local found = false
    for slot = s.c.PLAY_AREA_ARENA, count - 1 do
      local damage = s:_playAreaDamage(actor, slot)
      if damage and damage > 0 then found = true break end
    end
    if nonTurn then actor.duelVars:swapTurn() end
    return found
  end
  local function transferDamageCounter(s, actor, fromSlot, toSlot)
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    if type(fromSlot) ~= "number" or type(toSlot) ~= "number"
        or fromSlot < 0 or fromSlot >= count or toSlot < 0 or toSlot >= count
        or fromSlot == toSlot then
      return nil, "invalid_selection:damage_transfer"
    end
    local fromDamage = s:_playAreaDamage(actor, fromSlot)
    if not fromDamage or fromDamage < 10 then return nil, "invalid_selection:damage_transfer_source" end
    local toHP = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_HP + toSlot)
    if toHP <= 10 then return nil, "invalid_selection:damage_transfer_target" end
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_HP + fromSlot,
      actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_HP + fromSlot) + 10)
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_HP + toSlot, toHP - 10)
    s:_event("damage_counter_transfer", { from = fromSlot, to = toSlot })
    return false
  end

  -- Venusaur: Solar Power. Usable once per turn, and only while at least
  -- one active Pokemon (either side) has a status condition; clears both
  -- sides' status unconditionally when used.
  self:register("SolarPower_CheckUse", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    local flags = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_FLAGS + slot)
    if bit.band(flags, powerUsedMask(s)) ~= 0 then return true end
    if s.status:checkIsIncapableOfUsingPkmnPower(slot) then return true end
    if actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_STATUS) ~= 0 then return false end
    return actor.duelVars:getNonTurn(s.c.DUELVARS_ARENA_CARD_STATUS) == 0
  end)
  self:register("SolarPower_RemoveStatusEffect", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    s.memory:writeSymbol8("wLoadedAttackAnimation", s.c.ATK_ANIM_HEAL_BOTH_SIDES)
    markPowerUsed(s, actor, slot)
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_STATUS, s.c.NO_STATUS)
    actor.duelVars:setNonTurn(s.c.DUELVARS_ARENA_CARD_STATUS, s.c.NO_STATUS)
    return false
  end)

  -- Alakazam: Damage Swap.
  self:register("DamageSwap_CheckDamage", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    if not anyPlayAreaDamage(s, actor, false) then return true end
    return s.status:checkIsIncapableOfUsingPkmnPower(slot)
  end)
  self:register("DamageSwap_SelectAndSwapEffect", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local transfers, err = s:_selection(context, "damageTransfers",
      "selectDamageTransfers", { power = "damage_swap" })
    if transfers == nil then return nil, err end
    if type(transfers) ~= "table" then return nil, "invalid_selection:damageTransfers" end
    for _, move in ipairs(transfers) do
      if type(move) ~= "table" then return nil, "invalid_selection:damageTransfers" end
      local carry, moveErr = transferDamageCounter(s, actor, move.fromPlayArea, move.toPlayArea)
      if carry == nil then return nil, moveErr end
    end
    return false
  end)
  self:register("DamageSwap_SwapEffect", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local fromSlot = s.memory:readSymbol8("hAIPkmnPowerEffectParam")
    local toSlot = s.memory:readSymbol8("hTempRetreatCostCards")
    return transferDamageCounter(s, actor, fromSlot, toSlot)
  end)

  -- Tentacool: Cowardice.
  self:register("Cowardice_CheckUseAndBench", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    if s.status:checkIsIncapableOfUsingPkmnPower(slot) then return true end
    if actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) < 2 then return true end
    local flags = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_FLAGS + slot)
    return bit.band(flags, s.c.CAN_EVOLVE_THIS_TURN) == 0
  end)
  self:register("Cowardice_PlayerSelectEffect", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    if slot ~= s.c.PLAY_AREA_ARENA then
      s.memory:writeSymbol8("hAIPkmnPowerEffectParam", 0xff)
      return false
    end
    local replacement, err = s:_selection(context, "replacement", "selectBench",
      { power = "cowardice" })
    if replacement == nil then return nil, err end
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    if type(replacement) ~= "number" or replacement < s.c.PLAY_AREA_BENCH_1
        or replacement >= count then return nil, "invalid_selection:replacement" end
    s.memory:writeSymbol8("hAIPkmnPowerEffectParam", replacement)
    return false
  end)
  self:register("Cowardice_ReturnToHandEffect", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    local deckIndex = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD + slot)
    if deckIndex == 0xff then return nil, "cowardice_empty_slot" end
    actor.duelOps:movePlayAreaCardToDiscardPile(slot)
    if slot == s.c.PLAY_AREA_ARENA then
      local replacement = s.memory:readSymbol8("hAIPkmnPowerEffectParam")
      if replacement == 0xff then return nil, "cowardice_missing_replacement" end
      actor.duelOps:swapArenaWithBenchPokemon(replacement)
    end
    actor.duelOps:moveDiscardPileCardToHand(deckIndex)
    actor.duelOps:addCardToHand(deckIndex)
    actor.duelOps:shiftAllPokemonToFirstPlayAreaSlots()
    s:_event("cowardice", { slot = slot, deckIndex = deckIndex })
    return false
  end)

  -- Mysterious Fossil / Clefairy Doll's synthetic "Discard" Power (engine/
  -- duel/core.asm patches these two Trainer-as-Pokemon cards' data with 10
  -- HP, UNABLE_RETREAT, and a single fake Power pointing at this effect
  -- list, since they have no printed attacks/Powers of their own). Same
  -- shape as Cowardice above, but discards straight to the discard pile
  -- rather than returning to hand, and gates on Play Area count alone (no
  -- CAN_EVOLVE_THIS_TURN check).
  self:register("TrainerCardAsPokemon_BenchCheck", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    return actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) < 2
  end)
  self:register("TrainerCardAsPokemon_PlayerSelectSwitch", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    if slot ~= s.c.PLAY_AREA_ARENA then return false end
    local replacement, err = s:_selection(context, "replacement", "selectBench",
      { power = "trainer_card_as_pokemon" })
    if replacement == nil then return nil, err end
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    if type(replacement) ~= "number" or replacement < s.c.PLAY_AREA_BENCH_1
        or replacement >= count then return nil, "invalid_selection:replacement" end
    s.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", replacement)
    return false
  end)
  self:register("TrainerCardAsPokemon_DiscardEffect", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = s.memory:readSymbol8("hTemp_ffa0")
    actor.duelOps:movePlayAreaCardToDiscardPile(slot)
    if slot == s.c.PLAY_AREA_ARENA then
      local replacement = s.memory:readSymbol8("hTempPlayAreaLocation_ffa1")
      actor.duelOps:swapArenaWithBenchPokemon(replacement)
    end
    actor.duelOps:shiftAllPokemonToFirstPlayAreaSlots()
    s:_event("trainer_card_as_pokemon_discard", { slot = slot })
    return false
  end)

  -- Vileplume: Heal.
  self:register("Heal_OncePerTurnCheck", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    local flags = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_FLAGS + slot)
    if bit.band(flags, powerUsedMask(s)) ~= 0 then return true end
    if not anyPlayAreaDamage(s, actor, false) then return true end
    return s.status:checkIsIncapableOfUsingPkmnPower(slot)
  end)
  self:register("Heal_RemoveDamageEffect", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    local result, err = s.setup:tossCoin()
    if result == nil then return nil, err end
    s.memory:writeSymbol8("hAIPkmnPowerEffectParam", result)
    markPowerUsed(s, actor, slot)
    if result == s.c.TAILS then return false end
    local target, selErr = s:_selection(context, "playArea", "selectPlayArea",
      { power = "heal", damaged = true })
    if target == nil then return nil, selErr end
    local damage, maxHP, hp = s:_playAreaDamage(actor, target)
    if not damage or damage <= 0 then return nil, "invalid_selection:playArea" end
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_HP + target, math.min(maxHP, hp + 10))
    s.memory:writeSymbol8("hPlayAreaEffectTarget", target)
    s:_event("heal_power", { powerSlot = slot, target = target, amount = 10 })
    return false
  end)

  -- Slowbro: Step In. Unlike the other manual Powers here, this one can
  -- ONLY be used from the Bench (source: "CanOnlyBeUsedOnTheBenchText" when
  -- hTempPlayAreaLocation_ff9d == PLAY_AREA_ARENA), swapping itself into
  -- the Active spot. The used-this-turn flag is set on PLAY_AREA_ARENA
  -- unconditionally afterward (no +slot offset in the source), since by
  -- then this card IS the new Arena occupant.
  self:register("StepIn_BenchCheck", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    if slot == s.c.PLAY_AREA_ARENA then return true end
    local flags = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_FLAGS + slot)
    if bit.band(flags, powerUsedMask(s)) ~= 0 then return true end
    return s.status:checkIsIncapableOfUsingPkmnPower(slot)
  end)
  self:register("StepIn_SwitchEffect", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = s.memory:readSymbol8("hTemp_ffa0")
    actor.duelOps:swapArenaWithBenchPokemon(slot)
    markPowerUsed(s, actor, s.c.PLAY_AREA_ARENA)
    return false
  end)

  -- Venomoth: Shift.
  self:register("Shift_OncePerTurnCheck", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    local flags = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_FLAGS + slot)
    if bit.band(flags, powerUsedMask(s)) ~= 0 then return true end
    return s.status:checkIsIncapableOfUsingPkmnPower(slot)
  end)
  self:register("Shift_PlayerSelectEffect", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local color, err = s:_selection(context, "color", "selectColor", { power = "shift" })
    if color == nil then return nil, err end
    local found = false
    for side = 0, 1 do
      if side == 1 then actor.duelVars:swapTurn() end
      local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
      for slot = 0, count - 1 do
        if s.status:getPlayAreaCardColor(slot) == color then found = true break end
      end
      if side == 1 then actor.duelVars:swapTurn() end
      if found then break end
    end
    if not found then return nil, "invalid_selection:color" end
    s.memory:writeSymbol8("hAIPkmnPowerEffectParam", color)
    return false
  end)
  self:register("Shift_ChangeColorEffect", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    local color = s.memory:readSymbol8("hAIPkmnPowerEffectParam")
    markPowerUsed(s, actor, slot)
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_CHANGED_TYPE + slot,
      bit.bor(color, bit.lshift(1, s.c.HAS_CHANGED_COLOR_F)))
    s:_event("shift_color", { slot = slot, color = color })
    return false
  end)

  -- Mankey: Peek. The effect is informational; only the once-per-turn flag and
  -- exact encoded target are persistent duel state.
  self:register("Peek_OncePerTurnCheck", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    local flags = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_FLAGS + slot)
    if bit.band(flags, powerUsedMask(s)) ~= 0 then return true end
    return s.status:checkIsIncapableOfUsingPkmnPower(slot)
  end)
  self:register("Peek_SelectEffect", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    local target, err = s:_selection(context, "peekTarget", "selectPeekTarget", { power = "peek" })
    if target == nil then return nil, err end
    markPowerUsed(s, actor, slot)
    s.memory:writeSymbol8("hAIPkmnPowerEffectParam", target)
    s:_event("peek", { slot = slot, target = target })
    return false
  end)

  -- Slowbro: Strange Behavior.
  self:register("StrangeBehavior_CheckDamage", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    if not anyPlayAreaDamage(s, actor, false) then return true end
    if actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_HP + slot) < 20 then return true end
    return s.status:checkIsIncapableOfUsingPkmnPower(slot)
  end)
  self:register("StrangeBehavior_SelectAndSwapEffect", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    local transfers, err = s:_selection(context, "damageTransfers",
      "selectDamageTransfers", { power = "strange_behavior", receiver = slot })
    if transfers == nil then return nil, err end
    if type(transfers) ~= "table" then return nil, "invalid_selection:damageTransfers" end
    for _, move in ipairs(transfers) do
      if type(move) ~= "table" or move.toPlayArea ~= slot then
        return nil, "invalid_selection:damageTransfers"
      end
      local carry, moveErr = transferDamageCounter(s, actor, move.fromPlayArea, move.toPlayArea)
      if carry == nil then return nil, moveErr end
    end
    return false
  end)
  self:register("StrangeBehavior_SwapEffect", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local toSlot = powerSlot(s, context)
    local fromSlot = s.memory:readSymbol8("hTempPlayAreaLocation_ffa1")
    return transferDamageCounter(s, actor, fromSlot, toSlot)
  end)

  -- Gengar: Curse.
  self:register("Curse_CheckDamageAndBench", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    s.memory:writeSymbol8("hTemp_ffa0", slot)
    local flags = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_FLAGS + slot)
    if bit.band(flags, powerUsedMask(s)) ~= 0 then return true end
    actor.duelVars:swapTurn()
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    local hasDamage = anyPlayAreaDamage(s, actor, false)
    actor.duelVars:swapTurn()
    if count < 2 or not hasDamage then return true end
    return s.status:checkIsIncapableOfUsingPkmnPower(slot)
  end)
  self:register("Curse_PlayerSelectEffect", function(s, context)
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local selection = context.selection or {}
    local fromSlot, toSlot = selection.fromPlayArea, selection.toPlayArea
    if fromSlot == nil or toSlot == nil then
      local picked, err = s:_selection(context, "curseTransfer", "selectCurseTransfer",
        { power = "curse", nonTurn = true })
      if picked == nil then return nil, err end
      if type(picked) ~= "table" then return nil, "invalid_selection:curseTransfer" end
      fromSlot, toSlot = picked.fromPlayArea, picked.toPlayArea
    end
    actor.duelVars:swapTurn()
    local count = actor.duelVars:get(s.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
    local valid = type(fromSlot) == "number" and type(toSlot) == "number"
      and fromSlot >= 0 and fromSlot < count and toSlot >= 0 and toSlot < count
      and fromSlot ~= toSlot
    local damage = valid and s:_playAreaDamage(actor, fromSlot) or nil
    actor.duelVars:swapTurn()
    if not valid or not damage or damage <= 0 then return nil, "invalid_selection:curseTransfer" end
    s.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", fromSlot)
    s.memory:writeSymbol8("hPlayAreaEffectTarget", toSlot)
    return false
  end)
  self:register("Curse_TransferDamageEffect", function(s, context)
    local combat = context.combat
    local actor = powerActor(s, context); if not actor then return nil, "effect_context_missing_actor" end
    local slot = powerSlot(s, context)
    markPowerUsed(s, actor, slot)
    local fromSlot = s.memory:readSymbol8("hTempPlayAreaLocation_ffa1")
    local toSlot = s.memory:readSymbol8("hPlayAreaEffectTarget")
    actor.duelVars:swapTurn()
    local fromDamage = s:_playAreaDamage(actor, fromSlot)
    local toHP = actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_HP + toSlot)
    if not fromDamage or fromDamage < 10 or toHP <= 0 then
      actor.duelVars:swapTurn()
      return nil, "invalid_selection:curseTransfer"
    end
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_HP + fromSlot,
      actor.duelVars:get(s.c.DUELVARS_ARENA_CARD_HP + fromSlot) + 10)
    actor.duelVars:set(s.c.DUELVARS_ARENA_CARD_HP + toSlot, math.max(0, toHP - 10))
    actor.duelVars:swapTurn()
    s:_event("curse", { from = fromSlot, to = toSlot })
    if combat then
      local failed, exchangeErr = combat.setup:exchangeRNG()
      if failed then return nil, exchangeErr end
      local finished, koErr = combat.knockouts:handlePendingResolution()
      if koErr then return nil, koErr end
      context.powerEndedDuel = finished == true
    end
    return false
  end)

end

return EffectCommands
