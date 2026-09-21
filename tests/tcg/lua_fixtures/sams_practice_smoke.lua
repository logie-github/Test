-- Behavioral smoke test for Sam's practice-duel scripted AI (engine/duel/
-- ai/decks/sams_practice.asm AIPerformScriptedTurn and its 7 per-turn
-- branches, plus IsAIPracticeScriptedTurn), run under real LuaJIT.
--
-- Each of the 7 scripted turns is tested independently: rather than
-- re-deriving where every card would land by replaying turns 0-3 in this
-- fixture (a full duel-engine simulation this AI-only test doesn't own),
-- each `do` block hand-builds the exact Play Area/hand state
-- AI:performSamScriptedTurn's own code already assumes for that turn (e.g.
-- turn 4's retreat helper asserts the Arena holds Raticate -- that
-- precondition is set up directly rather than derived), and checks that the
-- turn's own production logic reacts to it correctly. This proves the
-- logic under real execution without this test having to be the arbiter of
-- exactly how turns 1-3 fill the Play Area on real hardware.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")
local bit = require("bit")

local C = {
  PLAY_AREA_ARENA = 0, PLAY_AREA_BENCH_1 = 1, PLAY_AREA_BENCH_2 = 2, MAX_PLAY_AREA_POKEMON = 6,
  DUELVARS_ARENA_CARD = 100, DUELVARS_ARENA_CARD_STAGE = 110, DUELVARS_ARENA_CARD_STATUS = 120,
  DUELVARS_HAND = 130, DUELVARS_NUMBER_OF_CARDS_IN_HAND = 140,
  CARD_LOCATION_PLAY_AREA = 0x10, CARD_LOCATION_DISCARD_PILE = 2,
  TYPE_ENERGY = 8, TYPE_TRAINER = 9, BASIC = 0,
  FIRST_ATTACK_OR_PKMN_POWER = 0,
  TRUE = 1,
  MACHOP = 100, RATTATA = 101, RATICATE = 102,
  FIGHTING_ENERGY = 200, LIGHTNING_ENERGY = 201,
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

local CARD_ROWS = {
  [C.MACHOP] = { type = 0, retreatCost = 1 },
  [C.RATTATA] = { type = 0, retreatCost = 1 },
  [C.RATICATE] = { type = 0, retreatCost = 1 },
  [C.FIGHTING_ENERGY] = { type = C.TYPE_ENERGY },
  [C.LIGHTNING_ENERGY] = { type = C.TYPE_ENERGY },
}

-- opts.playArea = {[slot]={deckIndex=.., cardId=..}}, opts.hand = {{deckIndex=.., cardId=..}, ...}
-- opts.attackUsable, opts.playSlotForNewBasic (slot the next putHandPokemonCardInPlayArea call uses)
local function newHarness(opts)
  local turn = {}
  local playArea = {} -- slot -> deckIndex
  local cardIdByDeckIndex = {}
  local location = {} -- deckIndex -> location code (used by _attachedEnergyDeckIndices)

  for slot, card in pairs(opts.playArea or {}) do
    playArea[slot] = card.deckIndex
    cardIdByDeckIndex[card.deckIndex] = card.cardId
    location[card.deckIndex] = bit.bor(C.CARD_LOCATION_PLAY_AREA, slot)
    turn[C.DUELVARS_ARENA_CARD + slot] = card.deckIndex
  end
  for slot = 0, C.MAX_PLAY_AREA_POKEMON - 1 do
    if turn[C.DUELVARS_ARENA_CARD + slot] == nil then turn[C.DUELVARS_ARENA_CARD + slot] = 0xff end
  end
  for _, e in ipairs(opts.attachedEnergy or {}) do
    cardIdByDeckIndex[e.deckIndex] = e.cardId
    location[e.deckIndex] = bit.bor(C.CARD_LOCATION_PLAY_AREA, e.slot)
  end

  local hand = {}
  for _, card in ipairs(opts.hand or {}) do
    hand[#hand + 1] = card.deckIndex
    cardIdByDeckIndex[card.deckIndex] = card.cardId
  end
  turn[C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = #hand
  for i, deckIndex in ipairs(hand) do turn[C.DUELVARS_HAND + (i - 1)] = deckIndex end

  local hramBytes, wramBytes = {}, {}
  local addresses = { hTempRetreatCostCards = 2000, wDuelTempList = 3000 }
  local words = { wDuelTurns = opts.wDuelTurns or 0 }

  local memory = {
    readSymbol8 = function(_, name) return words[name] or 0 end,
    writeSymbol8 = function(_, name, v) words[name] = v end,
    address = function(_, name) return addresses[name] or 0, 0 end,
    read8 = function(_, kind, addr, bank)
      return (kind == "hram" and hramBytes[addr] or wramBytes[addr]) or 0
    end,
    write8 = function(_, kind, addr, value, bank)
      if kind == "hram" then hramBytes[addr] = value else wramBytes[addr] = value end
    end,
  }

  local calls = {}
  local duelOps = {
    putHandPokemonCardInPlayArea = function(_, deckIndex)
      local slot = assert(opts.playSlotForNewBasic, "test must set playSlotForNewBasic")
      calls[#calls + 1] = { fn = "putHandPokemonCardInPlayArea", deckIndex = deckIndex, slot = slot }
      turn[C.DUELVARS_ARENA_CARD + slot] = deckIndex
      location[deckIndex] = bit.bor(C.CARD_LOCATION_PLAY_AREA, slot)
      return slot, false
    end,
    putHandCardInPlayArea = function(_, energyIndex, slot)
      calls[#calls + 1] = { fn = "putHandCardInPlayArea", energyIndex = energyIndex, slot = slot }
      location[energyIndex] = bit.bor(C.CARD_LOCATION_PLAY_AREA, slot)
    end,
    evolvePokemonCardIfPossible = function(_, evolutionIndex, slot)
      calls[#calls + 1] = { fn = "evolvePokemonCardIfPossible", evolutionIndex = evolutionIndex, slot = slot }
      turn[C.DUELVARS_ARENA_CARD + slot] = evolutionIndex
      location[evolutionIndex] = bit.bor(C.CARD_LOCATION_PLAY_AREA, slot)
      return true
    end,
    swapArenaWithBenchPokemon = function(_, targetSlot)
      calls[#calls + 1] = { fn = "swapArenaWithBenchPokemon", targetSlot = targetSlot }
    end,
    putCardInDiscardPile = function(_, discard)
      calls[#calls + 1] = { fn = "putCardInDiscardPile", discard = discard }
    end,
    removeCardFromDuelTempList = function(_, discard)
      calls[#calls + 1] = { fn = "removeCardFromDuelTempList", discard = discard }
    end,
  }

  local ai = AI.new(
    memory,
    { get = function(_, a) return turn[a] or 0 end, getNonTurn = function() return 0 end, swapTurn = function() end },
    { random = function() return 0 end, shuffleCards = function() end },
    {
      getCardIDFromDeckIndex = function(_, deckIndex) return cardIdByDeckIndex[deckIndex] end,
      get = function(_, cardId) return CARD_ROWS[cardId] end,
    },
    duelOps,
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
  -- _attachedEnergyDeckIndices scans raw deckIndex 0..DECK_SIZE-1 via
  -- duelVars:get(deckIndex) for the location code; back it with `location`.
  C.DECK_SIZE = C.DECK_SIZE or 20
  local rawDuelVars = ai.duelVars
  ai.duelVars = {
    get = function(_, a)
      if turn[a] ~= nil then return turn[a] end
      return location[a] or 0
    end,
    set = function(_, a, v) turn[a] = v end,
    getNonTurn = rawDuelVars.getNonTurn,
    swapTurn = rawDuelVars.swapTurn,
  }
  ai:setCombat({
    checkAttackUsable = function(_, deckIndex, attackIndex) return opts.attackUsable == true end,
    useAttack = function(_, deckIndex, attackIndex, o)
      calls[#calls + 1] = { fn = "useAttack", deckIndex = deckIndex, attackIndex = attackIndex }
      return true, "attacked"
    end,
    core = { clearNonTurnTemporaryDuelvars = function() end },
  })
  return ai, calls
end

-- isSamPracticeScriptedTurn: carry once AI has taken >= 7 turns
-- (wDuelTurns counts half-turns, so >= 14 means turn index >= 7).
do
  local ai = newHarness({ wDuelTurns = 0 })
  check("scripted turn check: wDuelTurns=0 -> true", ai:isSamPracticeScriptedTurn(), true)
end
do
  local ai = newHarness({ wDuelTurns = 12 })
  check("scripted turn check: wDuelTurns=12 (turn 6) -> true", ai:isSamPracticeScriptedTurn(), true)
end
do
  local ai = newHarness({ wDuelTurns = 14 })
  check("scripted turn check: wDuelTurns=14 (turn 7) -> false", ai:isSamPracticeScriptedTurn(), false)
end

-- Turn 0: attach Fighting Energy to Machop in Arena; then attack.
do
  local ai, calls = newHarness({
    wDuelTurns = 0, attackUsable = true,
    playArea = { [0] = { deckIndex = 1, cardId = C.MACHOP } },
    hand = { { deckIndex = 3, cardId = C.FIGHTING_ENERGY } },
  })
  local ok, result = ai:performSamScriptedTurn()
  check("turn 0: attaches energy to Machop@Arena", calls[1].fn, "putHandCardInPlayArea")
  check("turn 0: energy deck index", calls[1].energyIndex, 3)
  check("turn 0: target slot (Arena)", calls[1].slot, 0)
  check("turn 0: then attacks", calls[2].fn, "useAttack")
  check("turn 0: overall ok", ok, true)
end

-- Turn 1: play Rattata from hand to Bench1, attach Fighting Energy to it.
do
  local ai, calls = newHarness({
    wDuelTurns = 2, attackUsable = false,
    playArea = { [0] = { deckIndex = 1, cardId = C.MACHOP } },
    hand = { { deckIndex = 2, cardId = C.RATTATA }, { deckIndex = 4, cardId = C.FIGHTING_ENERGY } },
    playSlotForNewBasic = C.PLAY_AREA_BENCH_1,
  })
  local ok, result = ai:performSamScriptedTurn()
  check("turn 1: plays Rattata", calls[1].fn, "putHandPokemonCardInPlayArea")
  check("turn 1: Rattata deck index", calls[1].deckIndex, 2)
  check("turn 1: to Bench1", calls[1].slot, C.PLAY_AREA_BENCH_1)
  check("turn 1: attaches energy to it", calls[2].fn, "putHandCardInPlayArea")
  check("turn 1: energy target slot", calls[2].slot, C.PLAY_AREA_BENCH_1)
  check("turn 1: unusable attack -> finish_no_attack", result, "finish_no_attack")
end

-- Turn 2: evolve Rattata (Bench1) into Raticate, attach Lightning Energy.
do
  local ai, calls = newHarness({
    wDuelTurns = 4, attackUsable = false,
    playArea = { [0] = { deckIndex = 1, cardId = C.MACHOP }, [1] = { deckIndex = 2, cardId = C.RATTATA } },
    hand = { { deckIndex = 5, cardId = C.RATICATE }, { deckIndex = 6, cardId = C.LIGHTNING_ENERGY } },
  })
  local ok, result = ai:performSamScriptedTurn()
  check("turn 2: evolves Rattata", calls[1].fn, "evolvePokemonCardIfPossible")
  check("turn 2: evolution deck index (Raticate)", calls[1].evolutionIndex, 5)
  check("turn 2: at Rattata's slot (Bench1)", calls[1].slot, 1)
  check("turn 2: attaches Lightning Energy after evolving", calls[2].fn, "putHandCardInPlayArea")
  check("turn 2: to the now-Raticate slot", calls[2].slot, 1)
end

-- Turn 3: attach a second Lightning Energy to Raticate (still at Bench1).
do
  local ai, calls = newHarness({
    wDuelTurns = 6, attackUsable = false,
    playArea = { [0] = { deckIndex = 1, cardId = C.MACHOP }, [1] = { deckIndex = 5, cardId = C.RATICATE } },
    hand = { { deckIndex = 7, cardId = C.LIGHTNING_ENERGY } },
  })
  ai:performSamScriptedTurn()
  check("turn 3: attaches second Lightning Energy", calls[1].fn, "putHandCardInPlayArea")
  check("turn 3: energy deck index", calls[1].energyIndex, 7)
  check("turn 3: to Raticate's slot", calls[1].slot, 1)
end

-- Turn 4 (normal case): Raticate already active (Arena), plays a second
-- Machop to the first empty bench slot, attaches Fighting Energy to it
-- (scanning from BENCH_1 so it can't accidentally match the discarded
-- original Machop), then retreats. The bug compares the Arena's DECK INDEX
-- against the MACHOP CARD ID constant -- different namespaces, so in any
-- realistic deck index (here 10, far from the MACHOP id 100) it never
-- fires, and the target stays PLAY_AREA_BENCH_1 ("normal practice").
do
  local ai, calls = newHarness({
    wDuelTurns = 8, attackUsable = false,
    playArea = { [0] = { deckIndex = 10, cardId = C.RATICATE } },
    hand = { { deckIndex = 8, cardId = C.MACHOP }, { deckIndex = 9, cardId = C.FIGHTING_ENERGY } },
    attachedEnergy = { { deckIndex = 6, cardId = C.LIGHTNING_ENERGY, slot = 0 },
                        { deckIndex = 7, cardId = C.LIGHTNING_ENERGY, slot = 0 } },
    playSlotForNewBasic = C.PLAY_AREA_BENCH_1,
  })
  ai:performSamScriptedTurn()
  check("turn 4 (normal): plays second Machop to Bench1", calls[1].fn, "putHandPokemonCardInPlayArea")
  check("turn 4 (normal): to Bench1", calls[1].slot, C.PLAY_AREA_BENCH_1)
  check("turn 4 (normal): attaches energy to bench Machop", calls[2].fn, "putHandCardInPlayArea")
  check("turn 4 (normal): energy target slot", calls[2].slot, C.PLAY_AREA_BENCH_1)
  -- retreat: discards one of the two attached Lightning Energies, then swaps.
  local discardCall, swapCall
  for _, c in ipairs(calls) do
    if c.fn == "putCardInDiscardPile" then discardCall = c end
    if c.fn == "swapArenaWithBenchPokemon" then swapCall = c end
  end
  check("turn 4 (normal): discards one attached Energy", discardCall ~= nil, true)
  check("turn 4 (normal): retreat target is BENCH_1 (bug does not fire)", swapCall.targetSlot, C.PLAY_AREA_BENCH_1)
end

-- Turn 4 (bug-triggering case): a contrived state where the Arena's DECK
-- INDEX happens to numerically equal the MACHOP card ID constant -- proves
-- the exact (mistaken) comparison is preserved, not reimplemented as the
-- presumably-intended card-ID check.
do
  local ai, calls = newHarness({
    wDuelTurns = 8, attackUsable = false,
    playArea = { [0] = { deckIndex = C.MACHOP, cardId = C.RATICATE } }, -- deckIndex == MACHOP id, on purpose
    hand = { { deckIndex = 8, cardId = C.MACHOP }, { deckIndex = 9, cardId = C.FIGHTING_ENERGY } },
    attachedEnergy = { { deckIndex = 6, cardId = C.LIGHTNING_ENERGY, slot = 0 } },
    playSlotForNewBasic = C.PLAY_AREA_BENCH_1,
  })
  ai:performSamScriptedTurn()
  local swapCall
  for _, c in ipairs(calls) do if c.fn == "swapArenaWithBenchPokemon" then swapCall = c end end
  check("turn 4 (bug case): retreat target shifts to BENCH_2", swapCall.targetSlot, C.PLAY_AREA_BENCH_2)
end

-- Turns 5 and 6: attach Fighting Energy to Machop in Arena, same as turn 0.
for _, turnNum in ipairs({ 10, 12 }) do
  local ai, calls = newHarness({
    wDuelTurns = turnNum, attackUsable = true,
    playArea = { [0] = { deckIndex = 1, cardId = C.MACHOP } },
    hand = { { deckIndex = 11, cardId = C.FIGHTING_ENERGY } },
  })
  ai:performSamScriptedTurn()
  check(("turn %d: attaches energy to Machop@Arena"):format(turnNum / 2), calls[1].fn, "putHandCardInPlayArea")
  check(("turn %d: target slot"):format(turnNum / 2), calls[1].slot, 0)
end

if failures == 0 then
  print("all Sam's practice scripted-turn cases passed")
  os.exit(0)
else
  print(("%d Sam's practice scripted-turn case(s) failed"):format(failures))
  os.exit(1)
end
