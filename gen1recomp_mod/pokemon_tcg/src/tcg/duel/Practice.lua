-- Practice-duel action table translated from pret/poketcg
-- src/engine/duel/core.asm. Presentation remains an event adapter; all source
-- state tests, verifier branches, and SRAM rewind behavior live here.

local Practice = {}
Practice.__index = Practice

function Practice.new(memory, duelVars, duelOps, saveData, constants, adapters)
  return setmetatable({
    memory = assert(memory),
    duelVars = assert(duelVars),
    duelOps = assert(duelOps),
    saveData = assert(saveData),
    c = assert(constants),
    adapters = adapters or {},
  }, Practice)
end

function Practice:_event(name, payload)
  local fn = self.adapters.event
  if fn then fn(name, payload or {}) end
end

function Practice:_energyCount(playAreaSlot, energyType)
  self.duelOps:getPlayAreaCardAttachedEnergies(playAreaSlot)
  local base, bank = self.memory:address("wAttachedEnergies")
  return self.memory:read8("wram", base + energyType, bank)
end

function Practice:_verifyPlayerTurnActions()
  local turn = math.floor(self.memory:readSymbol8("wDuelTurns") / 2)
  local card = self.memory:readSymbol8("wTempCardID_ccc2")
  local attack = self.memory:readSymbol8("wSelectedAttack")

  if turn == 0 then
    return card ~= self.c.GOLDEEN
  elseif turn == 1 then
    if card ~= self.c.SEAKING or attack ~= self.c.SECOND_ATTACK then return true end
    return self:_energyCount(self.c.PLAY_AREA_ARENA, self.c.PSYCHIC) == 0
  elseif turn == 2 then
    if self:_energyCount(self.c.PLAY_AREA_BENCH_1, self.c.WATER) == 0 then return true end
    return card ~= self.c.SEAKING
  elseif turn == 3 then
    if self.memory:readSymbol8("wPlayerNumberOfPokemonInPlayArea") ~= 3 then return true end
    if self:_energyCount(self.c.PLAY_AREA_BENCH_2, self.c.WATER) == 0 then return true end
    return card ~= self.c.SEAKING or attack ~= self.c.SECOND_ATTACK
  elseif turn == 4 then
    if self:_energyCount(self.c.PLAY_AREA_ARENA, self.c.WATER) ~= 2 then return true end
    return card ~= self.c.STARYU
  elseif turn == 5 then
    if self:_energyCount(self.c.PLAY_AREA_ARENA, self.c.WATER) ~= 3 then return true end
    if self.memory:readSymbol8("wPlayerArenaCardHP") ~= 40 then return true end
    return card ~= self.c.STARYU
  else
    return card ~= self.c.STARMIE or attack ~= self.c.SECOND_ATTACK
  end
end

-- DoPracticeDuelAction:: return value is source carry as boolean.
function Practice:doAction(action)
  self.memory:writeSymbol8("wPracticeDuelAction", action)
  if self.memory:readSymbol8("wIsPracticeDuel") == 0 then return false end

  if action == self.c.PRACTICEDUEL_DRAW_SEVEN_CARDS then
    self:_event("draw_seven_cards", {})
    return false
  elseif action == self.c.PRACTICEDUEL_PLAY_GOLDEEN then
    local id = self.memory:readSymbol8("wLoadedCard1ID")
    if id == self.c.GOLDEEN then return false end
    self:_event("choose_goldeen", {})
    return true
  elseif action == self.c.PRACTICEDUEL_PUT_STARYU_IN_BENCH then
    self:_event("put_staryu_in_bench", {})
    return false
  elseif action == self.c.PRACTICEDUEL_VERIFY_INITIAL_PLAY then
    if self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) == 2 then return false end
    self:_event("choose_staryu", {})
    return true
  elseif action == self.c.PRACTICEDUEL_DONE_PUTTING_ON_BENCH then
    self.memory:writeSymbol8("wPracticeDuelTurn", 0xff)
    self:_event("done_putting_on_bench", {})
    return false
  elseif action == self.c.PRACTICEDUEL_PRINT_TURN_INSTRUCTIONS then
    local turn = self.memory:readSymbol8("wDuelTurns")
    local previous = self.memory:readSymbol8("wPracticeDuelTurn")
    self.memory:writeSymbol8("wPracticeDuelTurn", turn)
    self:_event("print_turn_instructions", { turn = turn, repeated = previous == turn })
    return false
  elseif action == self.c.PRACTICEDUEL_VERIFY_PLAYER_TURN_ACTIONS then
    local wrong = self:_verifyPlayerTurnActions()
    if not wrong then return false end
    -- fallthrough to PracticeDuel_RepeatInstructions
    self:_event("follow_my_guidance", {})
    self.saveData:loadBackupCurrentDuel()
    return true
  elseif action == self.c.PRACTICEDUEL_REPEAT_INSTRUCTIONS then
    self:_event("follow_my_guidance", {})
    self.saveData:loadBackupCurrentDuel()
    return true
  elseif action == self.c.PRACTICEDUEL_PLAY_STARYU_FROM_BENCH then
    if self.memory:readSymbol8("wDuelTurns") == 7 then
      self:_event("play_staryu_from_bench", {})
    end
    return false
  elseif action == self.c.PRACTICEDUEL_REPLACE_KNOCKED_OUT_POKEMON then
    if self.memory:readSymbol8("hTempPlayAreaLocation_ff9d") == self.c.PLAY_AREA_BENCH_1 then
      return false
    end
    self.duelOps:hasAlivePokemonInBench()
    self:_event("select_staryu", {})
    return true
  end

  error("untranslated PracticeDuelActionTable entry: " .. tostring(action))
end

return Practice
