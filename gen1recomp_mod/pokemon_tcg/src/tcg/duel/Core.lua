-- Foundational engine/duel/core.asm state routines translated directly from
-- pret/poketcg. They operate on the source WRAM/HRAM/SRAM addresses through
-- the generated RGBDS memory map; no parallel "friendly" duel state exists.

local bit = require("bit")

local Core = {}
Core.__index = Core

local function u8(value) return bit.band(value, 0xff) end

function Core.new(memory, duelVars, duelOps, constants, coreData)
  assert(memory and duelVars and duelOps and constants and coreData)
  assert(coreData.schema == 3, "unsupported generated TCG core-data schema")
  return setmetatable({
    memory = memory,
    duelVars = duelVars,
    duelOps = duelOps,
    c = constants,
    data = coreData,
  }, Core)
end

local function hasBit(value, index)
  return bit.band(value, bit.lshift(1, index)) ~= 0
end

-- InitVariablesToBeginDuel::
function Core:initVariablesToBeginDuel()
  self.memory:writeSymbol8("wDuelFinished", 0)
  self.memory:writeSymbol8("wDuelTurns", 0)
  self.memory:writeSymbol8("wUnused_cce7", 0)
  self.memory:writeSymbol8("wUnused_cc0f", 0xff)
  self.memory:writeSymbol8("wPlayerAttackingCardIndex", 0xff)
  self.memory:writeSymbol8("wPlayerAttackingAttackIndex", 0xff)

  -- EnableSRAM/DisableSRAM are hardware gating in the original. The native
  -- memory model addresses SRAM directly but preserves the exact source byte.
  self.memory:writeSymbol8("wSkipDelayAllowed",
    self.memory:readSymbol8("sSkipDelayAllowed"))

  local dtype = self.memory:readSymbol8("wPlayerDuelistType")
  if dtype ~= self.c.DUELIST_TYPE_LINK_OPP and not hasBit(dtype, 7) then
    dtype = self.memory:readSymbol8("wOpponentDuelistType")
    if dtype ~= self.c.DUELIST_TYPE_LINK_OPP and not hasBit(dtype, 7) then
      dtype = 0
    end
  end
  self.memory:writeSymbol8("wDuelType", dtype)
  return dtype
end

-- InitVariablesToBeginTurn::
function Core:initVariablesToBeginTurn()
  self.memory:writeSymbol8("wAlreadyPlayedEnergy", 0)
  self.memory:writeSymbol8("wConfusionRetreatCheckWasUnsuccessful", 0)
  self.memory:writeSymbol8("wGotHeadsFromSandAttackOrSmokescreenCheck", 0)
  self.memory:writeSymbol8("wWhoseTurn", self.duelVars:turn())
end

-- SetAllPlayAreaPokemonCanEvolve::
-- The repeat-until is intentional: RGBDS `dec c / jr nz` executes 256 times
-- when entered with c==0. Normal duel states call this with Pokemon in play,
-- but retaining the byte-loop shape avoids silently changing source behavior.
function Core:setAllPlayAreaPokemonCanEvolve()
  local count = self.duelVars:get(self.c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA)
  local address = self.duelVars:address(self.c.DUELVARS_ARENA_CARD_FLAGS)
  repeat
    local flags = self.memory:read8("wram", address, 0)
    flags = bit.band(flags,
      bit.bnot(bit.lshift(1, self.c.USED_PKMN_POWER_THIS_TURN_F)))
    flags = bit.bor(flags, bit.lshift(1, self.c.CAN_EVOLVE_THIS_TURN_F))
    self.memory:write8("wram", address, flags, 0)
    -- Source uses `inc l`, not `inc hl`: wrap within the same 256-byte duel page.
    address = bit.bor(bit.band(address, 0xff00), bit.band(address + 1, 0xff))
    count = u8(count - 1)
  until count == 0
end

-- InitializeDuelVariables::
function Core:initializeDuelVariables()
  local high = self.duelVars:turn()
  local page = high * 0x100
  local dtypeAddress = page + self.c.DUELVARS_DUELIST_TYPE
  local dtype = self.memory:read8("wram", dtypeAddress, 0)

  self.memory:zero("wram", page, 0x100, 0)
  self.memory:write8("wram", dtypeAddress, dtype, 0)

  for deckIndex = 0, self.c.DECK_SIZE - 1 do
    self.memory:write8("wram",
      page + self.c.DUELVARS_DECK_CARDS + deckIndex, deckIndex, 0)
    self.memory:write8("wram",
      page + self.c.DUELVARS_CARD_LOCATIONS + deckIndex, 0, 0)
  end

  for offset = 0, self.c.MAX_PLAY_AREA_POKEMON do
    self.memory:write8("wram",
      page + self.c.DUELVARS_ARENA_CARD + offset, 0xff, 0)
  end
