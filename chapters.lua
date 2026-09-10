--------------------------------------------------------------------------
-- Pokopia: Log 568 -- chapter openings.
--
-- The game has three authored compositions: the LOG 568 flash-forward that
-- opens it (engine OakSpeech, content replaced in main.lua), the ending that
-- pays it off (finale.lua), and the two chapters in between. This module owns
-- the openings of those two chapters.
--
-- Before this, neither chapter had one.
--
--   * The Mansion cut straight from the black LOG 568 screen to a player
--     standing on Pokemon Mansion 3F with an alarm running. No establishing
--     shot, no location, and no reason given for a DITTO being in a research
--     building full of evacuating humans.
--   * Celadon opened on `love.graphics.printf("Much earlier...")` -- LOVE's
--     default font, not the game's, with nothing composed around it -- and
--     then cut directly into the middle of a Super Nerd buying a prize, a
--     scene the player has no context for at all.
--
-- Both openings are built to do the same job the opening LOG 568 scene does:
-- plant a question the rest of the game answers.
--
--   Mansion: "No one has time to ask what a DITTO is doing here."
--   Celadon: "Somewhere in that crowd is a DITTO."
--
-- The first is a question. The second is its answer arriving one chapter
-- late, exactly the way LOG 568 arrives one game late.
--
-- Split into pure data and a runtime, the same as finale.lua, and drawing
-- through cinema.lua so all three compositions share one presentation.
--------------------------------------------------------------------------

local Chapters={}

Chapters.VERSION=1

--------------------------------------------------------------------------
-- Chapter cards.
--
-- Two lines each, deliberately parallel: where, then when. The Celadon card
-- keeps `Much earlier...` verbatim, because that line is the story's own
-- established chronology marker and predates this module.
--------------------------------------------------------------------------
Chapters.MANSION_CARD={"CINNABAR ISLAND","POKeMON MANSION"}
Chapters.CELADON_CARD={"CELADON CITY","Much earlier..."}

--------------------------------------------------------------------------
-- Mansion cold open.
--
-- Plays over the live Mansion floor, after the card, while the world fades
-- up underneath the text. Four beats and no speaker: the mod's established
-- narration voice, and no human in this building acknowledges the player.
--
-- Beat 3 is the load-bearing one. It names DITTO to the player without any
-- character identifying it -- which the project's existing rule forbids --
-- and it is the question the Celadon chapter exists to answer.
--------------------------------------------------------------------------
Chapters.MANSION_OPENING={
  {text="The alarm has been\ngoing a while now."},
  {text="No one in this\nbuilding has\nlooked down once."},
  {text="No one has time to\nask what a DITTO\nis doing here."},
  {text="The stairs are\nstill open."},
}

--------------------------------------------------------------------------
-- Celadon establishing montage.
--
-- Spoken over the three-shot camera sweep that already exists in main.lua's
-- Celadon cutscene controller but was never reached: `cut:enter()` jumped
-- straight to the Game Corner. One beat per shot.
--
-- The tone is the point. The Mansion opening is an alarm and people who will
-- not look down; this is an ordinary loud afternoon in a city that has not
-- heard any of it yet.
--------------------------------------------------------------------------
Chapters.CELADON_MONTAGE={
  {text="CELADON CITY is\nloud in the\nafternoon."},
  {text="The GAME CORNER is\nbusy. It is\nalways busy."},
  {text="Somewhere in that\ncrowd is a DITTO."},
}

--------------------------------------------------------------------------
-- Persistent state. Additive, inside the mod's existing namespace.
--------------------------------------------------------------------------
function Chapters.state(q)
  if type(q)~="table" then return {} end
  if type(q.chapters)~="table" then q.chapters={} end
  local c=q.chapters
  c.version=math.max(tonumber(c.version) or 0,Chapters.VERSION)
  c.mansionOpeningSeen=c.mansionOpeningSeen and true or false
  c.celadonOpeningSeen=c.celadonOpeningSeen and true or false
  return c
end

-- Any of these means the player is already inside the story and must not be
-- handed a cold open. Used by main.lua's save migration so a development save
-- made before this module existed does not replay the opening.
Chapters.PROGRESS_MARKERS={
  "distractionDone","distractionCommitted","giovanniMeetingDone",
  "persianLessonDone","loganAsked","pixieFollowing","pixieStored",
  "cardQuestComplete","refundDemanded","policeCalled","superNerdArrested",
}

function Chapters.hasProgress(q)
  if type(q)~="table" then return false end
  for _,key in ipairs(Chapters.PROGRESS_MARKERS) do
    if q[key] then return true end
  end
  if type(q.forms)=="table" then
    for _,unlocked in pairs(q.forms) do
      if unlocked then return true end
    end
  end
  return false
end

