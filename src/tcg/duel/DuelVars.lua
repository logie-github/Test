-- Exact native equivalents of the duel-variable page helpers in
-- pret/poketcg src/home/duel.asm.

local DuelVars = {}
DuelVars.__index = DuelVars

function DuelVars.new(memory, constants)
  assert(memory and constants, "DuelVars requires memory and generated constants")
  return setmetatable({ memory = memory, c = constants }, DuelVars)
end

function DuelVars:turn()
  -- hWhoseTurn stores the high byte of wPlayerDuelVariables/wOpponentDuelVariables.
  return self.memory:readSymbol8("hWhoseTurn")
end

function DuelVars:setTurn(highByte)
  self.memory:writeSymbol8("hWhoseTurn", highByte)
end

function DuelVars:address(offset, highByte)
  highByte = highByte or self:turn()
  return highByte * 0x100 + (offset % 0x100)
end

-- GetTurnDuelistVariable:: [hWhoseTurn:a]
function DuelVars:get(offset)
  local address = self:address(offset)
  return self.memory:read8("wram", address, 0), address
end

function DuelVars:set(offset, value)
  local address = self:address(offset)
  self.memory:write8("wram", address, value, 0)
  return address
end

-- GetNonTurnDuelistVariable:: chooses the other C2/C3 page.
function DuelVars:nonTurnHigh()
  if self:turn() == self.c.PLAYER_TURN then
    return self.c.OPPONENT_TURN
  end
  return self.c.PLAYER_TURN
end

function DuelVars:getNonTurn(offset)
  local address = self:address(offset, self:nonTurnHigh())
  return self.memory:read8("wram", address, 0), address
end

function DuelVars:setNonTurn(offset, value)
  local address = self:address(offset, self:nonTurnHigh())
  self.memory:write8("wram", address, value, 0)
  return address
end

-- SwapTurn:: writes the high byte selected by GetNonTurnDuelistVariable.
function DuelVars:swapTurn()
  local high = self:nonTurnHigh()
  self:setTurn(high)
  return high
end

return DuelVars
