-- Pokopia TCG duel adapter.
-- Uses the executable duel/runtime/AI/effect translations supplied with the TCG package,
-- then presents them through a Pokemon TCG (GBC)-style six-command duel screen.
local Battle = {}

local function loadModule(root, name)
  local path = tostring(root or "") .. "/tcg_engine/" .. name .. ".lua"
  local chunk, err = loadfile(path)
  if not chunk and love and love.filesystem and love.filesystem.load then
    chunk, err = love.filesystem.load(path)
  end
  if not chunk then return nil, err end
  local ok, value = pcall(chunk)
  if not ok then return nil, value end
  return value
end

local function shuffledCopy(src)
  local out = {}
  for i, v in ipairs(src or {}) do out[i] = v end
  for i = #out, 2, -1 do
    local j = love.math.random(1, i)
    out[i], out[j] = out[j], out[i]
  end
  return out
end

local function countsToList(counts)
  local out = {}
  for label, n in pairs(counts or {}) do
    n = math.max(0, math.floor(tonumber(n) or 0))
    if n > 0 then out[#out + 1] = { card = label, count = n } end
  end
  table.sort(out, function(a, b) return tostring(a.card) < tostring(b.card) end)
  return out
end

local function deckCount(counts)
  local n = 0
  for _, c in pairs(counts or {}) do n = n + math.max(0, math.floor(tonumber(c) or 0)) end
  return n
end

local function statusText(mon)
  if not mon then return "" end
  if mon.status and mon.status ~= "NONE" then return mon.status end
  if mon.poison and mon.poison ~= "NONE" then return mon.poison end
  return ""
end

local function energyTotal(mon)
  local n = 0
  for _, v in pairs((mon and mon.energy) or {}) do n = n + (tonumber(v) or 0) end
  return n
end

local function basicEnergyType(label)
  local map = {
    GrassEnergyCard = "Grass", FireEnergyCard = "Fire", WaterEnergyCard = "Water",
    LightningEnergyCard = "Lightning", FightingEnergyCard = "Fighting",
    PsychicEnergyCard = "Psychic",
  }
  return map[label]
end

local function isEnergy(card, label)
  if not card then return false end
  return basicEnergyType(label) ~= nil
    or label == "DoubleColorlessEnergyCard"
    or tostring(card.card_type or ""):find("Energy", 1, true) ~= nil
end

local function safeCardName(cards, label)
  local c = cards[label]
  return c and c.name or tostring(label or "?")
end

local function activeCard(cards, duelist)
  return duelist and duelist.active and cards[duelist.active.card_label] or nil
end

local function playAreaEntries(cards, duelist)
  local out = {}
  if duelist and duelist.active then
    out[#out + 1] = { mon = duelist.active, slot = 0, label = "ACTIVE: " .. safeCardName(cards, duelist.active.card_label) }
  end
  for i, mon in ipairs((duelist and duelist.bench) or {}) do
    out[#out + 1] = { mon = mon, slot = i, label = "BENCH " .. i .. ": " .. safeCardName(cards, mon.card_label) }
  end
  return out
end

function Battle.start(game, ctx)
  local cards = assert(ctx.cards, "TCG battle requires card database")
  local Runtime, err1 = loadModule(ctx.modPath, "engine_runtime")
  local DamageCalc, err2 = loadModule(ctx.modPath, "damage_calculation")
  local AI, err3 = loadModule(ctx.modPath, "ai_engine")
  local Effects, err4 = loadModule(ctx.modPath, "effect_functions_translated")
  local EffectCommands, err5 = loadModule(ctx.modPath, "effect_commands")
  local DuelEngine, err6 = loadModule(ctx.modPath, "duel_engine")
  local AttackAnimations, err7 = loadModule(ctx.modPath, "attack_animations")
  local EffectArgSpecs, err8 = loadModule(ctx.modPath, "effect_arg_specs")
  if not (Runtime and DamageCalc and AI and Effects and EffectCommands and DuelEngine and AttackAnimations and EffectArgSpecs) then
    local TextBox = require("src.render.TextBox")
    local err = err1 or err2 or err3 or err4 or err5 or err6 or err7 or err8 or "unknown error"
    game.stack:push(TextBox.new(game, "TCG DUEL ENGINE ERROR\n" .. tostring(err), ctx.done))
    return
  end
  Effects.__arg_names = EffectArgSpecs

  local Music = require("src.core.Music")
  local playerCounts = ctx.deckCounts or {}
  if deckCount(playerCounts) ~= 60 then
    ctx.say(game, "A duel deck needs\nexactly 60 cards.", ctx.done)
    return
  end

  -- GB1 deck legality is four cards of the same DISPLAY NAME, not four of
  -- each internal card label. Basic Energy is the only unlimited exception;
  -- Double Colorless Energy still obeys the four-card limit.
  local byName = {}
  for label, count in pairs(playerCounts) do
    if not basicEnergyType(label) then
      local c = cards[label]
      local name = c and c.name or tostring(label)
      byName[name] = (byName[name] or 0) + math.max(0, tonumber(count) or 0)
      if byName[name] > 4 then
        ctx.say(game, "Only 4 cards with the\nsame name are allowed.", ctx.done)
        return
      end
    end
  end

  local function getCard(label) return cards[label] end
  local function isBasic(label)
    local c = cards[label]
    return c and c.stage == "Basic" and c.hp ~= nil
  end
  local function isPokemon(label)
    local c = cards[label]
    return c and c.hp ~= nil
  end
  local function preevoLabel(label)
    local c = cards[label]
    if not c or not c.evolves_from then return nil end
    for otherLabel, other in pairs(cards) do
      if other and other.name == c.evolves_from and other.hp then return otherLabel end
    end
    return nil
  end
  local function hasEvolution(label)
    local c = cards[label]
    if not c then return false end
    for _, other in pairs(cards) do
      if other and other.evolves_from == c.name then return true end
    end
    return false
  end

  local basicsInDeck = 0
  for label, n in pairs(playerCounts) do if isBasic(label) then basicsInDeck = basicsInDeck + (tonumber(n) or 0) end end
  if basicsInDeck <= 0 then
    ctx.say(game, "Your deck needs a\nBasic POKeMON.", ctx.done)
    return
  end

  local starterKeys = {}
  for key, def in pairs(ctx.starterDecks or {}) do
    if def and deckCount(def.cards) == 60 then starterKeys[#starterKeys + 1] = key end
  end
  table.sort(starterKeys)
  if #starterKeys == 0 then
    ctx.say(game, "The attendant has no\nvalid duel deck.", ctx.done)
    return
  end
  local opponentKey = starterKeys[love.math.random(1, #starterKeys)]
  local opponentDef = ctx.starterDecks[opponentKey]

  local rt = Runtime.new()
  rt.rng = function() return love.math.random() end
  local setupInfo = DuelEngine.SetupDuel(rt, countsToList(playerCounts), countsToList(opponentDef.cards), isBasic, 6) or {}

  local state = {
    rt = rt,
    menuIndex = 1,
    playerTurns = 0,
    opponentTurns = 0,
    phase = "setup",
    winner = nil,
    opponentDeckName = opponentDef.name or opponentDef.label or "ATTENDANT DECK",
    message = "",
    submode = "main",
    attackRows = nil,
    attackIndex = 1,
  }

  -- Start the packaged Pokemon TCG GBC main duel theme as soon as the duel
  -- setup begins. It continues through Active/Bench selection and the match.
  Music.play(game.data, "Music_TCGDuelTheme1", true, { reason = "tcg_duel" })
  local duelMusicStarted = true

  -- Runtime.new_pokemon lacks the age/stack fields the UI needs for legal evolution and
  -- accurate knockout discard handling, so add them whenever a Pokemon enters play.
  local function newMon(label, turnNo)
    local mon = Runtime.new_pokemon(label)
    mon.stack = { label }
    mon.played_turn = turnNo or 0
    mon.evolved_turn = -1
    return mon
  end
  local function ensureMon(mon)
    if not mon then return nil end
    mon.stack = mon.stack or { mon.card_label }
    mon.played_turn = tonumber(mon.played_turn) or 0
    mon.evolved_turn = tonumber(mon.evolved_turn) or -1
    return mon
  end

  local duelMessage
  local tcgListMenu
  local prizeSelectScreen
  local drawOneCardScreen
  local playAttackPresentation
  local function message(text, after)
    if duelMessage and state.screen and game.stack and game.stack:top() == state.screen then
      duelMessage(text, after)
      return
    end
    local TextBox = require("src.render.TextBox")
    game.stack:push(TextBox.new(game, ctx.safe(text), after))
  end

  local function closeBattle()
    local top = game.stack:top()
    if top == state.screen then game.stack:pop() end
    if duelMusicStarted then
      duelMusicStarted = false
      pcall(Music.restoreMap, game.data, "tcg_duel")
    end
    if ctx.done then ctx.done(state.winner, state.finishReason) end
  end

  local function finish(winner, reason)
    if state.winner then return end
    state.winner = winner
    state.finishReason = reason
    local text
    if winner == "player" then
      text = "DITTO WINS THE DUEL!"
    elseif winner == "opponent" then
      text = "THE ATTENDANT WINS."
    else
      text = "THE DUEL IS A DRAW."
    end
    if reason and reason ~= "" then text = text .. "\n" .. reason end
    message(text, closeBattle)
  end

  local function discardPokemon(duelist, mon)
    if not mon then return end
    local used = false
    for _, label in ipairs(mon.stack or {}) do
      duelist.discard_pile[#duelist.discard_pile + 1] = label
      used = true
    end
    if not used and mon.card_label then duelist.discard_pile[#duelist.discard_pile + 1] = mon.card_label end
    -- Runtime tracks attached Energy as typed counts rather than physical cards. Recreate basic
    -- Energy cards in discard for the normal six types; Double Colorless falls back to Colorless.
    for typ, n in pairs(mon.energy or {}) do
      n = math.max(0, math.floor(tonumber(n) or 0))
      local label = typ .. "EnergyCard"
      if typ == "Colorless" then label = "DoubleColorlessEnergyCard" end
      for _ = 1, n do
        if cards[label] then duelist.discard_pile[#duelist.discard_pile + 1] = label end
      end
    end
  end

  local function choosePrize(duelist, who, after)
    if #duelist.prizes == 0 then if after then after() end return end
    if who == "opponent" then
      local prize = table.remove(duelist.prizes, 1)
      duelist.hand[#duelist.hand + 1] = prize
      if after then after() end
      return
    end
    prizeSelectScreen(game, #duelist.prizes, function(idx)
      idx = math.max(1, math.min(#duelist.prizes, tonumber(idx) or 1))
      local prize = table.remove(duelist.prizes, idx)
      duelist.hand[#duelist.hand + 1] = prize
      message("Took a Prize!\n" .. safeCardName(cards, prize), after)
    end)
  end

  local function promote(duelist, who, after)
    if duelist.active or #duelist.bench == 0 then if after then after() end return end
    if who == "opponent" then
      duelist.active = table.remove(duelist.bench, 1)
      if after then after() end
      return
    end
    local rows = {}
    for i, mon in ipairs(duelist.bench) do
      local c = cards[mon.card_label]
      rows[#rows + 1] = { label = c and c.name or mon.card_label, right = c and ((c.hp - mon.damage) .. "HP") or "", value = i }
    end
    tcgListMenu(game, "CHOOSE ACTIVE", rows, function(row)
      duelist.active = table.remove(duelist.bench, tonumber(row.value) or 1)
      if after then after() end
    end, function() promote(duelist, who, after) end, { footer = "Choose a new Active POKeMON." })
  end

  local function checkWinner()
    local playerWon = #rt.player.prizes == 0
      or (not rt.opponent.active and #rt.opponent.bench == 0)
    local opponentWon = #rt.opponent.prizes == 0
      or (not rt.player.active and #rt.player.bench == 0)
    if playerWon and opponentWon then return "draw", "Both players met a win condition." end
    if playerWon then return "player", #rt.player.prizes == 0 and "All Prize cards taken." or "No opposing POKeMON left." end
    if opponentWon then return "opponent", #rt.opponent.prizes == 0 and "All Prize cards taken." or "No POKeMON left in play." end
    return nil
  end

  local function knockoutSide(side, after)
    local d = side == "player" and rt.player or rt.opponent
    local other = side == "player" and rt.opponent or rt.player
    local mon = d.active
    if not mon then if after then after() end return end
    local c = cards[mon.card_label]
    if not c or mon.damage < (tonumber(c.hp) or 0) then if after then after() end return end
    local name = c.name
    discardPokemon(d, mon)
    d.active = nil
    message(name .. " was Knocked Out!", function()
      choosePrize(other, side == "player" and "opponent" or "player", function()
        local winner, reason = checkWinner()
        if winner then finish(winner, reason); return end
        promote(d, side, after)
      end)
    end)
  end

  local function handleKnockouts(after)
    local pc = rt.player.active and cards[rt.player.active.card_label]
    local oc = rt.opponent.active and cards[rt.opponent.active.card_label]
    local playerKO = pc and rt.player.active.damage >= (tonumber(pc.hp) or 0)
    local opponentKO = oc and rt.opponent.active.damage >= (tonumber(oc.hp) or 0)
    if playerKO and opponentKO then
      local playerMon, opponentMon = rt.player.active, rt.opponent.active
      discardPokemon(rt.player, playerMon); rt.player.active = nil
      discardPokemon(rt.opponent, opponentMon); rt.opponent.active = nil
      message(oc.name .. " was Knocked Out!", function()
        message(pc.name .. " was Knocked Out!", function()
          choosePrize(rt.player, "player", function()
            choosePrize(rt.opponent, "opponent", function()
              local winner, reason = checkWinner()
              if winner then finish(winner, reason); return end
              promote(rt.opponent, "opponent", function()
                promote(rt.player, "player", after)
              end)
            end)
          end)
        end)
      end)
      return
    end
    knockoutSide("opponent", function()
      if state.winner then return end
      knockoutSide("player", function()
        if state.winner then return end
        local winner, reason = checkWinner()
        if winner then finish(winner, reason) else if after then after() end end
      end)
    end)
  end

  local function energyName(typeName)
    return tostring(typeName or "ENERGY"):upper()
  end

  local function attachEnergy(mon, label)
    if not mon then return false end
    local typ = basicEnergyType(label)
    if typ then
      mon.energy[typ] = (mon.energy[typ] or 0) + 1
      return true
    end
    if label == "DoubleColorlessEnergyCard" then
      mon.energy.Colorless = (mon.energy.Colorless or 0) + 2
      return true
    end
    return false
  end

  local function discardRetreatEnergy(mon, cost)
    cost = math.max(0, math.floor(tonumber(cost) or 0))
    if energyTotal(mon) < cost then return false end
    local order = { "Colorless", "Grass", "Fire", "Water", "Lightning", "Fighting", "Psychic" }
    local left = cost
    for _, typ in ipairs(order) do
      while left > 0 and (mon.energy[typ] or 0) > 0 do
        mon.energy[typ] = mon.energy[typ] - 1
        left = left - 1
      end
    end
    return left == 0
  end

  local function attackUsable(mon, attack)
    if not mon or not attack or attack.kind == "Pokemon Power" then return false end
    return AI.CanUseAttack(mon, attack)
  end

  local function clearTurnModifiers(endingSide)
    local ending = endingSide == "player" and rt.player or rt.opponent
    local other = endingSide == "player" and rt.opponent or rt.player
    for _, e in ipairs(playAreaEntries(cards, ending)) do
      e.mon.pluspower_count = 0
      e.mon.substatus1 = e.mon.substatus1 or {}
    end
    -- Defender protects through the opponent's turn; once that opponent's turn ends it expires.
    for _, e in ipairs(playAreaEntries(cards, other)) do e.mon.defender_count = 0 end
  end

  local function drawFor(duelist, who, after)
    if rt:CheckIfDeckIsEmpty(duelist) then
      finish(who == "player" and "opponent" or "player", "No card to draw.")
      return
    end
    local label = duelist.deck[1]
    rt:DrawCardFromDeck(duelist)
    if who == "player" then
      drawOneCardScreen(game, label, #duelist.hand, #duelist.deck, after)
    else
      if after then after() end
    end
  end

  local function beginPlayerTurn()
    if state.winner then return end
    rt.turn_holder = "player"
    state.playerTurns = state.playerTurns + 1
    rt.player.energy_played_this_turn = false
    rt.player.retreated_this_turn = false
    rt.player.confusion_retreat_failed = false
    for _, e in ipairs(playAreaEntries(cards, rt.player)) do
      e.mon.played_this_turn = false
      e.mon.evolved_this_turn = false
    end
    message("DITTO'S TURN", function()
      drawFor(rt.player, "player", function() state.phase = "player" end)
    end)
  end

  local function resolveBetweenTurns(endingSide, after)
    local ending = endingSide == "player" and rt.player or rt.opponent
    local other = endingSide == "player" and rt.opponent or rt.player
    local endingName = endingSide == "player" and "DITTO'S" or "ATTENDANT'S"
    local otherName = endingSide == "player" and "ATTENDANT'S" or "DITTO'S"
    local events = {}
    local function resolveOne(duelist, ownerName, clearParalysis)
      local mon = duelist.active
      if not mon then return end
      local c = cards[mon.card_label]
      local hp = tonumber(c and c.hp) or math.huge
      local name = safeCardName(cards, mon.card_label)
      local poison = mon.poison
      if poison == "POISONED" or poison == "DOUBLE_POISONED" then
        local amount = poison == "DOUBLE_POISONED" and 20 or 10
        mon.damage = (tonumber(mon.damage) or 0) + amount
        events[#events + 1] = name .. " received " .. amount .. " damage\ndue to Poison."
      end
      -- The source skips the Sleep/Paralysis checks when Poison has already
      -- knocked the Active Pokemon out.
      if (tonumber(mon.damage) or 0) >= hp then return end
      if mon.status == "ASLEEP" then
        local woke = rt:TossCoin()
        if woke then mon.status = "NONE" end
        events[#events + 1] = name .. "'s Sleep check.\n" .. (woke and "It is cured of Sleep!" or "It is still Asleep.")
      end
      if clearParalysis and mon.status == "PARALYZED" then
        mon.status = "NONE"
        events[#events + 1] = name .. " is cured\nof Paralysis!"
      end
    end
    -- HandleBetweenTurnsEvents processes the turn holder, swaps, then handles
    -- the non-turn holder. Only the former clears Paralysis.
    resolveOne(ending, endingName, true)
    resolveOne(other, otherName, false)
    if #events == 0 then if after then after() end; return end
    local i = 1
    local function showNext()
      local text = events[i]; i = i + 1
      if text then message(text, showNext) elseif after then after() end
    end
    message("BETWEEN TURNS", showNext)
  end

  local function summarizeAILog(log)
    local lines = {}
    for _, raw in ipairs(log or {}) do
      local s = tostring(raw)
      if s == "Drew a card." then s = "" end
      s = s:gsub("Card", ""):gsub("Lv%d+", "")
      s = s:gsub("([A-Za-z]+)Energy", "%1 Energy")
      if s ~= "" then lines[#lines + 1] = s end
    end
    if #lines == 0 then return "The ATTENDANT finished the turn." end
    return table.concat(lines, "\n")
  end

  local function runOpponentTurn()
    if state.winner then return end
    rt.turn_holder = "opponent"
    state.phase = "opponent"
    state.opponentTurns = state.opponentTurns + 1
    message("ATTENDANT'S TURN", function()
    promote(rt.opponent, "opponent", function()
      local winner, reason = checkWinner()
      if winner then finish(winner, reason); return end
      local log, status, pending = DuelEngine.RunAutomatedTurn(rt, AI, DamageCalc, getCard, isBasic,
        hasEvolution, nil, {
          effects = Effects, effect_commands = EffectCommands,
          new_pokemon_fn = function(label) return newMon(label, state.opponentTurns) end,
          get_preevo_label_fn = preevoLabel, allow_evolution = state.opponentTurns > 1,
          defer_attack = true,
        })
      if status == "deckout" then finish("player", "The ATTENDANT could not draw."); return end
      local function finishOpponentTurn()
        handleKnockouts(function()
        if state.winner then return end
        resolveBetweenTurns("opponent", function()
          handleKnockouts(function()
            clearTurnModifiers("opponent")
            rt.opponent.energy_played_this_turn = false
            rt.opponent.retreated_this_turn = false
            rt.opponent.confusion_retreat_failed = false
            rt.turn_holder = "player"
            beginPlayerTurn()
          end)
        end)
      end)
      end
      local function afterActions(nextStep)
        local summary = summarizeAILog(log)
        message(summary, nextStep)
      end
      if pending then
        local _, _, transaction = DuelEngine.ResolveAttack(rt, DamageCalc, Effects, EffectCommands,
          pending.attacker_mon, pending.attacker_card, pending.attack,
          pending.defender_mon, pending.defender_card, getCard, { pending.attacker_mon },
          { defer_after_cost = true })
        afterActions(function()
          local function announceAttack()
          message(pending.attacker_card.name .. " used\n" .. pending.attack.name .. "!", function()
            local actualDamage, effectiveness = transaction.prepare()
            playAttackPresentation({
              card_label = pending.attacker_mon.card_label,
              attack_index = pending.attack_index,
              attack_name = pending.attack.name,
              damage = actualDamage,
              side = "opponent",
            }, nil, function()
              if transaction then transaction.commit() end
              local result = {}
              if effectiveness and effectiveness.weakness then result[#result + 1] = "Weakness!" end
              if effectiveness and effectiveness.resistance then result[#result + 1] = "Resistance!" end
              local extra = effectLogText(); if extra then result[#result + 1] = extra end
              if #result > 0 then message(table.concat(result,"\n"), finishOpponentTurn)
              else finishOpponentTurn() end
            end)
          end)
          end
          if pending.confusion_check then
            if rt:TossCoin() then
              message("Confusion check... HEADS!", announceAttack)
            else
              pending.attacker_mon.damage = (tonumber(pending.attacker_mon.damage) or 0) + 20
              message("Confusion check... TAILS!\n20 damage to itself.", finishOpponentTurn)
            end
          else
            announceAttack()
          end
        end)
      else
        afterActions(finishOpponentTurn)
      end
    end)
    end)
  end

  local function endPlayerTurn()
    if state.winner then return end
    state.phase = "transition"
    resolveBetweenTurns("player", function()
      handleKnockouts(function()
        if state.winner then return end
        clearTurnModifiers("player")
        rt.player.energy_played_this_turn = false
        rt.player.retreated_this_turn = false
        runOpponentTurn()
      end)
    end)
  end

  local function effectLogText()
    if not rt.log or #rt.log == 0 then return nil end
    local start = math.max(1, #rt.log - 3)
    local out = {}
    for i = start, #rt.log do out[#out + 1] = tostring(rt.log[i]) end
    rt.log = {}
    return table.concat(out, "\n")
  end

  local function choosePlayArea(duelist, title, filter, after, onCancel)
    local rows = {}
    for _, entry in ipairs(playAreaEntries(cards, duelist)) do
      local c = cards[entry.mon.card_label]
      if not filter or filter(entry.mon, c, entry.slot) then
        rows[#rows + 1] = {
          label = entry.label,
          right = c and ((c.hp - entry.mon.damage) .. "HP") or "",
          mon = entry.mon, card = c, slot = entry.slot,
        }
      end
    end
    if #rows == 0 then
      message("There is no valid\nPOKeMON to choose.", onCancel)
      return
    end
    tcgListMenu(game, title, rows, function(row) after(row.mon, row.card, row.slot) end, onCancel, { footer = "A SELECT  B BACK" })
  end

  local function checkCard(card, back)
    if not card then if back then back() end return end
    ctx.openCard(game, card, back)
  end

  local function chooseDeckCard(predicate, title, after, onCancel)
    local rows = {}
    for i, label in ipairs(rt.player.deck) do
      local c = cards[label]
      if c and (not predicate or predicate(c, label)) then
        rows[#rows + 1] = { label = c.name, right = c.card_type, labelKey = label, deckIndex = i }
      end
    end
    if #rows == 0 then message("No matching card\nin the deck.", onCancel); return end
    tcgListMenu(game, title, rows, function(row)
      local idx
      for i, label in ipairs(rt.player.deck) do if label == row.labelKey then idx = i break end end
      if not idx then if onCancel then onCancel() end return end
      local label = table.remove(rt.player.deck, idx)
      rt.player.hand[#rt.player.hand + 1] = label
      rt:ShuffleCardsInDeck(rt.player)
      after(label)
    end, onCancel, { visible = 6 })
  end

  local function discardFirstOtherCards(excludeLabel, count)
    local removed = 0
    local i = #rt.player.hand
    while i >= 1 and removed < count do
      if rt.player.hand[i] ~= excludeLabel then
        rt.player.discard_pile[#rt.player.discard_pile + 1] = table.remove(rt.player.hand, i)
        removed = removed + 1
      end
      i = i - 1
    end
    return removed == count
  end

  local function playTrainer(label, card, back)
    local d, o = rt.player, rt.opponent
    local function consume()
      rt:RemoveCardFromHand(d, label)
      d.discard_pile[#d.discard_pile + 1] = label
    end
    local name = card.name

    if label == "BillCard" then
      consume()
      for _ = 1, 2 do if not rt:CheckIfDeckIsEmpty(d) then rt:DrawCardFromDeck(d) end end
      message("Drew 2 cards.", back); return
    elseif label == "ProfessorOakCard" then
      consume()
      while #d.hand > 0 do d.discard_pile[#d.discard_pile + 1] = table.remove(d.hand) end
      for _ = 1, 7 do if not rt:CheckIfDeckIsEmpty(d) then rt:DrawCardFromDeck(d) end end
      message("Discarded the hand\nand drew 7 cards.", back); return
    elseif label == "FullHealCard" then
      if not d.active then message("No Active POKeMON.", back); return end
      consume(); d.active.status = "NONE"; d.active.poison = "NONE"
      message("The Active POKeMON\nwas fully healed of status.", back); return
    elseif label == "SwitchCard" then
      if #d.bench == 0 then message("There is no POKeMON\non the Bench.", back); return end
      choosePlayArea(d, "SWITCH WITH", function(_, _, slot) return slot > 0 end, function(_, _, slot)
        consume(); rt:SwapArenaWithBenchPokemon(d, slot); message("Switched Active POKeMON.", back)
      end, back); return
    elseif label == "PotionCard" then
      choosePlayArea(d, "USE POTION", function(mon) return mon.damage > 0 end, function(mon)
        consume(); mon.damage = math.max(0, mon.damage - 20); message("Removed 20 damage.", back)
      end, back); return
    elseif label == "PlusPowerCard" then
      if not d.active then message("No Active POKeMON.", back); return end
      consume(); d.active.pluspower_count = (d.active.pluspower_count or 0) + 1
      message("PLUSPOWER attached.\n+10 damage this turn.", back); return
    elseif label == "DefenderCard" then
      if not d.active then message("No Active POKeMON.", back); return end
      consume(); d.active.defender_count = (d.active.defender_count or 0) + 1
      message("DEFENDER attached.\n-20 damage next turn.", back); return
    elseif label == "EnergySearchCard" then
      consume()
      chooseDeckCard(function(_, l) return basicEnergyType(l) ~= nil end, "ENERGY SEARCH", function(found)
        message("Found\n" .. safeCardName(cards, found) .. ".", back)
      end, back); return
    elseif label == "PokeBallCard" then
      consume()
      if love.math.random(0, 1) == 0 then message("TAILS!\nThe search failed.", back); return end
      chooseDeckCard(function(c) return c.stage == "Basic" and c.hp end, "POKe BALL", function(found)
        message("HEADS! Found\n" .. safeCardName(cards, found) .. ".", back)
      end, back); return
    elseif label == "ComputerSearchCard" then
      if #d.hand < 3 then message("You need 2 other cards\nto discard.", back); return end
      consume()
      if not discardFirstOtherCards(nil, 2) then message("Could not discard 2 cards.", back); return end
      chooseDeckCard(nil, "COMPUTER SEARCH", function(found)
        message("Found\n" .. safeCardName(cards, found) .. ".", back)
      end, back); return
    elseif label == "ItemFinderCard" then
      if #d.hand < 3 then message("You need 2 other cards\nto discard.", back); return end
      local trainers = {}
      for i, l in ipairs(d.discard_pile) do
        local c = cards[l]
        if c and c.card_type == "Trainer" and l ~= label then trainers[#trainers + 1] = { label = c.name, key = l, idx = i } end
      end
      if #trainers == 0 then message("No Trainer card\nin the discard pile.", back); return end
      consume(); discardFirstOtherCards(nil, 2)
      tcgListMenu(game, "ITEM FINDER", trainers, function(row)
        local idx
        for i, l in ipairs(d.discard_pile) do if l == row.key then idx = i break end end
        if idx then d.hand[#d.hand + 1] = table.remove(d.discard_pile, idx) end
        message("Recovered\n" .. safeCardName(cards, row.key) .. ".", back)
      end, back); return
    elseif label == "ScoopUpCard" then
      choosePlayArea(d, "SCOOP UP", nil, function(mon, _, slot)
        if slot == 0 and #d.bench == 0 then message("You need another POKeMON\nto become Active.", back); return end
        consume()
        local base = mon.stack and mon.stack[1] or mon.card_label
        d.hand[#d.hand + 1] = base
        if slot == 0 then d.active = nil else table.remove(d.bench, slot) end
        if slot == 0 then promote(d, "player", function() message("POKeMON returned to hand.", back) end)
        else message("POKeMON returned to hand.", back) end
      end, back); return
    elseif label == "ReviveCard" then
      if #d.bench >= 5 then message("The Bench is full.", back); return end
      local rows = {}
      for i, l in ipairs(d.discard_pile) do
        local c = cards[l]
        if c and c.stage == "Basic" and c.hp then rows[#rows + 1] = { label = c.name, key = l, idx = i } end
      end
      if #rows == 0 then message("No Basic POKeMON\nin the discard pile.", back); return end
      tcgListMenu(game, "REVIVE", rows, function(row)
        consume()
        local idx
        for i, l in ipairs(d.discard_pile) do if l == row.key then idx = i break end end
        if idx then table.remove(d.discard_pile, idx) end
        local mon = newMon(row.key, state.playerTurns); local c = cards[row.key]
        local hp = tonumber(c.hp) or 0
        local revivedHP = math.floor((hp / 2) / 10) * 10
        mon.damage = math.max(0, hp - revivedHP)
        d.bench[#d.bench + 1] = mon
        message(c.name .. " was Revived!", back)
      end, back); return
    end

    -- For the remaining Trainer cards, use the translated source effect-command dispatch.
    consume()
    local dispatch = card.effect_fn and EffectCommands.dispatch[card.effect_fn]
    local ran = false
    for _, h in ipairs(dispatch or {}) do
      if h.hook == "EFFECTCMDTYPE_INITIAL_EFFECT_1" or h.hook == "EFFECTCMDTYPE_INITIAL_EFFECT_2"
         or h.hook == "EFFECTCMDTYPE_BEFORE_DAMAGE" then
        local fn = Effects[h["function"]]
        if fn then pcall(fn, rt, d); ran = true end
      end
    end
    local extra = effectLogText()
    message((ran and (name .. " was played.") or (name .. " has no usable effect here.")) .. (extra and ("\n" .. extra) or ""), back)
  end

  local function playEnergy(label, card, back)
    local d = rt.player
    if d.energy_played_this_turn then message("You already attached\nan Energy this turn.", back); return end
    choosePlayArea(d, "ATTACH ENERGY", nil, function(mon, monCard)
      if not attachEnergy(mon, label) then message("That Energy cannot\nbe attached.", back); return end
      rt:RemoveCardFromHand(d, label)
      d.energy_played_this_turn = true
      message("Attached " .. card.name .. "\nto " .. monCard.name .. ".", back)
    end, back)
  end

  local function playBasic(label, card, back)
    local d = rt.player
    if #d.bench >= 5 then message("There is no room\non the Bench.", back); return end
    rt:RemoveCardFromHand(d, label)
    d.bench[#d.bench + 1] = newMon(label, state.playerTurns)
    d.bench[#d.bench].played_this_turn = true
    message("Placed " .. card.name .. "\non the Bench.", back)
  end

  local function playEvolution(label, card, back)
    local d = rt.player
    if state.playerTurns <= 1 then message("POKeMON cannot evolve\non the first turn.", back); return end
    choosePlayArea(d, "EVOLVE WHICH?", function(mon, c)
      return c and card.evolves_from == c.name and mon.played_turn < state.playerTurns and mon.evolved_turn ~= state.playerTurns
    end, function(mon)
      rt:RemoveCardFromHand(d, label)
      mon.stack = mon.stack or { mon.card_label }
      mon.stack[#mon.stack + 1] = label
      mon.card_label = label
      mon.evolved_turn = state.playerTurns
      mon.evolved_this_turn = true
      mon.status = "NONE"; mon.poison = "NONE"
      message("Evolved into\n" .. card.name .. "!", back)
    end, back)
  end


  local function handMenu()
    if state.phase ~= "player" then return end
    local d = rt.player
    if #d.hand == 0 then message("There are no cards\nin your Hand.", function() end); return end
    local rows = {}
    for i, label in ipairs(d.hand) do
      local c = cards[label]
      local shown = c and c.name or label
      local parsedLv = tostring(label):match("Lv(%d+)Card")
      if c and c.hp and (c.level or parsedLv) then
        shown = shown .. " LV" .. tostring(c.level or parsedLv)
      end
      rows[#rows + 1] = { label = shown, key = label, handIndex = i }
    end
    local pname = (game.save and game.save.player and game.save.player.name) or "DITTO"
    tcgListMenu(game, tostring(pname) .. "'S HAND", rows, function(row)
      local c = cards[row.key]
      if not c then handMenu(); return end
      local choices = {
        { label = "PLAY", action = "play" },
        { label = "CHECK", action = "check" },
        { label = "CANCEL", action = "cancel" },
      }
      tcgListMenu(game, c.name, choices, function(ch)
        if ch.action == "check" then checkCard(c, handMenu); return end
        if ch.action == "cancel" then handMenu(); return end
        if c.card_type == "Trainer" then playTrainer(row.key, c, handMenu)
        elseif isEnergy(c, row.key) then playEnergy(row.key, c, handMenu)
        elseif c.hp and c.stage == "Basic" then playBasic(row.key, c, handMenu)
        elseif c.hp and c.evolves_from then playEvolution(row.key, c, handMenu)
        else message("That card cannot be\nplayed right now.", handMenu) end
      end, handMenu, { visible = 3, footer = "PLAY OR CHECK?" })
    end, function() end, {
      status = tostring(#d.hand) .. " CARDS",
      visible = 5,
      footer = "PLEASE SELECT\nHAND.",
      hand = true,
    })
  end

  local function useAttackRow(row)
    local d, o = rt.player, rt.opponent
    if not row or not d.active or not o.active then state.submode = "main" return end
    local card = cards[d.active.card_label]
    if not row.usable then
      message("Not enough Energy\nfor that attack.", function() state.submode = "attack" end)
      return
    end
    state.submode = "main"
    -- INITIAL checks and attack Energy discard precede the Confusion toss in
    -- UseAttackOrPokemonPower. Selection/BEFORE_DAMAGE wait until after the
    -- attack declaration, and HP waits until the animation has completed.
    local _, _, transaction = DuelEngine.ResolveAttack(rt, DamageCalc, Effects, EffectCommands,
      d.active, card, row.attack, o.active, cards[o.active.card_label], getCard,
      { d.active }, { defer_after_cost = true })
    local function beginPresentation()
      local defenderCard = cards[o.active.card_label]
      message(card.name .. " used\n" .. row.attack.name .. "!", function()
      local dmg, eff = transaction.prepare()
      playAttackPresentation({ card_label = d.active.card_label, attack_index = row.attackIndex,
        attack_name = row.attack.name, damage = dmg, side = "player" }, nil, function()
        if transaction then transaction.commit() end
        local result = {}
        if eff and eff.weakness then result[#result + 1] = "Weakness!" end
        if eff and eff.resistance then result[#result + 1] = "Resistance!" end
        local extra = effectLogText(); if extra then result[#result + 1] = extra end
        local function afterResult()
          handleKnockouts(function() if not state.winner then endPlayerTurn() end end)
        end
        if #result > 0 then message(table.concat(result,"\n"), afterResult) else afterResult() end
      end)
      end)
    end
    if d.active.status == "CONFUSED" then
      if love.math.random(0, 1) == 0 then
        d.active.damage = d.active.damage + 20
        message("CONFUSION... TAILS!\n20 damage to itself.", function()
          handleKnockouts(function() if not state.winner then endPlayerTurn() end end)
        end)
      else message("CONFUSION... HEADS!", beginPresentation) end
    else beginPresentation() end
  end

  local function attackMenu()
    local d, o = rt.player, rt.opponent
    if not d.active or not o.active then return end
    if d.active.status == "ASLEEP" or d.active.status == "PARALYZED" then
      message(safeCardName(cards, d.active.card_label) .. " is " .. d.active.status .. "\nand can't attack.", function() end); return
    end
    local card = cards[d.active.card_label]
    local rows = {}
    for i, atk in ipairs(card.attacks or {}) do
      if atk.kind ~= "Pokemon Power" then
        rows[#rows + 1] = {
          label = atk.name,
          attack = atk,
          attackIndex = i,
          usable = attackUsable(d.active, atk),
          damage = tonumber(atk.damage) or 0,
        }
      end
    end
    if #rows == 0 then message("This POKeMON has\nno attack.", function() end); return end
    state.attackRows = rows
    state.attackIndex = math.max(1, math.min(#rows, tonumber(state.attackIndex) or 1))
    state.submode = "attack"
  end

  local function checkList(title, duelist, back)
    local rows = {}
    for _, entry in ipairs(playAreaEntries(cards, duelist)) do
      local c = cards[entry.mon.card_label]
      local hp = c and math.max(0, c.hp - entry.mon.damage) or 0
      local stat = hp .. "HP"
      local st = statusText(entry.mon); if st ~= "" then stat = st end
      rows[#rows + 1] = { label = entry.label, right = stat, card = c, mon = entry.mon }
    end
    if #rows == 0 then message("No POKeMON in play.", back); return end
    tcgListMenu(game, title, rows, function(row)
      if row.card then checkCard(row.card, function() checkList(title, duelist, back) end) else back() end
    end, back, { visible = 5, footer = "A CHECK  B BACK" })
  end

  local function discardList(title, duelist, back)
    local rows = {}
    for i = #duelist.discard_pile, 1, -1 do
      local label = duelist.discard_pile[i]
      local c = cards[label]
      rows[#rows + 1] = { label = c and c.name or label, right = c and c.card_type or "", card = c }
    end
    if #rows == 0 then message("The discard pile\nis empty.", back); return end
    tcgListMenu(game, title, rows, function(row)
      if row.card then checkCard(row.card, function() discardList(title, duelist, back) end) else back() end
    end, back, { visible = 5, footer = "A CHECK  B BACK" })
  end

  local function checkMenu()
    local function yourPlayArea()
      local rows = {
        { label = "YOUR POKEMON", action = "pokemon" },
        { label = "YOUR HAND", action = "hand" },
        { label = "YOUR DISCARD PILE", action = "discard" },
      }
      tcgListMenu(game, "YOUR PLAY AREA", rows, function(row)
        if row.action == "pokemon" then checkList("YOUR POKEMON", rt.player, yourPlayArea)
        elseif row.action == "hand" then handMenu()
        else discardList("YOUR DISCARD", rt.player, yourPlayArea) end
      end, checkMenu, { visible = 3, footer = "CHECK WHAT?" })
    end

    local function oppPlayArea()
      local rows = {
        { label = "OPPONENT'S POKEMON", action = "pokemon" },
        { label = "OPP. DISCARD PILE", action = "discard" },
      }
      tcgListMenu(game, "OPP. PLAY AREA", rows, function(row)
        if row.action == "pokemon" then checkList("OPP. POKEMON", rt.opponent, oppPlayArea)
        else discardList("OPP. DISCARD", rt.opponent, oppPlayArea) end
      end, checkMenu, { visible = 2, footer = "CHECK WHAT?" })
    end

    local function fullPlayArea()
      local rows = {}
      for _, entry in ipairs(playAreaEntries(cards, rt.opponent)) do
        local c = cards[entry.mon.card_label]
        rows[#rows + 1] = { label = "OPP " .. entry.label, right = c and c.name or "", card = c }
      end
      for _, entry in ipairs(playAreaEntries(cards, rt.player)) do
        local c = cards[entry.mon.card_label]
        rows[#rows + 1] = { label = "YOU " .. entry.label, right = c and c.name or "", card = c }
      end
      tcgListMenu(game, "IN PLAY AREA", rows, function(row)
        if row.card then checkCard(row.card, fullPlayArea) end
      end, checkMenu, { visible = 5, footer = "A CHECK  B BACK" })
    end

    local rows = {
      { label = "IN PLAY AREA", action = "all" },
      { label = "YOUR PLAY AREA", action = "you" },
      { label = "OPP. PLAY AREA", action = "opp" },
      { label = "POKEMON CARD GLOSSARY", action = "glossary" },
    }
    tcgListMenu(game, "CHECK", rows, function(row)
      if row.action == "all" then fullPlayArea()
      elseif row.action == "you" then yourPlayArea()
      elseif row.action == "opp" then oppPlayArea()
      else
        message("POKEMON CARD GLOSSARY\nUse CHECK on a card for details.", checkMenu)
      end
    end, function() end, { visible = 4, footer = "PLEASE SELECT." })
  end

  local function powerMenu()
    local rows = {}
    for _, entry in ipairs(playAreaEntries(cards, rt.player)) do
      local c = cards[entry.mon.card_label]
      for _, atk in ipairs((c and c.attacks) or {}) do
        if atk.kind == "Pokemon Power" then rows[#rows + 1] = { label = c.name .. ": " .. atk.name, mon = entry.mon, card = c, power = atk } end
      end
    end
    if #rows == 0 then message("No POKeMON Power\nis available.", function() end); return end
    tcgListMenu(game, "PKMN POWER", rows, function(row)
      if row.mon.status ~= "NONE" then message(row.card.name .. " can't use\nits POKeMON Power now.", powerMenu); return end
      local dispatch = row.power.effect_fn and EffectCommands.dispatch[row.power.effect_fn]
      local ran = false
      rt.turn_holder = "player"
      for _, h in ipairs(dispatch or {}) do
        if h.hook == "EFFECTCMDTYPE_INITIAL_EFFECT_1" or h.hook == "EFFECTCMDTYPE_INITIAL_EFFECT_2"
           or h.hook == "EFFECTCMDTYPE_BEFORE_DAMAGE" or h.hook == "EFFECTCMDTYPE_AFTER_DAMAGE" then
          local fn = Effects[h["function"]]
          if fn then pcall(fn, rt, row.mon); ran = true end
        end
      end
      local extra = effectLogText()
      message(row.card.name .. " used\n" .. row.power.name .. "!" .. (extra and ("\n" .. extra) or (ran and "" or "\nNo effect.")), function() end)
    end, function() end, { visible = 5, footer = "CHOOSE A POKEMON POWER." })
  end

  local function retreatMenu()
    local d = rt.player
    if not d.active then return end
    if d.retreated_this_turn then message("You already retreated\nthis turn.", function() end); return end
    if d.confusion_retreat_failed then message("Unable to retreat due\nto the last Confusion check.", function() end); return end
    if d.active.status == "ASLEEP" or d.active.status == "PARALYZED" then message("The Active POKeMON\ncan't retreat now.", function() end); return end
    if #d.bench == 0 then message("There is no POKeMON\non the Bench.", function() end); return end
    local c = cards[d.active.card_label]
    local cost = tonumber(c.retreat_cost) or 0
    if energyTotal(d.active) < cost then message("Not enough Energy\nto retreat.", function() end); return end
    local rows = {}
    for i, mon in ipairs(d.bench) do
      local bc = cards[mon.card_label]
      rows[#rows + 1] = { label = bc.name, right = (bc.hp - mon.damage) .. "HP", slot = i }
    end
    tcgListMenu(game, "RETREAT", rows, function(row)
      if d.active.status == "CONFUSED" and not rt:TossCoin() then
        d.confusion_retreat_failed = true
        message("Confusion check... TAILS!\nUnable to retreat.", function() end)
        return
      elseif d.active.status == "CONFUSED" then
        message("Confusion check... HEADS!", function()
          discardRetreatEnergy(d.active, cost)
          rt:SwapArenaWithBenchPokemon(d, row.slot)
          d.retreated_this_turn = true
          message("Retreated to\n" .. safeCardName(cards, d.active.card_label) .. ".", function() end)
        end)
        return
      end
      discardRetreatEnergy(d.active, cost)
      rt:SwapArenaWithBenchPokemon(d, row.slot)
      d.retreated_this_turn = true
      message("Retreated to\n" .. safeCardName(cards, d.active.card_label) .. ".", function() end)
    end, function() end, {
      status = "RETREAT COST " .. cost,
      visible = 5,
      footer = "CHOOSE A BENCH POKEMON.",
    })
  end

  local Font = require("src.render.Font")
  local Sound = require("src.core.Sound")
  local screen = { isOpaque = true }
  state.screen = screen

  -- Pokémon TCG GB uses a dedicated 4x8 half-width font and an 8x8
  -- symbol font in duel screens. These are the game's original source
  -- atlases, packaged under assets/tcg/graphics/ui/.
  local halfFont = ctx.image and ctx.image("ui/half_width.png") or nil
  local symbolFont = ctx.image and ctx.image("ui/symbols_font.png") or nil
  local halfQuads, symbolQuads = {}, {}

  local function halfQuad(index)
    if not halfFont then return nil end
    local q = halfQuads[index]
    if q then return q end
    local iw, ih = halfFont:getDimensions()
    -- The PNG stores one 8x8 tile per half-width glyph; glyph ink only
    -- occupies the left half and the text engine advances 4 pixels.
    local col, row = index % 8, math.floor(index / 8)
    q = love.graphics.newQuad(col * 8, row * 8, 8, 8, iw, ih)
    halfQuads[index] = q
    return q
  end

  local function symbolQuad(index)
    if not symbolFont then return nil end
    local q = symbolQuads[index]
    if q then return q end
    local iw, ih = symbolFont:getDimensions()
    local col, row = index % 8, math.floor(index / 8)
    q = love.graphics.newQuad(col * 8, row * 8, 8, 8, iw, ih)
    symbolQuads[index] = q
    return q
  end

  local function tcgAscii(text)
    text = ctx.safe(tostring(text or ""))
    text = text:gsub("é", "e"):gsub("♀", "F"):gsub("♂", "M")
    text = text:gsub("’", "'"):gsub("“", '"'):gsub("”", '"')
    return text
  end

  local function tcgDraw(text, x, y)
    text = tcgAscii(text)
    if not halfFont then
      -- Defensive fallback only; normal packaged builds always have the TCG font.
      love.graphics.push()
      love.graphics.scale(0.5, 1)
      Font.draw(text, x * 2, y)
      love.graphics.pop()
      return
    end
    love.graphics.setColor(1, 1, 1, 1)
    local dx = x
    for i = 1, #text do
      local b = text:byte(i)
      if b == 10 then
        y = y + 8
        dx = x
      else
        if b < 0x20 or b > 0x7f then b = string.byte("?") end
        local q = halfQuad(b - 0x20)
        if q then love.graphics.draw(halfFont, q, dx, y) end
        dx = dx + 4
      end
    end
  end

  local function tcgWidth(text)
    text = tcgAscii(text)
    local longest, cur = 0, 0
    for i = 1, #text do
      if text:byte(i) == 10 then longest = math.max(longest, cur); cur = 0
      else cur = cur + 4 end
    end
    return math.max(longest, cur)
  end

  local function tcgFitText(text, pixels)
    text = tcgAscii(text)
    if tcgWidth(text) <= pixels then return text end
    local maxChars = math.max(1, math.floor(pixels / 4))
    if maxChars <= 1 then return "." end
    return text:sub(1, maxChars - 1) .. "."
  end

  local function drawSymbol(index, x, y)
    if symbolFont then
      local q = symbolQuad(index)
      if q then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(symbolFont, q, x, y)
        return
      end
    end
    -- Minimal fallback if the packaged source sheet cannot be loaded.
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("line", x + 1, y + 1, 5, 5)
  end

  local SYM = {
    SPACE=0x00, FIRE=0x01, GRASS=0x02, LIGHTNING=0x03,
    WATER=0x04, FIGHTING=0x05, PSYCHIC=0x06, COLORLESS=0x07,
    POISONED=0x08, ASLEEP=0x09, CONFUSED=0x0a, PARALYZED=0x0b,
    CURSOR_U=0x0c, POKEMON=0x0d, ATK_DESCR=0x0e, CURSOR_R=0x0f,
    HP=0x10, LV=0x11, E=0x12, PLUSPOWER=0x14, DEFENDER=0x15,
    HP_OK=0x16, HP_NOK=0x17,
    BOX_TOP_L=0x18, BOX_TOP_R=0x19, BOX_BTM_L=0x1a, BOX_BTM_R=0x1b,
    BOX_TOP=0x1c, BOX_BTM=0x1d, BOX_LEFT=0x1e, BOX_RIGHT=0x1f,
    DIGIT_0=0x20, PLUS=0x2b, MINUS=0x2c, CROSS=0x2d,
    SLASH=0x2e, CURSOR_D=0x2f, PRIZE=0x30,
  }

  local function drawSymbolNumber(n, x, y)
    local text = tostring(math.max(0, math.floor(tonumber(n) or 0)))
    for i = 1, #text do
      local d = tonumber(text:sub(i, i)) or 0
      drawSymbol(SYM.DIGIT_0 + d, x, y)
      x = x + 8
    end
  end

  local function drawSourceBox(x, y, wTiles, hTiles)
    local w, h = wTiles * 8, hTiles * 8
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", x, y, w, h)
    drawSymbol(SYM.BOX_TOP_L, x, y)
    drawSymbol(SYM.BOX_TOP_R, x + w - 8, y)
    drawSymbol(SYM.BOX_BTM_L, x, y + h - 8)
    drawSymbol(SYM.BOX_BTM_R, x + w - 8, y + h - 8)
    for xx = x + 8, x + w - 16, 8 do
      drawSymbol(SYM.BOX_TOP, xx, y)
      drawSymbol(SYM.BOX_BTM, xx, y + h - 8)
    end
    for yy = y + 8, y + h - 16, 8 do
      drawSymbol(SYM.BOX_LEFT, x, yy)
      drawSymbol(SYM.BOX_RIGHT, x + w - 8, yy)
    end
  end

  local function drawDuelBox()
    drawSourceBox(0, 96, 20, 6)
  end

  local function drawPlayCountIcon(x, y, count)
    drawSymbol(SYM.POKEMON, x, y)
    drawSymbolNumber(count, x + 8, y)
  end

  local function drawPrizeIcon(x, y, count)
    drawSymbol(SYM.PRIZE, x, y)
    drawSymbolNumber(count, x + 8, y)
  end

  local ENERGY_SYMBOL = {
    Fire=SYM.FIRE, Grass=SYM.GRASS, Lightning=SYM.LIGHTNING,
    Water=SYM.WATER, Fighting=SYM.FIGHTING, Psychic=SYM.PSYCHIC,
    Colorless=SYM.COLORLESS,
  }
  local function drawEnergyGlyph(typ, x, y)
    drawSymbol(ENERGY_SYMBOL[typ] or SYM.COLORLESS, x, y)
  end

  local function cardForListRow(row)
    if type(row) ~= "table" then return nil end
    if row.card then return row.card end
    if row.key then return cards[row.key] end
    return nil
  end

  local function drawCardListIcon(row, x, y)
    local c = cardForListRow(row)
    if not c then return false end
    local typ = c.card_type
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", x, y, 16, 16)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("line", x, y, 15, 15)
    if typ == "Trainer" then
      tcgDraw("T", x + 6, y + 4)
    elseif isEnergy(c, row.key) then
      local e = basicEnergyType(row.key) or "Colorless"
      local idx = ENERGY_SYMBOL[e] or SYM.COLORLESS
      if symbolFont then
        local q = symbolQuad(idx)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(symbolFont, q, x, y, 0, 2, 2)
      end
    else
      local idx = ENERGY_SYMBOL[typ] or SYM.COLORLESS
      if symbolFont then
        local q = symbolQuad(idx)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(symbolFont, q, x, y, 0, 2, 2)
      end
    end
    return true
  end

  local function footerLines(text)
    text = tcgAscii(text or "")
    local lines = {}
    for explicit in (text .. "\n"):gmatch("(.-)\n") do
      if #explicit <= 34 then
        lines[#lines + 1] = explicit
      else
        local line = ""
        for word in explicit:gmatch("%S+") do
          if #line == 0 then line = word
          elseif #line + 1 + #word <= 34 then line = line .. " " .. word
          else lines[#lines + 1] = line; line = word end
        end
        if line ~= "" then lines[#lines + 1] = line end
      end
    end
    return lines
  end

  -- Source-style list used by HAND, CHECK, RETREAT, POKEMON POWER and
  -- discard/play-area lists. It mirrors the GB1 five-row card list layout
  -- rather than falling back to the RPG's Start/Bag menu.
  tcgListMenu = function(game_, title, rows, onPick, onCancel, opts)
    opts = opts or {}
    rows = rows or {}
    local list = {
      isOpaque = true,
      index = 1,
      scroll = 0,
      rows = rows,
      visible = math.max(1, math.min(5, tonumber(opts.visible) or 5)),
    }

    local function clamp()
      local n = #list.rows
      if n <= 0 then list.index, list.scroll = 1, 0; return end
      list.index = math.max(1, math.min(n, list.index))
      if list.index - list.scroll > list.visible then list.scroll = list.index - list.visible end
      if list.index - list.scroll < 1 then list.scroll = list.index - 1 end
    end

    function list:update()
      local input = game_.input
      local n = #self.rows
      if input:wasPressed("up") and n > 0 then
        self.index = self.index > 1 and self.index - 1 or n
        clamp(); Sound.play(game_.data, "Press_AB")
      elseif input:wasPressed("down") and n > 0 then
        self.index = self.index < n and self.index + 1 or 1
        clamp(); Sound.play(game_.data, "Press_AB")
      elseif input:wasPressed("b") then
        Sound.play(game_.data, "Press_AB")
        if opts.cancelable ~= false then
          game_.stack:pop()
          if onCancel then onCancel() end
        end
      elseif input:wasPressed("a") and n > 0 then
        Sound.play(game_.data, "Press_AB")
        local row, idx = self.rows[self.index], self.index
        game_.stack:pop()
        if onPick then onPick(row, idx) end
      elseif input:wasPressed("select") and opts.hand and n > 1 then
        -- GB1 sorts the Hand when SELECT is pressed. Preserve each row's
        -- card identity while grouping Energy, Pokemon, then Trainer cards.
        table.sort(self.rows, function(a, b)
          local ca, cb = cardForListRow(a), cardForListRow(b)
          local function rank(c, row)
            if c and isEnergy(c, row and row.key) then return 1 end
            if c and c.hp then return 2 end
            if c and c.card_type == "Trainer" then return 3 end
            return 4
          end
          local ra, rb = rank(ca, a), rank(cb, b)
          if ra ~= rb then return ra < rb end
          return tostring((ca and ca.name) or a.label or "") < tostring((cb and cb.name) or b.label or "")
        end)
        self.index, self.scroll = 1, 0
      end
    end

    function list:draw()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      drawSourceBox(0, 0, 20, 14)
      local counter
      if opts.hand then counter = tostring(self.index) .. "/" .. tostring(#self.rows)
      elseif opts.status then counter = tostring(opts.status) end
      if counter and counter ~= "" then counter = tcgFitText(counter, 64) end
      local counterWidth = counter and tcgWidth(counter) or 0
      local titleBudget = counter and math.max(32, 136 - counterWidth - 8) or 136
      tcgDraw(tcgFitText(title or "", titleBudget), 8, 8)
      if counter and counter ~= "" then
        tcgDraw(counter, 144 - counterWidth, 8)
      end

      local firstY = 24
      for slot = 1, self.visible do
        local idx = self.scroll + slot
        local row = self.rows[idx]
        if not row then break end
        local y = firstY + (slot - 1) * 16
        local hasIcon = drawCardListIcon(row, 16, y)
        local labelX = hasIcon and 36 or 24
        local right = row.right and tcgFitText(tcgAscii(row.right), 48) or nil
        local rightX = right and (144 - tcgWidth(right)) or 144
        local budget = math.max(16, rightX - labelX - (right and 4 or 0))
        tcgDraw(tcgFitText(row.label or "", budget), labelX, y + 4)
        if right then tcgDraw(right, rightX, y + 4) end
        if idx == self.index then drawSymbol(SYM.CURSOR_R, 8, y + 4) end
      end

      if self.scroll > 0 then drawSymbol(SYM.CURSOR_U, 144, 16) end
      if self.scroll + self.visible < #self.rows then drawSymbol(SYM.CURSOR_D, 144, 96) end

      drawSourceBox(0, 104, 20, 5)
      local footer = opts.footer
      if footer == nil then footer = "A SELECT  B BACK" end
      local lines = footerLines(footer)
      if #lines > 0 then tcgDraw(lines[1], 8, 112) end
      if #lines > 1 then tcgDraw(lines[2], 8, 128) end
      love.graphics.setColor(1, 1, 1, 1)
    end

    game_.stack:push(list)
    return list
  end

  -- GB1 uses a dedicated face-down Prize selection screen rather than a
  -- generic text list.  Keep the six cards in a 3x2 table and select the
  -- physical position with the source cursor; B cannot cancel a required
  -- Prize take.
  prizeSelectScreen = function(game_, count, onPick)
    count = math.max(1, math.min(6, tonumber(count) or 1))
    local view = { isOpaque = true, index = 1 }
    local function colRow(index)
      return (index - 1) % 3, math.floor((index - 1) / 3)
    end
    local function indexFor(col, row)
      local idx = row * 3 + col + 1
      if idx > count then return nil end
      return idx
    end
    function view:update()
      local input = game_.input
      local col, row = colRow(self.index)
      local nextIndex
      if input:wasPressed("left") then
        for step = 1, 3 do
          local c = (col - step) % 3
          nextIndex = indexFor(c, row)
          if nextIndex then break end
        end
      elseif input:wasPressed("right") then
        for step = 1, 3 do
          local c = (col + step) % 3
          nextIndex = indexFor(c, row)
          if nextIndex then break end
        end
      elseif input:wasPressed("up") or input:wasPressed("down") then
        local other = row == 0 and 1 or 0
        nextIndex = indexFor(col, other)
        if not nextIndex then
          for c = math.min(col,2), 0, -1 do
            nextIndex = indexFor(c, other)
            if nextIndex then break end
          end
        end
      elseif input:wasPressed("a") then
        Sound.play(game_.data, "Press_AB")
        local picked = self.index
        if game_.stack:top() == self then game_.stack:pop() end
        if onPick then onPick(picked) end
        return
      elseif input:wasPressed("b") then
        -- A Prize must be taken after a Knock Out; the source screen does not
        -- permit escaping the selection.
        return
      end
      if nextIndex and nextIndex ~= self.index then
        self.index = nextIndex
        Sound.play(game_.data, "Press_AB")
      end
    end
    function view:draw()
      love.graphics.setColor(1,1,1,1)
      love.graphics.rectangle("fill",0,0,160,144)
      drawSourceBox(0,0,20,14)
      tcgDraw("TAKE A PRIZE",8,8)
      local status = "PRIZES LEFT " .. tostring(count)
      tcgDraw(status,144-tcgWidth(status),16)
      for i=1,count do
        local col,row=colRow(i)
        local x=28+col*44
        local y=36+row*32
        love.graphics.setColor(1,1,1,1)
        love.graphics.rectangle("fill",x,y,16,16)
        love.graphics.setColor(0,0,0,1)
        love.graphics.rectangle("line",x,y,15,15)
        love.graphics.rectangle("line",x+2,y+2,11,11)
        drawSymbol(SYM.PRIZE,x+4,y+4)
        if i==self.index then drawSymbol(SYM.CURSOR_R,x-12,y+4) end
      end
      drawSourceBox(0,104,20,5)
      tcgDraw("Choose a Prize card.",8,112)
      tcgDraw("A TAKE",8,128)
      love.graphics.setColor(1,1,1,1)
    end
    game_.stack:push(view)
  end

  duelMessage = function(text, after)
    local lines = footerLines(text)
    local pages = {}
    if #lines == 0 then lines = { "" } end
    for i = 1, #lines, 2 do pages[#pages + 1] = { lines[i], lines[i + 1] } end
    local overlay = { isOpaque = false, page = 1 }
    function overlay:update()
      local input = game.input
      if input:wasPressed("a") or input:wasPressed("b") then
        Sound.play(game.data, "Press_AB")
        if self.page < #pages then self.page = self.page + 1
        else
          game.stack:pop()
          if after then after() end
        end
      end
    end
    function overlay:draw()
      drawDuelBox()
      local pg = pages[self.page] or {}
      if pg[1] then tcgDraw(pg[1], 8, 112) end
      if pg[2] then tcgDraw(pg[2], 8, 128) end
      if self.page < #pages then drawSymbol(SYM.CURSOR_D, 144, 136) end
    end
    game.stack:push(overlay)
  end

  -- Beginning-of-turn draw screen.  GB1 explicitly enters a DRAW_CARDS
  -- screen before DrawCardFromDeck; this keeps that phase visible instead of
  -- collapsing it into an RPG dialogue line.  Character portraits are omitted
  -- by design; portrait assets are reserved for dialogue in Pokopia.
  drawOneCardScreen = function(game_, label, handCount, deckCountLeft, after)
    local view = { isOpaque = true, delay = 0 }
    function view:update()
      self.delay = self.delay + 1
      local input = game_.input
      if self.delay >= 10 and (input:wasPressed("a") or input:wasPressed("b")) then
        Sound.play(game_.data, "Press_AB")
        if game_.stack:top() == self then game_.stack:pop() end
        if after then after() end
      end
    end
    function view:draw()
      love.graphics.setColor(1,1,1,1)
      love.graphics.rectangle("fill",0,0,160,144)
      drawSourceBox(0,0,20,14)
      tcgDraw("DRAW 1 CARD",8,8)
      local c = cards[label]
      local img = ctx.cardImage and ctx.cardImage(label) or nil
      if img then
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(img,48,24)
      end
      tcgDraw(tcgFitText((c and c.name) or safeCardName(cards,label),144),8,80)
      tcgDraw("HAND",8,96)
      drawSymbolNumber(handCount or 0,32,96)
      tcgDraw("DECK",96,96)
      drawSymbolNumber(deckCountLeft or 0,120,96)
      drawSourceBox(0,104,20,5)
      tcgDraw("A CONTINUE",8,120)
      love.graphics.setColor(1,1,1,1)
    end
    game_.stack:push(view)
  end

  -- Opaque source-style setup message. The original game performs duel setup
  -- on the same 160x144 TCG canvas rather than dropping back into the RPG
  -- dialogue renderer, so all pre-duel notices use the TCG font/frame too.
  local function setupNotice(text, after)
    local lines = footerLines(text)
    if #lines == 0 then lines = { "" } end
    local pages = {}
    for i = 1, #lines, 2 do pages[#pages + 1] = { lines[i], lines[i + 1] } end
    local notice = { isOpaque = true, page = 1 }
    function notice:update()
      local input = game.input
      if input:wasPressed("a") or input:wasPressed("b") then
        Sound.play(game.data, "Press_AB")
        if self.page < #pages then self.page = self.page + 1
        else
          game.stack:pop()
          if after then after() end
        end
      end
    end
    function notice:draw()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      drawSourceBox(0, 104, 20, 5)
      local pg = pages[self.page] or {}
      if pg[1] then tcgDraw(pg[1], 8, 112) end
      if pg[2] then tcgDraw(pg[2], 8, 128) end
      if self.page < #pages then drawSymbol(SYM.CURSOR_D, 144, 136) end
      love.graphics.setColor(1, 1, 1, 1)
    end
    game.stack:push(notice)
  end

  -- Text-driven coin toss on the TCG canvas. It follows the source setup
  -- ordering (place Pokemon -> Prize cards -> coin toss -> first turn) and
  -- avoids introducing non-source portrait art.
  local function setupCoinToss(heads, after)
    local toss = { isOpaque = true, frames = 0, settled = false }
    function toss:update()
      self.frames = self.frames + 1
      if self.frames >= 42 then self.settled = true end
      if self.settled and (game.input:wasPressed("a") or game.input:wasPressed("b")) then
        Sound.play(game.data, "Press_AB")
        game.stack:pop()
        if after then after() end
      end
    end
    function toss:draw()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      drawSourceBox(2, 2, 16, 10)
      love.graphics.setColor(0, 0, 0, 1)
      tcgDraw("COIN TOSS", 60, 24)
      love.graphics.circle("line", 80, 62, 24)
      local face
      if self.settled then face = heads and "HEADS" or "TAILS"
      else face = (math.floor(self.frames / 4) % 2 == 0) and "HEADS" or "TAILS" end
      local fw = tcgWidth(face)
      tcgDraw(face, 80 - math.floor(fw / 2), 58)
      drawSourceBox(0, 104, 20, 5)
      if self.settled then
        tcgDraw((heads and "HEADS! DITTO" or "TAILS! ATTENDANT"), 8, 112)
        tcgDraw("PLAYS FIRST.", 8, 128)
      else
        tcgDraw("TOSSING THE COIN...", 8, 120)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
    game.stack:push(toss)
  end

  local ENERGY_ORDER = { "Grass", "Fire", "Water", "Lightning", "Fighting", "Psychic", "Colorless" }
  local function drawAttachedEnergy(mon, x, y)
    local n = 0
    for _, typ in ipairs(ENERGY_ORDER) do
      local count = math.max(0, math.floor(tonumber((mon.energy or {})[typ]) or 0))
      for _ = 1, count do
        local col = n % 9
        local row = math.floor(n / 9)
        drawEnergyGlyph(typ, x + col * 8, y + row * 8)
        n = n + 1
        if n >= 18 then return end
      end
    end
  end

  local function drawHP(mon, card, x, y)
    local maxHp = math.max(10, math.floor(tonumber(card.hp) or 10))
    local current = math.max(0, maxHp - math.floor(tonumber(mon.damage) or 0))
    local total = math.max(1, math.ceil(maxHp / 10))
    local ok = math.max(0, math.ceil(current / 10))
    -- The source HUD caps each row at six counters, then continues below it.
    for i = 1, total do
      local col = (i - 1) % 6
      local row = math.floor((i - 1) / 6)
      drawSymbol(i <= ok and SYM.HP_OK or SYM.HP_NOK,
                 x + col * 8, y + row * 8)
    end
  end

  local STATUS_SYMBOL = {
    POISONED=SYM.POISONED, DOUBLE_POISONED=SYM.POISONED,
    ASLEEP=SYM.ASLEEP, CONFUSED=SYM.CONFUSED, PARALYZED=SYM.PARALYZED,
  }
  local function drawStatus(mon, x, y)
    local st = statusText(mon)
    local sym = STATUS_SYMBOL[st]
    if sym then drawSymbol(sym, x, y) end
  end

  local function cardTitle(card)
    local name = card and card.name or "?"
    if card and card.level then name = name .. " LV" .. tostring(card.level) end
    return name
  end

  local function drawArena(duelist, isOpponent)
    local mon = duelist.active
    if not mon then return end
    ensureMon(mon)
    local card = cards[mon.card_label]
    if not card then return end
    -- Duel art is the card's own Pokemon TCG GB illustration, exactly the
    -- asset family the source duel screen uses.  Pokopia character portraits
    -- are dialogue-only and must never substitute for card/battle artwork.
    local img = ctx.cardImage(mon.card_label)
    if img then
      love.graphics.setColor(1, 1, 1, 1)
      if isOpponent then love.graphics.draw(img, 96, 8)
      else love.graphics.draw(img, 0, 40) end
    end

    love.graphics.setColor(0, 0, 0, 1)
    local title = cardTitle(card)
    if isOpponent then
      title = tcgFitText(title, 96)
      local w = tcgWidth(title)
      local x = math.max(56, 160 - w)
      drawEnergyGlyph(card.card_type or "Colorless", math.max(48, x - 8), 0)
      tcgDraw(title, x, 0)
      drawPlayCountIcon(8, 0, 1 + #duelist.bench)
      drawPrizeIcon(24, 0, #duelist.prizes)
      drawSymbol(SYM.E, 8, 8)
      drawSymbol(SYM.HP, 8, 16)
      drawAttachedEnergy(mon, 24, 8)
      drawHP(mon, card, 24, 16)
      drawStatus(mon, 88, 48)
    else
      title = tcgFitText(title, 104)
      drawEnergyGlyph(card.card_type or "Colorless", 0, 88)
      tcgDraw(title, 8, 88)
      drawPlayCountIcon(120, 88, 1 + #duelist.bench)
      drawPrizeIcon(136, 88, #duelist.prizes)
      drawSymbol(SYM.E, 72, 64)
      drawSymbol(SYM.HP, 72, 72)
      drawAttachedEnergy(mon, 88, 64)
      drawHP(mon, card, 88, 72)
      drawStatus(mon, 64, 40)
    end
  end

  local function drawSeparator()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.setLineWidth(2)
    love.graphics.line(0, 32, 88, 32)
    love.graphics.line(88, 32, 88, 40)
    love.graphics.line(88, 40, 80, 40)
    love.graphics.line(80, 40, 80, 56)
    love.graphics.line(80, 56, 160, 56)
    love.graphics.setLineWidth(1)
  end

  local menuPos = {
    [1] = { cursorX = 16, textX = 24, y = 112, text = "HAND" },
    [2] = { cursorX = 64, textX = 72, y = 112, text = "CHECK" },
    [3] = { cursorX = 112, textX = 120, y = 112, text = "RETREAT" },
    [4] = { cursorX = 16, textX = 24, y = 128, text = "ATTACK" },
    [5] = { cursorX = 64, textX = 72, y = 128, text = "PKMN POWER" },
    [6] = { cursorX = 112, textX = 120, y = 128, text = "DONE" },
  }

  -- Execute the decomp's ordered ATK_ANIM_* command list on the duel canvas.
  -- Damage/effects are committed at the first impact command, matching
  -- PlayAttackAnimation_DealAttackDamage's animation-before-SubtractHP order.
  local attackSpriteCache = {}
  local function attackSprite(duelAnim)
    local filename = AttackAnimations.assetFor(duelAnim)
    if attackSpriteCache[filename] ~= nil then return attackSpriteCache[filename] or nil end
    local path = tostring(ctx.modPath) .. "/assets/tcg/graphics/duel_anims/" .. filename
    local ok, img = pcall(love.graphics.newImage, path)
    attackSpriteCache[filename] = ok and img or false
    return ok and img or nil
  end

  playAttackPresentation = function(event, resolveAtImpact, after)
    local animId, sequence = AttackAnimations.forAttack(event.card_label, event.attack_index)
    if #sequence == 0 then sequence = { { target="opponent", id="DUEL_ANIM_HIT" } } end
    local view = { isOpaque=false, step=1, tick=0, impacted=false, animId=animId }
    local function impact()
      if view.impacted then return end
      view.impacted = true
      Sound.play(game.data, "Damage")
      if resolveAtImpact then resolveAtImpact() end
    end
    function view:update()
      self.tick = self.tick + 1
      local current = sequence[self.step]
      local id = current and current.id or ""
      if not self.impacted and (id:find("HIT",1,true) or id == "DUEL_ANIM_SHOW_DAMAGE"
          or self.step >= math.max(2, math.ceil(#sequence * 0.55))) then impact() end
      if self.tick >= 10 then
        self.tick = 0
        self.step = self.step + 1
        if self.step > #sequence then
          impact()
          if game.stack:top() == self then game.stack:pop() end
          if after then after() end
        end
      end
    end
    function view:draw()
      local current = sequence[self.step]
      if not current then return end
      local attackerIsPlayer = event.side == "player"
      local targets = attackerIsPlayer
        and { player={32,64}, opponent={128,32}, normal={80,48} }
        or  { player={128,32}, opponent={32,64}, normal={80,48} }
      local pos = targets[current.target] or targets.normal
      local id = current.id or ""
      if id == "DUEL_ANIM_FLASH" and math.floor(self.tick / 2) % 2 == 0 then
        love.graphics.setColor(0,0,0,0.75)
        love.graphics.rectangle("fill",0,0,160,96)
      end
      local img = attackSprite(id)
      if img then
        local iw, ih = img:getDimensions()
        local frameH = math.min(iw, ih)
        if frameH >= 8 then
          local frames = math.max(1, math.floor(ih / frameH))
          local frame = math.floor(self.tick / 2) % frames
          local quad = love.graphics.newQuad(0, frame * frameH, iw, frameH, iw, ih)
          love.graphics.setColor(1,1,1,1)
          love.graphics.draw(img, quad, pos[1] - iw/2, pos[2] - frameH/2)
        end
      elseif id:find("SHAKE",1,true) then
        love.graphics.setColor(0,0,0,0.25)
        love.graphics.rectangle("fill",0,0,160,96)
      end
      drawSourceBox(0,96,20,6)
      tcgDraw(tcgFitText(event.attack_name or animId,144),8,112)
      local damageText = tostring(math.max(0, tonumber(event.damage) or 0)) .. " DAMAGE"
      tcgDraw(self.impacted and damageText or "ATTACK!",8,128)
      love.graphics.setColor(1,1,1,1)
    end
    game.stack:push(view)
  end

  -- Source menu order is HAND / CHECK / RETREAT on row 1 and
  -- ATTACK / PKMN POWER / DONE on row 2.
  local mainActions = {
    [1] = handMenu, [2] = checkMenu, [3] = retreatMenu,
    [4] = attackMenu, [5] = powerMenu, [6] = endPlayerTurn,
  }

  local function moveMainCursor(dir)
    local idx = state.menuIndex
    local row = idx <= 3 and 1 or 2
    local col = ((idx - 1) % 3) + 1
    if dir == "up" or dir == "down" then row = row == 1 and 2 or 1
    elseif dir == "left" then col = col == 1 and 3 or col - 1
    elseif dir == "right" then col = col == 3 and 1 or col + 1 end
    state.menuIndex = (row - 1) * 3 + col
  end

  function screen:update()
    if state.phase ~= "player" or state.winner then return end
    local input = game.input
    if state.submode == "attack" then
      local rows = state.attackRows or {}
      if #rows == 0 then state.submode = "main" return end
      if input:wasPressed("up") then
        state.attackIndex = state.attackIndex > 1 and state.attackIndex - 1 or #rows
        Sound.play(game.data, "Press_AB")
      elseif input:wasPressed("down") then
        state.attackIndex = state.attackIndex < #rows and state.attackIndex + 1 or 1
        Sound.play(game.data, "Press_AB")
      elseif input:wasPressed("b") then
        state.submode = "main"
        Sound.play(game.data, "Press_AB")
      elseif input:wasPressed("start") then
        local c = activeCard(cards, rt.player)
        if c then checkCard(c, function() state.submode = "attack" end) end
      elseif input:wasPressed("a") then
        Sound.play(game.data, "Press_AB")
        useAttackRow(rows[state.attackIndex])
      end
      return
    end

    local bHeld = input.isDown and input:isDown("b")
    if bHeld and input:wasPressed("up") then
      checkList("OPP. PLAY AREA", rt.opponent, function() end)
    elseif bHeld and input:wasPressed("down") then
      checkList("YOUR PLAY AREA", rt.player, function() end)
    elseif bHeld and input:wasPressed("left") then
      discardList("YOUR DISCARD", rt.player, function() end)
    elseif bHeld and input:wasPressed("right") then
      discardList("OPP. DISCARD", rt.opponent, function() end)
    elseif input:wasPressed("up") then moveMainCursor("up"); Sound.play(game.data, "Press_AB")
    elseif input:wasPressed("down") then moveMainCursor("down"); Sound.play(game.data, "Press_AB")
    elseif input:wasPressed("left") then moveMainCursor("left"); Sound.play(game.data, "Press_AB")
    elseif input:wasPressed("right") then moveMainCursor("right"); Sound.play(game.data, "Press_AB")
    elseif input:wasPressed("a") then
      Sound.play(game.data, "Press_AB")
      local fn = mainActions[state.menuIndex]; if fn then fn() end
    elseif input:wasPressed("b") then
      -- Plain B is inert on the GB1 main duel screen; B+direction is handled above.
      return
    elseif input:wasPressed("start") and rt.player.active then
      checkCard(cards[rt.player.active.card_label], function() end)
    end
  end

  local function drawAttackBox()
    drawDuelBox()
    local rows = state.attackRows or {}
    local mon = rt.player.active
    local card = mon and cards[mon.card_label]
    for i = 1, math.min(2, #rows) do
      local row = rows[i]
      local y = (i == 1) and 104 or 120
      local atk = row.attack
      local x = 20
      for _, req in ipairs((atk and atk.energy_cost) or {}) do
        local count = math.max(0, tonumber(req.count) or 0)
        for _ = 1, count do
          drawEnergyGlyph(req.type or "Colorless", x, y)
          x = x + 8
        end
      end
      tcgDraw(tcgFitText(row.label, 74), 48, y)
      local dmg = tonumber(row.damage) or 0
      local dtext = dmg > 0 and tostring(dmg) or ""
      tcgDraw(dtext, 152 - tcgWidth(dtext), y)
    end
    if #rows > 0 then
      local y = state.attackIndex == 1 and 104 or 120
      drawSymbol(SYM.CURSOR_R, 8, y)
    end
  end

  function screen:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    drawArena(rt.opponent, true)
    drawArena(rt.player, false)
    drawSeparator()

    if state.submode == "attack" and state.phase == "player" and not state.winner then
      drawAttackBox()
    else
      drawDuelBox()
      love.graphics.setColor(0, 0, 0, 1)
      if state.phase == "player" and not state.winner then
        for i = 1, 6 do
          local p = menuPos[i]
          tcgDraw(p.text, p.textX, p.y)
        end
        local p = menuPos[state.menuIndex]
        drawSymbol(SYM.CURSOR_R, p.cursorX, p.y)
      else
        tcgDraw("ATTENDANT IS THINKING...", 16, 112)
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  local function openingBasicRows(hand)
    local rows = {}
    for _, label in ipairs(hand or {}) do
      if isBasic(label) then
        local c = cards[label]
        local parsedLv = tostring(label):match("Lv(%d+)Card")
        local shown = c.name .. ((c.level or parsedLv) and (" LV" .. tostring(c.level or parsedLv)) or "")
        rows[#rows + 1] = { label = shown, right = tostring(c.hp or 0) .. "HP", key = label }
      end
    end
    return rows
  end

  local function placeOpeningBench(after)
    local rows = openingBasicRows(rt.player.hand)
    if #rt.player.bench >= 5 or #rows == 0 then if after then after() end return end
    rows[#rows + 1] = { label = "DONE", done = true }
    tcgListMenu(game, "CHOOSE YOUR BENCH POKEMON", rows, function(row)
      if row.done then if after then after() end return end
      rt:RemoveCardFromHand(rt.player, row.key)
      local mon = newMon(row.key, 0); mon.played_this_turn = false
      rt.player.bench[#rt.player.bench + 1] = mon
      placeOpeningBench(after)
    end, after, {
      status = "BENCH " .. #rt.player.bench .. "/5",
      footer = "A PLACE  B DONE",
    })
  end

  local function setupOpponent()
    local basic = AI.ChooseFromPriorityList(rt.opponent.hand, nil, isBasic)
    if not basic then return false end
    rt:RemoveCardFromHand(rt.opponent, basic)
    rt.opponent.active = newMon(basic, 0)
    -- GB1's AI then places additional opening Basics on its Bench.  The
    -- packaged starter decks do not carry their original per-deck priority
    -- tables, so use the source AI helper's stable hand order fallback.
    while #rt.opponent.bench < 5 do
      local nextBasic = AI.ChooseFromPriorityList(rt.opponent.hand, nil, isBasic)
      if not nextBasic then break end
      rt:RemoveCardFromHand(rt.opponent, nextBasic)
      rt.opponent.bench[#rt.opponent.bench + 1] = newMon(nextBasic, 0)
    end
    return true
  end

  local function beginAfterCoin(heads)
    game.stack:push(screen)
    if heads then beginPlayerTurn() else runOpponentTurn() end
  end

  local function dealPrizesAndToss()
    DuelEngine.DealPrizes(rt, 6)
    -- HandleDuelSetup places Prize cards before deciding the first player.
    setupNotice("6 Prize cards were placed\nfor each player.", function()
      local heads = love.math.random(0, 1) == 1
      setupCoinToss(heads, function() beginAfterCoin(heads) end)
    end)
  end

  local function setUpOpponentAndContinue()
    setupNotice("ATTENDANT is selecting a POKeMON\nto place in the Arena.", function()
      if not setupOpponent() then
        -- SetupDuel guarantees a Basic after mulligans, so reaching this is
        -- a corrupted-deck guard rather than normal flow.
        finish("player", "ATTENDANT has no Basic POKeMON.")
        return
      end
      local c = cards[rt.opponent.active.card_label]
      local name = c and c.name or "POKeMON"
      setupNotice(name .. " was placed\nin the Arena.", dealPrizesAndToss)
    end)
  end

  local function chooseOpeningActive()
    local openingRows = openingBasicRows(rt.player.hand)
    tcgListMenu(game, "DITTO'S HAND", openingRows, function(row)
      rt:RemoveCardFromHand(rt.player, row.key)
      rt.player.active = newMon(row.key, 0)
      setupNotice("You may choose up to 5 Basic POKeMON\nto place on the Bench.", function()
        placeOpeningBench(setUpOpponentAndContinue)
      end)
    end, nil, {
      footer = "A SELECT",
      cancelable = false,
    })
  end

  local function beginSourceSetupPrompts()
    local pm = math.max(0, tonumber(setupInfo.player_mulligans) or 0)
    local om = math.max(0, tonumber(setupInfo.opponent_mulligans) or 0)
    local notices = {}
    if pm > 0 and om > 0 then
      notices[#notices + 1] = "Neither player has any Basic\nPOKeMON in the opening hand."
      notices[#notices + 1] = "Return the cards to the Deck\nand draw again."
    else
      if pm > 0 then
        notices[#notices + 1] = "There are no Basic POKeMON\nin DITTO's hand."
        notices[#notices + 1] = "Return the cards to the Deck\nand draw again."
      end
      if om > 0 then
        notices[#notices + 1] = "There are no Basic POKeMON\nin ATTENDANT's hand."
        notices[#notices + 1] = "Return the cards to the Deck\nand draw again."
      end
    end
    notices[#notices + 1] = "Choose a Basic POKeMON\nto place in the Arena."
    local i = 1
    local function nextNotice()
      local text = notices[i]
      i = i + 1
      if text then setupNotice(text, nextNotice) else chooseOpeningActive() end
    end
    nextNotice()
  end

  beginSourceSetupPrompts()
end

return Battle
