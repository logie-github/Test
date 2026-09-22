-- Standalone coordinator for a live, non-scripted duel: real deck vs real
-- AI deck, dynamic per-turn menu (not a fixed script), interactive
-- starting-hand/bench selection, and interactive prize/knockout-
-- replacement choices. Mirrors PracticeSession's boot/turn-loop shape but
-- replaces its hardcoded Sam script with state computed fresh each call.
--
-- SCOPE (v1): the matchup is fixed to two of the ROM's real pre-built
-- decks (Squirtle and Friends vs Charmander and Friends) rather than a
-- deck-picker menu -- both fully validated against the extracted deck
-- lists, just not player-selectable yet. Of the Trainer cards those two
-- decks contain, Bill, Professor Oak, Full Heal, Potion, Switch and Scoop
-- Up are offered; Computer Search, Item Finder, Poke Ball (each need a
-- picker over deck/discard contents) and PlusPower (attack-attachment
-- timing) are real cards in these decks not wired to an interactive
-- picker yet, so the menu does not offer them. Retreat reuses
-- AI:tryToRetreat's execution path (a faithful translation of the
-- cartridge's retreat routine) for which attached energy cards pay the
-- cost -- a disclosed simplification: the source's own player-facing
-- retreat would let you choose which specific energy cards to discard;
-- this picks by the same heuristic the AI uses on its own retreats.
--
-- Why a coroutine: DuelSetup/Prizes/KnockOuts call their player-choice
-- adapters (selectInitialActive, selectInitialBench, selectPrizeCard,
-- selectKnockoutReplacement) synchronously, nested arbitrarily deep inside
-- one boot()/turn call -- including in the middle of the *opponent's*
-- turn, if their attack knocks out your active Pokemon and you need to
-- pick a replacement. A plain call can't pause there and hand control
-- back to a frame-by-frame UI; a coroutine can, at any call depth, and
-- resume exactly where it left off once the UI supplies an answer.

local bit = require("bit")
local Runtime = require("src.tcg.duel.Runtime")

local DuelSession = {}
DuelSession.__index = DuelSession

function DuelSession.new(data)
  local c = data.constants

  local self = setmetatable({
    data = assert(data), phase = "boot", message = nil,
    events = {}, pending = nil, fatalError = nil,
    targetPick = nil, -- in-progress two-step Trainer target selection
    playerRetreatedThisTurn = false,
    opponentLabel = "OPPONENT",
    -- Trainer cards offered through the menu that need a single play-area
    -- or bench slot as their target, and which selection key each expects
    -- (matches EffectCommands' Potion/Switch/ScoopUp _PlayerSelection
    -- handlers exactly).
    targetTrainers = {
      [c.POTION] = { key = "playArea", label = "Heal 20 damage from" },
      [c.SWITCH] = { key = "bench", label = "Switch active with" },
      [c.SCOOP_UP] = { key = "playArea", label = "Return to hand" },
    },
  }, DuelSession)

  local adapters = {
    setup = {
      selectInitialActive = function(turn) return self:_yieldAsPlayer({ kind = "setup_active", turn = turn }) end,
      selectInitialBench = function(turn) return self:_yieldAsPlayer({ kind = "setup_bench", turn = turn }) end,
      event = function(name, payload) self:_event(name, payload) end,
    },
    ai = {},
    status = { event = function(name, payload) self:_event(name, payload) end },
    prizes = {
      selectPrizeCard = function(mask, remaining)
        return self:_yieldAsPlayer({ kind = "prize", mask = mask, remaining = remaining })
      end,
      event = function(name, payload) self:_event(name, payload) end,
    },
    knockouts = {
      selectKnockoutReplacement = function() return self:_yieldAsPlayer({ kind = "knockout" }) end,
      event = function(name, payload) self:_event(name, payload) end,
    },
    combat = { event = function(name, payload) self:_event(name, payload) end },
    playerActions = { event = function(name, payload) self:_event(name, payload) end },
    interface = {}, turn = {},
  }

  self.runtime = Runtime.new(data, adapters)
  self.co = coroutine.create(function() self:_run() end)
  self:_resume()
  return self
end

