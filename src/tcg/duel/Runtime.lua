-- Dependency bundle for source-backed Pokemon TCG duel routines.

local Memory = require("src.tcg.memory.Memory")
local DuelVars = require("src.tcg.duel.DuelVars")
local RNG = require("src.tcg.duel.RNG")
local CardData = require("src.tcg.duel.CardData")
local DuelOps = require("src.tcg.duel.DuelOps")
local Core = require("src.tcg.duel.Core")
local DeckLoader = require("src.tcg.duel.DeckLoader")
local DuelSetup = require("src.tcg.duel.DuelSetup")
local SaveData = require("src.tcg.duel.SaveData")
local Practice = require("src.tcg.duel.Practice")
local AI = require("src.tcg.duel.AI")
local Status = require("src.tcg.duel.Status")
local EffectCommands = require("src.tcg.duel.EffectCommands")
local Prizes = require("src.tcg.duel.Prizes")
local KnockOuts = require("src.tcg.duel.KnockOuts")
local DuelInterface = require("src.tcg.duel.DuelInterface")
local TurnFlow = require("src.tcg.duel.TurnFlow")
local Combat = require("src.tcg.duel.Combat")
local PlayerActions = require("src.tcg.duel.PlayerActions")

local Runtime = {}

function Runtime.new(data, adapters)
  adapters = adapters or {}
  local memory = Memory.new(data.memory)
  local duelVars = DuelVars.new(memory, data.constants)
  local rng = RNG.new(memory)
  local cardData = CardData.new(memory, duelVars, data)
  local duelOps = DuelOps.new(memory, duelVars, rng, data.constants, data.decks, cardData)
  local core = Core.new(memory, duelVars, duelOps, data.constants, data.core)
  local deckLoader = DeckLoader.new(memory, duelVars, duelOps, rng, data.constants, data.decks)
  local saveData = SaveData.new(memory, duelVars, cardData, data.constants, data.core)

  -- Setup, practice and AI refer to each other only through runtime actions, so
  -- connect them after construction rather than weakening their dependencies.
  local duelSetup = DuelSetup.new(memory, duelVars, rng, cardData, duelOps, core,
    data.constants, adapters.setup)
  local practice = Practice.new(memory, duelVars, duelOps, saveData,
    data.constants, adapters.practice)
  local ai = AI.new(memory, duelVars, rng, cardData, duelOps, data.constants,
    data.decks, adapters.ai)
  duelSetup:setPractice(practice)
  duelSetup:setAI(ai)

  local status = Status.new(memory, duelVars, cardData, duelOps, duelSetup,
    data.constants, adapters.status)
  local effectCommands = EffectCommands.new(memory, duelSetup, status,
    data.constants, data.effects, adapters.effects)
  effectCommands:setAI(ai)
  local prizes = Prizes.new(memory, duelVars, duelOps, ai, duelSetup,
    data.constants, adapters.prizes)
  local knockouts = KnockOuts.new(memory, duelVars, duelOps, cardData, status,
    core, prizes, practice, ai, duelSetup, data.constants, data.core,
    adapters.knockouts)
  status:setKnockOuts(knockouts)
  local combat = Combat.new(memory, duelVars, cardData, duelOps, core, status,
    duelSetup, knockouts, practice, effectCommands, data.constants, adapters.combat)
  ai:setCombat(combat)
  local playerActions = PlayerActions.new(memory, duelVars, cardData, duelOps, combat,
    effectCommands, data.constants, adapters.playerActions)
  ai:setPlayerActions(playerActions)
  local duelInterface = DuelInterface.new(memory, duelVars, ai, data.constants,
    adapters.interface)

  local turnFlow = TurnFlow.new(memory, duelVars, duelOps, core, duelSetup,
    status, saveData, practice, duelInterface, data.constants, adapters.turn)

  return {
    memory = memory,
    duelVars = duelVars,
    rng = rng,
    cardData = cardData,
    duelOps = duelOps,
    core = core,
    deckLoader = deckLoader,
    saveData = saveData,
    practice = practice,
    ai = ai,
    status = status,
    effectCommands = effectCommands,
    prizes = prizes,
    knockouts = knockouts,
    combat = combat,
    playerActions = playerActions,
    duelInterface = duelInterface,
    duelSetup = duelSetup,
    turnFlow = turnFlow,
  }
end

return Runtime
