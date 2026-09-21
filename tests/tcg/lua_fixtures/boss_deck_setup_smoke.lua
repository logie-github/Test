-- Behavioral smoke test for the boss-deck StartDuel primitives (AIActionTable_
-- <Boss>'s shared .start_duel sequence: SetUpBossStartingHandAndDeck and
-- TrySetUpBossStartingPlayArea, engine/duel/ai/{boss_deck_set_up,core}.asm),
-- run under real LuaJIT rather than only checked as source text.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  STARTING_HAND_SIZE = 7, DECK_SIZE = 60,
  DUELVARS_HAND = 0x10, DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x1f,
  DUELVARS_DECK_CARDS = 0x20, DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK = 0x60,
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = 0x70,
  TYPE_ENERGY = 8, TYPE_TRAINER = 9, BASIC = 0,
  PLAY_AREA_ARENA = 0, PLAY_AREA_BENCH_1 = 1,
  DUELVARS_ARENA_CARD = 0x80, DUELVARS_ARENA_CARD_HP = 0x90,
  BULBASAUR = 1, SQUIRTLE = 2, CHARMANDER = 3, PIDGEY = 4, RATTATA = 5,
  FIRE_ENERGY = 100, WATER_ENERGY = 101, GRASS_ENERGY = 102,
  BILL = 200,
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
  [C.BULBASAUR] = { type = 0, stage = C.BASIC },
  [C.SQUIRTLE] = { type = 0, stage = C.BASIC },
  [C.CHARMANDER] = { type = 0, stage = C.BASIC },
  [C.PIDGEY] = { type = 0, stage = C.BASIC },
  [C.RATTATA] = { type = 0, stage = C.BASIC },
  [C.FIRE_ENERGY] = { type = C.TYPE_ENERGY },
  [C.WATER_ENERGY] = { type = C.TYPE_ENERGY },
  [C.GRASS_ENERGY] = { type = C.TYPE_ENERGY },
  [C.BILL] = { type = C.TYPE_TRAINER },
}

-- Set by a test just before calling setUpBossStartingHandAndDeck to control
-- exactly what the next shuffleDeck() call arranges.
local nextShuffleArrangement = nil