function DuelSession:_event(name, payload)
  self.events[#self.events + 1] = { name = name, payload = payload or {} }
  if #self.events > 24 then table.remove(self.events, 1) end
end

-- Called only from inside self.co (via the adapter closures above).
function DuelSession:_yield(pending)
  self.pending = pending
  local answer = coroutine.yield()
  self.pending = nil
  return answer
end

-- Setup/prize/knockout picks are genuinely player-facing even when they
-- happen mid-boot or nested inside the opponent's own turn (their attack
-- knocking out your active Pokemon still asks *you* to pick the
-- replacement) -- PracticePlayable only renders a menu when phase=="player",
-- so this makes that true for exactly as long as this one decision is
-- outstanding, then restores whatever phase it interrupted.
function DuelSession:_yieldAsPlayer(pending)
  local previousPhase = self.phase
  self.phase = "player"
  local answer = self:_yield(pending)
  self.phase = previousPhase
  return answer
end

function DuelSession:_resume(value)
  if coroutine.status(self.co) ~= "suspended" then return end
  local ok, err = coroutine.resume(self.co, value)
  if not ok then
    self.fatalError = err
    self.pending = { kind = "error", message = tostring(err) }
  end
end

function DuelSession:_run()
  self:_boot()
  while true do
    if self.phase == "won" or self.phase == "lost" then
      self:_yield({ kind = "duel_over" })
    elseif self.phase == "player" then
      local action = self:_yield({ kind = "await_action" })
      local ok, result = self:_performActionBody(action)
      self.lastResult = { ok = ok, result = result }
      if not ok then
        self.message = tostring(result)
      else
        self.message = nil
        if action.kind == "attack" or action.kind == "power" or action.kind == "end_turn" then
          self:_completeCurrentTurn()
        end
      end
    else
      -- Transient (setup/ai) phases resolve within the same resume call
      -- that reached them; nothing external should observe this branch.
      self:_yield({ kind = "idle" })
    end
  end
end

function DuelSession:_boot()
  local r, c = self.runtime, self.data.constants
  r.memory:zeroBootRAM()
  r.memory:writeSymbol8("sSkipDelayAllowed", 0)
  r.memory:writeSymbol8("s0a008", 0)

  r.duelVars:setTurn(c.PLAYER_TURN)
  r.memory:writeSymbol8("wPlayerDuelistType", c.DUELIST_TYPE_PLAYER)
  r.deckLoader:loadDeck(c.SQUIRTLE_AND_FRIENDS_DECK)

  r.memory:writeSymbol8("wOpponentDeckID", c.CHARMANDER_AND_FRIENDS_DECK_ID)
  r.duelVars:swapTurn()
  r.deckLoader:loadOpponentDeck()
  r.duelVars:swapTurn()

  r.memory:writeSymbol8("wDuelInitialPrizes", 6)
  r.core:initVariablesToBeginDuel()
  local failed, err = r.duelSetup:handleDuelSetup()
  assert(not failed, "duel setup failed: " .. tostring(err))
  self.phase = "turn"
  self:_beginCurrentTurn()
end

function DuelSession:_resolveFinishedResult()
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

function DuelSession:_beginCurrentTurn()
  local r, c = self.runtime, self.data.constants
  if self:_resolveFinishedResult() then return end

  r.memory:writeSymbol8("wCurrentDuelMenuItem", 0)
  r.status:updateSubstatusConditionsStartOfTurn()
  local failed, err = r.duelSetup:exchangeRNG()
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
    self.playerRetreatedThisTurn = false
    self.phase = "player"
    self.message = nil
    return
  end

  self.phase = "ai"
  local ok, aiResult = r.ai:doTurn()
  if ok == false then error("AI turn failed: " .. tostring(aiResult)) end
  r.memory:writeSymbol8("wPlayerAttackingCardIndex", 0xff)
  r.memory:writeSymbol8("wPlayerAttackingAttackIndex", 0xff)
  self:_completeCurrentTurn()
end

function DuelSession:_completeCurrentTurn()
  local r, c = self.runtime, self.data.constants
  local failed, err = r.duelSetup:exchangeRNG()
  assert(not failed, tostring(err))
  if self:_resolveFinishedResult() then return end

  r.status:updateSubstatusConditionsEndOfTurn()
  local transmission, betweenErr = r.status:handleBetweenTurnsEvents()
  assert(not betweenErr, tostring(betweenErr))
  if transmission and r.memory:readSymbol8("wDuelType") == c.DUELTYPE_LINK then
    error("unexpected link transmission in a local duel")
  end

  failed, err = r.duelSetup:exchangeRNG()
  assert(not failed, tostring(err))
  if self:_resolveFinishedResult() then return end

  local turns = (r.memory:readSymbol8("wDuelTurns") + 1) % 0x100
  r.memory:writeSymbol8("wDuelTurns", turns)
  r.duelVars:swapTurn()
  self:_beginCurrentTurn()
