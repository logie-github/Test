-- Behavioral smoke test for Computer Search's AI decision
-- (AIDecide_ComputerSearch and its four deck-specific branches,
-- trainer_cards.asm), run under real LuaJIT.
--
-- shuffleCards is stubbed to a no-op (identity order) for deterministic
-- assertions -- the source's own shuffle-then-first-match only matters for
-- WHICH of several equally-qualifying cards gets picked when there's more
-- than one candidate, not for whether the type/avoid-index filtering
-- itself is correct, which is what these cases exercise. Each case is
-- built so at most one candidate ever qualifies.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  PLAY_AREA_ARENA = 0, MAX_PLAY_AREA_POKEMON = 6, DECK_SIZE = 60,
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 0x10, DUELVARS_HAND = 0x11,
  DUELVARS_ARENA_CARD = 0x40,
  CARD_LOCATION_DECK = 0, CARD_LOCATION_HAND = 1,
  TYPE_ENERGY = 8, TYPE_TRAINER = 9,
  ROCK_CRUSHER_DECK_ID = 501, WONDERS_OF_SCIENCE_DECK_ID = 502,
  FIRE_CHARGE_DECK_ID = 503, ANGER_DECK_ID = 504, ORDINARY_DECK_ID = 1,
  PROFESSOR_OAK = 1, FIGHTING_ENERGY = 2, DOUBLE_COLORLESS_ENERGY = 3,
  DIGLETT = 4, GEODUDE = 5, ONIX = 6, RHYHORN = 7,
  GRAVELER = 8, GOLEM = 9, DUGTRIO = 10,
  GRIMER = 11, MUK = 12,
  CHANSEY = 13, TAUROS = 14, JIGGLYPUFF_LV12 = 15,
  RATTATA = 16, RATICATE = 17, GROWLITHE = 18, ARCANINE_LV34 = 19,
  DODUO = 20, DODRIO = 21,
  BULBASAUR = 100, POKE_BALL = 101, GUST_OF_WIND = 102,
}
-- Every card ID used in these fixtures is a Pokemon (type=0) except the
-- ones explicitly listed here as Trainer or Energy.
local CARD_ROWS_OVERRIDE = {
  [C.PROFESSOR_OAK] = C.TYPE_TRAINER, [C.POKE_BALL] = C.TYPE_TRAINER,
  [C.GUST_OF_WIND] = C.TYPE_TRAINER,
  [C.FIGHTING_ENERGY] = C.TYPE_ENERGY, [C.DOUBLE_COLORLESS_ENERGY] = C.TYPE_ENERGY,
}
local CARD_ROWS = setmetatable({}, {
  __index = function(_, cardId) return { type = CARD_ROWS_OVERRIDE[cardId] or 0 } end,
})

local failures = 0
local function arraysEqual(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
local function fmt(v)
  if type(v) == "table" then return "{" .. table.concat(v, ",") .. "}" end
  return tostring(v)
end
local function check(label, got, want)
  local equal
  if type(got) == "table" or type(want) == "table" then equal = arraysEqual(got, want)
  else equal = got == want end
  if not equal then
    failures = failures + 1
    print(("FAIL  %s: got %s, want %s"):format(label, fmt(got), fmt(want)))
  else
    print(("ok    %s"):format(label))
  end
end

-- opts.deckLocations: {[deckIndex]=CARD_LOCATION_*} for _findCardIDInDeck.
-- opts.deckIndexToCardId: {[deckIndex]=cardId}.
-- opts.hand: array of deckIndex in hand (hand order).
-- opts.playArea: array of deckIndex, slot 0 = Arena.
local function newAI(opts)
  local words, wram = { wOpponentDeckID = opts.deckId or C.ORDINARY_DECK_ID }, {}
  local turn = { [C.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = #(opts.hand or {}) }
  for deckIndex, loc in pairs(opts.deckLocations or {}) do turn[deckIndex] = loc end
  for i, deckIndex in ipairs(opts.hand or {}) do turn[C.DUELVARS_HAND + (i - 1)] = deckIndex end
  for i, deckIndex in ipairs(opts.playArea or {}) do turn[C.DUELVARS_ARENA_CARD + (i - 1)] = deckIndex end
  turn[C.DUELVARS_ARENA_CARD + #(opts.playArea or {})] = 0xff

  local memory = {
    readSymbol8 = function(_, name) return words[name] or 0 end,
    writeSymbol8 = function(_, name, v) words[name] = v end,
    address = function(_, name) if name == "wDuelTempList" then return 2000, 0 end return 0, 0 end,
    read8 = function(_, kind, addr, bank) return wram[addr] or 0 end,
    write8 = function(_, kind, addr, value, bank) wram[addr] = value end,
  }
  local duelVars = {
    get = function(_, addr) return turn[addr] end,
    getNonTurn = function() return nil end,
  }
  local cardData = {
    getCardIDFromDeckIndex = function(_, deckIndex) return (opts.deckIndexToCardId or {})[deckIndex] end,
    get = function(_, cardId) return CARD_ROWS[cardId] end,
  }
  local duelOps = { createHandCardList = function() return opts.hand or {} end }
  local rng = { shuffleCards = function() end } -- identity order for deterministic tests
  return AI.new(memory, duelVars, rng, cardData, duelOps, C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} }, {})
end

-- ---------------------------------------------------------------------
-- Deck-agnostic hand-count gate and ordinary-deck no-op.
-- ---------------------------------------------------------------------
check("hand < 3 cards -> never plays, even for a specialized deck",
  newAI({ hand = { 1, 2 }, deckId = C.ROCK_CRUSHER_DECK_ID }):_decideComputerSearch(0xff), false)
check("hand >= 3, ordinary deck -> never plays (no general path exists)",
  newAI({ hand = { 1, 2, 3 }, deckId = C.ORDINARY_DECK_ID }):_decideComputerSearch(0xff), false)

-- ---------------------------------------------------------------------
-- Rock Crusher: exactly 3 hand cards -> target Professor Oak.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    deckId = C.ROCK_CRUSHER_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.PROFESSOR_OAK, [10] = C.BULBASAUR, [11] = C.POKE_BALL, [999] = 0 },
    hand = { 10, 11, 999 },
  })
  local ok, selection = ai:_decideComputerSearch(999)
  check("RockCrusher, 3 hand cards, Oak in deck: plays", ok, true)
  check("RockCrusher: targets Oak's deck index", selection.deckCard, 50)
  check("RockCrusher: discards the first 2 non-blocklisted, non-played hand cards",
    selection.handDiscards, { 10, 11 })
