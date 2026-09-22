-- Start-of-duel orchestration translated from pret/poketcg
-- src/engine/duel/core.asm (HandleDuelSetup and
-- ChooseInitialArenaAndBenchPokemon) plus the state-relevant part of TossCoin.
--
-- Presentation, AI policy, and link transport are explicit adapters. This file
-- never auto-selects a card, invents AI choices, or treats missing networking as
-- success. The RAM mutations and branch order follow the decomp.

local bit = require("bit")

local DuelSetup = {}
DuelSetup.__index = DuelSetup

local function u8(value) return bit.band(value, 0xff) end

function DuelSetup.new(memory, duelVars, rng, cardData, duelOps, core, constants, adapters)
  return setmetatable({
    memory = assert(memory),
    duelVars = assert(duelVars),
    rng = assert(rng),
    cardData = assert(cardData),
    duelOps = assert(duelOps),
    core = assert(core),
    c = assert(constants),
    adapters = adapters or {},
    ai = nil,
    practice = nil,
  }, DuelSetup)
end

function DuelSetup:setAI(ai)
  self.ai = assert(ai)
end

function DuelSetup:setPractice(practice)
  self.practice = assert(practice)
end

function DuelSetup:_event(name, payload)
  local fn = self.adapters.event
  if fn then fn(name, payload or {}) end
end

function DuelSetup:_required(name)
  local fn = self.adapters[name]
  assert(type(fn) == "function",
    "TCG duel setup requires untranslated adapter: " .. name)
  return fn
end

function DuelSetup:_practice(actionName)
  local action = self.c[actionName]
  assert(action ~= nil, "missing decomp practice constant " .. actionName)
  assert(self.practice, "DoPracticeDuelAction runtime is not connected")
  return self.practice:doAction(action)
end

-- State-relevant result generation from _TossCoin::
-- UpdateRNGSources; RRA; carry => tails, otherwise heads.
function DuelSetup:tossCoinLocal()
  self.memory:writeSymbol8("wCoinTossTotalNum", 1)
  self.memory:writeSymbol8("wCoinTossNumTossed", 0)
  self.memory:writeSymbol8("wCoinTossDuelistType",
    self.duelVars:get(self.c.DUELVARS_DUELIST_TYPE))
  self.memory:writeSymbol8("wCoinTossNumHeads", 0)
  local value = self.rng:updateSources()
  local tails = bit.band(value, 1) ~= 0
  local result = tails and self.c.TAILS or self.c.HEADS
  self.memory:writeSymbol8("wCoinTossNumTossed", 1)
  if result == self.c.HEADS then self.memory:writeSymbol8("wCoinTossNumHeads", 1) end
  -- TossCoin (the one-toss wrapper) clears wDuelDisplayedScreen after _TossCoin.
  self.memory:writeSymbol8("wDuelDisplayedScreen", 0)
  return result
end

-- TossCoin:: Link coin tosses include serial synchronization inside _TossCoin;
-- never substitute a local result in a link duel.
function DuelSetup:tossCoin()
  if self.memory:readSymbol8("wDuelType") == self.c.DUELTYPE_LINK then
    local result, err = self:_required("tossCoinLink")(self.duelVars:turn())
    if result == nil then return nil, err end
    assert(result == self.c.HEADS or result == self.c.TAILS,
      "tossCoinLink returned a non-source coin value")
    return result
  end
  return self:tossCoinLocal()
end

