-- Temporary native LÖVE presentation for the translated Sam practice duel.
-- This is intentionally not a recreation of the cartridge duel renderer/menu;
-- it exists so the source-state implementation can be played while those UI
-- routines are still being translated.

local PracticePlayable = {}
PracticePlayable.__index = PracticePlayable
PracticePlayable.isOpaque = true

function PracticePlayable.new(game, session)
  return setmetatable({ game = assert(game), session = assert(session), cursor = 1 }, PracticePlayable)
end

function PracticePlayable:enter()
  self.font = love.graphics.newFont(6)
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
  if input:wasPressed("b") then
    self.session:repeatTurn()
    self.cursor = 1
  end
end

local function cardLine(card)
  if not card then return "(none)" end
  return string.format("%s %d/%d", card.name, card.hp, card.maxHP)
end

local function benchLine(side)
  if #side.bench == 0 then return "Bench: -" end
  local out = {}
  for _, card in ipairs(side.bench) do out[#out + 1] = cardLine(card) end
  return "Bench: " .. table.concat(out, " | ")
end

function PracticePlayable:draw()
  local g = love.graphics
  g.setFont(self.font)
  g.setColor(0, 0, 0, 1)

  local c = self.session.data.constants
  local player = self.session:sideState(c.PLAYER_TURN)
  local opponent = self.session:sideState(c.OPPONENT_TURN)
  local turns = self.session.runtime.memory:readSymbol8("wDuelTurns")

  g.print("SAM'S PRACTICE DUEL  [development UI]", 3, 2)
  g.print(string.format("Turn %d  Player hand:%d prizes:%d", turns + 1, player.hand, player.prizes), 3, 11)
  g.print("You: " .. cardLine(player.active), 3, 20)
  g.printf(benchLine(player), 3, 29, 154, "left")
  g.print("Sam: " .. cardLine(opponent.active), 3, 39)
  g.printf(benchLine(opponent), 3, 48, 154, "left")

  if self.session.phase == "won" or self.session.phase == "lost" then
    local label = self.session.phase == "won" and "PRACTICE DUEL COMPLETE - YOU WIN" or "DUEL LOST"
    g.printf(label, 5, 69, 150, "center")
    g.printf("The original result screen is not translated yet.", 10, 84, 140, "center")
    return
  end

  if self.session.phase ~= "player" then
    g.printf("Sam is taking the source-scripted turn...", 5, 70, 150, "center")
    return
  end

  local actions = self.session:availableActions()
  g.print("Required actions:", 3, 60)
  local y = 69
  for i, action in ipairs(actions) do
    local prefix = i == self.cursor and "> " or "  "
    g.printf(prefix .. action.label, 3, y, 154, "left")
    y = y + 9
  end

  if self.session.message then
    g.printf(self.session.message, 3, 100, 154, "left")
  else
    local instruction = self.session.instructionText or ""
    instruction = instruction:gsub("\n+", " ")
    g.printf(instruction, 3, 100, 154, "left")
  end
  g.print("D-pad: select   A: act   B: restore turn", 3, 136)
end

return PracticePlayable
