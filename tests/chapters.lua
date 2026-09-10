--------------------------------------------------------------------------
-- Regression tests for chapters.lua -- the Mansion cold open and the
-- Celadon chapter opening.
--
-- What this file is protecting:
--
--   1. The composition. The Mansion opening asks what a DITTO is doing in
--      that building; the Celadon opening answers it one chapter later. That
--      pairing is the same structural move LOG 568 makes across the whole
--      game, and it is easy to erase with a well-meaning copy edit.
--   2. `Much earlier...` survives verbatim. It is the story's own chronology
--      marker and predates this module.
--   3. Every authored row fits the native text frame.
--   4. The cold open never lands on a save that is already inside the story.
--   5. The state machines run to completion and restore player input.
--   6. main.lua actually reaches both openings -- including the Celadon
--      camera sweep, which existed in the project for months without ever
--      being reachable.
--
--   lua5.1 tests/chapters.lua      (from the mod root)
--------------------------------------------------------------------------

local S=dofile("tests/support.lua")
local ok,eq=S.ok,S.eq
local Cinema=S.loadModule("cinema.lua")
local Chapters=S.loadModule("chapters.lua")

--------------------------------------------------------------------------
-- 1. Chapter cards.
--------------------------------------------------------------------------
S.section("chapter cards")

