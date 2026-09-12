-- Cross-checks the exported q8 blob against the trainer by running the mod's
-- own reader and forward pass on the real file.
local MAIN="/home/user/Test/pokemon_observer_ai/main.lua"
local species=arg[1]
local MODELDIR=arg[2]

local src={}
local n=0
for line in io.lines(MAIN) do n=n+1; src[n]=line end
local first,last
for i,l in ipairs(src) do
  if not first and l:find("Embedded q8 micro-transformer",1,true) then first=i end
  if first and not last and l:find("local function branchPrompt",1,true) then
    for j=i,#src do if src[j]=="  end" then last=j break end end
  end
end
assert(first and last,"could not locate the runtime block in main.lua")
local body=table.concat(src,"\n",first,last)

local mod={}
function mod:read(path)
  local p=path:gsub("^brains/"..species.."/",MODELDIR.."/")
  local f=io.open(p,"rb"); if not f then return nil end
  local d=f:read("*a"); f:close(); return d
end

local chunk=assert(loadstring([[
]]..[[
local mod=...
]]..body..[[

return {loadModel=loadModel,promptState=promptState,stepToken=stepToken,idsFor=idsFor,tokenize=tokenize}
]],"runtime"))
local R=chunk(mod)

local co=coroutine.create(function()
  local model=R.loadModel(species)
  io.write(string.format("V=%d D=%d H=%d L=%d F=%d M=%d\n",model.V,model.D,model.H,model.L,model.F,model.maxLen))
  local prompt=io.open(MODELDIR.."/verify_prompt.txt"):read("*a"):gsub("%s+$","")
  local s,logits=R.promptState(model,prompt,8)
  local f=io.open(MODELDIR.."/verify_lua_logits.txt","w")
  for i=1,model.V do f:write(string.format("%.6f\n",logits[i])) end
  f:close()
  io.write("wrote "..model.V.." logits, pos="..s.pos.."\n")
end)
while true do
  local ok,err=coroutine.resume(co)
  if not ok then error(err) end
  if coroutine.status(co)=="dead" then break end
end
