-- Main turn control flow translated from pret/poketcg
-- src/engine/duel/core.asm HandleTurn and MainDuelLoop through the result
-- branch. Presentation and DuelMainInterface action dispatch remain explicit.

local TurnFlow = {}
TurnFlow.__index = TurnFlow

function TurnFlow.new(memory, duelVars, duelOps, core, setup, status, saveData,
    practice, duelInterface, constants, adapters)
  return setmetatable({
    memory = assert(memory),
    duelVars = assert(duelVars),
    duelOps = assert(duelOps),
    core = assert(core),
    setup = assert(setup),
    status = assert(status),
    saveData = assert(saveData),
    practice = assert(practice),
    duelInterface = assert(duelInterface),
    c = assert(constants),
    adapters = adapters or {},
  }, TurnFlow)
end

function TurnFlow:_required(name)
  local fn = self.adapters[name]
  assert(type(fn) == "function", "TCG turn flow requires untranslated adapter: " .. name)
  return fn
end

function TurnFlow:handleTurn()
  local dtype = self.duelVars:get(self.c.DUELVARS_DUELIST_TYPE)
  self.memory:writeSymbol8("wDuelistType", dtype)

  if self.memory:readSymbol8("wDuelTurns") >= 2 then
    self.core:setAllPlayAreaPokemonCanEvolve()
  end
  self.core:initVariablesToBeginTurn()

  self:_required("displayDrawOneCardScreen")(self.duelVars:turn(), dtype)
  local deckIndex, carry = self.duelOps:drawCardFromDeck()
  if carry then
    self.memory:writeSymbol8("wDuelFinished", self.c.TURN_PLAYER_LOST)
    return "deck_empty"
  end

  self.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
  self.duelOps:addCardToHand(deckIndex)

  if dtype == self.c.DUELIST_TYPE_PLAYER then
    self:_required("displayPlayerDrawCardScreen")(deckIndex)
    self.saveData:saveDuelStateToSRAM()
    -- Source falls through RestartPracticeDuelTurn before DuelMainInterface.
    self.practice:doAction(self.c.PRACTICEDUEL_PRINT_TURN_INSTRUCTIONS)
  else
    self.duelVars:swapTurn()
    local clairvoyance = self.status:isClairvoyanceActive()
    self.duelVars:swapTurn()
    if clairvoyance then self:_required("displayPlayerDrawCardScreen")(deckIndex) end
  end

  return self.duelInterface:run()
end

function TurnFlow:_finished()
  return self.memory:readSymbol8("wDuelFinished") ~= 0
end

-- One MainDuelLoop iteration through .between_turns. Duel-result presentation
-- still begins at the returned "duel_finished" branch.
function TurnFlow:runTurnCycle()
  self.memory:writeSymbol8("wCurrentDuelMenuItem", 0)
  self.status:updateSubstatusConditionsStartOfTurn()
  self:_required("displayDuelistTurnScreen")()
  -- DisplayDuelistTurnScreen ends with ExchangeRNG in the source.
  local failed, err = self.setup:exchangeRNG()
  if failed then return "transmission_error", err end

  self:handleTurn()

  failed, err = self.setup:exchangeRNG()
  if failed then return "transmission_error", err end
  if self:_finished() then return "duel_finished" end

  self.status:updateSubstatusConditionsEndOfTurn()
  local _, betweenErr = self.status:handleBetweenTurnsEvents()
  if betweenErr then return "transmission_error", betweenErr end
  self:_required("finishQueuedAnimations")()

  failed, err = self.setup:exchangeRNG()
  if failed then return "transmission_error", err end
  if self:_finished() then return "duel_finished" end

  local turns = (self.memory:readSymbol8("wDuelTurns") + 1) % 0x100
  self.memory:writeSymbol8("wDuelTurns", turns)

  if self.memory:readSymbol8("wDuelType") == self.c.DUELTYPE_PRACTICE
      and self.memory:readSymbol8("wIsPracticeDuel") ~= 0
      and turns >= 15 then
    self.memory:writeSymbol8("wDuelResult", self.c.DUEL_WIN)
    return "practice_complete"
  end

  self.duelVars:swapTurn()
  return "next_turn"
end

return TurnFlow