--------------------------------------------------------------------------
-- Runtime.
--------------------------------------------------------------------------
function Chapters.new(api)
  api=api or {}
  local dataFor=api.data or function() return {} end
  local cinema=api.cinema
  assert(cinema,"chapters.lua requires api.cinema (see cinema.lua)")

  local self={}

  function self.state(game) return Chapters.state(dataFor(game)) end

  -- One-time reconciliation for saves written before this module existed.
  -- A player already inside the story must never be handed a cold open, so
  -- the first time this save is seen, existing story progress counts as
  -- having watched it. Idempotent: the `migrated` latch means later calls
  -- cannot re-derive the flag and undo a legitimate replay.
  function self.reconcile(game)
    local q=dataFor(game)
    local c=Chapters.state(q)
    if not c.migrated then
      c.migrated=true
      if not c.mansionOpeningSeen and Chapters.hasProgress(q) then
        c.mansionOpeningSeen=true
      end
    end
    return c
  end

  function self.shouldPlayMansionOpening(game)
    local c=self.reconcile(game)
    return not (c.mansionOpeningSeen or c.mansionOpeningRunning)
  end

  function self.markMansionOpeningSeen(game)
    self.state(game).mansionOpeningSeen=true
  end

  function self.markCeladonOpeningSeen(game)
    self.state(game).celadonOpeningSeen=true
  end

  ----------------------------------------------------------------------
  -- Composed chapter card.
  --
  -- Replaces the raw `printf` the `Much earlier...` intertitle used. The
  -- rules draw on before the text so the card assembles rather than simply
  -- appearing, and the whole thing is drawn in the game's own font.
  --
  -- Timings, in frames:
  --   0-26   rules grow out from the centre
  --   26-56  text fades up
  --   56-146 hold
  --   146-176 fade out
  ----------------------------------------------------------------------
  local CARD_RULE_IN,CARD_TEXT_IN=26,30
  local CARD_HOLD,CARD_OUT=90,30
  Chapters.CARD_FRAMES=CARD_RULE_IN+CARD_TEXT_IN+CARD_HOLD+CARD_OUT

  -- One timing curve, shared by the standalone card state and the Mansion
  -- cold open's card phase, so the two chapters open at identical pace.
  --
  --   0-26    rules grow out from the centre, text still absent
  --   26-56   text fades up between them
  --   56-146  hold
  --   146-176 rules and text leave together
  function Chapters.cardVisual(t)
    local ruleGrow=math.min(1,t/CARD_RULE_IN)
    local alpha
    if t<CARD_RULE_IN then
      alpha=0
    elseif t<CARD_RULE_IN+CARD_TEXT_IN then
      alpha=(t-CARD_RULE_IN)/CARD_TEXT_IN
    elseif t<CARD_RULE_IN+CARD_TEXT_IN+CARD_HOLD then
      alpha=1
    else
      alpha=1-((t-(CARD_RULE_IN+CARD_TEXT_IN+CARD_HOLD))/CARD_OUT)
    end
    alpha=math.max(0,math.min(1,alpha))
    -- The rules lead the text in and leave with it.
    local ruleAlpha=(t<CARD_RULE_IN) and ruleGrow or math.max(alpha,
      (t<CARD_RULE_IN+CARD_TEXT_IN+CARD_HOLD) and 1 or 0)
    return alpha,ruleGrow,math.max(0,math.min(1,ruleAlpha))
  end

  local function drawCardAt(lines,t,noClear)
    local alpha,ruleGrow,ruleAlpha=Chapters.cardVisual(t)
    cinema.drawCard(lines,{
      alpha=alpha,ruleGrow=ruleGrow,ruleAlpha=ruleAlpha,
      clear=(not noClear),
    })
  end

  function self.playCard(game,lines,opts)
    opts=opts or {}
    if not (game and game.stack) then
      if opts.onDone then opts.onDone(game) end
      return nil
    end

    local state={isOpaque=true,timer=0,finished=false}

    function state:update()
      self.timer=self.timer+1
      if self.timer>=Chapters.CARD_FRAMES and not self.finished then
        self.finished=true
        if game.stack:top()==self then game.stack:pop() end
        if opts.onDone then opts.onDone(game) end
      end
    end

    function state:draw() drawCardAt(lines,self.timer) end

    game.stack:push(state)
    return state
  end

  ----------------------------------------------------------------------
  -- Mansion cold open.
  --
  -- One non-opaque state over the live Mansion floor. Because it is not
  -- opaque, the overworld draws underneath it, which lets the card dissolve
  -- directly into the room the player is standing in instead of cutting.
  --
  --   CARD    black, the location card
  --   REVEAL  the black lifts and the Mansion appears
  --   NARRATE four beats over the live floor
  ----------------------------------------------------------------------
  local REVEAL_FRAMES=64

  function self.playMansionOpening(game,opts)
    opts=opts or {}
    if not (game and game.stack) then
      if opts.onDone then opts.onDone(game) end
      return nil
    end

    local c=self.state(game)
    c.mansionOpeningRunning=true

    local restoreInput=cinema.lockOverworld(game)
    local runner=cinema.newPageRunner(game,Chapters.MANSION_OPENING)

    local state={isOpaque=false,timer=0,phase="CARD",finished=false}

    function state:finish()
      if self.finished then return end
      self.finished=true
      c.mansionOpeningRunning=nil
      c.mansionOpeningSeen=true
      if game.stack:top()==self then game.stack:pop() end
      pcall(restoreInput)
      if opts.onDone then opts.onDone(game) end
    end

    function state:update()
      self.timer=self.timer+1

      if self.phase=="CARD" then
        if self.timer>=Chapters.CARD_FRAMES then
          self.phase="REVEAL"
          self.timer=0
        end

      elseif self.phase=="REVEAL" then
        if self.timer>=REVEAL_FRAMES then
          self.phase="NARRATE"
          self.timer=0
        end

      elseif self.phase=="NARRATE" then
        if runner:update() then self:finish() end
      end
    end

    function state:draw()
      if self.phase=="CARD" then
        -- This state is not opaque, so the live Mansion floor is already on
        -- screen underneath. Cover it completely, then draw the card on the
        -- black -- which is what lets the next phase dissolve the card
        -- straight into the room instead of cutting to it.
        cinema.drawFade(1)
        drawCardAt(Chapters.MANSION_CARD,self.timer,true)
        return
      end

      if self.phase=="REVEAL" then
        -- The Mansion is drawn by the overworld underneath; lift the black.
        cinema.drawFade(math.max(0,1-(self.timer/REVEAL_FRAMES)))
        return
      end

      runner:draw(self.timer)
    end

    game.stack:push(state)
    return state
  end

  return self
end

return Chapters
