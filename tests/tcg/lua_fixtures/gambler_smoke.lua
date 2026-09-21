-- Behavioral smoke test for Gambler's AI decision and RNG-cheat play wrapper
-- (AIDecide_Gambler/AIPlay_Gambler, trainer_cards.asm), run under real
-- LuaJIT rather than only checked as source text: the Imakuni-deck 2-in-10
-- roll, the Mewtwo-mill-flag gate for every other deck, and -- most
-- importantly -- the actual mechanical result of forcing wRNG1/wRNG2/
-- wRNGCounter to $50 through the real (already-verified) RNG module, which
-- this fixture confirms yields TAILS, not the HEADS the source's own
-- comment claims. That claim is not re-implemented; the literal byte-poke
-- mechanics are, and whatever a real cartridge would compute from them is
-- what this reproduces.

package.path = package.path .. ";./?.lua"
local AI = require("src.tcg.duel.AI")

local C = {
  DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK = 0x10,
  DECK_SIZE = 60,
  IMAKUNI_DECK_ID = 77,
  AI_MEWTWO_MILL = 0x80,
}

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(("FAIL  %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
  else
    print(("ok    %s"):format(label))
  end
end

local function newAI(opts)
  opts = opts or {}
  local symbols = {}
  for k, v in pairs(opts.symbols or {}) do symbols[k] = v end
  local memory = {
    readSymbol8 = function(_, name) return symbols[name] or 0 end,
    writeSymbol8 = function(_, name, v) symbols[name] = v end,
  }
  local ai = AI.new(
    memory,
    {
      get = function(_, addr) return (opts.turn or {})[addr] end,
      getNonTurn = function() return nil end,
    },
    { random = opts.random or function() return 5 end },
    { getCardIDFromDeckIndex = function() return nil end, get = function() return nil end },
    {},
    C,
    { aiByOpponentDeckId = {}, aiListsByOpponentDeckId = {} },
    {}
  )
  return ai, symbols
end

-- ---------------------------------------------------------------------
-- Imakuni? deck: real 10-sided roll, 2-in-10 chance (roll 0 or 1).
-- ---------------------------------------------------------------------
do
  local ai = newAI({ symbols = { wOpponentDeckID = C.IMAKUNI_DECK_ID },
    random = function(_, n) check("Imakuni roll size", n, 10); return 1 end })
  check("Imakuni deck: roll=1 (<2) -> plays", ai:_decideGambler(), true)
end
do
  local ai = newAI({ symbols = { wOpponentDeckID = C.IMAKUNI_DECK_ID },
    random = function() return 2 end })
  check("Imakuni deck: roll=2 (not <2) -> does not play", ai:_decideGambler(), false)
end

-- ---------------------------------------------------------------------
-- Every other deck: gated by the (not-yet-set) Mewtwo mill flag.
-- ---------------------------------------------------------------------
do
  local ai = newAI({ symbols = { wOpponentDeckID = 1, wAIBarrierFlagCounter = 0 } })
  check("mill flag unset -> never plays against other decks", ai:_decideGambler(), false)
end
do
  local ai = newAI({ symbols = { wOpponentDeckID = 1, wAIBarrierFlagCounter = C.AI_MEWTWO_MILL },
    turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 57 } })
  check("mill flag set, deck nearly empty (<=4 left) -> plays", ai:_decideGambler(), true)
end
do
  local ai = newAI({ symbols = { wOpponentDeckID = 1, wAIBarrierFlagCounter = C.AI_MEWTWO_MILL },
    turn = { [C.DUELVARS_NUMBER_OF_CARDS_NOT_IN_DECK] = 10 } })
  check("mill flag set, deck still has plenty (>4 left) -> does not play", ai:_decideGambler(), false)
end

-- ---------------------------------------------------------------------
-- _playGamblerWithRNGCheat: mechanical byte-poke + restore, verified
-- against the real RNG module rather than assumed.
-- ---------------------------------------------------------------------
do
  local ai, symbols = newAI({ symbols = {
    wOpponentDeckID = 1, wRNG1 = 0x12, wRNG2 = 0x34, wRNGCounter = 0x56,
  } })
  local seenDuringPlay = {}
  ai.playerActions = {
    playTrainer = function(_, cardId, selection)
      seenDuringPlay.rng1 = symbols.wRNG1
      seenDuringPlay.rng2 = symbols.wRNG2
      seenDuringPlay.counter = symbols.wRNGCounter
      return true, "trainer_played"
    end,
  }
  local ok = ai:_playGamblerWithRNGCheat(999, {})
  check("RNG-cheat: play succeeds", ok, true)
  check("RNG-cheat: wRNG1 forced to $50 during play", seenDuringPlay.rng1, 0x50)
  check("RNG-cheat: wRNG2 forced to $50 during play", seenDuringPlay.rng2, 0x50)
  check("RNG-cheat: wRNGCounter forced to $50 during play", seenDuringPlay.counter, 0x50)
  check("RNG-cheat: wRNG1 restored after play", symbols.wRNG1, 0x12)
  check("RNG-cheat: wRNG2 restored after play", symbols.wRNG2, 0x34)
  check("RNG-cheat: wRNGCounter restored after play", symbols.wRNGCounter, 0x56)
end
do
  -- Imakuni? deck bypasses the cheat entirely -- real RNG state untouched.
  local ai, symbols = newAI({ symbols = {
    wOpponentDeckID = C.IMAKUNI_DECK_ID, wRNG1 = 0x12, wRNG2 = 0x34, wRNGCounter = 0x56,
  } })
  local seenDuringPlay = {}
  ai.playerActions = {
    playTrainer = function(_, cardId, selection)
      seenDuringPlay.rng1 = symbols.wRNG1
      return true, "trainer_played"
    end,
  }
  ai:_playGamblerWithRNGCheat(999, {})
  check("Imakuni deck: RNG left untouched (not cheated)", seenDuringPlay.rng1, 0x12)
end

-- ---------------------------------------------------------------------
-- The actual mechanical result of the $50/$50/$50 seed, via the real
-- (already-verified) RNG module: confirms TAILS, not the source comment's
-- claimed HEADS.
-- ---------------------------------------------------------------------
do
  local RNG = require("src.tcg.duel.RNG")
  local bit = require("bit")
  local symbols = { wRNG1 = 0x50, wRNG2 = 0x50, wRNGCounter = 0x50 }
  local memory = {
    readSymbol8 = function(_, name) return symbols[name] end,
    writeSymbol8 = function(_, name, v) symbols[name] = v end,
  }
  local rng = RNG.new(memory)
  local value = rng:updateSources()
  check("$50/$50/$50 seed mechanically yields an odd (tails) result",
    bit.band(value, 1), 1)
end

if failures == 0 then
  print("all Gambler AI decision/RNG-cheat cases passed")
  os.exit(0)
else
  print(("%d Gambler AI decision/RNG-cheat case(s) failed"):format(failures))
  os.exit(1)
end
