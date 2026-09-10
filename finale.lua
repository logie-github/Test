--------------------------------------------------------------------------
-- Pokopia: Log 568 -- LOG 568 BOOKEND FINALE
--
-- The game opens on the engine's real OakSpeech screen with the Scientist
-- portrait reading LOG 568 on a black background (see the
-- `intro.oak_speech.build` wrap in main.lua). That opening is deliberately
-- context-free: the player does not yet know what failed, or when.
--
-- This module is the other half of that composition. It plays after the last
-- prequel beat, carries the player through the departure and the liftoff,
-- then reproduces the opening's exact visual language and exact opening
-- lines -- and continues the log past the point where the intro stopped.
--
-- Design constraints taken from the story brief, restated here because they
-- are load-bearing and easy to erode later:
--
--   * The existing opening is never removed or rewritten. This module only
--     quotes it. `Finale.OPENING_LINES` is the verbatim quote and
--     `tests/finale.lua` asserts the bookend still contains it in order.
--   * The liftoff is allowed to look like a success. Nothing explains the
--     failure until the Scientist does.
--   * No definitive cause is invented for the disasters, and no reason is
--     given for why humanity does not return. The log states the outcome.
--   * Humans are never shown returning successfully.
--   * The release contingency described in Giovanni's Conservation Project
--     briefing (main.lua, `giovanniMeetingTalk`) is still armed at the end.
--
-- The module is deliberately split into pure data (`Finale.SCRIPT`) and a
-- runtime (`Finale.new`). The data half has no love/engine dependency, which
-- is what makes the ending unit-testable without booting Gen1Recomp.
--------------------------------------------------------------------------

local Finale={}

Finale.VERSION=1

--------------------------------------------------------------------------
-- Verbatim quote of the OakSpeech opening.
--
-- These strings are copied character-for-character out of the `log568_a`,
-- `log568_b` and `log568_c` steps in main.lua. They exist so the bookend can
-- be validated against the opening instead of drifting away from it.
--------------------------------------------------------------------------
Finale.OPENING_LINES={
  "LOG 568:",
  "The experiment has\nfailed.",
  "Our last-ditch\nHail Mary project...",
  "A complete and\ntotal failure.",
}

Finale.OPENING_CLOSING_LINES={
  "Estimations show\nwithin a few days...",
  "Life on this planet\nas we know it will\ncome to an end.",
}

--------------------------------------------------------------------------
-- Scene 1 -- Departure.
--
-- Picks up the instant after LOGAN closes the PC on Ditto and PIXIE in the
-- Pokemon Mansion (`loganTalk`). Nothing here contradicts that scene; it
-- continues it from inside the storage system. Every human present still
-- believes the separation is temporary. That belief is the point.
--------------------------------------------------------------------------
local DEPARTURE={
  {text="The PC hums."},
  {text="Outside the glass,\nthe lab has gone\ndark."},
  {speaker="LOGAN",text="PIXIE is right\nbeside you. See?"},
  {speaker="LOGAN",text="You aren't alone\nin there."},
  {speaker="SCIENTIST",text="LOGAN.\nThe last transport\nis loading."},
  {speaker="LOGAN",text="One more minute."},
  {speaker="SCIENTIST",text="We don't have one."},
  {text="LOGAN puts a hand\nflat on the glass."},
  {speaker="LOGAN",text="We're coming back."},
  {speaker="LOGAN",text="That's the whole\npoint of all this."},
  {speaker="LOGAN",text="...I promise."},
  {text="The lab lights go\nout, one bank at\na time."},
  {speaker="SCIENTIST",text="CONSERVATION\nPROJECT sealed."},
  {speaker="SCIENTIST",text="Storage is stable.\nContingency armed."},
  {speaker="SCIENTIST",text="The first return\nsurvey is already\nscheduled."},
  {text="Above the lab,\nengines begin to\nturn over."},
}

--------------------------------------------------------------------------
-- Scene 2 -- Liftoff.
--
-- Deliberately almost wordless. The launch is allowed to read as a success,
-- and then it is allowed to simply sit there. The single closing line does
-- not editorialise.
--------------------------------------------------------------------------
local LIFTOFF_CLOSING={
  {text="Every ship clears\nthe sky."},
}