-- A DuelVars/DuelOps double faithful enough to exercise the real removal/
-- shift interactions setUpBossStartingHandAndDeck depends on: HAND and
-- DECK_CARDS are modeled as real growable/shiftable arrays keyed by
-- duelvars offset, matching how DuelOps:removeCardFromHand/returnCardToDeck/
-- searchCardInDeckAndAddToHand actually mutate them.
local function newHarness(deckIdsInDrawOrder)
  local vars = {}
  local function get(offset) return vars[offset] or 0 end
  local function set(offset, v) vars[offset] = v end

  -- deckIdsInDrawOrder: array of card IDs representing the deck contents in
  -- draw order (index 1 = first to draw). We map each to a synthetic unique
  -- deckIndex (its position) so getCardIDFromDeckIndex is a pure function.
  local cardIdByDeckIndex = {}
  for i, cardId in ipairs(deckIdsInDrawOrder) do cardIdByDeckIndex[i] = cardId end

  set(C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK, 0)
  for i = 1, #deckIdsInDrawOrder do
    set(C.DUELVARS_DECK_CARDS + (i - 1), i)
  end
  set(C.DUELVARS_NUMBER_OF_CARDS_IN_HAND, 0)

  local duelVars = {
    get = function(_, offset) return get(offset) end,
    getNonTurn = function() return nil end,
    set = function(_, offset, v) set(offset, v) end,
  }

  local cardData = {
    getCardIDFromDeckIndex = function(_, deckIndex) return cardIdByDeckIndex[deckIndex] end,
    get = function(_, cardId) return CARD_ROWS[cardId] end,
  }

  local shuffleLog = {}
  local duelOps = {
    removeCardFromHand = function(_, deckIndex)
      local n = get(C.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
      local found
      for i = 0, n - 1 do
        if get(C.DUELVARS_HAND + i) == deckIndex then found = i break end
      end
      assert(found, "removeCardFromHand: not in hand: " .. tostring(deckIndex))
      for i = found, n - 2 do set(C.DUELVARS_HAND + i, get(C.DUELVARS_HAND + i + 1)) end
      set(C.DUELVARS_NUMBER_OF_CARDS_IN_HAND, n - 1)
    end,
    returnCardToDeck = function(_, deckIndex)
      local gone = get(C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK) - 1
      set(C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK, gone)
      set(C.DUELVARS_DECK_CARDS + gone, deckIndex)
    end,
    -- Real ShuffleDeck semantics don't matter for these tests (only that it
    -- gets called when-and-only-when needed); each call installs the next
    -- pre-scripted arrangement from `shuffles` so a test can control exactly
    -- what the "reshuffled" deck looks like.
    shuffleDeck = function()
      shuffleLog[#shuffleLog + 1] = true
      if nextShuffleArrangement then
        for i, deckIndex in ipairs(nextShuffleArrangement) do
          set(C.DUELVARS_DECK_CARDS + (i - 1), deckIndex)
        end
      end
    end,
    -- Faithful port of DuelOps:searchCardInDeckAndAddToHand's shift-remove.
    searchCardInDeckAndAddToHand = function(_, deckIndex)
      local gone = get(C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK)
      local remaining = C.DECK_SIZE - gone
      set(C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK, gone + 1)
      local sourceOffset = C.DUELVARS_DECK_CARDS + C.DECK_SIZE - 1
      local destOffset = sourceOffset
      for _ = 1, remaining do
        local value = get(sourceOffset)
        sourceOffset = sourceOffset - 1
        if value ~= deckIndex then
          set(destOffset, value)
          destOffset = destOffset - 1
        end
      end
    end,
    addCardToHand = function(_, deckIndex)
      local n = get(C.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
      set(C.DUELVARS_HAND + n, deckIndex)
      set(C.DUELVARS_NUMBER_OF_CARDS_IN_HAND, n + 1)
    end,
    createHandCardList = function()
      local n = get(C.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
      local out = {}
      for i = 0, n - 1 do out[#out + 1] = get(C.DUELVARS_HAND + i) end
      return out
    end,
    putHandPokemonCardInPlayArea = function(_, deckIndex)
      local count = get(C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
      set(C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA, count + 1)
      return count, false
    end,
  }

  local ai = AI.new(
    { readSymbol8 = function() return 0 end, writeSymbol8 = function() end },
    duelVars, { random = function() return 5 end }, cardData, duelOps,
    C, { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} }, {}
  )
  return ai, get, set, shuffleLog
end

local function dealStartingHand(set, deckIdsInDrawOrder)
  -- Simulate the ordinary pre-boss-setup deal: draw the first 7 deck slots
  -- into hand, matching the state _start_duel_ finds itself in.
  for i = 0, C.STARTING_HAND_SIZE - 1 do
    set(C.DUELVARS_HAND + i, i + 1)
  end
  set(C.DUELVARS_NUMBER_OF_CARDS_IN_HAND, C.STARTING_HAND_SIZE)
  set(C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK, C.STARTING_HAND_SIZE)
end

-- ---------------------------------------------------------------------
-- setUpBossStartingHandAndDeck: a starting deal that already satisfies both
-- thresholds (>=2 Basic/Energy in the 7, >=4/>=4 across the first 13) needs
-- no reshuffle at all, and ends up with exactly those 7 cards in hand.
-- ---------------------------------------------------------------------
do
  -- Deck draw order (1-indexed): 2 Basic + 2 Energy in the first 7, plus
  -- enough more Basic/Energy in the next 6 to clear the 4/4 bar.
  local order = {
    C.BULBASAUR, C.SQUIRTLE, C.FIRE_ENERGY, C.WATER_ENERGY, C.BILL, C.BILL, C.BILL,
    C.CHARMANDER, C.PIDGEY, C.GRASS_ENERGY, C.FIRE_ENERGY, C.BILL, C.BILL,
  }
  for i = 14, 60 do order[i] = C.BILL end
  local ai, get, set, shuffleLog = newHarness(order)
  dealStartingHand(set, order)

  ai:setUpBossStartingHandAndDeck()
  check("already-sufficient deal: no reshuffle needed", #shuffleLog, 0)
  local hand = {}
  for i = 0, get(C.DUELVARS_NUMBER_OF_CARDS_IN_HAND) - 1 do hand[#hand + 1] = get(C.DUELVARS_HAND + i) end
  table.sort(hand)
  local expected = { 1, 2, 3, 4, 5, 6, 7 }
  local ok = #hand == #expected
  if ok then for i = 1, #hand do ok = ok and hand[i] == expected[i] end end
  check("already-sufficient deal: final hand is exactly the original 7 deck indices", ok, true)
end

-- ---------------------------------------------------------------------
-- A deal that fails the initial 2/2 threshold forces exactly one reshuffle,
-- and the FINAL hand reflects whatever the reshuffle produced (not the
-- original insufficient deal).
-- ---------------------------------------------------------------------
do
  -- Fixed deckIndex -> card identity for all 60 slots: positions 1-7 (the
  -- initial deal) are insufficient (1 Basic, 1 Energy); positions 8-14 hold
  -- a full good hand's worth of cards that a "reshuffle" can bring to the
  -- front; everything else is filler Trainer (Bill).
  local order = { C.BILL, C.BILL, C.BULBASAUR, C.FIRE_ENERGY, C.BILL, C.BILL, C.BILL,
    C.BULBASAUR, C.SQUIRTLE, C.FIRE_ENERGY, C.WATER_ENERGY, C.CHARMANDER, C.PIDGEY, C.RATTATA }
  for i = 15, 60 do order[i] = C.GRASS_ENERGY end
  local ai, get, set, shuffleLog = newHarness(order)
  dealStartingHand(set, order)

  -- Scripted reshuffle: a permutation of deckIndex (not card IDs) that
  -- brings the good positions 8-14 to the front.
  nextShuffleArrangement = { 8, 9, 10, 11, 12, 13, 14 }
  for i = 8, 60 do nextShuffleArrangement[i] = 15 end -- GRASS_ENERGY-backed filler

  ai:setUpBossStartingHandAndDeck()
  check("insufficient deal: exactly one reshuffle", #shuffleLog, 1)
  local hand = {}
  for i = 0, get(C.DUELVARS_NUMBER_OF_CARDS_IN_HAND) - 1 do hand[#hand + 1] = get(C.DUELVARS_HAND + i) end
  table.sort(hand)
  check("insufficient deal: final hand size is 7", #hand, 7)
  -- The final hand must be exactly the post-reshuffle front 7 (deckIndex
  -- 8-14), not the original (rejected) deckIndex 1-7.
  local expected = { 8, 9, 10, 11, 12, 13, 14 }
  local matches = #hand == #expected
  if matches then for i = 1, #hand do matches = matches and hand[i] == expected[i] end end
  check("insufficient deal: hand reflects the post-reshuffle arrangement, not the rejected deal",
    matches, true)
  nextShuffleArrangement = nil
end

-- ---------------------------------------------------------------------
-- trySetUpBossStartingPlayArea: no arenaPriority list at all -> false,
-- without touching the hand.
-- ---------------------------------------------------------------------
do
  local ai = newHarness({})
  ai._deckAIList = function() return nil end
  check("no arena list: returns false", ai:trySetUpBossStartingPlayArea(), false)
end

-- ---------------------------------------------------------------------
-- Arena list present but none of its card IDs are in hand -> false.
-- ---------------------------------------------------------------------
do
  local ai, _, set = newHarness({})
  set(C.DUELVARS_HAND + 0, 1)
  set(C.DUELVARS_NUMBER_OF_CARDS_IN_HAND, 1)
  ai.cardData.getCardIDFromDeckIndex = function(_, deckIndex) return deckIndex == 1 and C.BILL or nil end
  ai._deckAIList = function(_, name)
    if name == "arenaPriority" then return { cardIds = { C.BULBASAUR, C.SQUIRTLE } } end
    return nil
  end
  check("arena list present, no match in hand: returns false", ai:trySetUpBossStartingPlayArea(), false)
end

-- ---------------------------------------------------------------------
-- Arena match found, then Bench fills from its own priority list until
-- Play Area reaches 3.
-- ---------------------------------------------------------------------
do
  local ai, get, set = newHarness({})
  -- Hand: deckIndex 1=Squirtle, 2=Bulbasaur, 3=Charmander, 4=Pidgey.
  local idByIndex = { [1] = C.SQUIRTLE, [2] = C.BULBASAUR, [3] = C.CHARMANDER, [4] = C.PIDGEY }
  ai.cardData.getCardIDFromDeckIndex = function(_, deckIndex) return idByIndex[deckIndex] end
  for i, deckIndex in ipairs({ 1, 2, 3, 4 }) do set(C.DUELVARS_HAND + (i - 1), deckIndex) end
  set(C.DUELVARS_NUMBER_OF_CARDS_IN_HAND, 4)
  local placed = {}
  ai.duelOps.putHandPokemonCardInPlayArea = function(_, deckIndex)
    placed[#placed + 1] = deckIndex
    local count = get(C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA) + 1
    set(C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA, count)
    return count - 1, false
  end
  ai._deckAIList = function(_, name)
    -- Arena priority: Bulbasaur preferred over Squirtel/Charmander/Pidgey.
    if name == "arenaPriority" then return { cardIds = { C.BULBASAUR, C.SQUIRTLE } } end
    -- Bench priority: Pidgey, then Charmander, then Squirtle.
    if name == "benchPriority" then return { cardIds = { C.PIDGEY, C.CHARMANDER, C.SQUIRTLE } } end
    return nil
  end

  local ok = ai:trySetUpBossStartingPlayArea()
  check("arena+bench setup: overall success", ok, true)
  check("arena+bench setup: exactly 3 Pokemon placed (Play Area cap)", #placed, 3)
  check("arena+bench setup: Bulbasaur placed first (Arena, priority order)", placed[1], 2)
  check("arena+bench setup: Pidgey placed second (Bench priority #1)", placed[2], 4)
  check("arena+bench setup: Charmander placed third (Bench priority #2)", placed[3], 3)
  check("arena+bench setup: Play Area count stopped at 3", get(C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA), 3)
end

-- ---------------------------------------------------------------------
-- bossStartDuel: skips AIPlayInitialBasicCards entirely when Play Area
-- setup fails.
-- ---------------------------------------------------------------------
do
  local ai = newHarness({})
  local calledPlayInitialBasics = false
  ai.initDuelVars = function() end
  ai.setUpBossStartingHandAndDeck = function() end
  ai.trySetUpBossStartingPlayArea = function() return false end
  ai.playInitialBasicCards = function() calledPlayInitialBasics = true end
  ai:bossStartDuel()
  check("bossStartDuel: skips playInitialBasicCards when Play Area setup fails",
    calledPlayInitialBasics, false)
end
do
  local ai = newHarness({})
  local calledPlayInitialBasics = false
  ai.initDuelVars = function() end
  ai.setUpBossStartingHandAndDeck = function() end
  ai.trySetUpBossStartingPlayArea = function() return true end
  ai.playInitialBasicCards = function() calledPlayInitialBasics = true end
  ai:bossStartDuel()
  check("bossStartDuel: calls playInitialBasicCards when Play Area setup succeeds",
    calledPlayInitialBasics, true)
end

-- ---------------------------------------------------------------------
-- Dispatch wiring: a verified boss-deck label now routes forcedSwitch/
-- koSwitch/doTurn through the native common paths, not the adapter.
-- ---------------------------------------------------------------------
do
  local ai, get, set = newHarness({})
  ai.memory.readSymbol8 = function(_, name) return name == "wOpponentDeckID" and 5 or 0 end
  ai.decks.aiByOpponentDeckId = { [5] = "AIActionTable_RockCrusher" }
  ai.decideBenchPokemonToSwitchTo = function() return C.PLAY_AREA_BENCH_1, 99 end
  -- Satisfy forcedSwitch's own post-decision validation: a real Pokemon
  -- occupying the chosen Bench slot, within Play Area bounds.
  set(C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA, 2)
  set(C.DUELVARS_ARENA_CARD + C.PLAY_AREA_BENCH_1, 1)
  set(C.DUELVARS_ARENA_CARD_HP + C.PLAY_AREA_BENCH_1, 60)
  local slot = ai:forcedSwitch()
  check("boss deck (RockCrusher): forcedSwitch uses the native bench scorer", slot, C.PLAY_AREA_BENCH_1)
end
do
  local ai = newHarness({})
  ai.memory.readSymbol8 = function(_, name) return name == "wOpponentDeckID" and 5 or 0 end
  ai.decks.aiByOpponentDeckId = { [5] = "AIActionTable_RockCrusher" }
  local called = false
  ai.mainTurnLogic = function() called = true; return true end
  ai:doTurn()
  check("boss deck (RockCrusher): doTurn routes to mainTurnLogic (general .do_turn)", called, true)
end
do
  local ai = newHarness({})
  ai.memory.readSymbol8 = function(_, name) return name == "wOpponentDeckID" and 6 or 0 end
  ai.decks.aiByOpponentDeckId = { [6] = "AIActionTable_LegendaryMoltres" }
  local usedAdapter = false
  ai.adapters.turnSpecial = function() usedAdapter = true; return true end
  ai:doTurn()
  check("boss deck with bespoke turn logic (Legendary Moltres): still uses the adapter",
    usedAdapter, true)
end

if failures == 0 then
  print("all boss-deck setup cases passed")
  os.exit(0)
else
  print(("%d boss-deck setup case(s) failed"):format(failures))
  os.exit(1)
end
