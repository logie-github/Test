--------------------------------------------------------------------------
-- Pokopia: Log 568 -- shared Gen I cinematic presentation.
--
-- One presentation system for every authored cutscene in the project: the
-- Mansion cold open, the Celadon chapter card and montage, and the LOG 568
-- bookend finale. Before this module each of those either hand-rolled its own
-- drawing or, in the case of `Much earlier...`, fell back to a bare
-- `love.graphics.printf` with no Gen I font at all.
--
-- Two halves, deliberately separated:
--
--   * Pure helpers (`Cinema.layout`, `Cinema.pages`) have no LOVE or engine
--     dependency and are unit-tested directly.
--   * `Cinema.new(api)` returns the renderer and the page runner. Every
--     engine touch point is injected or `pcall`-guarded, so a host build
--     missing an optional module degrades instead of crashing.
--
-- Geometry note that the whole file depends on: the native viewport is
-- 160x144 and a `Font.drawBox(tx,ty,tw,th)` frame owns one tile of border, so
-- a box at ty=11 has interior rows at y=96, 112 and 128. Three rows is what
-- the opening LOG 568 page needs, which is why the cinematic frame is one
-- tile taller than the standard dialogue box.
--------------------------------------------------------------------------

local Cinema={}

Cinema.VERSION=1

--------------------------------------------------------------------------
-- Frame geometry.
--------------------------------------------------------------------------
Cinema.SCREEN_W,Cinema.SCREEN_H=160,144

Cinema.BOX={tx=0,ty=11,tw=20,th=7}
Cinema.BOX.x=Cinema.BOX.tx*8
Cinema.BOX.y=Cinema.BOX.ty*8
Cinema.BOX.w=Cinema.BOX.tw*8
Cinema.BOX.h=Cinema.BOX.th*8
Cinema.BOX.textX=Cinema.BOX.x+8
Cinema.BOX.rows={Cinema.BOX.y+8,Cinema.BOX.y+24,Cinema.BOX.y+40}
-- Pixel width available to text inside the frame.
Cinema.BOX.textPixels=Cinema.BOX.w-16

-- Default character budget when no font is available to measure with. 20 is
-- what the shipped OakSpeech opening already demonstrates fits: its
-- "Hail Mary project..." row is exactly 20 characters.
Cinema.DEFAULT_WIDTH=20
Cinema.MAX_ROWS=3

--------------------------------------------------------------------------
-- Pure helpers.
--------------------------------------------------------------------------

