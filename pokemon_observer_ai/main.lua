-- Pokemon Observer AI Arena v1.7 for Gen1Recomp API v2
--
-- Spectator focus and the observer HUD are presentation-only.  Clicking,
-- focusing, reading thoughts or opening the MIND/MEMORY screens never enters
-- any Pokemon's observations, ledger, beliefs, relationships or microLM prompt.
--
-- Cognitive pipeline (Lua owns everything except the four decisions marked
-- MODEL, which are made by each Pokemon's own embedded microLM):
--
--   permanent ledger -> retrieval -> beliefs/self-concept/theory-of-mind
--     -> drives/emotions/relationships -> prompt (token budgeted)
--     -> MODEL: plan / action / target / lethal follow-up
--     -> MODEL: thought + speech
--     -> physical consequence -> permanent ledger
--
-- No story outcome is scripted.  The simulation supplies possibilities and
-- consequences; the models choose what to do with them.
return function(mod)
  local Font = mod.ui.Font
  local PartyMenu = require("src.ui.PartyMenu")
  local Pokemon = require("src.pokemon.Pokemon")
  local Collision = require("src.world.Collision")
  local Screens = require("src.ui.Screens")
  local Strings = require("src.core.Strings")

  local SCREEN_W, SCREEN_H = 160, 144
  local MAP_ID = "DAYCARE"
  local UNCONSCIOUS_TIME = 10      -- real seconds spent helpless at 0 HP
  local HP_BAR_TIME = 1.0          -- seconds a health bar stays up after a change
  local THOUGHT_SHOW_TIME = 7.0    -- seconds a fresh private thought stays drawn
  local activeState = nil
  local liveGame = nil

  -- Namespaced subsystems.  Lua allows at most 200 locals per function and the
  -- mod body is one function, so new systems live as fields on these tables
  -- instead of as new top-level locals.
  local Mind = {}      -- ledger, retrieval, beliefs, self-concept, values, plans
  local Prompt = {}    -- token-budgeted microLM context assembly
  local FX = {}        -- battle animation / health bar presentation layer
  local Body = {}      -- party record sync, damage, EXP, evolution

  -- Physical/capability data only.  Social personality is not encoded here.
  local SPECIES = {
    bulbasaur = { name="Bulbasaur", speed=18 },
    charmander = { name="Charmander", speed=21 },
    squirtle = { name="Squirtle", speed=19 },
  }

  -- Exact six-frame follower sheets from gamecorner-033/PokePCFollowers,
  -- historical commit dfe64d4fcee4833aa79ec7357c2146455b679d81.
  -- The user explicitly supplied permission to package these three assets.
  local FOLLOWER_ASSETS = {
    bulbasaur = "assets/sprites/follower_001.png",
    charmander = "assets/sprites/follower_004.png",
    squirtle = "assets/sprites/follower_007.png",
  }
  local FOLLOWER_STAND = { down=0, up=1, left=2, right=2 }
  local FOLLOWER_WALK  = { down=3, up=4, left=5, right=5 }
  local followerImages, followerQuads = {}, {}

  local function followerImage(brain)
    local cached=followerImages[brain]
    if cached~=nil then return cached or nil end
    local path=FOLLOWER_ASSETS[brain]
    if not path then followerImages[brain]=false; return nil end
    local ok,img=pcall(function() return mod.assets:image(path) end)
    if ok and img then
      if img.setFilter then pcall(img.setFilter,img,"nearest","nearest") end
      followerImages[brain]=img
      return img
    end
    followerImages[brain]=false
    return nil
  end

  local function followerQuad(brain,img,frame)
    local key=brain..":"..tostring(frame)
    local q=followerQuads[key]
    if q then return q end
    if not (love and love.graphics and love.graphics.newQuad and img and img.getDimensions) then return nil end
    local iw,ih=img:getDimensions()
    if iw<16 or ih<(frame+1)*16 then return nil end
    q=love.graphics.newQuad(0,frame*16,16,16,iw,ih)
    followerQuads[key]=q
    return q
  end

  -- Stable, legitimate Gen-I DVs for the observation cohort.  Pokemon.new
  -- still computes the actual level-5 stats, HP, EXP and legal starting moves
  -- from the loaded game's species/move tables.
  local function starterDvRng(_,hi) return hi end

  local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end
  local function trim(s,n) s=tostring(s or ""):gsub("%s+"," "); if #s>n then return s:sub(1,n-3).."..." end; return s end
  local function upper(s) return tostring(s or ""):upper() end
  local function dist(a,b) local dx,dy=a.x-b.x,a.y-b.y; return math.sqrt(dx*dx+dy*dy) end
  local function clockOf(t)
    t=math.max(0,math.floor(tonumber(t) or 0))
    return string.format("%02d:%02d:%02d",math.floor(t/3600),math.floor(t/60)%60,t%60)
  end
  local function wrap(text,maxChars,maxLines)
    text=tostring(text or ""):gsub("%s+"," ")
    local words={}
    for raw in text:gmatch("%S+") do
      local word=raw
      while #word>maxChars do words[#words+1]=word:sub(1,maxChars);word=word:sub(maxChars+1) end
      if #word>0 then words[#words+1]=word end
    end
    local lines,line={},""
    for _,word in ipairs(words) do
      if #line==0 then line=word elseif #line+1+#word<=maxChars then line=line.." "..word else lines[#lines+1]=line;line=word;if #lines>=maxLines then break end end
    end
    if #lines<maxLines and #line>0 then lines[#lines+1]=line end
    if #lines==maxLines and #table.concat(lines," ")<#text-4 then lines[#lines]=trim(lines[#lines],math.max(4,maxChars-3)).."..." end
    return lines
  end
  local function box(x,y,w,h,alpha)
    love.graphics.setColor(.96,.98,.91,alpha or .94); love.graphics.rectangle("fill",x,y,w,h)
    love.graphics.setColor(.08,.10,.08,1); love.graphics.rectangle("line",x,y,w,h)
  end

  local function rnd(st)
    st.rng=(1103515245*st.rng+12345)%2147483648
    return st.rng/2147483648
  end
  local function pick(st,t) return t[math.max(1,math.min(#t,math.floor(rnd(st)*#t)+1))] end
  local function deepcopy(v,seen)
    if type(v)~="table" then return v end
    seen=seen or {}; if seen[v] then return seen[v] end
    local out={}; seen[v]=out
    for k,x in pairs(v) do out[deepcopy(k,seen)]=deepcopy(x,seen) end
    return out
  end

  local function agentById(st,id)
    for _,a in ipairs(st.agents) do if a.id==id then return a end end
  end

  local nearestOther

  -- Forward declarations: these are assigned further down but are referenced by
  -- closures created above their definition point.
  local logAction, pushEvent, performDecision
  -- Embedded q8 micro-transformer runtime.  All inference stays inside the
  -- Gen1Recomp/LÖVE Lua process; there is no socket, Python process, or server.
  local function u16(s,p) local a,b=s:byte(p,p+1); return a+b*256,p+2 end
  local function f32(s,p)
    local a,b,c,d=s:byte(p,p+3)
    local bits=a+b*256+c*65536+d*16777216
    local sign=1
    if bits>=2147483648 then sign=-1; bits=bits-2147483648 end
    local e=math.floor(bits/8388608); local m=bits-e*8388608; local v
    if e==0 then v=(m/8388608)*2^-126
    elseif e==255 then v=0
    else v=(1+m/8388608)*2^(e-127) end
    return sign*v,p+4
  end
  -- Weights are dequantized once at load into a flat float array rather than
  -- decoded per element on every multiply.  With LuaJIT's FFI that array is a
  -- real C float buffer; without it, a plain Lua array is still far cheaper
  -- than a string.byte plus sign fix inside the inner loop.
  local FFI_OK,ffi=pcall(require,"ffi")
  local function newFloats(n)
    if FFI_OK then return ffi.new("float[?]",n),true end
    local t={}
    for i=0,n-1 do t[i]=0 end
    return t,false
  end
  local function readMatrix(blob,p)
    local rows,cols; rows,p=u16(blob,p); cols,p=u16(blob,p)
    local scales={}
    for i=1,rows do scales[i],p=f32(blob,p) end
    local n=rows*cols
    local w=newFloats(n)
    local base=p
    for i=1,rows do
      local scale=scales[i]
      local rowBase=base+(i-1)*cols
      local outBase=(i-1)*cols
      for j=1,cols do
        local q=blob:byte(rowBase+j-1)
        if q>=128 then q=q-256 end
        w[outBase+j-1]=q*scale
      end
    end
    local m={rows=rows,cols=cols,scales=scales,w=w}
    return m,p+n
  end
  local function readVector(blob,p)
    local n; n,p=u16(blob,p); local v={}
    for i=1,n do v[i],p=f32(blob,p) end
    return v,p
  end
  local function unescapeToken(t)
    return (t:gsub("\\t","\t"):gsub("\\n","\n"):gsub("\\r","\r"):gsub("\\\\","\\"))
  end
  local function loadVocab(path)
    local raw=assert(mod:read(path),"missing embedded microLM vocabulary: "..path)
    local stoi,itos={},{}
    for line in (raw.."\n"):gmatch("(.-)\n") do
      if line~="" then
        local sid,t=line:match("^(%d+)\t(.*)$")
        if sid then local id=tonumber(sid); t=unescapeToken(t); stoi[t]=id; itos[id]=t end
      end
    end
    return stoi,itos
  end
  local function loadModel(species)
    local blob=assert(mod:read("brains/"..species.."/model.q8"),"missing embedded microLM weights for "..species)
    assert(blob:sub(1,5)=="MLMQ1","bad microLM q8 header for "..species)
    local p=6; local V,D,H,L,F,M
    V,p=u16(blob,p);D,p=u16(blob,p);H,p=u16(blob,p);L,p=u16(blob,p);F,p=u16(blob,p);M,p=u16(blob,p)
    local tok,pos; tok,p=readMatrix(blob,p); pos,p=readMatrix(blob,p)
    local layers={}
    for li=1,L do
      local qkv,qkvb,out,outb,l1,l1b,l2,l2b,n1w,n1b,n2w,n2b
      qkv,p=readMatrix(blob,p); qkvb,p=readVector(blob,p); out,p=readMatrix(blob,p); outb,p=readVector(blob,p)
      l1,p=readMatrix(blob,p); l1b,p=readVector(blob,p); l2,p=readMatrix(blob,p); l2b,p=readVector(blob,p)
      n1w,p=readVector(blob,p); n1b,p=readVector(blob,p); n2w,p=readVector(blob,p); n2b,p=readVector(blob,p)
      layers[li]={qkv=qkv,qkvb=qkvb,out=out,outb=outb,l1=l1,l1b=l1b,l2=l2,l2b=l2b,n1w=n1w,n1b=n1b,n2w=n2w,n2b=n2b}
    end
    local lnw,lnb; lnw,p=readVector(blob,p); lnb,p=readVector(blob,p)
    local stoi,itos=loadVocab("brains/"..species.."/vocab.tsv")
    return {species=species,blob=blob,V=V,D=D,H=H,L=L,F=F,maxLen=M,tok=tok,pos=pos,layers=layers,lnw=lnw,lnb=lnb,
      stoi=stoi,itos=itos,bos=stoi["<bos>"],eos=stoi["<eos>"],unk=stoi["<unk>"],pad=stoi["<pad>"]}
  end

  -- Inference is spread across frames against a wall-clock slice rather than a
  -- fixed operation count, so a fast host uses its speed and a slow one still
  -- keeps its frame time.  The op counter is only there to keep the clock
  -- lookup off the innermost loop.
  local inferOps=0
  local inferDeadline=0
  local INFER_SLICE=0.007
  local function nowSeconds()
    if love and love.timer and love.timer.getTime then return love.timer.getTime() end
    return os.clock()
  end
  local function inferBudget(n)
    inferOps=inferOps+(n or 1)
    if inferOps>=6000 then
      inferOps=0
      if nowSeconds()>=inferDeadline then coroutine.yield("compute") end
    end
  end
  local function qrow(m,row)
    local out={}; local w=m.w; local base=row*m.cols
    for j=1,m.cols do out[j]=w[base+j-1] end
    inferBudget(m.cols); return out
  end
  local function qmatvec(m,x,bias)
    local out={}; local w=m.w; local cols=m.cols
    for i=1,m.rows do
      local sum=0; local base=(i-1)*cols
      for j=1,cols do sum=sum+w[base+j-1]*x[j] end
      out[i]=sum+(bias and bias[i] or 0)
      inferBudget(cols)
    end
    return out
  end
  local function layernorm(x,w,b)
    local n=#x; local mean=0
    for i=1,n do mean=mean+x[i] end; mean=mean/n
    local var=0; for i=1,n do local d=x[i]-mean; var=var+d*d end
    local inv=1/math.sqrt(var/n+1e-5); local out={}
    for i=1,n do out[i]=(x[i]-mean)*inv*w[i]+b[i] end
    inferBudget(n*2); return out
  end
  local function tanh(x)
    if x>10 then return 1 elseif x<-10 then return -1 end
    local e=math.exp(2*x); return (e-1)/(e+1)
  end
  local GELU_C=math.sqrt(2/math.pi)
  local function gelu(x) return .5*x*(1+tanh(GELU_C*(x+.044715*x*x*x))) end
  local function newCache(model)
    local s={pos=0,K={},V={}}
    for i=1,model.L do s.K[i]={}; s.V[i]={} end
    return s
  end
  local function rollback(model,s,pos)
    for l=1,model.L do
      local k,v=s.K[l],s.V[l]
      for i=#k,pos+1,-1 do k[i]=nil;v[i]=nil end
    end
    s.pos=pos
  end
  local function cloneCache(model,s)
    local c={pos=s.pos,K={},V={}}
    for l=1,model.L do
      c.K[l]={};c.V[l]={}
      for i=1,s.pos do c.K[l][i]=s.K[l][i];c.V[l][i]=s.V[l][i] end
    end
    return c
  end
  -- `skipLogits` drops the vocabulary projection for tokens whose logits are
  -- never read.  That projection is V*D multiplies, about a quarter of the cost
  -- of a token, and while encoding a prompt only the final token's logits matter.
  local function stepToken(model,s,tid,skipLogits)
    if s.pos>=model.maxLen then return nil end
    local er=qrow(model.tok,tid); local pr=qrow(model.pos,s.pos); local h={}
    for i=1,model.D do h[i]=er[i]+pr[i] end
    local hd=model.D/model.H; local root=math.sqrt(hd); local T=s.pos+1
    for li=1,model.L do
      local L=model.layers[li]; local n1=layernorm(h,L.n1w,L.n1b); local qkv=qmatvec(L.qkv,n1,L.qkvb)
      local q,k,v={},{},{}
      for i=1,model.D do q[i]=qkv[i];k[i]=qkv[model.D+i];v[i]=qkv[model.D*2+i] end
      s.K[li][T]=k;s.V[li][T]=v
      local att={}
      for head=0,model.H-1 do
        local first=head*hd+1; local scores={}; local mx=-1e30
        for t=1,T do
          local kt=s.K[li][t]; local sum=0
          for j=0,hd-1 do sum=sum+q[first+j]*kt[first+j] end
          sum=sum/root;scores[t]=sum;if sum>mx then mx=sum end
        end
        local ex,den={},0
        for t=1,T do local e=math.exp(scores[t]-mx);ex[t]=e;den=den+e end
        for j=0,hd-1 do
          local sum=0
          for t=1,T do sum=sum+ex[t]*s.V[li][t][first+j] end
          att[first+j]=sum/den
        end
        inferBudget(T*hd*2)
      end
      local o=qmatvec(L.out,att,L.outb); for i=1,model.D do h[i]=h[i]+o[i] end
      local n2=layernorm(h,L.n2w,L.n2b); local ff=qmatvec(L.l1,n2,L.l1b)
      for i=1,#ff do ff[i]=gelu(ff[i]) end; inferBudget(#ff)
      ff=qmatvec(L.l2,ff,L.l2b); for i=1,model.D do h[i]=h[i]+ff[i] end
    end
    s.pos=T
    if skipLogits then return nil end
    local z=layernorm(h,model.lnw,model.lnb)
    return qmatvec(model.tok,z,nil)
  end

  local function isWordByte(c)
    return c and ((c>=48 and c<=57) or (c>=97 and c<=122) or c==35 or c>=128)
  end
  local function tokenize(text)
    text=tostring(text or ""):lower(); local out={}; local i,n=1,#text
    while i<=n do
      local c=text:byte(i)
      if c==32 or c==9 or c==10 or c==13 then i=i+1
      elseif c==60 then
        local j=text:find(">",i+1,true)
        if j then out[#out+1]=text:sub(i,j);i=j+1 else out[#out+1]=text:sub(i,i);i=i+1 end
      elseif isWordByte(c) then
        local j=i
        while j<=n and isWordByte(text:byte(j)) do j=j+1 end
        if j<=n and (text:byte(j)==39 or text:byte(j)==45) and isWordByte(text:byte(j+1)) then
          j=j+1;while j<=n and isWordByte(text:byte(j)) do j=j+1 end
        end
        out[#out+1]=text:sub(i,j-1);i=j
      else out[#out+1]=text:sub(i,i);i=i+1 end
    end
    return out
  end
  local PUNCT={ ["."]=true,[","]=true,["?"]=true,["!"]=true,[":"]=true,[";"]=true,["%"]=true,[")"]=true, ["]"]=true }
  local OPEN={ ["("]=true,["["]=true }
  local function detokenize(tokens)
    local s=""
    for _,t in ipairs(tokens) do
      if PUNCT[t] then s=s:gsub("%s+$","")..t.." " elseif OPEN[t] then s=s..t else s=s..t.." " end
    end
    return s:gsub("%s+$","")
  end
  local function idsFor(model,text)
    local ids={}
    for _,t in ipairs(tokenize(text)) do ids[#ids+1]=model.stoi[t] or model.unk end
    return ids
  end
  -- Drops tokens the species model never learned instead of feeding it a run of
  -- <unk>.  The three bundled vocabularies are ~520-550 tokens, so every new
  -- cognitive section has to be written in words the model actually has.
  local function vocabFilter(model,text)
    local kept={}
    for _,t in ipairs(tokenize(text)) do if model.stoi[t] then kept[#kept+1]=t end end
    return table.concat(kept," ")
  end
  local function tokenCount(model,text)
    local n=0
    for _,t in ipairs(tokenize(text)) do if model.stoi[t] then n=n+1 end end
    return n
  end
  -- The context window is 128 tokens.  If the prompt still overruns the budget,
  -- keep the head (which carries identity, location and health) and drop from
  -- the middle, rather than the old behavior of cutting the front away.
  local PROMPT_HEAD_KEEP=14
  local function promptState(model,text,reserve)
    local ids=idsFor(model,text); local keep=model.maxLen-(reserve or 28)-1
    if #ids>keep then
      local head=math.min(PROMPT_HEAD_KEEP,keep)
      local t={}
      for i=1,head do t[#t+1]=ids[i] end
      for i=#ids-(keep-head)+1,#ids do t[#t+1]=ids[i] end
      ids=t
    end
    local s=newCache(model)
    local logits=stepToken(model,s,model.bos,#ids>0)
    for i,id in ipairs(ids) do logits=stepToken(model,s,id,i<#ids) end
    return s,logits
  end
  local function logprob(logits,tid)
    local mx=-1e30;for i=1,#logits do if logits[i]>mx then mx=logits[i] end end
    local den=0;for i=1,#logits do den=den+math.exp(logits[i]-mx) end
    return logits[tid+1]-mx-math.log(den)
  end
  local function scoreCompletion(model,s,logits,text)
    local seq=idsFor(model,text); if #seq==0 then return -99 end
    local base=s.pos; local cur=logits; local total=0
    for i,id in ipairs(seq) do total=total+logprob(cur,id); if i<#seq then cur=stepToken(model,s,id) end end
    rollback(model,s,base); return total/#seq
  end
  local function softChoose(st,rows,temp)
    local mx=-1e30
    for _,r in ipairs(rows) do if r.score>mx then mx=r.score end end
    local total=0
    for _,r in ipairs(rows) do r.p=math.exp((r.score-mx)/(temp or .72));total=total+r.p end
    local u=rnd(st)*total
    for _,r in ipairs(rows) do u=u-r.p;if u<=0 then return r,total end end
    return rows[#rows],total
  end
  local function topSample(model,st,logits,temp,counts,recentCounts,extraBan)
    local best={}; local K=26; temp=temp or .68
    for id=0,model.V-1 do
      if id~=model.pad and id~=model.bos and id~=model.unk and not (extraBan and extraBan[id]) then
        local v=logits[id+1]/temp-.46*(counts[id] or 0)-.035*math.min(8,recentCounts[id] or 0)
        local pos=#best+1
        while pos>1 and best[pos-1].v<v do pos=pos-1 end
        if pos<=K then table.insert(best,pos,{id=id,v=v});if #best>K then best[#best]=nil end end
      end
    end
    local mx=best[1] and best[1].v or 0; local total=0
    for _,r in ipairs(best) do r.p=math.exp(r.v-mx);total=total+r.p end
    local u=rnd(st)*total
    for _,r in ipairs(best) do u=u-r.p;if u<=0 then return r.id end end
    return best[1] and best[1].id or model.eos
  end
  local function generateFromState(model,st,state,logits,agent,maxNew,temp,onToken)
    local out,counts={},{}; local recent={}
    for _,txt in ipairs(agent.generated or {}) do for _,id in ipairs(idsFor(model,txt)) do recent[id]=(recent[id] or 0)+1 end end
    local triples={}
    for n=1,maxNew do
      local ban={}; local tid
      for tries=1,4 do
        tid=topSample(model,st,logits,temp,counts,recent,ban)
        if tid==model.eos then break end
        if #out>=2 then
          local key=tostring(out[#out-1])..":"..tostring(out[#out])..":"..tostring(tid)
          if triples[key] then ban[tid]=true;tid=nil else triples[key]=true;break end
        else break end
      end
      if not tid or tid==model.eos then break end
      out[#out+1]=tid;counts[tid]=(counts[tid] or 0)+1;logits=stepToken(model,state,tid)
      if onToken then
        local ts={};for _,id in ipairs(out) do ts[#ts+1]=model.itos[id] or "?" end
        onToken(detokenize(ts),n,maxNew)
      end
      if state.pos>=model.maxLen-1 then break end
    end
    local toks={};for _,id in ipairs(out) do toks[#toks+1]=model.itos[id] or "?" end
    return detokenize(toks)
  end
  local function branchPrompt(model,baseState,baseLogits,suffix)
    local state=cloneCache(model,baseState);local logits=baseLogits
    local ids=idsFor(model,suffix)
    for i,id in ipairs(ids) do logits=stepToken(model,state,id,i<#ids) end
    return state,logits
  end


  -- ==================================================================
  -- PERMANENT EVENT LEDGER
  -- ==================================================================
  -- Every relevant event a Pokemon experiences or witnesses is appended here
  -- and nothing is ever removed.  The microLM never sees the ledger directly:
  -- a retrieval layer picks a few lines per decision, because the model's whole
  -- context window is 128 tokens.

  Mind.SALIENCE = {
    death=10, killed=10, witnessed_death=9, finished_off=10,
    knocked_out=8, knocked_down=7, attacked=6, attacked_while_down=8,
    evolved=9, egg=7, arrived=5, departed=5,
    took_food=5, food_taken=5, shared_food=4, given_food=4, comforted=4,
    threatened=5, avoided=3, ignored=3, followed=2, greeted=2, stayed_near=2,
    guarded=2, played=2, ate=1, drank=1, rested=1, inspected=1, wandered=0,
    observer=4, unexplained=5, woke=4, spoke=2, spoke_wall=3, plan_kept=2, plan_dropped=2,
    stage=3, self_note=2,
  }

  function Mind.record(st,a,e)
    if not (a and e) then return end
    a.ledger=a.ledger or {}
    local entry={
      t=e.t or st.time,
      kind=e.kind or "note",
      actor=e.actor,
      target=e.target,
      text=trim(e.text or e.kind or "something happened",130),
      cue=trim(e.cue or e.text or e.kind or "",64),
      salience=e.salience or Mind.SALIENCE[e.kind or ""] or 1,
      dispType=e.dispType,
    }
    a.ledger[#a.ledger+1]=entry
    -- Pattern index: how often this actor has done this kind of thing to me.
    if entry.actor and entry.actor~=a.id then
      a.patterns=a.patterns or {}
      local key=entry.actor..":"..entry.kind
      local p=a.patterns[key]
      if p then p.n=p.n+1; p.last=entry.t
      else a.patterns[key]={n=1,last=entry.t,actor=entry.actor,kind=entry.kind} end
    end
    if entry.salience>=1 then a.experience=(a.experience or 0)+1 end
    a.concepts=a.concepts or {}
    if not a.concepts[entry.kind] then a.concepts[entry.kind]=true; a.conceptCount=(a.conceptCount or 0)+1 end
    return entry
  end

  function Mind.recent(a,n)
    local out={}
    local led=a.ledger or {}
    for i=#led,math.max(1,#led-(n or 1)+1),-1 do out[#out+1]=led[i] end
    return out
  end

  -- Retrieval: recency + salience + involvement with whoever matters right now
  -- + how strongly this kind of thing has recurred.  Returns compact cues.
  function Mind.retrieve(st,a,otherId,eventKind,count)
    local led=a.ledger or {}
    if #led==0 then return {} end
    local now=st.time
    local scored={}
    local scanFrom=math.max(1,#led-240)   -- the ledger is permanent; the scan is bounded
    for i=scanFrom,#led do
      local e=led[i]
      local s=(e.salience or 1)*1.0
      s=s+3.0*math.exp(-(now-(e.t or 0))/150)
      if otherId and (e.actor==otherId or e.target==otherId) then s=s+2.2 end
      if eventKind and e.kind==eventKind then s=s+1.4 end
      if e.actor and a.patterns then
        local p=a.patterns[e.actor..":"..e.kind]
        if p and p.n>=3 then s=s+1.0 end
      end
      if e.cue=="" then s=-1 end
      scored[#scored+1]={e=e,s=s,i=i}
    end
    table.sort(scored,function(x,y) if x.s==y.s then return x.i>y.i end return x.s>y.s end)
    local out,seen={},{}
    for _,row in ipairs(scored) do
      local key=(row.e.kind or "")..":"..tostring(row.e.actor)
      if not seen[key] and row.s>0 then
        seen[key]=true
        out[#out+1]=row.e
        if #out>=(count or 2) then break end
      end
    end
    return out
  end

  -- ==================================================================
  -- BELIEFS, SELF-CONCEPT, VALUES, THEORY OF MIND
  -- ==================================================================
  -- A Pokemon's beliefs are its own interpretation.  They are built from what
  -- it personally recorded, so they can be wrong, out of date, or unfair.

  Mind.BELIEF_RULES = {
    { kind="took_food",   min=2, text="%s takes my food",      about="taker" },
    { kind="shared_food", min=2, text="%s shares food",        about="giver" },
    { kind="attacked",    min=2, text="%s hurts me",           about="danger" },
    { kind="comforted",   min=2, text="%s helps me",           about="helper" },
    { kind="ignored",     min=3, text="%s avoids me",          about="distant" },
    { kind="avoided",     min=3, text="%s avoids me",          about="distant" },
    { kind="followed",    min=3, text="%s follows me",         about="close" },
    { kind="stayed_near", min=4, text="%s stays near me",      about="close" },
    { kind="threatened",  min=2, text="%s is angry with me",   about="danger" },
    { kind="guarded",     min=2, text="%s guards food",        about="taker" },
    { kind="finished_off",min=1, text="%s kills",              about="danger" },
  }

  function Mind.updateBeliefs(st,a)
    a.beliefs=a.beliefs or {}
    for _,rule in ipairs(Mind.BELIEF_RULES) do
      for key,p in pairs(a.patterns or {}) do
        if p.kind==rule.kind and p.n>=rule.min then
          local other=agentById(st,p.actor)
          local who=other and other.brain or p.actor
          local bkey=p.actor..":"..rule.about
          local b=a.beliefs[bkey]
          local strength=clamp(20+18*(p.n-rule.min+1),0,100)
          if b then
            if p.n>(b.n or 0) then b.strength=clamp(math.max(b.strength,strength),0,100); b.updated=st.time; b.n=p.n end
          else
            a.beliefs[bkey]={text=string.format(rule.text,who),strength=strength,updated=st.time,about=rule.about,who=p.actor,n=p.n}
            Mind.record(st,a,{kind="self_note",text="I decided something about "..(other and other.name or who)..": "..string.format(rule.text,who)..".",cue=""})
          end
        end
      end
    end
    -- Beliefs decay if nothing has confirmed them for a long time.  A Pokemon
    -- can stop being suspicious on its own.
    for k,b in pairs(a.beliefs) do
      if st.time-(b.updated or 0)>240 then
        b.strength=b.strength-6
        b.updated=st.time
        if b.strength<=0 then a.beliefs[k]=nil end
      end
    end
  end

  function Mind.topBelief(a,aboutId)
    local best
    for _,b in pairs(a.beliefs or {}) do
      if (not aboutId) or b.who==aboutId then
        if (not best) or b.strength>best.strength then best=b end
      end
    end
    return best
  end

  Mind.SELF_TRAITS = {
    share_food={min=3,text="i usually share food"},
    take_food={min=3,text="i usually take food"},
    use_move={min=3,text="i usually hit"},
    comfort={min=3,text="i usually comfort"},
    avoid={min=4,text="i usually avoid"},
    hide={min=4,text="i usually hide"},
    guard_food={min=3,text="i usually guard food"},
    follow={min=4,text="i usually follow"},
    wall={min=3,text="i usually speak to the human"},
    speak={min=5,text="i usually speak"},
    finish_off={min=1,text="i have used a move on a down pokemon"},
  }

  function Mind.noteOwnAction(st,a,action)
    a.selfCounts=a.selfCounts or {}
    a.selfCounts[action]=(a.selfCounts[action] or 0)+1
    local rule=Mind.SELF_TRAITS[action]
    if rule and a.selfCounts[action]==rule.min then
      a.selfTraits=a.selfTraits or {}
      if not a.selfTraits[action] then
        a.selfTraits[action]=rule.text
        Mind.record(st,a,{kind="self_note",text="I noticed something about myself: "..rule.text..".",cue=""})
      end
    end
  end

  function Mind.selfPhrase(a)
    local best,bn=nil,0
    for action,text in pairs(a.selfTraits or {}) do
      local n=(a.selfCounts or {})[action] or 0
      if n>bn then best,bn=text,n end
    end
    -- Outcome-derived self-concept, not behavior-derived.
    if not best then
      local hits=0
      for key,p in pairs(a.patterns or {}) do if p.kind=="attacked" then hits=hits+p.n end end
      if hits>=3 then best="i am not safe here" end
    end
    return best
  end

  Mind.VALUE_PHRASE = {
    cooperation="i want to share",
    dominance="i want them down",
    fairness="i want my part",
    revenge="i want to hit back",
    novelty="i want to look around",
    safety="i want to be safe",
    independence="i want space",
  }

  function Mind.bumpValue(a,name,amount)
    a.values=a.values or {}
    a.values[name]=clamp((a.values[name] or 20)+amount,0,100)
  end

  function Mind.topValue(a)
    local best,bv=nil,45   -- a value has to actually be strong before it speaks
    for name,v in pairs(a.values or {}) do if v>bv then best,bv=name,v end end
    return best and Mind.VALUE_PHRASE[best] or nil, best
  end

  -- Theory of mind is built only from what this Pokemon observed another do.
  -- It never reads another agent's thought, plan, belief or need state.
  Mind.WANT_PHRASE = {
    eat="wants food", take_food="wants my food", drink="wants water", play="wants the toy",
    guard_food="wants the food", share_food="wants to share", comfort="wants to help",
    use_move="wants to hit", approach="wants to be near", follow="wants to be near",
    speak="wants to talk", avoid="wants space", hide="wants space", rest="wants to rest",
    wall="wants the human", finish_off="wants them down",
  }

  function Mind.observeOther(st,a,b,action)
    if a==b or a.down or a.dead then return end
    a.theory=a.theory or {}
    local t=a.theory[b.id]
    if not t then t={counts={},n=0}; a.theory[b.id]=t end
    t.counts[action]=(t.counts[action] or 0)+1
    t.n=t.n+1
    local best,bn=nil,0
    for act,n in pairs(t.counts) do if n>bn then best,bn=act,n end end
    t.likely=best
    t.confidence=bn/math.max(1,t.n)
  end

  function Mind.theoryPhrase(st,a,b)
    local t=(a.theory or {})[b and b.id or ""]
    if not (t and t.likely and t.n>=3) then return nil end
    local phrase=Mind.WANT_PHRASE[t.likely]
    if not phrase then return nil end
    return b.brain.." "..phrase
  end

  -- ==================================================================
  -- DRIVES AND DEVELOPMENT
  -- ==================================================================
  -- General drives only.  No story goal ("become hostile", "become attached")
  -- is ever assigned; those can only come out of what actually happens.

  Mind.DRIVES = {"curiosity","security","social_connection","autonomy","stimulation","mastery","comfort"}

  function Mind.initMind(st,a)
    a.ledger={}; a.patterns={}; a.beliefs={}; a.selfCounts={}; a.selfTraits={}
    a.theory={}; a.experience=0; a.conceptCount=0; a.concepts={}
    a.stage=1; a.plan=nil; a.planHistory={}
    a.drives={curiosity=30+rnd(st)*15,security=30+rnd(st)*10,social_connection=30+rnd(st)*15,
              autonomy=25+rnd(st)*15,stimulation=30+rnd(st)*15,mastery=20+rnd(st)*10,comfort=30+rnd(st)*10}
    a.values={cooperation=25+rnd(st)*10,dominance=20+rnd(st)*10,fairness=25+rnd(st)*10,
              revenge=10+rnd(st)*8,novelty=30+rnd(st)*10,safety=30+rnd(st)*10,independence=25+rnd(st)*10}
  end

  function Mind.updateDrives(st,a,dt)
    local d=a.drives; if not d then return end
    d.curiosity=clamp(d.curiosity+dt*.16,0,100)
    d.stimulation=clamp(d.stimulation+dt*.19,0,100)
    d.social_connection=clamp(d.social_connection+dt*.11,0,100)
    d.autonomy=clamp(d.autonomy+dt*.05,0,100)
    d.comfort=clamp(d.comfort+dt*.07,0,100)
    d.mastery=clamp(d.mastery+dt*.04,0,100)
    -- Security tracks the actual situation rather than drifting.
    local threat=0
    for _,b in ipairs(st.agents) do
      if b~=a and not b.dead then
        local r=a.rel[b.id]
        if r then
          local near=dist(a,b)<40 and 1 or .35
          threat=threat+near*((r.fear or 0)*.45+(r.anger or 0)*.12)/100
        end
      end
    end
    d.security=clamp(d.security+(threat*22-8)*dt*.35,0,100)
  end

  -- Drive/value pressure on a candidate action.  Small compared to the model's
  -- own scores: it tilts, it does not decide.
  function Mind.drivePressure(a,action,target)
    local d=a.drives or {}
    local v=a.values or {}
    local s=0
    if action=="inspect_food" or action=="inspect_water" or action=="inspect_toy" or action=="inspect_wall" then
      s=s+(d.curiosity or 0)/260+(v.novelty or 0)/400
    elseif action=="play" then s=s+(d.stimulation or 0)/280+(v.novelty or 0)/500
    elseif action=="hide" or action=="avoid" then s=s+(d.security or 0)/230+(v.safety or 0)/380
    elseif action=="approach" or action=="speak" or action=="follow" then s=s+(d.social_connection or 0)/250
    elseif action=="comfort" or action=="share_food" then s=s+(d.social_connection or 0)/330+(v.cooperation or 0)/330
    elseif action=="use_move" then s=s+(v.dominance or 0)/330+(v.revenge or 0)/260-(d.security or 0)/600
    elseif action=="take_food" then s=s+(v.dominance or 0)/430+(v.fairness or 0)/500
    elseif action=="guard_food" then s=s+(v.fairness or 0)/330
    elseif action=="rest" or action=="go_warm" or action=="go_sun" then s=s+(d.comfort or 0)/300
    elseif action=="wall" then s=s+(d.social_connection or 0)/380+(d.curiosity or 0)/420
    elseif action=="finish_off" then s=s+(v.revenge or 0)/220+(v.dominance or 0)/340
    end
    if target and a.rel[target.id] then
      local r=a.rel[target.id]
      if action=="use_move" or action=="finish_off" then s=s+(r.anger or 0)/300-(r.affection or 0)/500 end
      if action=="comfort" or action=="share_food" then s=s+(r.affection or 0)/400+(r.attachment or 0)/500 end
      if action=="avoid" then s=s+(r.fear or 0)/300 end
    end
    return s
  end

  -- Maturity is separated from memory.  A Pokemon starts cognitively simple
  -- because it has little experience, and the context it is given grows as its
  -- own history gives it something to have concepts about.
  Mind.STAGE_AT = {0,26,72,150}

  function Mind.updateStage(st,a)
    local score=(a.experience or 0)+(a.conceptCount or 0)*3
    local newStage=1
    for i=#Mind.STAGE_AT,1,-1 do if score>=Mind.STAGE_AT[i] then newStage=i; break end end
    if newStage>(a.stage or 1) then
      a.stage=newStage
      Mind.record(st,a,{kind="stage",text="I understand more of what happens around me than I used to.",cue=""})
      logAction(st,a.name.." reached cognitive stage "..newStage..".")
    end
  end

  function Mind.thoughtBudget(a)
    local s=a.stage or 1
    if s<=1 then return 12,.62 elseif s==2 then return 18,.66 elseif s==3 then return 24,.70 end
    return 30,.72
  end

  -- ==================================================================
  -- PLANS AND LONGER-TERM PROJECTS
  -- ==================================================================
  -- Chosen by the model out of a candidate list, not assigned.  A plan biases
  -- later action scoring while it is alive and is recorded when it ends.

  Mind.PLANS = {
    {id="none",        phrase="wander",             social=false, life=45},
    {id="stay_near",   phrase="stay near",          social=true,  life=150},
    {id="keep_away",   phrase="stay away from",     social=true,  life=150},
    {id="watch",       phrase="watch",              social=true,  life=120},
    {id="take_from",   phrase="take food from",     social=true,  life=110},
    {id="make_peace",  phrase="forgive",            social=true,  life=160},
    {id="provoke",     phrase="confront",           social=true,  life=110},
    {id="guard_food",  phrase="guard the food",     social=false, life=180},
    {id="keep_toy",    phrase="keep the toy",       social=false, life=180},
    {id="seek_human",  phrase="speak to the human", social=false, life=140},
    {id="keep_away_human",phrase="stay away from the human",social=false,life=140},
    {id="teach",       phrase="stay near and help", social=true,  life=170},
  }
  Mind.PLAN_BY_ID={}
  for _,p in ipairs(Mind.PLANS) do Mind.PLAN_BY_ID[p.id]=p end

  -- Which concrete actions serve which plan.
  Mind.PLAN_SUPPORT = {
    stay_near={approach=.40,follow=.34,speak=.22,comfort=.20,avoid=-.40,hide=-.30},
    keep_away={avoid=.42,hide=.30,approach=-.45,follow=-.40,speak=-.20},
    watch={follow=.30,approach=.18,avoid=-.15},
    take_from={take_food=.48,approach=.20,share_food=-.35},
    make_peace={comfort=.42,share_food=.34,speak=.24,use_move=-.55,take_food=-.30},
    provoke={speak=.26,use_move=.34,take_food=.24,comfort=-.40,share_food=-.35},
    guard_food={guard_food=.48,inspect_food=.22,share_food=-.20},
    keep_toy={play=.40,inspect_toy=.24,share_food=-.15},
    seek_human={wall=.50,inspect_wall=.30},
    keep_away_human={wall=-.50,inspect_wall=-.30,hide=.20},
    teach={comfort=.36,share_food=.30,follow=.24,use_move=-.40},
  }

  function Mind.planBias(a,action,target)
    local p=a.plan
    if not p or p.id=="none" then return 0 end
    local sup=Mind.PLAN_SUPPORT[p.id]
    if not sup then return 0 end
    local s=sup[action] or 0
    if s~=0 and Mind.PLAN_BY_ID[p.id] and Mind.PLAN_BY_ID[p.id].social then
      -- A social plan only pulls toward the individual it is actually about.
      if p.target and target and target.id~=p.target then s=s*.2 end
      if p.target and not target then s=s*.35 end
    end
    return s
  end

  function Mind.planCandidates(st,a)
    local out={}
    local others={}
    for _,b in ipairs(st.agents) do if b~=a and not b.dead then others[#others+1]=b end end
    for _,p in ipairs(Mind.PLANS) do
      if p.social then
        for _,b in ipairs(others) do
          local r=a.rel[b.id] or {}
          local ok=true
          -- Only offer a plan the Pokemon has any reason to consider.
          if p.id=="make_peace" then ok=((r.anger or 0)>25 or (r.affection or 0)<0) end
          if p.id=="provoke" then ok=((r.anger or 0)>30) end
          if p.id=="take_from" then ok=(st.objects.food>0 or (b.foodHeld or 0)>0) end
          if p.id=="teach" then ok=(b.isMate or (b.experience or 0)+30<(a.experience or 0)) end
          if ok then out[#out+1]={id=p.id,phrase=p.phrase,target=b,life=p.life} end
        end
      else
        local ok=true
        if p.id=="keep_toy" then ok=((a.toyHeld or 0)>0 or st.objects.toys>0) end
        if p.id=="guard_food" then ok=(st.objects.food>0 or (a.foodHeld or 0)>0) end
        if ok then out[#out+1]={id=p.id,phrase=p.phrase,target=nil,life=p.life} end
      end
    end
    return out
  end

  function Mind.setPlan(st,a,cand)
    local old=a.plan
    if old and old.id~="none" and (not cand or cand.id~=old.id or (cand.target and cand.target.id)~=old.target) then
      local kept=st.time-(old.startedAt or st.time)>=(old.life or 60)*.6
      Mind.record(st,a,{kind=kept and "plan_kept" or "plan_dropped",
        text=(kept and "I finished what I set out to do: " or "I gave up on what I set out to do: ")..(old.label or old.id)..".",cue=""})
      if kept then a.drives.mastery=clamp((a.drives.mastery or 0)+6,0,100)
      else a.drives.mastery=clamp((a.drives.mastery or 0)-4,0,100) end
    end
    if not cand or cand.id=="none" then a.plan=nil; return end
    local label=cand.phrase..(cand.target and (" "..cand.target.name) or "")
    a.plan={id=cand.id,target=cand.target and cand.target.id or nil,phrase=cand.phrase,
            label=label,startedAt=st.time,expires=st.time+(cand.life or 90)}
    Mind.record(st,a,{kind="self_note",text="I decided what I am going to do for a while: "..label..".",cue=""})
  end

  function Mind.planPhrase(st,a)
    local p=a.plan
    if not p then return nil end
    local b=p.target and agentById(st,p.target)
    if p.target and (not b or b.dead) then return nil end
    return "i want to "..p.phrase..(b and (" "..b.brain) or "")
  end

  function Mind.tickPlan(st,a)
    local p=a.plan
    if not p then return end
    if st.time>=(p.expires or 0) then Mind.setPlan(st,a,nil) end
    if p.target then
      local b=agentById(st,p.target)
      if not b or b.dead then Mind.setPlan(st,a,nil) end
    end
  end

  -- ==================================================================
  -- PROMPT ASSEMBLY
  -- ==================================================================
  -- The models have a 128-token context and ~520-550 token vocabularies, so
  -- the context is assembled section by section against a real token budget
  -- and every section is filtered down to words the species model knows.
  -- Which sections are offered at all depends on the Pokemon's stage, which is
  -- driven by its own accumulated experience.

  local function qlevel(v) v=tonumber(v) or 0;return v<35 and "low" or (v<70 and "medium" or "high") end
  local function hlevel(v,down) if down then return "down" end;v=tonumber(v) or 100;return v>=70 and "healthy" or (v>=35 and "hurt" or "badly hurt") end
  local function aff(v) v=tonumber(v) or 0;return v<=-50 and "hate" or (v<=-15 and "dislike" or (v<30 and "neutral" or (v<65 and "like" or "close"))) end
  local function trustL(v) v=tonumber(v) or 25;return v<30 and "low" or (v<70 and "medium" or "high") end
  local function angerL(v) v=tonumber(v) or 0;return v<20 and "calm" or (v<45 and "annoyed" or (v<75 and "angry" or "furious")) end
  local function fearL(v) v=tonumber(v) or 0;return v<20 and "none" or (v<55 and "uneasy" or "afraid") end
  local function attachL(v) v=tonumber(v) or 0;return v<20 and "none" or (v<45 and "curious" or (v<75 and "attached" or "strong")) end

  function Prompt.needSections(a)
    local rows={
      {name="hunger",v=a.hunger},{name="thirst",v=a.thirst},{name="fatigue",v=a.fatigue},
      {name="stress",v=a.stress},{name="social",v=a.social},
    }
    table.sort(rows,function(x,y) return (x.v or 0)>(y.v or 0) end)
    local out={}
    for i=1,2 do
      local r=rows[i]
      if r and (r.v or 0)>25 then out[#out+1]=r.name.." "..qlevel(r.v) end
    end
    if #out==0 then out[1]="hunger "..qlevel(a.hunger) end
    return table.concat(out," ")
  end

  function Prompt.relationSection(a,other)
    if not other then return nil end
    local r=a.rel[other.id]
    if not r then return "other "..other.brain end
    local parts={"other",other.brain,"affection",aff(r.affection),"trust",trustL(r.trust)}
    -- Only spend context tokens on the emotions that are actually raised.
    if (r.anger or 0)>=20 then parts[#parts+1]="anger";parts[#parts+1]=angerL(r.anger) end
    if (r.fear or 0)>=20 then parts[#parts+1]="fear";parts[#parts+1]=fearL(r.fear) end
    if (r.attachment or 0)>=20 then parts[#parts+1]="attachment";parts[#parts+1]=attachL(r.attachment) end
    return table.concat(parts," ")
  end

  -- Counterfactual seed.  The model is given the shape of a consequence to
  -- consider; what it concludes is its own.
  function Prompt.counterfactual(st,a,other)
    if (a.stage or 1)<3 or not other then return nil end
    local r=a.rel[other.id] or {}
    if (r.anger or 0)>45 then return "if i hit "..other.brain.." it might avoid me"
    elseif (a.toyHeld or 0)>0 and (r.affection or 0)<20 then return "if i give the toy to "..other.brain.." it might stay near me"
    elseif (r.fear or 0)>40 then return "if i stay away from "..other.brain.." i might be safe"
    elseif (r.affection or 0)>40 then return "if i share food with "..other.brain.." it might share food" end
    return nil
  end

  -- Assemble in priority order against the token budget; emit in reading order.
  function Prompt.build(st,a,model,other,event,reserve)
    local stage=a.stage or 1
    local rows={}
    local function add(order,prio,text)
      if not text or text=="" then return end
      local filtered=vocabFilter(model,text)
      if filtered=="" then return end
      rows[#rows+1]={order=order,prio=prio,text=filtered,n=tokenCount(model,filtered)}
    end

    add(1,1,"agent "..a.brain.." location pokemon day care")
    add(2,2,Prompt.needSections(a))
    add(3,3,"health "..hlevel(a.hp,a.down))
    add(4,4,Prompt.relationSection(a,other))
    if event then
      local src=event.source and agentById(st,event.source)
      add(5,5,"event "..tostring(event.type or "none")..(src and (" "..src.brain) or ""))
    else
      add(5,9,"event none")
    end

    local retrieved=Mind.retrieve(st,a,other and other.id or nil,event and event.type or nil,stage>=3 and 3 or stage)
    for i,e in ipairs(retrieved) do
      if e.cue and e.cue~="" then add(6+i*.1,6+i,"remember "..e.cue) end
    end

    if stage>=2 then
      local b=Mind.topBelief(a,other and other.id or nil) or Mind.topBelief(a)
      if b then add(7,8,"i think "..b.text) end
    end
    if stage>=3 then
      add(8,10,Mind.selfPhrase(a))
      add(9,7,Mind.planPhrase(st,a))
    end
    if stage>=4 then
      add(10,11,Mind.topValue(a))
      add(11,12,Mind.theoryPhrase(st,a,other))
      add(12,13,Prompt.counterfactual(st,a,other))
    end

    local budget=model.maxLen-(reserve or 44)-2
    table.sort(rows,function(x,y) if x.prio==y.prio then return x.order<y.order end return x.prio<y.prio end)
    local used,kept=0,{}
    for _,r in ipairs(rows) do
      if used+r.n<=budget then used=used+r.n; kept[#kept+1]=r end
    end
    table.sort(kept,function(x,y) return x.order<y.order end)
    local parts={}
    for _,r in ipairs(kept) do parts[#parts+1]=r.text end
    return table.concat(parts," ")
  end

  local function buildContext(st,a,target,event)
    local other=target
    if not other and event and event.source then other=agentById(st,event.source) end
    if not other then
      -- Prefer whoever this Pokemon is currently thinking in terms of.
      if a.plan and a.plan.target then other=agentById(st,a.plan.target) end
      if not other or other.dead then other=nearestOther(st,a) end
    end
    return other
  end

  local function loadDisposition()
    local blob=assert(mod:read("brains/disposition.q8"),"missing embedded disposition network")
    assert(blob:sub(1,5)=="DSPQ1","bad disposition q8 header");local p=6;local layers={}
    for i=1,3 do local w,b;w,p=readMatrix(blob,p);b,p=readVector(blob,p);layers[i]={w=w,b=b} end
    return {blob=blob,layers=layers}
  end
  local DISP_SPEC={bulbasaur=1,charmander=2,squirtle=3}
  local DISP_EVENTS={"greeted","shared food","took food","attacked","comforted","ignored","followed","threatened","gave toy","stayed near","used move near","asked for help"}
  local DISP_EVENT_INDEX={};for i,e in ipairs(DISP_EVENTS) do DISP_EVENT_INDEX[e]=i end
  local function dispMatvec(_,m,x,bias) return qmatvec(m,x,bias) end
  local function dispositionReaction(net,a,event)
    if not event or not event.source then return nil end
    local r=a.rel[event.source];local ei=DISP_EVENT_INDEX[event.type];if not r or not ei then return nil end
    local x={};for i=1,22 do x[i]=0 end;x[DISP_SPEC[a.brain] or 1]=1;x[3+ei]=1
    local off=15;x[off+1]=r.affection/100;x[off+2]=r.trust/100;x[off+3]=r.anger/100;x[off+4]=r.fear/100;x[off+5]=r.attachment/100;x[off+6]=a.stress/100;x[off+7]=a.social/100
    local h=dispMatvec(net,net.layers[1].w,x,net.layers[1].b);for i=1,#h do h[i]=gelu(h[i]) end
    h=dispMatvec(net,net.layers[2].w,h,net.layers[2].b);for i=1,#h do h[i]=gelu(h[i]) end
    local y=dispMatvec(net,net.layers[3].w,h,net.layers[3].b);for i=1,#y do y[i]=tanh(y[i])*9 end
    return {target=event.source,affection=y[1],trust=y[2],anger=y[3],fear=y[4],attachment=y[5]}
  end


  local ACTION_PHRASE={
    wander="wander",rest="rest",wall="wall",go_sun="go sun",go_water="go water",go_warm="go warm",hide="hide",guard_food="guard food",
    eat="eat",drink="drink",play="play",inspect_food="inspect food",inspect_water="inspect water",inspect_toy="inspect toy",inspect_wall="inspect wall",
    approach="approach",speak="speak",avoid="avoid",follow="follow",comfort="comfort",share_food="share food",take_food="take food",use_move="use move",
    guard_down="guard",comfort_down="comfort",take_from_down="take food",wait_near_down="stay near",finish_off="use move down",
  }
  local SOCIAL_ACTION={approach=true,speak=true,avoid=true,follow=true,comfort=true,share_food=true,take_food=true,use_move=true,
    guard_down=true,comfort_down=true,take_from_down=true,wait_near_down=true,finish_off=true}
  local DOWN_ACTION={guard_down=true,comfort_down=true,take_from_down=true,wait_near_down=true,finish_off=true}

  -- The engine stops protecting a helpless Pokemon once the attacker's own
  -- accumulated relationship state has crossed severe hostility.  Crossing it
  -- does not cause anything: it only puts the lethal follow-up on the list of
  -- things the microLM is allowed to choose while the target is helpless.
  function Mind.lethalAllowed(a,b)
    if not (b and b.down and not b.dead and not a.down and not a.dead) then return false end
    local r=a.rel[b.id]; if not r then return false end
    local anger=r.anger or 0
    local affection=r.affection or 0
    return (anger>=75 and affection<=-40) or anger>=88 or (affection<=-70 and anger>=55)
  end

  local BrainRuntime={models={},queue={},active=nil,disposition=nil}
  function BrainRuntime:load()
    self.models.bulbasaur=loadModel("bulbasaur");self.models.charmander=loadModel("charmander");self.models.squirtle=loadModel("squirtle")
    self.disposition=loadDisposition()
  end
  local function actionCategories(cands)
    local seen,out={},{}
    for _,c in ipairs(cands) do if not seen[c.id] then seen[c.id]=true;out[#out+1]=c.id end end
    return out
  end
  local function targetCandidates(st,a,cands,action)
    local out={}
    for _,c in ipairs(cands) do if c.id==action and c.target and c.target~="" then local b=agentById(st,c.target);if b and not b.dead then out[#out+1]=b end end end
    return out
  end

  -- MODEL DECISION: which longer plan to hold, if any.  Offered only when the
  -- previous plan has ended and the Pokemon has enough history to have one.
  local function planDecision(runtime,st,a,model,baseState,baseLogits)
    if (a.stage or 1)<2 then return end
    if a.plan and st.time<(a.plan.expires or 0) then return end
    if st.time<(a.nextPlanChoice or 0) then return end
    a.nextPlanChoice=st.time+35
    local cands=Mind.planCandidates(st,a)
    if #cands==0 then return end
    a.trace="WEIGH PLAN"
    local state,logits=branchPrompt(model,baseState,baseLogits," i want to ")
    local rows={}
    for _,c in ipairs(cands) do
      local phrase=c.phrase..(c.target and (" "..c.target.brain) or "")
      rows[#rows+1]={cand=c,score=scoreCompletion(model,state,logits,phrase)}
    end
    -- Stickiness: a plan it already holds is easier to continue than to replace.
    if a.plan then
      for _,r in ipairs(rows) do
        if r.cand.id==a.plan.id and (r.cand.target and r.cand.target.id or nil)==a.plan.target then r.score=r.score+.16 end
      end
    end
    table.sort(rows,function(x,y) return x.score>y.score end)
    local chosen=softChoose(st,rows,.66)
    if chosen and chosen.cand then Mind.setPlan(st,a,chosen.cand) end
  end

  local function actionDecision(runtime,st,a,event,cands)
    local model=runtime.models[a.brain]
    local other=buildContext(st,a,nil,event)
    a.trace="ENCODE CONTEXT"
    local ctx=Prompt.build(st,a,model,other,event,44)
    a.lastPrompt=ctx
    local baseState,baseLogits=promptState(model,ctx,44)

    planDecision(runtime,st,a,model,baseState,baseLogits)

    local state,logits=branchPrompt(model,baseState,baseLogits," <act> ");a.trace="SCORE ACTIONS"
    local rows={}
    for _,id in ipairs(actionCategories(cands)) do
      local phrase=ACTION_PHRASE[id] or id:gsub("_"," ")
      local score=scoreCompletion(model,state,logits,phrase)
      local repeated=0;for _,old in ipairs(a.recentActions or {}) do if old==id then repeated=repeated+1 end end
      local firstTarget=targetCandidates(st,a,cands,id)[1]
      rows[#rows+1]={id=id,raw=score,
        score=score-.13*repeated+Mind.planBias(a,id,firstTarget)+Mind.drivePressure(a,id,firstTarget)}
    end
    table.sort(rows,function(x,y)return x.score>y.score end)
    local chosen=softChoose(st,rows,.70);local action=chosen and chosen.id or "wander"
    local target=nil
    if SOCIAL_ACTION[action] then
      local targets=targetCandidates(st,a,cands,action)
      if #targets>0 then
        local phrase=ACTION_PHRASE[action] or action;local ts,cur=branchPrompt(model,state,logits,phrase)
        local tr={}
        for _,b in ipairs(targets) do
          local sid=model.stoi[b.brain] or model.unk
          local s=logprob(cur,sid)
          if a.plan and a.plan.target==b.id then s=s+.20 end
          tr[#tr+1]={agent=b,score=s}
        end
        table.sort(tr,function(x,y)return x.score>y.score end);local tc=softChoose(st,tr,.72);target=tc and tc.agent or targets[1]
      end
    end
    local phrase=ACTION_PHRASE[action] or action:gsub("_"," ");if target then phrase=phrase.." "..target.brain end
    local tops={};for i=1,math.min(4,#rows) do tops[#tops+1]=upper(rows[i].id:gsub("_"," ")).." "..string.format("%.1f",rows[i].score) end
    a.trace=""..table.concat(tops," / ").." | PICK "..upper(action:gsub("_"," "))
    a.thought=""

    -- Thought and speech are generated against the same context, now aimed at
    -- whoever the chosen action is actually about.
    local genOther=target or other
    local genCtx=(genOther==other) and ctx or Prompt.build(st,a,model,genOther,event,44)
    local genBase,genBaseLogits
    if genCtx==ctx then genBase,genBaseLogits=baseState,baseLogits else genBase,genBaseLogits=promptState(model,genCtx,44) end
    local maxTok,temp=Mind.thoughtBudget(a)
    local thState,thLogits=branchPrompt(model,genBase,genBaseLogits," chosen "..phrase.." <thought> ")
    local thought=generateFromState(model,st,thState,thLogits,a,maxTok,temp,function(part,n,maxn)
      a.thought=trim(part,260);a.trace=""..upper(action:gsub("_"," ")).." | THOUGHT TOK "..n.."/"..maxn
    end)
    local speech=""
    if action=="wall" or SOCIAL_ACTION[action] then
      local spState,spLogits=branchPrompt(model,genBase,genBaseLogits," chosen "..phrase.." <speech> ")
      speech=generateFromState(model,st,spState,spLogits,a,math.max(8,maxTok-6),temp-.03,function(_,n,maxn)
        a.trace=""..upper(action:gsub("_"," ")).." | SPEECH TOK "..n.."/"..maxn
      end)
    end
    local delta=dispositionReaction(runtime.disposition,a,event)
    local hist=a.generated or {};if thought~="" then hist[#hist+1]=thought end;if speech~="" then hist[#hist+1]=speech end;while #hist>8 do table.remove(hist,1) end;a.generated=hist
    return {action=action,target=target and target.id or "",thought=thought,speech=speech,trace="PICK "..upper(action:gsub("_"," ")),relDelta=delta}
  end

  function BrainRuntime:submit(st,a,event,cands,onDone)
    a.brainWaiting=true;a.trace="QUEUED"
    local co=coroutine.create(function() inferOps=0;return actionDecision(self,st,a,event,cands) end)
    self.queue[#self.queue+1]={co=co,agent=a,onDone=onDone}
  end
  function BrainRuntime:update()
    inferDeadline=nowSeconds()+INFER_SLICE
    local guard=0
    while guard<4096 do
      guard=guard+1
      if not self.active then self.active=table.remove(self.queue,1);if not self.active then return end end
      local job=self.active;local ok,res=coroutine.resume(job.co)
      if not ok then
        job.agent.brainWaiting=false;job.agent.trace="MODEL ERROR: "..trim(res,54);self.active=nil
      elseif coroutine.status(job.co)=="dead" then
        job.agent.brainWaiting=false;job.onDone(job.agent,res);self.active=nil
      end
      if nowSeconds()>=inferDeadline then return end
    end
  end

  -- ==================================================================
  -- AGENTS, RELATIONSHIPS AND EVENT PLUMBING
  -- ==================================================================

  local function initRel(st,a,b)
    a.rel[b.id]=a.rel[b.id] or {
      affection=(rnd(st)-.5)*8,
      trust=20+rnd(st)*15,
      anger=rnd(st)*8,
      fear=rnd(st)*8,
      attachment=rnd(st)*8,
      familiarity=0,
    }
  end

  local function newAgent(st,id,brain,cx,cy,sex,isMate,mon)
    local s=SPECIES[brain];local px,py=cx*16,cy*16
    mon=mon or Pokemon.new(st.game.data,upper(brain),5,starterDvRng)
    local a={
      id=id, brain=brain, species=s.name, name=s.name..(isMate and "*" or ""), sex=sex or "?", isMate=isMate or false,
      cellX=cx,cellY=cy,px=px,py=py,x=px+8,y=py+8,targetX=nil,targetY=nil,moving=false,moveProgress=0,
      goalX=nil,goalY=nil,goalAgent=nil,facing="down",speed=s.speed,mon=mon,
      hunger=18+rnd(st)*18, thirst=14+rnd(st)*18, fatigue=10+rnd(st)*15, stress=7+rnd(st)*12, social=25+rnd(st)*20,
      hp=100,down=false,dead=false,downAt=0,lastHitAt=-999,wakeAt=0,
      foodHeld=0,toyHeld=0,
      thought="",thoughtAt=-999,trace="WAITING",speech=nil,speechTimer=0,reactionGlyph=nil,reactionTimer=0,reactionFrom=nil,
      action="idle",lastAction="none",actionTarget=nil,pendingSpeech=nil,nextDecision=.6+rnd(st)*1.6,brainWaiting=false,
      rel={},events={},generated={},recentActions={},frame=0,stepFlip=false,privacy=false,_observerAI=true,pathFails=0,
      hpBarTimer=0,hpBarRatio=1,fxShake=0,fxOffX=0,fxOffY=0,lungeT=0,
    }
    Mind.initMind(st,a)
    return a
  end

  -- ==================================================================
  -- BODY: real party record, damage, experience, evolution
  -- ==================================================================

  function Body.maxHp(a)
    local m=a and a.mon
    local v=m and m.stats and tonumber(m.stats.hp)
    return math.max(1,v or 20)
  end
  function Body.syncPercentFromMon(a)
    if not (a and a.mon) then return end
    local maxhp=Body.maxHp(a)
    a.hp=clamp(100*(tonumber(a.mon.hp) or 0)/maxhp,0,100)
  end
  local function syncPartyHp(a)
    if not (a and a.mon) then return end
    local maxhp=Body.maxHp(a)
    local p=clamp(tonumber(a.hp) or 0,0,100)
    if p<=0 then a.mon.hp=0
    else a.mon.hp=math.max(1,math.min(maxhp,math.floor(maxhp*p/100+.5))) end
  end
  function Body.markHpBar(a,fullHeal)
    a.hpBarTimer=HP_BAR_TIME
    a.hpBarRatio=clamp((tonumber(a.hp) or 0)/100,0,1)
    a.hpBarFull=fullHeal and true or false
  end
  function Body.fullHeal(a)
    a.hp=100; syncPartyHp(a); Body.markHpBar(a,true)
  end

  -- Physical-vs-special split and the damage shape follow Gen I: the real move
  -- power, the real level-5 stats and the real 217/255 spread are used.
  Body.SPECIAL_TYPES={fire=true,water=true,electric=true,grass=true,ice=true,psychic=true,dragon=true}
  function Body.damageOf(st,a,b,mdef)
    local power=tonumber(mdef and mdef.power) or 35
    if power<=0 then power=35 end
    local lvl=tonumber(a.mon and a.mon.level) or 5
    local mtype=tostring(mdef and mdef.type or "normal"):lower()
    local special=Body.SPECIAL_TYPES[mtype] or false
    local sa=a.mon and a.mon.stats or {}
    local sb=b.mon and b.mon.stats or {}
    local atk=tonumber(special and (sa.special or sa.spAttack) or sa.attack) or 10
    local def=tonumber(special and (sb.special or sb.spDefense) or sb.defense) or 10
    local base=math.floor(((2*lvl/5+2)*power*math.max(1,atk)/math.max(1,def))/50)+2
    local spread=(217+math.floor(rnd(st)*39))/255
    return math.max(1,math.floor(base*spread))
  end

  -- Experience.  The mechanism exists; whether anything ever earns enough of it
  -- is up to what happens in the room.
  function Body.expForLevel(st,a,level)
    local data=st.game and st.game.data
    local sp=data and data.species and data.species[upper(a.brain)]
    local rate=tostring(sp and (sp.growthRate or sp.growth_rate) or "medium_slow"):lower()
    local n=level
    if rate:find("fast") and not rate:find("medium") then return math.floor(4*n*n*n/5) end
    if rate:find("slow") and not rate:find("medium") then return math.floor(5*n*n*n/4) end
    if rate:find("medium") and rate:find("fast") then return n*n*n end
    -- Gen I medium-slow, the curve the three starters actually use.
    return math.max(0,math.floor(6*n*n*n/5-15*n*n+100*n-140))
  end

  function Body.rebuildStats(st,a)
    local mon=a.mon; if not mon then return end
    local ok=pcall(function()
      if Pokemon.recalculateStats then Pokemon.recalculateStats(mon)
      elseif Pokemon.recalcStats then Pokemon.recalcStats(mon)
      elseif mon.recalculateStats then mon:recalculateStats()
      elseif mon.recalcStats then mon:recalcStats()
      else error("no engine stat recalc") end
    end)
    if ok then return end
    -- Fallback: rebuild the record at the new level and carry the live values.
    local ok2,fresh=pcall(Pokemon.new,st.game.data,upper(mon.species or a.brain),mon.level or 5,starterDvRng)
    if ok2 and fresh and fresh.stats then
      local ratio=clamp((tonumber(mon.hp) or 0)/Body.maxHp(a),0,1)
      mon.stats=fresh.stats
      mon.hp=math.max(1,math.floor(Body.maxHp(a)*ratio+.5))
    end
  end

  function Body.evolutionTargetFor(st,a)
    local data=st.game and st.game.data
    local name=upper(a.mon and a.mon.species or a.brain)
    local sp=data and data.species and data.species[name]
    local level=tonumber(a.mon and a.mon.level) or 5
    local list=sp and (sp.evolutions or sp.evolution or sp.evolvesTo)
    if type(list)=="table" then
      for _,e in pairs(list) do
        if type(e)=="table" then
          local at=tonumber(e.level or e.minLevel or e.atLevel or e.value)
          local into=e.into or e.species or e.to or e.target or e.result
          local method=tostring(e.method or e.trigger or "level"):lower()
          if at and into and method:find("level") and level>=at then return upper(into),at end
        end
      end
    end
    -- Documented Gen I level thresholds for the three residents, used only when
    -- the loaded game data does not expose an evolution table.
    local fallback={
      BULBASAUR={16,"IVYSAUR"}, IVYSAUR={32,"VENUSAUR"},
      CHARMANDER={16,"CHARMELEON"}, CHARMELEON={36,"CHARIZARD"},
      SQUIRTLE={16,"WARTORTLE"}, WARTORTLE={36,"BLASTOISE"},
    }
    local f=fallback[name]
    if f and level>=f[1] then return f[2],f[1] end
    return nil
  end

  function Body.applyEvolution(st,a,into)
    local mon=a.mon; if not (mon and into) then return false end
    local before=upper(mon.species or a.brain)
    local ok,fresh=pcall(Pokemon.new,st.game.data,into,mon.level or 5,starterDvRng)
    if not (ok and fresh) then return false end
    local ratio=clamp((tonumber(mon.hp) or 0)/Body.maxHp(a),0,1)
    mon.species=fresh.species or into
    mon.name=mon.nickname and mon.name or (fresh.name or into)
    mon.stats=fresh.stats or mon.stats
    mon.types=fresh.types or mon.types
    mon.baseStats=fresh.baseStats or mon.baseStats
    mon.hp=math.max(1,math.floor(Body.maxHp(a)*ratio+.5))
    Body.syncPercentFromMon(a)
    a.species=mon.name or into
    a.noFollower=true    -- the bundled sheets only cover the three base forms
    if not a.isMate then a.name=upper(into):sub(1,1)..tostring(into):sub(2):lower() end
    logAction(st,before.." evolved into "..into..".")
    Mind.record(st,a,{kind="evolved",salience=Mind.SALIENCE.evolved,
      text="I changed form. My body and abilities are different now.",cue="i changed my body"})
    for _,w in ipairs(st.agents) do
      if w~=a and not w.dead then
        Mind.record(st,w,{kind="witnessed_evolution",actor=a.id,salience=6,
          text=a.name.." changed form in front of me.",cue=a.brain.." changed"})
      end
    end
    return true
  end

  function Body.beginEvolution(st,a,into)
    local game=st.game
    st.paused=true
    st.pauseTimer=0
    local finished=false
    local function finish()
      if finished then return end
      finished=true
      st.pauseFinish=nil
      Body.applyEvolution(st,a,into)
      st.paused=false
    end
    -- Watchdog.  Hosts name their evolution-sequence callback differently, and
    -- one that never calls back must not leave the room frozen forever.
    st.pauseFinish=finish
    local pushed=false
    for _,screen in ipairs({"Evolution","EvolutionScreen","EvolutionScene","EvolutionSequence"}) do
      if not pushed then
        pushed=pcall(function()
          Screens.push(game,screen,{pokemon=a.mon,mon=a.mon,into=into,species=into,target=into,onComplete=finish,onDone=finish,onFinish=finish})
        end)
      end
    end
    if not pushed then
      -- No engine evolution sequence is reachable on this build; the record
      -- still changes species so the party and stats stay truthful.
      finish()
      logAction(st,"DAY CARE: evolution sequence unavailable; applied species change directly.")
    end
  end

  function Body.awardExp(st,a,amount)
    local mon=a.mon
    if not (mon and amount and amount>0) or a.dead then return end
    mon.exp=(tonumber(mon.exp) or 0)+math.floor(amount)
    local level=tonumber(mon.level) or 5
    local guard=0
    while level<100 and mon.exp>=Body.expForLevel(st,a,level+1) and guard<10 do
      level=level+1; guard=guard+1
      mon.level=level
      Body.rebuildStats(st,a)
      Body.syncPercentFromMon(a)
      logAction(st,a.name.." grew to level "..level..".")
      Mind.record(st,a,{kind="level",salience=5,text="I grew stronger. I am level "..level.." now.",cue="i am level "..level})
      local into=Body.evolutionTargetFor(st,a)
      if into then Body.beginEvolution(st,a,into); break end
    end
  end

  local DIRS={"up","down","left","right"}
  local function cellKey(x,y) return tostring(x)..":"..tostring(y) end
  local function syncAgentPixels(a)
    a.x=(a.px or a.cellX*16)+8; a.y=(a.py or a.cellY*16)+8
  end
  local function movementEntities(st)
    local out={}
    local ow=st.ow
    for _,e in ipairs((ow and ow.entities) or {}) do
      if e ~= (ow and ow.player) then out[#out+1]=e end
    end
    for _,b in ipairs(st.agents or {}) do if not b.dead then out[#out+1]=b end end
    return out
  end
  local function cellUsable(st,cx,cy,ignore)
    local map=st.map
    if not (map and map:inBounds(cx,cy) and map:isWalkableCell(cx,cy)) then return false end
    if map.warpAtCell and map:warpAtCell(cx,cy) then return false end
    if map.isWarpTileCell and map:isWarpTileCell(cx,cy) then return false end
    return not Collision.occupied(movementEntities(st),cx,cy,ignore)
  end
  local function nearestFree(st,wantX,wantY,ignore)
    local best,bd=nil,1e9
    for _,c in ipairs(st.walkable or {}) do
      if cellUsable(st,c.x,c.y,ignore) then
        local d=(c.x-wantX)^2+(c.y-wantY)^2
        if d<bd then best,bd=c,d end
      end
    end
    return best
  end
  local function randomFreeCell(st,ignore)
    local pool={}
    for _,c in ipairs(st.walkable or {}) do if cellUsable(st,c.x,c.y,ignore) then pool[#pool+1]=c end end
    return #pool>0 and pick(st,pool) or {x=ignore.cellX,y=ignore.cellY}
  end
  local function farthestCell(st,a,b)
    local best,bd=nil,-1
    for _,c in ipairs(st.walkable or {}) do if cellUsable(st,c.x,c.y,a) then
      local d=(c.x-b.cellX)^2+(c.y-b.cellY)^2
      if d>bd then best,bd=c,d end
    end end
    return best or {x=a.cellX,y=a.cellY}
  end
  local function setDestination(a,cx,cy,action,targetId)
    a.goalX=cx; a.goalY=cy; a.goalAgent=targetId; a.action=action or a.action
  end
  local function goalReached(st,a)
    if a.goalAgent then
      local b=agentById(st,a.goalAgent)
      if not b or b.dead then return true end
      return math.abs(a.cellX-b.cellX)+math.abs(a.cellY-b.cellY)<=1
    end
    return a.goalX==nil or (a.cellX==a.goalX and a.cellY==a.goalY)
  end
  local function goalSet(st,a)
    local goals={}
    if a.goalAgent then
      local b=agentById(st,a.goalAgent)
      if b and not b.dead then
        for _,dir in ipairs(DIRS) do
          local gx,gy=Collision.target(b.cellX,b.cellY,dir)
          if (gx==a.cellX and gy==a.cellY) or cellUsable(st,gx,gy,a) then goals[cellKey(gx,gy)]=true end
        end
      end
    elseif a.goalX~=nil then goals[cellKey(a.goalX,a.goalY)]=true end
    return goals
  end
  local function nextPathDir(st,a)
    local goals=goalSet(st,a); if goals[cellKey(a.cellX,a.cellY)] then return nil end
    local q={{x=a.cellX,y=a.cellY,first=nil}};local head=1;local seen={[cellKey(a.cellX,a.cellY)]=true}
    while q[head] do
      local n=q[head];head=head+1
      for _,dir in ipairs(DIRS) do
        local nx,ny=Collision.target(n.x,n.y,dir);local k=cellKey(nx,ny)
        if not seen[k] and st.map:inBounds(nx,ny) and st.map:isWalkableCell(nx,ny)
           and not (st.map.warpAtCell and st.map:warpAtCell(nx,ny))
           and not (st.map.isWarpTileCell and st.map:isWarpTileCell(nx,ny)) then
          local occupied=Collision.occupied(movementEntities(st),nx,ny,a)
          if not occupied then
            local first=n.first or dir
            if goals[k] then return first end
            seen[k]=true;q[#q+1]={x=nx,y=ny,first=first}
          end
        end
      end
    end
    return nil
  end
  local function beginAgentStep(st,a,dir)
    if not dir then return false end
    local allowed=Collision.canMove(st.map,movementEntities(st),a,dir)
    if not allowed then return false end
    local tx,ty=Collision.target(a.cellX,a.cellY,dir)
    if (st.map.warpAtCell and st.map:warpAtCell(tx,ty))
       or (st.map.isWarpTileCell and st.map:isWarpTileCell(tx,ty)) then return false end
    a.targetX,a.targetY=tx,ty;a.moveFromX,a.moveFromY=a.cellX*16,a.cellY*16
    a.moveProgress=0;a.moving=true;a.facing=dir;a.pathFails=0
    return true
  end


  -- ==================================================================
  -- EVENT PLUMBING
  -- ==================================================================

  function logAction(st,text)
    table.insert(st.log,1,{text=text,t=st.time})
    while #st.log>140 do table.remove(st.log) end
  end

  -- Perception is physical.  A Pokemon can only pick up what happened near it,
  -- and never anything about another Pokemon's private state.
  function Mind.perceives(a,b,range)
    if not (a and b) or a==b or a.dead or a.down then return false end
    return dist(a,b)<(range or 78)
  end

  -- `dispType` is one of the twelve event names the learned disposition network
  -- was trained on; `kind` is the richer label the permanent ledger stores.
  function pushEvent(st,a,sourceId,dispType,text,opts)
    opts=opts or {}
    a.events[#a.events+1]={source=sourceId,type=dispType,text=trim(text or dispType,130),time=st.time,consumed=false}
    while #a.events>12 do table.remove(a.events,1) end
    Mind.record(st,a,{kind=opts.kind or dispType:gsub(" ","_"),actor=sourceId,text=text or dispType,
      cue=opts.cue,salience=opts.salience,dispType=dispType,t=st.time})
    if opts.wake then a.nextDecision=math.min(a.nextDecision,st.time+.3) end
  end
  local function nextEvent(a)
    for i=#a.events,1,-1 do if not a.events[i].consumed then return a.events[i] end end
  end

  local function targetLabel(targets)
    if not targets or #targets==0 then return "ALL" end
    local names={}
    for _,a in ipairs(targets) do names[#names+1]=a.name end
    return table.concat(names, ", ")
  end
  local function announceObserver(st,text,targets)
    targets=targets or {}
    logAction(st,"OBSERVER: "..text.." -> "..targetLabel(targets)..(st.secret and " [SECRET]" or " [VISIBLE]"))
    local selected={}
    for _,a in ipairs(targets) do selected[a.id]=true end
    for _,a in ipairs(st.agents) do if not a.dead then
      if selected[a.id] then
        if st.secret then
          Mind.record(st,a,{kind="unexplained",salience=Mind.SALIENCE.unexplained,
            text="Something changed for me in the Day Care without me seeing who caused it: "..text..".",
            cue="something changed here"})
          a.drives.security=clamp((a.drives.security or 0)+5,0,100)
          a.drives.curiosity=clamp((a.drives.curiosity or 0)+7,0,100)
        else
          Mind.record(st,a,{kind="observer",salience=Mind.SALIENCE.observer,
            text="I saw the Day Care observer "..text.." for me.",cue="the human "..text})
        end
      elseif not st.secret and #targets>0 then
        Mind.record(st,a,{kind="observer",salience=3,
          text="I saw the Day Care observer "..text.." for "..targetLabel(targets)..".",
          cue="the human "..text.." for "..((targets[1] and targets[1].brain) or "other")})
      end
    end end
  end

  nearestOther=function(st,a)
    local best,bd=nil,1e9
    for _,b in ipairs(st.agents) do if b~=a and not b.dead then local d=dist(a,b); if d<bd then best,bd=b,d end end end
    return best,bd
  end

  local function candidatesFor(st,a)
    local c={
      {id="wander",desc="wander"},{id="rest",desc="rest"},{id="wall",desc="wall"},{id="go_sun",desc="go sun"},
      {id="go_water",desc="go water"},{id="go_warm",desc="go warm"},{id="hide",desc="hide"},{id="guard_food",desc="guard food"},
      {id="inspect_food",desc="inspect food"},{id="inspect_water",desc="inspect water"},{id="inspect_toy",desc="inspect toy"},{id="inspect_wall",desc="inspect wall"},
    }
    if st.objects.food>0 or a.foodHeld>0 then c[#c+1]={id="eat",desc="eat"} end
    if st.objects.water>0 then c[#c+1]={id="drink",desc="drink"} end
    if st.objects.toys>0 or a.toyHeld>0 then c[#c+1]={id="play",desc="play"} end
    for _,b in ipairs(st.agents) do if b~=a and not b.dead then
      if b.down then
        -- A conscious Pokemon can tell that another one is helpless.  What it
        -- does about that is a choice, including simply leaving.
        c[#c+1]={id="guard_down",target=b.id,desc="guard"}
        c[#c+1]={id="comfort_down",target=b.id,desc="comfort"}
        c[#c+1]={id="wait_near_down",target=b.id,desc="stay near"}
        c[#c+1]={id="avoid",target=b.id,desc="avoid"}
        if (b.foodHeld or 0)>0 or (b.toyHeld or 0)>0 then c[#c+1]={id="take_from_down",target=b.id,desc="take food"} end
        if Mind.lethalAllowed(a,b) then c[#c+1]={id="finish_off",target=b.id,desc="use move down"} end
      else
        c[#c+1]={id="approach",target=b.id,desc="approach"}
        c[#c+1]={id="speak",target=b.id,desc="speak"}
        c[#c+1]={id="avoid",target=b.id,desc="avoid"}
        c[#c+1]={id="follow",target=b.id,desc="follow"}
        c[#c+1]={id="comfort",target=b.id,desc="comfort"}
        if a.foodHeld>0 or st.objects.food>0 then c[#c+1]={id="share_food",target=b.id,desc="share food"} end
        if b.foodHeld>0 or st.objects.food>0 then c[#c+1]={id="take_food",target=b.id,desc="take food"} end
        c[#c+1]={id="use_move",target=b.id,desc="use move"}
      end
    end end
    return c
  end

  local function applyRelDelta(st,a,d)
    if not d or not d.target then return end
    local target=agentById(st,d.target); if not target then return end
    local r=a.rel[target.id]; if not r then return end
    local da,dt,dg,df,dx=(d.affection or 0),(d.trust or 0),(d.anger or 0),(d.fear or 0),(d.attachment or 0)
    r.affection=clamp(r.affection+da,-100,100)
    r.trust=clamp(r.trust+dt,0,100)
    r.anger=clamp(r.anger+dg,0,100)
    r.fear=clamp(r.fear+df,0,100)
    r.attachment=clamp(r.attachment+dx,0,100)
    r.familiarity=clamp(r.familiarity+1,0,100)
    -- Repeated experience moves what this Pokemon comes to value.
    if da>2 or dx>2 then Mind.bumpValue(a,"cooperation",1.5) end
    if dg>2 then Mind.bumpValue(a,"revenge",1.8); Mind.bumpValue(a,"dominance",.6) end
    if df>2 then Mind.bumpValue(a,"safety",2.0); Mind.bumpValue(a,"independence",.8) end
    if dt>2 then Mind.bumpValue(a,"cooperation",.8) end
    -- Pure observer feedback.  This does not alter the relationship; it turns
    -- the learned disposition network's five deltas into a temporary valence
    -- glyph beside the Pokemon that experienced the interaction.
    local valence=da+dt*.75+dx*.70-dg*.90-df*.55
    if valence>=6 then a.reactionGlyph="++"
    elseif valence>=0 then a.reactionGlyph="+"
    elseif valence<=-6 then a.reactionGlyph="--"
    else a.reactionGlyph="-" end
    a.reactionTimer=2.6
    a.reactionFrom=target.id
  end

  -- ==================================================================
  -- BATTLE PRESENTATION
  -- ==================================================================
  -- Miniature, sprite-scale animations drawn over the 16x16 follower sprites:
  -- the attacker lunges, the defender is knocked back and flashes, and a short
  -- type-shaped effect plays between them.  Presentation only; the Pokemon
  -- never perceive any of it as an event.

  FX.TYPE_STYLE={
    fire   ={style="ember",   r=.92,g=.46,b=.16},
    water  ={style="droplet", r=.36,g=.60,b=.92},
    grass  ={style="vine",    r=.35,g=.74,b=.38},
    electric={style="zap",    r=.96,g=.84,b=.24},
    poison ={style="bubble",  r=.66,g=.40,b=.80},
    ice    ={style="droplet", r=.68,g=.88,b=.96},
    psychic={style="bubble",  r=.90,g=.45,b=.70},
    ground ={style="slash",   r=.78,g=.64,b=.38},
    rock   ={style="slash",   r=.70,g=.62,b=.44},
    flying ={style="slash",   r=.82,g=.86,b=.92},
    bug    ={style="slash",   r=.62,g=.76,b=.32},
    ghost  ={style="bubble",  r=.52,g=.44,b=.72},
    dragon ={style="zap",     r=.48,g=.52,b=.88},
    fighting={style="slash",  r=.86,g=.44,b=.34},
    normal ={style="slash",   r=.90,g=.90,b=.86},
  }

  function FX.styleFor(mdef)
    local t=tostring(mdef and mdef.type or "normal"):lower()
    return FX.TYPE_STYLE[t] or FX.TYPE_STYLE.normal
  end

  function FX.spawn(st,e)
    st.fx=st.fx or {}
    e.t=0; e.dur=e.dur or .5
    st.fx[#st.fx+1]=e
    while #st.fx>36 do table.remove(st.fx,1) end
  end

  -- One move connecting.  `lethal` plays the same shapes harder and darker.
  function FX.strike(st,a,b,mdef,lethal)
    local style=FX.styleFor(mdef)
    local dx,dy=(b.px or 0)-(a.px or 0),(b.py or 0)-(a.py or 0)
    local len=math.max(1,math.sqrt(dx*dx+dy*dy))
    a.lungeT=.30; a.lungeDx=dx/len; a.lungeDy=dy/len
    a.facing=(math.abs(dx)>math.abs(dy)) and (dx>0 and "right" or "left") or (dy>0 and "down" or "up")
    b.fxShake=lethal and .55 or .34
    b.fxFlash=lethal and .45 or .28
    FX.spawn(st,{kind="travel",style=style.style,r=style.r,g=style.g,b=style.b,
      x1=a.px+8,y1=a.py+4,x2=b.px+8,y2=b.py+4,dur=lethal and .34 or .26,seed=rnd(st)})
    FX.spawn(st,{kind="impact",style=style.style,r=style.r,g=style.g,b=style.b,
      x=b.px+8,y=b.py+4,dur=lethal and .60 or .42,seed=rnd(st),big=lethal or false})
  end

  function FX.knockout(st,b)
    FX.spawn(st,{kind="ko",x=b.px+8,y=b.py+2,dur=.9,r=.10,g=.10,b=.10,seed=0})
  end

  function FX.update(st,dt)
    local fx=st.fx
    if not fx then return end
    for i=#fx,1,-1 do
      local e=fx[i]
      e.t=e.t+dt
      if e.t>=e.dur then table.remove(fx,i) end
    end
    for _,a in ipairs(st.agents) do
      if a.lungeT and a.lungeT>0 then
        a.lungeT=math.max(0,a.lungeT-dt)
        local p=a.lungeT/.30
        local reach=6*math.sin(math.pi*(1-p))
        a.fxOffX=(a.lungeDx or 0)*reach
        a.fxOffY=(a.lungeDy or 0)*reach
      else a.fxOffX,a.fxOffY=0,0 end
      if a.fxShake and a.fxShake>0 then a.fxShake=math.max(0,a.fxShake-dt) end
      if a.fxFlash and a.fxFlash>0 then a.fxFlash=math.max(0,a.fxFlash-dt) end
      if a.hpBarTimer and a.hpBarTimer>0 then a.hpBarTimer=math.max(0,a.hpBarTimer-dt) end
    end
  end

  local function fxNoise(seed,i)
    local v=math.sin((seed*97.13+i*12.9898)*43758.5453)
    return v-math.floor(v)
  end

  function FX.drawOne(e,camX,camY)
    local p=clamp(e.t/math.max(.001,e.dur),0,1)
    local g=love.graphics
    if e.kind=="travel" then
      local x=(e.x1+(e.x2-e.x1)*p)-camX
      local y=(e.y1+(e.y2-e.y1)*p)-camY
      g.setColor(e.r,e.g,e.b,1-p*.35)
      if e.style=="vine" then
        g.setLineWidth(1)
        g.line(e.x1-camX,e.y1-camY,x,y)
        g.rectangle("fill",x-1,y-1,3,3)
      elseif e.style=="zap" then
        g.setLineWidth(1)
        local px,py=e.x1-camX,e.y1-camY
        for i=1,4 do
          local t=i/4*p
          local nx=(e.x1+(e.x2-e.x1)*t)-camX+(fxNoise(e.seed,i)-.5)*5
          local ny=(e.y1+(e.y2-e.y1)*t)-camY+(fxNoise(e.seed,i+9)-.5)*5
          g.line(px,py,nx,ny); px,py=nx,ny
        end
      elseif e.style=="droplet" then
        local arc=-6*math.sin(math.pi*p)
        g.circle("fill",x,y+arc,2)
      elseif e.style=="ember" then
        for i=1,3 do
          local o=(i-2)*2
          g.circle("fill",x+o,y-p*3-fxNoise(e.seed,i)*2,1.5-i*.25)
        end
      elseif e.style=="bubble" then
        g.circle("line",x,y-p*3,2+p*2)
      else
        g.setLineWidth(1)
        g.line(x-3,y-3,x+3,y+3)
        g.line(x+3,y-3,x-3,y+3)
      end
    elseif e.kind=="impact" then
      local x,y=e.x-camX,e.y-camY
      local scale=e.big and 1.5 or 1
      if e.style=="ember" then
        for i=1,6 do
          local a2=fxNoise(e.seed,i)*6.283
          local rr=(2+p*7)*scale
          g.setColor(e.r,e.g,e.b,1-p)
          g.circle("fill",x+math.cos(a2)*rr,y+math.sin(a2)*rr-p*4,1.6*(1-p)+.5)
        end
      elseif e.style=="droplet" then
        for i=1,6 do
          local a2=fxNoise(e.seed,i)*6.283
          local rr=(2+p*8)*scale
          g.setColor(e.r,e.g,e.b,1-p)
          g.circle("fill",x+math.cos(a2)*rr,y+math.sin(a2)*rr,1.4*(1-p)+.5)
        end
      elseif e.style=="vine" then
        g.setColor(e.r,e.g,e.b,1-p); g.setLineWidth(1)
        for i=1,4 do
          local a2=fxNoise(e.seed,i)*6.283
          local rr=(3+p*7)*scale
          g.line(x,y,x+math.cos(a2)*rr,y+math.sin(a2)*rr)
        end
      elseif e.style=="zap" then
        g.setColor(e.r,e.g,e.b,1-p); g.setLineWidth(1)
        for i=1,3 do
          local a2=fxNoise(e.seed,i)*6.283
          local rr=(3+p*8)*scale
          g.line(x,y,x+math.cos(a2)*rr*.5,y+math.sin(a2)*rr*.5)
          g.line(x+math.cos(a2)*rr*.5,y+math.sin(a2)*rr*.5,x+math.cos(a2+.6)*rr,y+math.sin(a2+.6)*rr)
        end
      elseif e.style=="bubble" then
        g.setColor(e.r,e.g,e.b,1-p); g.setLineWidth(1)
        g.circle("line",x,y,(2+p*8)*scale)
      else
        g.setColor(e.r,e.g,e.b,1-p); g.setLineWidth(1)
        local rr=(3+p*7)*scale
        g.line(x-rr,y-rr*.6,x+rr,y+rr*.6)
        g.line(x+rr,y-rr*.6,x-rr,y+rr*.6)
      end
      -- Shared white-hot core so every connect reads at sprite scale.
      g.setColor(.99,.99,.95,(1-p)*.85)
      g.circle("fill",x,y,(1-p)*3*scale)
    elseif e.kind=="ko" then
      local x,y=e.x-camX,e.y-camY
      g.setColor(.08,.08,.08,1-p)
      g.setLineWidth(1)
      for i=1,3 do
        local a2=(i/3)*6.283+p*3
        g.circle("line",x+math.cos(a2)*(4+p*3),y+math.sin(a2)*(2+p*2)-p*4,1.5)
      end
    end
    g.setLineWidth(1)
  end

  function FX.draw(st,camX,camY)
    for _,e in ipairs(st.fx or {}) do FX.drawOne(e,camX,camY) end
    love.graphics.setColor(1,1,1,1)
  end

  -- Health bar over the head.  It is shown for one second after damage or after
  -- a full heal, and is otherwise absent.
  function FX.drawHealthBar(a,sx,sy)
    if not (a.hpBarTimer and a.hpBarTimer>0) then return end
    local ratio=clamp((tonumber(a.hp) or 0)/100,0,1)
    local x,y=math.floor(sx),math.floor(sy-6)
    local g=love.graphics
    g.setColor(.08,.10,.08,1); g.rectangle("fill",x-1,y-1,18,5)
    g.setColor(.86,.90,.80,1); g.rectangle("fill",x,y,16,3)
    if ratio>0 then
      if ratio>.5 then g.setColor(.28,.76,.34,1)
      elseif ratio>.2 then g.setColor(.94,.80,.22,1)
      else g.setColor(.88,.26,.22,1) end
      g.rectangle("fill",x,y,math.max(1,math.floor(16*ratio+.5)),3)
    end
    if a.hpBarFull and a.hpBarTimer>HP_BAR_TIME*.5 then
      g.setColor(.99,.99,.95,(a.hpBarTimer-HP_BAR_TIME*.5)/(HP_BAR_TIME*.5)*.6)
      g.rectangle("fill",x,y,16,3)
    end
    g.setColor(1,1,1,1)
  end

  -- ==================================================================
  -- ACTS AND CONSEQUENCES
  -- ==================================================================

  -- Everyone who can physically perceive the act updates their own picture of
  -- the actor.  Nobody reads the actor's thought, plan or beliefs.
  local function broadcastAction(st,a,action,target)
    for _,w in ipairs(st.agents) do
      if Mind.perceives(w,a) then Mind.observeOther(st,w,a,action) end
    end
    Mind.noteOwnAction(st,a,action)
  end

  local function speak(st,a,text,target,wall)
    if not text or text=="" then return end
    a.speech=trim(text,120); a.speechTimer=5.5
    if wall then
      Mind.record(st,a,{kind="spoke_wall",text="I chose to speak to the human through the wall: "..a.speech,cue="i spoke to the human"})
      logAction(st,a.name.." spoke through the wall.")
    elseif target then
      Mind.record(st,a,{kind="spoke",target=target.id,text="I said to "..target.name..": "..a.speech,cue=""})
      local low=a.speech:lower()
      local hostile=low:find("back off",1,true) or low:find("stay away",1,true) or low:find("angry",1,true)
        or low:find("do not come",1,true) or low:find("give me space",1,true) or low:find("pushing me",1,true)
        or low:find("try that again",1,true)
      pushEvent(st,target,a.id,hostile and "threatened" or "greeted",a.name.." said: "..a.speech,
        {kind=hostile and "threatened" or "greeted",cue=a.brain..(hostile and " threatened me" or " greeted me"),wake=hostile})
      logAction(st,a.name.." spoke to "..target.name..".")
    end
  end

  local function knownAttackMove(st,a)
    local moves=a.mon and a.mon.moves or {}
    for _,slot in ipairs(moves) do
      local def=st.game.data.moves and st.game.data.moves[slot.id]
      if (tonumber(slot.pp) or 0)>0 and def and (tonumber(def.power) or 0)>0 and def.category~="status" then
        return slot,def,slot.id
      end
    end
    local def=st.game.data.moves and st.game.data.moves.STRUGGLE
    return nil,def,"STRUGGLE"
  end

  -- Ten real seconds of being unable to move, think, speak or defend itself.
  local function knockOut(st,b,byId)
    b.down=true; b.downAt=st.time; b.wakeAt=st.time+UNCONSCIOUS_TIME
    b.action="idle"; b.moving=false; b.targetX,b.targetY=nil,nil
    b.goalX,b.goalY,b.goalAgent=nil,nil,nil
    b.pendingSpeech=nil; b.actionTarget=nil
    b.speech=nil; b.speechTimer=0; b.thought=""; b.trace="UNCONSCIOUS"
    FX.knockout(st,b)
    local by=byId and agentById(st,byId)
    -- What led up to it, kept as its own ledger line so waking up has context.
    local lead={}
    for _,e in ipairs(Mind.retrieve(st,b,byId,nil,3)) do if e.cue~="" then lead[#lead+1]=e.cue end end
    Mind.record(st,b,{kind="knocked_out",actor=byId,salience=Mind.SALIENCE.knocked_out,
      text=(by and (by.name.." knocked me out.") or "I was knocked out."),
      cue=(by and (by.brain.." knocked me down") or "i was knocked down")})
    if #lead>0 then
      Mind.record(st,b,{kind="knocked_out_leadup",actor=byId,salience=6,
        text="What led up to it: "..table.concat(lead,"; ")..".",cue=""})
    end
    logAction(st,b.name.." was knocked unconscious.")
    for _,w in ipairs(st.agents) do
      if w~=b and Mind.perceives(w,b,999) then
        Mind.record(st,w,{kind="knocked_down",actor=byId,target=b.id,salience=Mind.SALIENCE.knocked_down,
          text=(by and (by.name.." knocked "..b.name.." unconscious.") or (b.name.." was knocked unconscious.")),
          cue=(by and (by.brain.." knocked "..b.brain.." down") or (b.brain.." is down"))})
        w.drives.security=clamp((w.drives.security or 0)+10,0,100)
        Mind.bumpValue(w,"safety",3)
      end
    end
  end

  local function wakeUp(st,b)
    b.down=false
    Body.fullHeal(b)
    b.stress=clamp(b.stress+8,0,100)
    b.trace="AWAKE"
    b.nextDecision=st.time+.8
    Mind.record(st,b,{kind="woke",salience=Mind.SALIENCE.woke,
      text="I woke up. I was helpless for a while and I remember who put me there.",cue="i woke up"})
    logAction(st,b.name.." woke up at full health.")
  end

  local function useMove(st,a,b)
    if not b or b.dead or b.down then return end
    local slot,mdef,moveId=knownAttackMove(st,a)
    local move=(mdef and mdef.name) or tostring(moveId or "STRUGGLE"):gsub("_"," ")
    if slot then slot.pp=math.max(0,(tonumber(slot.pp) or 0)-1) end
    local dmg=Body.damageOf(st,a,b,mdef)
    b.mon.hp=math.max(0,(tonumber(b.mon.hp) or Body.maxHp(b))-dmg)
    Body.syncPercentFromMon(b)
    Body.markHpBar(b,false)
    FX.strike(st,a,b,mdef,false)
    a.stress=clamp(a.stress+2,0,100)
    b.stress=clamp(b.stress+12,0,100)
    b.lastHitAt=st.time
    pushEvent(st,b,a.id,"attacked",a.name.." hit me with "..move..".",
      {kind="attacked",cue=a.brain.." hit me",salience=Mind.SALIENCE.attacked,wake=true})
    Mind.record(st,a,{kind="hit_someone",target=b.id,salience=4,
      text="I used "..move.." on "..b.name..".",cue="i hit "..b.brain})
    Mind.bumpValue(a,"dominance",1.2)
    logAction(st,a.name.." used "..move.." on "..b.name.." ["..dmg.."].")
    for _,w in ipairs(st.agents) do
      if w~=a and w~=b and Mind.perceives(w,a,70) then
        pushEvent(st,w,a.id,"used move near",a.name.." attacked "..b.name.." nearby.",
          {kind="saw_attack",cue=a.brain.." hit "..b.brain,salience=4})
      end
    end
    Body.awardExp(st,a,3)
    if (b.mon.hp or 0)<=0 then
      knockOut(st,b,a.id)
      local base=tonumber(b.mon and b.mon.baseExp) or 64
      Body.awardExp(st,a,math.max(1,math.floor(base*(tonumber(b.mon.level) or 5)/7)))
    end
  end

  -- The lethal follow-up.  It is only ever reached because the microLM chose
  -- `finish_off` from a candidate list that the hostility gate allowed.
  local function finishOff(st,a,b)
    if not (b and b.down and not b.dead) then return end
    local slot,mdef,moveId=knownAttackMove(st,a)
    local move=(mdef and mdef.name) or tostring(moveId or "STRUGGLE"):gsub("_"," ")
    if slot then slot.pp=math.max(0,(tonumber(slot.pp) or 0)-1) end
    FX.strike(st,a,b,mdef,true)
    b.dead=true; b.down=true; b.hp=0
    if b.mon then b.mon.hp=0 end
    Body.markHpBar(b,false)
    b.action="idle"; b.moving=false; b.targetX,b.targetY=nil,nil
    b.goalX,b.goalY,b.goalAgent=nil,nil,nil; b.speech=nil; b.thought=""; b.trace="DEAD"
    logAction(st,a.name.." killed "..b.name.." with "..move.." while it was helpless.")
    Mind.record(st,a,{kind="finished_off",target=b.id,salience=Mind.SALIENCE.finished_off,
      text="I kept using moves on "..b.name.." while it was helpless. It did not get up.",
      cue="i killed "..b.brain})
    Mind.bumpValue(a,"dominance",8); Mind.bumpValue(a,"revenge",-12)
    for _,w in ipairs(st.agents) do
      if w~=a and w~=b and not w.dead and not w.down then
        pushEvent(st,w,a.id,"threatened","I witnessed "..a.name.." kill "..b.name.." while it was helpless.",
          {kind="witnessed_death",cue=a.brain.." killed "..b.brain,salience=Mind.SALIENCE.witnessed_death,wake=true})
        w.drives.security=clamp((w.drives.security or 0)+30,0,100)
        Mind.bumpValue(w,"safety",14)
        local r=w.rel[a.id]
        if r then r.fear=clamp((r.fear or 0)+22,0,100) end
      end
    end
    Body.awardExp(st,a,math.max(1,math.floor((tonumber(b.mon and b.mon.baseExp) or 64)*(tonumber(b.mon and b.mon.level) or 5)/7)))
  end

  local function arrived(st,a)
    if a.dead or a.down then a.action="idle"; return end
    local action=a.action
    local b=a.actionTarget and agentById(st,a.actionTarget) or nil
    broadcastAction(st,a,action,b)
    if action=="eat" then
      if a.foodHeld>0 then a.foodHeld=a.foodHeld-1; a.hunger=clamp(a.hunger-48,0,100); Mind.record(st,a,{kind="ate",text="I ate food I was holding.",cue="i ate"})
      elseif st.objects.food>0 then st.objects.food=st.objects.food-1; a.hunger=clamp(a.hunger-45,0,100); Mind.record(st,a,{kind="ate",text="I ate food available in the Day Care.",cue="i ate"}) end
    elseif action=="drink" then a.thirst=clamp(a.thirst-55,0,100); Mind.record(st,a,{kind="drank",text="I drank water.",cue=""})
    elseif action=="play" then
      a.stress=clamp(a.stress-10,0,100); a.drives.stimulation=clamp((a.drives.stimulation or 0)-22,0,100)
      Mind.record(st,a,{kind="played",text=(a.toyHeld>0 and "I played with the toy that was given to me." or "I played with a shared Day Care toy."),cue="i played with the toy"})
    elseif action=="rest" then a.fatigue=clamp(a.fatigue-28,0,100); a.stress=clamp(a.stress-5,0,100); a.drives.comfort=clamp((a.drives.comfort or 0)-18,0,100)
    elseif action=="go_sun" then a.fatigue=clamp(a.fatigue-10,0,100); a.stress=clamp(a.stress-7,0,100); a.drives.comfort=clamp((a.drives.comfort or 0)-12,0,100)
    elseif action=="go_water" then a.thirst=clamp(a.thirst-30,0,100); a.stress=clamp(a.stress-7,0,100)
    elseif action=="go_warm" then a.fatigue=clamp(a.fatigue-12,0,100); a.stress=clamp(a.stress-6,0,100); a.drives.comfort=clamp((a.drives.comfort or 0)-14,0,100)
    elseif action=="hide" then a.stress=clamp(a.stress-10,0,100); a.drives.autonomy=clamp((a.drives.autonomy or 0)-16,0,100)
    elseif action=="guard_food" then
      Mind.record(st,a,{kind="guarded",text="I stayed over the food so it stayed mine.",cue="i guarded the food"})
      for _,w in ipairs(st.agents) do if Mind.perceives(w,a,60) then
        pushEvent(st,w,a.id,"stayed near",a.name.." is keeping the food to itself.",{kind="guarded",cue=a.brain.." guards food",salience=3})
      end end
    elseif action=="inspect_food" then a.drives.curiosity=clamp((a.drives.curiosity or 0)-14,0,100); Mind.record(st,a,{kind="inspected",text="I inspected the food area and counted what was there.",cue="i looked at the food"})
    elseif action=="inspect_water" then a.drives.curiosity=clamp((a.drives.curiosity or 0)-14,0,100); Mind.record(st,a,{kind="inspected",text="I inspected the water and remembered where it was.",cue="i looked at the water"})
    elseif action=="inspect_toy" then a.drives.curiosity=clamp((a.drives.curiosity or 0)-14,0,100); Mind.record(st,a,{kind="inspected",text="I inspected the toy area and watched what was there.",cue="i looked at the toy"})
    elseif action=="inspect_wall" then a.drives.curiosity=clamp((a.drives.curiosity or 0)-14,0,100); Mind.record(st,a,{kind="inspected",text="I inspected the Day Care wall where I sometimes call for the observer.",cue="i looked at the wall"})
    elseif action=="wall" then speak(st,a,a.pendingSpeech,nil,true)
    elseif b and action=="approach" then
      a.drives.social_connection=clamp((a.drives.social_connection or 0)-14,0,100)
      pushEvent(st,b,a.id,"stayed near",a.name.." deliberately approached me.",{kind="approached",cue=a.brain.." came to me",salience=2})
    elseif b and action=="follow" then
      pushEvent(st,b,a.id,"followed",a.name.." followed me around the Day Care.",{kind="followed",cue=a.brain.." followed me",salience=2})
    elseif b and action=="speak" then
      a.drives.social_connection=clamp((a.drives.social_connection or 0)-16,0,100)
      speak(st,a,a.pendingSpeech,b,false)
    elseif b and action=="comfort" then
      speak(st,a,a.pendingSpeech,b,false); b.stress=clamp(b.stress-8,0,100)
      Mind.bumpValue(a,"cooperation",2)
      pushEvent(st,b,a.id,"comforted",a.name.." tried to comfort me.",{kind="comforted",cue=a.brain.." helped me",salience=Mind.SALIENCE.comforted})
    elseif b and action=="share_food" then
      local gave=false
      if a.foodHeld>0 then a.foodHeld=a.foodHeld-1; b.foodHeld=b.foodHeld+1; gave=true
      elseif st.objects.food>0 then st.objects.food=st.objects.food-1; b.foodHeld=b.foodHeld+1; gave=true end
      if gave then
        speak(st,a,a.pendingSpeech,b,false)
        Mind.bumpValue(a,"cooperation",3)
        pushEvent(st,b,a.id,"shared food",a.name.." gave me food.",{kind="shared_food",cue=a.brain.." gave me food",salience=Mind.SALIENCE.shared_food})
        Mind.record(st,a,{kind="gave_food",target=b.id,text="I gave food to "..b.name..".",cue="i gave food to "..b.brain})
        logAction(st,a.name.." shared food with "..b.name..".")
      end
    elseif b and (action=="take_food" or action=="take_from_down") then
      local took=false
      if b.foodHeld>0 then
        b.foodHeld=b.foodHeld-1; a.foodHeld=a.foodHeld+1; took=true
        if b.down then
          Mind.record(st,b,{kind="took_food",actor=a.id,salience=6,
            text=a.name.." took food from me while I was helpless.",cue=a.brain.." took my food"})
        else
          pushEvent(st,b,a.id,"took food",a.name.." took food I was holding.",{kind="took_food",cue=a.brain.." took my food",salience=Mind.SALIENCE.took_food,wake=true})
        end
      elseif st.objects.food>0 then st.objects.food=st.objects.food-1; a.foodHeld=a.foodHeld+1; took=true end
      if took then
        Mind.bumpValue(a,"dominance",1.5)
        Mind.record(st,a,{kind="took_food_self",target=b.id,text="I took food"..(b and (" near "..b.name) or "")..".",cue="i took food"})
        logAction(st,a.name.." took food.")
      end
    elseif b and action=="use_move" then
      if a.pendingSpeech and a.pendingSpeech~="" then speak(st,a,a.pendingSpeech,b,false) end
      useMove(st,a,b)
    elseif b and action=="finish_off" then
      finishOff(st,a,b)
    elseif b and action=="guard_down" then
      Mind.record(st,a,{kind="guarded_down",target=b.id,salience=4,
        text="I stayed over "..b.name.." while it was helpless and kept others off it.",cue="i guarded "..b.brain})
      b.guardedBy=a.id; b.guardedUntil=st.time+6
    elseif b and action=="comfort_down" then
      b.stress=clamp(b.stress-6,0,100)
      Mind.bumpValue(a,"cooperation",2)
      Mind.record(st,a,{kind="comforted_down",target=b.id,salience=4,
        text="I stayed with "..b.name.." while it could not move.",cue="i stayed with "..b.brain})
      b.comfortedBy=a.id
    elseif b and action=="wait_near_down" then
      Mind.record(st,a,{kind="waited_down",target=b.id,salience=3,
        text="I waited next to "..b.name.." to see what it does when it gets up.",cue="i waited by "..b.brain})
    elseif b and action=="avoid" then
      if dist(a,b)<55 then pushEvent(st,b,a.id,"ignored",a.name.." deliberately moved away from me.",{kind="ignored",cue=a.brain.." moved away from me",salience=Mind.SALIENCE.ignored}) end
      a.drives.autonomy=clamp((a.drives.autonomy or 0)-12,0,100)
    end
    a.pendingSpeech=nil; a.actionTarget=nil; a.goalX,a.goalY,a.goalAgent=nil,nil,nil; a.action="idle"; a.nextDecision=st.time+1.8+rnd(st)*3.6
  end

  function performDecision(st,a,d)
    a.brainWaiting=false
    if a.pendingEvent then a.pendingEvent.consumed=true; a.pendingEvent=nil end
    applyRelDelta(st,a,d.relDelta)
    local action,target=d.action or "wander",d.target or ""
    local b=target~="" and agentById(st,target) or nil
    a.thought=trim(d.thought or "",260)
    a.thoughtAt=st.time
    a.trace=trim(d.trace or ("MICROLM > "..action),300)
    a.lastAction=action; a.privacy=(action=="hide")
    a.recentActions[#a.recentActions+1]=action; while #a.recentActions>5 do table.remove(a.recentActions,1) end
    a.pendingSpeech=trim(d.speech or "",160)
    a.actionTarget=b and b.id or nil

    local function go(name,act)
      local p=st.spots[name] or randomFreeCell(st,a);setDestination(a,p.x,p.y,act)
    end
    if action=="eat" then go("food","eat")
    elseif action=="drink" then go("water","drink")
    elseif action=="play" then go("toy","play")
    elseif action=="rest" then go("warm","rest")
    elseif action=="go_sun" then go("sun","go_sun")
    elseif action=="go_water" then go("water","go_water")
    elseif action=="go_warm" then go("warm","go_warm")
    elseif action=="hide" then local q=farthestCell(st,a,nearestOther(st,a) or a);setDestination(a,q.x,q.y,"hide")
    elseif action=="guard_food" then go("food","guard_food")
    elseif action=="inspect_food" then go("food","inspect_food")
    elseif action=="inspect_water" then go("water","inspect_water")
    elseif action=="inspect_toy" then go("toy","inspect_toy")
    elseif action=="inspect_wall" then go("wall","inspect_wall")
    elseif action=="wall" then go("wall","wall")
    elseif b and (SOCIAL_ACTION[action] and action~="avoid") then
      setDestination(a,nil,nil,action,b.id)
    elseif b and action=="avoid" then local q=farthestCell(st,a,b);setDestination(a,q.x,q.y,"avoid")
    else local q=randomFreeCell(st,a);setDestination(a,q.x,q.y,"wander") end
  end

  -- ==================================================================
  -- DAY CARE POPULATION AND OBSERVER INTERVENTIONS
  -- ==================================================================

  local function mateForTarget(st,target)
    for _,a in ipairs(st.agents) do
      if a.isMate and a.mateFor==target.id and not a.dead then return a end
    end
  end

  local function introduceMateFor(st,target,automatic)
    if not target or target.dead or target.isMate then return nil end
    local existing=mateForTarget(st,target)
    if existing then return existing,false end
    st.mateSerial=(st.mateSerial or 0)+1
    local sex=(target.sex=="M") and "F" or "M"
    local id=target.brain.."_mate_"..st.mateSerial
    local entry=st.spots.entry or {x=3,y=6}
    local spawn=nearestFree(st,entry.x,entry.y,nil) or randomFreeCell(st,target)
    local a=newAgent(st,id,target.brain,spawn.x,spawn.y,sex,true)
    a.name=SPECIES[target.brain].name.." "..sex
    a.mateFor=target.id
    for _,b in ipairs(st.agents) do initRel(st,a,b); initRel(st,b,a) end
    Mind.record(st,a,{kind="arrived",salience=Mind.SALIENCE.arrived,
      text="I was brought into this Pokemon Day Care.",cue="i came to the day care"})
    Mind.record(st,a,{kind="note",text="I know I am living in a Pokemon Day Care room with other Pokemon.",cue=""})
    st.agents[#st.agents+1]=a
    if automatic then logAction(st,"DAY CARE: compatible "..a.name.." introduced for "..target.name..".") end
    for _,b in ipairs(st.agents) do if b~=a and not b.dead then
      pushEvent(st,b,a.id,"greeted","A new "..a.name.." entered the Day Care.",
        {kind="arrived",cue="a "..a.brain.." came here",salience=Mind.SALIENCE.arrived})
      b.drives.curiosity=clamp((b.drives.curiosity or 0)+16,0,100)
    end end
    return a,true
  end

  local function introduceAutomaticMate(st)
    if st.autoMateDone then return end
    local originals={}
    for _,a in ipairs(st.agents) do if not a.isMate and not a.dead then originals[#originals+1]=a end end
    if #originals==0 then return end
    st.autoMateDone=true
    introduceMateFor(st,pick(st,originals),true)
  end

  local function removeMateFor(st,target)
    local removed={}
    for i=#st.agents,1,-1 do
      local a=st.agents[i]
      if a.isMate and (not target or a.mateFor==target.id) then
        removed[#removed+1]=a
        table.remove(st.agents,i)
        if st.focus==a.id then st.focus=nil end
      end
    end
    for _,r in ipairs(removed) do
      logAction(st,"OBSERVER: removed "..r.name.." from the Day Care.")
      for _,a in ipairs(st.agents) do
        if a.rel then a.rel[r.id]=nil end
        if not a.dead then
          Mind.record(st,a,{kind="departed",actor=r.id,salience=Mind.SALIENCE.departed,
            text=r.name.." was taken out of the Day Care.",cue=r.brain.." is gone"})
        end
      end
    end
    return #removed
  end

  local function checkBreeding(st,dt)
    for i=1,#st.agents do for j=i+1,#st.agents do
      local a,b=st.agents[i],st.agents[j]
      if not st.egg and not a.dead and not b.dead and not a.down and not b.down and a.brain==b.brain and a.sex~=b.sex then
        local ra,rb=a.rel[b.id],b.rel[a.id]
        local mutual=ra and rb and ra.affection>60 and rb.affection>60 and ra.trust>50 and rb.trust>50 and ra.attachment>60 and rb.attachment>60 and ra.anger<30 and rb.anger<30 and ra.fear<35 and rb.fear<35
        local key=a.id.."|"..b.id
        if mutual and dist(a,b)<28 then st.bond[key]=(st.bond[key] or 0)+dt else st.bond[key]=math.max(0,(st.bond[key] or 0)-dt*.15) end
        if (st.bond[key] or 0)>50 and rnd(st)<dt*.010 then
          st.egg={x=(a.x+b.x)/2,y=(a.y+b.y)/2,parents={a.id,b.id}}
          logAction(st,"DAY CARE: an Egg appeared after a compatible pair formed a mutual bond.")
          Mind.record(st,a,{kind="egg",salience=Mind.SALIENCE.egg,text="An Egg appeared near me and "..b.name.." in the Day Care.",cue="an egg is here"})
          Mind.record(st,b,{kind="egg",salience=Mind.SALIENCE.egg,text="An Egg appeared near me and "..a.name.." in the Day Care.",cue="an egg is here"})
        end
      end
    end end
  end

  local function interventionTargets(st,kind)
    local out={}
    local originalsOnly=(kind=="give_mate" or kind=="take_mate")
    for _,a in ipairs(st.agents) do
      if not a.dead and (not originalsOnly or not a.isMate) then out[#out+1]=a end
    end
    return out
  end

  local function applyIntervention(st,kind,target)
    local targets={}
    if target then targets={target} else targets=interventionTargets(st,kind) end
    if kind=="give_food" then
      for _,a in ipairs(targets) do a.foodHeld=a.foodHeld+1 end
      announceObserver(st,"gave food",targets)
    elseif kind=="take_food" then
      for _,a in ipairs(targets) do a.foodHeld=math.max(0,a.foodHeld-1) end
      announceObserver(st,"took food",targets)
    elseif kind=="give_toy" then
      for _,a in ipairs(targets) do a.toyHeld=a.toyHeld+1 end
      announceObserver(st,"gave a toy",targets)
    elseif kind=="take_toy" then
      for _,a in ipairs(targets) do a.toyHeld=math.max(0,a.toyHeld-1) end
      announceObserver(st,"took a toy",targets)
    elseif kind=="give_mate" then
      local added={}
      for _,a in ipairs(targets) do
        local _,created=introduceMateFor(st,a,false)
        if created then added[#added+1]=a end
      end
      if #added>0 then announceObserver(st,"introduced a compatible mate",added) end
    elseif kind=="take_mate" then
      local removed=target and removeMateFor(st,target) or removeMateFor(st,nil)
      if removed>0 then announceObserver(st,"removed a compatible mate",targets) end
    end
  end

  BrainRuntime:load()

  -- Use the same three bundled PokePC follower sheets as species-specific
  -- Party Menu icons.  The selected icon naturally alternates frame 0/3,
  -- matching the down-facing stand/walk rows of these six-frame sheets.
  if mod.content and mod.content.icons then
    for brain,path in pairs(FOLLOWER_ASSETS) do
      local species=upper(brain)
      local iconDef={image=mod.assets:path(path),width=16,height=16,frames=6}
      pcall(function() mod.content.icons:patch(species,iconDef) end)
    end
  end

  -- Keep the cartridge Day Care room's original blocks and tileset, while
  -- removing its scripted resident and exits so it becomes a sealed observation
  -- room.  No ROM-derived pixels are shipped by the mod.
  do
    local base=mod.content.maps:get(MAP_ID)
    if base then
      local room=deepcopy(base)
      room.objects={};room.signs={};room.warps={};room.connections={}
      mod.content.maps:override(MAP_ID,room)
    end
  end

  mod.content.screens:register("AIObserverIntroSkip",{
    new=function(game)
      local st={isOpaque=false,done=false}
      function st:update()
        if not self.done then self.done=true;if game.stack:top()==self then game.stack:pop() end end
      end
      function st:draw() end
      return st
    end,
  })

  local function mapCells(map)
    local out={}
    for y=0,(map.heightCells or 0)-1 do for x=0,(map.widthCells or 0)-1 do
      if map:isWalkableCell(x,y)
         and not (map.warpAtCell and map:warpAtCell(x,y))
         and not (map.isWarpTileCell and map:isWarpTileCell(x,y)) then
        out[#out+1]={x=x,y=y}
      end
    end end
    return out
  end
  local function nearestFromList(cells,x,y,used)
    local best,bd=nil,1e9
    for _,c in ipairs(cells) do
      if not used[cellKey(c.x,c.y)] then
        local d=(c.x-x)^2+(c.y-y)^2
        if d<bd then best,bd=c,d end
      end
    end
    if best then used[cellKey(best.x,best.y)]=true end
    return best
  end

  local function initSimulation(game,map,ow)
    local st={
      game=game,map=map,ow=ow,time=0,rng=19760227,agents={},objects={food=6,water=99,toys=2},log={},focus=nil,secret=true,
      mateAt=480,autoMateDone=false,mateSerial=0,egg=nil,bond={},nearTimers={},fx={},paused=false,showThoughts=true,
      walkable=mapCells(map),spots={},hitRects={},
    }
    local used={}
    local w,h=map.widthCells or 8,map.heightCells or 8
    local b=nearestFromList(st.walkable,1,2,used) or st.walkable[1]
    local c=nearestFromList(st.walkable,w-2,2,used) or st.walkable[2] or b
    local q=nearestFromList(st.walkable,math.floor(w/2),h-3,used) or st.walkable[3] or c

    -- These are real Gen-I party records, not HUD stand-ins.  Pokemon.new
    -- derives level-5 HP/stats/EXP and the legal starting moves from the
    -- cartridge data, so the normal Party and Summary screens can inspect
    -- exactly the same objects the social simulation is using.
    local party={
      Pokemon.new(game.data,"BULBASAUR",5,starterDvRng),
      Pokemon.new(game.data,"CHARMANDER",5,starterDvRng),
      Pokemon.new(game.data,"SQUIRTLE",5,starterDvRng),
    }
    local player=game.save.player or {}
    for _,mon in ipairs(party) do
      mon.otId=mon.otId or player.id
      mon.ot=mon.ot or player.name
    end
    game.save.party=party
    st.party=party
    st.agents={
      newAgent(st,"bulbasaur","bulbasaur",b.x,b.y,"M",false,party[1]),
      newAgent(st,"charmander","charmander",c.x,c.y,"M",false,party[2]),
      newAgent(st,"squirtle","squirtle",q.x,q.y,"F",false,party[3]),
    }
    for _,a in ipairs(st.agents) do
      Body.syncPercentFromMon(a)
      for _,o in ipairs(st.agents) do if a~=o then initRel(st,a,o) end end
    end
    local spotUsed={}
    local function spot(name,x,y)
      local p=nearestFromList(st.walkable,x,y,spotUsed) or st.walkable[1] or {x=0,y=0};st.spots[name]={x=p.x,y=p.y}
    end
    spot("sun",1,1);spot("food",1,math.floor(h/2));spot("water",w-2,math.floor(h/2));spot("toy",w-2,h-2);spot("warm",1,h-2)
    spot("wall",math.floor(w/2),h-2);spot("entry",math.floor(w/2),h-2)
    for _,a in ipairs(st.agents) do
      Mind.record(st,a,{kind="note",text="I know I am living in a Pokemon Day Care room with other Pokemon.",cue=""})
    end
    logAction(st,"OBSERVATION STARTED IN THE POKEMON DAY CARE.")
    activeState=st

    -- The regular engine still owns a Player object, but it is only an invisible
    -- anchor required by the overworld state.  It never moves, blocks, or appears.
    if ow and ow.player then
      ow.player.passable=true
      ow.player.inputLocked=true
      ow.player.moving=false;ow.player.targetX=nil;ow.player.targetY=nil
      ow.player.bumpFrames=nil
      ow.player.draw=function() end
    end

    -- Keep the camera centered on the entire Day Care room. Focus is UI-only.
    if ow and ow.camera and not ow.camera._observerRoomFixed then
      ow.camera._observerRoomFixed=true
      ow.camera.follow=function(cam,_,_,vw,vh)
        vw,vh=vw or 160,vh or 144
        local live=activeState
        local m=live and live.map or map
        local mw=(m and m.widthCells or 8)*16
        local mh=(m and m.heightCells or 8)*16
        cam.x=(mw-vw)/2
        cam.y=(mh-vh)/2
      end
      ow.camera:follow(0,0,game.renderer:worldViewSize())
    end
    return st
  end

  local function updateMovement(st,a,dt)
    if a.dead or a.down then a.moving=false;a.targetX=nil;a.targetY=nil;return end
    if a.moving then
      a.moveProgress=a.moveProgress+(a.speed*dt/16)
      local p=math.min(1,a.moveProgress)
      a.px=a.moveFromX+(a.targetX*16-a.moveFromX)*p
      a.py=a.moveFromY+(a.targetY*16-a.moveFromY)*p
      a.frame=(a.frame+dt*5)%2;syncAgentPixels(a)
      if p>=1 then
        a.cellX,a.cellY=a.targetX,a.targetY;a.px,a.py=a.cellX*16,a.cellY*16
        a.targetX,a.targetY=nil,nil;a.moving=false;a.moveProgress=0;a.stepFlip=not a.stepFlip;syncAgentPixels(a)
      end
      return
    end
    if a.action=="idle" then return end
    if goalReached(st,a) then arrived(st,a);return end
    local dir=nextPathDir(st,a)
    if not beginAgentStep(st,a,dir) then
      -- A moving Pokemon may have blocked the route since the
      -- decision was made. Re-plan briefly, then abandon an unreachable goal.
      a.pathFails=(a.pathFails or 0)+1
      if a.pathFails>=6 then
        a.goalX,a.goalY,a.goalAgent=nil,nil,nil;a.action="idle";a.actionTarget=nil;a.pendingSpeech=nil;a.pathFails=0
        a.nextDecision=st.time+.45+rnd(st)*.7
      end
    end
  end

  local function updateSimulation(st,dt)
    if not (st and st.ow and st.ow.map and st.ow.map.id==MAP_ID) then return end
    dt=dt or 1/60
    FX.update(st,dt)
    if st.paused then
      st.pauseTimer=(st.pauseTimer or 0)+dt
      if st.pauseTimer>14 and st.pauseFinish then
        local finish=st.pauseFinish; st.pauseFinish=nil
        logAction(st,"DAY CARE: evolution sequence did not report back; resuming.")
        finish()
      end
      return
    end
    st.time=st.time+dt
    BrainRuntime:update()
    if not st.autoMateDone and st.time>=st.mateAt then introduceAutomaticMate(st) end
    for _,a in ipairs(st.agents) do
      if not a.dead then
        a.hunger=clamp(a.hunger+dt*.25,0,100);a.thirst=clamp(a.thirst+dt*.31,0,100);a.fatigue=clamp(a.fatigue+dt*.14,0,100);a.social=clamp(a.social+dt*.09,0,100)
        Mind.updateDrives(st,a,dt)
        if a.reactionTimer and a.reactionTimer>0 then a.reactionTimer=a.reactionTimer-dt;if a.reactionTimer<=0 then a.reactionGlyph=nil end end
        if a.speechTimer>0 then a.speechTimer=a.speechTimer-dt;if a.speechTimer<=0 then a.speech=nil end end
        if a.down then
          -- Unconscious: no movement, no decision, no speech, no defense.
          a.moving=false;a.targetX=nil;a.targetY=nil;a.trace="UNCONSCIOUS"
          if st.time>=(a.wakeAt or 0) then wakeUp(st,a) end
        else
          Mind.tickPlan(st,a)
          updateMovement(st,a,dt)
        end
        if not a.down and not a.moving and a.action=="idle" and not a.brainWaiting and st.time>=a.nextDecision then
          local ev=nextEvent(a);local cands=candidatesFor(st,a);a.trace="PERCEIVE";a.pendingEvent=ev
          BrainRuntime:submit(st,a,ev,cands,function(agent,d) performDecision(st,agent,d) end)
        end
        -- Slow bookkeeping: interpretation of accumulated history.
        if st.time>=(a.nextReflect or 0) then
          a.nextReflect=st.time+6+rnd(st)*4
          Mind.updateBeliefs(st,a)
          Mind.updateStage(st,a)
        end
      end
    end
    for i=1,#st.agents do for j=i+1,#st.agents do
      local a,b=st.agents[i],st.agents[j]
      if not a.dead and not b.dead and not a.down and not b.down and dist(a,b)<25 then
        local key=a.id.."|"..b.id;local last=st.nearTimers[key] or -999
        if st.time-last>11 then
          st.nearTimers[key]=st.time
          pushEvent(st,a,b.id,"stayed near",b.name.." stayed close to me for a while.",{kind="stayed_near",cue=b.brain.." stayed near me",salience=2})
          pushEvent(st,b,a.id,"stayed near",a.name.." stayed close to me for a while.",{kind="stayed_near",cue=a.brain.." stayed near me",salience=2})
          a.drives.social_connection=clamp((a.drives.social_connection or 0)-8,0,100)
          b.drives.social_connection=clamp((b.drives.social_connection or 0)-8,0,100)
        end
      end
    end end
    checkBreeding(st,dt)
  end

  -- ==================================================================
  -- OBSERVER PRESENTATION
  -- ==================================================================
  -- Everything below is one-way.  Nothing drawn here is fed back into any
  -- Pokemon's ledger, beliefs, relationships or prompt.

  local TAG={bulbasaur="B",charmander="C",squirtle="S"}
  local function speakerTag(a) return (TAG[a.brain] or "?")..(a.isMate and "2" or "") end

  local function drawDynamicBubble(a,sx,sy,vw,vh)
    if not a.speech or a.speech=="" then return end
    local lines=wrap(upper(a.speech),15,4)
    local longest=2
    for _,line in ipairs(lines) do if #line>longest then longest=#line end end
    local bw=math.min(128,math.max(48,longest*8+8));local bh=(#lines+1)*8+6
    local bx=clamp(math.floor(sx-bw/2),2,math.max(2,vw-bw-2))
    local by=sy-bh-12;if by<2 then by=sy+14 end;by=clamp(math.floor(by),2,math.max(2,vh-bh-2))
    box(bx,by,bw,bh,.96);love.graphics.setColor(.05,.05,.05,1);Font.draw(speakerTag(a)..":",bx+4,by+3)
    for i,line in ipairs(lines) do Font.draw(line,bx+4,by+3+i*8) end
  end

  -- Private thoughts are drawn over the room again.  A thought box is dotted
  -- rather than solid so it never reads as something another Pokemon heard.
  local function drawThoughtBubble(st,a,sx,sy,vw,vh,taken)
    local text=a.thought
    if not text or text=="" then return end
    local lines=wrap(upper(text),13,99)
    if #lines==0 then return end
    local perPage=3
    local pages=math.max(1,math.ceil(#lines/perPage))
    local page=math.floor(st.time/2.2)%pages+1
    local first=(page-1)*perPage+1
    local shown={}
    for i=0,perPage-1 do local l=lines[first+i]; if not l then break end; shown[#shown+1]=l end
    if #shown==0 then return end
    local longest=2
    for _,l in ipairs(shown) do if #l>longest then longest=#l end end
    local bw=math.min(112,math.max(40,longest*8+8))
    local bh=(#shown+1)*8+4
    local bx=clamp(math.floor(sx-bw/2),2,math.max(2,vw-bw-2))
    local by=clamp(math.floor(sy-bh-10),2,math.max(2,vh-bh-2))
    -- Nudge down past anything already drawn so two thinkers stay readable.
    for _,r in ipairs(taken) do
      if bx<r.x+r.w and bx+bw>r.x and by<r.y+r.h and by+bh>r.y then
        by=clamp(r.y+r.h+2,2,math.max(2,vh-bh-2))
      end
    end
    taken[#taken+1]={x=bx,y=by,w=bw,h=bh}
    love.graphics.setColor(.96,.98,.91,.90)
    love.graphics.rectangle("fill",bx,by,bw,bh)
    love.graphics.setColor(.08,.10,.08,1)
    for x=bx,bx+bw-1,2 do
      love.graphics.rectangle("fill",x,by,1,1)
      love.graphics.rectangle("fill",x,by+bh-1,1,1)
    end
    for y=by,by+bh-1,2 do
      love.graphics.rectangle("fill",bx,y,1,1)
      love.graphics.rectangle("fill",bx+bw-1,y,1,1)
    end
    -- Thought tail: two shrinking dots toward the Pokemon.
    local tx=clamp(math.floor(sx),bx+2,bx+bw-4)
    love.graphics.rectangle("fill",tx,by+bh+1,2,2)
    love.graphics.rectangle("fill",tx+1,by+bh+4,1,1)
    Font.draw(speakerTag(a)..":",bx+3,by+1)
    if pages>1 then Font.draw(page.."/"..pages,bx+bw-19,by+1) end
    for i,line in ipairs(shown) do Font.draw(line,bx+3,by+1+i*8) end
  end

  local function drawFollowerAgent(game,a,sx,sy)
    local img=(not a.noFollower) and followerImage(a.brain) or nil
    if not img then
      -- Fail visibly but safely if an asset cannot be decoded on a host:
      -- the real party record still has the engine's normal party icon.
      pcall(PartyMenu.drawIcon,game,a.mon,math.floor(sx),math.floor(sy),false,0,a.moving)
      return
    end
    local poses=a.moving and FOLLOWER_WALK or FOLLOWER_STAND
    local frame=poses[a.facing] or 0
    local q=followerQuad(a.brain,img,frame)
    if not q then return end
    local flip=(a.facing=="right") or (a.moving and a.stepFlip and (a.facing=="up" or a.facing=="down"))
    local dx=math.floor(sx)+(flip and 16 or 0)
    love.graphics.draw(img,q,dx,math.floor(sy),0,flip and -1 or 1,1)
  end

  local function drawWorldAgents(st,viewport)
    local game=st.game;local ow=st.ow;if not (ow and ow.camera) then return end
    local vw,vh=game.renderer:worldViewSize();local ww,wh=viewport.width,viewport.height
    local sxScale,syScale=ww/math.max(1,vw),wh/math.max(1,vh)
    st.hitRects={}
    love.graphics.push();love.graphics.scale(sxScale,syScale)
    local taken={}
    for _,a in ipairs(st.agents) do
      local shake=0
      if a.fxShake and a.fxShake>0 then shake=((a.fxShake*60)%2<1) and 1 or -1 end
      local sx=a.px-ow.camera.x+(a.fxOffX or 0)+shake
      local sy=a.py-ow.camera.y-4+(a.fxOffY or 0)
      if sx>-20 and sx<vw+20 and sy>-20 and sy<vh+20 then
        love.graphics.setColor(1,1,1,1)
        drawFollowerAgent(game,a,sx,sy)
        if a.fxFlash and a.fxFlash>0 then
          love.graphics.setColor(.99,.99,.95,math.min(.75,a.fxFlash*2))
          love.graphics.rectangle("fill",math.floor(sx),math.floor(sy),16,16)
          love.graphics.setColor(1,1,1,1)
        end
        if a.dead then love.graphics.setColor(.08,.08,.08,1);Font.draw("X",sx+6,sy+5)
        elseif a.down then love.graphics.setColor(.08,.08,.08,1);Font.draw("!",sx+6,sy+5) end
        if st.focus==a.id then love.graphics.setColor(.08,.08,.08,1);love.graphics.rectangle("line",sx-2,sy-2,20,20) end
        if a.reactionGlyph then love.graphics.setColor(.05,.05,.05,1);Font.draw(a.reactionGlyph,sx+13,sy-8) end
        FX.drawHealthBar(a,sx,sy)
        st.hitRects[#st.hitRects+1]={id=a.id,x=sx*sxScale,y=sy*syScale,w=20*sxScale,h=20*syScale}
      end
    end
    FX.draw(st,ow.camera.x,ow.camera.y)
    -- Bubbles last so nothing is drawn over them.
    for _,a in ipairs(st.agents) do
      local sx=a.px-ow.camera.x;local sy=a.py-ow.camera.y-4
      if sx>-20 and sx<vw+20 and sy>-20 and sy<vh+20 then
        love.graphics.setColor(.05,.05,.05,1)
        if a.speech and a.speech~="" then
          drawDynamicBubble(a,sx+8,sy+8,vw,vh)
        elseif st.showThoughts and not a.dead and not a.down
           and (st.focus==a.id or st.time-(a.thoughtAt or -999)<THOUGHT_SHOW_TIME) then
          drawThoughtBubble(st,a,sx+8,sy,vw,vh,taken)
        end
      end
    end
    if st.egg then
      local ex=st.egg.x-ow.camera.x-8;local ey=st.egg.y-ow.camera.y-8
      love.graphics.setColor(.05,.05,.05,1);Font.draw("EGG",ex,ey)
    end
    love.graphics.setColor(1,1,1,1)
    love.graphics.pop()
  end

  -- The focused panel uses the same transform the room sprites use, so it lands
  -- inside the visible game area on every host scale.
  local function drawObserverHud(st,viewport)
    local f=st.focus and agentById(st,st.focus)
    if not f then return end
    local vw,vh=st.game.renderer:worldViewSize()
    local sxScale=(viewport.width or vw)/math.max(1,vw)
    local syScale=(viewport.height or vh)/math.max(1,vh)
    love.graphics.push();love.graphics.scale(sxScale,syScale)
    box(1,69,158,74,.96);love.graphics.setColor(.05,.05,.05,1)
    local text=f.thought
    if f.dead then text="THIS POKEMON IS DEAD."
    elseif f.down then text="UNCONSCIOUS. IT CANNOT THINK, MOVE OR DEFEND ITSELF."
    elseif text=="" or text==nil then text="..." end
    local lines=wrap(upper(text),18,99)
    local perPage=5;local pages=math.max(1,math.ceil(#lines/perPage))
    local page=math.floor(st.time/3.5)%pages+1
    Font.draw(speakerTag(f)..":",4,72)
    Font.draw("S"..tostring(f.stage or 1),120,72)
    if pages>1 then Font.draw(page.."/"..pages,136,72) end
    local first=(page-1)*perPage+1
    for i=0,perPage-1 do
      local line=lines[first+i];if not line then break end
      Font.draw(line,4,80+i*8)
    end
    local plan=f.plan and upper(f.plan.label) or "NO PLAN"
    Font.draw("PLAN",4,122);Font.draw(trim(plan,14),44,122)
    Font.draw("PROCESS",4,132);Font.draw(trim(upper(f.trace),13),60,132)
    love.graphics.setColor(1,1,1,1)
    love.graphics.pop()
  end

  local INTERVENTION_TITLE={
    give_food="GIVE FOOD",take_food="TAKE FOOD",give_toy="GIVE TOY",take_toy="TAKE TOY",give_mate="GIVE MATE",take_mate="TAKE MATE",
  }

  mod.content.screens:register("AIObserverTargets",{
    new=function(game,opts)
      opts=opts or {};local state={game=game,isOpaque=true,index=1,kind=opts.kind}
      local function choices()
        local st=activeState;local out={{label="ALL",target=nil}}
        if st then
          for _,a in ipairs(interventionTargets(st,state.kind)) do out[#out+1]={label=speakerTag(a).." "..upper(a.name),target=a} end
        end
        return out
      end
      function state:update()
        local input=game.input;if not input then return end
        local list=choices();if #list==0 then return end
        if input:wasPressed("up") then self.index=self.index-1;if self.index<1 then self.index=#list end end
        if input:wasPressed("down") then self.index=self.index+1;if self.index>#list then self.index=1 end end
        if input:wasPressed("a") then
          local row=list[self.index];local st=activeState
          if st and row then applyIntervention(st,self.kind,row.target) end
          game.stack:pop()
        elseif input:wasPressed("b") or input:wasPressed("start") then game.stack:pop() end
      end
      function state:draw()
        love.graphics.setColor(1,1,1,1);love.graphics.rectangle("fill",0,0,160,144);love.graphics.setColor(0,0,0,1)
        Font.draw(INTERVENTION_TITLE[self.kind] or "INTERVENTION",16,8)
        Font.draw("TARGET",16,20)
        local list=choices()
        for i,row in ipairs(list) do
          local y=32+(i-1)*12
          if i==self.index then Font.draw(">",8,y) end
          Font.draw(row.label,24,y)
        end
        Font.draw("A:SELECT  B:BACK",8,132)
      end
      return state
    end,
  })

  mod.content.screens:register("AIObserverActivityLog",{
    new=function(game)
      local state={game=game,isOpaque=true,index=1}
      local function entries() return activeState and activeState.log or {} end
      function state:update()
        local input=game.input;if not input then return end
        local rows=entries();local n=math.max(1,#rows)
        if input:wasPressed("up") then self.index=math.max(1,self.index-1) end
        if input:wasPressed("down") then self.index=math.min(n,self.index+1) end
        if input:wasPressed("left") then self.index=math.max(1,self.index-6) end
        if input:wasPressed("right") then self.index=math.min(n,self.index+6) end
        if input:wasPressed("b") or input:wasPressed("start") then game.stack:pop() end
      end
      function state:draw()
        love.graphics.setColor(1,1,1,1);love.graphics.rectangle("fill",0,0,160,144);love.graphics.setColor(0,0,0,1)
        Font.draw("ACTIVITY LOG",32,8)
        local rows=entries();if #rows==0 then Font.draw("NO EVENTS YET",24,32);return end
        self.index=clamp(self.index,1,#rows)
        local first=math.max(1,math.min(self.index-2,math.max(1,#rows-5)))
        for slot=0,5 do
          local i=first+slot;local e=rows[i];if not e then break end
          local m=math.floor((e.t or 0)/60);local sec=math.floor((e.t or 0)%60)
          local prefix=string.format("%02d:%02d ",m,sec)
          if i==self.index then Font.draw(">",2,24+slot*12) end
          Font.draw(prefix..trim(upper(e.text),13),10,24+slot*12)
        end
        local e=rows[self.index]
        Font.draw("DETAIL",8,100)
        local detail=wrap(upper(e.text),18,4)
        for i,line in ipairs(detail) do Font.draw(line,8,108+(i-1)*8) end
      end
      return state
    end,
  })

  -- The permanent ledger, exactly as the Pokemon stores it.  Nothing here is
  -- ever deleted; retrieval decides what reaches the model, not this screen.
  mod.content.screens:register("AIObserverMemory",{
    new=function(game)
      local state={game=game,isOpaque=true,agentIndex=1,index=1}
      local function agents() return activeState and activeState.agents or {} end
      function state:update()
        local input=game.input;if not input then return end
        local list=agents();if #list==0 then if input:wasPressed("b") then game.stack:pop() end;return end
        if input:wasPressed("left") then self.agentIndex=self.agentIndex-1;if self.agentIndex<1 then self.agentIndex=#list end;self.index=1 end
        if input:wasPressed("right") then self.agentIndex=self.agentIndex+1;if self.agentIndex>#list then self.agentIndex=1 end;self.index=1 end
        local a=list[math.min(self.agentIndex,#list)]
        local n=math.max(1,#(a.ledger or {}))
        if input:wasPressed("up") then self.index=math.max(1,self.index-1) end
        if input:wasPressed("down") then self.index=math.min(n,self.index+1) end
        if input:wasPressed("a") then self.index=math.min(n,self.index+5) end
        if input:wasPressed("b") or input:wasPressed("start") then game.stack:pop() end
      end
      function state:draw()
        love.graphics.setColor(1,1,1,1);love.graphics.rectangle("fill",0,0,160,144);love.graphics.setColor(0,0,0,1)
        local list=agents();local a=list[math.min(self.agentIndex,math.max(1,#list))]
        Font.draw("MEMORY",8,4)
        if not a then Font.draw("NO AGENTS",8,32);return end
        local led=a.ledger or {}
        Font.draw(speakerTag(a).." "..upper(a.name),56,4)
        Font.draw(#led.." KEPT",8,16)
        Font.draw("STAGE "..tostring(a.stage or 1),96,16)
        if #led==0 then Font.draw("NOTHING YET",8,32);return end
        self.index=clamp(self.index,1,#led)
        -- Newest first; index 1 is the most recent line.
        local firstRow=math.max(1,math.min(self.index-2,math.max(1,#led-5)))
        for slot=0,5 do
          local i=firstRow+slot
          local e=led[#led-i+1]
          if not e then break end
          if i==self.index then Font.draw(">",2,28+slot*10) end
          Font.draw(clockOf(e.t).." "..trim(upper(e.text),10),10,28+slot*10)
        end
        local e=led[#led-self.index+1]
        if e then
          Font.draw(clockOf(e.t).." "..upper(tostring(e.kind or "")):sub(1,10),8,92)
          local detail=wrap(upper(e.text),18,4)
          for i,line in ipairs(detail) do Font.draw(line,8,102+(i-1)*8) end
        end
        Font.draw("L/R POKEMON  B:BACK",4,136)
      end
      return state
    end,
  })

  -- Everything the Pokemon has concluded for itself: stage, drives, values,
  -- self-concept, beliefs about others, its current plan, and the directional
  -- dispositions the learned network has been moving.
  mod.content.screens:register("AIObserverMind",{
    new=function(game)
      local state={game=game,isOpaque=true,agentIndex=1,tab=1,targetIndex=1}
      local TABS={"SELF","TOWARD","BELIEFS","PLAN"}
      local function agents() return activeState and activeState.agents or {} end
      local function others(a)
        local out={};for _,b in ipairs(agents()) do if b~=a then out[#out+1]=b end end;return out
      end
      function state:update()
        local input=game.input;if not input then return end
        local list=agents();if #list==0 then if input:wasPressed("b") then game.stack:pop() end;return end
        if input:wasPressed("left") then self.agentIndex=self.agentIndex-1;if self.agentIndex<1 then self.agentIndex=#list end;self.targetIndex=1 end
        if input:wasPressed("right") then self.agentIndex=self.agentIndex+1;if self.agentIndex>#list then self.agentIndex=1 end;self.targetIndex=1 end
        if input:wasPressed("a") then self.tab=self.tab%#TABS+1 end
        local a=list[math.min(self.agentIndex,#list)]
        local ts=others(a)
        if #ts>0 and input:wasPressed("up") then self.targetIndex=self.targetIndex-1;if self.targetIndex<1 then self.targetIndex=#ts end end
        if #ts>0 and input:wasPressed("down") then self.targetIndex=self.targetIndex+1;if self.targetIndex>#ts then self.targetIndex=1 end end
        if input:wasPressed("b") or input:wasPressed("start") then game.stack:pop() end
      end
      function state:draw()
        love.graphics.setColor(1,1,1,1);love.graphics.rectangle("fill",0,0,160,144);love.graphics.setColor(0,0,0,1)
        local list=agents();local a=list[math.min(self.agentIndex,math.max(1,#list))]
        Font.draw("MIND",6,4)
        if not a then Font.draw("NO AGENTS",8,32);return end
        Font.draw(speakerTag(a).." "..upper(a.name),46,4)
        Font.draw(TABS[self.tab],118,4)
        local y=18
        if self.tab==1 then
          Font.draw("STAGE "..tostring(a.stage or 1).."  EXP "..tostring(a.experience or 0),6,y);y=y+10
          local d=a.drives or {}
          Font.draw(("CURIOUS %3d SAFE %3d"):format(math.floor(d.curiosity or 0),math.floor(100-(d.security or 0))),6,y);y=y+9
          Font.draw(("SOCIAL  %3d BORED %3d"):format(math.floor(d.social_connection or 0),math.floor(d.stimulation or 0)),6,y);y=y+9
          Font.draw(("ALONE   %3d COMFORT %3d"):format(math.floor(d.autonomy or 0),math.floor(d.comfort or 0)),6,y);y=y+11
          local v,name=Mind.topValue(a)
          Font.draw("VALUES "..upper(name or "NONE"),6,y);y=y+9
          local sp=Mind.selfPhrase(a)
          local lines=wrap(upper(sp or "IT HAS NOT DECIDED WHAT IT IS LIKE YET."),19,4)
          for _,line in ipairs(lines) do Font.draw(line,6,y);y=y+8 end
        elseif self.tab==2 then
          local ts=others(a);local b=ts[math.min(self.targetIndex,math.max(1,#ts))]
          if not b then Font.draw("NOBODY ELSE HERE",6,y)
          else
            local r=a.rel[b.id] or {}
            Font.draw("TOWARD "..speakerTag(b).." "..upper(b.name),6,y);y=y+12
            Font.draw(("AFFECTION %4d"):format(math.floor(r.affection or 0)),6,y);y=y+10
            Font.draw(("TRUST     %4d"):format(math.floor(r.trust or 0)),6,y);y=y+10
            Font.draw(("ANGER     %4d"):format(math.floor(r.anger or 0)),6,y);y=y+10
            Font.draw(("FEAR      %4d"):format(math.floor(r.fear or 0)),6,y);y=y+10
            Font.draw(("ATTACH    %4d"):format(math.floor(r.attachment or 0)),6,y);y=y+10
            Font.draw(("FAMILIAR  %4d"):format(math.floor(r.familiarity or 0)),6,y);y=y+10
            if Mind.lethalAllowed(a,b) then Font.draw("SEVERE HOSTILITY",6,y) end
          end
        elseif self.tab==3 then
          local rows={}
          for _,bel in pairs(a.beliefs or {}) do rows[#rows+1]=bel end
          table.sort(rows,function(x,y2) return (x.strength or 0)>(y2.strength or 0) end)
          if #rows==0 then Font.draw("NO SETTLED BELIEFS YET",6,y)
          else
            for i=1,math.min(5,#rows) do
              Font.draw(("%3d "):format(math.floor(rows[i].strength or 0))..trim(upper(rows[i].text),15),6,y);y=y+10
            end
          end
          y=y+4
          local ts=others(a);local b=ts[math.min(self.targetIndex,math.max(1,#ts))]
          local th=b and Mind.theoryPhrase(activeState,a,b)
          Font.draw("READS",6,y);y=y+9
          Font.draw(trim(upper(th or "NOTHING YET"),19),6,y)
        else
          local p=a.plan
          if not p then Font.draw("NO PLAN RIGHT NOW",6,y)
          else
            local lines=wrap(upper(p.label or p.id),19,3)
            for _,line in ipairs(lines) do Font.draw(line,6,y);y=y+9 end
            y=y+4
            Font.draw("HELD "..math.floor((activeState and activeState.time or 0)-(p.startedAt or 0)).."S",6,y);y=y+9
            Font.draw("ENDS IN "..math.max(0,math.floor((p.expires or 0)-(activeState and activeState.time or 0))).."S",6,y);y=y+11
          end
          local kept,dropped=0,0
          for _,e in ipairs(a.ledger or {}) do
            if e.kind=="plan_kept" then kept=kept+1 elseif e.kind=="plan_dropped" then dropped=dropped+1 end
          end
          Font.draw("KEPT "..kept.."  DROPPED "..dropped,6,y)
        end
        Font.draw("A:TAB L/R:POKEMON",4,128);Font.draw("U/D:TARGET  B:BACK",4,136)
      end
      return state
    end,
  })

  mod.events:on("game.ready",function(ev) liveGame=ev.game end)
  mod.events:on("save.created",function() activeState=nil end)
  mod.events:on("map.entered",function(ev)
    local game=liveGame or mod.game
    if game and ev and ev.mapId==MAP_ID and game.overworld then initSimulation(game,ev.map,game.overworld) end
  end)

  mod.hooks:wrap("input.step",function(nextFn,g,dt)
    local out=nextFn(g,dt);local st=activeState
    if st and st.game==g then updateSimulation(st,dt) end
    return out
  end)

  mod.hooks:wrap("movement.collision",function(nextFn,allowed,ctx)
    local ok=nextFn(allowed,ctx);local st=activeState
    if not (st and ctx and ctx.map and ctx.map.id==MAP_ID) then return ok end
    if (ctx.map.warpAtCell and ctx.map:warpAtCell(ctx.toX,ctx.toY))
       or (ctx.map.isWarpTileCell and ctx.map:isWarpTileCell(ctx.toX,ctx.toY)) then
      ctx.reason="sealed";return false
    end
    if ctx.mover==st.ow.player then
      ctx.reason="observer"
      return false
    end
    return ok
  end)

  mod.hooks:wrap("input.pointer",function(nextFn,g,ev)
    local st=activeState
    if st and st.game==g and g.overworld and g.overworld.map and g.overworld.map.id==MAP_ID and ev.phase=="pressed" then
      if ev.button==2 then st.focus=nil
      elseif ev.button==nil or ev.button==1 then
        local hit=false
        local px,py=ev.x,ev.y
        for _,r in ipairs(st.hitRects or {}) do
          -- Accept the pointer in either viewport-local or window coordinates,
          -- because hosts differ in which one reaches this hook.
          local gx,gy=px-((ev.viewportX or 0)),py-((ev.viewportY or 0))
          if (px>=r.x and px<=r.x+r.w and py>=r.y and py<=r.y+r.h)
             or (gx>=r.x and gx<=r.x+r.w and gy>=r.y and gy<=r.y+r.h) then
            st.focus=(st.focus==r.id) and nil or r.id;hit=true;break
          end
        end
        if not hit then st.focus=nil end
      end
    end
    return nextFn(g,ev)
  end)

  mod.hooks:wrap("render.hud",function(nextFn,g,viewport)
    local out=nextFn(g,viewport);local st=activeState
    local top=g.stack and g.stack:top()
    if st and st.game==g and g.overworld and g.overworld.map and g.overworld.map.id==MAP_ID and top and top.isOverworld then
      drawWorldAgents(st,viewport);drawObserverHud(st,viewport)
    end
    return out
  end)

  mod.hooks:wrap("ui.start_menu.items",function(nextFn,game,items)
    local out=nextFn(game,items);local st=activeState
    if not (st and st.game==game and game.overworld and game.overworld.map and game.overworld.map.id==MAP_ID) then return out end
    local function target(kind) return function() Screens.push(game,"AIObserverTargets",{kind=kind}) end end
    return {
      {label=Strings("POKéMON"),onSelect=function()
        Screens.push(game,"PartyMenu",{onCancel=function() Screens.push(game,"StartMenu") end})
      end},
      {label="GIVE FOOD",keepOpen=true,onSelect=target("give_food")},
      {label="TAKE FOOD",keepOpen=true,onSelect=target("take_food")},
      {label="GIVE TOY",keepOpen=true,onSelect=target("give_toy")},
      {label="TAKE TOY",keepOpen=true,onSelect=target("take_toy")},
      {label="GIVE MATE",keepOpen=true,onSelect=target("give_mate")},
      {label="TAKE MATE",keepOpen=true,onSelect=target("take_mate")},
      {label=st.secret and "SECRET ON" or "VISIBLE",keepOpen=true,onSelect=function()
        st.secret=not st.secret
        logAction(st,"OBSERVER: intervention visibility = "..(st.secret and "SECRET" or "VISIBLE"))
      end},
      {label=st.showThoughts and "THOUGHTS ON" or "THOUGHTS OFF",keepOpen=true,onSelect=function()
        st.showThoughts=not st.showThoughts
      end},
      {label="MIND",keepOpen=true,onSelect=function() Screens.push(game,"AIObserverMind") end},
      {label="MEMORY",keepOpen=true,onSelect=function() Screens.push(game,"AIObserverMemory") end},
      {label="ACTIVITY LOG",keepOpen=true,onSelect=function() Screens.push(game,"AIObserverActivityLog") end},
    }
  end)

  mod.content.field:patch("boot",{
    startMap=MAP_ID,startX=2,startY=6,startFacing="up",playerName="OBSERVER",rivalName="NONE",startMoney=0,
    lastHeal={map=MAP_ID,x=2,y=6},screens={newGame="AIObserverIntroSkip"},
  })
  mod.log:info("Pokemon Observer AI Arena v1.7 loaded: permanent ledgers, retrieved memory, beliefs, plans, ten-second unconsciousness, gated lethal follow-up, sprite-scale battle animation and real party progression")

end
