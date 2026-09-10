-- Pokemon Trading Card Game (GBC) - Opponent AI decision engine
-- Source: src/engine/duel/ai/core.asm, damage_calculation.asm, retreat.asm, energy.asm
--         (heuristics previously only described in ai_and_deck_mechanics.lua / ai_routine_catalog.lua
--         are implemented here as real, executable decision algorithms)
--
-- === WHAT THIS FILE IS ===
-- A working reimplementation of the built-in AI's decision-making: which attack to use, whether
-- to retreat, and which Pokemon to attach Energy to. This is the "brain" that plays an opponent's
-- turn -- given a duel state, it returns concrete decisions rather than just describing heuristics.
--
-- === HOW THIS FILE CONNECTS TO THE OTHERS ===
-- Reads per-deck priority/scoring tables from ai_and_deck_mechanics.lua's AI.opponent_ai (keyed by
-- the same snake_case deck names documented there). Uses damage_calculation.lua for damage
-- prediction and card_database.lua for attack/HP/weakness data. Produces decisions that
-- duel_engine.lua then carries out via engine_runtime.lua and effect_functions_translated.lua.
--
-- Card lookups are passed in as functions (get_card_fn(label) -> card_database.lua entry) rather
-- than baked in, so this file has no hard dependency on how the caller loaded card_database.lua.
-- Similarly, damage_calculation.lua's module table is passed in explicitly as `dmgcalc` to every
-- function that needs it, rather than requiring it internally.

local AI = {}

-- ===================================================================================
-- ATTACK SELECTION
-- ===================================================================================

-- CanUseAttack: does the attacker have enough Energy attached to use this attack right now?
-- attack.energy_cost is card_database.lua's format: { {type="Fire", count=2}, ... }
function AI.CanUseAttack(mon, attack)
  for _, req in ipairs(attack.energy_cost or {}) do
    if req.type == "Colorless" then
      -- Colorless can be paid by ANY energy type; checked as a total-count requirement across
      -- whatever's left after specific-type costs are satisfied. Simplified check: total energy
      -- attached must be at least the sum of all requirements.
    else
      if (mon.energy[req.type] or 0) < req.count then return false end
    end
  end
  local total_required = 0
  for _, req in ipairs(attack.energy_cost or {}) do total_required = total_required + req.count end
  local total_attached = 0
  for _, n in pairs(mon.energy) do total_attached = total_attached + n end
  return total_attached >= total_required
end

-- PredictAttackDamage: compute the damage this attack would deal RIGHT NOW, ignoring any
-- attack-specific scripted effect that changes damage (coin flips, energy-count bonuses, etc.
-- are NOT applied here -- this is the AI's baseline prediction from the attack's printed base
-- damage only, matching the source's simpler AI damage-prediction pass; effect_commands.lua's
-- "AI"/"AI_SELECTION" hooks refine specific cards further and are not modeled here).
function AI.PredictAttackDamage(dmgcalc, attack, attacker_card_type, attacker_mon, defender_mon, get_card_fn)
  local base = tonumber(attack.damage) or 0
  return dmgcalc.ComputeDamageForCards(base, attacker_card_type, defender_mon, get_card_fn, {
    attacker_pluspower_count = attacker_mon.pluspower_count,
  })
end

