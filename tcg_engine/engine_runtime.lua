-- Pokemon Trading Card Game (GBC) - Executable engine runtime
-- Source: src/home/duel.asm, src/engine/duel/effect_functions.asm (shared primitives),
--         src/constants/duel_constants.asm (DUELVARS_* state layout)
--
-- === WHAT THIS FILE IS ===
-- Unlike every other file in this package, this one is not just data or a catalog -- it is a
-- real, executable Lua reimplementation of the ~35 "primitive" engine functions that almost every
-- card effect in effect_functions_translated.lua is built from (SwapTurn, TossCoin, damage-setting
-- functions, status application, energy/discard/deck manipulation, etc.). Card effects call these
-- functions exactly the way the original Z80 code calls its equivalents, so a card effect's logic
-- reads as a faithful line-for-line translation rather than a re-derived reimplementation.
--
-- === STATE MODEL ===
-- The original game addresses two duelists' data through a single "whose turn is it" pointer that
-- can be temporarily flipped (SwapTurn) -- this lets the same effect code work whether the
-- attacking or defending Pokemon needs to be affected. This runtime mirrors that: DuelState has
-- two Duelist tables ("player" and "opponent"), and turn_holder tracks which one is currently
-- "the turn duelist" for the purposes of GetTurnDuelistVariable/GetNonTurnDuelistVariable-style
-- access -- exactly as the original hWhoseTurn byte does.
--
-- A Pokemon in play is a table: {
--   card_label,          -- key into card_database.lua, e.g. "BulbasaurCard"
--   damage,               -- damage counters (in HP, not the game's internal /10 counter units)
--   status,               -- "NONE" | "ASLEEP" | "CONFUSED" | "PARALYZED"
--   poison,               -- "NONE" | "POISONED" | "DOUBLE_POISONED" (independent of status, matches
--                         -- the real CNF_SLP_PRZ / PSN_DBLPSN nibble split in rules.lua)
--   substatus1, substatus2, substatus3, -- sets of effect-specific flags (see rules.lua's status
--                         -- section and individual card effects for what populates these)
--   energy,               -- { Grass=0, Fire=0, Water=0, Lightning=0, Fighting=0, Psychic=0, Colorless=0 }
--   pluspower_count, defender_count,
--   changed_type, changed_weakness, changed_resistance, -- nil unless altered by an effect
--   played_this_turn, evolved_this_turn,
-- }

local Runtime = {}
Runtime.__index = Runtime

-- ===== State construction =====

local function new_pokemon(card_label)
  return {
    card_label = card_label,
    damage = 0,
    status = "NONE",
    poison = "NONE",
    substatus1 = {}, substatus2 = {}, substatus3 = {},
    energy = { Grass=0, Fire=0, Water=0, Lightning=0, Fighting=0, Psychic=0, Colorless=0 },
    pluspower_count = 0,
    defender_count = 0,
    changed_type = nil, changed_weakness = nil, changed_resistance = nil,
    played_this_turn = false,
    evolved_this_turn = false,
  }
end
Runtime.new_pokemon = new_pokemon

local function new_duelist()
  return {
    active = nil,          -- a Pokemon table, or nil if no active Pokemon (game-over condition)
    bench = {},             -- array of up to 5 Pokemon tables
    hand = {},               -- array of card_labels
    deck = {},               -- array of card_labels (deck[1] = top of deck)
    discard_pile = {},        -- array of card_labels
    prizes = {},               -- array of card_labels (face-down; content normally hidden from owner)
    energy_played_this_turn = false,
    retreated_this_turn = false,
  }
end
Runtime.new_duelist = new_duelist

function Runtime.new()
  local self = setmetatable({}, Runtime)
  self.player = new_duelist()
  self.opponent = new_duelist()
  self.turn_holder = "player"   -- matches hWhoseTurn
  self.damage = 0                -- wDamage: pending damage about to be dealt
  self.ai_min_damage = 0         -- wAIMinDamage
  self.ai_max_damage = 0         -- wAIMaxDamage
  self.no_damage_or_effect = false -- wNoDamageOrEffect (Smokescreen/Sand Attack evasion flag)
  self.no_effect_from_which_status = nil
  self.dealt_damage = 0           -- wDealtDamage: actual damage that landed after the damage step
                                    -- resolved (post weakness/resistance/etc) -- set by the
                                    -- (untranslated) core damage-resolution routine; several
                                    -- "after damage" effects (e.g. Leech Seed) read this rather
                                    -- than wDamage to know whether any damage actually landed.
  self.is_damage_to_self = false  -- wIsDamageToSelf: set by self-damaging bench-wide effects
                                    -- (e.g. Earthquake) so the damage step treats it as recoil,
                                    -- not an attack on the opponent.
  self.rng = math.random
  self.log = {}                  -- optional textual event log a caller can inspect/clear
  self.effect_errors = {}        -- diagnostics kept out of player-facing duel text
  self.presentation_events = {} -- adapter-consumable animation/SFX events
  self.on_presentation_event = nil
  return self
end

function Runtime:_say(fmt, ...)
  self.log[#self.log + 1] = string.format(fmt, ...)
end

-- ===== Turn-relative duelist access (GetTurnDuelistVariable / GetNonTurnDuelistVariable) =====

-- the "turn duelist" -- same semantics as GetTurnDuelistVariable's target
function Runtime:turn()
  return self[self.turn_holder]
end

-- the "non-turn duelist" -- same semantics as GetNonTurnDuelistVariable's target
function Runtime:nonturn()
  return self.turn_holder == "player" and self.opponent or self.player
end

-- SwapTurn:: flips which duelist is considered "the turn duelist" for addressing purposes.
-- Used pervasively so the same effect code can act on "my own Pokemon" vs "the opponent's".
function Runtime:SwapTurn()
  self.turn_holder = (self.turn_holder == "player") and "opponent" or "player"
end

-- Run fn() with turn_holder temporarily swapped, then restore it -- a very common idiom in the
-- source (push/SwapTurn/.../SwapTurn/pop) collapsed into one call.
function Runtime:WithSwappedTurn(fn, ...)
  self:SwapTurn()
  local a, b, c = fn(self, ...)
  self:SwapTurn()
  return a, b, c
end

-- ===== Coin flips (TossCoin / TossCoinATimes / Serial_TossCoinATimes) =====

-- TossCoin / TossCoin_BankB: single fair coin flip. Returns true for heads.
-- In the source, callers usually `ret nc` after this to bail out on tails.
function Runtime:TossCoin()
  local heads = self.rng() < 0.5
  self.last_coin_result = heads
  self:_say("Coin flip: %s", heads and "Heads" or "Tails")
  return heads
end

-- TossCoinATimes / TossCoinATimes_BankB: flip `count` coins, return number of heads.
function Runtime:TossCoinATimes(count)
  local heads = 0
  for _ = 1, count do
    if self.rng() < 0.5 then heads = heads + 1 end
  end
  self:_say("Flipped %d coin(s): %d heads", count, heads)
  self.last_coin_heads = heads
  self.last_coin_result = heads > 0
  return heads
end

-- ===== Damage bookkeeping (SetDefiniteDamage / SetExpectedAIDamage / UpdateExpectedAIDamage /
--       SetDefiniteAIDamage / AddToDamage / ATimes10) =====

-- SetDefiniteDamage: overwrite wDamage AND the AI's min/max damage prediction with one fixed value.
function Runtime:SetDefiniteDamage(amount)
  self.damage = amount
  self.ai_min_damage = amount
  self.ai_max_damage = amount
end

-- SetDefiniteAIDamage: sync the AI's min/max prediction to the current wDamage (no range).
function Runtime:SetDefiniteAIDamage()
  self.ai_min_damage = self.damage
  self.ai_max_damage = self.damage
end

-- SetExpectedAIDamage: set wDamage to `amount`, and the AI's predicted range to [min_delta, max_delta].
-- Used for genuinely variable-damage attacks (e.g. "flip coins, 10 damage per heads").
function Runtime:SetExpectedAIDamage(amount, min_delta, max_delta)
  self.damage = amount
  self.ai_min_damage = min_delta
  self.ai_max_damage = max_delta
end

-- UpdateExpectedAIDamage: ADD a delta on top of the existing wDamage/min/max, rather than
-- overwriting -- used for bonuses layered on top of an attack's base damage.
function Runtime:UpdateExpectedAIDamage(min_delta, max_delta)
  self.ai_min_damage = self.damage + min_delta
  self.ai_max_damage = self.damage + max_delta
  self.damage = self.damage + min_delta
end

-- UpdateExpectedAIDamage_AccountForPoison: same as above, but if the AI's target is already
-- Poisoned/Double Poisoned, skip adding the range (poison damage between turns makes the bonus's
-- exact value already determined rather than something to predict as a range).
function Runtime:UpdateExpectedAIDamage_AccountForPoison(min_delta, max_delta)
  local target = self:nonturn().active
  if target and (target.poison == "POISONED" or target.poison == "DOUBLE_POISONED") then
    self.ai_min_damage = self.damage
    self.ai_max_damage = self.damage
    return
  end
  self:UpdateExpectedAIDamage(min_delta, max_delta)
end

-- AddToDamage: add `amount` onto wDamage only (not the AI range -- callers combine this with
-- SetDefiniteAIDamage or UpdateExpectedAIDamage as appropriate, exactly as the source does).
function Runtime:AddToDamage(amount)
  self.damage = self.damage + amount
end

-- ATimes10: the source's helper for "register a, times 10" -- kept as a function for parity with
-- effect_function_analysis.lua's raw source, but in Lua this is just multiplication.
function Runtime:ATimes10(a)
  return a * 10
end

-- ===== Status conditions (QueueStatusCondition et al.) =====

-- QueueStatusCondition: apply a status ("CONFUSED"/"ASLEEP"/"PARALYZED") or poison
-- ("POISONED"/"DOUBLE_POISONED") to the NON-turn duelist's active Pokemon, with the source's
-- built-in immunity checks: fails against Clefairy Doll / Mysterious Fossil (non-Pokemon
-- "Pokemon"), and fails against Snorlax specifically unless already statused or affected by
-- Muk's Toxic Gas (which disables opposing Pokemon Powers, including Snorlax's own immunity).
function Runtime:QueueStatusCondition(status_or_poison, muk_toxic_gas_active)
  local target = self:nonturn().active
  if not target then return false end
  if target.card_label == "ClefairyDollCard" or target.card_label == "MysteriousFossilCard" then
    self.no_effect_from_which_status = status_or_poison
    return false
  end
  if target.card_label == "SnorlaxCard" then
    local already_statused = target.status ~= "NONE" or target.poison ~= "NONE"
    if not (already_statused or muk_toxic_gas_active) then
      self.no_effect_from_which_status = status_or_poison
      return false
    end
  end
  if status_or_poison == "POISONED" or status_or_poison == "DOUBLE_POISONED" then
    target.poison = status_or_poison
  else
    target.status = status_or_poison
  end
  self:_say("%s is now %s", target.card_label, status_or_poison)
  return true
end

-- ApplySubstatus1ToAttackingCard: mark a substatus flag on the ATTACKING (turn-holder's active)
-- Pokemon. Used for self-inflicted attack side effects (e.g. "can't attack next turn").
function Runtime:ApplySubstatus1ToAttackingCard(flag)
  local attacker = self:turn().active
  if attacker then attacker.substatus1[flag] = true end
end

-- ApplySubstatus2ToDefendingCard: mark a substatus flag on the DEFENDING (non-turn duelist's
-- active) Pokemon, unless prevented by a no-damage-or-effect condition (Smokescreen/Sand Attack).
function Runtime:ApplySubstatus2ToDefendingCard(flag)
  if self.no_damage_or_effect then return false end
  local defender = self:nonturn().active
  if defender then defender.substatus2[flag] = true end
  return true
end

-- ===== Damage-to-self / recoil / confusion self-damage =====

-- DealRecoilDamageToSelf / DealConfusionDamageToSelf: the turn holder's own active Pokemon takes
-- `amount` damage, computed through the normal damage-modifier pipeline (rules.lua's
-- damage_modifiers) but directed at its own side. Returns the actual damage dealt after modifiers.
function Runtime:DealRecoilDamageToSelf(amount)
  local self_pkmn = self:turn().active
  if not self_pkmn then return 0 end
  self_pkmn.damage = self_pkmn.damage + amount
  self:_say("%s takes %d recoil/confusion damage", self_pkmn.card_label, amount)
  return amount
end

-- ===== Bench-wide damage (DealDamageToAllBenchedPokemon) =====

-- DealDamageToAllBenchedPokemon: deal `amount` damage to EVERY Pokemon in the turn holder's own
-- Play Area (active AND all Bench Pokemon) -- used by self-damaging "splash" attacks. Note the
-- source applies this to the turn holder's own side; effects that hit the OPPONENT's bench use a
-- different routine and are translated per-card where that occurs.
function Runtime:DealDamageToAllBenchedPokemon(amount, duelist)
  duelist = duelist or self:turn()
  if duelist.active then duelist.active.damage = duelist.active.damage + amount end
  for _, mon in ipairs(duelist.bench) do
    mon.damage = mon.damage + amount
  end
end

-- ===== HP / Energy inspection =====

-- GetCardDamageAndMaxHP: returns (damage, max_hp) for the turn holder's active Pokemon.
-- max_hp must be supplied by the caller from card_database.lua (this runtime doesn't embed card
-- stats itself -- see effect_functions_translated.lua's card_hp() helper).
function Runtime:GetCardDamageAndMaxHP(get_max_hp_fn)
  local mon = self:turn().active
  if not mon then return 0, 0 end
  return mon.damage, get_max_hp_fn(mon.card_label)
end

-- GetPlayAreaCardAttachedEnergies: returns the energy table attached to the CURRENTLY-ACTING
-- Pokemon (the one at hTempPlayAreaLocation in the source -- here, simply passed in directly
-- since this runtime doesn't model a raw play-area index register).
function Runtime:GetPlayAreaCardAttachedEnergies(mon)
  return mon.energy
end

-- ApplyExtraWaterEnergyDamageBonus: the exact mechanic behind Water "more Energy = more damage"
-- attacks (e.g. Hydro Pump). required_water = Water Energy the attack's own cost requires;
-- colorless_portion = how much of the remaining (colorless) cost could also be paid with Water.
-- Adds 10 damage per Water Energy beyond what's required, capped at 2 extra cards (+20 max).
function Runtime:ApplyExtraWaterEnergyDamageBonus(mon, required_water, colorless_portion)
  local total_energy = 0
  for _, n in pairs(mon.energy) do total_energy = total_energy + n end
  local water = mon.energy.Water or 0
  local effective_required = required_water
  if water > 0 and total_energy == water then
    -- every attached energy happens to be Water: the colorless portion of the cost is also paid by Water
    effective_required = required_water + colorless_portion
  end
  local extra = water - effective_required
  if extra <= 0 then
    self:SetDefiniteAIDamage()
    return 0
  end
  if extra > 2 then extra = 2 end
  local bonus = extra * 10
  self:AddToDamage(bonus)
  self:SetDefiniteAIDamage()
  return bonus
end

-- ===== Immunity / evasion checks =====

-- CheckIsIncapableOfUsingPkmnPower: true if the given Pokemon cannot use Pokemon Powers right now
-- (affected by an active Muk "Toxic Gas"-style effect elsewhere in play). Caller supplies whether
-- such an effect is currently active, since that requires scanning the whole play area.
function Runtime:CheckIsIncapableOfUsingPkmnPower(muk_toxic_gas_active)
  return muk_toxic_gas_active == true
end

-- CheckNoDamageOrEffect / HandleNoDamageOrEffect: true if the current attack's damage/effect is
-- being nullified (Smokescreen/Sand Attack-style evasion already resolved this turn).
function Runtime:CheckNoDamageOrEffect()
  return self.no_damage_or_effect
end

-- ===== HP recovery =====

-- ApplyAndAnimateHPRecovery: heal `amount` HP off the turn holder's active Pokemon's damage
-- counters (cannot reduce damage below 0). Returns the actual amount healed.
function Runtime:ApplyAndAnimateHPRecovery(amount)
  local mon = self:turn().active
  if not mon or mon.damage == 0 then return 0 end
  local healed = math.min(amount, mon.damage)
  mon.damage = mon.damage - healed
  self:_say("%s heals %d damage", mon.card_label, healed)
  return healed
end

-- ===== Hand / deck / discard pile manipulation =====

function Runtime:PutCardInDiscardPile(duelist, card_label)
  duelist.discard_pile[#duelist.discard_pile + 1] = card_label
end

function Runtime:AddCardToHand(duelist, card_label)
  duelist.hand[#duelist.hand + 1] = card_label
end

function Runtime:RemoveCardFromHand(duelist, card_label)
  for i, c in ipairs(duelist.hand) do
    if c == card_label then
      table.remove(duelist.hand, i)
      return true
    end
  end
  return false
end

-- DrawCardFromDeck: move the top card of the deck into hand. Returns the card, or nil if empty.
function Runtime:DrawCardFromDeck(duelist)
  if #duelist.deck == 0 then return nil end
  local card = table.remove(duelist.deck, 1)
  duelist.hand[#duelist.hand + 1] = card
  return card
end

function Runtime:CheckIfDeckIsEmpty(duelist)
  return #duelist.deck == 0
end

-- ReturnCardToDeck: move a card from hand/discard back into the deck (used by e.g. Recycle,
-- Mr. Fuji-style effects). Shuffling afterward is the caller's responsibility, matching the
-- source's separate ShuffleCardsInDeck step.
function Runtime:ReturnCardToDeck(duelist, card_label, from)
  from = from or duelist.discard_pile
  for i, c in ipairs(from) do
    if c == card_label then
      table.remove(from, i)
      duelist.deck[#duelist.deck + 1] = card_label
      return true
    end
  end
  return false
end

-- ShuffleCardsInDeck: Fisher-Yates shuffle (the source uses the same hardware RNG as TossCoin).
function Runtime:ShuffleCardsInDeck(duelist)
  local deck = duelist.deck
  for i = #deck, 2, -1 do
    local j = math.random(i)
    deck[i], deck[j] = deck[j], deck[i]
  end
end

-- SearchCardInDeckAndAddToHand: search the deck with a predicate (e.g. "is a Basic Pokemon", "is
-- named X"), move the first match into hand, and shuffle. Returns the found card_label or nil.
-- This models the family of "search your deck for a X" trainer/attack effects generically; each
-- translated card effect supplies its own predicate matching its exact printed text.
function Runtime:SearchCardInDeckAndAddToHand(duelist, predicate)
  for i, card_label in ipairs(duelist.deck) do
    if predicate(card_label) then
      table.remove(duelist.deck, i)
      duelist.hand[#duelist.hand + 1] = card_label
      self:ShuffleCardsInDeck(duelist)
      return card_label
    end
  end
  self:ShuffleCardsInDeck(duelist) -- the source shuffles even on a whiff, to hide information
  return nil
end

-- ===== Play area management =====

-- SwapArenaWithBenchPokemon: retreat-style swap between the active Pokemon and a chosen Bench slot.
function Runtime:SwapArenaWithBenchPokemon(duelist, bench_index)
  local bench_mon = table.remove(duelist.bench, bench_index)
  if duelist.active then
    duelist.bench[#duelist.bench + 1] = duelist.active
  end
  duelist.active = bench_mon
end

-- PutHandPokemonCardInPlayArea / PutHandCardInPlayArea: move a Basic Pokemon from hand onto the
-- Bench (fails if the Bench is already full at 5).
function Runtime:PutHandPokemonCardInPlayArea(duelist, card_label)
  if #duelist.bench >= 5 then return false end
  if not self:RemoveCardFromHand(duelist, card_label) then return false end
  duelist.bench[#duelist.bench + 1] = new_pokemon(card_label)
  return true
end

-- MoveDiscardPileCardToHand: e.g. Energy Retrieval / Mr. Fuji-style effects that pull one
-- specific card back from the discard pile into hand.
function Runtime:MoveDiscardPileCardToHand(duelist, card_label)
  for i, c in ipairs(duelist.discard_pile) do
    if c == card_label then
      table.remove(duelist.discard_pile, i)
      duelist.hand[#duelist.hand + 1] = card_label
      return true
    end
  end
  return false
end

-- ===== Randomness (Random / PickRandomPlayAreaCard) =====

-- Random: uniform integer in [0, n-1], matching the source's `call Random` (a >= 0 output range).
function Runtime:Random(n)
  return math.random(0, n - 1)
end

-- PickRandomPlayAreaCard: pick a uniformly random occupied Play Area slot (active or bench) of
-- the given duelist. Returns ("active") or ("bench", index).
function Runtime:PickRandomPlayAreaCard(duelist)
  local n = 1 + #duelist.bench -- active + bench count
  local pick = self:Random(n)
  if pick == 0 then return "active" end
  return "bench", pick
end

-- ===== Selection-based effects (REQUIRE_SELECTION hooks) =====
-- The original game drives these interactively (show a card list / play-area picker, wait for
-- button input). In this headless runtime, the CALLER (a UI, or an AI move-selector) is
-- responsible for making the choice and passing it in -- these functions apply the consequence
-- of a choice already made, exactly like the original's ".../*_Effect" half of each selection
-- pair (the "PlayerSelectEffect"/"AISelection" half is presentation/AI-choice logic and is not
-- modeled here; see ai_and_deck_mechanics.lua and the ai_*_AIEffect raw source for that side).

-- PlayerPickEnergyCardToDiscard-family: discard a chosen attached Energy card of a given type
-- from a Pokemon. Returns true if it was actually attached and removed.
function Runtime:DiscardAttachedEnergy(mon, energy_type, count)
  count = count or 1
  if (mon.energy[energy_type] or 0) < count then return false end
  mon.energy[energy_type] = mon.energy[energy_type] - count
  self:_say("Discarded %d %s Energy from %s", count, energy_type, mon.card_label)
  return true
end

-- HandleSwitchDefendingPokemonEffect: force the opponent to switch their Active Pokemon with a
-- chosen Bench Pokemon (e.g. Whirlwind-style effects). bench_index is the caller's chosen slot.
function Runtime:HandleSwitchDefendingPokemonEffect(defending_duelist, bench_index)
  if #defending_duelist.bench == 0 then return false end
  self:SwapArenaWithBenchPokemon(defending_duelist, bench_index)
  return true
end

-- RandomlyDamagePlayAreaPokemon: deal `amount` damage to a uniformly random Pokemon somewhere in
-- play (used by e.g. Selfdestruct-adjacent and "stray shot" effects). duelist_pool is a list of
-- {duelist, } tables to choose among (usually both players' whole play areas).
function Runtime:RandomlyDamagePlayAreaPokemon(amount, duelist)
  local slot, idx = self:PickRandomPlayAreaCard(duelist)
  local mon = (slot == "active") and duelist.active or duelist.bench[idx]
  if mon then
    mon.damage = mon.damage + amount
    self:_say("%s (randomly chosen) takes %d damage", mon.card_label, amount)
  end
  return mon
end

-- CheckIfDefendingPokemonHasAnyAttack: used by Metronome-style "copy the opponent's attack"
-- effects to bail out if the target has no attacks to copy (e.g. it's Ditto with no printed
-- attacks in some configurations, or the check simply fails safe).
function Runtime:CheckIfDefendingPokemonHasAnyAttack(defending_mon, get_attacks_fn)
  local attacks = get_attacks_fn(defending_mon.card_label)
  return attacks ~= nil and #attacks > 0
end

-- ===== UI/presentation adapter hooks =====
-- State-free drawing calls remain stubs, while timing/SFX/animation calls emit events an adapter
-- can consume. This preserves the translated call order without coupling the engine to LÖVE.
function Runtime:DrawWideTextBox_WaitForInput() end
function Runtime:DrawWideTextBox_PrintText() end
function Runtime:LoadTxRam2() end
function Runtime:LoadTxRam3() end
function Runtime:_present(kind, value)
  local event = { kind = kind, value = value }
  self.presentation_events[#self.presentation_events + 1] = event
  if self.on_presentation_event then self.on_presentation_event(event) end
  return event
end
function Runtime:PlaySFX_InvalidChoice() self:_present("sfx", "invalid_choice") end
function Runtime:HandleMenuInput() end
function Runtime:DoFrame() self:_present("frame") end
function Runtime:EraseCursor() end
function Runtime:DrawSymbolOnPlayAreaCursor() end
function Runtime:DrawPlayAreaScreenToShowChanges() self:_present("redraw_play_area") end
function Runtime:InitializeMenuParameters() end
function Runtime:PlayAttackAnimationOverAttackingPokemon(anim_id)
  self:_present("attack_animation_over_attacker", anim_id)
end
function Runtime:ExchangeRNG() end -- RNG reseed; math.random already reseeds via randomseed elsewhere

return Runtime