--------------------------------------------------------------------------
-- Scene 3 -- LOG 568, again.
--
-- Pages 1-4 are `Finale.OPENING_LINES`. Pages 5-13 are new. Pages 14-15 are
-- `Finale.OPENING_CLOSING_LINES`. The recognition beat is pages 1-4; the
-- reframing beat is pages 14-15.
--
-- The continuation says three things and no more: the plan's second half
-- failed, there will be no return, and the surface projections are days
-- out. It does not name a cause, a location, or a mechanism -- the Human
-- Records leave those unresolved and so does this.
--------------------------------------------------------------------------
local LOG568_CONTINUATION={
  {text="The part after\nthe launch was\nmeant to be easy."},
  {text="It was not."},
  {text="I have gone back\nthrough every\nmodel we built."},
  {text="Not one of them\ndescribes what has\nhappened to us."},
  {text="There will be no\nreturn survey."},
  {text="No one is going\nback for them."},
  {text="I have deleted\nthat line four\ntimes."},
  {text="I am leaving it\nin this time."},
  {text="The last surface\nreadings came in\nthis morning."},
}

--------------------------------------------------------------------------
-- Scene 4 -- The preservation system.
--
-- The system outlives the people who built it. It is still running, still
-- holding its records, and still waiting on the habitat check that the
-- Conservation Project briefing promised. No human answers it.
--------------------------------------------------------------------------
local SYSTEM_STATUS={
  {"SYSTEM","ACTIVE"},
  {"POWER","INTERNAL"},
  {"UPLINK","NO SIGNAL"},
  {"LAST CONTACT","----"},
}

-- Two rows, because they replace the two record rows on the display without
-- pushing the status block off the top of the frame.
local SYSTEM_CONTINGENCY={
  "CONTINGENCY ARMED",
  "HABITAT   PENDING",
}

-- Sampled from the Mansion population the player actually met, so the roll
-- reads as "these are the ones you know" rather than filler.
local SYSTEM_RECORDS={
  {box="01",species="RATTATA"},
  {box="01",species="CHARMANDER"},
  {box="02",species="KOFFING"},
  {box="02",species="GRIMER"},
  {box="03",species="MAGNEMITE"},
  {box="03",species="PORYGON"},
  {box="04",species="SLOWPOKE"},
  {box="04",species="TOTODILE"},
  {box="05",species="VULPIX",nickname="PIXIE"},
  {box="06",species="LARVITAR"},
  {box="06",species="AMPHAROS"},
  {box="07",species="DITTO"},
}

local SYSTEM_NARRATION={
  {text="The system cannot\nknow that no one\nis listening."},
  {text="It keeps its\nrecords anyway."},
  {text="Every entry is\nstill intact."},
  {text="The release\ncontingency is\nstill armed."},
  {text="Still waiting for\nsomewhere safe to\nput them."},
}

--------------------------------------------------------------------------
-- Scene 5 -- Ditto, dormant.
--------------------------------------------------------------------------
local DORMANT={
  {text="BOX 07."},
  {text="DITTO."},
  {text="STATUS: DORMANT."},
  {text="The record is\nintact."},
}