-- TossCoinATimes:: state-relevant result generation. Fixed-count multi-coin
-- effects are common across the card library. Link duels remain an explicit
-- transport boundary because the cartridge synchronizes the whole toss.
function DuelSetup:tossCoinATimes(count)
  assert(type(count) == "number" and count >= 0 and count <= 0xff,
    "coin count must be an unsigned byte")
  if self.memory:readSymbol8("wDuelType") == self.c.DUELTYPE_LINK then
    local heads, err = self:_required("tossCoinATimesLink")(self.duelVars:turn(), count)
    if heads == nil then return nil, err end
    assert(type(heads) == "number" and heads >= 0 and heads <= (count == 0 and 1 or count),
      "tossCoinATimesLink returned an invalid head count")
    return heads, heads ~= 0
  end

  -- A=0 is used by the source as one toss in loops that continue until tails.
  local total = count == 0 and 1 or count
  self.memory:writeSymbol8("wCoinTossTotalNum", count)
  self.memory:writeSymbol8("wCoinTossNumTossed", 0)
  self.memory:writeSymbol8("wCoinTossDuelistType",
    self.duelVars:get(self.c.DUELVARS_DUELIST_TYPE))
  self.memory:writeSymbol8("wCoinTossNumHeads", 0)
  local heads = 0
  for tossed = 1, total do
    local value = self.rng:updateSources()
    if bit.band(value, 1) == 0 then heads = heads + 1 end
    self.memory:writeSymbol8("wCoinTossNumTossed", tossed)
    self.memory:writeSymbol8("wCoinTossNumHeads", heads)
  end
  return heads, heads ~= 0
end

local function block(memory, space, address, length, bank)
  return memory:readBlock(space, address, length, bank)
end

