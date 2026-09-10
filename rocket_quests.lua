-- Five save-persistent Team Rocket HQ operations for the playable Ditto.
-- The module is deliberately UI-agnostic: main.lua supplies the game's native
-- dialogue/menu helpers and TCG services.
local RocketQuests={}

local DEFINITIONS={
  {short="CREDENTIALS",title="COUNTERFEIT CREDENTIALS",reward="$500 + IMPOSTER OAK",summary="Collect clearance stamps from three off-duty ROCKETS."},
  {short="WALL ECHO",title="THE WALL ECHO",reward="$700 + MYSTERY CARDS",summary="Trace ZUBAT's echo, then win one round of CUE BONES."},
  {short="KEEPSAKE",title="CUBONE'S MISSING KEEPSAKE",reward="$800 + CUBONE CARDS",summary="Trace CUBONE's missing club through the lounge crew."},
  {short="EMPTY VAULT",title="OPERATION: EMPTY VAULT",reward="SUPPLIES OR $1500",summary="Locate three abandoned supply caches and decide their fate."},
  {short="HYPNO PROTOCOL",title="THE HYPNO PROTOCOL",reward="PSYCHIC DECK + $2000",summary="Defeat HYPNO in a dream-protocol TCG duel."},
}

local function flags(q)
  if type(q.rocketQuests)~="table" then q.rocketQuests={} end
  local r=q.rocketQuests
  r.completed=type(r.completed)=="table" and r.completed or {}
  r.progress=type(r.progress)=="table" and r.progress or {}
  return r
end

local function grantCard(t,label,count)
  if not (t and label) then return end
  t.collection=type(t.collection)=="table" and t.collection or {}
  t.collection[label]=(tonumber(t.collection[label]) or 0)+(count or 1)
end

