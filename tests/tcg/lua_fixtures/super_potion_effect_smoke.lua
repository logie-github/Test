-- Behavioral smoke test for the Super Potion Trainer EFFECT (as opposed to
-- the AI decision side, already covered by super_potion_smoke.lua), run
-- under real LuaJIT.
--
-- This closes a real bug found while starting on the card-effects sweep:
-- EffectCommands.lua registered these three handlers under invented names
-- (SuperPotion_DamageCheck / SuperPotion_PlayerSelection /
-- SuperPotion_HealAndDiscardEffect) that do NOT match
-- SuperPotionEffectCommands' real ROM-extracted function pointers
-- (SuperPotion_DamageEnergyCheck / SuperPotion_PlayerSelectEffect /
-- SuperPotion_HealEffect, verified directly against the real engine/duel/
-- effect_commands.asm via tools/tcg/build_manifest.py's own parser) --
-- meaning the real dispatcher (EffectCommands:tryExecute, keyed by the
-- extracted ROM function name) would have reported
-- "untranslated_effect:SuperPotion_DamageEnergyCheck" and failed closed at
-- runtime despite a handler existing under the wrong name. No LuaJIT
-- fixture had ever exercised these handlers at all before this file.
--
-- The gate check (SuperPotion_DamageEnergyCheck) also had a real logic bug:
-- it required damage AND an attached Energy card on the SAME Play Area
-- slot, but the source's CheckIfPlayAreaHasAnyDamage and
-- CheckIfThereAreAnyEnergyCardsAttached are independent whole-play-area
-- scans -- a damaged card and an energized card can be different Pokemon.

package.path = package.path .. ";./?.lua"
local EffectCommands = require("src.tcg.duel.EffectCommands")

local C = {
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = 0x50,
  DUELVARS_ARENA_CARD = 0x60, DUELVARS_ARENA_CARD_HP = 0x70,
  PLAY_AREA_ARENA = 0, PLAY_AREA_BENCH_1 = 1,
}

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(("FAIL  %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
  else
    print(("ok    %s"):format(label))
  end
end

-- opts.playArea = {[slot] = {deckIndex=.., maxHp=.., hp=.., energyCount=..}}
local function newHarness(opts)
  local turn = {}
  local cardById = {}
  local maxCount = 0
  for slot, card in pairs(opts.playArea or {}) do
    turn[C.DUELVARS_ARENA_CARD + slot] = card.deckIndex
    turn[C.DUELVARS_ARENA_CARD_HP + slot] = card.hp
    cardById[card.deckIndex] = { hp = card.maxHp }
    maxCount = math.max(maxCount, slot + 1)
  end
  turn[C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = opts.playAreaCount or maxCount

  local hramBytes = {}
  local addresses = { hTempPlayAreaLocation_ffa1 = 100, hTemp_ffa0 = 101, hTempRetreatCostCards = 102 }
  local words = {}
  local memory = {
    readSymbol8 = function(_, name) return words[name] or 0 end,
    writeSymbol8 = function(_, name, v) words[name] = v end,
    address = function(_, name) return addresses[name] or 0, 0 end,
    read8 = function(_, kind, addr) return hramBytes[addr] or 0 end,
    write8 = function(_, kind, addr, value) hramBytes[addr] = value end,
  }

  local discardCalls = {}
  local actor = {
    memory = memory,
    duelVars = {
      get = function(_, a) return turn[a] or 0 end,
      set = function(_, a, v) turn[a] = v end,
      getNonTurn = function() return 0 end,
      swapTurn = function() end,
    },
    cardData = {
      getCardIDFromDeckIndex = function(_, deckIndex) return deckIndex end,
      get = function(_, cardId) return cardById[cardId] end,
    },
    duelOps = {
      createArenaOrBenchEnergyCardList = function(_, slot)
        local card = (opts.playArea or {})[slot]
        return card and card.energyCount or 0
      end,
      putCardInDiscardPile = function(_, deckIndex)
        discardCalls[#discardCalls + 1] = deckIndex
      end,
    },
  }

  local effects = EffectCommands.new(
    memory, {}, {}, C,
    { schema = 1, byAddress = {}, byLabel = {} },
    {}
  )
  return effects, actor, discardCalls
end

-- SuperPotion_DamageEnergyCheck: independent scans, not same-slot pairing.
do
  -- Damage on Arena, Energy on Bench1 -- different cards -- still passes.
  local effects, actor = newHarness({
    playArea = {
      [0] = { deckIndex = 1, maxHp = 60, hp = 40, energyCount = 0 },
      [1] = { deckIndex = 2, maxHp = 60, hp = 60, energyCount = 1 },
    },
  })
  local carry = effects.handlers["SuperPotion_DamageEnergyCheck"](effects, { playerActions = actor })
  check("damage and energy on different slots -> playable (carry false)", carry, false)
end
do
  -- No damage anywhere -> not playable, regardless of energy.
  local effects, actor = newHarness({
    playArea = {
      [0] = { deckIndex = 1, maxHp = 60, hp = 60, energyCount = 1 },
    },
  })
  local carry = effects.handlers["SuperPotion_DamageEnergyCheck"](effects, { playerActions = actor })
  check("no damage anywhere -> not playable (carry true)", carry, true)
end
do
  -- Damage exists but no energy anywhere -> not playable.
  local effects, actor = newHarness({
    playArea = {
      [0] = { deckIndex = 1, maxHp = 60, hp = 40, energyCount = 0 },
    },
  })
  local carry = effects.handlers["SuperPotion_DamageEnergyCheck"](effects, { playerActions = actor })
  check("damage but no energy anywhere -> not playable (carry true)", carry, true)
end

-- SuperPotion_PlayerSelectEffect: selects a damaged, energized card, caps
-- the heal at 40, relays slot/discard/heal through the HRAM scratch bytes.
do
  local effects, actor = newHarness({
    playArea = { [0] = { deckIndex = 1, maxHp = 100, hp = 40, energyCount = 2 } }, -- 60 damage
  })
  local context = { playerActions = actor, selection = { playArea = 0, discardEnergy = 55 } }
  local carry = effects.handlers["SuperPotion_PlayerSelectEffect"](effects, context)
  check("player select: carry false (success)", carry, false)
  check("player select: relays target slot", actor.memory:readSymbol8("hTempPlayAreaLocation_ffa1"), 0)
  check("player select: relays discard choice", actor.memory:readSymbol8("hTemp_ffa0"), 55)
  check("player select: heal capped at 40 (damage was 60)",
    actor.memory:readSymbol8("hTempRetreatCostCards"), 40)
end
do
  -- Damage below the 40 cap heals for the actual (smaller) amount.
  local effects, actor = newHarness({
    playArea = { [0] = { deckIndex = 1, maxHp = 100, hp = 85, energyCount = 1 } }, -- 15 damage
  })
  local context = { playerActions = actor, selection = { playArea = 0, discardEnergy = 55 } }
  effects.handlers["SuperPotion_PlayerSelectEffect"](effects, context)
  check("player select: heal amount below cap uses actual damage",
    actor.memory:readSymbol8("hTempRetreatCostCards"), 15)
end
do
  -- Selecting a card with no damage is rejected.
  local effects, actor = newHarness({
    playArea = { [0] = { deckIndex = 1, maxHp = 100, hp = 100, energyCount = 1 } },
  })
  local context = { playerActions = actor, selection = { playArea = 0, discardEnergy = 55 } }
  local carry, err = effects.handlers["SuperPotion_PlayerSelectEffect"](effects, context)
  check("player select: no damage on chosen card -> rejected", carry, nil)
  check("player select: rejection reason", err, "invalid_selection:no_damage")
end
do
  -- Selecting a damaged card with no attached Energy is rejected.
  local effects, actor = newHarness({
    playArea = { [0] = { deckIndex = 1, maxHp = 100, hp = 40, energyCount = 0 } },
  })
  local context = { playerActions = actor, selection = { playArea = 0 } }
  local carry, err = effects.handlers["SuperPotion_PlayerSelectEffect"](effects, context)
  check("player select: damaged card with no Energy -> rejected", carry, nil)
  check("player select: rejection reason", err, "invalid_selection:no_energy")
end

-- SuperPotion_HealEffect: applies the relayed heal, discards exactly the
-- relayed Energy card.
do
  local effects, actor, discardCalls = newHarness({
    playArea = { [0] = { deckIndex = 1, maxHp = 100, hp = 40, energyCount = 1 } },
  })
  actor.memory:writeSymbol8("hTempPlayAreaLocation_ffa1", 0)
  actor.memory:writeSymbol8("hTemp_ffa0", 77)
  actor.memory:writeSymbol8("hTempRetreatCostCards", 40)
  local carry = effects.handlers["SuperPotion_HealEffect"](effects, { playerActions = actor })
  check("heal effect: carry false", carry, false)
  check("heal effect: HP increased by the healed amount",
    actor.duelVars:get(C.DUELVARS_ARENA_CARD_HP + 0), 80)
  check("heal effect: discards exactly the relayed Energy card", discardCalls[1], 77)
  check("heal effect: discards nothing else", #discardCalls, 1)
end

if failures == 0 then
  print("all Super Potion effect cases passed")
  os.exit(0)
else
  print(("%d Super Potion effect case(s) failed"):format(failures))
  os.exit(1)
end
