-- Duel save/restore translated from pret/poketcg
-- src/engine/duel/core.asm SaveDuelData*, LoadSavedDuelDataFromDE and
-- src/home/duel.asm SaveDuelStateToSRAM.
--
-- The payload layout is not recreated here: RomExtractor reads the exact
-- DuelDataToSave table from the validated cartridge and emits it in tcg_core.

local bit = require("bit")

local SaveData = {}
SaveData.__index = SaveData

local SNAPSHOT_DATA_OFFSET = 0x10 -- exact `ld de, $10` in SaveDuelStateToSRAM

function SaveData.new(memory, duelVars, cardData, constants, coreData)
  assert(type(coreData) == "table" and coreData.schema == 3,
    "generated TCG core-data schema 3 is required")
  local layout = assert(coreData.duelDataToSave, "DuelDataToSave extraction missing")
  assert(#layout > 0, "DuelDataToSave extraction is empty")
  return setmetatable({
    memory = assert(memory),
    duelVars = assert(duelVars),
    cardData = assert(cardData),
    c = assert(constants),
    layout = layout,
  }, SaveData)
end

function SaveData:_symbolLocation(name)
  local space, bank, address = self.memory:resolve(name)
  assert(space == "sram", name .. " is not an SRAM symbol")
  return bank, address
end

function SaveData:_payloadFromMemory()
  local payload = {}
  for _, entry in ipairs(self.layout) do
    assert(entry.space == "wram" or entry.space == "hram",
      "unsupported DuelDataToSave source space: " .. tostring(entry.space))
    local bytes = self.memory:readBlock(entry.space, entry.address, entry.size, entry.bank or 0)
    for _, value in ipairs(bytes) do payload[#payload + 1] = value end
  end
  assert(#payload == self.c.SAVE_DUEL_DATA_SIZE,
    "DuelDataToSave payload size does not match source constant")
  return payload
end

function SaveData:_restorePayload(payload)
  assert(#payload == self.c.SAVE_DUEL_DATA_SIZE,
    "saved duel payload size does not match source constant")
  local pos = 1
  for _, entry in ipairs(self.layout) do
    local bytes = {}
    for i = 1, entry.size do
      bytes[i] = payload[pos]
      pos = pos + 1
    end
    self.memory:writeBlock(entry.space, entry.address, bytes, entry.bank or 0)
  end
  assert(pos == #payload + 1, "DuelDataToSave restore did not consume payload")
end

-- SaveDuelDataToDE checksum generation.  The source deliberately excludes the
-- final six bytes of the 826-byte payload from this checksum.
function SaveData:_checksumForPayload(payload)
  local seed = self.c.SAVE_DUEL_CHECKSUM_SEED
  local e = seed % 0x100
  local d = math.floor(seed / 0x100) % 0x100
  local count = self.c.SAVE_DUEL_DATA_SIZE - 6
  for i = 1, count do
    local value = payload[i]
    e = (e - value) % 0x100
    d = bit.band(bit.bxor(value, d), 0xff)
  end
  return e, d
end

-- SaveDuelDataToDE:: `bank` is explicit because the same CPU address is used
-- for sCurrentDuel in SRAM0 and sBackupCurrentDuel in SRAM2.
function SaveData:saveDuelDataTo(bank, address)
  local payload = self:_payloadFromMemory()
  local payloadAddress = address + self.c.SAVE_DUEL_HEADER_SIZE
  self.memory:writeBlock("sram", payloadAddress, payload, bank)

  local low, high = self:_checksumForPayload(payload)
  self.memory:write8("sram", address + self.c.SAVE_DUEL_HEADER_VALID_FLAG, self.c.TRUE, bank)
  self.memory:write8("sram", address + self.c.SAVE_DUEL_HEADER_CHECKSUM, low, bank)
  self.memory:write8("sram", address + self.c.SAVE_DUEL_HEADER_CHECKSUM + 1, high, bank)
  self.memory:write8("sram", address + self.c.SAVE_DUEL_HEADER_DUEL_TYPE,
    self.memory:readSymbol8("wDuelType"), bank)
  return low, high
end

-- SaveDuelData::
function SaveData:saveDuelData()
  local bank, address = self:_symbolLocation("sCurrentDuel")
  return self:saveDuelDataTo(bank, address)
end

-- ValidateSavedDuelDataFromHL:: state/result semantics. Returns carry as bool.
function SaveData:validateSavedDuelData(bank, address)
  local valid = self.memory:read8("sram",
    address + self.c.SAVE_DUEL_HEADER_VALID_FLAG, bank)
  if valid == 0 then return true end

  local storedLow = self.memory:read8("sram",
    address + self.c.SAVE_DUEL_HEADER_CHECKSUM, bank)
  local storedHigh = self.memory:read8("sram",
    address + self.c.SAVE_DUEL_HEADER_CHECKSUM + 1, bank)
  local payload = self.memory:readBlock("sram",
    address + self.c.SAVE_DUEL_HEADER_SIZE, self.c.SAVE_DUEL_DATA_SIZE, bank)

  -- Preserve the validator's arithmetic rather than simply comparing a newly
  -- generated checksum: e = storedLow - seedLow, d = storedHigh xor seedHigh,
  -- then fold the same source byte range back toward zero.
  local seed = self.c.SAVE_DUEL_CHECKSUM_SEED
  local e = (storedLow - (seed % 0x100)) % 0x100
  local d = bit.band(bit.bxor(storedHigh, math.floor(seed / 0x100) % 0x100), 0xff)
  for i = 1, self.c.SAVE_DUEL_DATA_SIZE - 6 do
    local value = payload[i]
    e = (e + value) % 0x100
    d = bit.band(bit.bxor(value, d), 0xff)
  end
  return e ~= 0 or d ~= 0
end

-- LoadSavedDuelDataFromDE:: assumes validity, exactly like the source routine.
function SaveData:loadSavedDuelDataFrom(bank, address)
  local payload = self.memory:readBlock("sram",
    address + self.c.SAVE_DUEL_HEADER_SIZE, self.c.SAVE_DUEL_DATA_SIZE, bank)
  self:_restorePayload(payload)
end

function SaveData:saveBackupCurrentDuel()
  local bank, address = self:_symbolLocation("sBackupCurrentDuel")
  return self:saveDuelDataTo(bank, address)
end

function SaveData:loadBackupCurrentDuel()
  local bank, address = self:_symbolLocation("sBackupCurrentDuel")
  self:loadSavedDuelDataFrom(bank, address)
end

-- SaveDuelStateToSRAM::
function SaveData:saveDuelStateToSRAM()
  -- BANK(sBackupCurrentDuel); SaveDuelData.  sBackupCurrentDuel and
  -- sCurrentDuel intentionally share CPU address $bc00 in different SRAM banks.
  self:saveBackupCurrentDuel()

  local ring = self.memory:readSymbol8("s0a008")
  self.memory:writeSymbol8("s0a008", ring + 1)
  local slot = bit.band(ring, 0x03)
  local bufferName = "sDuelBuffer" .. tostring(slot)
  local bufferBank, bufferAddress = self:_symbolLocation(bufferName)

  -- Save wDuelTurns, non-turn arena card ID, turn arena card ID at +0..+2.
  local turnDeckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local turnCardId = self.cardData:getCardIDFromDeckIndex(turnDeckIndex)
  self.memory:writeSymbol8("wTempTurnDuelistCardID", turnCardId)
  self.duelVars:swapTurn()
  local nonTurnDeckIndex = self.duelVars:get(self.c.DUELVARS_ARENA_CARD)
  local nonTurnCardId = self.cardData:getCardIDFromDeckIndex(nonTurnDeckIndex)
  self.memory:writeSymbol8("wTempNonTurnDuelistCardID", nonTurnCardId)
  self.duelVars:swapTurn()

  self.memory:write8("sram", bufferAddress + 0, self.memory:readSymbol8("wDuelTurns"), bufferBank)
  self.memory:write8("sram", bufferAddress + 1, nonTurnCardId, bufferBank)
  self.memory:write8("sram", bufferAddress + 2, turnCardId, bufferBank)

  self:saveDuelDataTo(bufferBank, bufferAddress + SNAPSHOT_DATA_OFFSET)
  return slot
end

return SaveData