function RocketQuests.new(api)
  local self={}
  local function state(game) return flags(api.data(game)) end
  local function say(game,text,done,speaker)
    api.say(game,text,done,{speaker=speaker or "ROCKET"})
  end
  local function active(game,n) return tonumber(state(game).active)==n end
  local function step(game,key,value)
    local r=state(game); r.progress[key]=value==nil and true or value
  end
  local function has(game,key) return state(game).progress[key] and true or false end
  local function rewardSound(game)
    local ok,Sound=pcall(require,"src.core.Sound")
    if ok then Sound.play(game.data,"Get_Item1") end
  end
  local function complete(game,n,text,done)
    local r=state(game)
    r.completed[n]=true; r.active=nil; r.progress={}
    rewardSound(game)
    say(game,text,done,"DISPATCH")
  end

  local function accept(game,n,done)
    local r=state(game)
    if n>1 and not r.completed[n-1] then
      say(game,"Still LOCKED.\fClear last file\nfirst.",done,"DISPATCH")
      return
    end
    r.active=n; r.progress={}
    local intros={
      "Need three stamps.\fWALKER. LOUNGE.\nPACER.",
      "ZUBAT heard a\nhollow echo.\fCheck CUE BONES.\nWin one round.",
      "CUBONE lost its\nclub in cleanup.\fAsk CUBONE first.\nThen WALKER F.",
      "Three caches were\nmissed in cleanup.\fCheck RATICATE,\nZUBAT, WALKER M.",
      "HYPNO is testing\ndream security.\fBeat its PSYCHIC\ndeck, then report.",
    }
    say(game,intros[n],done,"DISPATCH")
  end

  local function ready(game,n)
    if n==1 then return has(game,"stampWalker") and has(game,"stampLounge") and has(game,"stampPacer") end
    if n==2 then return has(game,"echoChecked") and has(game,"cueWin") end
    if n==3 then return has(game,"cuboneAsked") and has(game,"lockerClue") and has(game,"clubFound") and has(game,"clubReturned") end
    if n==4 then return has(game,"cacheRat") and has(game,"cacheZubat") and has(game,"cacheGuard") end
    if n==5 then return has(game,"hypnoWin") end
    return false
  end

  local function status(game,n)
    local r=state(game)
    if r.completed[n] then return "DONE" end
    if n>1 and not r.completed[n-1] then return "LOCKED" end
    if r.active==n then return ready(game,n) and "REPORT" or "ACTIVE" end
    return "NEW"
  end

  local function grantPsychicDeck(game)
    local t=api.tcgState(game)
    local deck={
      AbraCard=4,KadabraCard=3,AlakazamCard=2,DrowzeeCard=4,HypnoCard=3,
      GastlyLv8Card=3,HaunterLv17Card=2,MewtwoLv60Card=1,
      ProfessorOakCard=2,BillCard=4,PokeBallCard=2,PotionCard=2,
      SwitchCard=2,EnergyRemovalCard=2,PsychicEnergyCard=24,
    }
    for label,count in pairs(deck) do grantCard(t,label,count) end
    t.deck={name="HYPNO PROTOCOL",cards={}}
    for label,count in pairs(deck) do t.deck.cards[label]=count end
  end

  local function report(game,n,done)
    if not ready(game,n) then
      local hints={
        "WALKER M.\nLOUNGE F. PACER M.",
        "Check ZUBAT.\fWin CUE BONES.",
        "CUBONE, WALKER F,\nthen RATICATE.",
        "Check RATICATE,\nZUBAT, WALKER M.",
        "Beat HYPNO's\nPSYCHIC deck.",
      }
      say(game,"OBJECTIVE\f"..hints[n],done,"DISPATCH")
      return
    end
    local t=api.tcgState(game)
    if n==1 then
      game.save.money=(tonumber(game.save.money) or 0)+500
      grantCard(t,"ImposterProfessorOakCard",2)
      complete(game,n,"Credentials clear.\fAll three stamps\nmatched.\f$500 and two\nIMPOSTER OAK x2!",done)
    elseif n==2 then
      game.save.money=(tonumber(game.save.money) or 0)+700
      grantCard(t,"GamblerCard",2); grantCard(t,"MysteriousFossilCard",2)
      complete(game,n,"Panel opened.\fCUE BONES shook\nit loose.\f$700 and four\nMYSTERY cards!",done)
    elseif n==3 then
      game.save.money=(tonumber(game.save.money) or 0)+800
      grantCard(t,"CuboneCard",4); grantCard(t,"MarowakLv26Card",2)
      complete(game,n,"Keepsake returned.\fTrail closed.\f$800 and CUBONE\ncards received!",done)
    elseif n==4 then
      api.menu(game,"EMPTY VAULT",{"DONATE SUPPLIES","KEEP THE FIND","DECIDE LATER"},function(i)
        if i==3 then if done then done() end; return end
        if i==1 then
          grantCard(t,"PotionCard",4); grantCard(t,"FullHealCard",4); grantCard(t,"ReviveCard",2)
          complete(game,n,"Supplies logged.\fSent to clinic.\fSUPPLY KIT x10!",done)
        else
          game.save.money=(tonumber(game.save.money) or 0)+1500
          complete(game,n,"Old caches clear.\f$1500 received!",done)
        end
      end,done)
    elseif n==5 then
      game.save.money=(tonumber(game.save.money) or 0)+2000
      grantPsychicDeck(game)
      complete(game,n,"Protocol logged.\f$2000 and the\nHYPNO PROTOCOL\ndeck received!",done)
    end
  end

  function self.board(game,done)
    done=done or function() end
    local function reopen() self.board(game,done) end
    local labels={}
    for i,d in ipairs(DEFINITIONS) do labels[i]=tostring(i).." "..d.short.." "..status(game,i) end
    labels[#labels+1]="LEAVE"
    api.menu(game,"ROCKET OPERATIONS",labels,function(i)
      if i>#DEFINITIONS then done(); return end
      local r=state(game); local s=status(game,i); local d=DEFINITIONS[i]
      if s=="DONE" then say(game,d.title.."\fCOMPLETE\nReward: "..d.reward,reopen,"DISPATCH")
      elseif s=="LOCKED" then say(game,"File classified.\fClear prior work.",reopen,"DISPATCH")
      elseif s=="ACTIVE" or s=="REPORT" then report(game,i,reopen)
      elseif r.active and r.active~=i then
        say(game,"Finish the current\noperation first.",reopen,"DISPATCH")
      else
        say(game,d.title.."\f"..d.summary,function() accept(game,i,reopen) end,"DISPATCH")
      end
    end,done)
  end

  local handlers={}
  handlers.RH_WALKER_M=function(game,done)
    if active(game,1) and not has(game,"stampWalker") then step(game,"stampWalker"); say(game,"Good enough.\fBLUE stamp.\nKeep moving.",done)
    elseif active(game,4) and not has(game,"cacheGuard") then step(game,"cacheGuard"); say(game,"Third cache?\fEmpty vent by the\nbunks.\fCache 3 secured.",done)
    else return false end
    return true
  end
  handlers.RH_LOUNGE_F=function(game,done)
    if active(game,1) and not has(game,"stampLounge") then step(game,"stampLounge"); say(game,"Hair's a bit off.\fRED stamp.\nDon't linger.",done); return true end
    return false
  end
  handlers.RH_PACER_M=function(game,done)
    if active(game,1) and not has(game,"stampPacer") then step(game,"stampPacer"); say(game,"Posture's right.\fGREEN stamp.\nReport back.",done); return true end
    return false
  end
  handlers.RH_ZUBAT=function(game,done)
    if active(game,2) and not has(game,"echoChecked") then step(game,"echoChecked"); say(game,"ZUBAT!\fA metal echo comes\nfrom CUE BONES.",done,"ZUBAT"); return true
    elseif active(game,4) and not has(game,"cacheZubat") then step(game,"cacheZubat"); say(game,"ZUBAT finds a\nhollow roof panel.\fCache 2 secured.",done,"ZUBAT"); return true end
    return false
  end
  handlers.RH_CUBONE=function(game,done)
    if active(game,3) and not has(game,"cuboneAsked") then step(game,"cuboneAsked"); say(game,"Bone...\fIt points at an\nempty hook.\fThen at WALKER F.",done,"CUBONE"); return true
    elseif active(game,3) and has(game,"clubFound") and not has(game,"clubReturned") then step(game,"clubReturned"); say(game,"You return the\nworn club.\fCUBONE grips it\nclose.\fReport back.",done,"CUBONE"); return true end
    return false
  end
  handlers.RH_WALKER_F=function(game,done)
    if active(game,3) and has(game,"cuboneAsked") and not has(game,"lockerClue") then step(game,"lockerClue"); say(game,"Cleanup put it in\nthe snack lockers.\fRATICATE gets into\nevery one.",done); return true end
    return false
  end
  handlers.RH_RATICATE=function(game,done)
    if active(game,3) and has(game,"lockerClue") and not has(game,"clubFound") then step(game,"clubFound"); say(game,"Club recovered.\fReturn to CUBONE.",done,"RATICATE"); return true
    elseif active(game,4) and not has(game,"cacheRat") then step(game,"cacheRat"); say(game,"RATICATE digs by\nthe cartons.\fCache 1 secured.",done,"RATICATE"); return true end
    return false
  end

  function self.talk(game,name,done)
    if name=="RH_DISPATCH" then self.board(game,done); return true end
    if name=="RH_HYPNO" then
      if active(game,5) and not has(game,"hypnoWin") then
        say(game,"Enter protocol?\fWin, and your mind\npasses the test.",function()
          api.duel(game,function(winner)
            if winner=="player" then step(game,"hypnoWin"); say(game,"Protocol cleared.\fReport back.",done,"HYPNO")
            else say(game,"Dream rejected.\fTry again.",done,"HYPNO") end
          end)
        end,"HYPNO")
      else say(game,"Dreams have marks.\fWe can test them.",done,"HYPNO") end
      return true
    end
    local fn=handlers[name]
    return fn and fn(game,done) or false
  end

  function self.cueBonesWin(game)
    if active(game,2) and has(game,"echoChecked") then step(game,"cueWin") end
  end

  return self
end

return RocketQuests