end
do
  -- Professor Oak not in deck at all -> no play.
  local ai = newAI({
    deckId = C.ROCK_CRUSHER_DECK_ID,
    deckLocations = {},
    deckIndexToCardId = { [10] = C.BULBASAUR, [11] = C.POKE_BALL, [999] = 0 },
    hand = { 10, 11, 999 },
  })
  check("RockCrusher, 3 hand cards, Oak NOT in deck: no play", ai:_decideComputerSearch(999), false)
end
do
  -- Only 1 qualifying discard (blocklist filters the rest) -> no play.
  local ai = newAI({
    deckId = C.ROCK_CRUSHER_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.PROFESSOR_OAK, [10] = C.BULBASAUR, [11] = C.FIGHTING_ENERGY, [999] = 0 },
    hand = { 10, 11, 999 },
  })
  check("RockCrusher, only 1 non-blocklisted discard available: no play",
    ai:_decideComputerSearch(999), false)
end

-- ---------------------------------------------------------------------
-- Rock Crusher: more than 3 hand cards -> Geodude/Graveler evolution chain.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    deckId = C.ROCK_CRUSHER_DECK_ID,
    deckLocations = { [55] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [55] = C.GRAVELER, [1] = C.GEODUDE, [10] = C.BULBASAUR,
      [11] = C.CHANSEY, [999] = 0 },
    hand = { 1, 10, 11, 999 },
  })
  local ok, selection = ai:_decideComputerSearch(999)
  check("RockCrusher, Geodude in hand + Graveler in deck: fetches Graveler", ok, true)
  check("RockCrusher: targets Graveler", selection.deckCard, 55)
  check("RockCrusher: Geodude excluded from the discard pool", selection.handDiscards, { 10, 11 })
end
do
  -- No Graveler/Golem/Dugtrio chain available at all -> no play.
  local ai = newAI({
    deckId = C.ROCK_CRUSHER_DECK_ID,
    deckLocations = {},
    deckIndexToCardId = { [10] = C.BULBASAUR, [11] = C.CHANSEY, [12] = C.TAUROS, [999] = 0 },
    hand = { 10, 11, 12, 999 },
  })
  check("RockCrusher, no evolution chain available: no play", ai:_decideComputerSearch(999), false)
end

-- ---------------------------------------------------------------------
-- Wonders of Science: < 5 hand cards targets Professor Oak.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    deckId = C.WONDERS_OF_SCIENCE_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.PROFESSOR_OAK, [10] = C.POKE_BALL, [11] = C.GUST_OF_WIND, [999] = 0 },
    hand = { 10, 11, 999 },
  })
  local ok, selection = ai:_decideComputerSearch(999)
  check("WondersOfScience, <5 hand, Oak in deck: plays", ok, true)
  check("WondersOfScience: targets Oak", selection.deckCard, 50)
