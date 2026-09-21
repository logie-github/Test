-- Behavioral smoke test for Pokemon Trader's AI decision
-- (AIDecide_PokemonTrader and its ten deck-specific branches,
-- trainer_cards.asm), run under real LuaJIT.
--
-- shuffleCards is unused here (Pokemon Trader's own search never shuffles,
-- unlike Computer Search's discard picker), so no rng stub is needed
-- beyond a bare no-op.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  PLAY_AREA_ARENA = 0, MAX_PLAY_AREA_POKEMON = 6, DECK_SIZE = 60,
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x10, DUELVARS_HAND = 0x11,
  DUELVARS_ARENA_CARD = 0x40, DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = 0x50,
  CARD_LOCATION_DECK = 0, CARD_LOCATION_HAND = 1,
  TYPE_ENERGY = 8, TYPE_TRAINER = 9,
  LEGENDARY_MOLTRES_DECK_ID = 601, LEGENDARY_ARTICUNO_DECK_ID = 602,
  LEGENDARY_DRAGONITE_DECK_ID = 603, LEGENDARY_RONALD_DECK_ID = 604,
  BLISTERING_POKEMON_DECK_ID = 605, SOUND_OF_THE_WAVES_DECK_ID = 606,
  POWER_GENERATOR_DECK_ID = 607, FLOWER_GARDEN_DECK_ID = 608,
  STRANGE_POWER_DECK_ID = 609, FLAMETHROWER_DECK_ID = 610,
  ORDINARY_DECK_ID = 1,
  -- Card IDs (arbitrary but distinct); only the specific IDs each case
  -- references matter, not their numeric values.
  MOLTRES_LV37 = 1, MOLTRES_LV35 = 2,
  ARTICUNO_LV35 = 3, LAPRAS = 4, SEEL = 5, DEWGONG = 6, CHANSEY = 7, DITTO = 8, ARTICUNO_LV37 = 9,
  KANGASKHAN = 10, MAGIKARP = 11, GYARADOS = 12, DRATINI = 13, DRAGONAIR = 14, DRAGONITE_LV41 = 15,
  CHARMANDER = 16, CHARMELEON = 17, CHARIZARD = 18,
  EEVEE = 19, FLAREON_LV22 = 20, VAPOREON_LV29 = 21, JOLTEON_LV24 = 22,
  ZAPDOS_LV68 = 23,
  RHYHORN = 24, RHYDON = 25, CUBONE = 26, MAROWAK_LV26 = 27, PONYTA = 28, RAPIDASH = 29,
  KRABBY = 30, KINGLER = 31, SHELLDER = 32, CLOYSTER = 33, HORSEA = 34, SEADRA = 35,
  TENTACOOL = 36, TENTACRUEL = 37,
  PIKACHU_LV14 = 38, PIKACHU_LV12 = 39, RAICHU_LV40 = 40,
  VOLTORB = 41, ELECTRODE_LV42 = 42, ELECTRODE_LV35 = 43,
  MAGNEMITE_LV13 = 44, MAGNEMITE_LV15 = 45, MAGNETON_LV35 = 46, MAGNETON_LV28 = 47,
  BULBASAUR = 48, IVYSAUR = 49, VENUSAUR_LV67 = 50,
  BELLSPROUT = 51, WEEPINBELL = 52, VICTREEBEL = 53, ODDISH = 54, GLOOM = 55, VILEPLUME = 56,
  MR_MIME = 57, VULPIX = 58, NINETALES_LV32 = 59, GROWLITHE = 60, ARCANINE_LV45 = 61,
  FLAREON_LV28 = 62,
  OTHER_POKEMON = 90, OTHER_ENERGY = 91,
}
local CARD_ROWS = setmetatable({}, { __index = function(_, id)
  if id == C.OTHER_ENERGY then return { type = C.TYPE_ENERGY } end
  return { type = 0 }
end })

local failures = 0
local function fmt(v) return tostring(v) end
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(("FAIL  %s: got %s, want %s"):format(label, fmt(got), fmt(want)))
  else
    print(("ok    %s"):format(label))
  end
