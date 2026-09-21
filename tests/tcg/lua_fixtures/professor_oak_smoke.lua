-- Behavioral smoke test for AIDecide_ProfessorOak (engine/duel/ai/
-- trainer_cards.asm), run under real LuaJIT. Before this change,
-- AI:_decideProfessorOak() implemented only the deck-agnostic gates and
-- failed closed for LegendaryArticuno/Excavation/WondersOfScience, and had
-- no general-path evolution/hand-basic/Blastoise scoring terms at all.
--
-- Part A: the three new small helpers (_checkIfCardCanBePlayed,
-- _checkForEvolutionInList, _lookForEvolutionForPlayArea) against a
-- controllable duelOps.checkIfCanEvolveInto stub (that primitive's own
-- correctness is proven elsewhere -- DuelOps.lua / pokemon_breeder_smoke.lua
-- -- so it's out of scope here; only how these three NEW routines drive it
-- and interpret its result is under test).
--
-- Part B: the four orchestrators (_decideProfessorOakGeneral,
-- _decideProfessorOakExcavation, _decideProfessorOakWondersOfScience,
-- _decideProfessorOakLegendaryArticuno) and the top-level dispatcher
-- (_decideProfessorOak), with Part A's already-proven helpers stubbed at
-- the instance level to isolate each orchestrator's own control flow.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  PLAY_AREA_ARENA = 0, MAX_PLAY_AREA_POKEMON = 6,
  BASIC = 0,
  TYPE_ENERGY = 8, TYPE_TRAINER = 9,
  DECK_SIZE = 60,
  DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK = 0x01,
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x02, DUELVARS_HAND = 0x60,
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = 0x03,
  DUELVARS_ARENA_CARD = 0x10, DUELVARS_ARENA_CARD_FLAGS = 0x20,
  DUELVARS_CARD_LOCATIONS = 0x00,
  CAN_EVOLVE_THIS_TURN = 1,
  CARD_LOCATION_DECK = 0, CARD_LOCATION_HAND = 1, CARD_LOCATION_PLAY_AREA = 0x10,
  EFFECTCMDTYPE_INITIAL_EFFECT_1 = 1,
  LEGENDARY_ARTICUNO_DECK_ID = 1, EXCAVATION_DECK_ID = 2, WONDERS_OF_SCIENCE_DECK_ID = 3,
  PROFESSOR_OAK = 500, MYSTERIOUS_FOSSIL = 501, GRIMER = 502, MUK = 503,
  BLASTOISE = 504, WATER_ENERGY = 9005,
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

-- ---------------------------------------------------------------------
-- Part A harness
-- ---------------------------------------------------------------------
-- opts.cards = { [deckIndex] = {type=.., stage=.., nameTextId=.., preEvolutionTextId=..} }
-- opts.turn = table of duelVars offset -> value
-- opts.canEvolveInto = { [deckIndex] = { [slot] = true/false } }
local function newPartAAI(opts)
  local turn = opts.turn or {}
  local memory = { words = {},
    readSymbol8 = function(self, name) return self.words[name] or 0 end,
    writeSymbol8 = function(self, name, v) self.words[name] = v end,
  }
  local cards = opts.cards or {}
  local ai = AI.new(
    memory,
    { get = function(_, a) return turn[a] or 0 end, getNonTurn = function() return 0 end, swapTurn = function() end },
    { random = function() return 0 end },
    {
      getCardIDFromDeckIndex = function(_, deckIndex) return deckIndex end,
      get = function(_, cardId) return cards[cardId] end,
    },
    {
      checkIfCanEvolveInto = function(_, deckIndex, slot)
        return ((opts.canEvolveInto or {})[deckIndex] or {})[slot] == true
      end,
    },
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
  ai:setCombat({ status = {
    checkCantUseTrainerDueToEffect = function() return opts.trainerBlocked == true end,
  } })
  ai:setPlayerActions({ effects = {
    loadNonPokemonCardEffectCommands = function() end,
    tryExecute = function() return opts.trainerCarry end,
  } })
  ai._isPrehistoricPowerActive = function() return opts.prehistoricPowerActive == true end
  return ai
end

-- _checkIfCardCanBePlayed: Basic Pokemon
do
  local ai = newPartAAI({
    cards = { [1] = { type = 0, stage = C.BASIC } },
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 3 },
  })
  check("Basic Pokemon, bench not full -> playable", ai:_checkIfCardCanBePlayed(1), true)
