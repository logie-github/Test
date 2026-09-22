package.path = "./?.lua;" .. package.path

local checks, failures = 0, 0
local function check(label, cond)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print(("FAIL  %s"):format(label))
  end
end

-- Minimal love stub: just enough surface for PracticePlayable:draw() to run
-- for real (not a rendering test -- there is no display here -- but every
-- draw call, cache lookup, palette recolor and layout branch it takes runs
-- as real Lua, so a nil-index or wrong-argument bug still fails this).
local drawCalls = { rectangle = 0, print = 0, printf = 0, draw = 0, newImage = 0 }
love = {
  graphics = {
    newFont = function() return {} end,
    setFont = function() end,
    setColor = function() end,
    rectangle = function(mode, x, y, w, h)
      assert(mode == "fill" or mode == "line", "bad rectangle mode")
      assert(type(x) == "number" and type(y) == "number", "bad rectangle coords")
      drawCalls.rectangle = drawCalls.rectangle + 1
    end,
    print = function(text, x, y)
      assert(type(x) == "number" and type(y) == "number", "bad print coords")
      drawCalls.print = drawCalls.print + 1
    end,
    printf = function(text, x, y, w, align)
      assert(type(x) == "number" and type(y) == "number" and type(w) == "number", "bad printf args")
      drawCalls.printf = drawCalls.printf + 1
    end,
    draw = function(image, x, y, r, sx, sy)
      assert(image, "drew a nil image")
      assert(type(sx) == "number" and sx > 0 and type(sy) == "number" and sy > 0, "bad draw scale")
      drawCalls.draw = drawCalls.draw + 1
    end,
    newImage = function(imageData)
      drawCalls.newImage = drawCalls.newImage + 1
      return {
        getWidth = function() return imageData.w end,
        getHeight = function() return imageData.h end,
        setFilter = function() end,
      }
    end,
  },
  image = {
    newImageData = function() error("gfx.path branch not exercised by this fixture") end,
  },
}

local PracticePlayable = require("src.tcg.states.PracticePlayable")

-- Same fake ImageData shape as card_palette_smoke.lua: a flat pixel grid
-- CardPalette.colorize can getPixel/setPixel over.
local FakeImageData = {}
FakeImageData.__index = FakeImageData
function FakeImageData.new(w, h)
  local pixels = {}
  for i = 1, w * h do pixels[i] = { 1, 1, 1, 1 } end -- all shade 0 (lightest)
  return setmetatable({ pixels = pixels, w = w, h = h }, FakeImageData)
end
function FakeImageData:getDimensions() return self.w, self.h end
function FakeImageData:getPixel(x, y)
  local p = self.pixels[y * self.w + x + 1]
  return p[1], p[2], p[3], p[4]
end
function FakeImageData:setPixel(x, y, r, g, b, a)
  self.pixels[y * self.w + x + 1] = { r, g, b, a }
end

local function cardRow(id, name, hp, kind, typeId)
  return {
    id = id, name = name, hp = hp, kind = kind, type = typeId,
    gfx = {
      width = 64, height = 48,
      image = FakeImageData.new(64, 48),
      palette = { 0x1F, 0x00, 0xE0, 0x03, 0x00, 0x7C, 0xFF, 0x7F },
    },
  }
end

local cardsById = {
  [1] = cardRow(1, "Bulbasaur", 40, "pokemon", 1),
  [2] = cardRow(2, "Squirtle", 30, "pokemon", 3),
  [3] = cardRow(3, "Charmander", 20, "pokemon", 0),
}

local fakeSession = {
  phase = "player",
  message = nil,
  instructionText = "Attach an Energy card, or attack.",
  cursor = 1,
  data = {
    constants = { PLAYER_TURN = 0, OPPONENT_TURN = 1 },
    cards = { byId = cardsById },
  },
  runtime = {
    memory = { readSymbol8 = function() return 3 end },
  },
}

function fakeSession:sideState(highByte)
  if highByte == self.data.constants.PLAYER_TURN then
    return { active = { cardId = 1, name = "Bulbasaur", hp = 25, maxHP = 40 },
             bench = { { cardId = 2, name = "Squirtle", hp = 30, maxHP = 30 } },
             prizes = 5, hand = 4 }
  end
  return { active = { cardId = 3, name = "Charmander", hp = 5, maxHP = 20 },
           bench = {}, prizes = 6, hand = 3 }
end

local actionLabels = {
  "Attack: Vine Whip", "Attach Energy: Grass", "Retreat", "Use Potion", "Evolve",
}
function fakeSession:availableActions()
  local out = {}
  for i, label in ipairs(actionLabels) do out[i] = { key = i, label = label } end
  return out
end