end

-- opts.deckLocations: {[deckIndex]=CARD_LOCATION_DECK}.
-- opts.deckIndexToCardId: {[deckIndex]=cardId}.
-- opts.hand: array of deckIndex in hand (hand order).
-- opts.playArea: array of deckIndex, slot 0 = Arena.
local function newAI(opts)
  local words = { wOpponentDeckID = opts.deckId or C.ORDINARY_DECK_ID }
  local turn = {
    [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = #(opts.hand or {}),
    [C.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = #(opts.playArea or {}),
  }
  for deckIndex, loc in pairs(opts.deckLocations or {}) do turn[deckIndex] = loc end
  for i, deckIndex in ipairs(opts.hand or {}) do turn[C.DUELVARS_HAND + (i - 1)] = deckIndex end
  for i, deckIndex in ipairs(opts.playArea or {}) do turn[C.DUELVARS_ARENA_CARD + (i - 1)] = deckIndex end
  turn[C.DUELVARS_ARENA_CARD + #(opts.playArea or {})] = 0xff

  local memory = {
    readSymbol8 = function(_, name) return words[name] or 0 end,
    writeSymbol8 = function(_, name, v) words[name] = v end,
  }
  local duelVars = {
    get = function(_, addr) return turn[addr] end,
    getNonTurn = function() return nil end,
  }
  local cardData = {
    getCardIDFromDeckIndex = function(_, deckIndex) return (opts.deckIndexToCardId or {})[deckIndex] end,
    get = function(_, cardId) return CARD_ROWS[cardId] end,
  }
  local duelOps = {
    createHandCardList = function() return opts.hand or {} end,
    countNumberOfEnergyCardsAttached = function(_, slot) return (opts.attachedEnergyBySlot or {})[slot] or 0 end,
  }
  local rng = { shuffleCards = function() end }
  return AI.new(memory, duelVars, rng, cardData, duelOps, C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} }, {})
end

check("ordinary deck -> never plays (no general path exists)",
  newAI({ deckId = C.ORDINARY_DECK_ID }):_decidePokemonTrader(), false)

-- ---------------------------------------------------------------------
-- Legendary Moltres: simple trade-search, avoiding MoltresLv35 specifically.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    deckId = C.LEGENDARY_MOLTRES_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.MOLTRES_LV37, [10] = C.MOLTRES_LV35, [11] = C.CHANSEY },
    hand = { 10, 11 },
  })
  local ok, selection = ai:_decidePokemonTrader()
  check("Moltres, MoltresLv37 in deck: plays", ok, true)
  check("Moltres: targets MoltresLv37", selection.deckPokemon, 50)
  check("Moltres: trades away the non-avoided hand card (Chansey)", selection.handPokemon, 11)
end
do
  -- MoltresLv37 already in hand -> no play.
  local ai = newAI({
    deckId = C.LEGENDARY_MOLTRES_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.MOLTRES_LV37, [10] = C.MOLTRES_LV37 },
    hand = { 10 },
  })
  check("Moltres, already in hand: no play", ai:_decidePokemonTrader(), false)
end

-- ---------------------------------------------------------------------
-- Legendary Articuno.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    deckId = C.LEGENDARY_ARTICUNO_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.SEEL, [10] = C.CHANSEY, [11] = C.CHANSEY },
    hand = { 10, 11 },
  })
  local ok, selection = ai:_decidePokemonTrader()
  check("Articuno, Seel in deck, 2 Chansey in hand: plays", ok, true)
  check("Articuno: targets Seel", selection.deckPokemon, 50)
  check("Articuno: trades away the spare Chansey (2nd copy)", selection.handPokemon, 11)
end
do
  -- Already has ArticunoLv35 out -> never plays, regardless of anything else.
  local ai = newAI({
    deckId = C.LEGENDARY_ARTICUNO_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.SEEL, [1] = C.ARTICUNO_LV35, [10] = C.CHANSEY, [11] = C.CHANSEY },
    hand = { 1, 10, 11 },
  })
  check("Articuno, ArticunoLv35 already out: no play", ai:_decidePokemonTrader(), false)
