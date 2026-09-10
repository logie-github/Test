--------------------------------------------------------------------------
-- Regression tests for the LOG 568 bookend.
--
-- Deliberately standalone: it stubs LOVE and the game stack instead of
-- booting Gen1Recomp, so the ending's script and its state machine can be
-- checked on any machine with a Lua interpreter.
--
--   lua5.1 tests/finale.lua      (run from the mod root)
--
-- What this file is actually protecting:
--
--   1. The bookend still quotes the opening verbatim and in order. If
--      someone edits the ending's first four pages, this fails.
--   2. The opening itself is still present and unmodified in main.lua. If
--      someone "tidies" the intro, this fails.
--   3. The ending preserves the ambiguity the source material leaves open --
--      no invented cause for the disasters, no explanation of why humanity
--      does not return, and no scene of humans returning successfully.
--   4. Every authored page fits the native 160x144 text frame.
--   5. The whole state machine runs to completion without touching a nil.
--------------------------------------------------------------------------

local failures=0
local checks=0

local function ok(cond,label)
  checks=checks+1
  if not cond then
    failures=failures+1
    io.write("  FAIL  ",label,"\n")
  end
end

local function eq(a,b,label)
  checks=checks+1
  if a~=b then
    failures=failures+1
    io.write("  FAIL  ",label,"\n")
    io.write("        expected: ",string.format("%q",tostring(b)),"\n")
    io.write("        actual:   ",string.format("%q",tostring(a)),"\n")
  end
end

local function readFile(path)
  local fh=io.open(path,"rb")
  if not fh then return nil end
  local body=fh:read("*a")
  fh:close()
  return body
end

--------------------------------------------------------------------------
-- Load the module under test.
--------------------------------------------------------------------------
local function loadModule(path)
  local chunk,err=loadfile(path)
  if not chunk then
    io.write("cannot load ",path,": ",tostring(err),"\n")
    os.exit(1)
  end
  return chunk()
end
local Cinema=loadModule("cinema.lua")
local Finale=loadModule("finale.lua")

-- The pure text helpers moved to cinema.lua when the Mansion cold open, the
-- Celadon chapter card and the ending were unified onto one presentation
-- system. The ending's own script is still checked through them here.
Finale.layout=Cinema.layout
Finale.pages=Cinema.pages

--------------------------------------------------------------------------
-- 1. Bookend fidelity.
--------------------------------------------------------------------------
io.write("bookend fidelity\n")
local log=Finale.SCRIPT.log568

for i,line in ipairs(Finale.OPENING_LINES) do
  eq(log[i] and log[i].text,line,"log page "..i.." quotes the opening verbatim")
  eq(log[i] and log[i].quoted,"opening","log page "..i.." is marked as a quote")
end

eq(log[1].reveal,"fade","the bookend re-uses the opening's fade reveal")

