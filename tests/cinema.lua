--------------------------------------------------------------------------
-- Regression tests for cinema.lua, the shared Gen I cinematic presentation.
--
-- Everything the Mansion cold open, the Celadon chapter card and the LOG 568
-- bookend draw goes through this module, so a fault here is a fault in all
-- three compositions at once.
--
--   lua5.1 tests/cinema.lua      (from the mod root)
--------------------------------------------------------------------------

local S=dofile("tests/support.lua")
local ok,eq=S.ok,S.eq
local Cinema=S.loadModule("cinema.lua")

--------------------------------------------------------------------------
-- Frame geometry.
--
-- The whole presentation depends on these numbers. A Font.drawBox frame owns
-- one tile of border, so the cinematic box at ty=11 must give three interior
-- rows -- which is exactly what the opening LOG 568 page needs.
--------------------------------------------------------------------------
S.section("frame geometry")
local B=Cinema.BOX
eq(B.x,0,"frame starts at the left edge")
eq(B.y,88,"frame top")
eq(B.w,160,"frame spans the screen")
eq(B.h,56,"frame height")
eq(#B.rows,3,"three interior rows")
eq(B.rows[1],96,"row 1 clears the top border")
eq(B.rows[2],112,"row 2")
eq(B.rows[3],128,"row 3")
ok(B.rows[3]+8<=Cinema.SCREEN_H-8,"row 3 clears the bottom border")
eq(B.textX,8,"text is inset one tile")
eq(B.textPixels,144,"interior text width")
eq(B.textPixels,B.w-16,"interior width is the frame minus both borders")

--------------------------------------------------------------------------
-- layout()
--------------------------------------------------------------------------
S.section("layout")

local authored=Cinema.layout("one\ntwo\nthree",20,99)
eq(#authored,3,"authored newlines are never re-flowed")
eq(authored[1],"one","authored row 1")
eq(authored[3],"three","authored row 3")

local wrapped=Cinema.layout("aaaaaaaaaa bbbbbbbbbb cccccccccc",18,99)
eq(#wrapped,3,"long text wraps")
for _,row in ipairs(wrapped) do ok(#row<=18,"wrapped row respects the budget") end

local tight=Cinema.layout("abcd efgh",6,99)
eq(#tight,2,"a tight character budget wraps")

local pixel=Cinema.layout("abcd efgh",40,99,function(s) return #s*4 end)
eq(#pixel,1,"a caller-supplied measure drives the wrap instead")

local clamped=Cinema.layout("a\nb\nc\nd\ne",20,3)
eq(#clamped,3,"maxRows clamps")
local unclamped=Cinema.layout("a\nb\nc\nd\ne",20,99)
eq(#unclamped,5,"a large maxRows does not clamp")

eq(#Cinema.layout("",20,99),0,"empty text yields no rows")
eq(#Cinema.layout(nil,20,99),0,"nil text yields no rows")
local trailing=Cinema.layout("one\n\n",20,99)
eq(#trailing,1,"trailing blank rows are dropped")

-- The opening's own longest rows must survive untouched at the default
-- budget; re-breaking them would break the bookend's recognition beat.
for _,line in ipairs({"Hail Mary project...","Life on this planet","within a few days..."}) do
  local rows=Cinema.layout(line,Cinema.DEFAULT_WIDTH,99)
  eq(#rows,1,"opening row survives the default budget: "..line)
end

-- authoredRows honours every break and wraps nothing at all.
local kept=Cinema.authoredRows("Hail Mary project...\nand another very long row here",99)
eq(#kept,2,"authoredRows never wraps")
eq(kept[1],"Hail Mary project...","authoredRows preserves an over-wide row verbatim")

--------------------------------------------------------------------------
-- pages()
--------------------------------------------------------------------------
S.section("pages")
local split=Cinema.pages({{speaker="LOGAN",text="one\ftwo",quoted="opening"}})
eq(#split,2,"a form-feed becomes two pages")
eq(split[1].text,"one","first page text")
eq(split[2].text,"two","second page text")
eq(split[2].speaker,"LOGAN","speaker carries to every page of a beat")
eq(split[2].quoted,"opening","quote marking carries to every page of a beat")
eq(#Cinema.pages({{text=""}}),0,"an empty beat yields no pages")
eq(#Cinema.pages(nil),0,"a nil beat list yields no pages")

--------------------------------------------------------------------------
-- Renderer.
--------------------------------------------------------------------------
S.section("renderer")
S.install()
local cinema=Cinema.new({})

eq(cinema.measure("MMMM"),32,"measure uses the font's advance widths")

local page={text="Life on this planet\nas we know it will\ncome to an end."}
eq(#cinema.rowsFor(page),3,"a three-row page keeps its rows through the font path")
eq(cinema.textLength(page),19+18+15,"text length counts every revealed character")

-- Typewriter: partial reveal must draw a prefix, never a whole row.
S.resetDrawn()
cinema.drawTextFrame(page,5,0,false)
eq(#S.drawn,1,"a partial reveal draws only the first row")
eq(S.drawn[1].text,"Life ","the first row is revealed a character at a time")
eq(S.drawn[1].x,B.textX,"revealed text starts at the text inset")
eq(S.drawn[1].y,B.rows[1],"revealed text sits on row 1")

S.resetDrawn()
cinema.drawTextFrame(page,999,0,false)
eq(#S.drawn,3,"a full reveal draws every row")
for i,d in ipairs(S.drawn) do eq(d.y,B.rows[i],"row "..i.." lands on its interior row") end

-- The no-loss guarantee: a page whose wrap would need a fourth row keeps its
-- authored breaks instead of being clamped, which would delete its ending.
local threeAuthored={text="Life on this planet\nas we know it will\ncome to an end."}
local rows=cinema.rowsFor(threeAuthored)
eq(#rows,3,"a three-row authored page stays three rows")
eq(rows[3],"come to an end.","the last authored row is never dropped")

-- A page quoted from the opening is never re-broken at any width.
local quotedPage={text="Our last-ditch\nHail Mary project...",quoted="opening"}
local quotedRows=cinema.rowsFor(quotedPage)
eq(#quotedRows,2,"a quoted opening page keeps its authored row count")
eq(quotedRows[2],"Hail Mary project...","a quoted opening row is reproduced verbatim")
local unquoted=cinema.rowsFor({text="Our last-ditch\nHail Mary project..."})
eq(#unquoted,3,"the same text unquoted is allowed to wrap as a backstop")

-- A page with a speaker draws its nameplate; a quoted OakSpeech page must not.
S.resetDrawn()
cinema.drawTextFrame({text="hi",speaker="LOGAN"},999,0,false)
local sawPlate=false
for _,d in ipairs(S.drawn) do if d.text=="LOGAN" then sawPlate=true end end
ok(sawPlate,"a speaker draws a nameplate")

S.resetDrawn()
cinema.drawTextFrame({text="hi"},999,0,false)
eq(#S.drawn,1,"a page with no speaker draws no nameplate")

-- The dark variant is used by the storage display and must not add a plate.
S.resetDrawn()
cinema.drawTextFrame({text="hi",speaker="SCIENTIST"},999,0,true)
eq(#S.drawn,1,"the machine-voice variant never draws a nameplate")

--------------------------------------------------------------------------
-- Chapter card.
--------------------------------------------------------------------------
S.section("chapter card")

local function cardRun(lines,opts)
  S.resetDrawn()
  cinema.drawCard(lines,opts)
  return S.drawn,S.rects
end

local drawnLines=cardRun({"CELADON CITY","Much earlier..."},{alpha=1})
eq(#drawnLines,2,"a two-line card draws both lines")
for _,d in ipairs(drawnLines) do
  local w=#d.text*8
  ok(d.x>=0 and d.x+w<=160,"card line fits horizontally: "..d.text)
  ok(d.y>=0 and d.y+8<=144,"card line fits vertically: "..d.text)
  eq(d.x,math.floor((160-w)/2),"card line is centred: "..d.text)
end
ok(drawnLines[2].y>drawnLines[1].y,"card lines stack downward")

-- Rules and text carry independent alpha so the card can assemble.
local textAtZero=cardRun({"ONE"},{alpha=0,ruleAlpha=1,ruleGrow=1})
eq(#textAtZero,0,"text at zero alpha is not drawn")
local _,rulesAtZero=cardRun({"ONE"},{alpha=0,ruleAlpha=1,ruleGrow=1})
ok(#rulesAtZero>=2,"rules still draw while the text is absent")

-- Growing rules stay centred and never leave the screen.
for _,grow in ipairs({0,0.25,0.5,1}) do
  local _,rects=cardRun({"POKeMON MANSION"},{alpha=1,ruleGrow=grow})
  for _,r in ipairs(rects) do
    ok(r.x>=0 and r.x+r.w<=160,"rule fits at grow="..grow)
    eq(r.x,math.floor((160-r.w)/2),"rule is centred at grow="..grow)
  end
end

--------------------------------------------------------------------------
-- Page runner.
--------------------------------------------------------------------------
S.section("page runner")

local quiet=S.newGame(false)
local runner=cinema.newPageRunner(quiet,{{text="abc"},{text="de"}})
eq(runner:current().text,"abc","runner starts on the first page")
ok(not runner:update(),"runner does not finish while revealing")
for _=1,20 do runner:update() end
eq(runner:current().text,"abc","no input means no advance, even fully revealed")
ok(not runner:isDone(),"runner is not done without input")

local pressing=S.newGame(true)
local fast=cinema.newPageRunner(pressing,{{text="abc"},{text="de"}})
ok(not fast:update(),"the first press completes the reveal rather than advancing")
eq(fast.reveal,3,"a press snaps the reveal to the full page")
ok(not fast:update(),"the next press advances to page two")
eq(fast:current().text,"de","runner advanced")
fast:update()
ok(fast:update(),"the runner reports completion after the last page")
ok(fast:isDone(),"runner is done")
ok(fast:current()==nil,"an exhausted runner has no current page")

--------------------------------------------------------------------------
-- Overworld lock contract.
--------------------------------------------------------------------------
S.section("overworld lock")
local ow=S.newOverworld()
local locking=Cinema.new({overworld=function() return ow end})
local restore=locking.lockOverworld({})
eq(ow.player.inputLocked,true,"the lock disables player input")
restore()
eq(ow.player.inputLocked,false,"the restore returns the previous value")

ow.player.inputLocked=true
local restore2=locking.lockOverworld({})
restore2()
eq(ow.player.inputLocked,true,"a lock taken over an existing lock restores it")

local noOw=Cinema.new({})
ok(type(noOw.lockOverworld({}))=="function",
  "the lock degrades to a no-op restore with no overworld")

S.finish("cinema")
