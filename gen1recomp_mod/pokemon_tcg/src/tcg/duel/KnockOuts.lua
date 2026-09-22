-- Between-turn knockout state machine translated from pret/poketcg
-- src/engine/duel/core.asm HandleBetweenTurnKnockOuts and dependencies.
-- Player replacement UI and the still-untranslated generic AI KO scorer remain
-- explicit choice boundaries; all result-bit accumulation and cleanup is native.

local bit = require("bit")

local KnockOuts = {}
KnockOuts.__index = KnockOuts

local function u8(v) return bit.band(v, 0xff) end

function KnockOuts.new(memory, duelVars, duelOps, cardData, status, core, prizes,
    practice, ai, setup, constants, coreData, adapters)
  assert(type(coreData) == "table" and coreData.schema == 3,
    "generated TCG core-data schema 3 is required")
  assert(type(coreData.duelFinishTable) == "table" and #coreData.duelFinishTable == 16,
    "HandleBetweenTurnKnockOuts.Data_6ed2 extraction is required")
  return setmetatable({
    memory = assert(memory),
    duelVars = assert(duelVars),
    duelOps = assert(duelOps),
    cardData = assert(cardData),
    status = assert(status),
    core = assert(core),
    prizes = assert(prizes),
    practice = assert(practice),
    ai = assert(ai),
    setup = assert(setup),
    c = assert(constants),
    finishTable = coreData.duelFinishTable,
    adapters = adapters or {},
  }, KnockOuts)
end

function KnockOuts:_required(name)
  local fn = self.adapters[name]
  assert(type(fn) == "function", "TCG knockout flow requires untranslated adapter: " .. name)
  return fn
end

function KnockOuts:_event(name, payload)
  local fn = self.adapters.event
  if fn then fn(name, payload or {}) end
end

-- CountKnockedOutPokemon:: Clefairy Doll and Mysterious Fossil retain their
-- original Trainer card type, so they do not award prizes when their HP is 0.
function KnockOuts:countKnockedOutPokemon()
  local count = 0
  for slot = 0, self.c.MAX_PLAY_AREA_POKEMON - 1 do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD + slot)
    if deckIndex ~= 0xff then
      local hp = self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot)
      if hp == 0 then
        local cardId = self.cardData:getCardIDFromDeckIndex(deckIndex)
        if self.cardData:getType(cardId) ~= self.c.TYPE_TRAINER then count = count + 1 end
      end
    end
  end
  self.memory:writeSymbol8("wNumberPrizeCardsToTake", count)
  return count, count ~= 0
end

-- CheckIfTurnDuelistPlayAreaPokemonAreAllKnockedOut:: returns source carry.
function KnockOuts:checkIfTurnDuelistPlayAreaPokemonAreAllKnockedOut()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for slot = 0, count - 1 do
    if self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot) ~= 0 then return false end
  end
  return true
end

function KnockOuts:moveAllTurnHolderKnockedOutPokemonToDiscardPile()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for slot = 0, count - 1 do
    if self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP + slot) == 0 then
      self.duelOps:movePlayAreaCardToDiscardPile(slot)
    end
  end
end

-- Preserve the source's cross-perspective test/clear ordering exactly.
function KnockOuts:clearDamageReductionSubstatus2OfKnockedOutPokemon()
  self.duelVars:swapTurn()
  if self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_HP) == 0 then
    self.status:clearDamageReductionSubstatus2()
  end
  self.duelVars:swapTurn()
  if self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_HP) == 0 then
    self.status:clearDamageReductionSubstatus2()
  end
end

function KnockOuts:cleanupKnockedOutPokemon()
  self:moveAllTurnHolderKnockedOutPokemonToDiscardPile()
  self.duelVars:swapTurn()
  self:moveAllTurnHolderKnockedOutPokemonToDiscardPile()
  self.duelVars:swapTurn()
  self.duelOps:shiftAllPokemonToFirstPlayAreaSlots()
end

local function rollCarry(value, carry)
  return u8(bit.lshift(value, 1) + (carry and 1 or 0))
end

-- Func_6fa5:: award prizes to the other duelist for current-side KOs.
function KnockOuts:_takePrizesForCurrentKnockouts()
  local count, hasKO = self:countKnockedOutPokemon()
  if not hasKO then return false end
  self.duelVars:swapTurn()
  local allPrizes, err = self.prizes:turnDuelistTakePrizes()
  self.duelVars:swapTurn()
  if allPrizes == nil then return nil, err end
  if not allPrizes then return false end
  -- Func_6fa5 swaps back to the prize-taking duelist for the all-prizes
  -- message and ExchangeRNG, then restores the KO side before returning carry.
  self.duelVars:swapTurn()
  self:_event("took_all_prizes", { knockedOut = count })
  local failed, exchangeErr = self.setup:exchangeRNG()
  self.duelVars:swapTurn()
  if failed then return nil, exchangeErr end
  return true
end

