-- Measures the real cost of the mod's own forward pass on the exported blob.
local MAIN="/home/user/Test/pokemon_observer_ai/main.lua"
local species=arg[1] or "bulbasaur"
local MODELDIR=arg[2] or ("out/"..species)
local src={} ; local n=0
for line in io.lines(MAIN) do n=n+1; src[n]=line end
local body=table.concat(src,"\n",144,460)
local mod={}
function mod:read(path)
  local p=path:gsub("^brains/"..species.."/",MODELDIR.."/")
  local f=io.open(p,"rb"); if not f then return nil end
  local d=f:read("*a"); f:close(); return d
end
local R=assert(loadstring([[
local mod=...
]]..body..[[

return {loadModel=loadModel,promptState=promptState,stepToken=stepToken,idsFor=idsFor,
        scoreCompletion=scoreCompletion,branchPrompt=branchPrompt,cloneCache=cloneCache}
]],"runtime"))(mod)

local co=coroutine.create(function()
  local t0=os.clock()
  local model=R.loadModel(species)
  print(string.format("load+dequant: %.2fs  (V=%d D=%d L=%d F=%d M=%d)",os.clock()-t0,model.V,model.D,model.L,model.F,model.maxLen))
  local ctx=("agent %s location pokemon day care hunger high stress medium health hurt "..
    "other charmander affection dislike trust low anger angry fear uneasy event attacked charmander "..
    "remember charmander took my food remember i hit charmander i think charmander hurts me "..
    "i usually guard food i want to guard the food i want to be safe charmander wants my food"):format(species)
  local ids=R.idsFor(model,ctx)
  t0=os.clock()
  local state,logits=R.promptState(model,ctx,44)
  local encode=os.clock()-t0
  print(string.format("encode %d tokens: %.2fs  (%.1f tok/s)",#ids,encode,#ids/encode))
  local phrases={"wander","rest","wall","go sun","go water","go warm","hide","guard food","eat","drink","play",
    "inspect food","inspect water","inspect toy","inspect wall","approach","speak","avoid","follow","comfort",
    "share food","take food","use move"}
  local s2,l2=R.branchPrompt(model,state,logits," <act> ")
  t0=os.clock()
  for _,p in ipairs(phrases) do R.scoreCompletion(model,s2,l2,p) end
  local score=os.clock()-t0
  print(string.format("score %d actions: %.2fs",#phrases,score))
  t0=os.clock()
  local st={rng=1}
  local gs,gl=R.branchPrompt(model,state,logits," chosen guard food <thought> ")
  for i=1,30 do gl=R.stepToken(model,gs,10+i) end
  local gen=os.clock()-t0
  print(string.format("generate 30 tokens: %.2fs  (%.1f tok/s)",gen,30/gen))
  print(string.format("ONE DECISION (plain lua5.1): %.2fs",encode+score+gen))
end)
while true do
  local ok,err=coroutine.resume(co)
  if not ok then error(err) end
  if coroutine.status(co)=="dead" then break end
end