end
do
  -- Only 1 Chansey (not a spare) -> no play.
  local ai = newAI({
    deckId = C.LEGENDARY_ARTICUNO_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.SEEL, [10] = C.CHANSEY },
    hand = { 10 },
  })
  check("Articuno, only 1 Chansey (no spare): no play", ai:_decidePokemonTrader(), false)
end

-- ---------------------------------------------------------------------
-- Legendary Dragonite: Kangaskhan gate vs. evolution chain.
-- ---------------------------------------------------------------------
do
  -- Fewer than 5 total Energy -> Kangaskhan directly.
  local ai = newAI({
    deckId = C.LEGENDARY_DRAGONITE_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.KANGASKHAN, [10] = C.DRATINI, [11] = C.DRATINI },
    hand = { 10, 11 },
  })
  local ok, selection = ai:_decidePokemonTrader()
  check("Dragonite, <5 Energy: targets Kangaskhan directly", ok, true)
  check("Dragonite: targets Kangaskhan", selection.deckPokemon, 50)
  check("Dragonite: trades away spare Dratini", selection.handPokemon, 11)
end
do
  -- >=5 Energy AND >=5 Pokemon -> evolution chain instead.
  local ai = newAI({
    deckId = C.LEGENDARY_DRAGONITE_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.GYARADOS, [1] = C.MAGIKARP,
      [10] = C.OTHER_ENERGY, [11] = C.OTHER_ENERGY, [12] = C.OTHER_ENERGY,
      [13] = C.OTHER_ENERGY, [14] = C.OTHER_ENERGY,
      [15] = C.OTHER_POKEMON, [16] = C.OTHER_POKEMON, [17] = C.OTHER_POKEMON, [18] = C.OTHER_POKEMON,
      [19] = C.DRAGONAIR, [20] = C.DRAGONAIR },
    hand = { 1, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 },
  })
  local ok, selection = ai:_decidePokemonTrader()
  check(">=5 Energy and >=5 Pokemon: evolution chain (Gyarados) used", ok, true)
  check("Dragonite: targets Gyarados", selection.deckPokemon, 50)
  check("Dragonite: trades away spare Dragonair (priority 1)", selection.handPokemon, 20)
end

-- ---------------------------------------------------------------------
-- Legendary Ronald: single-copy trade-away (not the 2-copies helper).
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    deckId = C.LEGENDARY_RONALD_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.FLAREON_LV22, [1] = C.EEVEE, [10] = C.ZAPDOS_LV68 },
    hand = { 1, 10 },
  })
  local ok, selection = ai:_decidePokemonTrader()
  check("Ronald, Eevee out + FlareonLv22 in deck: plays", ok, true)
  check("Ronald: targets FlareonLv22", selection.deckPokemon, 50)
  check("Ronald: trades away a SINGLE ZapdosLv68 (no spare needed)", selection.handPokemon, 10)
end

-- ---------------------------------------------------------------------
-- BlisteringPokemon / PowerGenerator / FlowerGarden / Flamethrower:
-- FindDuplicatePokemonCards trade-away, "last duplicate pair wins" quirk.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    deckId = C.BLISTERING_POKEMON_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.RHYDON, [1] = C.RHYHORN,
      [10] = C.CHANSEY, [11] = C.CHANSEY, [12] = C.DITTO, [13] = C.DITTO },
    hand = { 1, 10, 11, 12, 13 },
  })
  local ok, selection = ai:_decidePokemonTrader()
  check("BlisteringPokemon, Rhyhorn out + Rhydon in deck, 2 duplicate pairs: plays", ok, true)
  check("BlisteringPokemon: targets Rhydon", selection.deckPokemon, 50)
  check("BlisteringPokemon: LAST duplicate pair wins (Ditto, not Chansey)",
    selection.handPokemon, 13)
