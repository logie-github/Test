-- Native translation of pret/poketcg src/home/random.asm plus ShuffleCards
-- from src/home/duel.asm.  This intentionally preserves the game's RNG and
-- non-Fisher-Yates shuffle algorithm byte-for-byte at the state level.

local bit = require("bit")

local RNG = {}
RNG.__index = RNG

local function u8(v) return bit.band(v, 0xff) end
local function rol8(v)
  return u8(bit.lshift(v, 1) + bit.rshift(v, 7))
end

function RNG.new(memory)
  return setmetatable({ memory = assert(memory) }, RNG)
end

-- UpdateRNGSources:: exact 8-bit rotate/xor/carry sequence.
function RNG:updateSources()
  local rng1 = self.memory:readSymbol8("wRNG1")
  local rng2 = self.memory:readSymbol8("wRNG2")
  local counter = self.memory:readSymbol8("wRNGCounter")

  local a = bit.bxor(rol8(rol8(rng2)), rng1)
  -- XOR clears carry; RRA therefore shifts in zero and saves old bit 0 as C.
  local carry = bit.band(a, 1)
  a = bit.rshift(a, 1)

  local d = u8(bit.bxor(rng2, rng1))
  local e = u8(bit.bxor(counter, rng1))

  local nextCarry = bit.band(bit.rshift(e, 7), 1)
  e = u8(bit.lshift(e, 1) + carry)
  carry = nextCarry
  d = u8(bit.lshift(d, 1) + carry)

  local result = u8(bit.bxor(d, e))
  self.memory:writeSymbol8("wRNGCounter", counter + 1)
  self.memory:writeSymbol8("wRNG2", d)
  self.memory:writeSymbol8("wRNG1", e)
  return result
end

-- Random:: returns high byte of maxExclusive * UpdateRNGSources().
function RNG:random(maxExclusive)
  assert(type(maxExclusive) == "number" and maxExclusive >= 0 and maxExclusive <= 0xff)
  local source = self:updateSources()
  return math.floor((maxExclusive * source) / 0x100)
end

-- ShuffleCards:: for every position, swap against Random(original count).
function RNG:shuffleCards(address, count)
  count = count % 0x100
  if count == 0 then return end
  local originalCount = count
  for index = 0, count - 1 do
    local other = address + self:random(originalCount)
    local current = address + index
    local a = self.memory:read8("wram", other, 0)
    local b = self.memory:read8("wram", current, 0)
    self.memory:write8("wram", current, a, 0)
    self.memory:write8("wram", other, b, 0)
  end
end

return RNG
