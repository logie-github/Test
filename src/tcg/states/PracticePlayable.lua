-- Native LÖVE presentation for the translated Sam practice duel: real card
-- art (decoded + colorized from the imported ROM, see CardPalette.lua),
-- HP bars, and a bordered field/menu layout in the spirit of the cartridge
-- duel screen. It is a stylized approximation, not a byte-exact
-- recreation -- the actual GBC menu chrome, status-condition icons and
-- energy-attachment icons are not translated yet.

local CardPalette = require("src.tcg.states.CardPalette")

local PracticePlayable = {}
PracticePlayable.__index = PracticePlayable
PracticePlayable.isOpaque = true

local CANVAS_W, CANVAS_H = 160, 144
local LINE_H = 8

local COLOR_BG = { 0.94, 0.94, 0.82, 1 }
local COLOR_PANEL = { 0.98, 0.98, 0.90, 1 }
local COLOR_BORDER = { 0.05, 0.05, 0.05, 1 }
local COLOR_TEXT = { 0.05, 0.05, 0.05, 1 }
local COLOR_WHITE = { 1, 1, 1, 1 }
local COLOR_HP_GREEN = { 0.2, 0.7, 0.2, 1 }
local COLOR_HP_YELLOW = { 0.85, 0.72, 0.1, 1 }
local COLOR_HP_RED = { 0.8, 0.15, 0.15, 1 }
local COLOR_HP_TRACK = { 0.3, 0.3, 0.3, 1 }

-- TYPE_PKMN_* order from the decomp constants (FIRE..COLORLESS = 0..6).
local TYPE_COLORS = {
  [0] = { 0.85, 0.35, 0.15, 1 }, -- Fire
  [1] = { 0.25, 0.62, 0.25, 1 }, -- Grass
  [2] = { 0.85, 0.72, 0.15, 1 }, -- Lightning
  [3] = { 0.2, 0.45, 0.82, 1 },  -- Water
  [4] = { 0.6, 0.38, 0.18, 1 },  -- Fighting
  [5] = { 0.6, 0.25, 0.62, 1 },  -- Psychic
  [6] = { 0.58, 0.58, 0.55, 1 }, -- Colorless
}
local TYPE_COLOR_FALLBACK = { 0.5, 0.5, 0.5, 1 }

function PracticePlayable.new(game, session)
  return setmetatable({ game = assert(game), session = assert(session), cursor = 1 }, PracticePlayable)
end

function PracticePlayable:enter()
  self.font = love.graphics.newFont(6)
  self.imageCache = {}
end