end

-- ShuffleDeckAndDrawSevenCards::
-- Returns the source A result and carry as (0|1, carry).  This entry point
-- deliberately uses the local Basic-Pokemon test that excludes Clefairy Doll
-- and Mysterious Fossil, exactly as the setup routine does.
function Core:shuffleDeckAndDrawSevenCards()
  self:initializeDuelVariables()
  if self.memory:readSymbol8("wDuelType") ~= self.c.DUELTYPE_PRACTICE then
    self.duelOps:shuffleDeck()
    self.duelOps:shuffleDeck()
  end

  local draws = self.c.STARTING_HAND_SIZE
  for _ = 1, draws do
    local deckIndex = self.duelOps:drawCardFromDeck()
    self.duelOps:addCardToHand(deckIndex)
  end

  local hasBasic = 0
  for index = 0, draws - 1 do
    local deckIndex = self.duelVars:get(self.c.DUELVARS_HAND + index)
    self.duelOps.cardData:loadBuffer1FromDeckIndex(deckIndex)
    local result = self.duelOps.cardData:isLoadedCard1BasicPokemonSkipSpecial()
    hasBasic = bit.bor(hasBasic, result)
  end
  if hasBasic ~= 0 then return hasBasic, false end
  return 0, true
end


-- InitTurnDuelistPrizes::
function Core:initTurnDuelistPrizes()
  local high = self.duelVars:turn()
  local dest = high * 0x100 + self.c.DUELVARS_PRIZE_CARDS
  local target = self.memory:readSymbol8("wDuelInitialPrizes")
  local drawn = 0

  repeat
    local deckIndex = self.duelOps:drawCardFromDeck()
    -- The assembly ignores carry and keeps A. drawCardFromDeck therefore
    -- returns A even on its carry path, rather than returning nil.
    self.memory:write8("wram", dest, deckIndex, 0)
    dest = dest + 1
    self.memory:write8("wram",
      high * 0x100 + self.c.DUELVARS_CARD_LOCATIONS + deckIndex,
      self.c.CARD_LOCATION_PRIZE, 0)
    drawn = u8(drawn + 1)
  until drawn == target

  local mask = self.data.prizeBitmasks[target + 1]
  assert(mask ~= nil,
    "wDuelInitialPrizes indexed past decomp PrizeBitmasks table")
  self.memory:write8("wram", high * 0x100 + self.c.DUELVARS_PRIZES, mask, 0)
  return mask
end

-- TakeAPrizes:: (name preserved from the decomp).
function Core:takeAPrizes(amount)
  amount = u8(amount)
  if amount == 0 then return self.duelVars:get(self.c.DUELVARS_PRIZES) end
  local count = self.duelOps:countPrizes()
  local remaining = count - amount
  if remaining < 0 then remaining = 0 end
  local mask = self.data.prizeBitmasks[remaining + 1]
  assert(mask ~= nil, "prize count indexed past decomp PrizeBitmasks table")
  self.duelVars:set(self.c.DUELVARS_PRIZES, mask)
  return mask
end

-- ClearNonTurnTemporaryDuelvars::
function Core:clearNonTurnTemporaryDuelvars()
  local _, address = self.duelVars:getNonTurn(
    self.c.DUELVARS_ARENA_CARD_DISABLED_ATTACK_INDEX)
  self.memory:zero("wram", address, 8, 0)
end

-- ClearNonTurnTemporaryDuelvars_CopyStatus::
function Core:clearNonTurnTemporaryDuelvarsCopyStatus()
  local status = self.duelVars:getNonTurn(self.c.DUELVARS_ARENA_CARD_STATUS)
  self.memory:writeSymbol8("wUnused_DefendingPkmnStatus", status)
  self:clearNonTurnTemporaryDuelvars()
  return status
end

-- UpdateArenaCardLastTurnDamage::
function Core:updateArenaCardLastTurnDamage()
  local _, address = self.duelVars:getNonTurn(
    self.c.DUELVARS_ARENA_CARD_LAST_TURN_DAMAGE)
  if self.memory:readSymbol8("wDefendingWasForcedToSwitch") ~= 0 then
    self.memory:write8("wram", address, 0, 0)
    self.memory:write8("wram", address + 1, 0, 0)
    return 0
  end

  local dealt, bank = self.memory:address("wDealtDamage")
  assert(bank == 0, "wDealtDamage unexpectedly moved out of WRAM0")
  local lo = self.memory:read8("wram", dealt, bank)
  local hi = self.memory:read8("wram", dealt + 1, bank)
  self.memory:write8("wram", address, lo, 0)
  self.memory:write8("wram", address + 1, hi, 0)
  return lo + hi * 0x100
end

return Core
