-- Standalone coordinator for the source-scripted Sam practice duel.
--
-- The full overworld/start-duel presentation is not translated yet. This
-- development entry reproduces the cartridge's duel RAM initialization and
-- MainDuelLoop ordering, then pauses only at player decision points so the
-- translated practice duel can be exercised through a temporary LÖVE UI.

local Runtime = require("src.tcg.duel.Runtime")

local PracticeSession = {}
PracticeSession.__index = PracticeSession

local INSTRUCTION_LABELS = {
  [0] = { "Turn1DrMason1PracticeDuelText", "Turn1DrMason2PracticeDuelText", "Turn1DrMason3PracticeDuelText" },
  [1] = { "Turn2DrMason1PracticeDuelText", "Turn2DrMason2PracticeDuelText", "Turn2DrMason3PracticeDuelText" },
  [2] = { "Turn3DrMason1PracticeDuelText", "Turn3DrMason2PracticeDuelText", "Turn3DrMason3PracticeDuelText" },
  [3] = { "Turn4DrMason1PracticeDuelText", "Turn4DrMason2PracticeDuelText", "Turn4DrMason3PracticeDuelText" },
  [4] = { "Turn5DrMason1PracticeDuelText", "Turn5DrMason2PracticeDuelText" },
  [5] = { "Turn6DrMason1PracticeDuelText", "Turn6DrMason2PracticeDuelText", "Turn6DrMason3PracticeDuelText" },
  [6] = { "Turn7DrMason1PracticeDuelText", "Turn7DrMason2PracticeDuelText" },
  [7] = { "Turn8DrMason1PracticeDuelText", "Turn8DrMason2PracticeDuelText" },
}

local function firstPrizeIndex(mask)
  for i = 0, 5 do
    local flag = 2 ^ i
    if mask % (flag * 2) >= flag then return i end
  end
  return 0
end

function PracticeSession.new(data)
  local self = setmetatable({
    data = assert(data), phase = "boot", message = nil,
    completed = {}, events = {}, instructionText = "", opponentLabel = "SAM",
  }, PracticeSession)

  local initialBenchDone = false
  local adapters = {
    setup = {
      selectInitialActive = function()
        return assert(self:_findHandCard(self.data.constants.GOLDEEN),
          "PracticePlayerDeck starting hand did not contain Goldeen")
      end,
      selectInitialBench = function()
        if initialBenchDone then return nil end
        initialBenchDone = true
        return assert(self:_findHandCard(self.data.constants.STARYU),
          "PracticePlayerDeck starting hand did not contain Staryu")
      end,
      event = function(name, payload) self:_event(name, payload) end,
    },
    practice = {
      event = function(name, payload) self:_practiceEvent(name, payload) end,
    },
    ai = {},
    status = { event = function(name, payload) self:_event(name, payload) end },
    prizes = {
      -- Temporary presentation choice: the source UI asks the player to point
      -- at any remaining prize. Until that menu is translated, use the first
      -- legal cursor position; prize legality/state mutation remains native.
      selectPrizeCard = function(mask) return firstPrizeIndex(mask) end,
      event = function(name, payload) self:_event(name, payload) end,
    },
    knockouts = {
      selectKnockoutReplacement = function()
        local slot = self:_findPlayAreaCard(self.data.constants.STARYU,
          self.data.constants.PLAY_AREA_BENCH_1)
        assert(slot ~= 0xff, "practice replacement expected Staryu on bench")
        return slot
      end,
      event = function(name, payload) self:_event(name, payload) end,
    },
    combat = { event = function(name, payload) self:_event(name, payload) end },
    playerActions = { event = function(name, payload) self:_event(name, payload) end },
    interface = {}, turn = {},
  }

  self.runtime = Runtime.new(data, adapters)
  self:boot()
  return self
end