function PracticePlayable:update(dt)
  local input = self.game.input
  local actions = self.session:availableActions()
  if #actions > 0 then
    if input:wasPressed("up") then self.cursor = math.max(1, self.cursor - 1) end
    if input:wasPressed("down") then self.cursor = math.min(#actions, self.cursor + 1) end
    if input:wasPressed("a") then
      local action = actions[self.cursor]
      if action then self.session:performAction(action) end
      local after = self.session:availableActions()
      self.cursor = math.min(self.cursor, math.max(1, #after))
    end
  end
  -- repeatTurn (rewind to the last saved backup) is a practice-duel-only
  -- mechanic tied to Practice.lua's save/restore path; DuelSession has no
  -- equivalent (there is no "undo" in a real duel), so guard the call
  -- instead of assuming every session implements it.
  if input:wasPressed("b") and self.session.repeatTurn then
    self.session:repeatTurn()
    self.cursor = 1
  end
end

-- Decodes a card's art once (colorizing it from its embedded GBC palette)
-- and caches the resulting drawable Image by card id. `gfx.image` is what
-- the mod's patched RomExtractor hands back (decoded in memory, never
-- cached to disk); `gfx.path` is the canonical dev-mode shape (Data.lua's
-- extracted-once-to-disk cache) -- either way the pixels are still the
-- plain grayscale decode2bpp produces, so both need the same recolor pass.
function PracticePlayable:cardImage(cardId)
  local cached = self.imageCache[cardId]
  if cached ~= nil then
    if cached == false then return nil end
    return cached
  end
  local row = self.session.data.cards.byId[cardId]
  local gfx = row and row.gfx
  local ok, imageData
  if gfx then
    if gfx.image then
      ok, imageData = true, gfx.image
    elseif gfx.path then
      ok, imageData = pcall(love.image.newImageData, gfx.path)
    end
  end
  if not ok or not imageData then
    self.imageCache[cardId] = false
    return nil
  end
  if gfx.palette then
    CardPalette.colorize(imageData, CardPalette.decode(gfx.palette))
  end
  local image = love.graphics.newImage(imageData)
  image:setFilter("nearest", "nearest")
  self.imageCache[cardId] = image
  return image
end

-- Draws a card's art (or a type-tinted placeholder box if art isn't
-- available) inside a bordered frame at (x, y) scaled from its native
-- 64x48-ish size. Returns the frame's pixel width/height.
function PracticePlayable:drawCardFrame(x, y, cardId, scale)
  local g = love.graphics
  local row = self.session.data.cards.byId[cardId]
  local gfx = row and row.gfx
  local w = math.floor((gfx and gfx.width or 64) * scale)
  local h = math.floor((gfx and gfx.height or 48) * scale)

  local typeColor = TYPE_COLORS[row and row.type] or TYPE_COLOR_FALLBACK
  g.setColor(typeColor)
  g.rectangle("fill", x, y, w, h)

  local image = self:cardImage(cardId)
  if image then
    g.setColor(COLOR_WHITE)
    g.draw(image, x, y, 0, w / image:getWidth(), h / image:getHeight())
  end

  g.setColor(COLOR_BORDER)
  g.rectangle("line", x, y, w, h)
  return w, h
end

local function hpColor(hp, maxHP)
  if not maxHP or maxHP <= 0 then return COLOR_HP_TRACK end
  local ratio = hp / maxHP
  if ratio > 0.5 then return COLOR_HP_GREEN end
  if ratio > 0.25 then return COLOR_HP_YELLOW end
  return COLOR_HP_RED
end

function PracticePlayable:drawHPBar(x, y, w, hp, maxHP)
  local g = love.graphics
  g.setColor(COLOR_HP_TRACK)
  g.rectangle("fill", x, y, w, 4)
  if maxHP and maxHP > 0 then
    local filled = math.max(0, math.min(w, math.floor(w * hp / maxHP)))
    g.setColor(hpColor(hp, maxHP))
    g.rectangle("fill", x, y, filled, 4)
  end
  g.setColor(COLOR_BORDER)
  g.rectangle("line", x, y, w, 4)
  g.setColor(COLOR_TEXT)
  g.print((hp or 0) .. "/" .. (maxHP or 0), x + w + 3, y - 2)
end

-- One side's active Pokemon (art + name + HP bar) plus its bench as small
-- art-only thumbnails in a row underneath.
function PracticePlayable:drawSideBlock(x, y, w, h, label, side)
  local g = love.graphics
  g.setColor(COLOR_PANEL)
  g.rectangle("fill", x, y, w, h)
  g.setColor(COLOR_BORDER)
  g.rectangle("line", x, y, w, h)
  g.setColor(COLOR_TEXT)
  g.print(("%s  Prizes:%d"):format(label, side.prizes or 0), x + 3, y + 2)

  local artH = 0
  if side.active then
    local artW
    artW, artH = self:drawCardFrame(x + 3, y + 11, side.active.cardId, 0.4)
    g.setColor(COLOR_TEXT)
    g.print(side.active.name, x + 8 + artW, y + 12)
    self:drawHPBar(x + 8 + artW, y + 21, math.max(10, w - artW - 32), side.active.hp, side.active.maxHP)
  else
    g.setColor(COLOR_TEXT)
    g.print("(no active Pokemon)", x + 3, y + 12)
  end

  local benchY = y + 11 + artH + 2
  for i, card in ipairs(side.bench) do
    if i > 6 then break end
    self:drawCardFrame(x + 3 + (i - 1) * 12, benchY, card.cardId, 0.15)
  end
end

function PracticePlayable:drawOverlay(x, y, w, h, turnNumber, handCount)
  local g = love.graphics
  g.setColor(COLOR_PANEL)
  g.rectangle("fill", x, y, w, h)
  g.setColor(COLOR_BORDER)
  g.rectangle("line", x, y, w, h)
  g.setColor(COLOR_TEXT)

  if self.session.phase == "won" or self.session.phase == "lost" then
    g.print(("Turn %d"):format(turnNumber), x + 3, y + 2)
    local label = self.session.phase == "won" and "PRACTICE DUEL COMPLETE - YOU WIN" or "DUEL LOST"
    g.printf(label, x + 3, y + 14, w - 6, "center")
    g.printf("The original result screen is not translated yet.", x + 6, y + 28, w - 12, "center")
    return
  end

  if self.session.phase ~= "player" then
    g.print(("Turn %d"):format(turnNumber), x + 3, y + 2)
    local label = self.session.opponentLabel or "OPPONENT"
    g.printf(label .. " is taking their turn...", x + 3, y + 28, w - 6, "center")
    return
  end

  local actions = self.session:availableActions()
  -- A DuelSession pending decision (initial active/bench pick, a prize
  -- card, a knockout replacement) reuses this same overlay/action-list
  -- rendering, but is not an ordinary turn -- phase reads "player" for
  -- the whole time one is outstanding (see DuelSession:_yieldAsPlayer),
  -- so without this the header claimed "Turn 1 - YOUR MOVE" while the
  -- player was still picking their opening Pokemon, with both sides
  -- showing "(no active Pokemon)" and nothing to explain why.
  local pending = self.session.pending
  local pendingHeaders = {
    setup_active = "CHOOSE YOUR ACTIVE POKEMON",
    setup_bench = "CHOOSE A BENCH POKEMON (or Done)",
    prize = "CHOOSE A PRIZE CARD",
    knockout = "CHOOSE A REPLACEMENT",
  }
  if pending and pendingHeaders[pending.kind] then
    g.print(pendingHeaders[pending.kind], x + 3, y + 2)
  else
    g.print(("Turn %d - YOUR MOVE (hand: %d)"):format(turnNumber, handCount), x + 3, y + 2)
  end
  local listTop = y + 11
  local maxRows = math.max(1, math.floor((h - 11 - LINE_H - 2) / LINE_H))
  -- Keep the cursor's row visible: scroll the window once it runs past
  -- what fits instead of just cutting the list off.
  local firstRow = 1
  if self.cursor > maxRows then firstRow = self.cursor - maxRows + 1 end
  local listY = listTop
  for i = firstRow, math.min(#actions, firstRow + maxRows - 1) do
    local action = actions[i]
    local prefix = i == self.cursor and "> " or "  "
    g.printf(prefix .. action.label, x + 3, listY, w - 6, "left")
    listY = listY + LINE_H
  end
  if firstRow > 1 or firstRow + maxRows - 1 < #actions then
    g.printf(("(%d/%d)"):format(self.cursor, #actions), x + w - 30, y + 2, 27, "right")
  end

  local message = self.session.message
  if not message then
    message = (self.session.instructionText or ""):gsub("\n+", " ")
  end
  if message ~= "" then
    g.printf(message, x + 3, y + h - LINE_H - 2, w - 6, "left")
  end
end

function PracticePlayable:draw()
  local g = love.graphics
  g.setFont(self.font)
  g.setColor(COLOR_BG)
  g.rectangle("fill", 0, 0, CANVAS_W, CANVAS_H)

  local c = self.session.data.constants
  local player = self.session:sideState(c.PLAYER_TURN)
  local opponent = self.session:sideState(c.OPPONENT_TURN)
  local turns = self.session.runtime.memory:readSymbol8("wDuelTurns")

  self:drawSideBlock(1, 1, CANVAS_W - 2, 44, self.session.opponentLabel or "OPPONENT", opponent)
  self:drawSideBlock(1, 46, CANVAS_W - 2, 44, "YOU", player)

  self:drawOverlay(1, 91, CANVAS_W - 2, CANVAS_H - 92, turns + 1, player.hand or 0)
end

return PracticePlayable
