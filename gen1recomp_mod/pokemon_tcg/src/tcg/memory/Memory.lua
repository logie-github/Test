-- Sparse Game Boy RAM model for the Pokemon TCG translation.
--
-- Source of truth: pret/poketcg src/wram.asm, src/hram.asm, src/sram.asm and
-- the RGBDS symbol map generated from that same decomp revision.  The model is
-- deliberately address-based: aliases and UNIONs remain aliases because they
-- resolve to the same bank/address instead of becoming duplicated Lua fields.

local Memory = {}
Memory.__index = Memory

local function byte(value)
  assert(type(value) == "number", "memory write must be numeric")
  return value % 0x100
end

local function bankTable(space, bank, create)
  local row = space[bank]
  if not row and create then
    row = {}
    space[bank] = row
  end
  return row
end

function Memory.new(spec)
  assert(type(spec) == "table" and spec.schema == 1,
    "generated TCG memory map is required")
  assert(type(spec.symbols) == "table", "TCG memory symbols are missing")
  return setmetatable({
    symbols = spec.symbols,
    spaces = { wram = {}, hram = {}, sram = {} },
  }, Memory)
end

function Memory:resolve(name)
  for _, spaceName in ipairs({ "wram", "hram", "sram" }) do
    local loc = self.symbols[spaceName] and self.symbols[spaceName][name]
    if loc then
      return spaceName, loc[1], loc[2]
    end
  end
  error("unknown TCG RAM symbol: " .. tostring(name))
end

function Memory:address(name)
  local _, bank, address = self:resolve(name)
  return address, bank
end

function Memory:read8(spaceName, address, bank)
  bank = bank or 0
  local space = assert(self.spaces[spaceName], "unknown RAM space " .. tostring(spaceName))
  local row = bankTable(space, bank, false)
  local value = row and row[address]
  if value == nil then
    error(("uninitialized TCG %s read at bank %02x:$%04x")
      :format(spaceName, bank, address))
  end
  return value
end

function Memory:write8(spaceName, address, value, bank)
  bank = bank or 0
  local space = assert(self.spaces[spaceName], "unknown RAM space " .. tostring(spaceName))
  bankTable(space, bank, true)[address] = byte(value)
end

function Memory:readSymbol8(name)
  local space, bank, address = self:resolve(name)
  return self:read8(space, address, bank)
end

function Memory:writeSymbol8(name, value)
  local space, bank, address = self:resolve(name)
  self:write8(space, address, value, bank)
end

function Memory:writeBlock(spaceName, address, values, bank)
  for index, value in ipairs(values) do
    self:write8(spaceName, address + index - 1, value, bank)
  end
end

function Memory:readBlock(spaceName, address, length, bank)
  local out = {}
  for index = 0, length - 1 do
    out[#out + 1] = self:read8(spaceName, address + index, bank)
  end
  return out
end

function Memory:zero(spaceName, address, length, bank)
  for index = 0, length - 1 do
    self:write8(spaceName, address + index, 0, bank)
  end
end

function Memory:zeroSymbolPage(name)
  local space, bank, address = self:resolve(name)
  self:zero(space, math.floor(address / 0x100) * 0x100, 0x100, bank)
end

-- ZeroRAM:: from pret/poketcg src/home/setup.asm. Start calls this before
-- entering GameLoop, so standalone translated entry points must reproduce the
-- same initialized WRAM/HRAM state rather than relying on sparse-memory reads.
function Memory:zeroBootRAM()
  self:zero("wram", 0xc000, 0x2000, 0)
  self:zero("hram", 0xff80, 0x70, 0)
end

return Memory
