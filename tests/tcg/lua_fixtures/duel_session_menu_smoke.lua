package.path = "./?.lua;" .. package.path

local checks, failures = 0, 0
local function check(label, cond, detail)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print(("FAIL  %s%s"):format(label, detail and (" -- " .. tostring(detail)) or ""))
  end
end

-- Exercises DuelSession's dynamic per-turn menu builder (_turnActions) and
-- its evolve/attack legality pre-checks directly, against a hand-built
-- fake runtime -- the same "build the minimum real surface a method
-- touches" technique this suite uses elsewhere. Booting a *real* Runtime
-- (all 19 duel submodules) needs the actual extracted ROM data, which
-- this repo never ships; that full boot -> setup -> multi-turn path was
-- validated separately, this session, against a from-source-built
-- poketcg.gbc (real ROM bytes, not committed). That run found and fixed
-- the attackIndex off-by-one [T1] pins down, plus two unrelated
-- pre-existing engine bugs (AI.lua's forward-referenced wrMask local,
-- Combat.lua's ATK_ANIM_RECOIL_HIT typo) and a build_manifest.py
-- constants-file gap -- none reachable from here, since none are
-- DuelSession's own code.

local DuelSession = require("src.tcg.duel.DuelSession")

-- Trainer/Energy "constant" names double as the real card's own id in
-- this game (e.g. the real c.BILL equals Bill's actual CARD_DATA_ID), so
-- the fake constants below reuse the same fake card ids DuelSession is
-- asked to recognize by name, exactly like the real manifest does.
local BULBASAUR, IVYSAUR, VENUSAUR, ENERGY, POTION, BILL = 1, 2, 6, 3, 4, 5

local c = {
  PLAYER_TURN = 0, OPPONENT_TURN = 1,
  DUELVARS_NUMBER_OF_CARDS_IN_HAND = 100, DUELVARS_HAND = 200,
  DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA = 101,
  DUELVARS_ARENA_CARD = 300, DUELVARS_ARENA_CARD_HP = 400,
  DUELVARS_ARENA_CARD_FLAGS = 500,
  PLAY_AREA_ARENA = 0, PLAY_AREA_BENCH_1 = 1, MAX_PLAY_AREA_POKEMON = 5,
  CAN_EVOLVE_THIS_TURN = 128,
  BASIC = 0, TYPE_ENERGY = 8, TYPE_TRAINER = 16, POKEMON_POWER = 9,
  POTION = POTION, SWITCH = 901, SCOOP_UP = 902,
  PROFESSOR_OAK = 910, BILL = BILL, FULL_HEAL = 912,
}
local cardsById = {
  [BULBASAUR] = { id = BULBASAUR, name = "Bulbasaur", kind = "pokemon", stage = c.BASIC, nameTextId = 100 },
  [IVYSAUR] = { id = IVYSAUR, name = "Ivysaur", kind = "pokemon", stage = 1,
    preEvolutionTextId = 100, nameTextId = 150, hp = 60, retreatCost = 1,
    attacks = {
      { nameTextId = 201, name = "Vine Whip", category = 1, energy = { [0] = 1 } },
      { nameTextId = 0, name = "", category = 1, energy = {} }, -- unused slot
    } },
  [VENUSAUR] = { id = VENUSAUR, name = "Venusaur", kind = "pokemon", stage = 2, preEvolutionTextId = 150 },
  [ENERGY] = { id = ENERGY, name = "Grass Energy", kind = "energy" },
  [POTION] = { id = POTION, name = "Potion", kind = "trainer" },
  [BILL] = { id = BILL, name = "Bill", kind = "trainer" },
}

-- deckIndex -> cardId for every card either side of these tests can hold.
local deckIndexToCardId = { [10] = BULBASAUR, [11] = ENERGY, [12] = POTION, [13] = BILL,
  [14] = VENUSAUR, [20] = IVYSAUR, [21] = BULBASAUR }

-- opts: hand (list of deckIndex), attachedEnergy, alreadyPlayedEnergy,
-- canEvolve, retreated, playAreaCount (default 1, active only).
local function makeSession(opts)
  opts = opts or {}
  local hand = opts.hand or { 10, 11, 12, 13 }
  local vars = {
    [c.DUELVARS_NUMBER_OF_CARDS_IN_HAND] = #hand,
    [c.DUELVARS_NUMBER_OF_POKEMON_IN_PLAY_AREA] = opts.playAreaCount or 1,
    [c.DUELVARS_ARENA_CARD] = 20, -- Ivysaur
    [c.DUELVARS_ARENA_CARD_HP] = 60,
    [c.DUELVARS_ARENA_CARD_FLAGS] = opts.canEvolve and c.CAN_EVOLVE_THIS_TURN or 0,
  }
  for i, deckIndex in ipairs(hand) do vars[c.DUELVARS_HAND + i - 1] = deckIndex end
  if (opts.playAreaCount or 1) > 1 then
    vars[c.DUELVARS_ARENA_CARD + c.PLAY_AREA_BENCH_1] = 21 -- a bench Bulbasaur
    vars[c.DUELVARS_ARENA_CARD_HP + c.PLAY_AREA_BENCH_1] = 40
  end

  local memoryVars = { wAlreadyPlayedEnergy = opts.alreadyPlayedEnergy and 1 or 0 }

  local fakeRuntime = {
    duelVars = {
      get = function(_, key) return vars[key] or 0 end,
      set = function(_, key, value) vars[key] = value end,
      turn = function() return c.PLAYER_TURN end,
      setTurn = function() end,
      swapTurn = function() end,
    },
    cardData = {
      get = function(_, cardId) return cardsById[cardId] end,
      getCardIDFromDeckIndex = function(_, deckIndex) return deckIndexToCardId[deckIndex] end,
    },
    duelOps = {
      getPlayAreaCardAttachedEnergies = function() return opts.attachedEnergy or 0 end,
      countPrizes = function() return 6 end,
    },
    memory = {
      readSymbol8 = function(_, name) return memoryVars[name] or 0 end,
    },
  }

  return setmetatable({
    data = { constants = c, cards = { byId = cardsById } },
    runtime = fakeRuntime,
    phase = "player",
    playerRetreatedThisTurn = opts.retreated or false,
    targetTrainers = {
      [c.POTION] = { key = "playArea", label = "Heal 20 damage from" },
      [c.SWITCH] = { key = "bench", label = "Switch active with" },
      [c.SCOOP_UP] = { key = "playArea", label = "Return to hand" },
    },
  }, DuelSession)
end

local function findAction(actions, kind, matchLabel)
  for _, action in ipairs(actions) do
    if action.kind == kind and (not matchLabel or action.label:find(matchLabel, 1, true)) then
      return action
    end
  end
  return nil
end

local function countKind(actions, kind)
  local n = 0
  for _, action in ipairs(actions) do if action.kind == kind then n = n + 1 end end
  return n
end

-- [T1] Bare case: evolve flag unset, energy not yet played, enough
-- attached energy for Vine Whip, no bench.
local a1 = makeSession({ attachedEnergy = 1 }):_turnActions()
check("[T1] offers energy attach for the hand Energy card", findAction(a1, "energy") ~= nil)
check("[T1] offers Bill (no-target trainer) as a direct play", findAction(a1, "trainer", "Bill") ~= nil)
check("[T1] offers Potion as a target-picker, not a direct play",
  findAction(a1, "trainer_target", "Potion") ~= nil)
check("[T1] does not offer Potion as a direct trainer play", findAction(a1, "trainer", "Potion") == nil)
check("[T1] does not offer evolve (CAN_EVOLVE_THIS_TURN unset)", findAction(a1, "evolve") == nil)
check("[T1] does not offer the unused second attack slot (nameTextId==0)", countKind(a1, "attack") == 1)
check("[T1] Vine Whip uses the source's 0-based attackIndex, not the Lua 1-based loop index",
  findAction(a1, "attack", "Vine Whip").attack == 0)
check("[T1] end_turn is always offered, listed last", a1[#a1].kind == "end_turn")
check("[T1] does not offer retreat (no bench)", findAction(a1, "retreat") == nil)

-- [T2] Energy already played this turn.
local a2 = makeSession({ attachedEnergy = 1, alreadyPlayedEnergy = true }):_turnActions()
check("[T2] no energy action once wAlreadyPlayedEnergy is set", findAction(a2, "energy") == nil)

-- [T3] Not enough attached energy for Vine Whip (cost 1, attached 0).
local a3 = makeSession({ attachedEnergy = 0 }):_turnActions()
check("[T3] Vine Whip not offered when unaffordable", findAction(a3, "attack", "Vine Whip") == nil)

-- [T4] Evolve gated by CAN_EVOLVE_THIS_TURN: Venusaur's preEvolutionTextId
-- names Ivysaur (the active) by nameTextId, so it's a legal-looking evolve
-- target whenever the flag is set, and only then.
local hand5 = { 10, 11, 12, 13, 14 }
local a4 = makeSession({ attachedEnergy = 1, canEvolve = true, hand = hand5 }):_turnActions()
check("[T4] evolve offered once CAN_EVOLVE_THIS_TURN is set", findAction(a4, "evolve", "Venusaur") ~= nil)

local a4b = makeSession({ attachedEnergy = 1, canEvolve = false, hand = hand5 }):_turnActions()
check("[T4b] evolve NOT offered when CAN_EVOLVE_THIS_TURN is clear", findAction(a4b, "evolve", "Venusaur") == nil)

-- [T5] Retreat: needs a bench slot, enough attached energy for retreatCost
-- (1), and not already retreated this turn.
local a5 = makeSession({ attachedEnergy = 1, playAreaCount = 2 }):_turnActions()
check("[T5] retreat offered with a bench slot and enough energy", findAction(a5, "retreat") ~= nil)

local a5b = makeSession({ attachedEnergy = 1, playAreaCount = 2, retreated = true }):_turnActions()
check("[T5b] retreat NOT offered once playerRetreatedThisTurn is set", findAction(a5b, "retreat") == nil)

checks = checks + 1
if failures == 0 then
  print(("all duel session menu cases passed (%d checks)"):format(checks))
else
  print(("FAIL  %d/%d duel session menu checks failed"):format(failures, checks))
  os.exit(1)
end
