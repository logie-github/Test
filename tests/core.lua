package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.modkit")
local Data=require("src.core.Data"); Data:load()
local run=T.sdk.loadMod("mods/pokopia_log568_demo",{data=Data})
T.eq(#run.errors,0,"loads clean")
T.eq(Data.field.boot.startMap,"POKEMON_MANSION_3F","starts Mansion 3F")
T.eq(Data.field.boot.screens.newGame,"OakSpeech","uses stock OakSpeech")
T.eq(Data.field.playerSprites.walk,"POKOPIA_DITTO","Ditto is player walker")
T.eq(#Data.maps.POKEMON_MANSION_3F.objects,10,"3F emergency cast installed")
for _,id in ipairs({"POKEMON_MANSION_1F","POKEMON_MANSION_2F","POKEMON_MANSION_3F","POKEMON_MANSION_B1F"}) do
  local enc=Data.encounters[id]
  T.ok(enc and enc.grass and enc.grass.rate==0,id.." encounters disabled")
end
run.release()
T.finish("pokopia_log568_demo")