function PracticeSession:_event(name, payload)
  self.events[#self.events + 1] = { name = name, payload = payload or {} }
  if #self.events > 24 then table.remove(self.events, 1) end
end

function PracticeSession:_practiceEvent(name, payload)
  self:_event(name, payload)
  if name == "print_turn_instructions" then self:_loadInstructionText() end
  if name == "follow_my_guidance" then self.message = "Follow my guidance. Do it again." end
end

function PracticeSession:_findHandCard(cardId)
  if not self.runtime then return nil end
  local r = self.runtime
  local count = r.duelVars:get(self.data.constants.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  for i = 0, count - 1 do
    local deckIndex = r.duelVars:get(self.data.constants.DUELVARS_HAND + i)
    if r.cardData:getCardIDFromDeckIndex(deckIndex) == cardId then return deckIndex end
  end
  return nil
end

function PracticeSession:_findPlayAreaCard(cardId, firstSlot)
  local r, c = self.runtime, self.data.constants
  for slot = firstSlot or c.PLAY_AREA_ARENA, c.MAX_PLAY_AREA_POKEMON - 1 do
    local deckIndex = r.duelVars:get(c.DUELVARS_ARENA_CARD + slot)
    if deckIndex == 0xff then return 0xff end
    if r.cardData:getCardIDFromDeckIndex(deckIndex) == cardId then return slot end
  end
  return 0xff
end

function PracticeSession:_loadInstructionText()
  local turn = math.floor(self.runtime.memory:readSymbol8("wDuelTurns") / 2)
  local labels = INSTRUCTION_LABELS[turn] or {}
  local parts = {}
  for _, label in ipairs(labels) do
    local id = self.data.text.byLabel[label]
    local row = id and self.data.text.byId[id]
    if row and row.plain and row.plain ~= "" then parts[#parts + 1] = row.plain end
  end
  self.instructionText = table.concat(parts, "\n\n")
end

function PracticeSession:boot()
  local r, c = self.runtime, self.data.constants
  r.memory:zeroBootRAM()
  -- The normal save-data initialization path owns these SRAM bytes. They are
  -- the only SRAM reads needed before this standalone duel writes its own
  -- duel snapshots, and fresh-save source initialization sets both to zero.
  r.memory:writeSymbol8("sSkipDelayAllowed", 0)
  r.memory:writeSymbol8("s0a008", 0)

  r.duelVars:setTurn(c.PLAYER_TURN)
  r.memory:writeSymbol8("wPlayerDuelistType", c.DUELIST_TYPE_PLAYER)
  r.memory:writeSymbol8("wOpponentDeckID", c.SAMS_PRACTICE_DECK_ID)

  -- StartDuel_VSAIOpp's LoadPlayerDeck result is immediately replaced by the
  -- Sam special case in LoadOpponentDeck. Skip that transient SRAM read here;
  -- LoadOpponentDeck installs the exact PracticePlayerDeck and Sam deck.
  r.duelVars:swapTurn()
  r.deckLoader:loadOpponentDeck()
  r.duelVars:swapTurn()

  r.memory:writeSymbol8("wDuelInitialPrizes", 2)
  r.core:initVariablesToBeginDuel()
  local failed, err = r.duelSetup:handleDuelSetup()
  assert(not failed, "practice duel setup failed: " .. tostring(err))
  self.phase = "turn"
  self:_beginCurrentTurn()
end

function PracticeSession:_resolveFinishedResult()
  local r, c = self.runtime, self.data.constants
  local finish = r.memory:readSymbol8("wDuelFinished")
  if finish == 0 then return false end
  local playerTurn = r.duelVars:turn() == c.PLAYER_TURN
  local playerWon = (finish == c.TURN_PLAYER_WON and playerTurn)
    or (finish == c.TURN_PLAYER_LOST and not playerTurn)
  r.memory:writeSymbol8("wDuelResult", playerWon and c.DUEL_WIN or c.DUEL_LOSS)
  self.phase = playerWon and "won" or "lost"
  return true
end

function PracticeSession:_beginCurrentTurn()
  local r, c = self.runtime, self.data.constants
  if self:_resolveFinishedResult() then return end

  r.memory:writeSymbol8("wCurrentDuelMenuItem", 0)
  r.status:updateSubstatusConditionsStartOfTurn()
  local failed, err = r.duelSetup:exchangeRNG() -- DisplayDuelistTurnScreen tail
  assert(not failed, tostring(err))

  local dtype = r.duelVars:get(c.DUELVARS_DUELIST_TYPE)
  r.memory:writeSymbol8("wDuelistType", dtype)
  if r.memory:readSymbol8("wDuelTurns") >= 2 then r.core:setAllPlayAreaPokemonCanEvolve() end
  r.core:initVariablesToBeginTurn()

  local deckIndex, carry = r.duelOps:drawCardFromDeck()
  if carry then
    r.memory:writeSymbol8("wDuelFinished", c.TURN_PLAYER_LOST)
    self:_resolveFinishedResult()
    return
  end
  r.memory:writeSymbol8("hTempCardIndex_ff98", deckIndex)
  r.duelOps:addCardToHand(deckIndex)

  if dtype == c.DUELIST_TYPE_PLAYER then
    r.saveData:saveDuelStateToSRAM()
    r.practice:doAction(c.PRACTICEDUEL_PRINT_TURN_INSTRUCTIONS)
    self.completed = {}
    self.message = nil
    self.phase = "player"
    self:_loadInstructionText()
    return
  end

  self.phase = "ai"
  local ok, aiResult = r.ai:doTurn()
  if ok == false then error("Sam scripted turn failed: " .. tostring(aiResult)) end
  r.memory:writeSymbol8("wPlayerAttackingCardIndex", 0xff)
  r.memory:writeSymbol8("wPlayerAttackingAttackIndex", 0xff)
  self:_completeCurrentTurn()
end

function PracticeSession:_completeCurrentTurn()
  local r, c = self.runtime, self.data.constants
  local failed, err = r.duelSetup:exchangeRNG()
  assert(not failed, tostring(err))
  if self:_resolveFinishedResult() then return end

  r.status:updateSubstatusConditionsEndOfTurn()
  local transmission, betweenErr = r.status:handleBetweenTurnsEvents()
  assert(not betweenErr, tostring(betweenErr))
  if transmission and r.memory:readSymbol8("wDuelType") == c.DUELTYPE_LINK then
    error("unexpected link transmission in practice duel")
  end

  failed, err = r.duelSetup:exchangeRNG()
  assert(not failed, tostring(err))
  if self:_resolveFinishedResult() then return end

  local turns = (r.memory:readSymbol8("wDuelTurns") + 1) % 0x100
  r.memory:writeSymbol8("wDuelTurns", turns)
  if r.memory:readSymbol8("wDuelType") == c.DUELTYPE_PRACTICE
      and r.memory:readSymbol8("wIsPracticeDuel") ~= 0 and turns >= 15 then
    r.memory:writeSymbol8("wDuelResult", c.DUEL_WIN)
    self.phase = "won"
    return
  end
  r.duelVars:swapTurn()
  self:_beginCurrentTurn()
end

function PracticeSession:playerTurnNumber()
  return math.floor(self.runtime.memory:readSymbol8("wDuelTurns") / 2)
end

function PracticeSession:actions()
  local c = self.data.constants
  local turn = self:playerTurnNumber()
  if turn == 0 then
    return {
      { key="water_goldeen", label="Attach Water Energy to Goldeen", kind="energy", card=c.WATER_ENERGY, slot=c.PLAY_AREA_ARENA },
      { key="horn", label="Goldeen: Horn Attack", kind="attack", attack=c.FIRST_ATTACK_OR_PKMN_POWER },
    }
  elseif turn == 1 then
    return {
      { key="seaking", label="Evolve Goldeen into Seaking", kind="evolve", card=c.SEAKING, slot=c.PLAY_AREA_ARENA },
      { key="psychic_seaking", label="Attach Psychic Energy to Seaking", kind="energy", card=c.PSYCHIC_ENERGY, slot=c.PLAY_AREA_ARENA },
      { key="waterfall2", label="Seaking: Waterfall", kind="attack", attack=c.SECOND_ATTACK },
    }
  elseif turn == 2 then
    return {
      { key="water_staryu_b", label="Attach Water Energy to Benched Staryu", kind="energy", card=c.WATER_ENERGY, slot=c.PLAY_AREA_BENCH_1 },
      { key="horn3", label="Seaking: Horn Attack", kind="attack", attack=c.FIRST_ATTACK_OR_PKMN_POWER },
    }
  elseif turn == 3 then
    return {
      { key="drowzee", label="Put Drowzee on the Bench", kind="basic", card=c.DROWZEE },
      { key="water_drowzee", label="Attach Water Energy to Drowzee", kind="energy", card=c.WATER_ENERGY, slot=c.PLAY_AREA_BENCH_2 },
      { key="waterfall4", label="Seaking: Waterfall", kind="attack", attack=c.SECOND_ATTACK },
    }
  elseif turn == 4 then
    return {
      { key="water_staryu5", label="Attach Water Energy to Staryu", kind="energy", card=c.WATER_ENERGY, slot=c.PLAY_AREA_ARENA },
      { key="slap5", label="Staryu: Slap", kind="attack", attack=c.FIRST_ATTACK_OR_PKMN_POWER },
    }
  elseif turn == 5 then
    return {
      { key="potion", label="Use Potion on Staryu", kind="potion", slot=c.PLAY_AREA_ARENA },
      { key="water_staryu6", label="Attach Water Energy to Staryu", kind="energy", card=c.WATER_ENERGY, slot=c.PLAY_AREA_ARENA },
      { key="slap6", label="Staryu: Slap", kind="attack", attack=c.FIRST_ATTACK_OR_PKMN_POWER },
    }
  elseif turn == 6 then
    return {
      { key="starmie", label="Evolve Staryu into Starmie", kind="evolve", card=c.STARMIE, slot=c.PLAY_AREA_ARENA },
      { key="freeze7", label="Starmie: Star Freeze", kind="attack", attack=c.SECOND_ATTACK },
    }
  end
  return {
    { key="freeze8", label="Starmie: Star Freeze", kind="attack", attack=c.SECOND_ATTACK },
  }
end

function PracticeSession:availableActions()
  local out = {}
  for _, action in ipairs(self:actions()) do
    if not self.completed[action.key] then out[#out + 1] = action end
  end
  return out
end

function PracticeSession:performAction(action)
  if self.phase ~= "player" then return false, "not_player_turn" end
  local r = self.runtime
  local ok, result
  if action.kind == "energy" then
    ok, result = r.playerActions:attachEnergy(action.card, action.slot)
  elseif action.kind == "evolve" then
    ok, result = r.playerActions:evolve(action.card, action.slot)
  elseif action.kind == "basic" then
    ok, result = r.playerActions:playBasic(action.card)
  elseif action.kind == "potion" then
    ok, result = r.playerActions:usePotion(action.slot)
  elseif action.kind == "attack" then
    ok, result = r.playerActions:attack(action.attack)
  else
    return false, "unknown_action"
  end

  if not ok then
    if result == "repeat_practice" then
      self.completed = {}
      r.practice:doAction(self.data.constants.PRACTICEDUEL_PRINT_TURN_INSTRUCTIONS)
      self:_loadInstructionText()
    end
    self.message = tostring(result)
    return false, result
  end

  self.completed[action.key] = true
  self.message = nil
  if action.kind == "attack" then self:_completeCurrentTurn() end
  return true, result
end

function PracticeSession:repeatTurn()
  if self.phase ~= "player" then return false end
  local c = self.data.constants
  self.runtime.practice:doAction(c.PRACTICEDUEL_REPEAT_INSTRUCTIONS)
  self.runtime.practice:doAction(c.PRACTICEDUEL_PRINT_TURN_INSTRUCTIONS)
  self.completed = {}
  self.message = "Turn restored."
  self:_loadInstructionText()
  return true
end

function PracticeSession:sideState(highByte)
  local r, c = self.runtime, self.data.constants
  local side = { active = nil, bench = {}, prizes = 0, hand = 0 }
  local saved = r.duelVars:turn()
  r.duelVars:setTurn(highByte)
  local count = r.duelVars:get(c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  for slot = 0, math.max(0, count - 1) do
    local deckIndex = r.duelVars:get(c.DUELVARS_ARENA_CARD + slot)
    if deckIndex ~= 0xff then
      local id = r.cardData:getCardIDFromDeckIndex(deckIndex)
      local row = assert(r.cardData:get(id))
      local item = { cardId=id, name=row.name or row.constant or tostring(id),
        hp=r.duelVars:get(c.DUELVARS_ARENA_CARD_HP + slot), maxHP=row.hp, slot=slot }
      if slot == c.PLAY_AREA_ARENA then side.active = item else side.bench[#side.bench + 1] = item end
    end
  end
  side.prizes = r.duelOps:countPrizes()
  side.hand = r.duelVars:get(c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  r.duelVars:setTurn(saved)
  return side
end

return PracticeSession