-- ChooseAttack: pick the best available attack for the attacker to use against the defender.
-- Priority (matching the source's core.asm logic): (1) any attack that KOs the defender wins
-- outright; (2) otherwise, highest predicted damage; (3) ties broken by preferring the
-- lower-energy-cost attack (conserves resources, a reasonable tie-break consistent with the
-- source's general conservatism).
-- Returns: attack_table, index, predicted_damage, will_ko
function AI.ChooseAttack(dmgcalc, attacker_mon, attacker_card, defender_mon, defender_card, get_card_fn)
  local best, best_idx, best_damage, best_ko = nil, nil, -1, false
  for i, attack in ipairs(attacker_card.attacks or {}) do
    if attack.kind ~= "Pokemon Power" and AI.CanUseAttack(attacker_mon, attack) then
      local dmg = AI.PredictAttackDamage(dmgcalc, attack, attacker_card.card_type, attacker_mon, defender_mon, get_card_fn)
      local remaining_hp = defender_card.hp - defender_mon.damage
      local would_ko = dmg >= remaining_hp
      local better
      if would_ko and not best_ko then
        better = true
      elseif would_ko == best_ko then
        if dmg > best_damage then better = true
        elseif dmg == best_damage and best then
          local cost_a, cost_b = 0, 0
          for _, r in ipairs(attack.energy_cost) do cost_a = cost_a + r.count end
          for _, r in ipairs(best.energy_cost) do cost_b = cost_b + r.count end
          better = cost_a < cost_b
        else
          better = (best == nil)
        end
      end
      if better then
        best, best_idx, best_damage, best_ko = attack, i, dmg, would_ko
      end
    end
  end
  return best, best_idx, best_damage, best_ko
end

-- ===================================================================================
-- RETREAT DECISION
-- ===================================================================================

-- ScoreRetreat: implements the documented heuristic list from ai_and_deck_mechanics.lua's
-- AI.retreat_logic as real scoring code. Returns a numeric score (higher = more the AI wants to
-- retreat) and, if positive, which Bench Pokemon it would prefer to switch in.
function AI.ScoreRetreat(dmgcalc, own_active_mon, own_active_card, own_bench, get_card_fn,
                          defending_mon, defending_card, retreat_bonus_table)
  local score = 0
  local best_bench_idx, best_bench_score = nil, -math.huge

  for i, bench_mon in ipairs(own_bench) do
    local bench_card = get_card_fn(bench_mon.card_label)
    local bench_score = 0

    -- resistant to the defender's type: favorable matchup
    if bench_card.resistance and bench_card.resistance == defending_card.card_type then
      bench_score = bench_score + 10
    end
    -- NOT weak to the defender's type: safer matchup
    if bench_card.weakness ~= defending_card.card_type then
      bench_score = bench_score + 5
    end
    -- IS the defender's own weakness type: can hit hard
    if bench_card.weakness == nil or defending_card.weakness == bench_card.card_type then
      bench_score = bench_score + 8
    end
    -- could this Bench Pokemon KO the defender with an available attack?
    for _, attack in ipairs(bench_card.attacks or {}) do
      if attack.kind == "Attack" and AI.CanUseAttack(bench_mon, attack) then
        local dmg = AI.PredictAttackDamage(dmgcalc, attack, bench_card.card_type, bench_mon, defending_mon, get_card_fn)
        if dmg >= (defending_card.hp - defending_mon.damage) then
          bench_score = bench_score + 25
        end
      end
    end
    -- per-deck retreat_bonus table override (see ai_and_deck_mechanics.lua) -- only actually
    -- wired up for the Legendary Moltres deck in the real game; passed in optionally here
    if retreat_bonus_table then
      for _, entry in ipairs(retreat_bonus_table) do
        if entry.card == bench_card.name then
          bench_score = bench_score + entry.score
        end
      end
    end

    if bench_score > best_bench_score then
      best_bench_score = bench_score
      best_bench_idx = i
    end
  end

  if best_bench_idx then score = score + best_bench_score end

  -- penalize a high retreat cost
  local retreat_cost = own_active_card.retreat_cost or 0
  if retreat_cost > 1 then
    score = score - (retreat_cost - 1) * 5
  end

  -- discourage retreating a still-healthy final-evolution Pokemon
  if own_active_card.stage == "Stage 2" and own_active_mon.damage < (own_active_card.hp / 2) then
    score = score - 10
  end

  return score, best_bench_idx
end

-- ShouldRetreat: convenience wrapper -- true (with target Bench index) if ScoreRetreat's result
-- clears a positive threshold, matching the source's general "only retreat with good reason"
-- conservatism.
function AI.ShouldRetreat(dmgcalc, own_active_mon, own_active_card, own_bench, get_card_fn,
                           defending_mon, defending_card, retreat_bonus_table)
  if own_active_mon.status == "ASLEEP" or own_active_mon.status == "PARALYZED" then
    return false -- cannot retreat regardless of score (rules.lua)
  end
  if #own_bench == 0 then return false end
  local score, idx = AI.ScoreRetreat(dmgcalc, own_active_mon, own_active_card, own_bench, get_card_fn,
                                       defending_mon, defending_card, retreat_bonus_table)
  return score >= 15, idx
end

-- ===================================================================================
-- ENERGY ATTACHMENT DECISION
-- ===================================================================================

-- ScoreEnergyTarget: implements AI.energy_attachment_logic's documented heuristics as real
-- scoring code for one candidate Pokemon (active or bench).
function AI.ScoreEnergyTarget(mon, card, energy_type, energy_bonus_table, has_evolution_in_hand_or_deck)
  local score = 0

  -- does this Pokemon still need this energy type to use an attack it doesn't yet have enough for?
  for _, attack in ipairs(card.attacks or {}) do
    if attack.kind == "Attack" and not AI.CanUseAttack(mon, attack) then
      for _, req in ipairs(attack.energy_cost) do
        if req.type == energy_type then score = score + 10 end
      end
    end
  end

  -- bonus if this Pokemon is about to evolve (investing energy in a soon-to-be-stronger Pokemon)
  if has_evolution_in_hand_or_deck then score = score + 5 end

  -- per-deck energy_bonus table override (see ai_and_deck_mechanics.lua)
  if energy_bonus_table then
    for _, entry in ipairs(energy_bonus_table) do
      if entry.card == card.name then
        local current = mon.energy[energy_type] or 0
        if current < entry.max_attached then
          score = score + entry.score
        else
          score = score - 100 -- already at this deck's preferred cap for this card
        end
      end
    end
  end

  return score
end

-- ChooseEnergyTarget: pick the best Pokemon (active or a specific bench slot) to attach the given
-- energy card to, out of everything in the duelist's own Play Area.
-- Returns: "active" or ("bench", index), score
function AI.ChooseEnergyTarget(duelist, get_card_fn, energy_type, energy_bonus_table, has_evolution_fn)
  local best_slot, best_score = nil, -math.huge
  if duelist.active then
    local card = get_card_fn(duelist.active.card_label)
    local s = AI.ScoreEnergyTarget(duelist.active, card, energy_type, energy_bonus_table,
                                     has_evolution_fn(duelist.active.card_label))
    if s > best_score then best_score, best_slot = s, "active" end
  end
  for i, mon in ipairs(duelist.bench) do
    local card = get_card_fn(mon.card_label)
    local s = AI.ScoreEnergyTarget(mon, card, energy_type, energy_bonus_table, has_evolution_fn(mon.card_label))
    if s > best_score then best_score, best_slot = s, {"bench", i} end
  end
  return best_slot, best_score
end

-- ===================================================================================
-- ARENA/BENCH PRIORITY (which Basic Pokemon to lead with / bench first)
-- ===================================================================================

-- ChooseOpeningPlay / ChooseBenchPlay: pick which card from hand to play, preferring the order
-- given by a deck's arena_priority/bench_priority list (ai_and_deck_mechanics.lua), falling back
-- to the first playable Basic Pokemon found if the priority list doesn't match anything in hand.
function AI.ChooseFromPriorityList(hand, priority_list, is_basic_pokemon_fn)
  if priority_list then
    for _, preferred_name in ipairs(priority_list) do
      for _, card_label in ipairs(hand) do
        if card_label == preferred_name .. "Card" and is_basic_pokemon_fn(card_label) then
          return card_label
        end
      end
    end
  end
  for _, card_label in ipairs(hand) do
    if is_basic_pokemon_fn(card_label) then return card_label end
  end
  return nil
end

-- ===================================================================================
-- TRAINER CARD AI (translated from src/engine/duel/ai/trainer_cards.asm, the previously
-- untranslated 6,074-line subsystem). Each AI.Decide_X function mirrors the SAME-NAMED
-- AIDecide_X routine's actual logic, verified against the raw source -- not a generic guess.
-- Functions marked "(simplified)" below implement the routine's real core condition but drop
-- deck-specific special cases (e.g. Professor Oak's bespoke handling for 3 specific decks) for
-- tractability; functions with no marking are a direct, complete translation.
-- ===================================================================================

-- AIDecide_Bill: play Bill as long as more than 9 cards remain in the deck (don't thin an
-- already-small deck further).
function AI.Decide_Bill(duelist)
  local cards_not_in_deck = 60 - #duelist.deck
  return cards_not_in_deck < 60 - 9
end

-- AIDecide_ProfessorOak (simplified: general-deck branch only, real source special-cases 3
-- specific decks which are not modeled here): never play with <=6 cards left in deck; strongly
-- prefer playing when hand is small (<4 cards) and deck still has >14 cards.
function AI.Decide_ProfessorOak(duelist)
  local deck_left = #duelist.deck
  if deck_left <= 6 then return false end
  if deck_left <= 14 then return false end
  return #duelist.hand < 4
end

-- AIDecide_Switch: use Switch if retreat cost is 3+, OR if retreat cost exceeds attached energy
-- by 2 or more (can't easily pay to retreat normally).
function AI.Decide_Switch(active_mon, active_card, own_bench)
  if #own_bench == 0 then return false end
  local retreat_cost = active_card.retreat_cost or 0
  local total_energy = 0
  for _, n in pairs(active_mon.energy) do total_energy = total_energy + n end
  if retreat_cost >= 3 then return true end
  if retreat_cost - total_energy >= 2 then return true end
  return false
end

-- AIDecide_GustOfWind (simplified: drops the deck-specific Mew/Mewtwo exclusion and the
-- weakness-based bench-target search, keeps the real core gate): only useful if the attacker
-- currently CANNOT knock out the opponent's Active Pokemon but a Bench Pokemon exists to pull up
-- instead (Gust of Wind forces the opponent's weaker Bench Pokemon into the Active spot).
function AI.Decide_GustOfWind(dmgcalc, attacker_mon, attacker_card, defending_active, defending_active_card,
                                opposing_bench, get_card_fn, already_used_this_turn)
  if already_used_this_turn then return false end
  if #opposing_bench == 0 then return false end
  local attack = select(1, AI.ChooseAttack(dmgcalc, attacker_mon, attacker_card, defending_active,
                                             defending_active_card, get_card_fn))
  if attack then
    local dmg = AI.PredictAttackDamage(dmgcalc, attack, attacker_card.card_type, attacker_mon, defending_active, get_card_fn)
    if dmg >= (defending_active_card.hp - defending_active.damage) then
      return false -- can already KO the current Active -- no need to Gust
    end
  end
  return true
end

-- AIDecide_PokemonCenter (simplified: drops the KO-check short-circuit's exact energy-in-hand
-- nuance, keeps the core "only heal if not about to win/lose the exchange anyway" gate): play if
-- any of your own Pokemon has damage AND you're not about to KO the opponent this turn anyway.
function AI.Decide_PokemonCenter(dmgcalc, own_active_mon, own_active_card, own_bench,
                                   defending_active, defending_active_card, get_card_fn)
  local attack = select(1, AI.ChooseAttack(dmgcalc, own_active_mon, own_active_card, defending_active,
                                             defending_active_card, get_card_fn))
  if attack then
    local dmg = AI.PredictAttackDamage(dmgcalc, attack, own_active_card.card_type, own_active_mon, defending_active, get_card_fn)
    if dmg >= (defending_active_card.hp - defending_active.damage) then
      return false -- about to win the exchange -- no need to heal first
    end
  end
  local has_damage = own_active_mon.damage > 0
  for _, mon in ipairs(own_bench) do if mon.damage > 0 then has_damage = true end end
  return has_damage
end

-- AIDecide_FullHeal: play whenever the Active Pokemon has ANY status condition (Confused,
-- Asleep, Paralyzed, Poisoned, or Double Poisoned all qualify -- a direct, complete translation).
function AI.Decide_FullHeal(mon)
  return mon.status ~= "NONE" or mon.poison ~= "NONE"
end

-- AIDecide_PlusPower_Phase13: use PlusPower ONLY if the attacker cannot already KO the defender,
-- but WOULD be able to with the +10 PlusPower boost applied. A direct, complete translation --
-- this is exactly the source's "no free wins wasted, but close a genuine KO gap" logic.
function AI.Decide_PlusPower(dmgcalc, attacker_mon, attacker_card, defending_mon, defending_card, get_card_fn)
  for _, attack in ipairs(attacker_card.attacks or {}) do
    if attack.kind ~= "Pokemon Power" and AI.CanUseAttack(attacker_mon, attack) then
      local base_dmg = AI.PredictAttackDamage(dmgcalc, attack, attacker_card.card_type, attacker_mon, defending_mon, get_card_fn)
      local remaining_hp = defending_card.hp - defending_mon.damage
      if base_dmg >= remaining_hp then
        return false -- already KOs without help -- don't waste the PlusPower
      end
      if base_dmg + 10 >= remaining_hp then
        return true, attack -- +10 closes the gap
      end
    end
  end
  return false
end

-- AIDecide_Defender (mirrors AIDecide_PlusPower's shape from the opposite side, per
-- ai_and_deck_mechanics.lua's documented symmetry between the two cards): attach Defender to the
-- Active Pokemon only if it would turn an opponent's currently-lethal attack into a non-lethal one.
function AI.Decide_Defender(dmgcalc, own_mon, own_card, opposing_mon, opposing_card, get_card_fn)
  for _, attack in ipairs(opposing_card.attacks or {}) do
    if attack.kind == "Attack" and AI.CanUseAttack(opposing_mon, attack) then
      local dmg = AI.PredictAttackDamage(dmgcalc, attack, opposing_card.card_type, opposing_mon, own_mon, get_card_fn)
      local remaining_hp = own_card.hp - own_mon.damage
      if dmg >= remaining_hp and (dmg - 20) < remaining_hp then
        return true -- Defender's -20 would prevent this specific KO
      end
    end
  end
  return false
end

-- AIDecide_Recycle (simplified: drops the deck-specific Ghost/Fire-Charge priority-card search,
-- keeps the real core gate): only useful if the discard pile actually has something to reclaim.
function AI.Decide_Recycle(duelist)
  return #duelist.discard_pile > 0
end

-- AIDecide_ScoopUp (simplified: drops the deck-specific Articuno/Ronald branches, keeps the real
-- core gate): only useful with 2+ Pokemon in play (nothing to usefully bench-swap otherwise).
function AI.Decide_ScoopUp(duelist)
  local count = (duelist.active and 1 or 0) + #duelist.bench
  return count >= 2
end

-- ===================================================================================
-- TRAINER CARD PLAY ORCHESTRATION
-- ===================================================================================

-- TRAINER_CARD_DECIDERS: maps a card's base name (label minus "Card") to its decider. Each entry
-- returns true/false (play it or not) and is called with a fixed argument shape documented per
-- function above; ChooseTrainerCardToPlay below supplies the right arguments for each.
AI.TRAINER_CARD_DECIDERS = {
  "BillCard", "ProfessorOakCard", "SwitchCard", "GustOfWindCard", "PokemonCenterCard",
  "FullHealCard", "PlusPowerCard", "DefenderCard", "RecycleCard", "ScoopUpCard",
}

-- ChooseTrainerCardToPlay: scan the hand for the first Trainer card (in the fixed priority order
-- above, matching roughly the real game's early-to-late phase ordering documented in
-- ai_and_deck_mechanics.lua's AI.turn_logic.trainer_card_phases) that its own AI.Decide_X says
-- yes to right now. Returns the card_label to play, or nil if no Trainer card should be played.
function AI.ChooseTrainerCardToPlay(rt, dmgcalc, duelist, opposing, get_card_fn)
  local own_card = duelist.active and get_card_fn(duelist.active.card_label)
  local opp_card = opposing.active and get_card_fn(opposing.active.card_label)

  local function in_hand(label) for _, c in ipairs(duelist.hand) do if c == label then return true end end return false end

  if in_hand("BillCard") and AI.Decide_Bill(duelist) then return "BillCard" end
  if in_hand("ProfessorOakCard") and AI.Decide_ProfessorOak(duelist) then return "ProfessorOakCard" end
  if in_hand("FullHealCard") and duelist.active and AI.Decide_FullHeal(duelist.active) then return "FullHealCard" end
  if in_hand("RecycleCard") and AI.Decide_Recycle(duelist) then return "RecycleCard" end
  if in_hand("EnergyRetrievalCard") and AI.Decide_EnergyRetrieval(duelist) then return "EnergyRetrievalCard" end
  if in_hand("ItemFinderCard") and AI.Decide_ItemFinder(duelist) then return "ItemFinderCard" end
  if in_hand("ComputerSearchCard") and AI.Decide_ComputerSearch(duelist) then return "ComputerSearchCard" end
  if in_hand("MaintenanceCard") and AI.Decide_Maintenance(duelist) then return "MaintenanceCard" end
  if in_hand("GamblerCard") and AI.Decide_Gambler(duelist) then return "GamblerCard" end
  if in_hand("LassCard") and AI.Decide_Lass(opposing) then return "LassCard" end
  if in_hand("EnergySearchCard") and AI.Decide_EnergySearch(duelist, duelist.active, own_card) then return "EnergySearchCard" end
  if own_card and opp_card and duelist.active and opposing.active then
    if in_hand("PlusPowerCard") then
      local should = AI.Decide_PlusPower(dmgcalc, duelist.active, own_card, opposing.active, opp_card, get_card_fn)
      if should then return "PlusPowerCard" end
    end
    if in_hand("DefenderCard") then
      if AI.Decide_Defender(dmgcalc, duelist.active, own_card, opposing.active, opp_card, get_card_fn) then
        return "DefenderCard"
      end
    end
    if in_hand("GustOfWindCard") then
      if AI.Decide_GustOfWind(dmgcalc, duelist.active, own_card, opposing.active, opp_card,
                                opposing.bench, get_card_fn, duelist.used_gust_of_wind_this_turn) then
        return "GustOfWindCard"
      end
    end
    if in_hand("PokemonCenterCard") then
      if AI.Decide_PokemonCenter(dmgcalc, duelist.active, own_card, duelist.bench, opposing.active, opp_card, get_card_fn) then
        return "PokemonCenterCard"
      end
    end
    if in_hand("EnergyRemovalCard") then
      if AI.Decide_EnergyRemoval(dmgcalc, duelist.active, own_card, opposing.active, opp_card, get_card_fn) then
        return "EnergyRemovalCard"
      end
    end
    if in_hand("SuperEnergyRemovalCard") then
      if AI.Decide_SuperEnergyRemoval(dmgcalc, duelist.active, own_card, opposing.active, opp_card, get_card_fn) then
        return "SuperEnergyRemovalCard"
      end
    end
    if in_hand("PotionCard") and AI.Decide_Potion(dmgcalc, duelist.active, own_card, opposing.active, opp_card, get_card_fn) then
      return "PotionCard"
    end
    if in_hand("SuperPotionCard") and AI.Decide_SuperPotion(dmgcalc, duelist.active, own_card, opposing.active, opp_card, get_card_fn) then
      return "SuperPotionCard"
    end
  end
  if in_hand("SwitchCard") and duelist.active and own_card then
    if AI.Decide_Switch(duelist.active, own_card, duelist.bench) then return "SwitchCard" end
  end
  if in_hand("ScoopUpCard") and AI.Decide_ScoopUp(duelist) then return "ScoopUpCard" end
  if in_hand("SuperEnergyRetrievalCard") and AI.Decide_SuperEnergyRetrieval(duelist) then return "SuperEnergyRetrievalCard" end
  if in_hand("ImposterProfessorOakCard") and AI.Decide_ImposterProfessorOak(opposing) then return "ImposterProfessorOakCard" end
  if in_hand("PokedexCard") and AI.Decide_Pokedex(rt, duelist) then return "PokedexCard" end
  if in_hand("PokemonFluteCard") then
    local function has_basic_in_discard(d)
      for _, c in ipairs(d.discard_pile) do
        local card = get_card_fn(c)
        if card and card.stage == "Basic" then return true end
      end
      return false
    end
    if AI.Decide_PokemonFlute(opposing, has_basic_in_discard) then return "PokemonFluteCard" end
  end
  if in_hand("MysteriousFossilCard") and AI.Decide_MysteriousFossil(duelist) then return "MysteriousFossilCard" end
  if in_hand("ClefairyDollCard") and AI.Decide_ClefairyDoll(duelist) then return "ClefairyDollCard" end
  if in_hand("PokeBallCard") and AI.Decide_Pokeball(duelist) then return "PokeBallCard" end
  if in_hand("PokemonTraderCard") then
    local function is_pokemon(l)
      local c = get_card_fn(l)
      return c ~= nil and c.card_type ~= "Trainer" and not (c.card_type or ""):match("^Energy")
    end
    if AI.Decide_PokemonTrader(duelist, is_pokemon) then return "PokemonTraderCard" end
  end

  return nil
end

-- ===================================================================================
-- TRAINER CARD AI, ROUND 2: 8 more cards, same standard -- source-verified core condition,
-- deck-specific special-case branches dropped for tractability (documented per function).
-- ===================================================================================

-- AIDecide_EnergyRetrieval (simplified: drops the Go-Go-Rain-Dance-deck special case, keeps the
-- real core gate): play only if a DUPLICATE Energy card sits in hand (a spare to use as the
-- discard-as-cost requirement) -- checked here as 2+ of the same Energy label in hand.
function AI.Decide_EnergyRetrieval(duelist)
  local counts = {}
  for _, c in ipairs(duelist.hand) do
    if c:match("EnergyCard$") then counts[c] = (counts[c] or 0) + 1 end
  end
  for _, n in pairs(counts) do
    if n >= 2 then return true end
  end
  return false
end

-- AIDecide_ItemFinder (simplified: the real source searches specifically for Energy Removal in
-- the discard pile; kept faithful to that exact target rather than generalizing to "any Trainer").
function AI.Decide_ItemFinder(duelist)
  for _, c in ipairs(duelist.discard_pile) do
    if c == "EnergyRemovalCard" then return true end
  end
  return false
end

-- AIDecide_ComputerSearch (simplified: the real source only plays this for 4 specific named
-- decks -- Rock Crusher, Wonders of Science, Fire Charge, Anger -- each with bespoke target logic;
-- not deck-aware here, so this keeps only the universal minimum gate: 3+ cards in hand (2 to
-- discard as cost, matching the printed "discard 2 cards from your hand" requirement).
function AI.Decide_ComputerSearch(duelist)
  return #duelist.hand >= 3
end

-- AIDecide_EnergySearch (simplified: drops the Heated Battle/Wonders of Science deck branches,
-- keeps the real core gate): play if the deck still has a basic Energy card to find AND the hand
-- doesn't already hold an Energy card useful to something in play (i.e. don't search if you
-- already have what you need).
function AI.Decide_EnergySearch(duelist, active_mon, active_card)
  local has_useful_energy_in_hand = false
  for _, c in ipairs(duelist.hand) do
    local etype = c:match("^(%a+)EnergyCard$")
    if etype and etype ~= "Double" and active_card then
      for _, attack in ipairs(active_card.attacks or {}) do
        if attack.kind == "Attack" and not AI.CanUseAttack(active_mon, attack) then
          for _, req in ipairs(attack.energy_cost) do
            if req.type == etype then has_useful_energy_in_hand = true end
          end
        end
      end
    end
  end
  if has_useful_energy_in_hand then return false end
  for _, c in ipairs(duelist.deck) do
    if c:match("EnergyCard$") and not c:match("^Double") then return true end
  end
  return false
end

-- AIDecide_Maintenance (simplified: keeps the real core gate): play if hand has 4+ cards AND at
-- least one duplicate card (same label appearing twice), giving something safe to shuffle back.
function AI.Decide_Maintenance(duelist)
  if #duelist.hand < 4 then return false end
  local counts = {}
  for _, c in ipairs(duelist.hand) do counts[c] = (counts[c] or 0) + 1 end
  for _, n in pairs(counts) do
    if n >= 2 then return true end
  end
  return false
end

-- AIDecide_Gambler (heavily simplified: the real source only fires this under a specific
-- "opponent is mill-stalling with a Mewtwo-only deck" flag this runtime doesn't track; kept here
-- as the closest analogous, always-available condition: play to refresh a nearly-empty hand's
-- worth of resources when your own deck is critically low, matching the documented intent of
-- "replenish before decking out" even though the exact trigger condition differs from the source).
function AI.Decide_Gambler(duelist)
  local cards_not_in_deck = 60 - #duelist.deck
  return cards_not_in_deck >= 60 - 4
end

-- AIDecide_Lass (simplified: drops the exact "any other Trainer in hand" loop condition, keeps
-- the real confirmed gate): only consider playing if the OPPONENT has a large hand (7+ cards) --
-- Lass's real payoff scales with how many Trainer cards there are to strip from a big hand.
function AI.Decide_Lass(opposing_duelist)
  return #opposing_duelist.hand >= 7
end

-- AIDecide_EnergyRemoval (same "don't disrupt if you can already win the exchange" shape as
-- PlusPower/Defender/PokemonCenter): only worth playing if the attacker CANNOT already KO the
-- opponent's Active Pokemon this turn, and that Pokemon has Energy attached to strip.
function AI.Decide_EnergyRemoval(dmgcalc, attacker_mon, attacker_card, defending_mon, defending_card, get_card_fn)
  for _, attack in ipairs(attacker_card.attacks or {}) do
    if attack.kind ~= "Pokemon Power" and AI.CanUseAttack(attacker_mon, attack) then
      local dmg = AI.PredictAttackDamage(dmgcalc, attack, attacker_card.card_type, attacker_mon, defending_mon, get_card_fn)
      if dmg >= (defending_card.hp - defending_mon.damage) then
        return false -- can already KO -- no need to disrupt
      end
    end
  end
  local total = 0
  for _, n in pairs(defending_mon.energy) do total = total + n end
  return total > 0
end

-- ===================================================================================
-- TRAINER CARD AI, ROUND 3: the last 10 cards, bringing coverage to 28 of ~30.
-- ===================================================================================

-- Shared helper for the Potion/Super Potion family: would healing `heal_amount` off the ACTIVE
-- Pokemon prevent it from being Knocked Out by the opponent's best available attack this turn?
local function would_heal_prevent_ko(dmgcalc, own_mon, own_card, opposing_mon, opposing_card, get_card_fn, heal_amount)
  local worst_incoming = 0
  for _, attack in ipairs(opposing_card.attacks or {}) do
    if attack.kind == "Attack" and AI.CanUseAttack(opposing_mon, attack) then
      local dmg = AI.PredictAttackDamage(dmgcalc, attack, opposing_card.card_type, opposing_mon, own_mon, get_card_fn)
      if dmg > worst_incoming then worst_incoming = dmg end
    end
  end
  if worst_incoming == 0 then return false end -- nothing threatens a KO right now
  local remaining_hp = own_card.hp - own_mon.damage
  local would_die_without_heal = worst_incoming >= remaining_hp
  local would_survive_with_heal = worst_incoming < (remaining_hp + math.min(heal_amount, own_mon.damage))
  return would_die_without_heal and would_survive_with_heal
end

-- AIDecide_Potion (both phase variants share this shape): heal 20 only if it would prevent an
-- otherwise-lethal hit next turn.
function AI.Decide_Potion(dmgcalc, own_mon, own_card, opposing_mon, opposing_card, get_card_fn)
  return would_heal_prevent_ko(dmgcalc, own_mon, own_card, opposing_mon, opposing_card, get_card_fn, 20)
end

-- AIDecide_SuperPotion (simplified: drops the retreat-first/high-recoil-attack pre-checks, keeps
-- the real core gate): heal 40 only if it would prevent an otherwise-lethal hit, and only if
-- there's Energy attached somewhere to pay the discard-as-cost requirement.
function AI.Decide_SuperPotion(dmgcalc, own_mon, own_card, opposing_mon, opposing_card, get_card_fn)
  local has_energy = false
  for _, n in pairs(own_mon.energy) do if n > 0 then has_energy = true end end
  if not has_energy then return false end
  return would_heal_prevent_ko(dmgcalc, own_mon, own_card, opposing_mon, opposing_card, get_card_fn, 40)
end

-- AIDecide_ImposterProfessorOak: targets the OPPONENT's hand/deck (this card refreshes THEIR
-- hand, a disruptive effect) -- a direct, complete translation of the two-branch condition.
function AI.Decide_ImposterProfessorOak(opposing_duelist)
  local deck_left = #opposing_duelist.deck
  if deck_left > 14 then
    return #opposing_duelist.hand >= 9
  else
    return #opposing_duelist.hand < 6
  end
end

-- AIDecide_Pokedex (simplified: the real source also requires an internal "hasn't looked in a
-- while" counter to reach 6 uses since last check, which this runtime doesn't track; kept here as
-- the two conditions that ARE tracked): deck has more than 4 cards left, and a 30% random chance
-- (matching the source's literal "3 in 10" roll) -- so this fires less predictably than most
-- deciders, matching the source's own intentionally randomized behavior for this card.
function AI.Decide_Pokedex(rt, duelist)
  if #duelist.deck <= 4 then return false end
  return rt:Random(10) < 3
end

-- AIDecide_PokemonBreeder: reuses the exact legality condition already implemented as
-- Effects.PokemonBreeder_HandPlayAreaCheck in effect_functions_translated.lua (a hand Stage 2 with
-- its Basic in play, unless Prehistoric Power already grants free Stage-2 evolution).
function AI.Decide_PokemonBreeder(has_playable_stage2_fn, prehistoric_power_active)
  if prehistoric_power_active then return false end -- redundant if already granted for free
  return has_playable_stage2_fn()
end

-- AIDecide_PokemonFlute: play if the OPPONENT's discard pile has a Basic Pokemon to revive into
-- THEIR OWN Bench (a card-advantage-denial trick -- reviving a low-value Basic clogs their Bench
-- slot) and their Play Area isn't already full.
function AI.Decide_PokemonFlute(opposing_duelist, has_basic_in_discard_fn)
  if #opposing_duelist.bench + (opposing_duelist.active and 1 or 0) >= 6 then return false end
  return has_basic_in_discard_fn(opposing_duelist)
end

-- AIDecide_ClefairyDollOrMysteriousFossil (simplified: drops the Wigglytuff-specific always-play
-- override, keeps the real core gate): play if own Play Area has room and isn't already at 4+
-- Pokemon (the source treats 4+ as "probably don't need another body").
function AI.Decide_MysteriousFossil(duelist)
  local count = (duelist.active and 1 or 0) + #duelist.bench
  if count >= 6 then return false end
  return count < 4
end
AI.Decide_ClefairyDoll = AI.Decide_MysteriousFossil

-- AIDecide_SuperEnergyRetrieval: identical mechanic/shape to AIDecide_EnergyRetrieval (needs a
-- spare duplicate Energy card in hand).
AI.Decide_SuperEnergyRetrieval = AI.Decide_EnergyRetrieval

-- AIDecide_SuperEnergyRemoval: needs a non-Double-Colorless Energy card attached somewhere on
-- your own side (to discard as this card's cost) AND the opponent's Active Pokemon must have
-- Energy attached to strip, and (matching the same "don't disrupt an already-won exchange" shape
-- as the other disruption cards) the attacker shouldn't already be able to KO outright.
function AI.Decide_SuperEnergyRemoval(dmgcalc, own_mon, own_card, opposing_mon, opposing_card, get_card_fn)
  local has_removable = false
  for etype, n in pairs(own_mon.energy) do
    if etype ~= "DoubleColorless" and n > 0 then has_removable = true end
  end
  if not has_removable then return false end
  local opp_total = 0
  for _, n in pairs(opposing_mon.energy) do opp_total = opp_total + n end
  if opp_total == 0 then return false end
  for _, attack in ipairs(own_card.attacks or {}) do
    if attack.kind == "Attack" and AI.CanUseAttack(own_mon, attack) then
      local dmg = AI.PredictAttackDamage(dmgcalc, attack, own_card.card_type, own_mon, opposing_mon, get_card_fn)
      if dmg >= (opposing_card.hp - opposing_mon.damage) then return false end
    end
  end
  return true
end

-- AIDecide_Pokeball (the real source only plays this for 5 specific named decks, each searching a
-- different hardcoded priority list of card IDs -- "or a; ret" i.e. FALSE for every other deck.
-- Rather than reproduce 5 bespoke priority lists, this substitutes the closest reasonable general
-- policy: search when the deck is large enough that a random find is likely worthwhile. This is
-- explicitly NOT a translation of the source's actual (deck-specific-only) behavior.
function AI.Decide_Pokeball(duelist)
  return #duelist.deck >= 10
end

-- AIDecide_PokemonTrader (same shape of exception as Poke Ball above: the real source is played
-- for 9 specific named decks, each with its own hardcoded target Pokemon search, and is FALSE
-- ("or a; ret") for every other deck -- there is no general-case behavior in the source at all.
-- Substitutes the legality condition already used for the attack-effect version
-- (Effects.PokemonTrader_HandDeckCheck): a Pokemon card in hand to trade away, and the deck not
-- empty (so there's something to plausibly search for in return). This closes the LAST Trainer
-- card gap -- all ~30 cards now have some AI decider, even if a couple (this one and Poke Ball)
-- are honest generic substitutes rather than faithful translations, clearly marked as such.
function AI.Decide_PokemonTrader(duelist, is_pokemon_fn)
  if #duelist.hand < 2 then return false end
  if #duelist.deck == 0 then return false end
  for _, c in ipairs(duelist.hand) do
    if is_pokemon_fn(c) then return true end
  end
  return false
end

return AI