-- Split an authored page into rendered rows.
--
-- Authored `\n` breaks are always honoured: hand-broken pages must render
-- exactly as authored. The wrap is only a backstop for a future edit that
-- overruns the frame.
function Cinema.layout(text,maxWidth,maxRows,measure)
  maxWidth=maxWidth or Cinema.DEFAULT_WIDTH
  maxRows=maxRows or Cinema.MAX_ROWS
  measure=measure or function(s) return #s end
  local rows={}
  for chunk in (tostring(text or "").."\n"):gmatch("(.-)\n") do
    if measure(chunk)<=maxWidth then
      rows[#rows+1]=chunk
    else
      local current=""
      for word in chunk:gmatch("%S+") do
        local candidate=(current=="") and word or (current.." "..word)
        if measure(candidate)>maxWidth and current~="" then
          rows[#rows+1]=current
          current=word
        else
          current=candidate
        end
      end
      if current~="" then rows[#rows+1]=current end
    end
  end
  while #rows>0 and rows[#rows]=="" do rows[#rows]=nil end
  while #rows>maxRows do rows[#rows]=nil end
  return rows
end

-- Authored rows exactly as written, honouring every `\n` and wrapping nothing.
function Cinema.authoredRows(text,maxRows)
  return Cinema.layout(text,math.huge,maxRows or Cinema.MAX_ROWS)
end

-- Flatten a beat list into single pages. Authored beats may contain `\f` page
-- breaks so they read like the rest of the project's dialogue; every other
-- field on the beat is carried onto each page it produces.
function Cinema.pages(beats)
  local out={}
  for _,beat in ipairs(beats or {}) do
    local text=tostring(beat.text or "")
    local start=1
    while true do
      local cut=text:find("\f",start,true)
      local part=cut and text:sub(start,cut-1) or text:sub(start)
      if part~="" then
        out[#out+1]={
          text=part,
          speaker=beat.speaker,
          reveal=beat.reveal,
          quoted=beat.quoted,
          hold=beat.hold,
          dark=beat.dark,
        }
      end
      if not cut then break end
      start=cut+1
    end
  end
  return out
end

--------------------------------------------------------------------------
-- Runtime.
--------------------------------------------------------------------------

local function noop() end

local function safeRequire(name)
  local ok,value=pcall(require,name)
  if ok then return value end
  return nil
end

Cinema.safeRequire=safeRequire

function Cinema.new(api)
  api=api or {}
  local trainerImage=api.trainerImage or function() return nil,nil end
  local trainerMaskShader=api.trainerMaskShader or function() return nil end
  local stopAlarm=api.stopAlarm or noop

  local self={}
  self.api=api
  self.layout=Cinema.layout
  self.pages=Cinema.pages
  self.BOX=Cinema.BOX

  ----------------------------------------------------------------------
  -- Engine accessors.
  ----------------------------------------------------------------------
  local function Font() return safeRequire("src.render.Font") end
  self.font=Font

  function self.measure(s)
    local F=Font()
    if F and F.width then
      local ok,w=pcall(F.width,tostring(s))
      if ok and tonumber(w) then return tonumber(w) end
    end
    return #tostring(s)*8
  end

  -- Rows for a page, measured against the frame's real pixel interior using
  -- the engine font's own advance widths.
  --
  -- The authored line breaks always win. The wrap is a backstop for a future
  -- edit that overruns the frame, and it is only accepted when it actually
  -- helps -- that is, when the wrapped result still fits the three interior
  -- rows. If wrapping would need a fourth row, the authored breaks are used
  -- instead, because clamping a wrapped result to three rows silently deletes
  -- the end of the page.
  --
  -- This is not hypothetical. The opening OakSpeech page
  -- "Life on this planet / as we know it will / come to an end." is already
  -- three authored rows, and its first row is 19 characters. Under any
  -- measure that calls 19 characters too wide, wrapping produces four rows
  -- and the bookend would lose "come to an end." -- the single most important
  -- line in the ending.
  function self.rowsFor(page)
    local authored=Cinema.authoredRows(page.text,Cinema.MAX_ROWS)
    -- A page quoted from the opening is never re-broken, at any width. The
    -- bookend's whole job is to reproduce the intro's presentation exactly,
    -- and the intro renders these rows as authored; re-wrapping "Our
    -- last-ditch / Hail Mary project..." into three rows would still say the
    -- right words while no longer looking like the scene it is quoting.
    if page.quoted then return authored end
    local F=Font()
    if not (F and F.width and pcall(F.width,"M")) then return authored end
    local fitted=Cinema.layout(page.text,Cinema.BOX.textPixels,
      Cinema.MAX_ROWS+1,self.measure)
    if #fitted<=Cinema.MAX_ROWS then return fitted end
    return authored
  end

  function self.textLength(page)
    local n=0
    for _,row in ipairs(self.rowsFor(page)) do n=n+#row end
    return n
  end

  ----------------------------------------------------------------------
  -- Audio. Gen1Recomp builds differ on which of these entry points exist,
  -- so every call is guarded and the caller never has to care.
  ----------------------------------------------------------------------
  function self.beep(game)
    local Sound=safeRequire("src.core.Sound")
    if Sound and Sound.play and game and game.data then
      pcall(Sound.play,game.data,"Press_AB")
    end
  end

  function self.playSfx(game,id)
    local Sound=safeRequire("src.core.Sound")
    if Sound and Sound.play and game and game.data and id then
      pcall(Sound.play,game.data,id)
    end
  end

  function self.silenceMusic(game)
    pcall(stopAlarm,game)
    local Sound=safeRequire("src.core.Sound")
    if Sound and Sound.stopLoop then pcall(Sound.stopLoop,"Low_Health_Alarm") end
    local Music=safeRequire("src.core.Music")
    if not Music then return end
    if Music.stop then
      if pcall(Music.stop,game and game.data) then return end
      if pcall(Music.stop) then return end
    end
    if Music.play then pcall(Music.play,game and game.data,nil) end
  end

  function self.playMusic(game,id,reason)
    local Music=safeRequire("src.core.Music")
    if not (Music and Music.play and game and game.data and id) then return false end
    return pcall(Music.play,game.data,id,true,{reason=reason or "pokopia_cinema"}) and true or false
  end

  function self.restoreMusic(game,reason)
    local Music=safeRequire("src.core.Music")
    if Music and Music.restoreMap and game and game.data then
      pcall(Music.restoreMap,game.data,reason or "pokopia_cinema")
    end
  end

  ----------------------------------------------------------------------
  -- Drawing primitives.
  ----------------------------------------------------------------------
  function self.drawFade(alpha)
    if not alpha or alpha<=0 then return end
    love.graphics.push("all")
    love.graphics.setColor(0,0,0,math.min(1,alpha))
    love.graphics.rectangle("fill",0,0,Cinema.SCREEN_W,Cinema.SCREEN_H)
    love.graphics.pop()
  end

  function self.drawFrame(x,y,w,h)
    love.graphics.push("all")
    love.graphics.setColor(1,1,1,1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line",x+0.5,y+0.5,w-1,h-1)
    love.graphics.pop()
  end

  -- Trainer-class cutout, positioned exactly the way the mod's dialogue
  -- renderer positions it: bottom-anchored, right-aligned to the text frame,
  -- drawn at 2x behind the box.
  function self.drawSpeakerArt(game,speaker,alpha)
    local img,mask=trainerImage(game,speaker)
    if not img then return false end
    local iw,ih=img:getWidth(),img:getHeight()
    local scale=2
    local x=math.floor(Cinema.BOX.x+Cinema.BOX.w-iw*scale)
    local y=math.floor(Cinema.SCREEN_H-ih*scale)
    love.graphics.push("all")
    love.graphics.setColor(1,1,1,alpha or 1)
    local shader=mask and trainerMaskShader() or nil
    if shader and mask then
      pcall(shader.send,shader,"cutoutMask",mask)
      love.graphics.setShader(shader)
      love.graphics.draw(img,x,y,0,scale,scale)
      love.graphics.setShader()
    else
      love.graphics.draw(img,x,y,0,scale,scale)
    end
    love.graphics.pop()
    return true
  end

  -- Speaker plate, matching `drawSpeakerMeta` in main.lua so a cinematic line
  -- is presentationally identical to ordinary game dialogue. Scenes that quote
  -- OakSpeech deliberately pass no speaker, because OakSpeech has no plate.
  function self.drawNameplate(speaker)
    if not speaker or speaker=="" then return end
    local F=Font()
    local label=tostring(speaker)
    local w=math.max(36,math.min(Cinema.BOX.w-8,self.measure(label)+10))
    local x,y=Cinema.BOX.x+4,Cinema.BOX.y-14
    love.graphics.push("all")
    love.graphics.setColor(1,1,1,1)
    love.graphics.rectangle("fill",x,y,w,12)
    love.graphics.setColor(0,0,0,1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line",x,y,w,12)
    if F and F.draw then F.draw(label,x+5,y+3) end
    love.graphics.pop()
  end

  -- Gen I text frame with a typewriter reveal and a blinking advance cursor.
  -- `dark` renders the machine-voice variant used by the storage system:
  -- white glyphs on black instead of black glyphs on white.
  function self.drawTextFrame(page,revealed,timer,dark)
    local F=Font()
    if not F then return end
    local B=Cinema.BOX
    local rows=self.rowsFor(page)

    love.graphics.push("all")
    if dark then
      love.graphics.setColor(0,0,0,1)
      love.graphics.rectangle("fill",B.x,B.y,B.w,B.h)
      love.graphics.setColor(1,1,1,1)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line",B.x+2.5,B.y+2.5,B.w-5,B.h-5)
      love.graphics.setColor(1,1,1,1)
    else
      if F.drawBox then F.drawBox(B.tx,B.ty,B.tw,B.th) end
      love.graphics.setColor(0,0,0,1)
    end

    local budget=math.floor(revealed or 0)
    local shown,full=0,0
    for _,row in ipairs(rows) do full=full+#row end
    for i,row in ipairs(rows) do
      if budget<=0 then break end
      local take=math.min(#row,budget)
      budget=budget-take
      shown=shown+take
      if take>0 and F.draw and B.rows[i] then
        F.draw(row:sub(1,take),B.textX,B.rows[i])
      end
    end

    if shown>=full and math.floor((timer or 0)/20)%2==0 then
      local cx,cy=B.x+B.w-14,B.y+B.h-12
      love.graphics.polygon("fill",cx,cy,cx+6,cy,cx+3,cy+5)
    end
    love.graphics.pop()

    if not dark then self.drawNameplate(page.speaker) end
  end

  ----------------------------------------------------------------------
  -- Chapter / location card.
  --
  -- The project previously drew `Much earlier...` with a raw
  -- `love.graphics.printf`, which uses LOVE's default font rather than the
  -- game's, and sat on the screen with nothing around it. This draws a real
  -- composed card in the Gen I font: centred lines between two rules, with a
  -- reveal that can be driven either as a fade or line by line.
  ----------------------------------------------------------------------
  function self.drawCard(lines,opts)
    opts=opts or {}
    local F=Font()
    -- A card drawn by an opaque state owns the frame and clears it. A card
    -- drawn over a live map (the Mansion cold open) has already covered the
    -- screen with `drawFade(1)` and must not clear, so the same card can
    -- dissolve into the room underneath it on the next phase.
    if opts.clear~=false then love.graphics.clear(0,0,0,1) end
    if not (F and F.draw) then return end

    local n=#lines
    if n==0 then return end
    local pitch=opts.pitch or 14
    local blockH=n*pitch-(pitch-8)
    local top=math.floor(opts.y or ((Cinema.SCREEN_H-blockH)/2))

    local widest=0
    for _,line in ipairs(lines) do
      local w=self.measure(line)
      if w>widest then widest=w end
    end

    local alpha=opts.alpha
    if alpha==nil then alpha=1 end
    alpha=math.max(0,math.min(1,alpha))

    love.graphics.push("all")

    -- Rules and text carry independent alpha so a card can assemble: the
    -- rules draw on first, then the text fades up between them.
    local ruleAlpha=opts.ruleAlpha
    if ruleAlpha==nil then ruleAlpha=alpha end

    if opts.rules~=false and ruleAlpha>0 then
      -- Rule width is keyed to the widest line, so a one-word card and a
      -- two-line location card both stay visually balanced.
      local grow=opts.ruleGrow
      if grow==nil then grow=1 end
      grow=math.max(0,math.min(1,grow))
      local fullW=math.min(Cinema.SCREEN_W-32,widest+24)
      local ruleW=math.max(2,math.floor(fullW*grow))
      local ruleX=math.floor((Cinema.SCREEN_W-ruleW)/2)
      love.graphics.setColor(1,1,1,ruleAlpha)
      love.graphics.rectangle("fill",ruleX,top-9,ruleW,1)
      love.graphics.rectangle("fill",ruleX,top+blockH+8,ruleW,1)
    end

    if alpha>0 then
      love.graphics.setColor(1,1,1,alpha)
      for i,line in ipairs(lines) do
        F.draw(line,math.floor((Cinema.SCREEN_W-self.measure(line))/2),
          top+(i-1)*pitch)
      end
    end
    love.graphics.pop()
  end

  ----------------------------------------------------------------------
  -- Page runner.
  --
  -- Shared by every scene that pages authored dialogue: reveal at Gen I
  -- speed, let A or B complete the reveal, then advance on the next press.
  -- `wasPressed` is edge-triggered by the engine, so holding A cannot blow
  -- through a scene.
  ----------------------------------------------------------------------
  local Runner={}
  Runner.__index=Runner

  function Runner:current()
    return self.pages[self.index]
  end

  function Runner:isDone()
    return self.index>#self.pages
  end

  -- Returns true once the beat list is exhausted.
  function Runner:update()
    local page=self:current()
    if not page then return true end

    local full=self.cinema.textLength(page)
    local input=self.game and self.game.input
    local pressed=input and (input:wasPressed("a") or input:wasPressed("b"))

    if self.reveal<full then
      self.reveal=self.reveal+self.speed
      if pressed then self.reveal=full end
      return false
    end

    if pressed then
      self.cinema.beep(self.game)
      self.index=self.index+1
      self.reveal=0
      return self:current()==nil
    end
    return false
  end

  function Runner:draw(timer,dark)
    local page=self:current()
    if not page then return end
    self.cinema.drawTextFrame(page,self.reveal,timer,dark or page.dark)
  end

  function self.newPageRunner(game,beats,opts)
    opts=opts or {}
    return setmetatable({
      cinema=self,
      game=game,
      pages=Cinema.pages(beats),
      index=1,
      reveal=0,
      -- Two frames per character, matching the engine's normal text speed.
      speed=opts.speed or 0.5,
    },Runner)
  end

  ----------------------------------------------------------------------
  -- Overworld input lock, used by every cutscene that plays over a live map.
  ----------------------------------------------------------------------
  function self.lockOverworld(game)
    local ow=api.overworld and api.overworld(game) or nil
    if not (ow and ow.player) then return noop end
    local previousInput=ow.player.inputLocked
    local previousFrozen=ow.player.frozen
    ow.player.inputLocked=true
    return function()
      if not ow.player then return end
      ow.player.inputLocked=previousInput
      ow.player.frozen=previousFrozen
    end
  end

  return self
end

return Cinema
