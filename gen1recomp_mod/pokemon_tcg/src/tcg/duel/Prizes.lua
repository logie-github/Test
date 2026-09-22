-- Prize-card selection/taking translated from pret/poketcg
-- engine/menus/duel.asm _SelectPrizeCards and engine/duel/core.asm
-- TurnDuelistTakePrizes. UI choice itself remains an adapter.

local Prizes = {}
Prizes.__index = Prizes

function Prizes.new(memory, duelVars, duelOps, ai, setup, constants, adapters)
  return setmetatable({
    memory = assert(memory),
    duelVars = assert(duelVars),
    duelOps = assert(duelOps),
    ai = assert(ai),
    setup = assert(setup),
    c = assert(constants),
    adapters = adapters or {},
  }, Prizes)
end

function Prizes:_required(name)
  local fn = self.adapters[name]
  assert(type(fn) == "function", "TCG prize flow requires untranslated adapter: " .. name)
  return fn
end

function Prizes:_event(name, payload)
  local fn = self.adapters.event
  if fn then fn(name, payload or {}) end
end

local function bitMask(index) return 2 ^ index end

function Prizes:_setSelectedListPointer(address)
  local ptr, bank = self.memory:address("wSelectedPrizeCardListPtr")
  self.memory:write8("wram", ptr, address % 0x100, bank)
  self.memory:write8("wram", ptr + 1, math.floor(address / 0x100) % 0x100, bank)
end

-- _SelectPrizeCards:: State-equivalent card selection. The adapter only chooses
-- a prize cursor index that the source UI would allow (0..5 and currently set).
function Prizes:selectPrizeCards(amount)
  self.memory:writeSymbol8("wNumberOfPrizeCardsToSelect", amount)
  local listSpace, listBank, listAddress = self.memory:resolve("hTempPlayAreaLocation_ffa1")
  assert(listSpace == "hram", "selected prize list base moved out of HRAM")
  self:_setSelectedListPointer(listAddress)
  local outPos = 0

  while self.memory:readSymbol8("wNumberOfPrizeCardsToSelect") ~= 0 do
    local prizes = self.duelVars:get(self.c.DUELVARS_PRIZES)
    if prizes == 0 then break end
    local index = self:_required("selectPrizeCard")(prizes,
      self.memory:readSymbol8("wNumberOfPrizeCardsToSelect"))
    assert(type(index) == "number" and index >= 0 and index < 6,
      "SelectPrizeCards adapter returned invalid prize index")
    local mask = bitMask(index)
    assert(prizes % (mask * 2) >= mask,
      "SelectPrizeCards adapter selected an already-taken prize")

    self.duelVars:set(self.c.DUELVARS_PRIZES, prizes - mask)
    local deckIndex = self.duelVars:get(self.c.DUELVARS_PRIZE_CARDS + index)
    self.memory:write8(listSpace, listAddress + outPos, deckIndex, listBank)
    outPos = outPos + 1
    self.duelOps:addCardToHand(deckIndex)
    self:_event("prize_selected", { index = index, deckIndex = deckIndex })
    self.memory:writeSymbol8("wNumberOfPrizeCardsToSelect",
      self.memory:readSymbol8("wNumberOfPrizeCardsToSelect") - 1)
  end

  local prizes = self.duelVars:get(self.c.DUELVARS_PRIZES)
  self.memory:writeSymbol8("hTemp_ffa0", prizes)
  self.memory:write8(listSpace, listAddress + outPos, 0xff, listBank)
  return prizes
end

-- TurnDuelistTakePrizes:: returns carry=true when all prizes were taken.
function Prizes:turnDuelistTakePrizes()
  local amount = self.memory:readSymbol8("wNumberPrizeCardsToTake")
  local dtype = self.duelVars:get(self.c.DUELVARS_DUELIST_TYPE)

  if dtype == self.c.DUELIST_TYPE_PLAYER then
    self:_event("will_draw_prizes", { amount = amount, player = true })
    self:selectPrizeCards(amount)
    if self.memory:readSymbol8("wDuelType") == self.c.DUELTYPE_LINK then
      self:_required("sendPrizeSelection")(
        self.memory:readSymbol8("hTemp_ffa0"),
        self.memory:readSymbol8("hTempPlayAreaLocation_ffa1"))
    end
  else
    self:_event("will_draw_prizes", { amount = amount, player = false })
    local before = self.duelOps:countPrizes()
    self.memory:writeSymbol8("wTempNumRemainingPrizeCards", before)
    if dtype == self.c.DUELIST_TYPE_LINK_OPP then
      local newMask, deckIndex = self:_required("receivePrizeSelection")()
      self.duelVars:set(self.c.DUELVARS_PRIZES, newMask)
      if deckIndex ~= 0xff then self.duelOps:addCardToHand(deckIndex) end
    else
      self.ai:takePrize()
    end
    self:_event("drew_prizes", { amount = math.min(before, amount) })
  end

  local failed, err = self.setup:exchangeRNG()
  if failed then return nil, err end
  return self.duelVars:get(self.c.DUELVARS_PRIZES) == 0
end

return Prizes