local total=#log
for i,line in ipairs(Finale.OPENING_CLOSING_LINES) do
  local page=log[total-#Finale.OPENING_CLOSING_LINES+i]
  eq(page and page.text,line,"the ending re-uses opening closing line "..i)
  eq(page and page.quoted,"opening","closing line "..i.." is marked as a quote")
end

ok(total>#Finale.OPENING_LINES+#Finale.OPENING_CLOSING_LINES,
  "the log continues past where the opening stopped")

--------------------------------------------------------------------------
-- 2. The opening in main.lua is untouched.
--------------------------------------------------------------------------
io.write("opening preserved in main.lua\n")
local main=readFile("main.lua")
ok(main~=nil,"main.lua is readable")
if main then
  ok(main:find('id="log568_a"',1,true)~=nil,"opening step log568_a still exists")
  ok(main:find('id="log568_b"',1,true)~=nil,"opening step log568_b still exists")
  ok(main:find('id="log568_c"',1,true)~=nil,"opening step log568_c still exists")
  ok(main:find('intro.oak_speech.build',1,true)~=nil,"OakSpeech content wrap intact")
  ok(main:find('OPP_SCIENTIST',1,true)~=nil,"Scientist portrait still used by the intro")
  -- main.lua holds these as Lua source, so a real newline in the quote is a
  -- literal backslash-n there.
  local function asSource(line) return (line:gsub("\n","\\n")) end
  for _,line in ipairs(Finale.OPENING_LINES) do
    ok(main:find(asSource(line),1,true)~=nil,
      "main.lua still contains: "..line:gsub("\n"," / "))
  end
  for _,line in ipairs(Finale.OPENING_CLOSING_LINES) do
    ok(main:find(asSource(line),1,true)~=nil,
      "main.lua still contains: "..line:gsub("\n"," / "))
  end
  -- The finale must actually be reachable from the game.
  ok(main:find("Finale.play(game",1,true)~=nil,"main.lua triggers the finale")
  ok(main:find("Finale.markPrequelComplete(game)",1,true)~=nil,
    "the Celadon chapter arms the finale")
  ok(main:find("finale.lua",1,true)~=nil,"main.lua loads finale.lua")
  ok(main:find("cinema.lua",1,true)~=nil,"main.lua loads cinema.lua")
  ok(main:find("Finale.shouldAutoPlay(game)",1,true)~=nil,
    "the ending is gated so it fires once")
  -- A save made before schema 5, or one quit mid-cutscene, must still reach
  -- the ending without replaying anything.
  ok(main:find("q.cardQuestComplete) and true or false",1,true)~=nil,
    "prequel completion is migrated from the pre-schema-5 flag")
  ok(main:find("not isMansion(ow.map.id)",1,true)~=nil,
    "the reconciliation trigger stays out of the Mansion timeline")
end

--------------------------------------------------------------------------
-- 3. Preserved ambiguity.
--------------------------------------------------------------------------
io.write("preserved ambiguity\n")

-- Words that would commit the story to a cause the Human Records leave
-- unresolved, or to a mechanism for humanity's failure to return.
local BANNED_CAUSE={
  "meteor","asteroid","comet","virus","plague","nuclear","reactor",
  "meltdown","war","weapon","alien","invasion","supernova","solar flare",
  "climate","greenhouse","because of","caused by","the cause was",
}
-- Phrases that would show humans coming back.
local BANNED_RETURN={
  "we returned","they returned","we came back","humanity returned",
  "the ships came back","rescue arrived","we made it back",
}

local function collect(beats,out)
  out=out or {}
  for _,beat in ipairs(beats) do out[#out+1]=tostring(beat.text or "") end
  return out
end

local allText={}
collect(Finale.SCRIPT.log568,allText)
collect(Finale.SCRIPT.departure,allText)
collect(Finale.SCRIPT.liftoffClosing,allText)
collect(Finale.SCRIPT.systemNarration,allText)
collect(Finale.SCRIPT.dormant,allText)
local function flatten(list)
  return (table.concat(list," "):gsub("[\n\f]"," "):gsub("%s+"," "):lower())
end
local blob=flatten(allText)

for _,word in ipairs(BANNED_CAUSE) do
  ok(blob:find(word,1,true)==nil,"no invented cause: '"..word.."'")
end
for _,phrase in ipairs(BANNED_RETURN) do
  ok(blob:find(phrase,1,true)==nil,"humans are never shown returning: '"..phrase.."'")
end

-- The contingency described in Giovanni's briefing must still be present.
local contingency=flatten(Finale.SCRIPT.systemContingency)
ok(contingency:find("armed",1,true)~=nil,"release contingency is still armed")
local narration=flatten(collect(Finale.SCRIPT.systemNarration))
ok(narration:find("contingency",1,true)~=nil,"the ending states the contingency survives")

-- The departure must carry the belief that the separation is temporary.
local departure=flatten(collect(Finale.SCRIPT.departure))
ok(departure:find("coming back",1,true)~=nil,"LOGAN still believes he is coming back")
ok(departure:find("return survey",1,true)~=nil,"the return survey is still scheduled")
-- ...and the log must revoke exactly that.
local logBlob=flatten(collect(Finale.SCRIPT.log568))
ok(logBlob:find("no return survey",1,true)~=nil,"the log revokes the return survey")

--------------------------------------------------------------------------
-- 4. Every page fits the native text frame.
--------------------------------------------------------------------------
io.write("text frame fit\n")
local function checkFit(name,beats)
  for _,page in ipairs(Finale.pages(beats)) do
    -- Ask for an unbounded row count so a page that overruns the frame shows
    -- up as "too many rows" rather than as silently dropped text.
    local rows=Finale.layout(page.text,20,99)
    ok(#rows>=1 and #rows<=3,name..": 1-3 rows for "..page.text:gsub("\n"," / "))
    -- Newly authored copy follows the project's hand-broken 18-character
    -- convention. Rows quoted from the opening are exempt: they ship as-is in
    -- the intro and must not be re-broken here.
    local budget=(page.quoted=="opening") and 20 or 18
    for _,row in ipairs(rows) do
      ok(#row<=budget,name..": row <="..budget.." chars ('"..row.."')")
    end
    local joined=table.concat(rows," "):gsub("%s+"," ")
    local source=page.text:gsub("\n"," "):gsub("%s+"," ")
    eq(joined,source,name..": no text lost in layout")
  end
end
checkFit("departure",Finale.SCRIPT.departure)
checkFit("liftoff",Finale.SCRIPT.liftoffClosing)
checkFit("log568",Finale.SCRIPT.log568)
checkFit("system",Finale.SCRIPT.systemNarration)
checkFit("dormant",Finale.SCRIPT.dormant)

for _,row in ipairs(Finale.SCRIPT.systemContingency) do
  ok(#row<=18,"contingency row fits: "..row)
end
for _,row in ipairs(Finale.SCRIPT.systemStatus) do
  ok(#row[1]+#row[2]<=18,"status row fits: "..row[1].." "..row[2])
end

-- Records are drawn as "BOX nn  NAME" on one row of the storage display.
local recordNames={}
local dittoRecord=nil
for _,rec in ipairs(Finale.SCRIPT.systemRecords) do
  local label="BOX "..rec.box.."  "..(rec.nickname or rec.species)
  ok(#label<=18,"record row fits: "..label)
  recordNames[rec.nickname or rec.species]=rec
  if rec.species=="DITTO" then dittoRecord=rec end
end
ok(recordNames.PIXIE~=nil,"PIXIE is still in the system the player put her in")
ok(dittoRecord~=nil,"DITTO is in the system")
ok(Finale.SCRIPT.systemRecords[#Finale.SCRIPT.systemRecords].species=="DITTO",
  "the record roll ends on DITTO")
if dittoRecord then
  eq(Finale.SCRIPT.dormant[1].text,"BOX "..dittoRecord.box..".",
    "the closing scene names DITTO's actual box")
end

--------------------------------------------------------------------------
-- 5. Pure helpers.
--------------------------------------------------------------------------
io.write("pure helpers\n")
local split=Finale.pages({{speaker="LOGAN",text="one\ftwo"}})
eq(#split,2,"a form-feed becomes two pages")
eq(split[1].text,"one","first page text")
eq(split[2].speaker,"LOGAN","speaker carries to every page of a beat")

local wrapped=Finale.layout("aaaaaaaaaa bbbbbbbbbb cccccccccc",18)
eq(#wrapped,3,"long text wraps to three rows")
ok(#wrapped[1]<=18,"wrapped row respects the interior width")

-- Authored line breaks are honoured even when the row would also fit joined.
local kept=Finale.layout("one\ntwo\nthree",20,99)
eq(#kept,3,"authored newlines are never re-flowed")

-- A caller-supplied measure drives the wrap, which is how the runtime uses
-- the engine font's real advance widths.
local charWrapped=Finale.layout("abcd efgh",6,99)
eq(#charWrapped,2,"a tight character budget wraps")
local pixelWrapped=Finale.layout("abcd efgh",40,99,function(s) return #s*4 end)
eq(#pixelWrapped,1,"a caller-supplied measure drives the wrap instead")

local q={}
local f1=Finale.state(q)
f1.prequelComplete=true
q.somethingUnrelated="keep me"
local f2=Finale.state(q)
eq(f2.prequelComplete,true,"finale state is stable across normalization")
eq(q.somethingUnrelated,"keep me","normalization never drops unrelated fields")
eq(f1,f2,"finale state is not re-created on each call")

--------------------------------------------------------------------------
-- 6. Headless run of the whole state machine.
--------------------------------------------------------------------------
io.write("headless run\n")

local drawCalls=0
local function nop() end
love={
  graphics={
    clear=nop,setColor=nop,rectangle=function() drawCalls=drawCalls+1 end,
    polygon=nop,push=nop,pop=nop,translate=nop,scale=nop,setLineWidth=nop,
    draw=nop,setShader=nop,
    newImage=function() error("no image backend in tests") end,
    newShader=function() error("no shader backend in tests") end,
  },
  math={random=function(m) return m and 1 or 0.5 end},
}

-- A Font stub lets the headless run exercise the real text paths and record
-- exactly where every string lands, which is the only way to catch a layout
-- row drifting under the dialogue frame without booting the engine.
local drawn={}
local FontStub={
  drawBox=nop,
  draw=function(text,x,y) drawn[#drawn+1]={text=tostring(text),x=x,y=y} end,
  width=function(s) return #tostring(s)*8 end,
}
local realRequire=require
require=function(name)
  if name=="src.render.Font" then return FontStub end
  return realRequire(name)
end

local function newGame(pressed)
  local stack={items={}}
  function stack:push(s) self.items[#self.items+1]=s end
  function stack:pop() local s=self.items[#self.items]; self.items[#self.items]=nil; return s end
  function stack:top() return self.items[#self.items] end
  return {
    data={},
    stack=stack,
    input={wasPressed=function(_,_) return pressed end},
    save={modData={}},
  }
end

local allDrawn={}

local function runFinale(opts,pressed)
  local store={}
  local runtime=Finale.new({
    data=function() return store end,
    modPath=".",
    cinema=Cinema.new({}),
  })
  local game=newGame(pressed~=false)
  local state=runtime.play(game,opts)
  local seen={}
  local frames=0
  while state and not state.finished and frames<40000 do
    frames=frames+1
    local okUpdate,updateErr=pcall(function() state:update() end)
    if not okUpdate then
      failures=failures+1
      io.write("  FAIL  update error at frame ",frames,": ",tostring(updateErr),"\n")
      break
    end
    local okDraw,drawErr=pcall(function() state:draw() end)
    if not okDraw then
      failures=failures+1
      io.write("  FAIL  draw error at frame ",frames,": ",tostring(drawErr),"\n")
      break
    end
    if state.mode then seen[state.mode]=true end
    for _,d in ipairs(drawn) do d.mode=state.mode end
    for i=1,#drawn do allDrawn[#allDrawn+1]=drawn[i] end
    for i=#drawn,1,-1 do drawn[i]=nil end
  end
  return runtime,store,game,state,seen,frames
end

local runtime,store,game,state,seen,frames=runFinale(nil,true)
ok(state~=nil,"play() returns a state")
ok(state and state.finished,"the finale runs to completion")
ok(frames<40000,"the finale terminates (frames="..tostring(frames)..")")
ok(drawCalls>0,"the finale actually draws")
eq(#game.stack.items,0,"the finale pops itself off the stack")

for _,mode in ipairs({
  "DEPARTURE","LIFTOFF_RISE","LIFTOFF_TEXT","LIFTOFF_HOLD","TO_BLACK",
  "LOG568","LOG_HOLD","SYSTEM","SYSTEM_CONTINGENCY","DORMANT","OUTRO","END",
}) do
  ok(seen[mode],"the run passes through "..mode)
end

-- Every string must land inside the 160x144 viewport, and must sit either
-- fully above the dialogue frame (chrome) or on one of its interior rows
-- (dialogue). Anything in between would be drawn under the frame border.
--
-- Rows quoted verbatim from the opening are exempt from the horizontal check
-- and only from that one. The harness measures a worst-case fixed 8px glyph;
-- the real engine font is proportional, which is why `Font.width` exists and
-- why the shipped intro renders a 20-character row such as
-- "Hail Mary project..." without incident. The bookend reproduces those rows
-- exactly rather than re-breaking them, so under the harness's pessimistic
-- measure they overhang by design. Everything this project authors itself is
-- still held to the strict edge.
local openingRows={}
for _,group in ipairs({Finale.OPENING_LINES,Finale.OPENING_CLOSING_LINES}) do
  for _,line in ipairs(group) do
    for row in (line.."\n"):gmatch("(.-)\n") do
      if row~="" then openingRows[#openingRows+1]=row end
    end
  end
end
local function isOpeningPrefix(text)
  for _,row in ipairs(openingRows) do
    if row:sub(1,#text)==text then return true end
  end
  return false
end

local outOfBounds,inDeadBand=nil,nil
for _,d in ipairs(allDrawn) do
  local w=#d.text*8
  if not outOfBounds and not isOpeningPrefix(d.text)
      and (d.x<0 or d.x+w>160 or d.y<0 or d.y+8>144) then
    outOfBounds=d
  end
  -- Quoted rows are still held to the vertical bounds and to the row grid.
  if not outOfBounds and isOpeningPrefix(d.text) and (d.x<0 or d.y<0 or d.y+8>144) then
    outOfBounds=d
  end
  if not inDeadBand and not (d.y+8<=88 or d.y>=96) then
    inDeadBand=d
  end
end
ok(#allDrawn>0,"the headless run drew text (n="..tostring(#allDrawn)..")")
ok(outOfBounds==nil,"every string fits the 160x144 viewport"..
  (outOfBounds and (": '"..outOfBounds.text.."' at "..outOfBounds.x..","..
   outOfBounds.y.." in "..tostring(outOfBounds.mode)) or ""))
ok(inDeadBand==nil,"no string is drawn under the dialogue frame border"..
  (inDeadBand and (": '"..inDeadBand.text.."' at y="..inDeadBand.y..
   " in "..tostring(inDeadBand.mode)) or ""))

local finState=Finale.state(store)
eq(finState.completed,true,"a normal run marks the ending complete")
eq(finState.logSeen,true,"a normal run records that LOG 568 was seen")
eq(finState.running,nil,"the running flag is cleared on close")

--------------------------------------------------------------------------
-- 7. Trigger gating and developer replay.
--------------------------------------------------------------------------
io.write("trigger gating\n")
local gate={}
local gateRuntime=Finale.new({data=function() return gate end,cinema=Cinema.new({})})
eq(gateRuntime.shouldAutoPlay({}),false,"the ending does not fire before the prequel")
gateRuntime.markPrequelComplete({})
eq(gateRuntime.shouldAutoPlay({}),true,"the ending arms once the prequel is finished")
Finale.state(gate).completed=true
eq(gateRuntime.shouldAutoPlay({}),false,"the ending never fires twice")

local _,devStore=runFinale({dev=true,from="LOG568"},true)
eq(Finale.state(devStore).completed,false,
  "a developer scene jump does not consume the real ending")
eq(Finale.state(devStore).logSeen,true,"a LOG568 jump still records the log")

--------------------------------------------------------------------------
io.write("\n")
if failures>0 then
  io.write(("finale: %d/%d checks failed\n"):format(failures,checks))
  os.exit(1)
end
io.write(("finale: %d checks passed\n"):format(checks))