local performActionCalls = 0
function fakeSession:performAction(action)
  performActionCalls = performActionCalls + 1
  return true
end

-- Deliberately does NOT define repeatTurn, the same shape DuelSession has
-- (no rewind-to-backup concept in a real duel) -- update()'s "b" handler
-- must guard against that instead of assuming every session implements it.

local fakeGame = { input = { wasPressed = function() return false end } }

local function freshView(cursor, phase)
  local view = PracticePlayable.new(fakeGame, fakeSession)
  view:enter()
  fakeSession.cursor = cursor
  fakeSession.phase = phase
  view.cursor = cursor
  return view
end

-- Player's turn, cursor within the visible window.
local ok, err = pcall(function()
  local view = freshView(1, "player")
  view:draw()
end)
check("player-turn draw does not error", ok)
if not ok then print("  error: " .. tostring(err)) end

check("drew at least one card image", drawCalls.draw >= 1)
check("cached decoded images (newImage called once per unique card)", drawCalls.newImage <= 3)

-- Scrolled cursor (forces the scroll-window branch in drawOverlay).
local scrollOk, scrollErr = pcall(function()
  local view = freshView(#actionLabels, "player")
  view:draw()
end)
check("scrolled action list draw does not error", scrollOk)
if not scrollOk then print("  error: " .. tostring(scrollErr)) end

-- AI turn (phase ~= "player" and not won/lost).
local aiOk, aiErr = pcall(function()
  local view = freshView(1, "opponent")
  view:draw()
end)
check("opponent-turn draw does not error", aiOk)
if not aiOk then print("  error: " .. tostring(aiErr)) end

-- Won / lost result screens.
local wonOk, wonErr = pcall(function()
  local view = freshView(1, "won")
  view:draw()
end)
check("won-phase draw does not error", wonOk)
if not wonOk then print("  error: " .. tostring(wonErr)) end

local lostOk, lostErr = pcall(function()
  local view = freshView(1, "lost")
  view:draw()
end)
check("lost-phase draw does not error", lostOk)
if not lostOk then print("  error: " .. tostring(lostErr)) end

-- No active/no bench (a side with a knocked-out-everything edge) must not crash.
local emptySession = setmetatable({}, { __index = fakeSession })
emptySession.phase = "player"
emptySession.cursor = 1
function emptySession:sideState() return { active = nil, bench = {}, prizes = 0, hand = 0 } end
function emptySession:availableActions() return {} end
local emptyOk, emptyErr = pcall(function()
  local view = PracticePlayable.new(fakeGame, emptySession)
  view:enter()
  view:draw()
end)
check("empty side (no active, no bench) draw does not error", emptyOk)
if not emptyOk then print("  error: " .. tostring(emptyErr)) end

-- update(): the actual input-handling path draw() never exercises. This
-- is exactly where the real repeatTurn() crash was: a session missing an
-- optional method, only reachable by pressing the button, not by drawing.
local function withPressed(button, fn)
  local previous = fakeGame.input.wasPressed
  fakeGame.input.wasPressed = function(_, b) return b == button end
  local ok, err = pcall(fn)
  fakeGame.input.wasPressed = previous
  return ok, err
end

local view = freshView(1, "player")
local aPressOk, aPressErr = withPressed("a", function() view:update(0) end)
check("pressing A calls session:performAction without error", aPressOk)
if not aPressOk then print("  error: " .. tostring(aPressErr)) end
check("pressing A actually invoked performAction", performActionCalls > 0)

local bPressOk, bPressErr = withPressed("b", function() view:update(0) end)
check("pressing B does not error when the session has no repeatTurn (DuelSession's shape)", bPressOk)
if not bPressOk then print("  error: " .. tostring(bPressErr)) end

-- A session that DOES implement repeatTurn (PracticeSession's shape)
-- must still have it invoked.
local repeatTurnCalls = 0
local sessionWithRepeat = setmetatable({}, { __index = fakeSession })
function sessionWithRepeat:repeatTurn() repeatTurnCalls = repeatTurnCalls + 1 end
local viewWithRepeat = PracticePlayable.new(fakeGame, sessionWithRepeat)
viewWithRepeat:enter()
viewWithRepeat.cursor = 1
local repeatOk, repeatErr = withPressed("b", function() viewWithRepeat:update(0) end)
check("pressing B does not error when the session has repeatTurn", repeatOk)
if not repeatOk then print("  error: " .. tostring(repeatErr)) end
check("pressing B actually invoked repeatTurn when present", repeatTurnCalls > 0)

checks = checks + 1
if failures == 0 then
  print(("all practice playable cases passed (%d checks)"):format(checks))
else
  print(("FAIL  %d/%d practice playable checks failed"):format(failures, checks))
  os.exit(1)
end
