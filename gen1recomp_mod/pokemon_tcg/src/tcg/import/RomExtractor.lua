-- Pokemon TCG cartridge extractor for Gen1Recomp.
--
-- ROM addresses come exclusively from the manifest generated from
-- pret/poketcg + its RGBDS .sym output. Every pointer table read below is
-- cross-checked against the source label the decomp says occupies that slot.

local Rom = require("src.import.Rom")
local ImageWriter = require("src.import.ImageWriter")
local TextCodec = require("mods.pokemon_tcg.src.tcg.import.TextCodec")

local RomExtractor = {}
RomExtractor.__index = RomExtractor

local EXPECTED_SHA1 = "0f8670a583255cff3e5b7ca71b5d7454d928fc48"
local EXPECTED_SIZE = 64 * 0x4000 -- src/layout.link reaches ROMX $3f
local STAGES = 8

local function u8(raw, offset)
  local value = raw[offset + 1]
  assert(value ~= nil, ("read past structure at +$%02x"):format(offset))
  return value
end

local function u16(raw, offset)
  return u8(raw, offset) + u8(raw, offset + 1) * 0x100
end

local function copyBytes(data, first, length)
  local out = {}
  for i = 0, length - 1 do
    local value = data:byte(first + i + 1)
    assert(value, ("ROM read past end at file offset $%x"):format(first + i))
    out[#out + 1] = value
  end
  return out
end

function RomExtractor.new(romData, manifest, progress)
  assert(type(romData) == "string", "TCG ROM data must be a string")
  assert(#romData == EXPECTED_SIZE,
    ("TCG ROM must be %d bytes, got %d"):format(EXPECTED_SIZE, #romData))
  assert(type(manifest) == "table", "TCG ROM manifest is required")
  assert(manifest.schema == 5, "unsupported TCG manifest schema")
  assert(manifest.romSha1 == EXPECTED_SHA1,
    "TCG manifest does not describe the supported ROM")
  assert(type(manifest.symbols) == "table", "TCG manifest has no symbol map")
  assert(type(manifest.constants) == "table", "TCG manifest has no constants")
  assert(type(manifest.memory) == "table" and type(manifest.memory.symbols) == "table",
    "TCG manifest has no memory symbol map")

  return setmetatable({
    rom = Rom.new(romData),
    romData = romData,
    manifest = manifest,
    symbols = manifest.symbols,
    constants = manifest.constants,
    progress = progress,
    stage = 0,
  }, RomExtractor)
end

function RomExtractor:symbol(name)
  local loc = self.symbols[name]
  assert(loc, "required poketcg symbol is missing: " .. tostring(name))
  assert(type(loc) == "table" and type(loc[1]) == "number"
    and type(loc[2]) == "number", "invalid symbol record: " .. tostring(name))
  return { bank = loc[1], address = loc[2], name = name }
end

function RomExtractor:symbolOffset(name)
  local s = self:symbol(name)
  return Rom.offset(s.bank, s.address)
end

function RomExtractor:locationForOffset(offset)
  assert(offset >= 0 and offset < #self.romData, "ROM file offset out of range")
  if offset < 0x4000 then return 0, offset end
  local bank = math.floor(offset / 0x4000)
  local address = 0x4000 + (offset % 0x4000)
  return bank, address
end

function RomExtractor:byteAt(offset)
  local value = self.romData:byte(offset + 1)
  assert(value, ("ROM read past end at file offset $%x"):format(offset))
  return value
end

function RomExtractor:wordAt(offset)
  return self:byteAt(offset) + self:byteAt(offset + 1) * 0x100
end

function RomExtractor:triAt(offset)
  return self:wordAt(offset) + self:byteAt(offset + 2) * 0x10000
end

-- No-ops in the pokemon_tcg mod: extraction results are consumed
-- directly from each extract*() method's return value and never
-- persisted to the shared ROM-derived cache -- the ROM is read, used
-- to build this turn's duel state, and never written back out.
function RomExtractor:write(name, value) end

function RomExtractor:save(image, relative) end

function RomExtractor:beginStage(name)
  self.stage = self.stage + 1
  if self.progress then self.progress(self.stage - 1, STAGES, name, 0, 1) end
end

function RomExtractor:tick(name, current, total)
  if self.progress then
    self.progress(self.stage - 1 + current / total, STAGES, name, current, total)
  end
end

function RomExtractor:validateAnchorSymbols()
  for _, name in ipairs({
    "CardPointers", "CardGraphics", "DeckPointers", "DeckAIPointerTable",
    "TextOffsets", "GameLoop", "EffectCommands",
    "wPlayerDuelVariables", "wOpponentDuelVariables", "wPlayerDeck",
    "wOpponentDeck", "wDuelTempList", "wRNG1", "wRNG2", "wRNGCounter",
    "hWhoseTurn", "wLoadedCard1", "wLoadedCard2", "wDeckName",
    "ConvertSpecialTrainerCardToPokemon.trainer_to_pkmn_data",
    "PrizeBitmasks", "TakeAPrizes", "DuelDataToSave",
    "HandleBetweenTurnKnockOuts.Data_6ed2",
    "HandleBetweenTurnKnockOuts.ClearDamageReductionSubstatus2OfKnockedOutPokemon",
  }) do
    self:symbol(name)
  end
end

function RomExtractor:extractMemory()
  self:beginStage("TCG memory map")
  local memory = assert(self.manifest.memory, "TCG memory manifest missing")
  local out = {
    schema = 1,
    symbols = assert(memory.symbols),
    sourceFiles = assert(memory.sourceFiles),
  }
  self:write("tcg_memory", out)
  local count = 0
  for _, space in pairs(out.symbols) do
    for _ in pairs(space) do count = count + 1 end
  end
  self:tick("TCG memory map", 1, 1)
  return out, count
end


function RomExtractor:extractCoreData()
  self:beginStage("TCG core data")
  local c = self.constants
  local template = self:symbol("ConvertSpecialTrainerCardToPokemon.trainer_to_pkmn_data")
  local length = assert(c.CARD_DATA_AI_INFO) - assert(c.CARD_DATA_HP)
  local raw = self.rom:bytes(template.bank, template.address, length)

  -- PrizeBitmasks is a source table immediately preceding TakeAPrizes.  Derive
  -- its byte length from RGBDS symbols rather than reproducing the table size.
  local prize = self:symbol("PrizeBitmasks")
  local afterPrize = self:symbol("TakeAPrizes")
  assert(prize.bank == afterPrize.bank and afterPrize.address >= prize.address,
    "PrizeBitmasks/TakeAPrizes symbol layout changed")
  local prizeLength = afterPrize.address - prize.address
  local prizeBitmasks = self.rom:bytes(prize.bank, prize.address, prizeLength)

  -- DuelDataToSave is the ROM table that drives SaveDuelDataToDE and
  -- LoadSavedDuelDataFromDE.  Preserve the CPU addresses and byte counts
  -- exactly; do not replace this with a Lua-native snapshot layout.
  local saveTable = self:symbol("DuelDataToSave")
  local saveOffset = Rom.offset(saveTable.bank, saveTable.address)
  local duelDataToSave = {}
  local totalSaveBytes = 0
  local saveTableTerminated = false
  for _ = 1, 32 do
    local address = self:wordAt(saveOffset)
    saveOffset = saveOffset + 2
    if address == 0 then
      saveTableTerminated = true
      break
    end
    local size = self:wordAt(saveOffset)
    saveOffset = saveOffset + 2
    local space
    if address >= 0xc000 and address <= 0xdfff then
      space = "wram"
    elseif address >= 0xff80 and address <= 0xfffe then
      space = "hram"
    else
      error(("DuelDataToSave contains unsupported CPU address $%04x"):format(address))
    end
    duelDataToSave[#duelDataToSave + 1] = {
      space = space, address = address, size = size, bank = 0,
    }
    totalSaveBytes = totalSaveBytes + size
  end
  assert(saveTableTerminated, "DuelDataToSave did not terminate within 32 entries")
  assert(#duelDataToSave > 0, "DuelDataToSave was empty")
  assert(totalSaveBytes == assert(c.SAVE_DUEL_DATA_SIZE),
    ("DuelDataToSave totals %d bytes, source constant says %d")
      :format(totalSaveBytes, c.SAVE_DUEL_DATA_SIZE))

  -- Result lookup used by HandleBetweenTurnKnockOuts. Derive its length from
  -- the next RGBDS local symbol so the Lua port does not duplicate the table.
  local finishTable = self:symbol("HandleBetweenTurnKnockOuts.Data_6ed2")
  local finishTableEnd = self:symbol(
    "HandleBetweenTurnKnockOuts.ClearDamageReductionSubstatus2OfKnockedOutPokemon")
  assert(finishTable.bank == finishTableEnd.bank
      and finishTableEnd.address >= finishTable.address,
    "HandleBetweenTurnKnockOuts result-table symbol layout changed")
  local duelFinishTable = self.rom:bytes(
    finishTable.bank, finishTable.address, finishTableEnd.address - finishTable.address)

  local out = {
    schema = 3,
    specialTrainerTemplate = raw,
    specialTrainerTemplateLength = length,
    prizeBitmasks = prizeBitmasks,
    duelDataToSave = duelDataToSave,
    duelDataToSaveBytes = totalSaveBytes,
    duelFinishTable = duelFinishTable,
  }
  self:write("tcg_core", out)
  self:tick("TCG core data", 1, 1)
  return out
end

function RomExtractor:extractConstants()
  self:beginStage("TCG constants")
  self:write("tcg_constants", self.constants)
  self:tick("TCG constants", 1, 1)
end

function RomExtractor:extractEffects()
  self:beginStage("TCG effect commands")
  local spec = assert(self.manifest.effects, "TCG effect-command manifest missing")
  local lists = assert(spec.lists, "TCG effect-command lists missing")
  local base = self:symbol("EffectCommands")
  local out = {
    schema = 1,
    commandBank = base.bank,
    byAddress = {},
    byLabel = {},
    count = #lists,
  }
  local functionBanks = {}

  for index, source in ipairs(lists) do
    local label = assert(source.label)
    local loc = self:symbol(label)
    assert(loc.bank == base.bank,
      label .. " is not in the EffectCommands bank; 16-bit pointer semantics changed")
    local offset = Rom.offset(loc.bank, loc.address)
    local row = { sourceLabel = label, address = loc.address, commands = {} }

    for _, sourceCommand in ipairs(assert(source.commands)) do
      local typeName = assert(sourceCommand.type)
      local typeId = assert(self.constants[typeName], "unknown effect command type " .. typeName)
      local functionLabel = assert(sourceCommand["function"])
      local fn = self:symbol(functionLabel)
      local romType = self:byteAt(offset)
      local romFunction = self:wordAt(offset + 1)
      assert(romType == typeId,
        ("%s command type is $%02x in ROM, source %s is $%02x")
          :format(label, romType, typeName, typeId))
      assert(romFunction == fn.address,
        ("%s function pointer is $%04x in ROM, %s is $%04x")
          :format(label, romFunction, functionLabel, fn.address))
      functionBanks[fn.bank] = true
      row.commands[#row.commands + 1] = {
        type = typeId,
        typeName = typeName,
        functionLabel = functionLabel,
        functionAddress = fn.address,
        functionBank = fn.bank,
      }
      offset = offset + 3
    end
    assert(self:byteAt(offset) == 0,
      label .. " effect-command list is not zero terminated")
    assert(out.byAddress[loc.address] == nil,
      ("duplicate effect-command address $%04x"):format(loc.address))
    out.byAddress[loc.address] = row
    out.byLabel[label] = loc.address
    self:tick("TCG effect commands", index, #lists)
  end

  local bankCount, onlyBank = 0, nil
  for bank in pairs(functionBanks) do bankCount, onlyBank = bankCount + 1, bank end
  if bankCount == 1 then out.functionBank = onlyBank end
  self:write("tcg_effects", out)
  return out
end

function RomExtractor:extractText()
  self:beginStage("TCG text")
  local spec = assert(self.manifest.text, "TCG text manifest missing")
  local names = assert(spec.pointerNames, "TCG text pointer names missing")
  local base = self:symbol("TextOffsets")
  local baseOffset = Rom.offset(base.bank, base.address)

  -- ID 0 is the null text ID: text_offsets.asm emits dwb $0000, $00.
  assert(self:triAt(baseOffset) == 0, "TextOffsets ID 0 is no longer null")

  local codecSpec = {
    constants = self.constants,
    charmap = assert(spec.charmap, "TCG charmap missing"),
  }
  local out = { byId = {}, byLabel = {}, count = #names }
  out.byId[0] = { id = 0, label = "NONE", raw = { 0 }, plain = "" }

  for id, label in ipairs(names) do
    local delta = self:triAt(baseOffset + id * 3)
    local targetOffset = baseOffset + delta
    local expectedOffset = self:symbolOffset(label)
    assert(targetOffset == expectedOffset,
      ("TextOffsets[%d] points to $%x, decomp symbol %s is $%x")
        :format(id, targetOffset, label, expectedOffset))

    local raw = {}
    for n = 0, 0xffff do
      local value = self:byteAt(targetOffset + n)
      raw[#raw + 1] = value
      if value == self.constants.TX_END then break end
      if n == 0xffff then error("unterminated TCG text: " .. label) end
    end
    local bank, address = self:locationForOffset(targetOffset)
    out.byId[id] = {
      id = id,
      label = label,
      bank = bank,
      address = address,
      raw = raw,
      plain = TextCodec.decode(raw, codecSpec),
    }
    out.byLabel[label] = id
    self:tick("TCG text", id, #names)
  end
  self:write("tcg_text", out)
  return out
end

local function textValue(text, id)
  if not id or id == 0 then return nil end
  local row = text.byId[id]
  assert(row, ("unknown TCG text id $%04x"):format(id))
  return row.plain
end

function RomExtractor:extractCardGraphic(id, cardLabel, gfxLabel, gfxIndex)
  local gfxSpec = assert(self.manifest.cards.graphics[gfxLabel],
    "missing card gfx metadata: " .. tostring(gfxLabel))
  local baseOffset = self:symbolOffset("CardGraphics")
  local gfxOffset = baseOffset + gfxIndex * 8 -- macros/data.asm: gfx
  local expectedOffset = self:symbolOffset(gfxLabel)
  assert(gfxOffset == expectedOffset,
    ("%s gfx index $%04x resolves to $%x, %s is $%x")
      :format(cardLabel, gfxIndex, gfxOffset, gfxLabel, expectedOffset))

  local rawLength = assert(gfxSpec.twoBppBytes)
  local raw = copyBytes(self.romData, gfxOffset, rawLength)
  if gfxSpec.columns then
    assert(gfxSpec.width % 8 == 0 and gfxSpec.height % 8 == 0,
      "card gfx dimensions must be tile-aligned")
    raw = ImageWriter.columnsToRows(raw, gfxSpec.width / 8, gfxSpec.height / 8)
  end
  local paletteLength = assert(self.constants.PAL_SIZE, "PAL_SIZE missing from decomp constants")
  local palette = copyBytes(self.romData, gfxOffset + rawLength, paletteLength)
  local image = ImageWriter.decode2bpp(raw, gfxSpec.width, gfxSpec.height)
  -- Not persisted to the shared ROM-derived cache: the pokemon_tcg mod
  -- keeps the decoded image in memory for this session only.
  return {
    sourceLabel = gfxLabel,
    image = image,
    width = gfxSpec.width,
    height = gfxSpec.height,
    index = gfxIndex,
    palette = palette,
  }
end

function RomExtractor:decodeEnergyCost(raw, offset)
  local result = {}
  local numTypes = assert(self.constants.NUM_TYPES)
  local byteCount = numTypes / 2
  assert(byteCount == math.floor(byteCount), "NUM_TYPES must be even for energy encoding")
  for typeId = 0, numTypes - 1 do
    local packed = u8(raw, offset + math.floor(typeId / 2))
    local amount = typeId % 2 == 0 and math.floor(packed / 16) or packed % 16
    result[typeId] = amount
  end
  return result
end

function RomExtractor:decodeAttack(raw, offset, text)
  local c = self.constants
  local descriptionOffset = c.CARD_DATA_ATTACK1_DESCRIPTION - c.CARD_DATA_ATTACK1
  local nameOffset = c.CARD_DATA_ATTACK1_NAME - c.CARD_DATA_ATTACK1
  local damageOffset = c.CARD_DATA_ATTACK1_DAMAGE - c.CARD_DATA_ATTACK1
  local categoryOffset = c.CARD_DATA_ATTACK1_CATEGORY - c.CARD_DATA_ATTACK1
  local effectOffset = c.CARD_DATA_ATTACK1_EFFECT_COMMANDS - c.CARD_DATA_ATTACK1
  local flag1Offset = c.CARD_DATA_ATTACK1_FLAG1 - c.CARD_DATA_ATTACK1
  local flag2Offset = c.CARD_DATA_ATTACK1_FLAG2 - c.CARD_DATA_ATTACK1
  local flag3Offset = c.CARD_DATA_ATTACK1_FLAG3 - c.CARD_DATA_ATTACK1
  local paramOffset = c.CARD_DATA_ATTACK1_EFFECT_PARAM - c.CARD_DATA_ATTACK1
  local animOffset = c.CARD_DATA_ATTACK1_ANIMATION - c.CARD_DATA_ATTACK1
  local nameId = u16(raw, offset + nameOffset)
  local descId = u16(raw, offset + descriptionOffset)
  local descContId = u16(raw, offset + descriptionOffset + 2)
  return {
    energy = self:decodeEnergyCost(raw, offset),
    nameTextId = nameId,
    name = textValue(text, nameId),
    descriptionTextId = descId,
    description = textValue(text, descId),
    descriptionContTextId = descContId,
    descriptionCont = textValue(text, descContId),
    damage = u8(raw, offset + damageOffset),
    category = u8(raw, offset + categoryOffset),
    effectCommands = u16(raw, offset + effectOffset),
    flags = {
      u8(raw, offset + flag1Offset),
      u8(raw, offset + flag2Offset),
      u8(raw, offset + flag3Offset),
    },
    effectParam = u8(raw, offset + paramOffset),
    animation = u8(raw, offset + animOffset),
  }
end

function RomExtractor:extractCards(text)
  self:beginStage("TCG cards")
  local spec = assert(self.manifest.cards, "TCG card manifest missing")
  local labels = assert(spec.pointerLabels)
  local ids = assert(spec.ids)
  local c = self.constants
  local count = assert(c.NUM_CARDS)
  assert(#ids == count, "card ID list/count mismatch")
  assert(#labels == count + 2 and labels[1] == "NULL" and labels[#labels] == "NULL",
    "CardPointers source layout mismatch")

  local base = self:symbol("CardPointers")
  local baseOffset = Rom.offset(base.bank, base.address)
  assert(self:wordAt(baseOffset) == 0, "CardPointers first sentinel is not NULL")
  assert(self:wordAt(baseOffset + (count + 1) * 2) == 0,
    "CardPointers final sentinel is not NULL")

  local out = { byId = {}, byConstant = {}, count = count }
  for id = 1, count do
    local cardLabel = labels[id + 1]
    local expected = self:symbol(cardLabel)
    assert(expected.bank == base.bank,
      cardLabel .. " is not in CardPointers bank; 16-bit pointer semantics changed")
    local pointer = self:wordAt(baseOffset + id * 2)
    assert(pointer == expected.address,
      ("CardPointers[%d] is $%04x, %s is $%04x")
        :format(id, pointer, cardLabel, expected.address))

    local cardOffset = Rom.offset(base.bank, pointer)
    local cardType = self:byteAt(cardOffset)
    local kind, length
    if cardType < c.TYPE_ENERGY then
      kind, length = "pokemon", assert(c.PKMN_CARD_DATA_LENGTH)
    elseif cardType < c.TYPE_TRAINER then
      kind, length = "energy", assert(c.ENERGY_CARD_DATA_LENGTH)
    else
      kind, length = "trainer", assert(c.TRN_CARD_DATA_LENGTH)
    end
    local raw = copyBytes(self.romData, cardOffset, length)
    -- home/card_data.asm LoadCardDataToHL_FromCardID always copies
    -- PKMN_CARD_DATA_LENGTH bytes, even for 14-byte Energy/Trainer records.
    -- Preserve those exact bytes for the translated buffer-copy routines.
    local bufferRaw = copyBytes(self.romData, cardOffset, assert(c.PKMN_CARD_DATA_LENGTH))
    local storedId = u8(raw, c.CARD_DATA_ID)
    assert(storedId == id,
      ("%s stores card id $%02x, expected $%02x"):format(cardLabel, storedId, id))

    local nameId = u16(raw, c.CARD_DATA_NAME)
    local gfxIndex = u16(raw, c.CARD_DATA_GFX)
    local gfxLabel = assert(spec.recordGraphics[cardLabel],
      "missing source gfx relationship for " .. cardLabel)
    local row = {
      id = id,
      constant = ids[id],
      sourceLabel = cardLabel,
      type = cardType,
      kind = kind,
      gfx = self:extractCardGraphic(id, cardLabel, gfxLabel, gfxIndex),
      nameTextId = nameId,
      name = textValue(text, nameId),
      rarity = u8(raw, c.CARD_DATA_RARITY),
      set = u8(raw, c.CARD_DATA_SET),
      raw = raw,
      bufferRaw = bufferRaw,
    }

    if kind == "pokemon" then
      local preId = u16(raw, c.CARD_DATA_PREEVO_NAME)
      local categoryId = u16(raw, c.CARD_DATA_CATEGORY)
      local descriptionId = u16(raw, c.CARD_DATA_PKMN_DESCRIPTION)
      row.hp = u8(raw, c.CARD_DATA_HP)
      row.stage = u8(raw, c.CARD_DATA_STAGE)
      row.preEvolutionTextId = preId
      row.preEvolution = textValue(text, preId)
      row.attacks = {
        self:decodeAttack(raw, c.CARD_DATA_ATTACK1, text),
        self:decodeAttack(raw, c.CARD_DATA_ATTACK2, text),
      }
      row.retreatCost = u8(raw, c.CARD_DATA_RETREAT_COST)
      row.weakness = u8(raw, c.CARD_DATA_WEAKNESS)
      row.resistance = u8(raw, c.CARD_DATA_RESISTANCE)
      row.categoryTextId = categoryId
      row.category = textValue(text, categoryId)
      row.pokedexNumber = u8(raw, c.CARD_DATA_POKEDEX_NUMBER)
      row.level = u8(raw, c.CARD_DATA_LEVEL)
      row.length = { u8(raw, c.CARD_DATA_LENGTH), u8(raw, c.CARD_DATA_LENGTH + 1) }
      row.weight = u16(raw, c.CARD_DATA_WEIGHT)
      row.descriptionTextId = descriptionId
      row.description = textValue(text, descriptionId)
      row.aiInfo = u8(raw, c.CARD_DATA_AI_INFO)
    else
      local descriptionId = u16(raw, c.CARD_DATA_NONPKMN_DESCRIPTION)
      local descriptionContId = u16(raw, c.CARD_DATA_ATTACK1)
      row.effectCommands = u16(raw, c.CARD_DATA_EFFECT_COMMANDS)
      row.descriptionTextId = descriptionId
      row.description = textValue(text, descriptionId)
      row.descriptionContTextId = descriptionContId
      row.descriptionCont = textValue(text, descriptionContId)
    end

    out.byId[id] = row
    out.byConstant[ids[id]] = id
    self:tick("TCG cards", id, count)
  end
  self:write("tcg_cards", out)
  return out
end

function RomExtractor:extractDecks(cards)
  self:beginStage("TCG decks")
  local spec = assert(self.manifest.decks, "TCG deck manifest missing")
  local ids, labels = assert(spec.ids), assert(spec.pointerLabels)
  local count = assert(self.constants.NUM_VALID_DECKS)
  local deckSize = assert(self.constants.DECK_SIZE)
  assert(#ids == count, "deck ID list/count mismatch")
  assert(#labels == count + 1 and labels[#labels] == "NULL",
    "DeckPointers source layout mismatch")

  local base = self:symbol("DeckPointers")
  local baseOffset = Rom.offset(base.bank, base.address)
  assert(self:wordAt(baseOffset + count * 2) == 0,
    "DeckPointers final sentinel is not NULL")

  local aiLabels = assert(spec.aiActionTables, "TCG deck AI table manifest missing")
  local aiCount = assert(self.constants.NUM_DECK_IDS)
  assert(#aiLabels == aiCount, "DeckAIPointerTable source count mismatch")
  local aiBase = self:symbol("DeckAIPointerTable")
  local aiBaseOffset = Rom.offset(aiBase.bank, aiBase.address)

  local aiListSpecs = assert(spec.aiListsByActionTable, "TCG deck AI list manifest missing")
  local out = {
    byId = {}, byConstant = {}, count = count, aiByOpponentDeckId = {},
    aiListsByOpponentDeckId = {},
  }

  local function validateAIList(row)
    local loc = self:symbol(row.label)
    local offset = Rom.offset(loc.bank, loc.address)
    local cardIds = {}
    if row.kind == "card_ids" then
      for i, entry in ipairs(row.entries) do
        assert(self:byteAt(offset) == entry.cardId,
          ("%s entry %d card ID mismatch"):format(row.label, i))
        cardIds[#cardIds + 1] = entry.cardId
        offset = offset + 1
      end
    elseif row.kind == "retreat_bonus" then
      for i, entry in ipairs(row.entries) do
        assert(self:byteAt(offset) == entry.cardId,
          ("%s entry %d card ID mismatch"):format(row.label, i))
        assert(self:byteAt(offset + 1) == entry.scoreByte,
          ("%s entry %d retreat score mismatch"):format(row.label, i))
        offset = offset + 2
      end
    elseif row.kind == "energy_bonus" then
      for i, entry in ipairs(row.entries) do
        assert(self:byteAt(offset) == entry.cardId,
          ("%s entry %d card ID mismatch"):format(row.label, i))
        assert(self:byteAt(offset + 1) == entry.maxEnergy,
          ("%s entry %d max-energy mismatch"):format(row.label, i))
        assert(self:byteAt(offset + 2) == entry.scoreByte,
          ("%s entry %d energy score mismatch"):format(row.label, i))
        offset = offset + 3
      end
    else
      error("unsupported deck AI list kind: " .. tostring(row.kind))
    end
    assert(self:byteAt(offset) == 0, "deck AI list terminator mismatch: " .. row.label)
    return {
      sourceLabel = row.label,
      kind = row.kind,
      entries = row.entries,
      cardIds = cardIds,
    }
  end

  for opponentDeckId = 0, aiCount - 1 do
    local actionTableLabel = aiLabels[opponentDeckId + 1]
    local expected = self:symbol(actionTableLabel)
    assert(expected.bank == aiBase.bank,
      actionTableLabel .. " is not in DeckAIPointerTable bank")
    local pointer = self:wordAt(aiBaseOffset + opponentDeckId * 2)
    assert(pointer == expected.address,
      ("DeckAIPointerTable[%d] is $%04x, %s is $%04x")
        :format(opponentDeckId, pointer, actionTableLabel, expected.address))
    out.aiByOpponentDeckId[opponentDeckId] = actionTableLabel

    local sourceLists = aiListSpecs[actionTableLabel] or {}
    local runtimeLists = {}
    for name, row in pairs(sourceLists) do runtimeLists[name] = validateAIList(row) end
    out.aiListsByOpponentDeckId[opponentDeckId] = runtimeLists
  end

  for deckId = 0, count - 1 do
    local sourceLabel = labels[deckId + 1]
    local expected = self:symbol(sourceLabel)
    assert(expected.bank == base.bank,
      sourceLabel .. " is not in DeckPointers bank; 16-bit pointer semantics changed")
    local pointer = self:wordAt(baseOffset + deckId * 2)
    assert(pointer == expected.address,
      ("DeckPointers[%d] is $%04x, %s is $%04x")
        :format(deckId, pointer, sourceLabel, expected.address))

    local sourceList = assert(spec.sourceLists and spec.sourceLists[sourceLabel],
      "missing decomp deck list for " .. sourceLabel)
    local offset = Rom.offset(base.bank, pointer)
    local entries, expanded = {}, {}
    local total = 0
    -- The source list itself determines the number of quantity/id pairs.
    -- This preserves deliberately non-DECK_SIZE lists such as UnnamedDeck2.
    for sourceIndex, expectedEntry in ipairs(sourceList.entries) do
      local quantity = self:byteAt(offset)
      local cardId = self:byteAt(offset + 1)
      offset = offset + 2
      assert(quantity == expectedEntry.quantity and cardId == expectedEntry.cardId,
        ("%s entry %d ROM=(%d,$%02x) decomp=(%d,$%02x)")
          :format(sourceLabel, sourceIndex, quantity, cardId,
            expectedEntry.quantity, expectedEntry.cardId))
      assert(cardId >= 1 and cardId <= cards.count,
        ("%s contains invalid card id $%02x"):format(sourceLabel, cardId))
      entries[#entries + 1] = { quantity = quantity, cardId = cardId }
      total = total + quantity
      for _ = 1, quantity do expanded[#expanded + 1] = cardId end
    end
    assert(self:byteAt(offset) == 0, "deck list terminator mismatch: " .. sourceLabel)
    -- CopyDeckData reads the two bytes immediately following the zero
    -- terminator into wDeckName. Preserve them even for odd/unused lists.
    local nameWord = self:wordAt(offset + 1)
    assert(total == sourceList.total,
      ("%s ROM total %d differs from decomp source total %d")
        :format(sourceLabel, total, sourceList.total))

    local row = {
      id = deckId,
      constant = ids[deckId + 1],
      sourceLabel = sourceLabel,
      entries = entries,
      cards = expanded,
      total = total,
      deckSizeConformant = total == deckSize,
      macroEnded = sourceList.macroEnded == true,
      nameWord = nameWord,
    }
    out.byId[deckId] = row
    out.byConstant[row.constant] = deckId
    self:tick("TCG decks", deckId + 1, count)
  end
  self:write("tcg_decks", out)
  return out
end

function RomExtractor:extractMetadata(memoryCount, text, cards, decks, effects)
  self:beginStage("TCG metadata")
  local header = self.rom:bytes(0, 0x0100, 0x50)
  self:write("tcg_meta", {
    schema = 5,
    romSha1 = self.manifest.romSha1,
    decompCommit = self.manifest.decompCommit,
    romHeader = header,
    sourceFileCount = self.manifest.sourceFileCount,
    translationComplete = self.manifest.translationComplete == true,
    extracted = {
      memorySymbols = memoryCount,
      text = text.count,
      cards = cards.count,
      decks = decks.count,
      effectCommandLists = effects.count,
    },
  })
  self:tick("TCG metadata", 1, 1)
end

function RomExtractor:run()
  self:validateAnchorSymbols()
  local _, memoryCount = self:extractMemory()
  self:extractConstants()
  self:extractCoreData()
  local effects = self:extractEffects()
  local text = self:extractText()
  local cards = self:extractCards(text)
  local decks = self:extractDecks(cards)
  self:extractMetadata(memoryCount, text, cards, decks, effects)

  -- A player-ready cache is still gated on the complete translation ledger.
  -- Development can import this data slice explicitly while behavior is ported.
  if self.manifest.translationComplete ~= true
      and os.getenv("POKEPORT_TCG_ALLOW_PARTIAL") ~= "1" then
    error("Pokemon TCG translation is incomplete; refusing to create a "
      .. "player-ready cache. Set POKEPORT_TCG_ALLOW_PARTIAL=1 for development.")
  end
end

return RomExtractor
