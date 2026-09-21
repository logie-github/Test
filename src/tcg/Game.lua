-- Pokemon TCG runtime shell using Gen1Recomp services.
-- Gameplay behavior is added only as decomp routines are translated.

local FixedStep = require("src.core.FixedStep")
local Input = require("src.core.Input")
local Renderer = require("src.render.Renderer")
local StateStack = require("src.core.StateStack")
local TouchControls = require("src.core.TouchControls")
local Data = require("src.tcg.Data")
local Game = {}

function Game:load()
  self.data = Data:load()
  local practicePlayable = os.getenv("POKEPORT_TCG_PRACTICE") == "1"

  self.input = Input
  Input:init()

  self.touchControls = TouchControls
  TouchControls:init()

  self.renderer = Renderer
  Renderer:init()

  self.stack = StateStack
  StateStack:init()

  FixedStep:init(function(step) self:step(step) end)
  self.fixedStep = FixedStep

  if self.data.meta.translationComplete ~= true
      and os.getenv("POKEPORT_TCG_ALLOW_PARTIAL") ~= "1"
      and not practicePlayable then
    error("TCG runtime reached with an incomplete translation cache")
  end

  if practicePlayable then
    local PracticeSession = require("src.tcg.duel.PracticeSession")
    local PracticePlayable = require("src.tcg.states.PracticePlayable")
    local session = PracticeSession.new(self.data)
    self.tcg = session.runtime
    self.practiceSession = session
    self.stack:push(PracticePlayable.new(self, session))
  else
    self.tcg = require("src.tcg.duel.Runtime").new(self.data)
    local Status = require("src.tcg.states.TranslationIncomplete")
    self.stack:push(Status.new(self, self.data))
  end
end

function Game:step(dt)
  self.input:step()
  self.stack:update(dt)
end

function Game:update(dt)
  FixedStep:update(dt)
end

function Game:draw()
  Renderer:setUISize(Renderer.WIDTH, Renderer.HEIGHT)
  Renderer:beginFrame(false)
  self.stack:draw()
  Renderer:endFrame(nil, nil)
  TouchControls:draw()
end

function Game:keypressed(key) Input:keypressed(key) end
function Game:keyreleased(key) Input:keyreleased(key) end
function Game:gamepadpressed(joystick, button)
  TouchControls:noteGamepad()
  Input:gamepadpressed(joystick, button)
end
function Game:gamepadreleased(joystick, button)
  Input:gamepadreleased(joystick, button)
end
function Game:gamepadaxis(joystick, axis, value)
  if math.abs(value) > 0.5 then TouchControls:noteGamepad() end
  Input:gamepadaxis(joystick, axis, value)
end
function Game:focus(f)
  Input:reset()
  TouchControls:reset()
end

function Game:visible(v)
  Input:reset()
  TouchControls:reset()
end

function Game:joystickremoved(joystick)
  Input:reset()
  TouchControls:joystickremoved()
end

function Game:touchpressed(id, x, y)
  TouchControls:touchpressed(id, x, y)
end

function Game:touchmoved(id, x, y)
  TouchControls:touchmoved(id, x, y)
end

function Game:touchreleased(id, x, y)
  TouchControls:touchreleased(id, x, y)
end

-- main.lua forwards the wheel unconditionally once a game is running. TCG
-- does not have a translated wheel-facing action; consume it at the host edge.
function Game:wheelmoved(x, y) end

return Game