end
do
  -- >= 5 hand cards: falls to Grimer (not already in hand).
  local ai = newAI({
    deckId = C.WONDERS_OF_SCIENCE_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.GRIMER, [10] = C.POKE_BALL, [11] = C.GUST_OF_WIND, [12] = C.BULBASAUR,
      [13] = C.CHANSEY, [999] = 0 },
    hand = { 10, 11, 12, 13, 999 },
  })
  local ok, selection = ai:_decideComputerSearch(999)
  check("WondersOfScience, >=5 hand, Grimer not in hand: fetches Grimer", ok, true)
  check("WondersOfScience: targets Grimer", selection.deckCard, 50)
end
do
  -- Grimer already in hand -> falls to Muk.
  local ai = newAI({
    deckId = C.WONDERS_OF_SCIENCE_DECK_ID,
    deckLocations = { [51] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [51] = C.MUK, [1] = C.GRIMER, [10] = C.POKE_BALL, [11] = C.GUST_OF_WIND,
      [12] = C.BULBASAUR, [999] = 0 },
    hand = { 1, 10, 11, 12, 999 },
  })
  local ok, selection = ai:_decideComputerSearch(999)
  check("WondersOfScience, Grimer already in hand: fetches Muk instead", ok, true)
  check("WondersOfScience: targets Muk", selection.deckCard, 51)
end

-- ---------------------------------------------------------------------
-- Fire Charge: Chansey > Tauros > JigglypuffLv12 priority.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    deckId = C.FIRE_CHARGE_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK, [51] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.CHANSEY, [51] = C.TAUROS, [10] = C.POKE_BALL, [11] = C.GUST_OF_WIND,
      [999] = 0 },
    hand = { 10, 11, 999 },
  })
  local ok, selection = ai:_decideComputerSearch(999)
  check("FireCharge, Chansey and Tauros both in deck: Chansey wins", ok, true)
  check("FireCharge: targets Chansey", selection.deckCard, 50)
end
do
  -- Chansey already in hand -> skip to Tauros.
  local ai = newAI({
    deckId = C.FIRE_CHARGE_DECK_ID,
    deckLocations = { [51] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [51] = C.TAUROS, [1] = C.CHANSEY, [10] = C.POKE_BALL, [11] = C.GUST_OF_WIND,
      [999] = 0 },
    hand = { 1, 10, 11, 999 },
  })
  local ok, selection = ai:_decideComputerSearch(999)
  check("FireCharge, Chansey already in hand: falls to Tauros", ok, true)
  check("FireCharge: targets Tauros", selection.deckCard, 51)
end

-- ---------------------------------------------------------------------
-- Anger: evolution-chain search (Rattata/Raticate as the representative
-- pair), preferring the evolution when the pre-evolution is already out.
-- ---------------------------------------------------------------------
do
  local ai = newAI({
    deckId = C.ANGER_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.RATICATE, [1] = C.RATTATA, [10] = C.POKE_BALL, [11] = C.GUST_OF_WIND,
      [999] = 0 },
    hand = { 1, 10, 11, 999 },
  })
  local ok, selection = ai:_decideComputerSearch(999)
  check("Anger, Rattata in hand + Raticate in deck: fetches Raticate", ok, true)
  check("Anger: targets Raticate", selection.deckCard, 50)
end
do
  -- Raticate already in hand, Rattata itself in deck -> fetch Rattata.
  local ai = newAI({
    deckId = C.ANGER_DECK_ID,
    deckLocations = { [50] = C.CARD_LOCATION_DECK },
    deckIndexToCardId = { [50] = C.RATTATA, [1] = C.RATICATE, [10] = C.POKE_BALL, [11] = C.GUST_OF_WIND,
      [999] = 0 },
    hand = { 1, 10, 11, 999 },
  })
  local ok, selection = ai:_decideComputerSearch(999)
  check("Anger, Raticate already in hand: fetches Rattata itself", ok, true)
  check("Anger: targets Rattata", selection.deckCard, 50)
end
do
  -- Neither condition met for any of the three pairs -> no play.
  local ai = newAI({
    deckId = C.ANGER_DECK_ID,
    deckLocations = {},
    deckIndexToCardId = { [10] = C.POKE_BALL, [11] = C.GUST_OF_WIND, [999] = 0 },
    hand = { 10, 11, 999 },
  })
  check("Anger, no chain condition met: no play", ai:_decideComputerSearch(999), false)
end

if failures == 0 then
  print("all Computer Search AI decision cases passed")
  os.exit(0)
else
  print(("%d Computer Search AI decision case(s) failed"):format(failures))
  os.exit(1)
end