end
do
  local ai = newPartAAI({
    cards = { [1] = { type = 0, stage = C.BASIC } },
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 6 },
  })
  check("Basic Pokemon, bench full -> not playable", ai:_checkIfCardCanBePlayed(1), false)
end

-- _checkIfCardCanBePlayed: evolution Pokemon
do
  local ai = newPartAAI({
    cards = { [1] = { type = 0, stage = 1 } },
    prehistoricPowerActive = true,
  })
  check("Evolution card, Prehistoric Power blocking -> not playable", ai:_checkIfCardCanBePlayed(1), false)
end
do
  local ai = newPartAAI({
    cards = { [1] = { type = 0, stage = 1 } },
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2 },
    canEvolveInto = { [1] = { [1] = true } },
  })
  check("Evolution card, a Play Area slot accepts it -> playable", ai:_checkIfCardCanBePlayed(1), true)
end
do
  local ai = newPartAAI({
    cards = { [1] = { type = 0, stage = 1 } },
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2 },
    canEvolveInto = {},
  })
  check("Evolution card, no slot accepts it -> not playable", ai:_checkIfCardCanBePlayed(1), false)
end

-- _checkIfCardCanBePlayed: Trainer
do
  local ai = newPartAAI({ cards = { [1] = { type = C.TYPE_TRAINER } }, trainerBlocked = true })
  check("Trainer, blocked by effect -> not playable", ai:_checkIfCardCanBePlayed(1), false)
end
do
  local ai = newPartAAI({ cards = { [1] = { type = C.TYPE_TRAINER } }, trainerCarry = true })
  check("Trainer, INITIAL_EFFECT_1 carry=true -> not playable", ai:_checkIfCardCanBePlayed(1), false)
end
do
  local ai = newPartAAI({ cards = { [1] = { type = C.TYPE_TRAINER } }, trainerCarry = false })
  check("Trainer, INITIAL_EFFECT_1 carry=false -> playable", ai:_checkIfCardCanBePlayed(1), true)
end

-- _checkIfCardCanBePlayed: Energy
do
  local ai = newPartAAI({ cards = { [1] = { type = C.TYPE_ENERGY } } })
  ai.memory:writeSymbol8("wAlreadyPlayedEnergy", 0)
  check("Energy, none played yet this turn -> playable", ai:_checkIfCardCanBePlayed(1), true)
end
do
  local ai = newPartAAI({ cards = { [1] = { type = C.TYPE_ENERGY } } })
  ai.memory:writeSymbol8("wAlreadyPlayedEnergy", 1)
  check("Energy, already played this turn -> not playable", ai:_checkIfCardCanBePlayed(1), false)
end

-- _checkForEvolutionInList
do
  local ai = newPartAAI({
    cards = { [100] = { nameTextId = 7 }, [1] = { preEvolutionTextId = 7 } },
    turn = { [C.DUELVARS_ARENA_CARD_FLAGS + C.PLAY_AREA_ARENA] = 0 },
  })
  check("CheckForEvolutionInList: evolve-this-turn flag clear -> nil even with a match",
    ai:_checkForEvolutionInList(100, { 1 }), nil)
end
do
  local ai = newPartAAI({
    cards = { [100] = { nameTextId = 7 }, [1] = { preEvolutionTextId = 9 }, [2] = { preEvolutionTextId = 7 } },
    turn = { [C.DUELVARS_ARENA_CARD_FLAGS + C.PLAY_AREA_ARENA] = C.CAN_EVOLVE_THIS_TURN },
  })
  check("CheckForEvolutionInList: flag set, matching entry found -> that deckIndex",
    ai:_checkForEvolutionInList(100, { 1, 2 }), 2)
end
do
  local ai = newPartAAI({
    cards = { [100] = { nameTextId = 7 }, [1] = { preEvolutionTextId = 9 } },
    turn = { [C.DUELVARS_ARENA_CARD_FLAGS + C.PLAY_AREA_ARENA] = C.CAN_EVOLVE_THIS_TURN },
  })
  check("CheckForEvolutionInList: flag set, no matching entry -> nil",
    ai:_checkForEvolutionInList(100, { 1 }), nil)
end

-- _lookForEvolutionForPlayArea
do
  -- deckIndex 5 evolves slot 0 and is located in hand -> short-circuits true,true.
  local ai = newPartAAI({
    turn = { [C.DUELVARS_CARD_LOCATIONS + 5] = C.CARD_LOCATION_HAND,
             [C.DUELVARS_CARD_LOCATIONS + 40] = C.CARD_LOCATION_DECK },
    canEvolveInto = { [5] = { [0] = true }, [40] = { [0] = true } },
  })
  local inHand, anywhere = ai:_lookForEvolutionForPlayArea(0)
  check("LookForEvolution: found in hand -> foundInHand", inHand, true)
  check("LookForEvolution: found in hand -> foundAnywhere", anywhere, true)