end

function DuelSession:playerTurnNumber()
  return math.floor(self.runtime.memory:readSymbol8("wDuelTurns") / 2)
end

-- ===== Shared field-state accessor (same shape PracticePlayable expects) =====

function DuelSession:sideState(highByte)
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
      local item = { cardId = id, name = row.name or row.constant or tostring(id),
        hp = r.duelVars:get(c.DUELVARS_ARENA_CARD_HP + slot), maxHP = row.hp, slot = slot }
      if slot == c.PLAY_AREA_ARENA then side.active = item else side.bench[#side.bench + 1] = item end
    end
  end
  side.prizes = r.duelOps:countPrizes()
  side.hand = r.duelVars:get(c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  r.duelVars:setTurn(saved)
  return side
end

-- ===== Dynamic per-turn / per-pending-decision action menu =====

local function handEntries(session)
  local r, c = session.runtime, session.data.constants
  local count = r.duelVars:get(c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  local out = {}
  for i = 0, count - 1 do
    local deckIndex = r.duelVars:get(c.DUELVARS_HAND + i)
    local cardId = r.cardData:getCardIDFromDeckIndex(deckIndex)
    local row = r.cardData:get(cardId)
    if row then out[#out + 1] = { deckIndex = deckIndex, cardId = cardId, row = row } end
  end
  return out
end

local function playAreaEntries(session, side)
  local out = {}
  if side.active then out[#out + 1] = side.active end
  for _, card in ipairs(side.bench) do out[#out + 1] = card end
  return out
end

function DuelSession:_turnActions()
  local r, c = self.runtime, self.data.constants
  local actions = {}
  local side = self:sideState(c.PLAYER_TURN)
  local field = playAreaEntries(self, side)
  local playAreaCount = r.duelVars:get(c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local alreadyPlayedEnergy = r.memory:readSymbol8("wAlreadyPlayedEnergy") ~= 0

  for _, entry in ipairs(handEntries(self)) do
    local row = entry.row
    if row.kind == "pokemon" then
      if row.stage == c.BASIC then
        if playAreaCount < c.MAX_PLAY_AREA_POKEMON then
          actions[#actions + 1] = { key = "basic:" .. entry.cardId, kind = "basic",
            label = "Play " .. row.name .. " to bench", card = entry.cardId }
        end
      else
        for _, target in ipairs(field) do
          local targetRow = r.cardData:get(target.cardId)
          -- Mirror DuelOps:checkIfCanEvolveInto's CAN_EVOLVE_THIS_TURN
          -- flag check (set by Core:setAllPlayAreaPokemonCanEvolve on turn
          -- 2+): skip offering an evolution the target can't legally take
          -- yet (just played, or it's turn 0/1) instead of letting the
          -- player pick a menu item that's certain to fail.
          local flags = r.duelVars:get(c.DUELVARS_ARENA_CARD_FLAGS + target.slot)
          local canEvolve = bit.band(flags, c.CAN_EVOLVE_THIS_TURN) ~= 0
          if targetRow and canEvolve and row.preEvolutionTextId == targetRow.nameTextId then
            actions[#actions + 1] = { key = "evolve:" .. entry.cardId .. ":" .. target.slot,
              kind = "evolve", label = "Evolve " .. target.name .. " into " .. row.name,
              card = entry.cardId, slot = target.slot }
          end
        end
      end
    elseif row.kind == "energy" and not alreadyPlayedEnergy then
      for _, target in ipairs(field) do
        actions[#actions + 1] = { key = "energy:" .. entry.cardId .. ":" .. target.slot,
          kind = "energy", label = "Attach " .. row.name .. " to " .. target.name,
          card = entry.cardId, slot = target.slot }
      end
    elseif row.kind == "trainer" then
      local targetSpec = self.targetTrainers[entry.cardId]
      if targetSpec then
        actions[#actions + 1] = { key = "trainer_target:" .. entry.cardId, kind = "trainer_target",
          label = "Play " .. row.name, card = entry.cardId }
      elseif entry.cardId == c.PROFESSOR_OAK or entry.cardId == c.BILL
          or entry.cardId == c.FULL_HEAL then
        actions[#actions + 1] = { key = "trainer:" .. entry.cardId, kind = "trainer",
          label = "Play " .. row.name, card = entry.cardId }
      end
      -- Computer Search, Item Finder, Poke Ball and PlusPower need a
      -- deck/discard-contents picker or attack-attachment timing this
      -- session doesn't implement yet -- see the file header.
    end
  end

  if side.active then
    local activeRow = r.cardData:get(side.active.cardId)
    for luaIndex, attack in ipairs(activeRow.attacks or {}) do
      -- row.attacks is a plain 1-indexed Lua array (attacks[1]/attacks[2]),
      -- but Combat/PlayerActions take the source's 0-based attackIndex
      -- (FIRST_ATTACK_OR_PKMN_POWER=0, SECOND_ATTACK=1) and index
      -- row.attacks[attackIndex + 1] with it -- convert here, once.
      local attackIndex = luaIndex - 1
      -- nameTextId==0 marks an unused attack slot (e.g. a Pokemon with
      -- only one real attack) -- Combat:hasEnoughEnergy treats it as
      -- "no_attack" rather than a free 0-cost move; mirror that guard so
      -- the menu never offers a slot that isn't really there.
      if attack.nameTextId ~= 0 then
        local total = 0
        for _, amount in pairs(attack.energy) do total = total + amount end
        local attached = r.duelOps:getPlayAreaCardAttachedEnergies(c.PLAY_AREA_ARENA)
        local kind = attack.category == c.POKEMON_POWER and "power" or "attack"
        local affordable = kind == "power" or attached >= total
        if affordable then
          actions[#actions + 1] = { key = kind .. ":" .. attackIndex, kind = kind,
            label = (attack.name or ("Attack " .. attackIndex)), attack = attackIndex }
        end
      end
    end

    if not self.playerRetreatedThisTurn and #side.bench > 0 then
      local cost = activeRow.retreatCost or 0
      local attached = r.duelOps:getPlayAreaCardAttachedEnergies(c.PLAY_AREA_ARENA)
      if attached >= cost then
        for _, bench in ipairs(side.bench) do
          actions[#actions + 1] = { key = "retreat:" .. bench.slot, kind = "retreat",
            label = "Retreat to " .. bench.name, slot = bench.slot }
        end
      end
    end
  end

  -- Always available: nothing forces an attack every turn (no energy
  -- attached yet, or the player simply doesn't want to), so there must be
  -- an explicit way to end the turn. Listed last so it reads as the
  -- fallback it is.
  actions[#actions + 1] = { key = "end_turn", kind = "end_turn", label = "End Turn" }

  return actions
end

function DuelSession:_setupActions(kind)
  local r, c = self.runtime, self.data.constants
  local actions = {}
  for _, entry in ipairs(handEntries(self)) do
    local row = entry.row
    if row.kind == "pokemon" and row.stage == c.BASIC then
      actions[#actions + 1] = { key = "pick:" .. entry.deckIndex, kind = "setup_pick",
        label = row.name, deckIndex = entry.deckIndex }
    end
  end
  if kind == "setup_bench" then
    actions[#actions + 1] = { key = "done", kind = "setup_done", label = "Done" }
  end
  return actions
end

function DuelSession:_prizeActions(mask)
  local r = self.runtime
  local actions = {}
  for i = 0, 5 do
    local flag = 2 ^ i
    if mask % (flag * 2) >= flag then
      actions[#actions + 1] = { key = "prize:" .. i, kind = "prize_pick",
        label = "Prize card " .. (i + 1), index = i }
    end
  end
  return actions
end

function DuelSession:_knockoutActions()
  local r, c = self.runtime, self.data.constants
  local side = self:sideState(c.PLAYER_TURN)
  local actions = {}
  for _, bench in ipairs(side.bench) do
    if bench.hp > 0 then
      actions[#actions + 1] = { key = "ko:" .. bench.slot, kind = "knockout_pick",
        label = "Send out " .. bench.name, slot = bench.slot }
    end
  end
  return actions
end

function DuelSession:_targetActions(kind)
  local r, c = self.runtime, self.data.constants
  local side = self:sideState(c.PLAYER_TURN)
  local actions = {}
  if kind == "playArea" then
    for _, card in ipairs(playAreaEntries(self, side)) do
      if card.hp < card.maxHP or self.targetPick.card == c.SCOOP_UP then
        actions[#actions + 1] = { key = "target:" .. card.slot, kind = "target_pick",
          label = card.name .. (card.slot == c.PLAY_AREA_ARENA and " (active)" or ""), slot = card.slot }
      end
    end
  elseif kind == "bench" then
    for _, card in ipairs(side.bench) do
      actions[#actions + 1] = { key = "target:" .. card.slot, kind = "target_pick",
        label = card.name, slot = card.slot }
    end
  end
  return actions
end

function DuelSession:availableActions()
  if self.targetPick then
    return self:_targetActions(self.targetPick.awaiting)
  end
  local pending = self.pending
  if pending then
    if pending.kind == "setup_active" then return self:_setupActions("setup_active") end
    if pending.kind == "setup_bench" then return self:_setupActions("setup_bench") end
    if pending.kind == "prize" then return self:_prizeActions(pending.mask) end
    if pending.kind == "knockout" then return self:_knockoutActions() end
  end
  if self.phase == "player" then return self:_turnActions() end
  return {}
end

-- ===== Action execution =====

function DuelSession:_performActionBody(action)
  local r, c = self.runtime, self.data.constants
  if action.kind == "basic" then
    return r.playerActions:playBasic(action.card)
  elseif action.kind == "evolve" then
    return r.playerActions:evolve(action.card, action.slot)
  elseif action.kind == "energy" then
    return r.playerActions:attachEnergy(action.card, action.slot)
  elseif action.kind == "trainer" then
    return r.playerActions:playTrainer(action.card)
  elseif action.kind == "attack" then
    return r.playerActions:attack(action.attack)
  elseif action.kind == "power" then
    return r.playerActions:usePokemonPower(c.PLAY_AREA_ARENA, action.attack)
  elseif action.kind == "retreat" then
    local ok, result = r.ai:tryToRetreat(action.slot)
    if ok then self.playerRetreatedThisTurn = true end
    return ok, result
  elseif action.kind == "end_turn" then
    return true
  end
  return false, "unknown_action"
end

-- Two-step Trainer target selection (Potion/Switch/Scoop Up): the first
-- pick starts self.targetPick, the second (only for Scoop Up on the
-- active slot) asks for a bench replacement too, then performAction runs
-- for real with the gathered selection.
function DuelSession:_beginTargetPick(cardId)
  local spec = assert(self.targetTrainers[cardId])
  self.targetPick = { card = cardId, awaiting = spec.key, selection = {} }
end

function DuelSession:_continueTargetPick(slot)
  local pick = self.targetPick
  pick.selection[pick.awaiting] = slot
  local c = self.data.constants
  if pick.card == c.SCOOP_UP and pick.awaiting == "playArea" and slot == c.PLAY_AREA_ARENA then
    pick.awaiting = "replacement"
    return nil -- still gathering
  end
  self.targetPick = nil
  return self.runtime.playerActions:playTrainer(pick.card, pick.selection)
end

function DuelSession:performAction(action)
  if self.fatalError then return false, "session_error" end

  if self.targetPick then
    if action.kind ~= "target_pick" then return false, "target_pick_required" end
    local ok, result = self:_continueTargetPick(action.slot)
    if ok == nil then return true, "target_pick_continues" end
    self.message = ok and nil or tostring(result)
    return ok, result
  end

  local pending = self.pending
  if pending and pending.kind == "setup_active" then
    if action.kind ~= "setup_pick" then return false, "setup_pick_required" end
    self:_resume(action.deckIndex)
    return true
  elseif pending and pending.kind == "setup_bench" then
    if action.kind == "setup_done" then self:_resume(nil); return true end
    if action.kind ~= "setup_pick" then return false, "setup_pick_required" end
    self:_resume(action.deckIndex)
    return true
  elseif pending and pending.kind == "prize" then
    if action.kind ~= "prize_pick" then return false, "prize_pick_required" end
    self:_resume(action.index)
    return true
  elseif pending and pending.kind == "knockout" then
    if action.kind ~= "knockout_pick" then return false, "knockout_pick_required" end
    self:_resume(action.slot)
    return true
  end

  if self.phase ~= "player" then return false, "not_player_turn" end
  if action.kind == "trainer_target" then
    self:_beginTargetPick(action.card)
    return true, "target_pick_started"
  end

  self:_resume(action)
  if self.lastResult then
    local ok, result = self.lastResult.ok, self.lastResult.result
    self.lastResult = nil
    return ok, result
  end
  return true
end

return DuelSession
