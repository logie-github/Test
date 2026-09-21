-- DuelMainInterface branch dispatcher translated from pret/poketcg
-- src/engine/duel/core.asm. Rendering/input/action engines remain separate
-- adapters, but source branch selection and AI post-turn state are native.

local DuelInterface = {}
DuelInterface.__index = DuelInterface

function DuelInterface.new(memory, duelVars, ai, constants, adapters)
  return setmetatable({
    memory = assert(memory),
    duelVars = assert(duelVars),
    ai = assert(ai),
    c = assert(constants),
    adapters = adapters or {},
  }, DuelInterface)
end

function DuelInterface:_required(name)
  local fn = self.adapters[name]
  assert(type(fn) == "function",
    "TCG DuelMainInterface requires untranslated adapter: " .. name)
  return fn
end

function DuelInterface:run()
  self:_required("drawDuelMainScene")()
  local dtype = self.memory:readSymbol8("wDuelistType")
  if dtype == self.c.DUELIST_TYPE_PLAYER then
    return self:_required("playerDuelMenu")()
  elseif dtype == self.c.DUELIST_TYPE_LINK_OPP then
    return self:_required("linkOpponentTurn")()
  end

  -- DUELIST_TYPE_AI_OPP path.
  self.memory:writeSymbol8("wVBlankCounter", 0)
  self.memory:writeSymbol8("wSkipDuelistIsThinkingDelay", 0)
  local present = self.adapters.showDuelistIsThinking
  if present then present() end
  local result = self.ai:doTurn()
  self.memory:writeSymbol8("wPlayerAttackingCardIndex", 0xff)
  self.memory:writeSymbol8("wPlayerAttackingAttackIndex", 0xff)
  return result
end

return DuelInterface