end
do
  -- Only a deck copy evolves slot 0 -> false, true.
  local ai = newPartAAI({
    turn = { [C.DUELVARS_CARD_LOCATIONS + 40] = C.CARD_LOCATION_DECK },
    canEvolveInto = { [40] = { [0] = true } },
  })
  local inHand, anywhere = ai:_lookForEvolutionForPlayArea(0)
  check("LookForEvolution: found only in deck -> foundInHand false", inHand, false)
  check("LookForEvolution: found only in deck -> foundAnywhere true", anywhere, true)
end
do
  local ai = newPartAAI({ canEvolveInto = {} })
  local inHand, anywhere = ai:_lookForEvolutionForPlayArea(0)
  check("LookForEvolution: found nowhere -> foundInHand false", inHand, false)
  check("LookForEvolution: found nowhere -> foundAnywhere false", anywhere, false)
end

-- ---------------------------------------------------------------------
-- Part B harness: orchestrators, Part A helpers stubbed at instance level.
-- ---------------------------------------------------------------------
local function newPartBAI(opts)
  local turn = opts.turn or {}
  local hand = opts.hand or {}
  for i, deckIndex in ipairs(hand) do turn[C.DUELVARS_HAND + (i - 1)] = deckIndex end
  turn[C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = turn[C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] or #hand
  local cards = opts.cards or {}
  local memory = { words = { wOpponentDeckID = opts.deckId },
    readSymbol8 = function(self, name) return self.words[name] or 0 end,
    writeSymbol8 = function(self, name, v) self.words[name] = v end,
  }
  local ai = AI.new(
    memory,
    { get = function(_, a) return turn[a] or 0 end, getNonTurn = function() return 0 end, swapTurn = function() end },
    { random = function() return 0 end },
    {
      getCardIDFromDeckIndex = function(_, deckIndex) return deckIndex end,
      get = function(_, cardId) return cards[cardId] end,
    },
    { createHandCardList = function() return hand end },
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
  ai:setCombat({ status = {
    checkCantUseTrainerDueToEffect = function() return false end,
    countPokemonWithActivePkmnPowerInBothPlayAreas = function(_, cardId)
      local v = (opts.mukActiveCount or 0)
      return v, v ~= 0
    end,
    countTurnDuelistPokemonWithActivePkmnPower = function(_, cardId)
      return opts.blastoiseCount or 0
    end,
  } })
  ai._energyCardsInHand = function() return opts.energyInHand or {} end
  ai._findCardIDInHand = function(_, cardId)
    for _, c in ipairs(hand) do if c == cardId then return c end end
    return nil
  end
  ai._cardIDInHand = function(_, cardId) return ai:_findCardIDInHand(cardId) ~= nil end
  ai._cardIDInHandAndPlayArea = function() return opts.fossilOut == true end
  ai._lookForEvolutionForPlayArea = function(_, slot)
    return (opts.evoInHandBySlot or {})[slot] == true, (opts.evoAnywhereBySlot or {})[slot] == true
  end
  ai._checkForEvolutionInList = function(_, cardId, list) return (opts.evoListResultByCardId or {})[cardId] end
  ai._checkIfCardCanBePlayed = function(_, deckIndex) return (opts.playableByDeckIndex or {})[deckIndex] == true end
  return ai
end

-- _decideProfessorOakGeneral
do
  local ai = newPartBAI({ turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 46 } })
  check("General: notInDeck >= DECK_SIZE-14 -> false", ai:_decideProfessorOakGeneral(30), false)
end
do
  -- score 30, hand<4 (+50) = 80 -> true, no other bonuses.
  local ai = newPartBAI({
    turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 0, [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 0 },
    hand = { 1, 2 },
    energyInHand = { { deckIndex = 1, cardId = 1 } },
  })
  check("General: hand<4 bonus alone reaches threshold -> true", ai:_decideProfessorOakGeneral(30), true)
end
do
  -- score 30, hand>=9 (-30) = 0 -> false.
  local ai = newPartBAI({
    turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 0, [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 0 },
    hand = { 1, 2, 3, 4, 5, 6, 7, 8, 9 },
    energyInHand = { { deckIndex = 1, cardId = 1 } },
  })
  check("General: hand>=9 penalty -> false", ai:_decideProfessorOakGeneral(30), false)
end
do
  -- score 30, empty energy in hand (+40) = 70 -> true.
  local ai = newPartBAI({
    turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 0, [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 0 },
    hand = { 1, 2, 3, 4, 5 },
    energyInHand = {},
  })
  check("General: no Energy in hand bonus -> true", ai:_decideProfessorOakGeneral(30), true)
end
do
  -- Blastoise active, Muk absent, no Water Energy in hand -> +10, stacked with
  -- the empty-hand-energy +40 bonus: 30+40+10 = 80 -> true.
  local ai = newPartBAI({
    turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 0, [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 0 },
    hand = { 1, 2, 3, 4, 5 },
    energyInHand = {},
    blastoiseCount = 1, mukActiveCount = 0,
  })
  check("General: Blastoise active, no Muk, no Water Energy -> Rain Dance bonus -> true",
    ai:_decideProfessorOakGeneral(30), true)
end
do
  -- Same, but Muk is active -> no bonus, stays at 30 -> false.
  local ai = newPartBAI({
    turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 0, [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 0 },
    hand = { 1, 2, 3, 4, 5 },
    energyInHand = { { deckIndex = 1, cardId = 1 } },
    blastoiseCount = 1, mukActiveCount = 1,
  })
  check("General: Blastoise active but Muk neutralizes it -> no bonus -> false",
    ai:_decideProfessorOakGeneral(30), false)
end
do
  -- Hand-basic-bug: a card with type>=TYPE_ENERGY and stage==BASIC scores +10 per hit.
  local ai = newPartBAI({
    turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 0, [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 0 },
    hand = { 1, 2, 3 },
    cards = {
      [1] = { type = C.TYPE_TRAINER, stage = C.BASIC },
      [2] = { type = C.TYPE_ENERGY, stage = C.BASIC },
      [3] = { type = 0, stage = C.BASIC },
    },
    energyInHand = { { deckIndex = 1, cardId = 1 } },
  })
  check("General: hand-basic bug counts Trainer/Energy with stage==BASIC, not real Pokemon",
    ai:_decideProfessorOakGeneral(20), true) -- 20 + 10 (card1) + 10 (card2) = 40, card3 excluded by type<TYPE_ENERGY
end
do
  -- Evolution available somewhere but not in hand -> +10, landing exactly on
  -- the score>=60 threshold: 50+10 = 60 -> true.
  local ai = newPartBAI({
    turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 0, [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 1 },
    hand = { 1, 2, 3, 4, 5 },
    energyInHand = { { deckIndex = 1, cardId = 1 } },
    evoInHandBySlot = {}, evoAnywhereBySlot = { [0] = true },
  })
  check("General: evolution available but not in hand -> bonus -> true",
    ai:_decideProfessorOakGeneral(50), true)
end
do
  -- Evolution available AND already in hand -> no bonus.
  local ai = newPartBAI({
    turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 0, [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 1 },
    hand = { 1, 2, 3, 4, 5 },
    energyInHand = { { deckIndex = 1, cardId = 1 } },
    evoInHandBySlot = { [0] = true }, evoAnywhereBySlot = { [0] = true },
  })
  check("General: evolution already in hand -> no bonus -> false",
    ai:_decideProfessorOakGeneral(20), false)
end

-- _decideProfessorOakExcavation
do
  local ai = newPartBAI({ turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 46 } })
  check("Excavation: gate at DECK_SIZE-14 -> false", ai:_decideProfessorOakExcavation(46), false)