--------------------------------------------------------------------------
-- Assembled script. Exposed for tests and for future phases that want to
-- reuse individual beats without pulling in the renderer.
--------------------------------------------------------------------------
Finale.SCRIPT={
  departure=DEPARTURE,
  liftoffClosing=LIFTOFF_CLOSING,
  log568=(function()
    local pages={}
    for i,line in ipairs(Finale.OPENING_LINES) do
      pages[#pages+1]={text=line,reveal=(i==1) and "fade" or nil,quoted="opening"}
    end
    for _,page in ipairs(LOG568_CONTINUATION) do
      pages[#pages+1]={text=page.text}
    end
    for _,line in ipairs(Finale.OPENING_CLOSING_LINES) do
      pages[#pages+1]={text=line,quoted="opening"}
    end
    return pages
  end)(),
  systemStatus=SYSTEM_STATUS,
  systemContingency=SYSTEM_CONTINGENCY,
  systemRecords=SYSTEM_RECORDS,
  systemNarration=SYSTEM_NARRATION,
  dormant=DORMANT,
}

--------------------------------------------------------------------------
-- Scene order. `Finale.new(...).play(game,{from="LOG568"})` starts at any of
-- these, which is what the developer scene picker uses.
--------------------------------------------------------------------------
Finale.SCENES={"DEPARTURE","LIFTOFF","LOG568","SYSTEM","DORMANT"}

local SCENE_INDEX={}
for i,name in ipairs(Finale.SCENES) do SCENE_INDEX[name]=i end

-- The persistent record for the ending. Additive: it only ever creates its
-- own sub-table inside the mod's existing `pokopia_log568` namespace.
function Finale.state(q)
  if type(q)~="table" then return {} end
  if type(q.finale)~="table" then q.finale={} end
  local f=q.finale
  f.version=math.max(tonumber(f.version) or 0,Finale.VERSION)
  f.playCount=math.max(0,math.floor(tonumber(f.playCount) or 0))
  f.prequelComplete=f.prequelComplete and true or false
  f.logSeen=f.logSeen and true or false
  f.completed=f.completed and true or false
  return f
end


--------------------------------------------------------------------------
-- Runtime.
--
-- All Gen I presentation -- the text frame, the Scientist cutout, the page
-- runner, fades, audio and the overworld input lock -- comes from cinema.lua,
-- which the Mansion cold open and the Celadon chapter card share. This file
-- owns only the ending's own composition: its scene order, its timings, and
-- the two custom renderers (the launch and the storage display) that exist
-- nowhere else.
--------------------------------------------------------------------------

local function safeRequire(name)
  local ok,value=pcall(require,name)
  if ok then return value end
  return nil
end

function Finale.new(api)
  api=api or {}
  local dataFor=api.data or function() return {} end
  local cinema=api.cinema
  assert(cinema,"finale.lua requires api.cinema (see cinema.lua)")

  local B=cinema.BOX
  local self={}

  ----------------------------------------------------------------------
  -- Save helpers.
  ----------------------------------------------------------------------
  function self.state(game) return Finale.state(dataFor(game)) end

  function self.markPrequelComplete(game)
    local f=self.state(game)
    f.prequelComplete=true
    return f
  end

  function self.isComplete(game) return self.state(game).completed and true or false end

  -- The automatic trigger. The ending only rolls once, and only after the
  -- prequel chapter it explains has actually been played.
  function self.shouldAutoPlay(game)
    local f=self.state(game)
    if f.completed or f.running then return false end
    return f.prequelComplete and true or false
  end

  ----------------------------------------------------------------------
  -- Liftoff renderer.
  --
  -- Pure primitives, four-shade friendly: black sky, white stars, a white
  -- horizon and a white vehicle. No new image assets are introduced.
  ----------------------------------------------------------------------
  local STARS={}
  do
    -- Deterministic layout so the sky is identical on every playthrough and
    -- in every capture, rather than reshuffling per run.
    local seed=20250910
    local function rand(m)
      seed=(seed*1103515245+12345)%2147483648
      return seed%m
    end
    for _=1,34 do STARS[#STARS+1]={rand(160),rand(96)} end
  end

  local GROUND_Y=118

  local function drawSky(timer)
    love.graphics.clear(0,0,0,1)
    love.graphics.push("all")
    for i,s in ipairs(STARS) do
      local twinkle=math.floor((timer+i*7)/24)%7
      love.graphics.setColor(1,1,1,(twinkle==0) and 0.35 or 1)
      love.graphics.rectangle("fill",s[1],s[2],1,1)
    end
    love.graphics.pop()
  end

  local function drawGround()
    love.graphics.push("all")
    love.graphics.setColor(0,0,0,1)
    love.graphics.rectangle("fill",0,GROUND_Y,160,144-GROUND_Y)
    love.graphics.setColor(1,1,1,1)
    love.graphics.rectangle("fill",0,GROUND_Y,160,1)
    -- Launch facility silhouette: outlines only, so the palette pass keeps it
    -- reading as a distant structure rather than a solid blob.
    local shapes={{8,104,18,14},{30,110,10,8},{116,100,16,18},{136,108,16,10}}
    for _,s in ipairs(shapes) do
      love.graphics.setColor(0,0,0,1)
      love.graphics.rectangle("fill",s[1],s[2],s[3],s[4])
      love.graphics.setColor(1,1,1,1)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line",s[1]+0.5,s[2]+0.5,s[3]-1,s[4]-1)
    end
    love.graphics.pop()
  end

  local function drawShip(cx,cy,scale,exhaust)
    love.graphics.push("all")
    love.graphics.translate(cx,cy)
    love.graphics.scale(scale,scale)
    love.graphics.setColor(1,1,1,1)
    love.graphics.rectangle("fill",-3,-9,6,18)
    love.graphics.polygon("fill",-3,-9,3,-9,0,-16)
    love.graphics.polygon("fill",-3,9,-3,3,-7,9)
    love.graphics.polygon("fill",3,9,3,3,7,9)
    if exhaust and exhaust>0 then
      local flare=6+exhaust*8
      love.graphics.polygon("fill",-3,9,3,9,0,9+flare)
      love.graphics.setColor(1,1,1,0.5)
      love.graphics.polygon("fill",-2,9+flare*0.4,2,9+flare*0.4,0,9+flare*1.5)
    end
    love.graphics.pop()
  end

  ----------------------------------------------------------------------
  -- Storage-system renderer.
  --
  -- Display geometry. Everything above the text frame belongs to the storage
  -- readout, so each block gets an explicit row and nothing can drift
  -- underneath the dialogue box.
  ----------------------------------------------------------------------
  local SYS_FRAME={2,2,156,84}
  local SYS_TITLE_Y,SYS_SUBTITLE_Y=6,16
  local SYS_STATUS_Y,SYS_STATUS_PITCH=30,10
  local SYS_ROLL_Y,SYS_ROLL_PITCH=68,10
  local SYS_ROLL_CLEAR={4,64,152,22}

  local dittoBattler=nil
  local dittoBattlerTried=false
  local function loadDittoBattler(game)
    if dittoBattlerTried then return dittoBattler end
    dittoBattlerTried=true
    local Sprites=safeRequire("src.pokemon.Sprites")
    local Assets=safeRequire("src.render.Assets")
    if not (Sprites and Assets and game and game.data) then return nil end
    local okPath,path=pcall(Sprites.path,game.data,"DITTO","front",{kind="battle"})
    if not okPath or not path then return nil end
    local okImg,img=pcall(Assets.image,path)
    if okImg and img then
      if img.setFilter then pcall(img.setFilter,img,"nearest","nearest") end
      dittoBattler=img
    end
    return dittoBattler
  end

  local function drawSystemChrome(timer,scroll)
    local F=cinema.font()
    love.graphics.clear(0,0,0,1)
    cinema.drawFrame(SYS_FRAME[1],SYS_FRAME[2],SYS_FRAME[3],SYS_FRAME[4])
    love.graphics.push("all")
    love.graphics.setColor(1,1,1,1)
    if F and F.draw then
      F.draw("POKeMON STORAGE",8,SYS_TITLE_Y)
      F.draw("CONSERVATION PROJ.",8,SYS_SUBTITLE_Y)
      local y=SYS_STATUS_Y
      for _,row in ipairs(SYSTEM_STATUS) do
        F.draw(row[1],8,y)
        local value=row[2]
        F.draw(value,150-cinema.measure(value),y)
        y=y+SYS_STATUS_PITCH
      end
      -- Slow record roll. The list is what is actually being preserved, so it
      -- moves at reading pace rather than as decoration. Stored Pokemon are
      -- listed by the name they were stored under, which is how the player
      -- finds PIXIE again.
      local records=SYSTEM_RECORDS
      local index=(math.floor((scroll or timer)/48)%#records)+1
      for i=0,1 do
        local rec=records[((index-1+i)%#records)+1]
        F.draw("BOX "..rec.box.."  "..(rec.nickname or rec.species),
          8,SYS_ROLL_Y+i*SYS_ROLL_PITCH)
      end
    end
    love.graphics.pop()
  end

  -- Replaces the record roll in place, so the status block above it stays on
  -- screen while the contingency readout is held.
  local function drawContingency()
    local F=cinema.font()
    love.graphics.push("all")
    love.graphics.setColor(0,0,0,1)
    love.graphics.rectangle("fill",
      SYS_ROLL_CLEAR[1],SYS_ROLL_CLEAR[2],SYS_ROLL_CLEAR[3],SYS_ROLL_CLEAR[4])
    love.graphics.setColor(1,1,1,1)
    if F and F.draw then
      for i,line in ipairs(SYSTEM_CONTINGENCY) do
        F.draw(line,8,SYS_ROLL_Y+(i-1)*SYS_ROLL_PITCH)
      end
    end
    love.graphics.pop()
  end

  -- The final image: the stored record itself. The battler is drawn on a lit
  -- plate and then dimmed with a slow pulse, so Ditto reads as present and
  -- intact but asleep rather than absent.
  local function drawDormantDitto(game,timer)
    local img=loadDittoBattler(game)
    love.graphics.clear(0,0,0,1)
    love.graphics.push("all")
    local pw,ph=72,72
    local px,py=math.floor((160-pw)/2),16
    love.graphics.setColor(1,1,1,1)
    love.graphics.rectangle("fill",px,py,pw,ph)
    love.graphics.setColor(0,0,0,1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line",px+0.5,py+0.5,pw-1,ph-1)
    if img then
      local iw,ih=img:getWidth(),img:getHeight()
      local scale=math.min((pw-8)/iw,(ph-8)/ih)
      love.graphics.setColor(1,1,1,1)
      love.graphics.draw(img,
        math.floor(px+(pw-iw*scale)/2),
        math.floor(py+(ph-ih*scale)/2),0,scale,scale)
    end
    -- Dormancy pulse: a slow breath rather than a blink.
    love.graphics.setColor(0,0,0,0.22+0.12*math.sin((timer or 0)/54))
    love.graphics.rectangle("fill",px,py,pw,ph)
    love.graphics.pop()
  end

  local logoImage=nil
  local function drawLogo(alpha)
    if not api.modPath then return false end
    if logoImage==nil then
      local ok,img=pcall(love.graphics.newImage,
        tostring(api.modPath).."/assets/pokopia_logo_dmg.png")
      if ok and img then
        if img.setFilter then pcall(img.setFilter,img,"nearest","nearest") end
        logoImage=img
      else
        logoImage=false
      end
    end
    if not logoImage then return false end
    local iw,ih=logoImage:getWidth(),logoImage:getHeight()
    local scale=math.min(120/iw,48/ih)
    love.graphics.push("all")
    love.graphics.setColor(1,1,1,alpha or 1)
    love.graphics.draw(logoImage,
      math.floor((160-iw*scale)/2),
      math.floor((144-ih*scale)/2),0,scale,scale)
    love.graphics.pop()
    return true
  end

  ----------------------------------------------------------------------
  -- The finale state machine.
  --
  -- One stack state owns the whole ending. Keeping it in a single opaque
  -- state means no half-torn-down overworld can draw underneath it, and a
  -- single `pop` at the end restores whatever the player was doing.
  ----------------------------------------------------------------------
  function self.play(game,opts)
    opts=opts or {}
    if not (game and game.stack) then return nil end

    local f=Finale.state(dataFor(game))
    f.running=true
    f.playCount=f.playCount+1

    cinema.silenceMusic(game)
    local restoreInput=cinema.lockOverworld(game)

    local startScene=SCENE_INDEX[tostring(opts.from or "DEPARTURE"):upper()] or 1

    local state={isOpaque=true}
    state.timer=0
    state.sceneIndex=startScene
    state.fade=0
    state.runner=nil
    state.mode=nil
    state.finished=false

    local enterScene

    local function advanceScene()
      state.sceneIndex=state.sceneIndex+1
      if state.sceneIndex>#Finale.SCENES then
        state.mode="END"
        state.timer=0
        return
      end
      enterScene(Finale.SCENES[state.sceneIndex])
    end

    enterScene=function(name)
      state.timer=0
      state.fade=0
      state.sceneIndex=SCENE_INDEX[name] or state.sceneIndex
      f.lastScene=name

      if name=="DEPARTURE" then
        state.mode="DEPARTURE"
        state.runner=cinema.newPageRunner(game,DEPARTURE)

      elseif name=="LIFTOFF" then
        state.mode="LIFTOFF_RISE"
        state.runner=nil
        -- The launch gets the Pokopia theme. It is stopped again the moment
        -- the Scientist appears, so LOG 568 plays in silence exactly like the
        -- opening does.
        cinema.playMusic(game,"Music_PokopiaTitleMashup","pokopia_finale")

      elseif name=="LOG568" then
        -- The recognition beat. Silence first, then the opening's exact
        -- presentation: black field, Scientist portrait, no nameplate.
        cinema.silenceMusic(game)
        state.mode="LOG568"
        f.logSeen=true
        state.runner=cinema.newPageRunner(game,Finale.SCRIPT.log568)

      elseif name=="SYSTEM" then
        state.mode="SYSTEM"
        state.runner=cinema.newPageRunner(game,SYSTEM_NARRATION)

      elseif name=="DORMANT" then
        state.mode="DORMANT"
        state.runner=cinema.newPageRunner(game,DORMANT)
      end
    end

    ------------------------------------------------------------------
    -- Update.
    ------------------------------------------------------------------
    local function pages(onExhausted)
      if state.runner and state.runner:update() then onExhausted() end
    end

    function state:update()
      self.timer=self.timer+1

      if self.mode=="DEPARTURE" then
        pages(function()
          -- Ease out of the lab before the exterior appears.
          self.mode="DEPARTURE_FADE"
          self.timer=0
        end)

      elseif self.mode=="DEPARTURE_FADE" then
        if self.timer>=48 then advanceScene() end

      elseif self.mode=="LIFTOFF_RISE" then
        -- Ignition, climb, then the vehicle becomes a point of light.
        if self.timer>=300 then
          self.mode="LIFTOFF_TEXT"
          self.timer=0
          self.runner=cinema.newPageRunner(game,LIFTOFF_CLOSING)
        end

      elseif self.mode=="LIFTOFF_TEXT" then
        pages(function()
          -- Step 2 of the brief: let the apparent success sit. Nothing is
          -- explained here, and the player is given no prompt to skip.
          self.mode="LIFTOFF_HOLD"
          self.timer=0
        end)

      elseif self.mode=="LIFTOFF_HOLD" then
        if self.timer>=150 then
          self.mode="TO_BLACK"
          self.timer=0
        end

      elseif self.mode=="TO_BLACK" then
        -- Step 3: fade completely to black, then hold on nothing before the
        -- Scientist appears.
        self.fade=math.min(1,self.timer/70)
        if self.timer>=70+60 then advanceScene() end

      elseif self.mode=="LOG568" then
        local page=self.runner and self.runner:current()
        if page and page.reveal=="fade" and self.timer<40 then
          -- Reproduces the opening step's `reveal="fade"`.
          self.fade=1-(self.timer/40)
          return
        end
        self.fade=0
        pages(function()
          self.mode="LOG_HOLD"
          self.timer=0
        end)

      elseif self.mode=="LOG_HOLD" then
        -- Step 8: hold on black for several seconds. Deliberately not
        -- skippable; the pause is doing the work here.
        if self.timer>=300 then advanceScene() end

      elseif self.mode=="SYSTEM" then
        self.fade=(self.timer<40) and (1-(self.timer/40)) or 0
        if self.timer>=40 then
          pages(function()
            self.mode="SYSTEM_CONTINGENCY"
            self.timer=0
          end)
        end

      elseif self.mode=="SYSTEM_CONTINGENCY" then
        -- Step 10: the contingency still exists. Shown, not narrated.
        if self.timer>=180 then
          self.mode="TO_DORMANT"
          self.timer=0
        end

      elseif self.mode=="TO_DORMANT" then
        self.fade=math.min(1,self.timer/40)
        if self.timer>=40+30 then advanceScene() end

      elseif self.mode=="DORMANT" then
        self.fade=(self.timer<40) and (1-(self.timer/40)) or 0
        if self.timer>=40 then
          pages(function()
            self.mode="DORMANT_HOLD"
            self.timer=0
          end)
        end

      elseif self.mode=="DORMANT_HOLD" then
        if self.timer>=220 then
          self.mode="OUTRO"
          self.timer=0
        end

      elseif self.mode=="OUTRO" then
        self.fade=math.min(1,self.timer/60)
        if self.timer>=60+40 then
          self.mode="END"
          self.timer=0
        end

      elseif self.mode=="END" then
        if self.timer>=180 then
          local input=game.input
          if input and (input:wasPressed("a") or input:wasPressed("b")) then
            self:close()
          end
        end
      end
    end

    function state:close()
      if self.finished then return end
      self.finished=true
      f.running=nil
      -- A developer scene jump replays the ending without consuming it, so
      -- the automatic trigger still fires on a normal playthrough afterward.
      if not opts.dev then f.completed=true end
      if game.stack:top()==self then game.stack:pop() end
      pcall(restoreInput)
      cinema.restoreMusic(game,"pokopia_finale")
      if opts.onFinish then pcall(opts.onFinish,game) end
    end

    ------------------------------------------------------------------
    -- Draw.
    ------------------------------------------------------------------
    function state:draw()
      local mode=self.mode

      if mode=="DEPARTURE" or mode=="DEPARTURE_FADE" then
        -- Inside the sealed system, looking out. A dark field with the storage
        -- frame around it and one indicator that is still alive.
        love.graphics.clear(0,0,0,1)
        cinema.drawFrame(6,6,148,B.y-12)
        if math.floor(self.timer/40)%2==0 then
          love.graphics.push("all")
          love.graphics.setColor(1,1,1,1)
          love.graphics.rectangle("fill",144,14,3,3)
          love.graphics.pop()
        end
        if mode=="DEPARTURE" then
          self.runner:draw(self.timer)
        else
          cinema.drawFade(math.min(1,self.timer/48))
        end
        return
      end

      if mode=="LIFTOFF_RISE" or mode=="LIFTOFF_TEXT"
          or mode=="LIFTOFF_HOLD" or mode=="TO_BLACK" then
        local t=(mode=="LIFTOFF_RISE") and self.timer or 300
        drawSky(self.timer)

        love.graphics.push("all")
        -- Ignition shake, strongest at the moment the engines catch.
        if mode=="LIFTOFF_RISE" and t>=48 and t<150 then
          local mag=math.max(0,1-(t-48)/102)*2
          love.graphics.translate(
            math.floor((math.random()*2-1)*mag),
            math.floor((math.random()*2-1)*mag))
        end

        drawGround()

        local padY=GROUND_Y-10
        if t<48 then
          drawShip(72,padY,1,0)
        else
          local p=math.min(1,(t-48)/252)
          local y=padY-(p*p*1.1)*(padY+56)
          if y>-24 then
            drawShip(72,y,math.max(0.18,1-p*0.82),0.6+0.4*math.sin(t/3))
          end
          if p>=0.85 then
            -- A single point of light, still climbing.
            love.graphics.setColor(1,1,1,(math.floor(t/14)%2==0) and 1 or 0.4)
            love.graphics.rectangle("fill",71,10,2,2)
          end
        end
        love.graphics.pop()

        if mode=="LIFTOFF_TEXT" then self.runner:draw(self.timer) end
        if mode=="TO_BLACK" then cinema.drawFade(self.fade) end
        return
      end

      if mode=="LOG568" then
        -- Step 4: the opening's visual language, reproduced exactly.
        love.graphics.clear(0,0,0,1)
        cinema.drawSpeakerArt(game,"SCIENTIST",1)
        self.runner:draw(self.timer)
        cinema.drawFade(self.fade)
        return
      end

      if mode=="LOG_HOLD" then
        love.graphics.clear(0,0,0,1)
        return
      end

      if mode=="SYSTEM" or mode=="SYSTEM_CONTINGENCY" or mode=="TO_DORMANT" then
        drawSystemChrome(self.timer,(mode=="SYSTEM") and self.timer or nil)
        if mode~="SYSTEM" then drawContingency() end
        if mode=="SYSTEM" then self.runner:draw(self.timer,true) end
        cinema.drawFade(self.fade)
        return
      end

      if mode=="DORMANT" or mode=="DORMANT_HOLD" or mode=="OUTRO" then
        drawDormantDitto(game,self.timer)
        if mode=="DORMANT" then self.runner:draw(self.timer,true) end
        cinema.drawFade(self.fade)
        return
      end

      -- END.
      love.graphics.clear(0,0,0,1)
      local shown=math.min(1,(self.timer or 0)/60)
      if not drawLogo(shown) then
        local F=cinema.font()
        if F and F.draw then
          love.graphics.push("all")
          love.graphics.setColor(1,1,1,shown)
          F.draw("POKOPIA",56,68)
          love.graphics.pop()
        end
      end
    end

    enterScene(Finale.SCENES[startScene])
    game.stack:push(state)
    return state
  end

  return self
end

return Finale