-- ReplaceKnockedOutPokemon:: returns source carry (true means no replacement).
function KnockOuts:replaceKnockedOutPokemon()
  if self.duelVars:get(self.c.DUELVARS_ARENA_CARD_HP) ~= 0 then return false end

  self.duelOps:clearAllStatusConditions()
  local _, noAliveBench = self.duelOps:hasAlivePokemonInBench()
  if noAliveBench then
    self:_event("no_pokemon_to_replace_knockout", {})
    local failed, err = self.setup:exchangeRNG()
    if failed then return nil, err end
    return true
  end

  local dtype = self.duelVars:get(self.c.DUELVARS_DUELIST_TYPE)
  local selected
  if dtype == self.c.DUELIST_TYPE_PLAYER then
    self:_event("select_knockout_replacement", {})
    self.practice:doAction(self.c.PRACTICEDUEL_PLAY_STARYU_FROM_BENCH)
    while true do
      selected = self:_required("selectKnockoutReplacement")()
      assert(type(selected) == "number"
          and selected >= self.c.PLAY_AREA_BENCH_1
          and selected < self.c.MAX_PLAY_AREA_POKEMON,
        "knockout replacement adapter returned invalid play-area slot")
      self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", selected)
      if self.memory:readSymbol8("wDuelType") == self.c.DUELTYPE_LINK then
        self:_required("sendKnockoutReplacement")(selected)
      end
      if not self.practice:doAction(self.c.PRACTICEDUEL_REPLACE_KNOCKED_OUT_POKEMON) then break end
    end
  elseif dtype == self.c.DUELIST_TYPE_LINK_OPP then
    selected = self:_required("receiveKnockoutReplacement")()
    assert(type(selected) == "number", "link replacement transport returned no slot")
    self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", selected)
    while self.practice:doAction(self.c.PRACTICEDUEL_REPLACE_KNOCKED_OUT_POKEMON) do
      selected = self:_required("receiveKnockoutReplacement")()
      self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", selected)
    end
  else
    selected = self.ai:koSwitch()
    self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", selected)
    while self.practice:doAction(self.c.PRACTICEDUEL_REPLACE_KNOCKED_OUT_POKEMON) do
      selected = self.ai:koSwitch()
      self.memory:writeSymbol8("hTempPlayAreaLocation_ff9d", selected)
    end
  end

  self.duelOps:swapPlayAreaPokemon(selected, self.c.PLAY_AREA_ARENA)
  self:_event("knockout_replaced", { slot = selected })
  local failed, err = self.setup:exchangeRNG()
  if failed then return nil, err end
  return false
end

function KnockOuts:_finish(result)
  self.memory:writeSymbol8("wDuelFinished", result)
  self:cleanupKnockedOutPokemon()
  return true
end

-- HandleBetweenTurnKnockOuts:: Exact result-bit accumulation and result table.
function KnockOuts:handlePendingResolution()
  self:clearDamageReductionSubstatus2OfKnockedOutPokemon()
  local finishParam = 0
  self.memory:writeSymbol8("wDuelFinishParam", 0)

  self.duelVars:swapTurn()
  local carry, err = self:_takePrizesForCurrentKnockouts()
  if carry == nil then self.duelVars:swapTurn(); return true, err end
  finishParam = rollCarry(finishParam, carry)
  self.memory:writeSymbol8("wDuelFinishParam", finishParam)
  self.duelVars:swapTurn()

  if finishParam ~= 0 and not self:checkIfTurnDuelistPlayAreaPokemonAreAllKnockedOut() then
    local koCount = self:countKnockedOutPokemon()
    self.duelVars:swapTurn()
    local prizeCount = self.duelOps:countPrizes()
    self.duelVars:swapTurn()
    if u8(prizeCount - 1) >= koCount then
      self.duelVars:swapTurn()
      self.core:takeAPrizes(koCount)
      self.duelVars:swapTurn()
      return self:_finish(self.c.TURN_PLAYER_WON)
    end
  end

  carry, err = self:_takePrizesForCurrentKnockouts()
  if carry == nil then return true, err end
  finishParam = rollCarry(finishParam, carry)
  self.memory:writeSymbol8("wDuelFinishParam", finishParam)

  if finishParam == self.c.TRUE then
    self.duelVars:swapTurn()
    local otherAllKO = self:checkIfTurnDuelistPlayAreaPokemonAreAllKnockedOut()
    self.duelVars:swapTurn()
    if not otherAllKO then return self:_finish(self.c.TURN_PLAYER_LOST) end
  end

  self.duelVars:swapTurn()
  carry, err = self:replaceKnockedOutPokemon()
  if carry == nil then self.duelVars:swapTurn(); return true, err end
  finishParam = rollCarry(finishParam, carry)
  self.memory:writeSymbol8("wDuelFinishParam", finishParam)
  self.duelVars:swapTurn()

  carry, err = self:replaceKnockedOutPokemon()
  if carry == nil then return true, err end
  finishParam = rollCarry(finishParam, carry)
  self.memory:writeSymbol8("wDuelFinishParam", finishParam)

  if finishParam == 0 then
    self:cleanupKnockedOutPokemon()
    return false
  end

  local result = self.finishTable[finishParam + 1]
  assert(result ~= nil, "wDuelFinishParam indexed outside Data_6ed2")
  return self:_finish(result)
end

return KnockOuts