eq(#Chapters.MANSION_CARD,2,"the Mansion card is two lines")
eq(#Chapters.CELADON_CARD,2,"the Celadon card is two lines")
eq(Chapters.MANSION_CARD[1],"CINNABAR ISLAND","Mansion card names the island")
eq(Chapters.MANSION_CARD[2],"POKeMON MANSION","Mansion card names the building")
eq(Chapters.CELADON_CARD[1],"CELADON CITY","Celadon card names the city")
-- This exact string predates the module and is the story's chronology marker.
eq(Chapters.CELADON_CARD[2],"Much earlier...",
  "the Celadon card preserves the original intertitle verbatim")

-- Both cards are where/when pairs, so they must be structurally parallel.
eq(#Chapters.MANSION_CARD,#Chapters.CELADON_CARD,
  "both chapter cards have the same shape")

for _,card in ipairs({Chapters.MANSION_CARD,Chapters.CELADON_CARD}) do
  for _,line in ipairs(card) do
    ok(#line<=18,"card line fits the frame: "..line)
    ok(not line:find("\n",1,true),"card lines carry no embedded breaks: "..line)
  end
end

--------------------------------------------------------------------------
-- 2. Authored beats fit the native frame.
--------------------------------------------------------------------------
S.section("text frame fit")

local function checkFit(name,beats)
  for _,page in ipairs(Cinema.pages(beats)) do
    -- Unbounded row count, so an overrun shows up as "too many rows" rather
    -- than as silently dropped text.
    local rows=Cinema.layout(page.text,20,99)
    ok(#rows>=1 and #rows<=3,name..": 1-3 rows for "..page.text:gsub("\n"," / "))
    for _,row in ipairs(rows) do
      ok(#row<=18,name..": row <=18 chars ('"..row.."')")
    end
    local joined=table.concat(rows," "):gsub("%s+"," ")
    local source=page.text:gsub("\n"," "):gsub("%s+"," ")
    eq(joined,source,name..": no text lost in layout")
  end
end
checkFit("mansion opening",Chapters.MANSION_OPENING)
checkFit("celadon montage",Chapters.CELADON_MONTAGE)

--------------------------------------------------------------------------
-- 3. The composition.
--------------------------------------------------------------------------
S.section("composition")

local mansion=S.flatten(Chapters.MANSION_OPENING)
local celadon=S.flatten(Chapters.CELADON_MONTAGE)

eq(#Chapters.MANSION_OPENING,4,"the Mansion opening is four beats")
eq(#Chapters.CELADON_MONTAGE,3,"the montage has one beat per camera shot")

-- The question and its answer. Both name DITTO; neither has a speaker,
-- because no character in either scene is addressing the player.
ok(mansion:find("ditto",1,true)~=nil,"the Mansion opening names DITTO")
ok(celadon:find("ditto",1,true)~=nil,"the Celadon opening names DITTO")
ok(mansion:find("what a ditto\nis doing here",1,true)~=nil
  or mansion:find("what a ditto is doing here",1,true)~=nil,
  "the Mansion opening asks why a DITTO is there")
ok(celadon:find("somewhere in that crowd is a ditto",1,true)~=nil,
  "the Celadon opening answers it")

for _,beat in ipairs(Chapters.MANSION_OPENING) do
  eq(beat.speaker,nil,"Mansion opening beats are narration, not dialogue")
end
for _,beat in ipairs(Chapters.CELADON_MONTAGE) do
  eq(beat.speaker,nil,"montage beats are narration, not dialogue")
end

-- No human in the Mansion may identify the player. The project's existing
-- rule; the cold open names DITTO only in narration, never in a quoted line.
for _,beat in ipairs(Chapters.MANSION_OPENING) do
  ok(not tostring(beat.text):find(":",1,true),
    "no Mansion opening beat is attributed speech")
end

-- The two openings must not sound like each other. The Mansion is an alarm
-- and people who will not look down; Celadon is an ordinary loud afternoon.
ok(mansion:find("alarm",1,true)~=nil,"the Mansion opening establishes the alarm")
ok(celadon:find("alarm",1,true)==nil,"the Celadon opening carries no alarm")
ok(celadon:find("loud",1,true)~=nil,"the Celadon opening establishes an ordinary city")

--------------------------------------------------------------------------
-- 4. Save state and cold-open gating.
--------------------------------------------------------------------------
S.section("state and gating")

local fresh={}
local c=Chapters.state(fresh)
eq(c.mansionOpeningSeen,false,"a fresh save has not seen the cold open")
eq(c.celadonOpeningSeen,false,"a fresh save has not seen the Celadon opening")
fresh.unrelated="keep me"
Chapters.state(fresh)
eq(fresh.unrelated,"keep me","normalization never drops unrelated fields")
eq(Chapters.state(fresh),c,"state is not re-created on each call")

eq(Chapters.hasProgress({}),false,"an empty save shows no progress")
eq(Chapters.hasProgress({distractionDone=true}),true,"a story flag counts as progress")
eq(Chapters.hasProgress({cardQuestComplete=true}),true,"Celadon progress counts")
eq(Chapters.hasProgress({forms={PERSIAN=true}}),true,"a learned form counts as progress")
eq(Chapters.hasProgress({forms={}}),false,"an empty form table is not progress")
eq(Chapters.hasProgress(nil),false,"a nil save is handled")

S.install()
local cinema=Cinema.new({})

local function runtimeFor(store)
  return Chapters.new({data=function() return store end,cinema=cinema})
end

local newSave={}
local newRuntime=runtimeFor(newSave)
eq(newRuntime.shouldPlayMansionOpening({}),true,"a new game gets the cold open")

local inProgress={giovanniMeetingDone=true}
local resumed=runtimeFor(inProgress)
eq(resumed.shouldPlayMansionOpening({}),false,
  "a save already inside the story never gets a cold open")
eq(Chapters.state(inProgress).mansionOpeningSeen,true,
  "reconciliation records the derivation")

-- The migration latch must be one-shot: a deliberate replay must survive a
-- later reconcile pass.
local replay={giovanniMeetingDone=true}
local replayRuntime=runtimeFor(replay)
replayRuntime.shouldPlayMansionOpening({})
Chapters.state(replay).mansionOpeningSeen=false
eq(replayRuntime.shouldPlayMansionOpening({}),true,
  "reconciliation cannot undo a deliberate replay")

--------------------------------------------------------------------------
-- 5. Headless runs.
--------------------------------------------------------------------------
S.section("headless runs")

-- The standalone chapter card, as used by `Much earlier...`.
do
  local game=S.newGame(false)
  local store={}
  local runtime=runtimeFor(store)
  local done=false
  local state=runtime.playCard(game,Chapters.CELADON_CARD,{onDone=function() done=true end})
  ok(state~=nil,"playCard returns a state")
  eq(#game.stack.items,1,"the card is pushed")
  local _,frames,all=S.drive(state,{field="phase"})
  ok(done,"the card hands off when it finishes")
  ok(frames<=Chapters.CARD_FRAMES+2,"the card ends on schedule (frames="..frames..")")
  eq(#game.stack.items,0,"the card pops itself")
  S.assertGeometry(all,"celadon card",{skipDeadBand=true})
  local sawBoth={}
  for _,d in ipairs(all) do sawBoth[d.text]=true end
  ok(sawBoth["CELADON CITY"],"the card drew its first line")
  ok(sawBoth["Much earlier..."],"the card drew the intertitle")
end

-- The Mansion cold open, over a live overworld.
do
  local ow=S.newOverworld()
  local game=S.newGame(true)
  local store={}
  local runtime=Chapters.new({
    data=function() return store end,
    cinema=Cinema.new({overworld=function() return ow end}),
  })
  local done=false
  local state=runtime.playMansionOpening(game,{onDone=function() done=true end})
  ok(state~=nil,"playMansionOpening returns a state")
  eq(state.isOpaque,false,
    "the cold open is not opaque, so the Mansion draws underneath it")
  eq(ow.player.inputLocked,true,"player input is locked for the cold open")
  eq(Chapters.state(store).mansionOpeningRunning,true,"the run is marked in progress")

  local seen,frames,all=S.drive(state,{field="phase"})
  ok(done,"the cold open completes")
  ok(seen.CARD,"the run passes through CARD")
  ok(seen.REVEAL,"the run passes through REVEAL")
  ok(seen.NARRATE,"the run passes through NARRATE")
  ok(frames>Chapters.CARD_FRAMES,"the run is longer than its card")
  eq(#game.stack.items,0,"the cold open pops itself")
  eq(ow.player.inputLocked,false,"player input is restored")
  eq(Chapters.state(store).mansionOpeningSeen,true,"the cold open is recorded as seen")
  eq(Chapters.state(store).mansionOpeningRunning,nil,"the in-progress flag is cleared")
  eq(runtime.shouldPlayMansionOpening({}),false,"the cold open never replays")
  S.assertGeometry(all,"mansion cold open")

  local sawCard,sawBeat=false,false
  for _,d in ipairs(all) do
    if d.text=="CINNABAR ISLAND" then sawCard=true end
    if d.text:find("alarm",1,true) then sawBeat=true end
  end
  ok(sawCard,"the cold open drew its location card")
  ok(sawBeat,"the cold open drew its narration")
end

-- Degenerate hosts must not strand the caller.
do
  local runtime=runtimeFor({})
  local reached=false
  runtime.playCard(nil,Chapters.CELADON_CARD,{onDone=function() reached=true end})
  ok(reached,"playCard with no game still hands off")
  reached=false
  runtime.playMansionOpening(nil,{onDone=function() reached=true end})
  ok(reached,"playMansionOpening with no game still hands off")
end

--------------------------------------------------------------------------
-- 6. main.lua wiring.
--------------------------------------------------------------------------
S.section("main.lua wiring")
local main=S.readFile("main.lua")
ok(main~=nil,"main.lua is readable")
if main then
  ok(main:find("chapters.lua",1,true)~=nil,"main.lua loads chapters.lua")
  ok(main:find("cinema.lua",1,true)~=nil,"main.lua loads cinema.lua")
  ok(main:find("Chapters.playMansionOpening(game)",1,true)~=nil,
    "main.lua triggers the Mansion cold open")
  ok(main:find("Chapters.shouldPlayMansionOpening(game)",1,true)~=nil,
    "the cold open is gated")
  ok(main:find("Chapters.playCard(game,Chapters.module.CELADON_CARD",1,true)~=nil,
    "the Much earlier intertitle is now a composed card")
  -- The raw printf is the thing being replaced; it must be gone.
  ok(main:find('printf("Much earlier',1,true)==nil,
    "the raw printf intertitle is gone")

  -- The Celadon camera sweep existed but was unreachable. Arming the first
  -- shot in cut:enter is what makes the chapter open on the city.
  ok(main:find('self.cityPanStage="hold_first"',1,true)~=nil,
    "cut:enter arms the Celadon establishing sweep")
  ok(main:find("frameCityView(self.views[1])",1,true)~=nil,
    "cut:enter frames the first shot")
  ok(main:find("montageSay(1,",1,true)~=nil,"shot one carries a narration beat")
  ok(main:find("montageSay(2,",1,true)~=nil,"shot two carries a narration beat")
  ok(main:find("montageSay(3,",1,true)~=nil,"shot three carries a narration beat")
  ok(main:find("CELADON_MONTAGE",1,true)~=nil,
    "the montage reads its text from chapters.lua")
  -- The old direct jump past the sweep must not come back.
  ok(main:find("-- room. The former Celadon establishing pan is intentionally skipped.",
    1,true)==nil,"the skip-the-sweep comment is gone")

  -- The cold open must stay out of the ending's way and vice versa.
  ok(main:find("isMansion(ow.map.id)\n        and not ow.player.inputLocked",1,true)~=nil
    or main:find("and isMansion(ow.map.id)",1,true)~=nil,
    "the cold open trigger is scoped to Mansion floors")
  ok(main:find("not isMansion(ow.map.id)",1,true)~=nil,
    "the ending's reconciliation stays out of the Mansion timeline")
end

S.finish("chapters")