-- ExchangeRNG:: High-level native transport boundary. Serial encoding/timing is
-- a hardware subsystem; the exchanged byte ranges and direction are source-exact.
function DuelSetup:exchangeRNG()
  if self.memory:readSymbol8("wDuelType") ~= self.c.DUELTYPE_LINK then
    return false
  end
  local exchange = self:_required("serialExchange")
  local dtype = self.duelVars:get(self.c.DUELVARS_DUELIST_TYPE)
  local sendSymbol, recvSymbol
  if dtype == self.c.DUELIST_TYPE_PLAYER then
    sendSymbol, recvSymbol = "wRNGVars", "wOppRNGVars"
  else
    sendSymbol, recvSymbol = "wOppRNGVars", "wRNGVars"
  end
  local sendAddr, sendBank = self.memory:address(sendSymbol)
  local recvAddr, recvBank = self.memory:address(recvSymbol)
  local count = assert(self.c.RNGVARS_SIZE, "RNGVARS_SIZE missing from decomp constants")
  local received, err = exchange(block(self.memory, "wram", sendAddr, count, sendBank), {
    sourceRoutine = "ExchangeRNG",
    chunk = 1,
    chunks = 1,
  })
  if not received then return true, err end
  assert(#received == count, "ExchangeRNG transport returned wrong byte count")
  self.memory:writeBlock("wram", recvAddr, received, recvBank)
  return false
end

-- ChooseInitialArenaAndBenchPokemon.exchange_duelvars performs two sequential
-- 0x80-byte SerialExchangeBytes calls. Preserve that chunk boundary.
function DuelSetup:exchangeDuelVars()
  local exchange = self:_required("serialExchange")
  local player, playerBank = self.memory:address("wPlayerDuelVariables")
  local opponent, opponentBank = self.memory:address("wOpponentDuelVariables")
  assert(playerBank == 0 and opponentBank == 0, "duel variable pages moved out of WRAM0")
  local half = math.floor((opponent - player) / 2)
  assert(half * 2 == opponent - player,
    "player/opponent duel-variable page distance is no longer even")

  for chunkIndex = 0, 1 do
    local sendAddress = player + chunkIndex * half
    local recvAddress = opponent + chunkIndex * half
    local received, err = exchange(block(self.memory, "wram", sendAddress, half, 0), {
      sourceRoutine = "ChooseInitialArenaAndBenchPokemon.exchange_duelvars",
      chunk = chunkIndex + 1,
      chunks = 2,
    })
    if not received then return true, err end
    assert(#received == half, "duel-var transport returned wrong byte count")
    self.memory:writeBlock("wram", recvAddress, received, 0)
  end
  return false
end

function DuelSetup:_handContains(deckIndex)
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_CARDS_IN_HAND)
  for i = 0, count - 1 do
    if self.duelVars:get(self.c.DUELVARS_HAND + i) == deckIndex then return true end
  end
  return false
end

function DuelSetup:_requireInitialBasic(deckIndex)
  assert(type(deckIndex) == "number" and deckIndex >= 0 and deckIndex < self.c.DECK_SIZE,
    "initial Pokemon selection must be a deck index 0..59")
  assert(self:_handContains(deckIndex), "initial Pokemon selection is not in hand")
  self.cardData:loadBuffer1FromDeckIndex(deckIndex)
  local basic, carry = self.cardData:isLoadedCard1BasicPokemon()
  assert(not carry and basic ~= 0,
    "initial Pokemon selection is not a Basic Pokemon under decomp rules")
end

function DuelSetup:_choosePlayerInitialPokemon()
  local selectActive = self:_required("selectInitialActive")
  local selectBench = self:_required("selectInitialBench")

  while true do
    self:_event("choose_initial_active", { turn = self.duelVars:turn() })
    if self:_practice("PRACTICEDUEL_DRAW_SEVEN_CARDS") then
      -- Source loops through the selection screen; the adapter supplies the
      -- next selection attempt after the practice action rejects it.
    end
    local deckIndex = selectActive(self.duelVars:turn())
    self:_requireInitialBasic(deckIndex)
    if not self:_practice("PRACTICEDUEL_PLAY_GOLDEEN") then
      local _, carry = self.duelOps:putHandPokemonCardInPlayArea(deckIndex)
      assert(not carry, "source initial active placement unexpectedly had no play-area slot")
      self:_event("placed_initial_active", { deckIndex = deckIndex })
      break
    end
  end

  self:_event("choose_initial_bench", { turn = self.duelVars:turn() })
  if self.memory:readSymbol8("wDuelType") == self.c.DUELTYPE_PRACTICE then
    self:_practice("PRACTICEDUEL_PUT_STARYU_IN_BENCH")
  end

  while true do
    local deckIndex = selectBench(self.duelVars:turn())
    if deckIndex == nil then
      if not self:_practice("PRACTICEDUEL_VERIFY_INITIAL_PLAY") then break end
    else
      local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
      if count >= self.c.MAX_PLAY_AREA_POKEMON then
        self:_event("initial_bench_full", {})
      else
        self:_requireInitialBasic(deckIndex)
        local _, carry = self.duelOps:putHandPokemonCardInPlayArea(deckIndex)
        assert(not carry, "bench count allowed placement but PutHandPokemonCardInPlayArea carried")
        self:_event("placed_initial_bench", { deckIndex = deckIndex })
        self:_practice("PRACTICEDUEL_DONE_PUTTING_ON_BENCH")
      end
    end
  end
  return false
end

-- ChooseInitialArenaAndBenchPokemon::
function DuelSetup:chooseInitialArenaAndBenchPokemon()
  local dtype, dtypeAddress = self.duelVars:get(self.c.DUELVARS_DUELIST_TYPE)
  if dtype == self.c.DUELIST_TYPE_PLAYER then
    return self:_choosePlayerInitialPokemon()
  end

  if dtype == self.c.DUELIST_TYPE_LINK_OPP then
    self:_event("transmitting_initial_duelvars", {})
    local failed, err = self:exchangeRNG()
    if failed then return true, err end
    return self:exchangeDuelVars()
  end

  -- AI branch: source preserves the DUELVARS_DUELIST_TYPE byte across
  -- AIDoAction_StartDuel even though the action routine may clobber registers.
  assert(self.ai, "AIDoAction_StartDuel runtime is not connected")
  self.ai:startDuel()
  self.memory:write8("wram", dtypeAddress, dtype, 0)
  return false
end

function DuelSetup:_redrawTurnUntilBasic(side)
  while true do
    self:_event("no_basic_in_starting_hand", { side = side, turn = self.duelVars:turn() })
    self.core:initializeDuelVariables()
    self:_event("shuffle_and_draw_seven", { side = side, turn = self.duelVars:turn() })
    local value, carry = self.core:shuffleDeckAndDrawSevenCards()
    if not carry then return value end
  end
end

function DuelSetup:_establishStartingHands()
  while true do
    -- HandleDuelSetup begins by zeroing both duel-variable pages, then each
    -- ShuffleDeckAndDrawSevenCards reinitializes its own page again.
    self.core:initializeDuelVariables()
    self.duelVars:swapTurn()
    self.core:initializeDuelVariables()
    self.duelVars:swapTurn()
    self:_event("both_shuffle_and_draw", {})

    local playerValue = self.core:shuffleDeckAndDrawSevenCards()
    self.memory:writeSymbol8("hTemp_ffa0", playerValue)
    self.duelVars:swapTurn()
    local opponentValue = self.core:shuffleDeckAndDrawSevenCards()
    self.duelVars:swapTurn()

    local both = bit.band(playerValue, opponentValue)
    if both ~= 0 then return end

    if bit.bor(playerValue, opponentValue) == 0 then
      self:_event("neither_drew_basic", {})
      self.core:initializeDuelVariables()
      self.duelVars:swapTurn()
      self.core:initializeDuelVariables()
      self.duelVars:swapTurn()
      self:_event("return_both_hands_and_restart_setup", {})
      -- Source jumps to HandleDuelSetup, including its initial page reset.
    elseif playerValue == 0 then
      self:_redrawTurnUntilBasic("player")
      return
    else
      self.duelVars:swapTurn()
      self:_redrawTurnUntilBasic("opponent")
      self.duelVars:swapTurn()
      return
    end
  end
end

function DuelSetup:_placePrizes(savedTurn)
  self:_event("placing_prizes", { count = self.memory:readSymbol8("wDuelInitialPrizes") })
  -- Source calls ExchangeRNG while hWhoseTurn is still PLAYER_TURN after the
  -- two initial-placement calls. Only after the visual prize placement does it
  -- pop the saved turn and draw the actual prize cards.
  local failed, err = self:exchangeRNG()
  if failed then return true, err end
  self.duelVars:setTurn(savedTurn)
  self.core:initTurnDuelistPrizes()
  self.duelVars:swapTurn()
  self.core:initTurnDuelistPrizes()
  self.duelVars:swapTurn()
  return false
end

function DuelSetup:_decideFirstPlayer()
  self:_event("coin_toss_to_decide_first_player", { turn = self.duelVars:turn() })

  local result, tossErr = self:tossCoin()
  if result == nil then return true, tossErr end

  -- In both source branches, heads means the current hWhoseTurn duelist goes
  -- first; tails swaps hWhoseTurn before the explanatory text is shown.
  if result == self.c.TAILS then self.duelVars:swapTurn() end
  self:_event("first_player_decided", { result = result, turn = self.duelVars:turn() })

  local failed, err = self:exchangeRNG()
  if failed then return true, err end
  return false
end

-- HandleDuelSetup:: deterministic state orchestration. Returns carry/error as
-- (true, err) on a link-transport failure, otherwise false.
function DuelSetup:handleDuelSetup()
  self:_establishStartingHands()

  local savedTurn = self.duelVars:turn()
  self.duelVars:setTurn(self.c.PLAYER_TURN)
  local failed, err = self:chooseInitialArenaAndBenchPokemon()
  if failed then return true, err end
  self.duelVars:swapTurn()
  failed, err = self:chooseInitialArenaAndBenchPokemon()
  self.duelVars:swapTurn()
  if failed then return true, err end

  -- hWhoseTurn is PLAYER_TURN here, exactly as in the source. Prize setup
  -- performs its pre-placement ExchangeRNG before restoring savedTurn.
  failed, err = self:_placePrizes(savedTurn)
  if failed then return true, err end
  return self:_decideFirstPlayer()
end

return DuelSetup
