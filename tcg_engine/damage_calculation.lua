-- Pokemon Trading Card Game (GBC) - Damage calculation engine
-- Source: src/home/duel.asm (ApplyDamageModifiers_DamageToTarget / _DamageToSelf)
--
-- === WHAT THIS FILE IS ===
-- The exact damage-modifier pipeline, translated line-for-line: this is the real order of
-- operations the original game applies to every attack's base damage before it lands. Order
-- matters and is preserved exactly: Weakness (x2) -> Resistance (-30) -> PlusPower (+10 each) ->
-- Defender (-20 each) -> clamp negative results to 0.
--
-- === HOW THIS FILE CONNECTS TO THE OTHERS ===
-- Card type/weakness/resistance values come from card_database.lua (fields: card_type, weakness,
-- resistance). PlusPower/Defender counts come from a Pokemon table's .pluspower_count/
-- .defender_count fields (engine_runtime.lua's Pokemon schema). Called by ai_engine.lua (to
-- predict damage for move selection) and duel_engine.lua (to resolve real attacks).

local DamageCalc = {}

-- WR_* weakness/resistance mapping: a Pokemon's card_type IS its own weakness/resistance target
-- color in this game (i.e. "weak to Fire" means the attacker's type must equal "Fire").
-- ComputeDamage(base_damage, attacker_type, defender, opts) -> final_damage, effectiveness
--   defender: a Pokemon table with .weakness, .resistance (strings, e.g. "Fire", or nil),
--             .pluspower_count, .defender_count, and optional .changed_weakness/.changed_resistance
--             (Conversion1/2-style overrides, checked in preference to the card's printed values)
--   opts: { unaffected_by_weakness_resistance = bool, halve_damage = bool (Light Screen-style),
--           reduce_by = number (Minimize/Expand/Snivel-style flat reduction on top of the above),
--           prevent_less_than = number (Harden-style floor -- final damage can't go below this
--           UNLESS it would go below 0, matching the source's clamp-to-0 always taking priority) }
function DamageCalc.ComputeDamage(base_damage, attacker_type, defender, opts)
  opts = opts or {}
  if base_damage == 0 then return 0, {} end

  local effectiveness = {}
  local damage = base_damage

  local unaffected = opts.unaffected_by_weakness_resistance
  if not unaffected then
    local weakness = defender.changed_weakness or defender.weakness
    local resistance = defender.changed_resistance or defender.resistance
    if weakness and weakness == attacker_type then
      damage = damage * 2
      effectiveness.weakness = true
    end
    if resistance and resistance == attacker_type then
      damage = damage - 30
      effectiveness.resistance = true
    end
  end

  -- PlusPower: applied to the ATTACKER's side (+10 per attached PlusPower)
  damage = damage + 10 * (opts.attacker_pluspower_count or 0)
  -- Defender: applied to the DEFENDER's side (-20 per attached Defender)
  damage = damage - 20 * (defender.defender_count or 0)

  if opts.halve_damage then
    damage = math.floor(damage / 2)
  end
  if opts.reduce_by then
    damage = damage - opts.reduce_by
  end
  if opts.prevent_less_than and damage > 0 and damage < opts.prevent_less_than then
    damage = opts.prevent_less_than
  end

  if damage < 0 then damage = 0 end
  return damage, effectiveness
end

-- Convenience wrapper reading straight from card_database.lua-shaped data: given the attacker's
-- card_type string and the defender Pokemon's card_label, look up weakness/resistance via a
-- supplied card lookup function (e.g. built from card_database.lua) rather than requiring the
-- caller to pre-extract them.
function DamageCalc.ComputeDamageForCards(base_damage, attacker_card_type, defender_mon, get_card_fn, opts)
  local defender_card = get_card_fn(defender_mon.card_label)
  local defender_view = {
    weakness = defender_card and defender_card.weakness,
    resistance = defender_card and defender_card.resistance,
    changed_weakness = defender_mon.changed_weakness,
    changed_resistance = defender_mon.changed_resistance,
    defender_count = defender_mon.defender_count,
  }
  return DamageCalc.ComputeDamage(base_damage, attacker_card_type, defender_view, opts)
end

return DamageCalc
