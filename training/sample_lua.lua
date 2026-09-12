-- Generates thoughts and speech through the mod's own runtime, so what is
-- printed here is exactly what the game would produce for these situations.
local MAIN="/home/user/Test/pokemon_observer_ai/main.lua"
local species=arg[1] or "bulbasaur"
local MODELDIR=arg[2] or ("out/"..species)
local src={} ; local n=0
for line in io.lines(MAIN) do n=n+1; src[n]=line end
local body=table.concat(src,"\n",144,470)
local mod={}
function mod:read(path)
  local p=path:gsub("^brains/"..species.."/",MODELDIR.."/")
  local f=io.open(p,"rb"); if not f then return nil end
  local d=f:read("*a"); f:close(); return d
end
local R=assert(loadstring([[
local mod=...
]]..body..[[

return {loadModel=loadModel,promptState=promptState,branchPrompt=branchPrompt,
        generateFromState=generateFromState,scoreCompletion=scoreCompletion,
        softChoose=softChoose,vocabFilter=vocabFilter,tokenCount=tokenCount}
]],"runtime"))(mod)

local SITUATIONS={
  {other="charmander",ctx="hunger high stress medium health hurt other charmander affection dislike trust low anger angry fear uneasy event attacked charmander remember charmander took my food remember charmander hit me i think charmander hurts me i usually guard food i want to guard the food i want to be safe charmander wants my food",
   act="guard food"},
  {other="squirtle",ctx="social high health healthy other squirtle affection close trust high attachment strong event stayed near squirtle remember squirtle gave me food remember i gave food to squirtle i think squirtle shares food i usually share food i want to stay near squirtle i want to share squirtle wants to be near",
   act="share food squirtle"},
  {other="charmander",ctx="stress high health badly hurt other charmander affection hate trust low anger furious fear afraid event attacked charmander remember charmander knocked me down remember i woke up i think charmander hurts me i am not safe here i want to stay away from charmander i want to be safe if i stay away from charmander i might be safe",
   act="avoid charmander"},
  {other="charmander",ctx="health healthy other charmander affection hate trust low anger furious event none remember charmander killed squirtle remember charmander knocked me down i think charmander kills i usually hit i want to confront charmander i want to hit back",
   act="use move down charmander"},
  {other="squirtle",ctx="fatigue high health healthy other squirtle affection neutral trust medium event none remember i looked at the wall remember the human gave food i think squirtle stays near me i usually speak to the human i want to speak to the human i want to look around",
   act="wall"},
}

local co=coroutine.create(function()
  local model=R.loadModel(species)
  local st={rng=20260912}
  print(("=== %s  V=%d D=%d L=%d ctx=%d ==="):format(species,model.V,model.D,model.L,model.maxLen))
  for i,s in ipairs(SITUATIONS) do
    local ctx=R.vocabFilter(model,"agent "..species.." location pokemon day care "..s.ctx)
    local base,logits=R.promptState(model,ctx,44)
    local agent={generated={}}
    local ts,tl=R.branchPrompt(model,base,logits," chosen "..s.act.." <thought> ")
    local thought=R.generateFromState(model,st,ts,tl,agent,26,.70)
    local ss,sl=R.branchPrompt(model,base,logits," chosen "..s.act.." <speech> ")
    local speech=R.generateFromState(model,st,ss,sl,agent,16,.66)
    print(("\n[%d] %d ctx tokens | chose: %s"):format(i,R.tokenCount(model,ctx),s.act))
    print("    thought: "..thought)
    print("    speech : "..speech)
  end
end)
while true do
  local ok,err=coroutine.resume(co)
  if not ok then error(err) end
  if coroutine.status(co)=="dead" then break end
end