end
do
  local calls = {}
  local ai = newPartBAI({
    turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 0, [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 0 },
    hand = {}, energyInHand = {}, fossilOut = true,
  })
  ai._decideProfessorOakGeneral = function(_, score) calls[#calls + 1] = score return true end
  ai:_decideProfessorOakExcavation(0)
  check("Excavation: Mysterious Fossil already out -> initial score 30", calls[1], 30)
end
do
  local calls = {}
  local ai = newPartBAI({
    turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 0 },
    fossilOut = false,
  })
  ai._decideProfessorOakGeneral = function(_, score) calls[#calls + 1] = score return true end
  ai:_decideProfessorOakExcavation(0)
  check("Excavation: Mysterious Fossil missing -> initial score 80", calls[1], 80)
end

-- _decideProfessorOakWondersOfScience
do
  local ai = newPartBAI({ hand = { C.GRIMER } })
  check("WondersOfScience: Grimer in hand -> false", ai:_decideProfessorOakWondersOfScience(), false)
end
do
  local ai = newPartBAI({ hand = { C.MUK } })
  check("WondersOfScience: Muk in hand -> false", ai:_decideProfessorOakWondersOfScience(), false)
end
do
  local calls = {}
  local ai = newPartBAI({ hand = {} })
  ai._decideProfessorOakGeneral = function(_, score) calls[#calls + 1] = score return true end
  ai:_decideProfessorOakWondersOfScience()
  check("WondersOfScience: neither -> falls to General(30)", calls[1], 30)
end

-- _decideProfessorOakLegendaryArticuno
do
  -- <3 Play Area Pokemon, no evolution found for any of them -> true immediately.
  local ai = newPartBAI({
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 2, [C.DUELVARS_ARENA_CARD] = 10, [C.DUELVARS_ARENA_CARD + 1] = 11 },
    evoListResultByCardId = {},
  })
  check("Articuno: <3 in play, no evolution anywhere -> true", ai:_decideProfessorOakLegendaryArticuno(), true)
end
do
  -- <3 Play Area Pokemon, an evolution IS found -> falls into playable-cards
  -- gate; energy>=4 in hand cancels Oak outright.
  local ai = newPartBAI({
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 1, [C.DUELVARS_ARENA_CARD] = 10 },
    evoListResultByCardId = { [10] = 99 },
    energyInHand = { {}, {}, {}, {} },
  })
  check("Articuno: evolution found, then >=4 Energy in hand -> false",
    ai:_decideProfessorOakLegendaryArticuno(), false)