end
do
  -- Evolution chain fails entirely -> no play.
  local ai = newAI({
    deckId = C.BLISTERING_POKEMON_DECK_ID,
    deckLocations = {},
    deckIndexToCardId = { [10] = C.CHANSEY, [11] = C.CHANSEY },
    hand = { 10, 11 },
  })
  check("BlisteringPokemon, no evolution chain available: no play", ai:_decidePokemonTrader(), false)
end

-- ---------------------------------------------------------------------
-- PowerGenerator: the Magnemite line's asymmetric AndPlayArea/Hand order.
-- ---------------------------------------------------------------------
do
  -- Neither Pikachu nor Voltorb lines match; MagnemiteLv15 is in hand
  -- (not Play Area) with MagnetonLv35 in deck -> only the Hand pass (which
  -- checks Lv15 before Lv13) can find it.
  local ai = newAI({
    deckId = C.POWER_GENERATOR_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.MAGNETON_LV35, [1] = C.MAGNEMITE_LV15,
      [10] = C.CHANSEY, [11] = C.CHANSEY },
    hand = { 1, 10, 11 },
  })
  local ok, selection = ai:_decidePokemonTrader()
  check("PowerGenerator, MagnemiteLv15 in hand only: Hand-pass order finds it", ok, true)
  check("PowerGenerator: targets MagnetonLv35", selection.deckPokemon, 50)
end
do
  -- Missing `jr .no_carry` source bug: chain fails entirely -> fails
  -- closed (not reproducing the register-garbage fallthrough).
  local ai = newAI({
    deckId = C.POWER_GENERATOR_DECK_ID,
    deckLocations = {},
    deckIndexToCardId = { [10] = C.CHANSEY, [11] = C.CHANSEY },
    hand = { 10, 11 },
  })
  check("PowerGenerator, chain fails entirely: fails closed (not the source's register-garbage bug)",
    ai:_decidePokemonTrader(), false)
end

-- ---------------------------------------------------------------------
-- FlowerGarden.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    deckId = C.FLOWER_GARDEN_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.IVYSAUR, [1] = C.BULBASAUR, [10] = C.DITTO, [11] = C.DITTO },
    hand = { 1, 10, 11 },
  })
  local ok, selection = ai:_decidePokemonTrader()
  check("FlowerGarden, Bulbasaur out + Ivysaur in deck: plays", ok, true)
  check("FlowerGarden: targets Ivysaur", selection.deckPokemon, 50)
end

-- ---------------------------------------------------------------------
-- StrangePower: redundant wanted==avoid card ID.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    deckId = C.STRANGE_POWER_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.MR_MIME, [10] = C.CHANSEY },
    hand = { 10 },
  })
  local ok, selection = ai:_decidePokemonTrader()
  check("StrangePower, MrMime in deck: plays", ok, true)
  check("StrangePower: targets MrMime", selection.deckPokemon, 50)
  check("StrangePower: trades away the hand card", selection.handPokemon, 10)
end
do
  local ai = newAI({
    deckId = C.STRANGE_POWER_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.MR_MIME, [10] = C.MR_MIME },
    hand = { 10 },
  })
  check("StrangePower, MrMime already in hand: no play", ai:_decidePokemonTrader(), false)
end

-- ---------------------------------------------------------------------
-- Flamethrower.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    deckId = C.FLAMETHROWER_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.NINETALES_LV32, [1] = C.VULPIX,
      [10] = C.CHANSEY, [11] = C.CHANSEY },
    hand = { 1, 10, 11 },
  })
  local ok, selection = ai:_decidePokemonTrader()
  check("Flamethrower, Vulpix out + NinetalesLv32 in deck: plays", ok, true)
  check("Flamethrower: targets NinetalesLv32", selection.deckPokemon, 50)
end

if failures == 0 then
  print("all Pokemon Trader AI decision cases passed")
  os.exit(0)
else
  print(("%d Pokemon Trader AI decision case(s) failed"):format(failures))
  os.exit(1)
end
