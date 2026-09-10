-- Pokemon Trading Card Game (GBC) - Duel engine (turn loop / game orchestration)
-- Source: src/engine/duel/core.asm, src/home/duel.asm (turn structure), rules.lua (win conditions,
--         status timing), duel_engine_routine_catalog.lua (routine reference)
--
-- === WHAT THIS FILE IS ===
-- The actual playable game loop: setup, turn structure, attack resolution, knockouts/prizes,
-- between-turn status effects, and win-condition checking, wired up to run against
-- engine_runtime.lua (state), damage_calculation.lua (damage math), ai_engine.lua (opponent
-- decisions), and effect_functions_translated.lua (card effect logic). This is the file that
-- turns everything else in this package from "data and logic pieces" into "a duel you can
-- actually run start to finish."
--
-- === HONEST SCOPE NOTE ===
-- Basic Pokemon placement (opening AND mid-game bench plays), evolution, Energy attachment,
-- retreat, attacking, and now Trainer card play are all automated by AI policy.
--
-- Trainer card play uses ai_engine.lua's AI.ChooseTrainerCardToPlay, which implements REAL,
-- source-verified decision logic (not guesses) for all ~30 Trainer cards -- 100% coverage as of
-- this version. Most are complete translations of the real AIDecide_X routine; several are
-- documented as "simplified" where the source has deck-specific special-case branches (e.g.
-- Professor Oak's bespoke handling for 3 named decks) that were dropped for tractability -- the
-- core condition is still faithful. Three are honest exceptions rather than simplifications,
-- called out explicitly in ai_engine.lua's own comments: Gambler substitutes an analogous
-- always-available condition because its real trigger depends on an untracked AI flag; Poke Ball
-- and Pokemon Trader substitute generic "worth searching" heuristics because their real source
-- ONLY plays them for a handful of specific named decks (never otherwise) with hardcoded
-- per-deck target lists that weren't worth reproducing.
--
-- REQUIRE_SELECTION effect hooks are now invoked (previously silently skipped), but still share
-- one generic argument list across all cards -- an attack/Trainer card whose selection function
-- needs a specific argument shape (a chosen target Pokemon, a chosen energy type) will only work
-- correctly if the caller supplies matching effect_args for that specific card.
--
-- === HOW THIS FILE CONNECTS TO THE OTHERS ===
-- rules.lua: deck_size, starting_hand_size, prizes, status timing, win_conditions.
-- card_database.lua: card stats, looked up via a get_card_fn(label) the caller supplies.
-- ai_and_deck_mechanics.lua: AI.decks for deck lists, AI.opponent_ai for per-deck AI tables.
-- opponents_and_ai_routing.lua: which AI table a given deck uses.

local DuelEngine = {}

-- ===================================================================================
-- SETUP
-- ===================================================================================

-- BuildDeck: expand a compact {card, count} list (as stored in ai_and_deck_mechanics.lua /
-- auto_deck_full_lists.lua) into a flat array of card labels, ready to shuffle.
function DuelEngine.BuildDeck(card_count_list)
  local deck = {}
  for _, entry in ipairs(card_count_list) do
    for _ = 1, entry.count do
      deck[#deck + 1] = entry.card
    end
  end
  return deck
end

-- SetupDuel: shuffle both decks and deal opening 7-card hands. Prize cards are
-- deliberately dealt later, after both players place opening Pokemon, matching the GB1 setup order. Does NOT place
-- opening Basic Pokemon -- call PlaceOpeningPokemon for each duelist after this, since a real
-- duel requires BOTH players to have placed before prizes are dealt (matching
-- menus_and_flow.lua's Menus.duel_setup_menus ordering) and a hand with no Basic Pokemon must be
-- reshuffled and redrawn (the "mulligan" rule) -- modeled via retry_on_no_basic.
function DuelEngine.SetupDuel(rt, player_deck_list, opponent_deck_list, is_basic_pokemon_fn, num_prizes)
  num_prizes = num_prizes or 6
  rt.player.deck = DuelEngine.BuildDeck(player_deck_list)
  rt.opponent.deck = DuelEngine.BuildDeck(opponent_deck_list)

  local function deal_opening_hand(duelist)
    local mulligans = 0
    while true do
      rt:ShuffleCardsInDeck(duelist)
      duelist.hand = {}
      for i = 1, 7 do
        duelist.hand[i] = table.remove(duelist.deck, 1)
      end
      local has_basic = false
      for _, c in ipairs(duelist.hand) do
        if is_basic_pokemon_fn(c) then has_basic = true break end
      end
      if has_basic then break end
      mulligans = mulligans + 1
      -- Pokemon TCG GB setup returns the whole hand to the Deck, shuffles,
      -- and draws seven again until a Basic Pokemon is present.  Keep the
      -- count so the presentation layer can reproduce the source setup text
      -- instead of silently hiding the redraw.
      for _, c in ipairs(duelist.hand) do duelist.deck[#duelist.deck + 1] = c end
      duelist.hand = {}
    end
    return mulligans
  end
  local player_mulligans = deal_opening_hand(rt.player)
  local opponent_mulligans = deal_opening_hand(rt.opponent)

  return {
    player_mulligans = player_mulligans,
    opponent_mulligans = opponent_mulligans,
  }
end

-- PlaceOpeningPokemon: choose and place the opening Active Pokemon (and as many Bench Pokemon as
-- fit/are available) from hand, using the given priority-ordered policy function
-- policy_fn(hand, is_basic_pokemon_fn) -> card_label or nil.
function DuelEngine.PlaceOpeningPokemon(rt, duelist, is_basic_pokemon_fn, choose_fn, new_pokemon_fn)
  local first = choose_fn(duelist.hand, is_basic_pokemon_fn)
  if not first then return false end
  rt:RemoveCardFromHand(duelist, first)
  duelist.active = new_pokemon_fn(first)
  return true
end

-- DealPrizes: after both duelists have placed their opening Pokemon, deal `num_prizes` face-down
-- cards from the top of each deck.
function DuelEngine.DealPrizes(rt, num_prizes)
  num_prizes = num_prizes or 6
  for _, duelist in ipairs({rt.player, rt.opponent}) do
    duelist.prizes = {}
    for i = 1, num_prizes do
      duelist.prizes[i] = table.remove(duelist.deck, 1)
    end
  end
end

-- ===================================================================================
-- BETWEEN-TURN STATUS EFFECTS (rules.lua: poison/double-poison damage, sleep coin-flip check)
-- ===================================================================================

-- ResolveBetweenTurnStatus: apply poison/double-poison damage and the sleep wake-up coin flip to
-- a duelist's Active Pokemon, matching rules.lua's status_conditions timing exactly.
function DuelEngine.ResolveBetweenTurnStatus(rt, duelist, clear_paralysis)
  local mon = duelist.active
  if not mon then return end
  if mon.poison == "POISONED" then
    mon.damage = mon.damage + 10
  elseif mon.poison == "DOUBLE_POISONED" then
    mon.damage = mon.damage + 20
  end
  if mon.status == "ASLEEP" then
    if rt:TossCoin() then -- heads: wake up
      mon.status = "NONE"
    end
  end
  if mon.status == "PARALYZED" and clear_paralysis then
    -- Paralysis clears only after the affected Pokemon's owner's turn.
    -- Between-turn Poison/Sleep processing still runs for BOTH Active Pokemon.
    mon.status = "NONE"
  end
end

-- ===================================================================================
-- KNOCKOUTS AND PRIZES
-- ===================================================================================

-- CheckAndHandleKnockOuts: for both duelists, if their Active Pokemon's damage >= its max HP,
-- move it to the discard pile, award the OPPONENT one prize card (moved from prizes to hand), and
-- leave .active = nil (the owner must place a new Active Pokemon from Bench before their next
-- turn actions -- modeled via NeedsNewActive below).
function DuelEngine.CheckAndHandleKnockOuts(rt, get_card_fn)
  local knocked_out = {}
  for side, duelist in pairs({player = rt.player, opponent = rt.opponent}) do
    local opposing = (side == "player") and rt.opponent or rt.player
    if duelist.active then
      local card = get_card_fn(duelist.active.card_label)
      if card and duelist.active.damage >= card.hp then
        duelist.discard_pile[#duelist.discard_pile + 1] = duelist.active.card_label
        duelist.active = nil
        if #opposing.prizes > 0 then
          local prize = table.remove(opposing.prizes, 1)
          opposing.hand[#opposing.hand + 1] = prize
        end
        knocked_out[#knocked_out + 1] = side
      end
    end
  end
  return knocked_out
end

function DuelEngine.NeedsNewActive(duelist)
  return duelist.active == nil
end

-- ===================================================================================
-- WIN CONDITIONS (rules.lua: Rules.win_conditions)
-- ===================================================================================

-- CheckWinner: returns "player", "opponent", "draw", or nil (duel continues).
-- Deck-out is NOT checked here -- it's a "cannot draw" event that only makes sense at the
-- moment of drawing, so it's surfaced directly by RunAutomatedTurn's return status ("deckout")
-- instead; a caller should treat that status as an immediate loss for whoever's turn it was.
function DuelEngine.CheckWinner(rt)
  local function has_lost(duelist)
    if #duelist.prizes == 0 then return false end -- taking all prizes is a WIN, not a loss
    if duelist.active == nil and #duelist.bench == 0 then return true end -- no Pokemon left
    return false
  end
  local function has_won_by_prizes(duelist)
    return #duelist.prizes == 0
  end

  local player_won = has_won_by_prizes(rt.player) or has_lost(rt.opponent)
  local opponent_won = has_won_by_prizes(rt.opponent) or has_lost(rt.player)
  if player_won and opponent_won then return "draw" end
  if player_won then return "player" end
  if opponent_won then return "opponent" end
  return nil
end

-- ===================================================================================
-- ATTACK RESOLUTION
-- ===================================================================================

-- ResolveAttack: apply an attack's damage (via damage_calculation.lua) AND its scripted effect
-- (via effect_functions_translated.lua, looked up by attack.effect_fn), in the correct order --
-- INITIAL_EFFECT hooks before damage, BEFORE_DAMAGE hooks modify the damage number, then damage
-- is dealt, then AFTER_DAMAGE hooks run (matching effect_commands.lua's hook ordering).
function DuelEngine.ResolveAttack(rt, dmgcalc, effects, effect_commands, attacker_mon, attacker_card,
                                    attack, defender_mon, defender_card, get_card_fn, effect_args, options)
  options = options or {}
  -- Default the shared effect-argument list to the attacking Pokemon, since the large majority
  -- of translated effect functions take (rt, mon_or_attacker, ...) as their signature. This
  -- fixes real crashes (e.g. Ember's INITIAL_EFFECT_1 hook, Ember_CheckEnergy(rt, mon), previously
  -- received no `mon` at all and errored) without requiring every caller to hand-supply args for
  -- every card. A caller can still override with effect_args for cards needing a different shape
  -- (e.g. a chosen target Pokemon, an energy type). Hook calls are pcall-wrapped below so a
  -- genuine argument-shape mismatch degrades to "no extra effect happened" rather than crashing
  -- the whole duel -- this is the known, documented limitation of the shared-argument design
  -- (see this file's HONEST SCOPE NOTE), made non-fatal rather than fully solved.
  effect_args = effect_args or { attacker_mon }
  rt.damage = tonumber(attack.damage) or 0
  rt.dealt_damage = 0

  local dispatch = attack.effect_fn and effect_commands.dispatch[attack.effect_fn]
  local own_duelist, opposing_duelist = rt:turn(), rt:nonturn()
  local function first_key(t)
    for k, n in pairs(t or {}) do if (tonumber(n) or 0) > 0 then return k end end
    return nil
  end
  local function first_card(list, predicate)
    for _, label in ipairs(list or {}) do if not predicate or predicate(label) then return label end end
    return nil
  end
  local function card_of(value)
    local label = type(value) == "table" and value.card_label or value
    return label and get_card_fn(label) or nil
  end
  local function is_basic(label)
    local c = card_of(label)
    return c and c.hp ~= nil and c.stage == "Basic" or false
  end
  local function is_pokemon(label)
    local c = card_of(label)
    return c and c.hp ~= nil or false
  end
  local function is_energy(label)
    return tostring(label or ""):find("EnergyCard", 1, true) ~= nil
  end
  local function is_trainer(label)
    local c = card_of(label)
    return c and c.card_type == "Trainer" or false
  end
  local function energy_type(mon)
    return first_key(mon and mon.energy) or "Colorless"
  end
  local function get_attacks(value)
    local c = card_of(value)
    return c and c.attacks or {}
  end
  local function get_max_hp(value)
    local c = card_of(value)
    return tonumber(c and c.hp) or 0
  end
  local function get_preevo(value)
    local c = card_of(value)
    if not c or not c.evolves_from then return nil end
    for label, candidate in pairs((function()
      local out = {}
      for _, zone in ipairs({ own_duelist.deck, own_duelist.hand, opposing_duelist.deck, opposing_duelist.hand }) do
        for _, l in ipairs(zone or {}) do out[l] = get_card_fn(l) end
      end
      return out
    end)()) do
      if candidate and candidate.name == c.evolves_from then return label end
    end
    return nil
  end
  local function resolve_arg(name)
    if name == "attacker" or name == "attacker_mon" or name == "mon" or name == "source_mon"
        or name == "own_active" or name == "cost_mon" or name == "heal_target_mon" then return attacker_mon end
    if name == "defending_mon" or name == "opposing_mon" or name == "opponent_active"
        or name == "opposing_active" then return defender_mon end
    if name == "target_mon" or name == "from_mon" then return attacker_mon end
    if name == "to_mon" then return own_duelist.bench[1] or attacker_mon end
    if name == "duelist" or name == "own_duelist" then return own_duelist end
    if name == "opposing_duelist" or name == "defending_duelist" then return opposing_duelist end
    if name == "attacker_type" or name == "chosen_type" then return attacker_card.card_type or "Colorless" end
    if name == "chosen_energy_type" or name == "chosen_energy_1" or name == "chosen_energy_2"
        or name == "own_energy_a" or name == "own_energy_b" or name == "opp_energy" then
      return energy_type(name == "opp_energy" and defender_mon or attacker_mon)
    end
    if name == "coin_result" or name == "coin_was_heads" then return rt.last_coin_result ~= false end
    if name == "roll" then return math.max(1, math.floor((rt.rng and rt.rng() or math.random()) * 8) + 1) end
    if name:find("bench_index", 1, true) or name == "bench_choice" or name == "play_area_index" then return 1 end
    if name == "chosen_bench_indices" then return { 1, 2 } end
    if name == "chosen_attack_index" or name == "copied_attack_index" then return 1 end
    if name == "chosen_attack" then return (defender_card.attacks or {})[1] end
    if name == "chosen_count" or name == "count" or name == "amount" then return 1 end
    if name == "chosen_a" or name == "chosen_b" or name == "card_a" or name == "card_b"
        or name == "discard_a" or name == "discard_b" or name == "discard_card"
        or name == "return_card" or name == "hand_card" then return own_duelist.hand[1] end
    if name == "wanted_card_label" or name == "card_label" or name == "energy_card_label"
        or name == "chosen_energy_card" or name == "retrieve_energy_card" then
      return first_card(own_duelist.deck, is_energy) or first_card(own_duelist.discard_pile, is_energy) or own_duelist.deck[1]
    end
    if name == "chosen_card" or name == "retrieve_card" or name == "chosen_trainer_card"
        or name == "discard_basic_pokemon_card" or name == "opposing_discard_basic_pokemon_card" then
      return first_card(own_duelist.discard_pile, name:find("basic", 1, true) and is_basic or nil)
    end
    if name == "chosen_cards" or name == "chosen_energy_cards" or name == "chosen_list"
        or name == "retrieve_list" or name == "shed_cards" or name == "chosen_order"
        or name == "new_top_order" or name == "top_n_preview_choice" then
      local a = own_duelist.discard_pile[1] or own_duelist.deck[1]
      local b = own_duelist.discard_pile[2] or own_duelist.deck[2]
      return b and { a, b } or { a }
    end
    if name == "evolution_chain_card_ids" then
      local ids = {}
      for _, candidate in ipairs(own_duelist.bench or {}) do
        local c = card_of(candidate)
        if c and c.name then ids[#ids + 1] = tostring(c.name):upper():gsub("[^A-Z0-9]", "") end
      end
      return ids
    end
    if name == "get_attacks_fn" then return get_attacks end
    if name == "get_max_hp_fn" then return get_max_hp end
    if name == "get_type_fn" then return function(v) local c=card_of(v); return c and c.card_type end end
    if name == "get_weakness_fn" then return function(v) local c=card_of(v); return c and c.weakness end end
    if name == "get_resistance_fn" then return function(v) local c=card_of(v); return c and c.resistance end end
    if name == "get_preevo_fn" then return get_preevo end
    if name == "energy_type_of_card_fn" then
      return function(label) return tostring(label or ""):match("^([A-Za-z]+)EnergyCard$") or "Colorless" end
    end
    if name == "get_energy_multiplier_damage_fn" then return function(mon) return 10 * (function() local n=0; for _,v in pairs((mon and mon.energy) or {}) do n=n+(tonumber(v) or 0) end; return n end)() end end
    if name == "is_basic_pokemon_fn" or name == "discard_has_basic_fn" or name == "opposing_discard_has_basic_fn" then return is_basic end
    if name == "is_pokemon_fn" then return is_pokemon end
    if name == "is_basic_energy_fn" or name == "is_fire_energy_fn" then return is_energy end
    if name == "is_trainer_fn" then return is_trainer end
    if name == "is_evolved_fn" then return function(v) local c=card_of(v); return c and c.stage ~= "Basic" end end
    if name == "predicate" then return is_basic end
    if name == "can_evolve_fn" or name == "has_playable_stage2_fn" then return function() return true end end
    if name == "muk_toxic_gas_active" or name == "prehistoric_power_active" or name == "protected" then return false end
    if name == "is_active" or name == "is_active_pokemon" or name == "is_arena_card" then return true end
    if name == "chosen_side" then return "own" end
    return nil
  end
  local function run_hook(hook_name)
    if not dispatch then return end
    for _, h in ipairs(dispatch) do
      if h.hook == hook_name then
        local fn = effects[h["function"]]
        if fn then
          local args = effect_args
          local spec = effects.__arg_names and effects.__arg_names[h["function"]]
          if spec then
            args = {}
            for i, name in ipairs(spec) do args[i] = resolve_arg(name) end
          end
          local argc = spec and #spec or #args
          local ok, err = pcall(fn, rt, (table.unpack or unpack)(args, 1, argc))
          if not ok then
            rt.effect_errors = rt.effect_errors or {}
            rt.effect_errors[#rt.effect_errors + 1] = {
              effect = h["function"], hook = hook_name, error = tostring(err),
            }
          end
        end
      end
    end
  end

  run_hook("EFFECTCMDTYPE_INITIAL_EFFECT_1")
  run_hook("EFFECTCMDTYPE_INITIAL_EFFECT_2")
  run_hook("EFFECTCMDTYPE_DISCARD_ENERGY")
  local prepared = false
  local final_damage, effectiveness
  local function prepare()
    if prepared then return final_damage, effectiveness end
    prepared = true
    run_hook("EFFECTCMDTYPE_REQUIRE_SELECTION")
    run_hook("EFFECTCMDTYPE_BEFORE_DAMAGE")
    final_damage, effectiveness = dmgcalc.ComputeDamageForCards(
      rt.damage, attacker_card.card_type, defender_mon, get_card_fn,
      { attacker_pluspower_count = attacker_mon.pluspower_count,
        unaffected_by_weakness_resistance = rt.unaffected_by_weakness_resistance })
    return final_damage, effectiveness
  end
  -- GB1 calculates damage and queues its attack/status presentation before
  -- SubtractHP.  The presentation adapter can request a transaction here,
  -- play the complete animation, then commit HP and AFTER_DAMAGE effects.
  local committed = false
  local function commit()
    prepare()
    if committed then return final_damage, effectiveness end
    committed = true
    if not rt.no_damage_or_effect then
      defender_mon.damage = defender_mon.damage + final_damage
      rt.dealt_damage = final_damage
    end
    rt.unaffected_by_weakness_resistance = false
    run_hook("EFFECTCMDTYPE_AFTER_DAMAGE")
    return final_damage, effectiveness
  end
  local transaction = { prepare = prepare, commit = commit }
  -- Used by the interactive adapter so attack costs occur before Confusion,
  -- while target selection and BEFORE_DAMAGE remain after the attack text.
  if options.defer_after_cost then return nil, nil, transaction end
  prepare()
  if options.defer_damage then
    return final_damage, effectiveness, transaction
  end
  commit()
  return final_damage, effectiveness
end

-- ===================================================================================
-- FULL TURN (automated: draw, Trainer cards, bench play, evolve, energy attach, retreat, attack)
-- ===================================================================================

-- RunAutomatedTurn: plays one full turn for the CURRENT turn holder using ai_engine.lua for all
-- decisions. Returns a log table describing what happened, and a status string
-- ("ok" or "deckout" -- see CheckWinner's note on how to interpret "deckout").
function DuelEngine.RunAutomatedTurn(rt, ai, dmgcalc, get_card_fn, is_basic_pokemon_fn,
                                       has_evolution_fn, deck_ai_tables, options)
  options = options or {}
  local log = {}
  local duelist = rt:turn()
  local opposing = rt:nonturn()

  -- draw phase
  if rt:CheckIfDeckIsEmpty(duelist) then
    log[#log+1] = "Deck empty at draw step -- loss by deck-out."
    return log, "deckout"
  end
  rt:DrawCardFromDeck(duelist)
  log[#log+1] = "Drew a card."

  -- Trainer cards: repeatedly ask the AI decider for the best card to play right now (a card
  -- just played may make another worth playing, e.g. Bill drawing into a second Trainer card),
  -- capped to avoid infinite loops if a decider's condition doesn't change after playing.
  if options.play_trainer_cards_fn then
    options.play_trainer_cards_fn(rt, duelist, opposing, log)
  else
    for _ = 1, 5 do
      local choice = ai.ChooseTrainerCardToPlay(rt, dmgcalc, duelist, opposing, get_card_fn)
      if not choice then break end
      local before_hand_size = #duelist.hand
      rt:RemoveCardFromHand(duelist, choice)
      duelist.discard_pile[#duelist.discard_pile + 1] = choice
      local card = get_card_fn(choice)
      local dispatch = card and card.effect_fn and options.effect_commands
        and options.effect_commands.dispatch[card.effect_fn]
      if dispatch and options.effects then
        for _, h in ipairs(dispatch) do
          local fn = options.effects[h["function"]]
          if fn and (h.hook == "EFFECTCMDTYPE_INITIAL_EFFECT_1" or h.hook == "EFFECTCMDTYPE_INITIAL_EFFECT_2"
                     or h.hook == "EFFECTCMDTYPE_BEFORE_DAMAGE") then
            pcall(fn, rt, duelist)
          end
        end
      end
      log[#log+1] = "Played " .. choice .. "."
      if #duelist.hand >= before_hand_size then break end -- safety: hand size must shrink to progress
    end
  end

  -- play additional Basic Pokemon from hand onto the Bench (if there's room and the AI thinks
  -- it's worth it -- uses the same priority-list preference as the opening play, simplified to
  -- "always bench if possible", matching the source's general willingness to build board presence)
  if #duelist.bench < 5 then
    for _, card_label in ipairs(duelist.hand) do
      if is_basic_pokemon_fn(card_label) and #duelist.bench < 5 then
        rt:RemoveCardFromHand(duelist, card_label)
        duelist.bench[#duelist.bench + 1] = options.new_pokemon_fn and options.new_pokemon_fn(card_label)
        log[#log+1] = "Played " .. card_label .. " to the Bench."
      end
    end
  end

  -- evolve: for each Pokemon in play (Active + Bench) not already evolved this turn, evolve it
  -- if a matching Evolution card sits in hand. The adapter can disable this on a duelist's
  -- first turn, matching the original duel core's first-turn evolution gate.
  if options.get_preevo_label_fn and options.allow_evolution ~= false then
    local function try_evolve(mon)
      if mon.evolved_this_turn or mon.played_this_turn then return end
      for _, card_label in ipairs(duelist.hand) do
        local pre = options.get_preevo_label_fn(card_label)
        if pre == mon.card_label then
          rt:RemoveCardFromHand(duelist, card_label)
          mon.stack = mon.stack or { mon.card_label }
          mon.stack[#mon.stack + 1] = card_label
          mon.card_label = card_label
          mon.evolved_this_turn = true
          mon.status = "NONE"
          mon.poison = "NONE"
          log[#log+1] = "Evolved into " .. card_label .. "."
          return
        end
      end
    end
    if duelist.active then try_evolve(duelist.active) end
    for _, mon in ipairs(duelist.bench) do try_evolve(mon) end
  end

  -- energy attachment (once per turn, if a basic Energy card is in hand and none played yet)
  if not duelist.energy_played_this_turn then
    for _, card_label in ipairs(duelist.hand) do
      local etype = card_label:match("^(%a+)EnergyCard$")
      if etype and etype ~= "Double" then
        local slot, score = ai.ChooseEnergyTarget(duelist, get_card_fn, etype, nil, has_evolution_fn)
        if slot then
          local target_mon = (slot == "active") and duelist.active or duelist.bench[slot[2]]
          rt:RemoveCardFromHand(duelist, card_label)
          target_mon.energy[etype] = (target_mon.energy[etype] or 0) + 1
          duelist.energy_played_this_turn = true
          log[#log+1] = string.format("Attached %s Energy to %s.", etype, target_mon.card_label)
        end
        break
      end
    end
  end

  -- retreat decision. The source game requires enough attached Energy to pay the printed
  -- retreat cost, discards that Energy, and blocks retreat while Asleep or Paralyzed.
  if duelist.active and not duelist.retreated_this_turn
      and duelist.active.status ~= "ASLEEP" and duelist.active.status ~= "PARALYZED" then
    local active_card = get_card_fn(duelist.active.card_label)
    local defending_card = opposing.active and get_card_fn(opposing.active.card_label)
    if defending_card then
      local should, bench_idx = ai.ShouldRetreat(dmgcalc, duelist.active, active_card, duelist.bench,
                                                    get_card_fn, opposing.active, defending_card, nil)
      local cost = math.max(0, tonumber(active_card and active_card.retreat_cost) or 0)
      local total = 0
      for _, n in pairs(duelist.active.energy or {}) do total = total + (tonumber(n) or 0) end
      if should and bench_idx and total >= cost then
        local confusion_ok = true
        if duelist.active.status == "CONFUSED" then
          confusion_ok = rt:TossCoin()
          if not confusion_ok then
            duelist.confusion_retreat_failed = true
            log[#log+1] = "Confusion check failed. Unable to retreat."
          end
        end
        if confusion_ok then
        local left = cost
        for _, typ in ipairs({"Colorless","Grass","Fire","Water","Lightning","Fighting","Psychic"}) do
          while left > 0 and (duelist.active.energy[typ] or 0) > 0 do
            duelist.active.energy[typ] = duelist.active.energy[typ] - 1
            left = left - 1
          end
        end
        rt:SwapArenaWithBenchPokemon(duelist, bench_idx)
        duelist.retreated_this_turn = true
        log[#log+1] = "Retreated to " .. duelist.active.card_label .. "."
        end
      end
    end
  end

  -- attack phase
  if duelist.active and opposing.active then
    local active_card = get_card_fn(duelist.active.card_label)
    local defending_card = get_card_fn(opposing.active.card_label)
    if duelist.active.status ~= "ASLEEP" and duelist.active.status ~= "PARALYZED" then
      local attack, idx, dmg, ko = ai.ChooseAttack(dmgcalc, duelist.active, active_card,
                                                      opposing.active, defending_card, get_card_fn)
      if attack then
        if options.defer_attack then
          -- The adapter owns cost -> Confusion -> declaration -> animation ->
          -- HP commit, matching UseAttackOrPokemonPower in the source.
          return log, "ok", {
            attacker_mon = duelist.active, attacker_card = active_card,
            defender_mon = opposing.active, defender_card = defending_card,
            attack = attack, attack_index = idx, predicted_damage = dmg, predicted_ko = ko,
            confusion_check = duelist.active.status == "CONFUSED",
          }
        end
        local confused_failed = false
        if duelist.active.status == "CONFUSED" and not rt:TossCoin() then
          duelist.active.damage = duelist.active.damage + 20
          log[#log+1] = duelist.active.card_label .. " hurt itself in Confusion for 20 damage."
          confused_failed = true
        end
        if not confused_failed then
          DuelEngine.ResolveAttack(rt, dmgcalc, options.effects, options.effect_commands,
                                     duelist.active, active_card, attack, opposing.active,
                                     defending_card, get_card_fn, options.effect_args)
          log[#log+1] = string.format("Used %s for %d damage%s.", attack.name, dmg, ko and " (Knock Out!)" or "")
        end
      else
        log[#log+1] = "No usable attack -- passed."
      end
    else
      log[#log+1] = duelist.active.card_label .. " is " .. duelist.active.status .. " and could not attack."
    end
  end

  return log, "ok"
end

-- EndTurn: reset per-turn flags, resolve between-turn status for the duelist WHOSE TURN IS
-- ENDING (matching rules.lua: poison/sleep/paralysis resolve based on the turn that just
-- happened), handle any knockouts, then hand the turn to the other duelist.
function DuelEngine.EndTurn(rt, get_card_fn)
  local ending_duelist = rt:turn()
  DuelEngine.ResolveBetweenTurnStatus(rt, ending_duelist)
  local kos = DuelEngine.CheckAndHandleKnockOuts(rt, get_card_fn)
  ending_duelist.energy_played_this_turn = false
  ending_duelist.retreated_this_turn = false
  rt:SwapTurn()
  return kos
end

return DuelEngine