end
do
  -- >=3 in play (skips the evolution pre-check entirely), <4 energy, every
  -- remaining hand card (after removing up to 2 Oaks) is unplayable -> true.
  local ai = newPartBAI({
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 3 },
    hand = { C.PROFESSOR_OAK, C.PROFESSOR_OAK, 1, 2 },
    energyInHand = {},
    playableByDeckIndex = {},
  })
  check(">=3 in play, <4 energy, hand all unplayable after Oak removal -> true",
    ai:_decideProfessorOakLegendaryArticuno(), true)
end
do
  -- Same, but one remaining card IS playable -> false.
  local ai = newPartBAI({
    turn = { [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 3 },
    hand = { C.PROFESSOR_OAK, C.PROFESSOR_OAK, 1, 2 },
    energyInHand = {},
    playableByDeckIndex = { [2] = true },
  })
  check(">=3 in play, <4 energy, one remaining card playable -> false",
    ai:_decideProfessorOakLegendaryArticuno(), false)
end

-- _decideProfessorOak dispatcher
do
  local ai = newPartBAI({ turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 54 } })
  check("Dispatcher: notInDeck >= DECK_SIZE-6 -> false", ai:_decideProfessorOak(), false)
end
do
  local ai = newPartBAI({
    deckId = C.LEGENDARY_ARTICUNO_DECK_ID,
    turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 0, [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = 0 },
    evoListResultByCardId = {},
  })
  check("Dispatcher: LegendaryArticuno deck -> routes to Articuno branch", ai:_decideProfessorOak(), true)
end
do
  local calls = {}
  local ai = newPartBAI({ deckId = C.EXCAVATION_DECK_ID, turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 0 } })
  ai._decideProfessorOakExcavation = function(_, notInDeck) calls[#calls + 1] = notInDeck return true end
  ai:_decideProfessorOak()
  check("Dispatcher: Excavation deck -> routes to Excavation branch", #calls, 1)
end
do
  local calls = {}
  local ai = newPartBAI({ deckId = C.WONDERS_OF_SCIENCE_DECK_ID, turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 0 } })
  ai._decideProfessorOakWondersOfScience = function(_) calls[#calls + 1] = true return true end
  ai:_decideProfessorOak()
  check("Dispatcher: WondersOfScience deck -> routes to WondersOfScience branch", #calls, 1)
end
do
  local calls = {}
  local ai = newPartBAI({ deckId = 999, turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 0 } })
  ai._decideProfessorOakGeneral = function(_, score) calls[#calls + 1] = score return true end
  ai:_decideProfessorOak()
  check("Dispatcher: any other deck -> routes to General(30)", calls[1], 30)
end

if failures == 0 then
  print("all Professor Oak AI decision cases passed")
  os.exit(0)
else
  print(("%d Professor Oak AI decision case(s) failed"):format(failures))
  os.exit(1)
end
