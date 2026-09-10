--------------------------------------------------------------------------
-- Shared harness for the standalone Pokopia suites.
--
-- These tests deliberately do not boot Gen1Recomp. They stub LOVE, the game
-- stack, the input edge detector and the Gen I font, then drive the real
-- cutscene state machines frame by frame with both `update` and `draw`
-- running -- which is what lets them catch a layout row drifting under the
-- dialogue frame, or a nil reached only on one branch of one phase.
--
--   lua5.1 tests/run.lua        (from the mod root)
--------------------------------------------------------------------------

local S={failures=0,checks=0}

function S.ok(cond,label)
  S.checks=S.checks+1
  if not cond then
    S.failures=S.failures+1
    io.write("  FAIL  ",tostring(label),"\n")
  end
  return cond and true or false
end

function S.eq(a,b,label)
  S.checks=S.checks+1
  if a~=b then
    S.failures=S.failures+1
    io.write("  FAIL  ",tostring(label),"\n")
    io.write("        expected: ",string.format("%q",tostring(b)),"\n")
    io.write("        actual:   ",string.format("%q",tostring(a)),"\n")
    return false
  end
  return true
end

function S.section(name) io.write(name,"\n") end

function S.readFile(path)
  local fh=io.open(path,"rb")
  if not fh then return nil end
  local body=fh:read("*a")
  fh:close()
  return body
end

function S.loadModule(path)
  local chunk,err=loadfile(path)
  if not chunk then
    io.write("cannot load ",path,": ",tostring(err),"\n")
    os.exit(1)
  end
  return chunk()
end

-- Flatten authored beat text into one lowercase blob for prose assertions.
function S.flatten(list)
  local parts={}
  for _,entry in ipairs(list) do
    parts[#parts+1]=tostring(type(entry)=="table" and (entry.text or entry[1]) or entry)
  end
  return (table.concat(parts," "):gsub("[\n\f]"," "):gsub("%s+"," "):lower())
end

--------------------------------------------------------------------------
-- LOVE and font stubs.
--------------------------------------------------------------------------
local function nop() end
S.nop=nop

-- Every string the runs draw, with the phase/mode it was drawn in. Suites
-- assert against this to prove nothing paints outside the 160x144 viewport.
S.drawn={}
S.rects={}

function S.resetDrawn()
  for i=#S.drawn,1,-1 do S.drawn[i]=nil end
  for i=#S.rects,1,-1 do S.rects[i]=nil end
end

S.FontStub={
  drawBox=nop,
  draw=function(text,x,y) S.drawn[#S.drawn+1]={text=tostring(text),x=x,y=y} end,
  -- The real Gen I font is measured with Font.width; 8px per glyph matches the
  -- fallback main.lua itself uses when the font module is unavailable.
  width=function(s) return #tostring(s)*8 end,
}

function S.install()
  love={
    graphics={
      clear=nop,setColor=nop,
      rectangle=function(mode,x,y,w,h)
        S.rects[#S.rects+1]={mode=mode,x=x,y=y,w=w,h=h}
      end,
      polygon=nop,push=nop,pop=nop,translate=nop,scale=nop,setLineWidth=nop,
      draw=nop,setShader=nop,
      newImage=function() error("no image backend in tests") end,
      newShader=function() error("no shader backend in tests") end,
    },
    math={random=function(m) return m and 1 or 0.5 end},
  }

  local realRequire=require
  require=function(name)
    if name=="src.render.Font" then return S.FontStub end
    return realRequire(name)
  end
end

--------------------------------------------------------------------------
-- Fake game / stack / input.
--------------------------------------------------------------------------
function S.newGame(pressed)
  local stack={items={}}
  function stack:push(s) self.items[#self.items+1]=s end
  function stack:pop()
    local s=self.items[#self.items]
    self.items[#self.items]=nil
    return s
  end
  function stack:top() return self.items[#self.items] end
  return {
    data={},
    stack=stack,
    input={wasPressed=function(_,_) return pressed and true or false end},
    save={modData={}},
  }
end

-- A minimal overworld whose player can be locked and restored, so the input
-- lock contract can be asserted rather than assumed.
function S.newOverworld()
  return {map={id="POKEMON_MANSION_3F"},player={inputLocked=false,frozen=false}}
end

--------------------------------------------------------------------------
-- Frame driver.
--
-- Runs a pushed state to completion, executing update and draw every frame
-- and recording which phases/modes were visited and every string drawn.
--------------------------------------------------------------------------
function S.drive(state,opts)
  opts=opts or {}
  local limit=opts.limit or 40000
  local field=opts.field or "mode"
  local seen,frames={},0
  local all={}
  while state and not state.finished and frames<limit do
    frames=frames+1
    S.resetDrawn()
    local okU,errU=pcall(function() state:update() end)
    if not okU then
      S.failures=S.failures+1
      S.checks=S.checks+1
      io.write("  FAIL  update error at frame ",frames,": ",tostring(errU),"\n")
      break
    end
    local okD,errD=pcall(function() state:draw() end)
    if not okD then
      S.failures=S.failures+1
      S.checks=S.checks+1
      io.write("  FAIL  draw error at frame ",frames,": ",tostring(errD),"\n")
      break
    end
    local phase=state[field]
    if phase then seen[phase]=true end
    for _,d in ipairs(S.drawn) do
      d.phase=phase
      all[#all+1]=d
    end
  end
  return seen,frames,all
end

-- Every string must land inside the viewport, and must sit either fully above
-- the dialogue frame (chrome/cards) or on one of its interior rows.
function S.assertGeometry(all,label,opts)
  opts=opts or {}
  local outOfBounds,inDeadBand=nil,nil
  for _,d in ipairs(all) do
    local w=#d.text*8
    if not outOfBounds and (d.x<0 or d.x+w>160 or d.y<0 or d.y+8>144) then
      outOfBounds=d
    end
    if not opts.skipDeadBand and not inDeadBand
        and not (d.y+8<=88 or d.y>=96) then
      inDeadBand=d
    end
  end
  S.ok(#all>0,label..": drew text (n="..tostring(#all)..")")
  S.ok(outOfBounds==nil,label..": every string fits the 160x144 viewport"..
    (outOfBounds and (": '"..outOfBounds.text.."' at "..outOfBounds.x..","..
     outOfBounds.y.." in "..tostring(outOfBounds.phase)) or ""))
  if not opts.skipDeadBand then
    S.ok(inDeadBand==nil,label..": no string under the dialogue frame border"..
      (inDeadBand and (": '"..inDeadBand.text.."' at y="..inDeadBand.y..
       " in "..tostring(inDeadBand.phase)) or ""))
  end
end

function S.finish(name)
  io.write("\n")
  if S.failures>0 then
    io.write(("%s: %d/%d checks failed\n"):format(name,S.failures,S.checks))
    os.exit(1)
  end
  io.write(("%s: %d checks passed\n"):format(name,S.checks))
end

return S
