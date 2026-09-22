-- Pokemon TCG text stream decoder.
-- Control values and glyph maps are generated from pret/poketcg's
-- constants/text_constants.asm and constants/charmaps.asm.

local TextCodec = {}

local function key(n) return tostring(n) end

local function append(out, value)
  out[#out + 1] = value
end

function TextCodec.decode(raw, spec)
  assert(type(raw) == "table", "text raw bytes required")
  assert(type(spec) == "table", "text manifest required")
  local constants = assert(spec.constants, "text control constants required")
  local maps = assert(spec.charmap, "text charmap required")
  local half = maps.halfwidth or {}
  local full = maps.fullwidth or {}

  local txEnd = assert(constants.TX_END)
  local txSymbol = assert(constants.TX_SYMBOL)
  local txHalf = assert(constants.TX_HALFWIDTH)
  local txHalf2Full = assert(constants.TX_HALF2FULL)
  local txRam1 = assert(constants.TX_RAM1)
  local txLine = assert(constants.TX_LINE)
  local txRam2 = assert(constants.TX_RAM2)
  local txRam3 = assert(constants.TX_RAM3)
  local txHiragana = assert(constants.TX_HIRAGANA)
  local txKatakana = assert(constants.TX_KATAKANA)
  local fullWidth = assert(constants.FULL_WIDTH)
  local halfWidth = assert(constants.HALF_WIDTH)

  local width = fullWidth
  local syllabary = txKatakana
  local out = {}
  local i = 1
  while i <= #raw do
    local b = raw[i]
    if b == txEnd then
      break
    elseif b == txHalf then
      width = halfWidth
    elseif b == txHalf2Full then
      width = fullWidth
      syllabary = txKatakana
    elseif b == txLine then
      append(out, "\n")
    elseif b == txRam1 then
      append(out, "<RAMNAME>")
    elseif b == txRam2 then
      append(out, "<RAMTEXT>")
    elseif b == txRam3 then
      append(out, "<RAMNUM>")
    elseif b == txHiragana then
      syllabary = txHiragana
    elseif b == txKatakana then
      syllabary = txKatakana
    elseif b == txSymbol then
      i = i + 1
      local symbol = raw[i]
      assert(symbol ~= nil, "truncated TX_SYMBOL sequence")
      append(out, ("<SYMBOL:%02X>"):format(symbol))
    elseif width == halfWidth then
      append(out, half[key(b)] or ("<BYTE:%02X>"):format(b))
    else
      local prefix = syllabary
      local code = b
      -- TX_FULLWIDTH1..4 are explicit two-byte charmap selectors. TX_FULLWIDTH0
      -- is zero and is reserved as TX_END in a text stream; its characters are
      -- encoded directly and looked up in the common map below.
      if b >= 1 and b <= 4 then
        prefix = b
        i = i + 1
        code = raw[i]
        assert(code ~= nil, "truncated full-width character")
      end
      local common = full[key(0)] or {}
      local selected = full[key(prefix)] or {}
      local glyph
      if prefix >= 1 and prefix <= 4 then
        -- Explicit TX_FULLWIDTH1..4 selects that bank for this character.
        glyph = selected[key(code)]
      elseif code >= 0x60 then
        -- text_constants.asm: hiragana/katakana share FULLWIDTH0 at >= $60.
        glyph = common[key(code)]
      else
        glyph = selected[key(code)]
      end
      append(out, glyph or ("<FW:%02X:%02X>"):format(prefix, code))
    end
    i = i + 1
  end
  return table.concat(out)
end

return TextCodec
