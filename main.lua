
local START_MAP="POKEMON_MANSION_3F"
local MANSION={
  POKEMON_MANSION_1F=true,
  POKEMON_MANSION_2F=true,
  POKEMON_MANSION_3F=true,
  POKEMON_MANSION_B1F=true,
}

local DITTO="POKOPIA_DITTO"
local GRIMER="POKOPIA_GRIMER"
local MAGNEMITE="POKOPIA_MAGNEMITE"
local MAGNETON="POKOPIA_MAGNETON"
local VOLTORB="POKOPIA_VOLTORB"
local ELECTRODE="POKOPIA_ELECTRODE"
local KOFFING="POKOPIA_KOFFING"
local WEEZING="POKOPIA_WEEZING"
local PICHU="POKOPIA_PICHU"
local TOGEPI="POKOPIA_TOGEPI"
local POLIWHIRL="POKOPIA_POLIWHIRL"
local SLOWPOKE="POKOPIA_SLOWPOKE"
local DODRIO="POKOPIA_DODRIO"
local TOTODILE="POKOPIA_TOTODILE"
local SPINARAK="POKOPIA_SPINARAK"
local AMPHAROS="POKOPIA_AMPHAROS"
local LARVITAR="POKOPIA_LARVITAR"
local MUK="POKOPIA_MUK"
local PORYGON="POKOPIA_PORYGON"
local VULPIX="POKOPIA_VULPIX"
local RATTATA="POKOPIA_RATTATA"
local CHARMANDER="POKOPIA_CHARMANDER"
local BULBASAUR="POKOPIA_BULBASAUR"
local SQUIRTLE="POKOPIA_SQUIRTLE"
local PERSIAN="POKOPIA_PERSIAN"
local HYPNO="POKOPIA_HYPNO"
local ZUBAT="POKOPIA_ZUBAT"
local RATICATE="POKOPIA_RATICATE"
local EKANS="POKOPIA_EKANS"
local ARBOK="POKOPIA_ARBOK"
local GOLBAT="POKOPIA_GOLBAT"
local DROWZEE="POKOPIA_DROWZEE"
local VILEPLUME="POKOPIA_VILEPLUME"
local MURKROW="POKOPIA_MURKROW"
local HOUNDOUR="POKOPIA_HOUNDOUR"
local HOUNDOOM="POKOPIA_HOUNDOOM"
local TENTACOOL="POKOPIA_TENTACOOL"
local TENTACRUEL="POKOPIA_TENTACRUEL"
local EEVEE="POKOPIA_EEVEE"
local GROWLITHE="POKOPIA_GROWLITHE"
local BELLSPROUT="POKOPIA_BELLSPROUT"
local SENTRET="POKOPIA_SENTRET"
local WOOPER="POKOPIA_WOOPER"

local OPEN_BLOCK=0x0e

-- All switch-controlled barriers in the Mansion, copied from the engine's
-- own Pokemon Mansion script table. Every one is forced to the open floor.
local OPEN_GATES={
  POKEMON_MANSION_1F={
    {12,6},{8,3},{10,8},
  },
  POKEMON_MANSION_2F={
    {4,2},{9,4},{3,11},
  },
  POKEMON_MANSION_B1F={
    {13,8},{6,11},{4,3},{8,8},
  },
}

local function copy(t)
  local o={}
  for k,v in pairs(t or {}) do o[k]=v end
  return o
end

local function isMansion(id)
  return id and MANSION[id] == true
end

return function(mod)
  --------------------------------------------------------------------------
  -- Dialogue portrait framework.
  --
  -- Portrait art is intentionally NOT registered yet.  Dialogue boxes may
  -- opt into a portrait with:
  --   opts.portrait={speaker="VULPIX", expression="worried"}
  --
  -- Later portrait assets can be registered without changing the dialogue
  -- renderer:
  --   mod.pokopiaPortraits.register("VULPIX","worried",{
  --     image="assets/portraits/vulpix_worried.png"
  --   })
  --
  -- A speaker can have as many named expressions as needed.  Until an image
  -- is registered for a requested speaker/expression, no empty portrait frame
  -- is drawn; this keeps the current build clean while the art is pending.
  --------------------------------------------------------------------------
  local portraitRegistry={}
  local portraitImageCache={}

  local function portraitKey(speaker,expression)
    return tostring(speaker or "").."\0"..tostring(expression or "default")
  end

  local function registerPortrait(speaker,expression,def)
    if not speaker or speaker=="" then return end
    expression=expression or "default"
    portraitRegistry[portraitKey(speaker,expression)]=def or {}
    -- Permit a default fallback for expressions that do not yet have art.
    portraitImageCache[portraitKey(speaker,expression)]=nil
  end

  local function resolvePortrait(meta)
    if not meta then return nil end
    local speaker=meta.speaker or meta.id
    if not speaker then return nil end
    local expression=meta.expression or meta.variant or "default"
    return portraitRegistry[portraitKey(speaker,expression)]
      or portraitRegistry[portraitKey(speaker,"default")]
  end

  local function portraitImage(def)
    if not def or not def.image then return nil end
    local key=tostring(def.image)
    local cached=portraitImageCache[key]
    if cached~=nil then return cached or nil end

    -- These PNGs are packaged as ordinary files inside this mod, not as
    -- assets/generated overrides.  Assets.resolve intentionally leaves such
    -- paths untouched, so a bare "assets/portraits/..." path points at the
    -- game root and cannot find them.  mod.path is the loader-provided root of
    -- this exact installed mod; load the image from there directly.
    local fullPath=tostring(mod.path or "").."/"..tostring(def.image)
    local okImg,img=pcall(love.graphics.newImage,fullPath)
    if okImg and img and img.setFilter then img:setFilter("nearest","nearest") end
    portraitImageCache[key]=okImg and img or false
    return okImg and img or nil
  end

  -- Expose the registry to this mod's future dialogue/asset pass.  This is a
  -- small API on purpose: images and expression names can be added later
  -- without rewriting TextBox or existing cutscene code.
  mod.pokopiaPortraits={
    register=registerPortrait,
    resolve=resolvePortrait,
    registry=portraitRegistry,
  }

  -- Generation I Pokémon portrait library. Only the base-form images that
  -- live directly inside each Pokédex-number folder are packaged. Nested
  -- numbered form folders (including 0000/0001) and ^ alternates are ignored.
  local POKEMON_DEX={
    ["BULBASAUR"]="0001",
    ["IVYSAUR"]="0002",
    ["VENUSAUR"]="0003",
    ["CHARMANDER"]="0004",
    ["CHARMELEON"]="0005",
    ["CHARIZARD"]="0006",
    ["SQUIRTLE"]="0007",
    ["WARTORTLE"]="0008",
    ["BLASTOISE"]="0009",
    ["CATERPIE"]="0010",
    ["METAPOD"]="0011",
    ["BUTTERFREE"]="0012",
    ["WEEDLE"]="0013",
    ["KAKUNA"]="0014",
    ["BEEDRILL"]="0015",
    ["PIDGEY"]="0016",
    ["PIDGEOTTO"]="0017",
    ["PIDGEOT"]="0018",
    ["RATTATA"]="0019",
    ["RATICATE"]="0020",
    ["SPEAROW"]="0021",
    ["FEAROW"]="0022",
    ["EKANS"]="0023",
    ["ARBOK"]="0024",
    ["PIKACHU"]="0025",
    ["RAICHU"]="0026",
    ["SANDSHREW"]="0027",
    ["SANDSLASH"]="0028",
    ["NIDORAN_F"]="0029",
    ["NIDORINA"]="0030",
    ["NIDOQUEEN"]="0031",
    ["NIDORAN_M"]="0032",
    ["NIDORINO"]="0033",
    ["NIDOKING"]="0034",
    ["CLEFAIRY"]="0035",
    ["CLEFABLE"]="0036",
    ["VULPIX"]="0037",
    ["NINETALES"]="0038",
    ["JIGGLYPUFF"]="0039",
    ["WIGGLYTUFF"]="0040",
    ["ZUBAT"]="0041",
    ["GOLBAT"]="0042",
    ["ODDISH"]="0043",
    ["GLOOM"]="0044",
    ["VILEPLUME"]="0045",
    ["PARAS"]="0046",
    ["PARASECT"]="0047",
    ["VENONAT"]="0048",
    ["VENOMOTH"]="0049",
    ["DIGLETT"]="0050",
    ["DUGTRIO"]="0051",
    ["MEOWTH"]="0052",
    ["PERSIAN"]="0053",
    ["PSYDUCK"]="0054",
    ["GOLDUCK"]="0055",
    ["MANKEY"]="0056",
    ["PRIMEAPE"]="0057",
    ["GROWLITHE"]="0058",
    ["ARCANINE"]="0059",
    ["POLIWAG"]="0060",
    ["POLIWHIRL"]="0061",
    ["POLIWRATH"]="0062",
    ["ABRA"]="0063",
    ["KADABRA"]="0064",
    ["ALAKAZAM"]="0065",
    ["MACHOP"]="0066",
    ["MACHOKE"]="0067",
    ["MACHAMP"]="0068",
    ["BELLSPROUT"]="0069",
    ["WEEPINBELL"]="0070",
    ["VICTREEBEL"]="0071",
    ["TENTACOOL"]="0072",
    ["TENTACRUEL"]="0073",
    ["GEODUDE"]="0074",
    ["GRAVELER"]="0075",
    ["GOLEM"]="0076",
    ["PONYTA"]="0077",
    ["RAPIDASH"]="0078",
    ["SLOWPOKE"]="0079",
    ["SLOWBRO"]="0080",
    ["MAGNEMITE"]="0081",
    ["MAGNETON"]="0082",
    ["FARFETCHD"]="0083",
    ["DODUO"]="0084",
    ["DODRIO"]="0085",
    ["SEEL"]="0086",
    ["DEWGONG"]="0087",
    ["GRIMER"]="0088",
    ["MUK"]="0089",
    ["SHELLDER"]="0090",
    ["CLOYSTER"]="0091",
    ["GASTLY"]="0092",
    ["HAUNTER"]="0093",
    ["GENGAR"]="0094",
    ["ONIX"]="0095",
    ["DROWZEE"]="0096",
    ["HYPNO"]="0097",
    ["KRABBY"]="0098",
    ["KINGLER"]="0099",
    ["VOLTORB"]="0100",
    ["ELECTRODE"]="0101",
    ["EXEGGCUTE"]="0102",
    ["EXEGGUTOR"]="0103",
    ["CUBONE"]="0104",
    ["MAROWAK"]="0105",
    ["HITMONLEE"]="0106",
    ["HITMONCHAN"]="0107",
    ["LICKITUNG"]="0108",
    ["KOFFING"]="0109",
    ["WEEZING"]="0110",
    ["RHYHORN"]="0111",
    ["RHYDON"]="0112",
    ["CHANSEY"]="0113",
    ["TANGELA"]="0114",
    ["KANGASKHAN"]="0115",
    ["HORSEA"]="0116",
    ["SEADRA"]="0117",
    ["GOLDEEN"]="0118",
    ["SEAKING"]="0119",
    ["STARYU"]="0120",
    ["STARMIE"]="0121",
    ["MR_MIME"]="0122",
    ["SCYTHER"]="0123",
    ["JYNX"]="0124",
    ["ELECTABUZZ"]="0125",
    ["MAGMAR"]="0126",
    ["PINSIR"]="0127",
    ["TAUROS"]="0128",
    ["MAGIKARP"]="0129",
    ["GYARADOS"]="0130",
    ["LAPRAS"]="0131",
    ["DITTO"]="0132",
    ["EEVEE"]="0133",
    ["VAPOREON"]="0134",
    ["JOLTEON"]="0135",
    ["FLAREON"]="0136",
    ["PORYGON"]="0137",
    ["OMANYTE"]="0138",
    ["OMASTAR"]="0139",
    ["KABUTO"]="0140",
    ["KABUTOPS"]="0141",
    ["AERODACTYL"]="0142",
    ["SNORLAX"]="0143",
    ["ARTICUNO"]="0144",
    ["ZAPDOS"]="0145",
    ["MOLTRES"]="0146",
    ["DRATINI"]="0147",
    ["DRAGONAIR"]="0148",
    ["DRAGONITE"]="0149",
    ["MEWTWO"]="0150",
    ["MEW"]="0151",
    ["CHIKORITA"]="0152",
    ["BAYLEEF"]="0153",
    ["MEGANIUM"]="0154",
    ["CYNDAQUIL"]="0155",
    ["QUILAVA"]="0156",
    ["TYPHLOSION"]="0157",
    ["TOTODILE"]="0158",
    ["CROCONAW"]="0159",
    ["FERALIGATR"]="0160",
    ["SENTRET"]="0161",
    ["FURRET"]="0162",
    ["HOOTHOOT"]="0163",
    ["NOCTOWL"]="0164",
    ["LEDYBA"]="0165",
    ["LEDIAN"]="0166",
    ["SPINARAK"]="0167",
    ["ARIADOS"]="0168",
    ["CROBAT"]="0169",
    ["CHINCHOU"]="0170",
    ["LANTURN"]="0171",
    ["PICHU"]="0172",
    ["CLEFFA"]="0173",
    ["IGGLYBUFF"]="0174",
    ["TOGEPI"]="0175",
    ["TOGETIC"]="0176",
    ["NATU"]="0177",
    ["XATU"]="0178",
    ["MAREEP"]="0179",
    ["FLAAFFY"]="0180",
    ["AMPHAROS"]="0181",
    ["BELLOSSOM"]="0182",
    ["MARILL"]="0183",
    ["AZUMARILL"]="0184",
    ["SUDOWOODO"]="0185",
    ["POLITOED"]="0186",
    ["HOPPIP"]="0187",
    ["SKIPLOOM"]="0188",
    ["JUMPLUFF"]="0189",
    ["AIPOM"]="0190",
    ["SUNKERN"]="0191",
    ["SUNFLORA"]="0192",
    ["YANMA"]="0193",
    ["WOOPER"]="0194",
    ["QUAGSIRE"]="0195",
    ["ESPEON"]="0196",
    ["UMBREON"]="0197",
    ["MURKROW"]="0198",
    ["SLOWKING"]="0199",
    ["MISDREAVUS"]="0200",
    ["UNOWN"]="0201",
    ["WOBBUFFET"]="0202",
    ["GIRAFARIG"]="0203",
    ["PINECO"]="0204",
    ["FORRETRESS"]="0205",
    ["DUNSPARCE"]="0206",
    ["GLIGAR"]="0207",
    ["STEELIX"]="0208",
    ["SNUBBULL"]="0209",
    ["GRANBULL"]="0210",
    ["QWILFISH"]="0211",
    ["SCIZOR"]="0212",
    ["SHUCKLE"]="0213",
    ["HERACROSS"]="0214",
    ["SNEASEL"]="0215",
    ["TEDDIURSA"]="0216",
    ["URSARING"]="0217",
    ["SLUGMA"]="0218",
    ["MAGCARGO"]="0219",
    ["SWINUB"]="0220",
    ["PILOSWINE"]="0221",
    ["CORSOLA"]="0222",
    ["REMORAID"]="0223",
    ["OCTILLERY"]="0224",
    ["DELIBIRD"]="0225",
    ["MANTINE"]="0226",
    ["SKARMORY"]="0227",
    ["HOUNDOUR"]="0228",
    ["HOUNDOOM"]="0229",
    ["KINGDRA"]="0230",
    ["PHANPY"]="0231",
    ["DONPHAN"]="0232",
    ["PORYGON2"]="0233",
    ["STANTLER"]="0234",
    ["SMEARGLE"]="0235",
    ["TYROGUE"]="0236",
    ["HITMONTOP"]="0237",
    ["SMOOCHUM"]="0238",
    ["ELEKID"]="0239",
    ["MAGBY"]="0240",
    ["MILTANK"]="0241",
    ["BLISSEY"]="0242",
    ["RAIKOU"]="0243",
    ["ENTEI"]="0244",
    ["SUICUNE"]="0245",
    ["LARVITAR"]="0246",
    ["PUPITAR"]="0247",
    ["TYRANITAR"]="0248",
    ["LUGIA"]="0249",
    ["HO_OH"]="0250",
    ["CELEBI"]="0251",
  }
  local POKEMON_SPEAKER_ALIASES={
    ["NIDORAN♀"]="NIDORAN_F",
    ["NIDORAN♂"]="NIDORAN_M",
    ["FARFETCH'D"]="FARFETCHD",
    ["MR. MIME"]="MR_MIME",
    ["MR.MIME"]="MR_MIME",
    ["HO-OH"]="HO_OH",
    ["HO OH"]="HO_OH",
  }
  -- Dialogue/display names that are individual Pokémon rather than species
  -- names. Keep the nameplate nickname, but resolve portrait art through the
  -- underlying species library.
  local POKEMON_PORTRAIT_ALIASES={
    ["PIXIE"]="VULPIX",
    ["RATTY"]="RATTATA",
  }
  local BASE_PORTRAIT_EXPRESSIONS={
    ["Normal"]=true,
    ["Angry"]=true,
    ["Crying"]=true,
    ["Determined"]=true,
    ["Dizzy"]=true,
    ["Happy"]=true,
    ["Inspired"]=true,
    ["Joyous"]=true,
    ["Pain"]=true,
    ["Sad"]=true,
    ["Shouting"]=true,
    ["Sigh"]=true,
    ["Stunned"]=true,
    ["Surprised"]=true,
    ["Teary-Eyed"]=true,
    ["Worried"]=true,
    ["Special0"]=true,
    ["Special1"]=true,
    ["Special2"]=true,
    ["Special3"]=true,
  }
  do
    for speaker,dex in pairs(POKEMON_DEX) do
      local base="assets/portraits/pokemon/"..dex.."/"
      -- Every species in the supplied set has Normal.png; it is the safe
      -- fallback when a contextual expression is unavailable for that species.
      registerPortrait(speaker,"default",{image=base.."Normal.png"})
      for expression in pairs(BASE_PORTRAIT_EXPRESSIONS) do
        registerPortrait(speaker,expression,{image=base..expression..".png", optional=true})
      end
    end
  end

  -- Speaker-aware dialogue UI. Speaker identity is presentation metadata,
  -- not prose: legacy strings such as "SUPER NERD: ..." are stripped before
  -- TextBox sees them, then rendered in a separate nameplate above the box.
  -- Keeping the source strings intact also means Giovanni's authored speech
  -- remains unchanged while its visual prefix is no longer printed inline.
  local activeDialogueMeta=nil
  local dialogueSerial=0

  local SPEAKER_ALIASES={
    ["NERD"]="SUPER NERD",
  }
  local KNOWN_SPEAKERS={
    ["RATTATA"]=true,["PERSIAN"]=true,["MAGNETON"]=true,
    ["MAGNEMITE"]=true,["VOLTORB"]=true,["ELECTRODE"]=true,
    ["KOFFING"]=true,["WEEZING"]=true,["GRIMER"]=true,["MUK"]=true,
    ["PICHU"]=true,["TOGEPI"]=true,["POLIWHIRL"]=true,["SLOWPOKE"]=true,["DODRIO"]=true,
    ["TOTODILE"]=true,["SPINARAK"]=true,["AMPHAROS"]=true,["LARVITAR"]=true,
    ["PORYGON"]=true,["VULPIX"]=true,["CHARMANDER"]=true,
    ["BULBASAUR"]=true,["DITTO"]=true,["WOOPER"]=true,
    ["LOGAN"]=true,["PIXIE"]=true,["SCIENTIST"]=true,
    ["GIOVANNI"]=true,["SUPER NERD"]=true,["PRIZE LADY"]=true,
    ["PRIZE WORKER"]=true,["TV REPORTER"]=true,["ROCKET"]=true,["ROCKET GUARD"]=true,
    ["SCALPER"]=true,["MOM"]=true,["DAD"]=true,["KID"]=true,["GIRL"]=true,
    ["OFFICER"]=true,["OLD MAN"]=true,["OLD TIMER"]=true,["YOUNGSTER"]=true,
    ["ERIKA"]=true,
  }
  local TRAINER_PORTRAITS={
    ["GIOVANNI"]="OPP_GIOVANNI",
    ["ERIKA"]="OPP_ERIKA",
    ["SUPER NERD"]="OPP_SUPER_NERD",
    ["SCIENTIST"]="OPP_SCIENTIST",
    ["LOGAN"]="OPP_SCIENTIST",
    ["PRIZE LADY"]="OPP_BEAUTY",
    ["PRIZE WORKER"]="OPP_BIKER",
    ["TV Reporter"]="OPP_COOLTRAINER_F",
    ["TV REPORTER"]="OPP_COOLTRAINER_F",
    ["ROCKET"]="OPP_ROCKET",
    ["ROCKET GUARD"]="OPP_ROCKET",
    ["OFFICER"]="OPP_COOLTRAINER_M",
    ["ATTENDANT"]="OPP_BEAUTY",
    ["OLD MAN"]="OPP_GENTLEMAN",
    ["OLD TIMER"]="OPP_GENTLEMAN",
    ["WOMAN"]="OPP_BEAUTY",
    ["SHOPPER"]="OPP_BEAUTY",
    ["GENTLEMAN"]="OPP_GENTLEMAN",
    ["SALESMAN"]="OPP_GENTLEMAN",
    ["CLERK"]="OPP_GENTLEMAN",
    ["BIKER"]="OPP_BIKER",
    ["BEAUTY"]="OPP_BEAUTY",
    ["TRAINER"]="OPP_COOLTRAINER_M",
    ["YOUNGSTER"]="OPP_YOUNGSTER",
    ["GAMBLER"]="OPP_GAMBLER",
    ["PLAYER"]="OPP_COOLTRAINER_M",
    ["MAN"]="OPP_GENTLEMAN",
    ["SCALPER"]="OPP_GAMBLER",
    ["MOM"]="OPP_BEAUTY",
    ["DAD"]="OPP_GENTLEMAN",
    ["KID"]="OPP_YOUNGSTER",
    ["GIRL"]="OPP_BEAUTY",
    ["YELLOW"]="POKOPIA_YELLOW",
  }

  local function speakerFromText(text)
    if type(text)~="string" then return nil,text end

    -- Explicit NAME: dialogue remains the strongest signal and has its label
    -- stripped because the nameplate now owns speaker presentation.
    local raw=text:match('^([A-Z][A-Z0-9 %-%\'%.]+):%s*')
    if raw then
      raw=raw:gsub('%s+$','')
      local speaker=SPEAKER_ALIASES[raw] or POKEMON_SPEAKER_ALIASES[raw] or raw
      if KNOWN_SPEAKERS[speaker] or POKEMON_DEX[speaker] or POKEMON_PORTRAIT_ALIASES[speaker] then
        local stripped=text:gsub('^[A-Z][A-Z0-9 %-%\'%.]+:%s*','',1)
        local esc=raw:gsub('([^%w])','%%%1')
        stripped=stripped:gsub('\f'..esc..':%s*','\f')
        return speaker,stripped
      end
    end

    -- Pokémon event text in this mod often uses narrated Gen-I phrasing
    -- instead of NAME: speech: "VULPIX is trembling", "PERSIAN used...",
    -- "DITTO had an idea", etc. Treat a species/nickname at the beginning of
    -- the textbox as the speaker for portrait/nameplate purposes while leaving
    -- the narration itself intact.
    local first=text:match('^([A-Z][A-Z0-9_ %-%\'%.♀♂]+)')
    if first then
      -- Try longest plausible leading token first so MR. MIME/FARFETCH'D work.
      local upper=first:gsub('%s+$','')
      local candidates={upper}
      local words={}
      for w in upper:gmatch('%S+') do words[#words+1]=w end
      for n=#words-1,1,-1 do
        candidates[#candidates+1]=table.concat(words,' ',1,n)
      end
      for _,candidate in ipairs(candidates) do
        local canonical=POKEMON_SPEAKER_ALIASES[candidate] or candidate
        if POKEMON_DEX[canonical] or POKEMON_PORTRAIT_ALIASES[canonical] then
          return canonical,text
        end
      end
    end
    return nil,text
  end

  local function pokemonExpressionFor(speaker,text)
    if not speaker or not POKEMON_DEX[speaker] then return nil end
    local t=tostring(text or ""):upper()
    -- Lightweight context inference. Explicit per-line portrait metadata still
    -- wins; this only chooses a sensible emotion for ordinary Pokémon speech.
    if t:find("AHH",1,true) or t:find("OW",1,true) or t:find("HURT",1,true) or t:find("PAIN",1,true) then return "Pain" end
    if t:find("CRY",1,true) or t:find("TEAR",1,true) or t:find("SOB",1,true) then return "Teary-Eyed" end
    if t:find("SORRY",1,true) or t:find("SAD",1,true) or t:find("MISS",1,true) or t:find("ALONE",1,true) then return "Sad" end
    if t:find("WORR",1,true) or t:find("SICK",1,true) or t:find("PLEASE",1,true) or t:find("SCARED",1,true) or t:find("TREMBL",1,true) then return "Worried" end
    if t:find("STUN",1,true) or t:find("CAN'T MOVE",1,true) then return "Stunned" end
    if t:find("?!",1,true) or t:find("WHAT",1,true) or t:find("HUH",1,true) or t:find("HEY...",1,true) then return "Surprised" end
    if t:find("!",1,true) and (t:find("NO",1,true) or t:find("GET",1,true) or t:find("STOP",1,true) or t:find("TCH",1,true)) then return "Angry" end
    if t:find("LET'S",1,true) or t:find("I'LL",1,true) or t:find("READY",1,true) or t:find("DO IT",1,true) or t:find("WON'T LOSE",1,true) or t:find("NEVER FIND",1,true) then return "Determined" end
    if t:find("THANK",1,true) or t:find("YAY",1,true) or t:find("GREAT",1,true) or t:find("THAT WAS ACTUALLY KINDA FUN",1,true) then return "Joyous" end
    if t:find("HEH",1,true) or t:find("HAH",1,true) or t:find("GOOD",1,true) or t:find("LIKE",1,true) or t:find("FUN",1,true) then return "Happy" end
    if t:find("HMPH",1,true) or t:find("NEVER MIND",1,true) or t:find("WHATEVER",1,true) then return "Sigh" end
    return "Normal"
  end

  local function inferPortraitMeta(speaker,text,existing)
    existing=existing or {}
    if existing.speaker then return existing end
    if not speaker then return existing end
    local portraitSpeaker=POKEMON_PORTRAIT_ALIASES[speaker] or speaker
    local meta={speaker=portraitSpeaker,expression=existing.expression}
    if POKEMON_DEX[portraitSpeaker] and not meta.expression then
      meta.expression=pokemonExpressionFor(portraitSpeaker,text) or "Normal"
    end
    return meta
  end

  -- Reflow dialogue into dense two-line pages. Authored \n / \v breaks are
  -- treated as soft whitespace inside each explicit \f beat, so a short
  -- sentence does not strand half of the textbox just because its source
  -- happened to contain a manual line break. TextBox.paginate then wraps by
  -- the active font's real pixel width; if the beat needs more than two rows,
  -- each additional pair becomes the next page.
  local function forceTwoLinePages(game,text,TextBox)
    if type(text)~="string" or text=="" or not TextBox or not TextBox.paginate then
      return text
    end
    local expanded=text
    if TextBox.substitute then
      local ok,value=pcall(TextBox.substitute,game,text)
      if ok and type(value)=="string" then expanded=value end
    end

    local out={}
    -- Keep authored page/event beats, but let line breaks within a beat reflow.
    local start=1
    while true do
      local cut=expanded:find("\f",start,true)
      local beat=cut and expanded:sub(start,cut-1) or expanded:sub(start)
      beat=beat:gsub("[\n\v]+"," ")
      beat=beat:gsub("[ \t]+"," ")
      beat=beat:gsub("^%s+",""):gsub("%s+$","")
      if beat~="" then
        local ok,pages=pcall(TextBox.paginate,beat)
        if ok and type(pages)=="table" then
          for _,page in ipairs(pages) do
            if type(page)=="table" then
              local i=1
              while i<=#page do
                local a=tostring(page[i] or "")
                local b=(i+1<=#page) and tostring(page[i+1] or "") or nil
                out[#out+1]=b and (a.."\n"..b) or a
                i=i+2
              end
            end
          end
        else
          out[#out+1]=beat
        end
      end
      if not cut then break end
      start=cut+1
    end

    if #out==0 then return expanded end
    return table.concat(out,"\f")
  end

  do
    local TextBox=require("src.render.TextBox")
    if TextBox and TextBox.new and not TextBox._pokopiaSpeakerUIWrapped then
      local originalNew=TextBox.new
      TextBox.new=function(game,text,done,opts,...)
        opts=opts or {}
        local speaker,clean=speakerFromText(text)
        -- Preserve authored control codes and let the engine TextBox handle\n        -- pagination/waits natively. Rewriting \f/\v here can change prompt\n        -- timing and was the source of premature dialogue close/advance bugs.\n        if opts.speaker then speaker=opts.speaker end
        dialogueSerial=dialogueSerial+1
        local serial=dialogueSerial
        local originalDone=done
        local wrappedDone=function(...)
          if activeDialogueMeta and activeDialogueMeta.serial==serial then
            activeDialogueMeta=nil
          end
          if originalDone then return originalDone(...) end
        end
        local box=originalNew(game,clean,wrappedDone,opts,...)
        local portrait=inferPortraitMeta(speaker,clean,opts.portrait)
        local meta={
          serial=serial,
          speaker=speaker or (portrait and portrait.speaker),
          portrait=portrait,
          box=box,
          game=game,
        }
        if box then
          box.pokopiaSpeaker=meta.speaker
          box.pokopiaPortrait=portrait
          box.pokopiaDialogueSerial=serial
        end
        activeDialogueMeta=meta
        return box
      end
      TextBox._pokopiaSpeakerUIWrapped=true
    end
  end

  local trainerImageCache={}

  -- Trainer art itself stays completely opaque. A separate RGB-only mask is
  -- generated from the source image and used as a stencil while drawing.
  -- Nothing in the trainer image is made transparent or discarded.
  local function trainerCutoutBundle(game,id)
    local path=nil
    if id=="POKOPIA_YELLOW" then
      path=mod.path.."/assets/custom_trainers/yellow.png"
    else
      if not (game and game.data and game.data.trainers) then return nil end
      local tr=game.data.trainers[id]
      path=tr and tr.pic
    end
    if not path then return nil end

    local okAssets,Assets=pcall(require,"src.render.Assets")
    if not okAssets or not Assets then return nil end

    local okData,data=pcall(function()
      if Assets.imageData then return Assets.imageData(path) end
      return love.image.newImageData(Assets.resolve(path))
    end)
    if not okData or not data then return nil end

    local w,h=data:getWidth(),data:getHeight()
    if w<1 or h<1 then return nil end

    -- Identify the dominant perimeter colour. Trainer battle art normally uses
    -- a flat white matte, but sampling the live source avoids hard-coding white.
    local bins={}
    local function sample(x,y)
      local r,g,b=data:getPixel(x,y)
      local qr=math.floor(r*63+0.5)
      local qg=math.floor(g*63+0.5)
      local qb=math.floor(b*63+0.5)
      local k=qr..":"..qg..":"..qb
      local e=bins[k]
      if not e then e={n=0,r=0,g=0,b=0}; bins[k]=e end
      e.n=e.n+1
      e.r=e.r+r; e.g=e.g+g; e.b=e.b+b
    end
    for x=0,w-1 do
      sample(x,0)
      if h>1 then sample(x,h-1) end
    end
    for y=1,h-2 do
      sample(0,y)
      if w>1 then sample(w-1,y) end
    end

    local best=nil
    for _,e in pairs(bins) do
      if not best or e.n>best.n then best=e end
    end
    if not best then return nil end
    local br,bg,bb=best.r/best.n,best.g/best.n,best.b/best.n

    -- Build an edge-connected matte map. This is only a drawing mask; the
    -- original RGB artwork is never altered by this classification.
    local matte={}
    local qx,qy={},{}
    local head,tail=1,0
    local tolerance=0.018
    local function key(x,y) return y*w+x+1 end
    local function matchesMatte(x,y)
      local r,g,b=data:getPixel(x,y)
      return math.abs(r-br)<=tolerance
         and math.abs(g-bg)<=tolerance
         and math.abs(b-bb)<=tolerance
    end
    local function push(x,y)
      if x<0 or y<0 or x>=w or y>=h then return end
      local k=key(x,y)
      if matte[k] or not matchesMatte(x,y) then return end
      matte[k]=true
      tail=tail+1
      qx[tail],qy[tail]=x,y
    end

    for x=0,w-1 do push(x,0); push(x,h-1) end
    for y=0,h-1 do push(0,y); push(w-1,y) end
    while head<=tail do
      local x,y=qx[head],qy[head]
      head=head+1
      push(x-1,y); push(x+1,y); push(x,y-1); push(x,y+1)
    end

    -- Create the fully opaque trainer image. Alpha is normalized to 1 for every
    -- pixel, including the matte. The matte will be hidden only by the stencil.
    local opaqueData=data:clone()
    for y=0,h-1 do
      for x=0,w-1 do
        local r,g,b=opaqueData:getPixel(x,y)
        opaqueData:setPixel(x,y,r,g,b,1)
      end
    end

    -- The mask itself is also fully opaque: white means draw trainer art,
    -- black means reject that location from the stencil.
    local maskData=love.image.newImageData(w,h)
    for y=0,h-1 do
      for x=0,w-1 do
        if matte[key(x,y)] then
          maskData:setPixel(x,y,0,0,0,1)
        else
          maskData:setPixel(x,y,1,1,1,1)
        end
      end
    end

    local okImg,img=pcall(love.graphics.newImage,opaqueData)
    local okMask,mask=pcall(love.graphics.newImage,maskData)
    if not okImg or not img or not okMask or not mask then return nil end
    if img.setFilter then img:setFilter("nearest","nearest") end
    if mask.setFilter then mask:setFilter("nearest","nearest") end
    return {image=img,mask=mask}
  end

  local function trainerPortraitImage(game,speaker)
    local id=TRAINER_PORTRAITS[speaker]
    if not id or not game then return nil,nil end
    if trainerImageCache[id]~=nil then
      local cached=trainerImageCache[id]
      if not cached then return nil,nil end
      return cached.image,cached.mask
    end

    local bundle=trainerCutoutBundle(game,id)
    if bundle then
      trainerImageCache[id]=bundle
      return bundle.image,bundle.mask
    end

    -- If a custom pack cannot be read into ImageData, fall back to the native
    -- trainer resolver. That fallback is drawn as-authored with no alpha edits.
    local okOak,OakSpeech=pcall(require,"src.ui.OakSpeech")
    if okOak and OakSpeech and OakSpeech.resolvePic then
      local ok,img=pcall(function()
        return OakSpeech.resolvePic(game,{type="trainer",id=id})
      end)
      if ok and img then
        if img.setFilter then img:setFilter("nearest","nearest") end
        trainerImageCache[id]={image=img,mask=nil}
        return img,nil
      end
    end

    trainerImageCache[id]=false
    return nil,nil
  end

  local function currentDialogueMeta(game)
    -- Prefer the live TextBox itself when it is the top state, but retain the
    -- explicit active record because some stack implementations wrap the box.
    if game and game.stack then
      local ok,top=pcall(function() return game.stack:top() end)
      if ok and top and (top.pokopiaSpeaker or top.pokopiaPortrait) then
        return {speaker=top.pokopiaSpeaker,portrait=top.pokopiaPortrait,box=top}
      end
    end
    return activeDialogueMeta
  end

  local function speakerVisual(game,meta)
    if not meta or (not meta.speaker and not meta.portrait) then return nil,nil,nil end
    local speaker=meta.speaker or (meta.portrait and meta.portrait.speaker)
    local portraitMeta=meta.portrait
    local def=resolvePortrait(portraitMeta)
    local img=portraitImage(def)
    -- Not every species has every emotion. If a requested expression asset is
    -- absent, fall back to that Pokémon's Normal/default portrait.
    if not img and portraitMeta and portraitMeta.speaker then
      local fallback=portraitRegistry[portraitKey(portraitMeta.speaker,"default")]
      if fallback~=def then img=portraitImage(fallback) end
    end
    -- Human dialogue may keep one nameplate while deliberately using a
    -- different trainer-class cutout (e.g. every line member says SCALPER,
    -- but their artwork matches Gambler/Super Nerd/Beauty/Gentleman).
    local trainerSpeaker=speaker
    if portraitMeta and portraitMeta.speaker
        and TRAINER_PORTRAITS[portraitMeta.speaker] then
      trainerSpeaker=portraitMeta.speaker
    end
    local isTrainer=trainerSpeaker and TRAINER_PORTRAITS[trainerSpeaker]~=nil
    local trainerMask=nil
    if not img and isTrainer then
      img,trainerMask=trainerPortraitImage(game,trainerSpeaker)
    end
    return speaker,img,isTrainer,trainerMask
  end

  -- Human trainer-class artwork is a character cutout, not a portrait card.
  -- Draw it before the native textbox so its feet are anchored at the bottom
  -- of the screen and the textbox naturally covers the lower edge, like a
  -- scripted character event.  No frame/background is drawn around it.
  local function dialogueBoxRect(meta,ctx)
    local ww=(ctx and ctx.ww) or 160
    local wh=(ctx and ctx.wh) or 144
    local box=meta and meta.box
    local tx=(box and box.boxTx) or 0
    local ty=(box and box.boxTy) or 12
    local tw=(box and box.boxTw) or 20
    local th=(box and box.boxTh) or 6
    return tx*8,ty*8,tw*8,th*8,ww,wh
  end

  local trainerMaskShader=nil
  local function getTrainerMaskShader()
    if trainerMaskShader==false then return nil end
    if trainerMaskShader then return trainerMaskShader end
    local ok,shader=pcall(love.graphics.newShader,[[
      extern Image cutoutMask;
      vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4 m=Texel(cutoutMask,tc);
        if (m.r < 0.5) discard;
        vec4 p=Texel(tex,tc);
        return vec4(p.rgb,1.0) * color;
      }
    ]])
    trainerMaskShader=ok and shader or false
    return ok and shader or nil
  end

  local function drawTrainerSpeaker(game,meta,ctx)
    local speaker,img,isTrainer,mask=speakerVisual(game,meta)
    if not isTrainer or not img then return end
    local bx,by,bw,bh,ww,wh=dialogueBoxRect(meta,ctx)
    local iw,ih=img:getWidth(),img:getHeight()
    local scale=2
    local x=bx+bw-iw*scale
    local y=wh-ih*scale
    if speaker=="SUPER NERD" then
      x=x+(iw*scale*0.28)
      y=y-(ih*scale*0.25)
    end
    x,y=math.floor(x),math.floor(y)

    love.graphics.push("all")
    love.graphics.setColor(1,1,1,1)

    local shader=mask and getTrainerMaskShader() or nil
    if shader and mask then
      -- Sample the independent silhouette mask in the same texture coordinates
      -- as the opaque trainer image. This works inside Gen1Recomp's active
      -- Canvas and does not require a stencil attachment.
      shader:send("cutoutMask",mask)
      love.graphics.setShader(shader)
      love.graphics.draw(img,x,y,0,scale,scale)
      love.graphics.setShader()
    else
      -- Compatibility fallback: keep the trainer image untouched and opaque.
      love.graphics.draw(img,x,y,0,scale,scale)
    end

    love.graphics.pop()
  end

  local portraitPaletteShader=nil
  local function portraitShader()
    if portraitPaletteShader==false then return nil end
    if portraitPaletteShader then return portraitPaletteShader end
    local ok,shader=pcall(love.graphics.newShader,[[
      extern vec3 c0; extern vec3 c1; extern vec3 c2; extern vec3 c3;
      vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4 p = Texel(tex, tc);
        float l = dot(p.rgb, vec3(0.299, 0.587, 0.114));
        vec3 mapped = l > 0.83 ? c0 : (l > 0.5 ? c1 : (l > 0.17 ? c2 : c3));
        return vec4(mapped, p.a) * color;
      }
    ]])
    portraitPaletteShader=ok and shader or false
    return ok and shader or nil
  end

  local function reversePalette(colors)
    if not colors then return nil end
    return {colors[4],colors[3],colors[2],colors[1]}
  end

  local function pokemonPortraitColors(game,species)
    local ok,PaletteFX=pcall(require,"src.render.PaletteFX")
    if not ok or not PaletteFX then return nil,nil end
    local mode=PaletteFX.mode
    -- Advanced is the one mode where the supplied full-colour portrait art
    -- is intentionally shown as authored.  Every other mode is reduced to
    -- four shades and recoloured through the same active palette family.
    if mode=="redpp" then return nil,PaletteFX end
    if mode=="classic" then return PaletteFX.CLASSIC,PaletteFX end
    if mode=="og" then
      return {{255,255,255},{170,170,170},{85,85,85},{0,0,0}},PaletteFX
    end
    if mode=="og_inv" then
      return {{0,0,0},{85,85,85},{170,170,170},{255,255,255}},PaletteFX
    end
    local colors=PaletteFX.monPal and PaletteFX.monPal(game and game.data,species) or nil
    if mode=="gbc_inv" then colors=reversePalette(colors) end
    return colors,PaletteFX
  end

  local function sendPortraitColors(shader,colors)
    if not (shader and colors and #colors>=4) then return false end
    for i=1,4 do
      local c=colors[i] or {0,0,0}
      shader:send("c"..(i-1),{(c[1] or 0)/255,(c[2] or 0)/255,(c[3] or 0)/255})
    end
    return true
  end

  local function fitNameplate(Font,label,maxWidth)
    local display=tostring(label or "")
    local textWidth=(Font and Font.width and Font.width(display)) or (#display*8)
    if textWidth<=maxWidth then return display,textWidth end
    local suffix="..."
    local suffixWidth=(Font and Font.width and Font.width(suffix)) or 24
    local spans=(Font and Font.split and Font.split(display)) or nil
    if spans then
      for keep=#spans,1,-1 do
        local cut=display:sub(1,spans[keep].to)..suffix
        local w=Font.width(cut)
        if w<=maxWidth then return cut,w end
      end
    end
    return suffix,math.min(suffixWidth,maxWidth)
  end

  local function drawSpeakerMeta(game,meta,ctx)
    if not meta or (not meta.speaker and not meta.portrait) then return end
    local Font=require("src.render.Font")
    local bx,by,bw,bh,ww,wh=dialogueBoxRect(meta,ctx)
    local speaker,img,isTrainer=speakerVisual(game,meta)

    -- Measure the actual rendered glyph advances.  The old fixed 92px cap
    -- was narrower than labels such as ROCKET GUARD/SUPER NERD and let text
    -- paint beyond the tab.  Grow the tab to the label up to the textbox
    -- width, then clip/truncate defensively if a future translated name is
    -- longer still.
    if speaker and speaker~="" then
      local maxInner=math.max(24,bw-20)
      local label,labelWidth=fitNameplate(Font,tostring(speaker),maxInner)
      local w=math.max(36,math.min(bw-8,labelWidth+10))
      local x=bx+4
      local y=by-14
      love.graphics.push("all")
      -- Native Font.draw uses black bitmap glyphs; use a light plate so the
      -- speaker name is always readable instead of black-on-black.
      love.graphics.setColor(1,1,1,1)
      love.graphics.rectangle("fill",x,y,w,12)
      love.graphics.setColor(0,0,0,1)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line",x,y,w,12)
      if love.graphics.setScissor then love.graphics.setScissor(x+4,y+1,w-8,10) end
      if Font and Font.draw then Font.draw(label,x+5,y+3) end
      if love.graphics.setScissor then love.graphics.setScissor() end
      love.graphics.pop()
    end

    -- Trainer-class sprites are already drawn as large bottom-anchored cutouts
    -- behind the textbox.  Only Pokémon use the compact portrait card.
    if isTrainer or not img then return end

    local size=40
    local x=bx+bw-size-4
    local y=by-size-3
    if y<4 then y=4 end
    local iw,ih=img:getWidth(),img:getHeight()
    local pad=2
    local avail=size-pad*2
    local scale=math.min(avail/iw,avail/ih)

    love.graphics.push("all")
    -- Match the speaker nameplate: one black card with a single white outline.
    love.graphics.setColor(0,0,0,1)
    love.graphics.rectangle("fill",x,y,size,size)
    love.graphics.setColor(1,1,1,1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line",x,y,size,size)

    local portraitSpecies=meta and meta.portrait and meta.portrait.speaker
    local colors,PaletteFX=pokemonPortraitColors(game,portraitSpecies)
    local sh=colors and portraitShader() or nil
    if sh and sendPortraitColors(sh,colors) then love.graphics.setShader(sh) end
    love.graphics.draw(img,
      math.floor(x+(size-iw*scale)/2),
      math.floor(y+(size-ih*scale)/2),0,scale,scale)
    love.graphics.setShader()
    love.graphics.pop()

    -- Portraits are already explicitly palette-processed above (or deliberately
    -- full colour in Advanced), so keep Renderer:endFrame's zone pass from
    -- tinting them a second time.
    if PaletteFX and PaletteFX.markTrueColor then
      pcall(PaletteFX.markTrueColor,x,y,size,size)
    end
  end

  local function drawSpeakerUI(game,ctx)
    drawSpeakerMeta(game,currentDialogueMeta(game),ctx)
  end

  -- Keep speaker presentation bound to the exact live TextBox. Trainer art is
  -- drawn first (behind the textbox); the nameplate/Pokémon portrait is drawn
  -- afterward (above it).
  do
    local TextBox=require("src.render.TextBox")
    if TextBox and TextBox.draw and not TextBox._pokopiaSpeakerDrawWrapped then
      local originalDraw=TextBox.draw
      TextBox.draw=function(self,...)
        local hasSpeaker=self and (self.pokopiaSpeaker or self.pokopiaPortrait)
        local game=self and (self.game or (activeDialogueMeta and activeDialogueMeta.game) or liveGame) or liveGame
        local meta=hasSpeaker and {
          speaker=self.pokopiaSpeaker,
          portrait=self.pokopiaPortrait,
          box=self,
        } or nil
        if meta then drawTrainerSpeaker(game,meta,{ww=160,wh=144}) end
        local result=originalDraw(self,...)
        if meta then drawSpeakerMeta(game,meta,{ww=160,wh=144}) end
        return result
      end
      TextBox._pokopiaSpeakerDrawWrapped=true
    end
  end
  --------------------------------------------------------------------------
  -- Newly-added Pokemon use the NORMAL/non-shiny generated runtime
  -- followsprites from randyadr's Pokemon Stadium 2 Overworld Models package.
  -- Existing Pokopia Pokemon retain their established follower sheets. Both
  -- paths use the same 16x16 / six-frame / anchorX=8 / anchorY=16 contract.
  --------------------------------------------------------------------------
  local placeholder=mod.content.sprites:get("SPRITE_PIKACHU")
    or mod.content.sprites:get("SPRITE_RED")

  local FOLLOWER_DEX={
    [DITTO]="132", [GRIMER]="088", [MAGNEMITE]="081", [MAGNETON]="082",
    [VOLTORB]="100", [ELECTRODE]="101", [KOFFING]="109", [WEEZING]="110",
    [POLIWHIRL]="061", [SLOWPOKE]="079", [DODRIO]="085", [TOTODILE]="158",
    [SPINARAK]="167", [AMPHAROS]="181", [LARVITAR]="246", [MUK]="089",
    [PORYGON]="137", [VULPIX]="037", [RATTATA]="019", [CHARMANDER]="004",
    [BULBASAUR]="001", [SQUIRTLE]="007", [PERSIAN]="053", [PICHU]="172", [TOGEPI]="175",
    [HYPNO]="097", [ZUBAT]="041", [RATICATE]="020", ["CUBONE"]="104",
    [EKANS]="023", [ARBOK]="024", [GOLBAT]="042", [DROWZEE]="096",
    [VILEPLUME]="045", [MURKROW]="198", [HOUNDOUR]="228", [HOUNDOOM]="229",
    [TENTACOOL]="072", [TENTACRUEL]="073",
    [EEVEE]="133", [GROWLITHE]="058", [BELLSPROUT]="069", [SENTRET]="161",
    [WOOPER]="194",
    ["SLOWBRO"]="080", ["HITMONLEE"]="106", ["HITMONCHAN"]="107",
  }

  -- Use the exact NORMAL/non-shiny Enhanced Overworld follower sheets from
  -- assets/enhanced_overworld/poke_followers for every Pokopia Pokemon.
  local function registerFollower(id)
    local dex=FOLLOWER_DEX[id]
    local image=nil

    if dex then
      image=mod.path.."/assets/enhanced_overworld/poke_followers/follower_"..dex.."_normal.png"
    elseif placeholder then
      image=placeholder.image
    end

    mod.content.sprites:register(id,{
      id=id,
      image=image,
      frames=6,
      walker=true,
      trueColor=true,
      frameWidth=16,
      frameHeight=16,
      anchorX=8,
      anchorY=16,
    })
  end

  registerFollower(DITTO)
  registerFollower(GRIMER)
  registerFollower(MAGNEMITE)
  registerFollower(MAGNETON)
  registerFollower(VOLTORB)
  registerFollower(ELECTRODE)
  registerFollower(KOFFING)
  registerFollower(WEEZING)
  registerFollower(POLIWHIRL)
  registerFollower(SLOWPOKE)
  registerFollower(DODRIO)
  registerFollower(TOTODILE)
  registerFollower(SPINARAK)
  registerFollower(AMPHAROS)
  registerFollower(LARVITAR)
  registerFollower(MUK)
  registerFollower(PORYGON)
  registerFollower(VULPIX)
  registerFollower(RATTATA)
  registerFollower(CHARMANDER)
  registerFollower(BULBASAUR)
  registerFollower(SQUIRTLE)
  registerFollower(PERSIAN)
  registerFollower(PICHU)
  registerFollower(TOGEPI)
  registerFollower(HYPNO)
  registerFollower(ZUBAT)
  registerFollower(RATICATE)
  registerFollower("CUBONE")
  registerFollower(EKANS)
  registerFollower(ARBOK)
  registerFollower(GOLBAT)
  registerFollower(DROWZEE)
  registerFollower(VILEPLUME)
  registerFollower(MURKROW)
  registerFollower(HOUNDOUR)
  registerFollower(HOUNDOOM)
  registerFollower(TENTACOOL)
  registerFollower(TENTACRUEL)
  registerFollower(EEVEE)
  registerFollower(GROWLITHE)
  registerFollower(BELLSPROUT)
  registerFollower(SENTRET)
  registerFollower(WOOPER)
  registerFollower("SLOWBRO")
  registerFollower("HITMONLEE")
  registerFollower("HITMONCHAN")

  -- Perfect Crystal female Team Rocket grunt supplied with the project gfx.
  mod.content.sprites:register("POKOPIA_ROCKET_GIRL",{
    id="POKOPIA_ROCKET_GIRL",
    image=mod.path.."/assets/custom_overworld/rocket_girl_pc.png",
    frames=6, walker=true,
    frameWidth=16, frameHeight=16, anchorX=8, anchorY=16,
  })


  -- Yellow uses the supplied 16x96 four-shade sheet with one preprocessing
  -- pass only: pure white (OBJ colour 0) becomes transparent. The remaining
  -- grayscale indices stay unchanged and use the engine's normal NPC palette.
  mod.content.sprites:register("POKOPIA_YELLOW",{
    id="POKOPIA_YELLOW",
    image=mod.path.."/assets/custom_overworld/yellow_transparent.png",
    frames=6,
    walker=true,
    trueColor=false,
    frameWidth=16,
    frameHeight=16,
    anchorX=8,
    anchorY=16,
  })

  mod.content.items:register("CHEESE",{
    id="CHEESE", name="CHEESE", price=0, keyItem=true, tossable=false,
  })

  mod.content.items:register("MAGNET",{
    id="MAGNET", name="MAGNET", price=0, keyItem=true, tossable=false,
  })

  mod.content.items:register("KEY_TO_CITY",{
    id="KEY_TO_CITY", name="KEY TO THE CITY", price=0, keyItem=true, tossable=false,
  })

  mod.content.items:register("SNACK",{
    id="SNACK", name="SNACK", price=0, keyItem=true, tossable=false,
  })

  -- Physical TCG booster packs. These are ordinary stackable Bag items.
  -- The item-effect registry freezes after mod load, so register the bridge now
  -- and attach the Celadon TCG implementation to it later at runtime.
  local tcgOpenPackEffectUse
  local tcgOpenPackDirectUse
  local tcgPackItemIds={
    "TCG_COLOSSEUM_PACK","TCG_EVOLUTION_PACK",
    "TCG_MYSTERY_PACK","TCG_LABORATORY_PACK",
  }
  mod.content.items:register("TCG_COLOSSEUM_PACK",{
    id="TCG_COLOSSEUM_PACK", name="COLOSSEUM PACK", price=10, tossable=true, pocket="ITEM", effect="TCG_OPEN_PACK",
  })
  mod.content.items:register("TCG_EVOLUTION_PACK",{
    id="TCG_EVOLUTION_PACK", name="EVOLUTION PACK", price=10, tossable=true, pocket="ITEM", effect="TCG_OPEN_PACK",
  })
  mod.content.items:register("TCG_MYSTERY_PACK",{
    id="TCG_MYSTERY_PACK", name="MYSTERY PACK", price=10, tossable=true, pocket="ITEM", effect="TCG_OPEN_PACK",
  })
  mod.content.items:register("TCG_LABORATORY_PACK",{
    id="TCG_LABORATORY_PACK", name="LABORATORY PACK", price=10, tossable=true, pocket="ITEM", effect="TCG_OPEN_PACK",
  })

  -- Registry content is mutable only during initial mod loading. Keep this
  -- callback tiny and delegate to the TCG system once Celadon initializes it.
  local tcgOpenPackEffectDef={
    needsTarget=false,
    field=true,
    battle=true,
    use=function(ctx)
      if tcgOpenPackEffectUse then return tcgOpenPackEffectUse(ctx) end
      return "failed",{"This pack could not be opened yet."}
    end,
  }
  mod.content.item_effects:register("TCG_OPEN_PACK",tcgOpenPackEffectDef)

  -- Install the Bag interception while hooks are still being registered.
  -- Some API-2 Gen1Recomp builds do not route custom Gen 1 item effects
  -- through data.item_effects, but do expose the item.use seam. Registering
  -- this here (rather than when Celadon starts) makes booster USE reliable.
  mod.hooks:wrap("item.use",function(next,game,battle,id,target,list,moveIndex,picker)
    if tcgOpenPackDirectUse then
      local handled=tcgOpenPackDirectUse(game,battle,id,target,list,moveIndex,picker)
      if handled then return end
    end
    return next(game,battle,id,target,list,moveIndex,picker)
  end)

  -- Hard Bag bypass for TCG boosters.  This does not rely on Runtime.call,
  -- ItemEffects.use, the custom item_effects registry, or field-use checks.
  -- Selecting a booster still opens the native Gen I USE/TOSS submenu, but
  -- its USE row calls Pokopia's pack opener directly.  Vanilla item dispatch
  -- is therefore unreachable for these four item ids, so OAK can never reject
  -- a booster because of map/location context.
  local tcgPackIdSet={}
  for _,id in ipairs(tcgPackItemIds) do tcgPackIdSet[id]=true end
  do
    local okBag,BagMenu=pcall(require,"src.ui.BagMenu")
    if okBag and type(BagMenu)=="table" and type(BagMenu.new)=="function"
        and not BagMenu._pokopiaTCGHardBypass then
      local vanillaBagNew=BagMenu.new
      BagMenu._pokopiaTCGHardBypass=true
      BagMenu.new=function(game,opts)
        opts=opts or {}
        local list=vanillaBagNew(game,opts)
        if not list or type(list.onChoose)~="function" then return list end
        local vanillaChoose=list.onChoose
        list.onChoose=function(item,...)
          local id=item and item.value
          if not tcgPackIdSet[id] or list.swapIndex then
            return vanillaChoose(item,...)
          end

          local Menu=require("src.ui.Menu")
          local QuantityBox=require("src.ui.QuantityBox")
          local ChoiceBox=require("src.ui.ChoiceBox")
          local Bag=require("src.inventory.Bag")
          local Strings=require("src.core.Strings")
          local def=game.data.items and game.data.items[id]

          local function refreshAfterRemove()
            local left=game.save.inventory[id]
            for i,row in ipairs(list.items or {}) do
              if row.value==id then
                if left then
                  row.right="x"..tostring(left)
                else
                  table.remove(list.items,i)
                  list.index=math.max(1,math.min(list.index,#list.items))
                end
                break
              end
            end
          end

          game.stack:push(Menu.new(game,{
            {label=Strings("USE"),onSelect=function()
              -- This is the decisive bypass: never call ItemEffects.use.
              if tcgOpenPackDirectUse then
                local handled=tcgOpenPackDirectUse(
                  game,opts.battle,id,nil,list,nil,nil)
                if handled then return end
              end
              -- If the TCG runtime has not initialized yet, keep the pack and
              -- suppress vanilla use rather than falling through to OAK.
              local TextBox=require("src.render.TextBox")
              game.stack:push(TextBox.new(game,"The booster pack isn't ready yet."))
            end},
            {label=Strings("TOSS"),onSelect=function()
              local have=(game.save.inventory and game.save.inventory[id]) or 0
              if have<=0 then return end
              game.stack:push(QuantityBox.new(game,{
                max=have,
                onDone=function(qty)
                  if not qty then return end
                  game.stack:push(ChoiceBox.new(game,function(yes)
                    if not yes then return end
                    Bag.remove(game.save,id,qty)
                    refreshAfterRemove()
                  end))
                end,
              }))
            end},
          },{tx=13,ty=10,tw=7,th=5}))
          return
        end
        return list
      end
    end
  end

  -- You are Ditto, rather than a trainer controlling one.
  mod.content.field:patch("playerSprites",{
    walk=DITTO,
    surf=DITTO,
    bike=DITTO,
    fly=DITTO,
    surfPikachu=DITTO,
  })

  -- Portraits are dialogue-only. Battle sprites, menu sprites, TCG duel art,
  -- transformation previews, and every other gameplay renderer keep their
  -- native/source artwork.  This deliberately leaves pokemon.sprite entirely
  -- untouched so Gen1 front/back battlers cannot be replaced by portrait art.

  --------------------------------------------------------------------------
  -- Stock New Game / OakSpeech presentation.
  --------------------------------------------------------------------------
  mod.content.field:patch("boot",{
    startMap=START_MAP,
    startX=8,
    startY=10,
    startFacing="left",
    playerName="DITTO",
    rivalName="",
    startMoney=0,
    lastHeal={map=START_MAP,x=8,y=10},
    namePresets={player={"DITTO"},rival={""}},
    -- Native title mon rotation: Ditto is always the first displayed species,
    -- then the title rotates only through the Pokemon present in the Mansion.
    title={
      cycleSpecies={
        "DITTO",
        "MAGNEMITE","MAGNETON","VOLTORB","ELECTRODE",
        "KOFFING","WEEZING","GRIMER","MUK","POLIWHIRL","SLOWPOKE","DODRIO","TOTODILE","SPINARAK","AMPHAROS","LARVITAR","PORYGON",
        "VULPIX","RATTATA","CHARMANDER","BULBASAUR",
      },
    },
    -- Explicitly retain the engine's real OakSpeech.
    screens={newGame="OakSpeech"},
  })

  -- Replace OakSpeech's CONTENT only. The stock OakSpeech screen still owns
  -- fades, text box placement, timing and completion behavior.
  mod.hooks:wrap("intro.oak_speech.build",function(next,steps,speech)
    return {
      {
        id="log568_a",
        kind="say",
        text="LOG 568:\f"
          .."The experiment has\nfailed.\f"
          .."Our last-ditch\nHail Mary project...\f"
          .."A complete and\ntotal failure.",
        pic={type="trainer",id="OPP_SCIENTIST"},
        reveal="fade",
      },
      {
        id="log568_b",
        kind="say",
        text="Estimations show\nwithin a few days...",
        pic={type="trainer",id="OPP_SCIENTIST"},
      },
      {
        id="log568_c",
        kind="say",
        text="Life on this planet\nas we know it will\ncome to an end.",
        pic={type="trainer",id="OPP_SCIENTIST"},
      },
    }
  end)

  --------------------------------------------------------------------------
  -- OakSpeech visual treatment.
  --
  -- Keep the original OakSpeech state/layout, but force its presentation
  -- background to black. The scientist portrait/text remain the stock
  -- OakSpeech elements drawn on top.
  --------------------------------------------------------------------------
  local inOakSpeech=false
  local introFinished=false

  local function stopPokopiaAlarm(game)
    if not game then return end
    local Sound=require("src.core.Sound")
    Sound.stopLoop("Low_Health_Alarm")
    if game.pokopiaAlarm then
      pcall(game.pokopiaAlarm.stop,game.pokopiaAlarm)
      game.pokopiaAlarm=nil
    end
  end

  local function startPokopiaAlarm(game)
    if not game then return end

    if type(game.save.modData)~="table" then game.save.modData={} end
    if type(game.save.modData.pokopia_log568)~="table" then
      game.save.modData.pokopia_log568={}
    end
    if game.save.modData.pokopia_log568.alarmDisabled then
      stopPokopiaAlarm(game)
      return
    end

    local Sound=require("src.core.Sound")
    Sound.stopLoop("Low_Health_Alarm")

    if game.pokopiaAlarm then
      pcall(game.pokopiaAlarm.stop,game.pokopiaAlarm)
      game.pokopiaAlarm=nil
    end

    local ok,alarm=pcall(require("src.core.ChipAudio").newLowHealthAlarm)
    if ok and alarm then
      pcall(alarm.setLooping,alarm,true)
      pcall(alarm.setVolume,alarm,0.4)
      pcall(alarm.play,alarm)
      game.pokopiaAlarm=alarm
    end
  end

  -- Exact engine seam: OakSpeech emits this from finish() immediately
  -- before it pops itself. The Mansion/DITTO overworld is the next state.
  mod.events:on("intro.oak_speech.finished",function(ev)
    introFinished=true
    local game=ev and ev.speech and ev.speech.game
    if game then startPokopiaAlarm(game) end
  end)

  mod.hooks:wrap("render.compose",function(next,renderer,ctx)
    local game=renderer and renderer.game
    local stack=game and game.stack
    local top=stack and stack.top and stack:top()
    local name=top and (top.id or top.name or top.screenId)

    -- OakSpeech implementations do not consistently expose an id, so also
    -- recognize its characteristic speech fields.
    inOakSpeech = name=="OakSpeech"
      or (top and top.steps and top.stepIndex and top.game and not top.map)

    if inOakSpeech then
      love.graphics.setColor(0,0,0,1)
      love.graphics.rectangle("fill",0,0,ctx.ww,ctx.wh)
    end

    return next()
  end)

  --------------------------------------------------------------------------
  -- Mansion-wide emergency population.
  -- Exactly one of every requested Pokemon exists across the four floors.
  --------------------------------------------------------------------------
  local MANSION={
    POKEMON_MANSION_1F=true,
    POKEMON_MANSION_2F=true,
    POKEMON_MANSION_3F=true,
    POKEMON_MANSION_B1F=true,
  }

  local function npc(i,x,y,sprite,movement,range,text,name)
    return {index=i,x=x,y=y,sprite=sprite,movement=movement or "STAY",
      range=range or "NONE",text=text,name=name}
  end

  local POP={
    POKEMON_MANSION_1F={
      npc(1,4,26,"SPRITE_SCIENTIST","STAY","RIGHT","TEXT_EXIT_A","EXIT_SCI_A"),
      npc(2,7,26,"SPRITE_SCIENTIST","STAY","LEFT","TEXT_EXIT_B","EXIT_SCI_B"),
      npc(7,17,17,"SPRITE_SCIENTIST","WALK","LEFT_RIGHT","TEXT_1S1","SCI_1A"),
      npc(8,10,12,"SPRITE_SCIENTIST","WALK","UP_DOWN","TEXT_1S2","SCI_1B"),
      npc(3,14,3,MAGNEMITE,"WALK","LEFT_RIGHT","TEXT_MAGNEMITE","MAGNEMITE"),
      npc(4,18,21,RATTATA,"WALK","ANY_DIR","TEXT_RATTATA","RATTATA"),
      npc(5,7,18,BULBASAUR,"STAY","NONE","TEXT_BULBASAUR","BULBASAUR"),
      npc(6,22,23,MUK,"WALK","LEFT_RIGHT","TEXT_MUK","MUK"),
      npc(10,6,3,"SPRITE_GIOVANNI","STAY","DOWN","TEXT_GIOVANNI","GIOVANNI"),
      npc(13,7,3,PERSIAN,"STAY","DOWN","TEXT_PERSIAN","PERSIAN"),
      npc(12,9,1,"SPRITE_ROCKET","STAY","DOWN","TEXT_ROCKET_GUARD","ROCKET_GUARD"),
      npc(14,7,5,"SPRITE_SCIENTIST","STAY","LEFT","TEXT_1S3","SCI_1C"),
      npc(15,20,15,POLIWHIRL,"WALK","LEFT_RIGHT","TEXT_POLIWHIRL","POLIWHIRL"),
      npc(16,5,24,LARVITAR,"STAY","NONE","TEXT_LARVITAR","LARVITAR"),
    },
    POKEMON_MANSION_2F={
      npc(1,3,17,"SPRITE_SCIENTIST","WALK","LEFT_RIGHT","TEXT_2S1","SCI_2A"),
      npc(2,18,2,"SPRITE_SCIENTIST","WALK","UP_DOWN","TEXT_2S2","SCI_2B"),
      npc(3,22,7,VOLTORB,"WALK","LEFT_RIGHT","TEXT_VOLTORB","VOLTORB"),
      npc(4,3,22,KOFFING,"WALK","UP_DOWN","TEXT_KOFFING","KOFFING"),
      npc(5,12,12,VULPIX,"STAY","NONE","TEXT_VULPIX","VULPIX"),
      -- CHEESE pickup on the table immediately below Koffing.
      -- Koffing spawns at (3,22); this is the intervening table cell (3,23),
      -- not the floor cell below the table.
      {
        index=6,
        x=3,y=23,
        sprite="SPRITE_POKE_BALL",
        movement="STAY",
        range="NONE",
        item="CHEESE",
        name="CHEESE_ITEM",
      },
      npc(7,5,23,SLOWPOKE,"STAY","NONE","TEXT_SLOWPOKE","SLOWPOKE"),
      npc(8,12,25,AMPHAROS,"STAY","NONE","TEXT_AMPHAROS","AMPHAROS"),

    },
    POKEMON_MANSION_3F={
      npc(1,5,11,"SPRITE_SCIENTIST","WALK","LEFT_RIGHT","TEXT_3S1","SCI_3A"),
      npc(2,20,11,"SPRITE_SCIENTIST","WALK","LEFT_RIGHT","TEXT_3S2","SCI_3B"),
      npc(3,7,9,"SPRITE_SCIENTIST","WALK","UP_DOWN","TEXT_3S3","SCI_3C"),
      npc(4,1,16,GRIMER,"WALK","LEFT_RIGHT","TEXT_GRIMER","GRIMER"),
      npc(5,6,12,MAGNETON,"WALK","UP_DOWN","TEXT_MAGNETON","MAGNETON"),
      npc(6,25,5,PORYGON,"STAY","NONE","TEXT_PORYGON","PORYGON"),
      npc(7,19,10,CHARMANDER,"WALK","LEFT_RIGHT","TEXT_CHARMANDER","CHARMANDER"),
      npc(8,23,7,DODRIO,"WALK","LEFT_RIGHT","TEXT_DODRIO","DODRIO"),
      npc(9,2,2,SPINARAK,"STAY","NONE","TEXT_SPINARAK","SPINARAK"),
      -- Developer time-jump helper, placed directly above the requested
      -- 3F test position (player shown at X12,Y12).
      npc(10,9,9,HYPNO,"STAY","NONE","TEXT_HYPNO_TIME","HYPNO_TIME"),
    },
    POKEMON_MANSION_B1F={
      npc(1,16,23,"SPRITE_SCIENTIST","WALK","LEFT_RIGHT","TEXT_BS1","SCI_BA"),
      npc(2,27,11,"SPRITE_SCIENTIST","WALK","UP_DOWN","TEXT_BS2","SCI_BB"),
      npc(5,13,15,"SPRITE_SCIENTIST","STAY","NONE","TEXT_PC_END","PC_SCIENTIST"),
      -- The basement PC is map geometry, not an overworld actor.  Its visual
      -- is installed from the vanilla POKECENTER blockset in mansionEnter().
      -- Verified vanilla B1F object coordinate (TM_BLIZZARD in pokered).
      npc(6,19,25,TOTODILE,"WALK","ANY_DIR","TEXT_TOTODILE","TOTODILE"),
      npc(3,10,2,ELECTRODE,"WALK","LEFT_RIGHT","TEXT_ELECTRODE","ELECTRODE"),
      npc(4,5,4,WEEZING,"WALK","UP_DOWN","TEXT_WEEZING","WEEZING"),
      npc(8,4,4,PICHU,"STAY","NONE","TEXT_PICHU","PICHU"),
      npc(9,6,4,TOGEPI,"STAY","NONE","TEXT_TOGEPI","TOGEPI"),
    },
  }

  for mapId,objects in pairs(POP) do
    local base=mod.content.maps:get(mapId)
    if base then
      local changed=copy(base)
      changed.objects=objects
      mod.content.maps:override(mapId,changed)
    end
    mod.content.encounters:override(mapId,{grass={rate=0,slots={}},water={rate=0,slots={}}})
  end

  -- Replace the three original CELADON_CHIEF_HOUSE occupants.
  -- The room geometry, exits and map scripts remain untouched; the family is
  -- spawned at runtime once Scene 2 reaches free roam.
  do
    local base=mod.content.maps:get("CELADON_CHIEF_HOUSE")
    if base then
      local changed=copy(base)
      changed.objects={}
      mod.content.maps:override("CELADON_CHIEF_HOUSE",changed)
    end
  end

  -- Scene 2 replaces every ordinary Game Corner floor NPC. The counter
  -- attendants are background/map interactions, not overworld objects, so
  -- clearing this list leaves the attendants intact while removing the vanilla
  -- gamblers and poster Rocket.
  do
    local base=mod.content.maps:get("GAME_CORNER")
    if base then
      local changed=copy(base)
      changed.objects={}
      -- The Rocket Hideout stair is permanently open in Pokopia. Vanilla's
      -- secret-door block lives at block (8,2); author the opened staircase
      -- block into the map record so renderers and fresh map instances see it
      -- open before any runtime script executes. Runtime reconciliation below
      -- still uses the engine-extracted poster metadata as a defensive pass.
      if changed.blocks and changed.width then
        changed.blocks=copy(changed.blocks)
        local stairIndex=2*changed.width+8+1
        if changed.blocks[stairIndex]~=nil then
          changed.blocks[stairIndex]=0x43
        end
      end
      changed._pokopiaRocketHideoutAlwaysOpen=true
      mod.content.maps:override("GAME_CORNER",changed)
    end
  end

  -- Permanent Celadon geometry authored into the merged map registry.
  --
  -- Dramatic Shape Voxel Mod captures Game.data maps at `mods.loaded` and
  -- deliberately meshes from that immutable snapshot. Runtime replaceBlock()
  -- edits therefore happen too late to affect its canonical 3D geometry. Keep
  -- Pokopia's always-open south Gym approach and tree-free Gym in the map
  -- records themselves, before any renderer takes that snapshot.
  do
    local base=mod.content.maps:get("CELADON_CITY")
    if base and base.blocks and base.width then
      local changed=copy(base)
      changed.blocks=copy(base.blocks)
      -- Screenshot references X=22..26,Y=31 sit directly north of this
      -- barrier row. Cells are 2 per block, so this is bx 11..13, by 16.
      -- 0x55 is Celadon's normal open-ground block already used by the
      -- runtime implementation in prior builds.
      for bx=11,13 do
        local i=16*changed.width+bx+1
        if changed.blocks[i]~=nil then changed.blocks[i]=0x55 end
      end

      -- The card-line/kid barrier at screen coordinates X=20, Y=10..13 is
      -- permanent geometry too.  Those cells are block column 10, rows 5..6.
      -- Author it here (rather than waiting for applyCeladonKidBarrier at
      -- runtime) so 3D renderers that snapshot the map during mods.loaded see
      -- exactly the same wall from their very first mesh build.
      local kidBarrierBlock=changed.borderBlock or 0x0f
      for by=5,6 do
        local i=by*changed.width+10+1
        if changed.blocks[i]~=nil then changed.blocks[i]=kidBarrierBlock end
      end

      changed._pokopiaPermanentSouthGymOpening=true
      changed._pokopiaPermanentKidBarrier=true
      mod.content.maps:override("CELADON_CITY",changed)
    end
  end

  do
    local base=mod.content.maps:get("CELADON_GYM")
    if base and base.blocks then
      local changed=copy(base)
      changed.blocks=copy(base.blocks)
      -- Native Gen I GYM Cut swaps. Applying them to the authored blockmap
      -- removes every cut-tree obstacle from both visuals and collision before
      -- the map ever reaches the 2D or voxel renderer.
      local swaps={[0x3c]=0x35,[0x3f]=0x35,[0x3d]=0x36}
      for i,block in ipairs(changed.blocks) do
        changed.blocks[i]=swaps[block] or block
      end
      changed._pokopiaPermanentTreeFree=true
      mod.content.maps:override("CELADON_GYM",changed)
    end
  end

  -- Rocket Hideout living-floor geometry.
  --
  -- Keep these plans in the enclosing mod scope because they are applied twice:
  -- once to the authored map registry (so renderers that snapshot maps at load
  -- time see the remodel) and again to the live overworld on entry (so no later
  -- vanilla/map-script reconciliation can resurrect the old spinner maze).
  --
  -- Coordinates below are map BLOCK coordinates, not 16x16 player cells.
  -- Furnishings use only native Gen-I FACILITY blocks already present in the
  -- ROM. No generated images or runtime image construction are used here.
  local ROCKET_HOME_FLOOR=0x0e
  local ROCKET_HOME_LAYOUTS={
    ROCKET_HIDEOUT_B1F={
      -- Main recreation/dining floor. Keep the irregular shell and stair/elevator
      -- pockets, but turn the old offices into one believable shared living room
      -- plus a compact east-side break/dispatch nook.
      clear={{5,10,3,12},{12,13,3,7}},
      furniture={
        -- North-west lounge: television/console on the wall, two couches and
        -- low tables arranged around an open center rather than in a grid.
        {5,4,0x0a},{6,4,0x47},{7,4,0x47},
        {5,5,0x28},{8,5,0x28},{6,6,0x37},{7,6,0x37},

        -- Central communal table. The 34/36/37 family is a native multi-block
        -- table set, deliberately centered with a full walking lane around it.
        {7,8,0x34},{8,8,0x34},{9,8,0x34},
        {7,9,0x36},{8,9,0x36},{9,9,0x36},
        {7,10,0x37},{8,10,0x37},{9,10,0x37},

        -- South-west kitchen/prep wall. Appliances are against the perimeter so
        -- nobody has to walk through a kitchen work triangle to cross the room.
        {5,10,0x52},{5,11,0x61},{6,11,0x65},{5,12,0x54},{6,12,0x54},

        -- East break/dispatch nook: couch, console/TV and storage with the
        -- center cells deliberately kept open for the two quest terminals.
        {12,4,0x47},{13,4,0x47},{12,5,0x28},
        {13,5,0x0a},
      },
    },

    ROCKET_HIDEOUT_B2F={
      -- Barracks. This rectangle is the actual Gen-I spinner maze. Every block
      -- in it is rewritten to plain floor before any furniture is stamped.
      clear={{1,10,4,12},{12,13,4,8}},
      furniture={
        -- Eight bunks in two rows with generous center aisles. Beds are paired
        -- with lockers rather than scattered randomly throughout the floor.
        {2,4,0x43},{4,4,0x43},{6,4,0x43},{8,4,0x43},
        {2,7,0x43},{4,7,0x43},{6,7,0x43},{8,7,0x43},
        {1,4,0x52},{3,4,0x54},{5,4,0x52},{7,4,0x54},{9,4,0x52},
        {1,7,0x52},{3,7,0x54},{5,7,0x52},{7,7,0x54},{9,7,0x52},

        -- Small lounge between the sleeping and dining zones.
        {4,9,0x28},{5,9,0x37},{6,9,0x37},{7,9,0x28},

        -- South dining table, offset from the bunks so the main vertical aisle
        -- remains open from the stairs to the lower half of the room.
        {5,10,0x34},{6,10,0x34},{7,10,0x34},
        {5,11,0x36},{6,11,0x36},{7,11,0x36},
        {5,12,0x37},{6,12,0x37},{7,12,0x37},

        -- Laundry/kitchen utility corner against the lower-left wall.
        {2,10,0x61},{3,10,0x65},{2,11,0x52},{3,11,0x54},

        -- East quartermaster room: desk/console facing the room, couch and
        -- storage on the wall instead of blocking the doorway.
        {12,4,0x0a},{13,4,0x52},{12,5,0x47},{13,5,0x47},
        {12,7,0x28},{13,7,0x54},
      },
    },

    ROCKET_HIDEOUT_B3F={
      -- TV / games / operations floor. The upper rectangle contains the other
      -- major spinner maze and is completely repaved.
      clear={{5,13,3,8},{5,10,9,12}},
      furniture={
        -- TV wall with a shallow U-shaped seating group.
        {7,4,0x0a},{8,4,0x0a},
        {6,5,0x28},{9,5,0x28},
        {6,6,0x47},{7,6,0x37},{8,6,0x37},{9,6,0x47},

        -- Card/strategy corner on the east side, kept separate from the TV lane.
        {11,4,0x34},{12,4,0x34},
        {11,5,0x36},{12,5,0x36},
        {11,6,0x37},{12,6,0x37},{13,6,0x28},

        -- Lower operations/workshop: terminals on the north edge, benches and
        -- storage around the perimeter, open center for technicians and traffic.
        {5,10,0x0a},{6,10,0x0a},{7,10,0x52},{8,10,0x54},
        {5,11,0x47},{6,11,0x47},{8,11,0x28},{9,11,0x28},
        {5,12,0x61},{6,12,0x65},{9,12,0x52},{10,12,0x54},
      },
    },

    ROCKET_HIDEOUT_B4F={
      -- Quiet residential/medical/records floor. There was no spinner maze on
      -- B4F, but the original command-room partitions are repurposed as rooms.
      clear={{5,13,1,10}},
      furniture={
        -- North sleeping/medical row. Beds are parallel, each with a cabinet.
        {5,2,0x43},{7,2,0x43},{9,2,0x43},{11,2,0x43},
        {5,3,0x52},{7,3,0x52},{9,3,0x52},{11,3,0x52},

        -- Archive/monitor wall immediately below the beds.
        {5,5,0x54},{6,5,0x54},{7,5,0x0a},{8,5,0x0a},

        -- Lounge with facing couches and two low tables.
        {6,7,0x28},{9,7,0x28},
        {6,8,0x47},{7,8,0x37},{8,8,0x37},{9,8,0x47},

        -- South kitchen and dining area. The kitchen hugs the east wall; the
        -- dining table sits west of it with a clean route to the elevator.
        {10,9,0x61},{11,9,0x65},{12,9,0x52},{13,9,0x54},
        {6,9,0x34},{7,9,0x34},{8,9,0x34},
        {6,10,0x37},{7,10,0x37},{8,10,0x37},
      },
    },
  }

  local function rocketHomeBlockKey(bx,by)
    return tostring(bx)..":"..tostring(by)
  end

  local function rocketHomeWarpBlocks(map)
    local keep={}
    local warps=(map and map.warps)
      or (map and map.def and map.def.warps)
      or {}
    for _,w in ipairs(warps) do
      local x=tonumber(w.x or w[1]); local y=tonumber(w.y or w[2])
      if x and y then
        keep[rocketHomeBlockKey(math.floor(x/2),math.floor(y/2))]=true
      end
    end
    return keep
  end

  -- Author the remodel into the merged map records. Crucially, vanilla object
  -- removal happens in THIS SAME override. Older builds did a second map
  -- override afterward just to clear objects; depending on registry semantics,
  -- that could re-read the pristine ROM map and silently put the spinner maze
  -- back. There is now one final override per hideout floor.
  do
    for mapId,plan in pairs(ROCKET_HOME_LAYOUTS) do
      local base=mod.content.maps:get(mapId)
      if base and base.blocks and base.width and base.height then
        local changed=copy(base)
        changed.blocks=copy(base.blocks)
        changed.objects={}
        local keep=rocketHomeWarpBlocks(base)

        local function setBlock(bx,by,block)
          if bx<0 or by<0 or bx>=base.width or by>=base.height then return end
          if keep[rocketHomeBlockKey(bx,by)] then return end
          changed.blocks[by*base.width+bx+1]=block
        end

        -- First pass: repave every old maze/office cell in the authored room
        -- rectangles. This removes arrow/spinner tiles, maze dividers, old
        -- consoles and collision pieces instead of selectively painting over a
        -- few visible cells.
        for _,r in ipairs(plan.clear or {}) do
          for by=r[3],r[4] do
            for bx=r[1],r[2] do setBlock(bx,by,ROCKET_HOME_FLOOR) end
          end
        end

        -- Second pass: furnish the empty rooms deliberately.
        for _,f in ipairs(plan.furniture or {}) do
          setBlock(f[1],f[2],f[3])
        end

        changed._pokopiaFurnishedRocketHome=true
        changed._pokopiaRocketMazeRemoved=true
        mod.content.maps:override(mapId,changed)
      end
      mod.content.encounters:override(mapId,{grass={rate=0,slots={}},water={rate=0,slots={}}})
    end

    -- Elevator has no living-floor remodel; only remove its vanilla occupants.
    local elevator=mod.content.maps:get("ROCKET_HIDEOUT_ELEVATOR")
    if elevator then
      local changed=copy(elevator)
      changed.objects={}
      mod.content.maps:override("ROCKET_HIDEOUT_ELEVATOR",changed)
      mod.content.encounters:override("ROCKET_HIDEOUT_ELEVATOR",{grass={rate=0,slots={}},water={rate=0,slots={}}})
    end
  end


  --------------------------------------------------------------------------
  -- Ditto player UI portraits. These contexts do not alter OakSpeech.
  --------------------------------------------------------------------------
  mod.hooks:wrap("player.sprite",function(next,path,ctx)
    if ctx and ctx.side=="front"
        and ctx.kind=="trainer_card" then
      local data=ctx.data
      local ditto=data and data.pokemon and data.pokemon.DITTO
      if ditto and ditto.spriteFront then
        ctx.trueColor=ditto.trueColor and true or false
        return ditto.spriteFront
      end
    end
    return next(path,ctx)
  end)


  -- Forward declarations: the transform menu is defined before the
  -- overworld sprite helpers, but its onSelect runs later at runtime.
  local activeOverworld
  local applyDittoForm
  local liveGame
  local muchEarlier
  -- The LOG 568 bookend finale lives in finale.lua and is constructed further
  -- down, once its dialogue/portrait/overworld dependencies exist. It is
  -- declared here because `startCeladonEnding` closes over it long before the
  -- module is loaded.
  local Finale

  -- Save compatibility policy: this namespace is permanent. New builds only
  -- add/normalize fields inside it; they never require a fresh save or rename
  -- the namespace. Unknown fields are deliberately preserved so saves can move
  -- between older/newer demo builds without destructive conversion.
  -- Schema 5 adds the `finale` sub-table used by the LOG 568 bookend. It is
  -- purely additive; a schema-4 save loads with the ending simply unplayed.
  local POKOPIA_SAVE_SCHEMA=5
  local function normalizePokopiaSave(save)
    if type(save)~="table" then return {} end
    if type(save.modData)~="table" then save.modData={} end

    local q=save.modData.pokopia_log568
    if type(q)~="table" then
      q={}
      save.modData.pokopia_log568=q
    end

    local oldSchema=tonumber(q.schemaVersion) or 0
    if type(q.forms)~="table" then q.forms={} end
    if type(q.currentForm)~="string" or q.currentForm=="" then
      q.currentForm="DITTO"
    end

    -- Character-specific relationship/progression state lives under a stable
    -- character key so future Wooper scenes can build on the same first
    -- impression without scattering one-off flags across the root namespace.
    if type(q.characters)~="table" then q.characters={} end
    if type(q.characters.WOOPER)~="table" then q.characters.WOOPER={} end
    local wooper=q.characters.WOOPER
    wooper.streetCred=math.max(0,tonumber(wooper.streetCred) or 0)

    -- LOG 568 bookend state. `prequelComplete` is what arms the ending; it is
    -- reconstructed from the Celadon chapter's own completion flag so saves
    -- made before schema 5 still reach the finale without a replay.
    if type(q.finale)~="table" then q.finale={} end
    local fin=q.finale
    fin.version=math.max(1,tonumber(fin.version) or 1)
    fin.playCount=math.max(0,math.floor(tonumber(fin.playCount) or 0))
    fin.prequelComplete=(fin.prequelComplete or q.cardQuestComplete) and true or false
    fin.logSeen=fin.logSeen and true or false
    fin.completed=fin.completed and true or false
    -- A save written mid-cutscene must never come back still "running".
    fin.running=nil

    -- Celadon cafe delivery job state. Keep this additive and save-compatible.
    if type(q.cafeJobs)~="table" then q.cafeJobs={} end
    local cj=q.cafeJobs
    cj.deliveriesCompleted=math.max(0,tonumber(cj.deliveriesCompleted) or 0)
    cj.deliveriesFailed=math.max(0,tonumber(cj.deliveriesFailed) or 0)
    cj.totalEarned=math.max(0,tonumber(cj.totalEarned) or 0)
    cj.totalPenalties=math.max(0,tonumber(cj.totalPenalties) or 0)
    cj.nextDeliveryId=math.max(1,math.floor(tonumber(cj.nextDeliveryId) or 1))
    if cj.currentOrder~=nil and type(cj.currentOrder)~="table" then cj.currentOrder=nil end

    -- Additive migrations for saves made by any earlier Pokopia build. These
    -- reconstruct dependent state but never clear story progress or inventory.
    if q.distractionDone then
      q.distractionCommitted=true
      q.rattataFollowing=false
    end
    if q.persianLessonDone then
      q.forms.PERSIAN=true
      if type(q.argumentPositions)=="table" then
        q.argumentPositions.locked=true
      end
    end
    if q.electrodeFormLearned then q.forms.ELECTRODE=true end
    local learnedHitmon=nil
    if q.hitmonLearnedChoice=="HITMONLEE"
        or q.hitmonLearnedChoice=="HITMONCHAN" then
      learnedHitmon=q.hitmonLearnedChoice
    elseif q.hitmonWinChoice=="HITMONLEE"
        or q.hitmonWinChoice=="HITMONCHAN" then
      -- v1.0.340 writes this at the instant the spar reaches its win state,
      -- before BattleState teardown.  It doubles as a repair anchor if a
      -- later engine callback is interrupted.
      learnedHitmon=q.hitmonWinChoice
    elseif q.hitmonLearnedForm=="HITMONLEE"
        or q.hitmonLearnedForm=="HITMONCHAN" then
      learnedHitmon=q.hitmonLearnedForm
    elseif q.forms.HITMONLEE and not q.forms.HITMONCHAN then
      learnedHitmon="HITMONLEE"
    elseif q.forms.HITMONCHAN and not q.forms.HITMONLEE then
      learnedHitmon="HITMONCHAN"
    end
    if learnedHitmon then
      q.hitmonLearnedChoice=learnedHitmon
      q.hitmonLearnedForm=learnedHitmon
      q.forms[learnedHitmon]=true
    end
    if q.porygonFormLearned then
      q.forms.PORYGON=true
    elseif q.forms.PORYGON then
      q.porygonFormLearned=true
    end

    -- v1.0.319 consolidates the Celadon card quest around one completion
    -- flag and expansion-specific pack inventory. Old dream/key fields are
    -- read once here only so existing saves keep their progress.
    if not q.cardQuest311Migrated then
      local oldComplete=q.cardQuestComplete
        or q.keyToCityAwarded
        or q.cardPacksGifted
        or q.scalperLineCleared

      q.cardPackInventory=type(q.cardPackInventory)=="table"
        and q.cardPackInventory or {}

      -- Preserve generic packs from older builds instead of deleting them.
      -- Legacy generic packs become COLOSSEUM packs, the first current set.
      local legacyPacks=tonumber(q.cardPacks) or 0
      if legacyPacks>0 then
        q.cardPackInventory.COLOSSEUM=
          (tonumber(q.cardPackInventory.COLOSSEUM) or 0)+legacyPacks
      end

      if oldComplete then q.cardQuestComplete=true end

      q.scalperDreamComplete=nil
      q.dreamWakeStarted=nil
      q.keyCeremonyPending=nil
      q.keyCeremonyStarted=nil
      q.keyToCityAwarded=nil
      q.cardPacksGifted=nil
      q.cardPacks=nil
      q.kidPackSharedRarity=nil
      q.kidPackResults=nil
      q.kidPackOpened=nil
      q.kidIndex304Migrated=nil
      if save.inventory then save.inventory.KEY_TO_CITY=nil end
      q.cardQuest311Migrated=true
    end

    -- Never downgrade a save written by a newer build. Keeping a higher schema
    -- number plus all unknown fields makes round-tripping non-destructive.
    q.schemaVersion=math.max(oldSchema,POKOPIA_SAVE_SCHEMA)
    return q
  end

  -- The Prize Room changes its greeting only after the player has truly
  -- won a spin. SlotMachine sets self.win before startPayout(), so this is the
  -- engine-authored point where a winning spin is known to have happened.
  do
    local SlotMachine=require("src.ui.SlotMachine")
    if not SlotMachine._pokopiaWinTrackingWrapped then
      local originalStartPayout=SlotMachine.startPayout
      function SlotMachine:startPayout(...)
        local q=normalizePokopiaSave(self.game.save)
        if self.win and (self.win.payout or 0)>0 then
          q.slotWinSeen=true
          require("src.core.Sound").play(self.game.data,"Get_Item1")
        end
        return originalStartPayout(self,...)
      end
      SlotMachine._pokopiaWinTrackingWrapped=true
    end
  end

  local function openTransformMenu(game)
    local TrainerCard=require("src.ui.TrainerCard")
    local Font=require("src.render.Font")
    local Assets=require("src.render.Assets")
    local Sprites=require("src.pokemon.Sprites")
    local SpriteRenderer=require("src.render.SpriteRenderer")

    local q=normalizePokopiaSave(game.save)

    -- Keep the real Trainer Card object underneath this screen so its exact
    -- extracted frame tiles / box geometry are reused rather than approximated.
    local card=TrainerCard.new(game,{})
    card.isOpaque=true
    card.transformCursor=0 -- 0 = large battler/DITTO return slot
    card.transformSlots={
      { form="PERSIAN", species="PERSIAN", spriteId=PERSIAN },
      { form="ELECTRODE", species="ELECTRODE", spriteId=ELECTRODE },
      { form="OLD_WOMAN", species=nil, spriteId="SPRITE_SILPH_WORKER_F" },
    }

    -- Before the spar is won, both Hitmon skills are visible as locked choices.
    -- The first successful choice is permanent: once one is learned, the other
    -- disappears from Transformations entirely.
    local learnedHitmon=q.hitmonLearnedChoice or q.hitmonLearnedForm
    if learnedHitmon=="HITMONLEE" or learnedHitmon=="HITMONCHAN" then
      table.insert(card.transformSlots,{
        form=learnedHitmon,species=learnedHitmon,spriteId=learnedHitmon,
      })
    else
      table.insert(card.transformSlots,{
        form="HITMONLEE",species="HITMONLEE",spriteId="HITMONLEE",
      })
      table.insert(card.transformSlots,{
        form="HITMONCHAN",species="HITMONCHAN",spriteId="HITMONCHAN",
      })
    end

    local function imageFromPath(path)
      if not path then return nil end
      local ok,img=pcall(love.graphics.newImage,Assets.resolve(path))
      return ok and img or nil
    end

    -- The preview uses battle fronts, but every form is recolored with the same
    -- three Ditto-purple shades used by the actual overworld transformation.
    local previewCache={}
    local function purpleBattle(species)
      if not species or species=="OLD_WOMAN" or species=="SCALPER" then return nil end
      if previewCache[species] then return previewCache[species] end
      local path=Sprites.path(game.data,species,"front",
        {kind="trainer_card"})
      if not path then return nil end
      local ok,id=pcall(Assets.imageData,path)
      if not ok or not id then return nil end
      id:mapPixel(function(_,_,r,g,b,a)
        if a==0 then return r,g,b,0 end
        if r>0.83 and g>0.83 and b>0.83 then
          return 1,1,1,0
        elseif r>0.50 then
          return 221/255,178/255,242/255,1
        elseif r>0.17 then
          return 167/255,92/255,201/255,1
        else
          return 79/255,38/255,104/255,1
        end
      end)
      local okImg,img=pcall(love.graphics.newImage,id)
      if okImg then
        img:setFilter("nearest","nearest")
        previewCache[species]=img
        return img
      end
    end

    local iconCache={}
    local function overworldIcon(slot)
      if iconCache[slot.form] then return iconCache[slot.form] end
      local def=game.data.sprites[slot.spriteId]
      if not def then return nil end
      local ok,r=pcall(SpriteRenderer.new,def,"transform_menu_"..slot.form)
      if ok then
        iconCache[slot.form]=r
        return r
      end
    end

    local function selectedSlot(self)
      if self.transformCursor==0 then
        return {form="DITTO",species="DITTO",unlocked=true}
      end
      local slot=self.transformSlots[self.transformCursor]
      if not slot then return nil end
      slot.unlocked=q.forms[slot.form] and true or false
      return slot
    end

    local function applySelected(self)
      local slot=selectedSlot(self)
      if not slot or slot.unlocked==false then return end
      local previous=q.currentForm or "DITTO"
      q.requestedForm=slot.form
      local ow=activeOverworld and activeOverworld(game)
      if ow and applyDittoForm then
        local changed=applyDittoForm(game,slot.form,ow)
        if changed and previous~=slot.form then
          -- pokered data/moves/sfx.asm:
          -- TRANSFORM = SFX_FAINT_FALL, pitch $ff, tempo $ff.
          require("src.core.Sound").playMove(game.data,{
            sound="Faint_Fall",pitch=0xff,tempo=0xff
          })
        end
      end
      game.stack:pop()
    end

    function card:update(dt)
      local input=game.input
      local n=#self.transformSlots

      if input:wasPressed("b") then
        game.stack:pop()
        return
      end

      -- The large battle sprite is a real selectable DITTO slot. Down enters
      -- the badge grid; Up from the top row returns to DITTO.
      if input:wasPressed("up") then
        if self.transformCursor>0 and self.transformCursor<=4 then
          self.transformCursor=0
        elseif self.transformCursor>4 then
          self.transformCursor=self.transformCursor-4
        end
      elseif input:wasPressed("down") then
        if self.transformCursor==0 then
          if n>0 then self.transformCursor=1 end
        elseif self.transformCursor<=4 and self.transformCursor+4<=n then
          self.transformCursor=self.transformCursor+4
        end
      elseif input:wasPressed("left") and self.transformCursor>0 then
        local col=(self.transformCursor-1)%4
        if col>0 then self.transformCursor=self.transformCursor-1 end
      elseif input:wasPressed("right") and self.transformCursor>0 then
        local col=(self.transformCursor-1)%4
        if col<3 and self.transformCursor<n then
          self.transformCursor=self.transformCursor+1
        end
      end

      if input:wasPressed("a") then applySelected(self) end
    end

    function card:draw()
      love.graphics.setColor(1,1,1,1)
      love.graphics.rectangle("fill",0,0,160,144)

      local slot=selectedSlot(self)
      local selectedName=(slot and slot.form) or "DITTO"
      local activeForm=q.currentForm or "DITTO"

      -- Exact Trainer Card top box. Money is intentionally replaced by the
      -- transformation currently under the cursor.
      self:frameBox(0,0,20,8)
      love.graphics.setColor(0,0,0,1)
      Font.draw("NAME/DITTO",16,16)
      Font.draw("FORM/"..selectedName,16,32)
      local t=math.floor(game.save.playTime or 0)
      Font.draw(("TIME/%3d:%02d"):format(math.floor(t/3600),
        math.floor(t/60)%60),16,48)

      -- The trainer-card portrait reflects the transformation that is actually
      -- active. Moving the cursor only selects a target; the battler changes
      -- after A successfully applies that form.
      local preview=purpleBattle(activeForm)
      if preview then
        local pw,ph=preview:getDimensions()
        local scale=math.min(48/pw,56/ph)
        local dx=132-(pw*scale)/2
        local dy=32-(ph*scale)/2
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(preview,dx,dy,0,scale,scale)
        local okFX,PaletteFX=pcall(require,"src.render.PaletteFX")
        if okFX and PaletteFX and PaletteFX.markTrueColor then
          PaletteFX.markTrueColor(dx,dy,pw*scale,ph*scale)
        end
        if self.transformCursor==0 then
          love.graphics.setColor(0,0,0,1)
          -- Small right-pointing menu cursor beside the DITTO return slot.
          love.graphics.polygon("fill",
            math.max(2,dx-8),dy+ph*scale/2-4,
            math.max(2,dx-8),dy+ph*scale/2+4,
            math.max(2,dx-3),dy+ph*scale/2)
        end
      end

      -- Same middle banner position as BADGES.
      self:frameBox(0,8,20,3)
      love.graphics.setColor(0,0,0,1)
      Font.draw("TRANSFORMATIONS",24,72)

      -- Same 4x2 badge-grid box and coordinates. Known transformations use
      -- their actual overworld stand-down sprite. Locked known forms are gray.
      self:frameBox(0,11,20,7)
      for i,entry in ipairs(self.transformSlots) do
        local col,row=(i-1)%4,math.floor((i-1)/4)
        local x,y=20+col*32,100+row*24
        local r=overworldIcon(entry)
        if r and r.frames and r.frames[0] then
          if q.forms[entry.form] then
            love.graphics.setColor(1,1,1,1)
          else
            love.graphics.setColor(0.32,0.32,0.32,1)
          end
          local fw=r.frameWidth or 16
          local fh=r.frameHeight or 16
          local sc=math.min(16/fw,16/fh)
          love.graphics.draw(r.image,r.frames[0],
            x+(16-fw*sc)/2,y+(16-fh*sc)/2,0,sc,sc)
        end
        if self.transformCursor==i then
          love.graphics.setColor(0,0,0,1)
          -- Badge-menu style hover cursor: point at the sprite instead of
          -- boxing the whole slot.
          love.graphics.polygon("fill",
            x-7,y+4,
            x-7,y+12,
            x-2,y+8)
        end
      end

      love.graphics.setColor(1,1,1,1)
    end

    game.stack:push(card)
  end

  -- The DITTO row replaces the old trainer-card/badge destination with the
  -- learned-form list. The SAVE panel reports learned transformations instead
  -- of the Pokedex-owned count. Portrait assets are dialogue-only.
  mod.hooks:wrap("ui.start_menu.items",function(next,game,items)
    local out=next(game,items)
    if type(out)~="table" then return out end

    local playerName=game.save.player.name or "DITTO"
    for _,row in ipairs(out) do
      if row.label==playerName then
        row.label="DITTO"
        row.onSelect=function()
          openTransformMenu(game)
        end
        row.keepOpen=false
      elseif tostring(row.label):upper()=="SAVE" then
        row.keepOpen=true
        row.onSelect=function()
          local TextBox=require("src.render.TextBox")
          local Theme=require("src.ui.Theme")
          local Font=require("src.render.Font")
          local badges=require("src.inventory.Badges").count(game.data,game.save)
          local q=game.save.modData and game.save.modData.pokopia_log568 or {}
          local learned=0
          for _,yes in pairs(q.forms or {}) do if yes then learned=learned+1 end end
          local t=math.floor(game.save.playTime or 0)
          local panel

          local function closePanel()
            if game.stack:top()==panel then game.stack:pop() end
          end

          panel={
            holdsUIAnchors=true,delay=0,
            update=function()
              panel.delay=panel.delay+1
              if panel.delay==30 then panel.openPrompt() end
            end,
            draw=function()
              Font.drawBox(4,0,16,10)
              love.graphics.setColor(0,0,0,1)
              Font.draw("PLAYER",5*8,2*8)
              Font.draw("DITTO",10*8,2*8)
              Font.draw("BADGES",5*8,4*8)
              Font.draw(("%2d"):format(badges),17*8,4*8)
              Font.draw("TRANSFORM",5*8,6*8)
              Font.draw(("%2d"):format(learned),17*8,6*8)
              Font.draw("TIME",5*8,8*8)
              Font.draw(("%3d:%02d"):format(math.floor(t/3600),math.floor(t/60)%60),13*8,8*8)

              -- No portrait art here: portrait assets are reserved for dialogue.
              love.graphics.setColor(1,1,1,1)
            end,
          }

          panel.openPrompt=function()
            game.stack:push(TextBox.new(game,"Would you like to\nSAVE the game?",nil,{
              choiceBox=Theme.saveBox,
              choice=function(yes)
                if not yes then closePanel() return end
                game.stack:push(TextBox.new(game,"Now saving...",function()
                  game:writeSave()
                  game.stack:push(TextBox.new(game,"DITTO saved\nthe game!",closePanel,{
                    auto={
                      sound=function() return require("src.core.Sound").play(game.data,"Save") end,
                      delay=30,
                    }
                  }))
                end,{auto={delay=120}}))
              end,
            }))
          end
          game.stack:push(panel)
        end
      end
    end
    return out
  end)

  -- Transformation movement is keyed off the PLAYER'S applied form, not an
  -- Electrode NPC and not a save-side form flag. Player:stepLength() passes
  -- the transformed player itself in ctx.player, so this is authoritative.
  mod.hooks:wrap("movement.speed",function(next,frames,ctx)
    local out=next(frames,ctx)
    local p=ctx and ctx.player

    -- Followers are authored around vanilla walking cadence. While PIXIE or
    -- RATTATA is actively following Ditto, suppress every transformation
    -- speed modifier and use the engine's unmodified movement speed.
    local save=ctx and ctx.save
    local q=save and save.modData and save.modData.pokopia_log568
    if q and (q.pixieFollowing or q.rattataFollowing) then
      if p then p.pokopiaElectrodeAccelSteps=0 end
      return out
    end

    local form=p and p.pokopiaForm or "DITTO"
    if form=="PERSIAN" then
      return math.max(1,math.floor((tonumber(out) or tonumber(frames) or 16)/1.5+0.5))
    end
    if form=="ELECTRODE" then
      -- Momentum belongs to the continuous D-pad hold, not to a particular
      -- direction. Turning while still holding the pad therefore preserves
      -- the accumulated speed; only a full release resets it below.
      local n=math.max(0,tonumber(p.pokopiaElectrodeAccelSteps) or 0)+1
      p.pokopiaElectrodeAccelSteps=n
      if n>=4 then return 4 end
      if n>=2 then return 8 end
      return 10
    end
    return out
  end)

  --------------------------------------------------------------------------
  -- Native title screen player graphic: Scientist instead of Red.
  --------------------------------------------------------------------------
  -- Title music converted directly from the supplied Pokopia theme MIDI.
  -- Source MIDI: 120 BPM, 384 PPQ, three simultaneous pitched voices.
  do
    local ChipAsm=require("src.audio.ChipAsm")
    local titleTheme=ChipAsm.song({
      tempo=120,
      channels={
        {
          program={
            {duty=2},
            {notetype={speed=12,volume=12,fade=3}},
            {label="midi_ch1"},{octave=3},{note="D",len=1},{rest=3},{note="D",len=1},{rest=2},{note="A",len=1},{note="D",len=1},{rest=2},{octave=4},{note="F#",len=1},{octave=2},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=2},{octave=4},{note="A",len=1},{octave=2},{note="G",len=1},{rest=2},{octave=4},{note="B",len=1},{octave=3},{note="D",len=1},{rest=3},{note="D",len=1},{rest=3},{note="D",len=1},{rest=3},{octave=2},{note="E",len=1},{rest=3},{note="E",len=1},{rest=2},{octave=4},{note="F#",len=1},{octave=2},{note="E",len=1},{rest=2},{octave=4},{note="G",len=1},{octave=2},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=2},{octave=3},{note="A",len=1},{octave=2},{note="A#",len=1},{rest=3},{note="A#",len=1},{rest=2},{octave=3},{note="G",len=1},{octave=2},{note="A#",len=1},{rest=1},{octave=4},{note="D",len=1},{note="F",len=1},{octave=3},{note="C",len=1},{rest=3},{note="C",len=1},{rest=3},{note="C",len=1},{rest=3},{note="D",len=1},{rest=3},{note="D",len=1},{rest=2},{note="A",len=1},{note="D",len=1},{rest=2},{octave=4},{note="F#",len=1},{octave=2},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="A#",len=1},{rest=3},{note="A#",len=1},{rest=3},{note="A#",len=1},{rest=3},{note="F#",len=1},{rest=3},{octave=4},{note="A",len=4},{octave=2},{note="B",len=1},{rest=3},{note="E",len=1},{rest=3},{octave=4},{note="E",len=4},{octave=2},{note="A",len=1},{rest=3},{note="D",len=1},{rest=7},{octave=3},{note="A",len=1},{note="B",len=3},{octave=2},{note="D",len=1},{rest=7},{note="A#",len=4},{note="G",len=1},{rest=3},{note="G",len=1},{rest=2},{octave=3},{note="G",len=1},{octave=2},{note="G",len=1},{rest=2},{octave=4},{note="D",len=1},{octave=2},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="F#",len=1},{rest=1},{octave=3},{note="A",len=10},{octave=2},{note="F#",len=1},{rest=1},{octave=4},{note="A",len=16},{note="A",len=1},{octave=3},{note="G",len=1},{octave=2},{note="E",len=1},{rest=1},{octave=4},{note="D",len=1},{note="F#",len=5},{octave=2},{note="A#",len=1},{rest=1},{octave=4},{note="F#",len=1},{note="E",len=1},{octave=2},{note="B",len=1},{rest=3},{note="A",len=1},{rest=1},{octave=4},{note="A",len=9},{octave=3},{note="B",len=1},{octave=2},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="G#",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=2},{octave=4},{note="G",len=1},{octave=3},{note="C",len=1},{rest=3},{note="C",len=1},{rest=2},{octave=5},{note="E",len=1},{octave=3},{note="C",len=1},{rest=2},{octave=5},{note="C#",len=1},{octave=2},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=2},{octave=4},{note="B",len=1},{octave=2},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=2},{octave=4},{note="D",len=1},{octave=2},{note="G",len=1},{rest=2},{octave=4},{note="B",len=1},{octave=2},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A#",len=1},{rest=3},{note="A#",len=1},{rest=2},{octave=5},{note="A#",len=1},{octave=2},{note="A#",len=1},{rest=2},{octave=6},{note="F",len=1},{octave=3},{note="C",len=1},{rest=3},{note="C",len=1},{rest=3},{note="C",len=1},{rest=3},{note="D",len=1},{rest=3},{note="D",len=1},{rest=2},{octave=5},{note="A",len=1},{octave=3},{note="D",len=1},{rest=2},{octave=6},{note="F#",len=1},{octave=2},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=1},{octave=6},{note="G",len=1},{note="F#",len=1},{octave=3},{note="C",len=1},{rest=3},{note="C",len=1},{rest=2},{octave=5},{note="G",len=1},{octave=3},{note="C",len=1},{rest=2},{octave=5},{note="A",len=1},{octave=2},{note="B",len=1},{rest=3},{note="B",len=1},{rest=3},{note="B",len=1},{octave=5},{note="D",len=1},{note="E",len=1},{note="F#",len=1},{octave=2},{note="A#",len=1},{rest=3},{note="A#",len=1},{rest=2},{octave=5},{note="F#",len=1},{octave=2},{note="A#",len=1},{rest=2},{octave=5},{note="G",len=1},{octave=2},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="G",len=1},{rest=1},{octave=5},{note="E",len=6},{octave=2},{note="G",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=2},{octave=5},{note="C#",len=1},{octave=2},{note="G",len=1},{rest=3},{note="G",len=1},{rest=2},{octave=4},{note="A",len=1},{octave=2},{note="G",len=1},{rest=2},{octave=5},{note="D",len=1},{octave=2},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=2},{octave=5},{note="A",len=1},{octave=2},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="A#",len=4},{note="A#",len=4},{note="A#",len=4},{note="A#",len=4},{note="A#",len=4},{note="A#",len=4},{note="B",len=4},{octave=3},{note="C",len=4},{note="C",len=4},{note="C",len=4},{note="C",len=4},{note="C",len=4},{note="C",len=4},{note="C#",len=4},{note="D",len=1},{rest=3},{note="D",len=1},{rest=4},{note="D",len=1},{note="D",len=1},{note="D",len=1},{rest=3},{note="D",len=1},{rest=3},{note="D",len=1},{rest=3},{note="C",len=1},{note="C",len=1},{note="C",len=1},{note="C",len=1},{note="C",len=1},{note="C#",len=1},{note="D",len=11},{loop={count=0,to="midi_ch1"}}
          },
        },
        {
          program={
            {duty=3},
            {notetype={speed=12,volume=11,fade=2}},
            {label="midi_ch2"},{octave=4},{note="F#",len=6},{rest=2},{note="D",len=3},{rest=1},{note="E",len=4},{note="A",len=8},{note="B",len=7},{rest=1},{note="G",len=3},{rest=1},{note="A",len=4},{note="F#",len=8},{note="G",len=7},{rest=1},{note="E",len=3},{rest=1},{note="F#",len=4},{note="D",len=7},{rest=1},{octave=3},{note="A#",len=7},{rest=1},{note="A#",len=2},{rest=2},{octave=4},{note="A",len=4},{note="G",len=4},{note="E",len=4},{note="F#",len=7},{rest=1},{note="D",len=3},{rest=1},{note="E",len=4},{note="A",len=8},{note="B",len=4},{octave=5},{note="C#",len=4},{note="D",len=4},{note="E",len=8},{note="D",len=4},{note="C#",len=4},{rest=4},{octave=4},{note="B",len=4},{note="G",len=4},{rest=4},{note="F#",len=4},{note="D",len=1},{rest=11},{note="D",len=1},{rest=7},{octave=3},{note="A#",len=11},{rest=1},{note="B",len=3},{rest=1},{octave=4},{note="F#",len=4},{note="E",len=4},{note="D",len=4},{note="C#",len=2},{rest=2},{octave=2},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{octave=5},{note="C",len=2},{rest=2},{octave=2},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="E",len=1},{rest=3},{note="E",len=1},{rest=3},{octave=3},{note="B",len=2},{rest=2},{octave=2},{note="A",len=1},{rest=3},{octave=4},{note="E",len=2},{rest=2},{note="D",len=4},{note="C#",len=2},{rest=2},{octave=2},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{octave=4},{note="C",len=4},{note="A",len=4},{note="A#",len=4},{note="B",len=4},{note="B",len=4},{note="B",len=3},{rest=1},{octave=5},{note="D",len=7},{rest=1},{note="D",len=3},{rest=1},{octave=4},{note="A",len=4},{note="A",len=4},{note="A",len=3},{rest=1},{octave=5},{note="C",len=4},{octave=4},{note="B",len=4},{note="A",len=4},{note="G",len=7},{rest=1},{note="G",len=3},{rest=1},{note="A",len=4},{octave=5},{note="D",len=8},{octave=6},{note="D",len=7},{rest=1},{note="D",len=3},{rest=1},{note="E",len=4},{note="A",len=4},{note="G",len=4},{note="F#",len=7},{rest=1},{note="D",len=3},{rest=1},{note="E",len=4},{note="A",len=6},{rest=2},{note="E",len=7},{rest=1},{octave=5},{note="F#",len=3},{rest=1},{note="G",len=4},{note="D",len=5},{rest=3},{note="G",len=7},{rest=1},{note="E",len=3},{rest=1},{note="F#",len=4},{note="D",len=4},{octave=4},{note="A",len=4},{note="B",len=2},{rest=2},{octave=2},{note="G",len=1},{rest=3},{octave=4},{note="B",len=4},{octave=5},{note="D",len=4},{note="C#",len=7},{rest=1},{note="D",len=7},{rest=1},{octave=4},{note="B",len=3},{rest=1},{octave=5},{note="F#",len=4},{note="E",len=4},{note="D",len=4},{note="C#",len=4},{note="E",len=3},{rest=1},{octave=6},{note="C#",len=4},{note="C",len=4},{octave=5},{note="B",len=4},{note="A",len=4},{note="A#",len=4},{note="F",len=16},{note="A#",len=4},{note="B",len=4},{octave=6},{note="C",len=4},{octave=5},{note="G",len=8},{octave=4},{note="G",len=8},{octave=5},{note="C",len=4},{note="C#",len=4},{note="D",len=1},{rest=3},{note="D",len=1},{rest=4},{note="D",len=1},{note="D",len=1},{note="D",len=1},{rest=3},{note="D",len=1},{rest=3},{note="D",len=1},{rest=3},{note="C",len=1},{note="C",len=1},{note="C",len=1},{note="C",len=1},{note="C",len=1},{note="C#",len=1},{note="D",len=11},{loop={count=0,to="midi_ch2"}}
          },
        },
        {
          hw=3,
          program={
            {notetype={speed=12,waveLevel=1,waveInstrument=0}},
            {label="midi_ch3"},{octave=2},{note="D",len=1},{rest=3},{note="D",len=1},{rest=3},{note="D",len=1},{rest=3},{octave=1},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{octave=2},{note="D",len=1},{rest=3},{note="D",len=1},{rest=3},{note="D",len=1},{rest=3},{octave=1},{note="E",len=1},{rest=3},{note="E",len=1},{rest=3},{note="E",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="A#",len=1},{rest=3},{note="A#",len=1},{rest=3},{note="A#",len=1},{rest=3},{octave=2},{note="C",len=1},{rest=3},{note="C",len=1},{rest=3},{note="C",len=1},{rest=3},{note="D",len=1},{rest=3},{note="D",len=1},{rest=3},{note="D",len=1},{rest=3},{octave=1},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="A#",len=1},{rest=3},{note="A#",len=1},{rest=3},{note="A#",len=1},{rest=3},{note="F#",len=1},{rest=7},{note="B",len=1},{rest=3},{note="E",len=1},{rest=7},{note="A",len=1},{rest=3},{note="D",len=1},{rest=11},{note="D",len=1},{rest=7},{note="A#",len=4},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="E",len=1},{rest=3},{note="E",len=1},{rest=3},{note="E",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A#",len=1},{rest=3},{note="B",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="G#",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{octave=2},{note="C",len=1},{rest=3},{note="C",len=1},{rest=3},{note="C",len=1},{rest=3},{octave=1},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A#",len=1},{rest=3},{note="A#",len=1},{rest=3},{note="A#",len=1},{rest=3},{octave=2},{note="C",len=1},{rest=3},{note="C",len=1},{rest=3},{note="C",len=1},{rest=3},{note="D",len=1},{rest=3},{note="D",len=1},{rest=3},{note="D",len=1},{rest=3},{octave=1},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{octave=2},{note="C",len=1},{rest=3},{note="C",len=1},{rest=3},{note="C",len=1},{rest=3},{octave=1},{note="B",len=1},{rest=3},{note="B",len=1},{rest=3},{note="B",len=1},{rest=3},{note="A#",len=1},{rest=3},{note="A#",len=1},{rest=3},{note="A#",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="A",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="G",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="F#",len=1},{rest=3},{note="A#",len=4},{note="A#",len=4},{note="A#",len=4},{note="A#",len=4},{note="A#",len=4},{note="A#",len=4},{note="B",len=4},{octave=2},{note="C",len=4},{note="C",len=4},{note="C",len=4},{note="C",len=4},{note="C",len=4},{note="C",len=4},{note="C#",len=4},{note="D",len=1},{rest=3},{note="D",len=1},{rest=4},{note="D",len=1},{note="D",len=1},{note="D",len=1},{rest=3},{note="D",len=1},{rest=3},{note="D",len=1},{rest=3},{note="C",len=1},{note="C",len=1},{note="C",len=1},{note="C",len=1},{note="C",len=1},{note="C#",len=1},{note="D",len=11},{loop={count=0,to="midi_ch3"}}
          },
        },
      },
    })
    mod.content.music:register("Music_PokopiaTitleMashup",titleTheme)

    -- Pokemon TCG GBC normal/main duel theme. v1.0.340 generates this module
    -- from the original DuelTheme1 score using the source engine's exact
    -- speed*length VBlank timing, and packages both source and converter.
    local duelMusicPath=tostring(mod.path).."/assets/tcg/audio/dueltheme1.lua"
    local duelChunk,duelErr=loadfile(duelMusicPath)
    if not duelChunk and love and love.filesystem and love.filesystem.load then
      duelChunk,duelErr=love.filesystem.load(duelMusicPath)
    end
    if not duelChunk then error("Could not load packaged TCG duel theme: "..tostring(duelErr),0) end
    local duelOK,duelTheme=pcall(duelChunk)
    if not duelOK then error("Could not assemble packaged TCG duel theme: "..tostring(duelTheme),0) end
    mod.content.music:register("Music_TCGDuelTheme1",duelTheme)
  end

  mod.content.screens:override("TitleState",{
    new=function(game,opts)
      local TitleState=require("src.ui.TitleState")
      local Music=require("src.core.Music")
      local state=TitleState.new(game,opts)

      -- Do not start the custom song here. TitleState is constructed during
      -- the intro transition, so constructor-time playback replaces the intro
      -- music too early. Start it on the first actual logo/title draw instead.
      local pokopiaTitleMusicStarted=false

      -- The title uses one battler sprite only: DITTO. Native TitleState
      -- still loads the battler image for us, but its own Pokemon draw is
      -- suppressed below and replaced by the custom moving actor.
      state.cycleSpecies={"DITTO"}
      state.cycleIndex=1
      state.sprites={}

      -- Keep engine-owned TitleState assets intact. Native title branding is
      -- suppressed only inside this state's temporary draw wrappers so no
      -- shared sprite/image state can leak into overworld NPC rendering.

      -- Remove Red's multipart throwing sprite/ball animation.
      state.player=nil
      state.playerQuads=nil
      state.ballQuad=nil

      -- Scientist portrait removed from custom title.

      -- User-supplied title assets.
      local pokopiaLogo=nil
      local pokopiaBackground=nil
      local pokopiaClouds=nil
      local pokopiaGrassTile=nil
      local conservationProjectLogo=nil
      local pokopiaCloudX=0
      local pokopiaCloudLastTime=(love.timer and love.timer.getTime()) or 0
      local pokopiaDittoLastTime=(love.timer and love.timer.getTime()) or 0

      -- Animated title DITTO state. Paths are intentionally independent of
      -- TitleState's species-cycling timer so DITTO never flashes/replaces.
      state.pokopiaDittoPath=0
      state.pokopiaDittoPathTime=0
      state.pokopiaDittoWait=0
      state.pokopiaDittoElapsed=0
      local dittoSeeded=false
      local dittoShader=nil
      local dittoBattlerImage=nil

      do
        local Sprites=require("src.pokemon.Sprites")
        local Assets=require("src.render.Assets")
        local okPath,dittoPath=pcall(function()
          local path=Sprites.path(game.data,"DITTO","front",{kind="title"})
          return path
        end)
        if okPath and dittoPath then
          local resolved=Assets.resolve(dittoPath)
          local okImg,img=pcall(love.graphics.newImage,resolved)
          if okImg then
            img:setFilter("nearest","nearest")
            dittoBattlerImage=img
          end
        end
      end

      local function chooseDittoPath()
        local previous=state.pokopiaDittoPath
        local nextPath=love.math.random(1,6)
        if nextPath==previous then nextPath=(nextPath%6)+1 end
        state.pokopiaDittoPath=nextPath
        state.pokopiaDittoPathTime=0
        state.pokopiaDittoWait=0.25+love.math.random()*0.45
      end

      local function dittoPose(t,path)
        -- x/y are the battler's feet position. Every routine stays below the
        -- title/subtitle area, but each has an obviously different silhouette.
        if path==1 then
          -- Straight left -> right stroll.
          local d=6.5
          local u=math.min(1,t/d)
          return -30+220*u,126,1,t>=d,0
        elseif path==2 then
          -- Right -> left with three pronounced bouncy hops.
          local d=7.0
          local u=math.min(1,t/d)
          local hop=math.max(0,math.sin(u*math.pi*6))
          return 190-220*u,126-hop*13,-1,t>=d,hop
        elseif path==3 then
          -- Enter, stop in the middle, wobble/inspect, then dash away.
          if t<2.4 then
            local u=t/2.4
            return -30+108*u,126,1,false,0
          elseif t<4.5 then
            local q=t-2.4
            return 78+math.sin(q*7)*7,124-math.abs(math.sin(q*5))*3,
              (math.cos(q*7)>=0) and 1 or -1,false,0.5
          else
            local u=math.min(1,(t-4.5)/2.5)
            return 78+112*u,126,1,u>=1,0
          end
        elseif path==4 then
          -- Big rolling wave across the lower band.
          local d=8.0
          local u=math.min(1,t/d)
          local wave=(1-math.cos(u*math.pi*6))*0.5
          return -30+220*u,126-wave*18,1,t>=d,wave
        elseif path==5 then
          -- Run in, retreat almost to the edge, then sprint across.
          if t<2.0 then
            local u=t/2.0
            return -30+100*u,126,1,false,0
          elseif t<3.5 then
            local u=(t-2.0)/1.5
            return 70-65*u,126,-1,false,0
          else
            local u=math.min(1,(t-3.5)/3.2)
            return 5+185*u,126,1,u>=1,0
          end
        else
          -- Playful "puddle": cross halfway, flatten dramatically, spring
          -- upward, then continue off screen.
          if t<2.8 then
            local u=t/2.8
            return -30+108*u,126,1,false,0
          elseif t<4.0 then
            return 78,126,1,false,-1
          elseif t<4.8 then
            local u=(t-4.0)/0.8
            return 78,126-math.sin(u*math.pi)*19,1,false,1
          else
            local u=math.min(1,(t-4.8)/3.0)
            return 78+112*u,126,1,u>=1,0
          end
        end
      end

      do
        local okLogo,logo=pcall(love.graphics.newImage,
          "mods/pokopia_log568_demo/assets/pokopia_logo_truecolor.png")
        if okLogo then pokopiaLogo=logo end

        local okBg,bg=pcall(love.graphics.newImage,
          "mods/pokopia_log568_demo/assets/pokopia_title_bg.png")
        if okBg then pokopiaBackground=bg end

        local okClouds,clouds=pcall(love.graphics.newImage,
          "mods/pokopia_log568_demo/assets/pokopia_title_clouds.png")
        if okClouds then
          clouds:setFilter("nearest","nearest")
          pokopiaClouds=clouds
        end

        local okConservation,conservation=pcall(love.graphics.newImage,
          "mods/pokopia_log568_demo/assets/conservation_project.png")
        if okConservation then
          conservation:setFilter("nearest","nearest")
          conservationProjectLogo=conservation
        end

        local okGrass,grass=pcall(love.graphics.newImage,
          "mods/pokopia_log568_demo/assets/title_grass_tile.png")
        if okGrass then
          grass:setFilter("nearest","nearest")
          grass:setWrap("repeat","repeat")
          pokopiaGrassTile=grass
        end

        -- Map the monochrome battler sprite through the same purple ramp used
        -- by transformed DITTO forms. Alpha remains untouched.
        local okShader,shader=pcall(love.graphics.newShader,[[
          vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
            vec4 p = Texel(tex, uv);
            if (p.a <= 0.001) return vec4(0.0);
            float l = dot(p.rgb, vec3(0.299,0.587,0.114));
            vec3 c;
            if (l > 0.83) c = vec3(0.9608,0.8824,1.0000);
            else if (l > 0.50) c = vec3(0.8667,0.6980,0.9490);
            else if (l > 0.17) c = vec3(0.6549,0.3608,0.7882);
            else c = vec3(0.3098,0.1490,0.4078);
            return vec4(c,p.a) * color;
          }
        ]])
        if okShader then dittoShader=shader end

        if not dittoSeeded then
          love.math.setRandomSeed(os.time())
          dittoSeeded=true
          chooseDittoPath()
        end
      end

      local Font=require("src.render.Font")

      -- User-supplied Conservation Project artwork. Dark pixels were removed
      -- from the source image at packaging time, leaving only its pink/white art.

      -- Leave the engine's TitleState.update signature untouched.
      -- DITTO uses a real-time clock in draw, just like the working cloud
      -- layer, because TitleState.update does not receive a numeric dt here.
      local nativeDraw=state.draw
      state.draw=function(self)
        -- This draw function is the actual logo/title screen. Start the
        -- Bicycle-melody/Credits-accompaniment cue only once we reach it.
        if not pokopiaTitleMusicStarted then
          pokopiaTitleMusicStarted=true
          Music.play(game.data,"Music_PokopiaTitleMashup",true,{reason="title"})
        end

        -- Replace the native white title canvas with the supplied green
        -- Pokopia pattern. Fill the entire 160x144 logical screen.
        if pokopiaBackground then
          local bw,bh=pokopiaBackground:getDimensions()
          love.graphics.setColor(1,1,1,1)
          love.graphics.draw(pokopiaBackground,0,0,0,160/bw,144/bh)
          require("src.render.PaletteFX").markTrueColor(0,0,160,144)
        end

        -- Temporarily scale only the title Pokemon draw path to 50%.
        -- The native TitleState stores the current Pokemon image in
        -- currentSprite(); wrap love.graphics.draw only while nativeDraw
        -- renders that specific image.
        local monEntry=self.currentSprite and self:currentSprite()
        local monImage=monEntry and monEntry.image

        local realDraw=love.graphics.draw
        local realClear=love.graphics.clear
        local realRectangle=love.graphics.rectangle
        local realPrint=love.graphics.print

        -- Prevent native TitleState from replacing our background with its
        -- usual white clear/full-screen white fill.
        love.graphics.clear=function(...) end
        love.graphics.rectangle=function(mode,x,y,w,h,...)
          if mode=="fill" and x==0 and y==0 and w>=160 and h>=144 then
            return
          end
          return realRectangle(mode,x,y,w,h,...)
        end

        -- Suppress the native version string at its source instead of drawing
        -- our subtitle over it. Everything else printed by TitleState remains.
        love.graphics.print=function(text,...)
          local args={...}
          local y=args[2] or 0
          local t=tostring(text or "")
          local upper=t:upper()

          -- The custom title owns the entire upper title area. Suppress every
          -- native text draw there so fragments of BLUE/version/copyright
          -- cannot leak through behind our replacement.
          if y<80
            or upper:match("^V?%d+%.%d+")
            or upper:find("VERSION",1,true)
            or upper=="BLUE"
            or upper=="POKEMON"
            or upper:find("UNDERDECODED",1,true)
            or upper:find("DECODEDHD",1,true)
            or upper:find("2026",1,true)
          then
            return
          end
          return realPrint(text,...)
        end

        -- Suppress the native Pokemon title logo artwork completely.
        -- TitleState draws several images; keep the animated Pokemon image
        -- (at half size) but reject large images occupying the upper title
        -- region, which are the stock POKEMON logo / BLUE version artwork.
        love.graphics.draw=function(image,...)
          local args={...}
          local x=args[1] or 0
          local y=args[2] or 0

          if image==monImage then
            -- Custom DITTO actor is drawn after nativeDraw instead.
            return
          end

          local okDim,iw,ih=pcall(function()
            return image:getDimensions()
          end)
          if okDim and y<80 and iw>=48 and ih>=8 then
            return
          end

          return realDraw(image,...)
        end

        local ok,err=pcall(nativeDraw,self)
        love.graphics.draw=realDraw
        love.graphics.clear=realClear
        love.graphics.rectangle=realRectangle
        love.graphics.print=realPrint
        if not ok then error(err,0) end

        -- Repaint the custom title area from the palette-aware background
        -- after nativeDraw. This guarantees no stock title fragments remain.
        if pokopiaBackground then
          local bw,bh=pokopiaBackground:getDimensions()
          love.graphics.setColor(1,1,1,1)
          love.graphics.draw(pokopiaBackground,0,0,0,160/bw,80/bh)
          require("src.render.PaletteFX").markTrueColor(0,0,160,80)
        end

        -- Fit the supplied grass texture to the title width without
        -- distorting its aspect ratio. Only the lower title band is visible;
        -- the excess height is cropped rather than vertically squashed.
        if pokopiaGrassTile then
          local grassTop=80
          local tw,th=pokopiaGrassTile:getDimensions()
          local grassHeight=144-grassTop
          local grassScale=160/tw
          love.graphics.setColor(1,1,1,1)
          love.graphics.setScissor(0,grassTop,160,grassHeight)
          love.graphics.draw(pokopiaGrassTile,0,grassTop,0,grassScale,grassScale)
          love.graphics.setScissor()
          local okFX,PaletteFX=pcall(require,"src.render.PaletteFX")
          if okFX and PaletteFX and type(PaletteFX.markTrueColor)=="function" then
            PaletteFX.markTrueColor(0,grassTop,160,grassHeight)
          end
        end

        -- Slow looping cloud layer: sky -> clouds -> Pokopia logo.
        if pokopiaClouds then
          local cw,ch=pokopiaClouds:getDimensions()
          local scale=160/cw
          local dw=cw*scale
          local dh=ch*scale

          -- Time-based motion keeps the drift smooth across variable FPS.
          local now=(love.timer and love.timer.getTime()) or pokopiaCloudLastTime
          local dt=now-pokopiaCloudLastTime
          if dt<0 then dt=0 end
          if dt>0.05 then dt=0.05 end
          pokopiaCloudLastTime=now
          local speed=3.0
          pokopiaCloudX=pokopiaCloudX-speed*dt
          while pokopiaCloudX<=-dw do
            pokopiaCloudX=pokopiaCloudX+dw
          end

          love.graphics.setColor(1,1,1,1)
          love.graphics.draw(pokopiaClouds,pokopiaCloudX,0,0,scale,scale)
          love.graphics.draw(pokopiaClouds,pokopiaCloudX+dw,0,0,scale,scale)
          require("src.render.PaletteFX").markTrueColor(0,0,160,math.min(144,dh))
        end

        -- Animated DITTO battler. It stays entirely in the lower band
        -- (roughly y=88..130), so it never passes behind the logo/subtitle.
        if dittoBattlerImage then
          -- Real elapsed time: this is independent of the engine update
          -- callback signature and cannot be frozen by nonnumeric input args.
          local dittoNow=(love.timer and love.timer.getTime()) or pokopiaDittoLastTime
          local dittoDt=dittoNow-pokopiaDittoLastTime
          if dittoDt<0 then dittoDt=0 end
          if dittoDt>0.05 then dittoDt=0.05 end
          pokopiaDittoLastTime=dittoNow

          if (self.pokopiaDittoWait or 0)>0 then
            self.pokopiaDittoWait=math.max(0,self.pokopiaDittoWait-dittoDt)
          else
            self.pokopiaDittoPathTime=(self.pokopiaDittoPathTime or 0)+dittoDt
            local _,_,_,done=dittoPose(
              self.pokopiaDittoPathTime,self.pokopiaDittoPath
            )
            if done then chooseDittoPath() end
          end

          local pathTime=self.pokopiaDittoPathTime or 0
          local path=self.pokopiaDittoPath or 1
          if path==0 then
            chooseDittoPath()
            path=self.pokopiaDittoPath
            pathTime=self.pokopiaDittoPathTime
          end
          local x,baseY,facing,_,pathEnergy=dittoPose(pathTime,path)

          local iw,ih=dittoBattlerImage:getDimensions()
          local idle=pathTime
          local bounce=math.sin(idle*8.5)
          local squash=math.sin(idle*8.5+math.pi/2)
          pathEnergy=pathEnergy or 0

          -- Deliberately visible organic deformation. Normal walking breathes
          -- by roughly 12%; hop paths compress on landing; the puddle path
          -- briefly spreads very wide before springing back up.
          local baseScale=1.16
          local stretchX=1+0.12*squash
          local stretchY=1-0.14*squash
          if pathEnergy<0 then
            stretchX=1.48
            stretchY=0.58
          elseif pathEnergy>0.75 then
            stretchX=0.82
            stretchY=1.30
          elseif pathEnergy>0 then
            stretchX=stretchX+0.10*pathEnergy
            stretchY=stretchY-0.12*pathEnergy
          end
          local sx=baseScale*stretchX*facing
          local sy=baseScale*stretchY
          local y=baseY-3.0*math.abs(bounce)

          love.graphics.setColor(1,1,1,1)
          local previousShader=love.graphics.getShader()
          if dittoShader then love.graphics.setShader(dittoShader) end
          love.graphics.draw(
            dittoBattlerImage,
            x,y,
            0,
            sx,sy,
            iw/2,ih
          )
          love.graphics.setShader(previousShader)

          -- Keep DITTO's custom purple pixels out of emulator palette remap.
          local okFX,PaletteFX=pcall(require,"src.render.PaletteFX")
          if okFX and PaletteFX and type(PaletteFX.markTrueColor)=="function" then
            local sw=iw*baseScale*1.12
            local sh=ih*baseScale*1.15
            PaletteFX.markTrueColor(
              math.floor(x-sw/2),
              math.floor(y-sh),
              math.ceil(sw),
              math.ceil(sh)
            )
          end
        end

        -- Pokopia logo.
        if pokopiaLogo then
          local lw,lh=pokopiaLogo:getDimensions()
          local maxW,maxH=140,43
          local scale=math.min(maxW/lw,maxH/lh)
          local dw=lw*scale
          love.graphics.setColor(1,1,1,1)
          local logoX=(160-dw)/2
          local logoY=4
          love.graphics.draw(pokopiaLogo,logoX,logoY,0,scale,scale)

          -- This is the original full-color Pokopia artwork. Keep the
          -- logo rectangle out of the emulator's palette remap.
          local okPaletteFX,PaletteFX=pcall(require,"src.render.PaletteFX")
          if okPaletteFX and PaletteFX and type(PaletteFX.markTrueColor)=="function" then
            PaletteFX.markTrueColor(
              math.floor(logoX),
              math.floor(logoY),
              math.ceil(dw),
              math.ceil(lh*scale)
            )
          end

          -- User-supplied Conservation Project lockup. Black canvas pixels are
          -- transparent; preserve the supplied green/pink/white artwork in true color.
          if conservationProjectLogo then
            local cw,ch=conservationProjectLogo:getWidth(),conservationProjectLogo:getHeight()
            local targetW=87
            local cscale=targetW/cw
            local cdh=ch*cscale
            local cx=(160-targetW)/2
            local cy=44
            love.graphics.setColor(1,1,1,1)
            love.graphics.draw(conservationProjectLogo,cx,cy,0,cscale,cscale)
            if okPaletteFX and PaletteFX and type(PaletteFX.markTrueColor)=="function" then
              PaletteFX.markTrueColor(math.floor(cx),math.floor(cy),math.ceil(targetW),math.ceil(cdh))
            end
          end

          -- Native copyright / Game Freak art is disabled above; this is the
          -- only footer rendered.
          love.graphics.setColor(0,0,0,1)
          Font.draw("2026 Logie",4,136)
          love.graphics.setColor(1,1,1,1)
        end

      end

      return state
    end,
  })

  --------------------------------------------------------------------------
  -- Battle-off mode.
  --------------------------------------------------------------------------
  mod.hooks:wrap("trainer.before_battle",function(next,game,context,continue)
    continue({cancel=true})
    return true
  end)

  --------------------------------------------------------------------------
  -- Mansion emergency behavior on every floor.
  --------------------------------------------------------------------------
  local COMMON={
    TEXT_MAGNEMITE={{"face_player"},{"play_cry","MAGNEMITE"},{"show_text","MAGNEMITE works at a\nsparking cable.\fIt keeps reconnecting\nit, no matter what."}},
    TEXT_MAGNETON={{"face_player"},{"play_cry","MAGNETON"},{"show_text",
      "MAGNETON powers several\nmachines at once.\f"
      .."It doesn't seem to\nnotice the chaos."}},
    TEXT_VOLTORB={{"face_player"},{"play_cry","VOLTORB"},{"show_text","VOLTORB races up and\ndown the hall.\fIt seems to think the\nalarm is cheering it on."}},
    TEXT_ELECTRODE={{"face_player"},{"play_cry","ELECTRODE"},{"show_text","ELECTRODE races through\nthe hall, grinning.\fEvery loud crash makes\nit bounce higher.\fIt seems delighted."}},
    TEXT_KOFFING={{"face_player"},{"play_cry","KOFFING"},{"show_text","KOFFING flinches at\nevery shout.\fIt ducks behind a pipe...\fThen peeks out again."}},
    TEXT_WEEZING={{"face_player"},{"play_cry","WEEZING"},{"show_text","WEEZING guides smaller\nPOKeMON away from smoke.\fIt keeps looking back\nto make sure they follow."}},
    TEXT_GRIMER={{"face_player"},{"play_cry","GRIMER"},{"show_text","GRIMER slurps up a\nchemical spill.\fFor once, nobody seems\nupset to see it."}},
    TEXT_MUK={{"face_player"},{"play_cry","MUK"},{"show_text","MUK presses itself against\na leaking pipe.\fThe dripping stops.\fMUK looks extremely proud."}},
    TEXT_PICHU={{"face_player"},{"play_cry","PIKACHU"},{"show_text","PICHU: Pii! Pichu!"}},
    TEXT_TOGEPI={{"face_player"},{"play_cry","CLEFAIRY"},{"show_text","TOGEPI: Toge-prii!"}},
    TEXT_POLIWHIRL={{"face_player"},{"play_cry","POLIWHIRL"},{"show_text","POLIWHIRL sways in place,\nkeeping time with the alarm.\fIt seems oddly relaxed."}},
    TEXT_SLOWPOKE={{"face_player"},{"play_cry","SLOWPOKE"},{"show_text","SLOWPOKE stares at the\nCHEESE for a long time.\f...It may have just noticed it."}},
    TEXT_DODRIO={{"face_player"},{"play_cry","DODRIO"},{"show_text","DODRIO argues with itself.\fTwo heads want to run.\fThe third refuses to move."}},
    TEXT_TOTODILE={{"face_player"},{"play_cry","SQUIRTLE"},{"show_text","TOTODILE stomps out a\nsmall flame with its foot.\fThen it grins like it\nplanned that all along."}},
    TEXT_SPINARAK={{"face_player"},{"play_cry","WEEDLE"},{"show_text","SPINARAK makes tiny patrols\naround its web.\fIt never strays far from\nits corner."}},
    TEXT_AMPHAROS={{"face_player"},{"play_cry","PIKACHU"},{"show_text","AMPHAROS faces the sea.\fIts tail flashes slowly\nthrough the smoke.\fFar-off boats can use\nit as a beacon."}},
    TEXT_LARVITAR={{"face_player"},{"play_cry","CUBONE"},{"show_text","LARVITAR stands watch in\nthe lobby.\fIt keeps nudging loose\nrubble away from the path."}},
    TEXT_PORYGON={{"face_player"},{"play_cry","PORYGON"},{"show_text","PORYGON studies a dead\ncomputer terminal.\fIt taps the keys with\nperfect, steady timing."}},
    TEXT_VULPIX={{"face_player"},{"play_cry","VULPIX"},{"show_text","VULPIX is trembling.\fIts ears twitch at\nevery alarm.\fIt keeps staring at\nthe stairwell."}},
    TEXT_RATTATA={{"face_player"},{"play_cry","RATTATA"},{"show_text","RATTATA darts through\nthe fallen papers.\fIt found a packet of\ncrackers.\fIt looks very pleased."}},
    TEXT_CHARMANDER={{"face_player"},{"play_cry","CHARMANDER"},{"show_text","CHARMANDER stands beside\na dead machine.\fIts tail flame keeps a\ntiny pilot light alive."}},
    TEXT_BULBASAUR={{"face_player"},{"play_cry","BULBASAUR"},{"show_text","BULBASAUR sits quietly\nby the wall.\fIts bulb opens a little.\fThe POKeMON nearby seem\ncalmer around it."}},
  }

  local FLOOR_TALK={
    POKEMON_MANSION_1F={
      TEXT_EXIT_A={{"show_text",
        "SCIENTIST: We can't open\nthose doors!\f"
        .."You saw the readings!\f"
        .."Nobody goes outside!\f"
        .."SCIENTIST: Then help me\nkeep this entrance clear!"}},
      TEXT_EXIT_B={{"show_text",
        "SCIENTIST: And staying\nin here is better?!\f"
        .."This whole place is\ncoming apart!\f"
        .."SCIENTIST: Fine!\f"
        .."But if it gets worse,\nwe're leaving!"}},
      TEXT_1S1={{"face_player"},{"show_text","SCIENTIST: The south\nstairs are clear!\fKeep moving!\fDon't stop!"}},
      TEXT_1S2={{"face_player"},{"show_text","SCIENTIST: Half the\ninstruments are dead!\fIf it still gives a\nreading, write it down!"}},
      TEXT_1S3={{"face_player"},{"show_text",
        "SCIENTIST: Sir...\f"
        .."The POKeMON\nCONSERVATION PROJECT\f"
        .."is ready.\f"
        .."POKeMON that cannot\ncome with us\f"
        .."will be preserved\nin the PC system.\f"
        .."They'll remain there\nwhile Earth recovers.\f"
        .."Mankind will leave\nthe planet...\f"
        .."and establish itself\nin space.\f"
        .."When Earth can sustain\nPOKeMON again,\f"
        .."the system will release\nthem into safe habitats.\f"
        .."God help us all..."}},
      TEXT_GIOVANNI={{"face_player"},{"show_text",
        "SCIENTIST: Sir...\f"
        .."The POKeMON\nCONSERVATION PROJECT\f"
        .."is ready.\f"
        .."POKeMON that cannot\ncome with us\f"
        .."will be preserved\nin the PC system.\f"
        .."They'll remain there\nwhile Earth recovers.\f"
        .."Mankind will leave\nthe planet...\f"
        .."and establish itself\nin space.\f"
        .."When Earth can sustain\nPOKeMON again,\f"
        .."the system will release\nthem into safe habitats.\f"
        .."God help us all..."}},
      TEXT_PERSIAN={{"face_player"},{"play_cry","PERSIAN"},{"show_text",
        "PERSIAN: You shouldn't\nbe back here."}},
      TEXT_ROCKET_GUARD={{"face_player"},{"show_text",
        "ROCKET: Woah,\nlittle fella!\f"
        .."You don't have\nclearance to come\nin here.\f"
        .."Don't worry.\f"
        .."I know the sounds\nare scary...\f"
        .."But it'll be okay.\f"
        .."The boss is making\nsure of it!"}},
    },
    POKEMON_MANSION_2F={
      TEXT_2S1={{"face_player"},{"show_text","SCIENTIST: I can't reach\nanyone off the island!\fEvery channel is\nnothing but noise!"}},
      TEXT_2S2={{"face_player"},{"show_text","SCIENTIST: Backup power\nkeeps dropping!\fIf the lights go out,\nstay by the walls!"}},
    },
    POKEMON_MANSION_3F={
      TEXT_3S1={{"face_player"},{"show_text","SCIENTIST: No...\nNo, no, no!\fThe readings are still\nclimbing!\fWhy won't they stop?!"}},
      TEXT_3S2={{"face_player"},{"show_text","SCIENTIST: The island\nsensors are gone!\fEvery reading is off\nthe scale!\fWe have to evacuate!\fBut... where can we go?!"}},
      TEXT_3S3={{"face_player"},{"show_text","SCIENTIST: Don't touch\nanything!\f...No. Forget it.\fWeeks...\fHe said we had WEEKS..."}},
    },
    POKEMON_MANSION_B1F={
      TEXT_PC_END={{"show_text","LOGAN: Please!\fFind PIXIE for me!"}},
      TEXT_BS1={{"face_player"},{"show_text","SCIENTIST: The storage\nsystem still has power!\fSave every record you\ncan before it fails!"}},
      TEXT_BS2={{"face_player"},{"show_text","SCIENTIST: I called the\nmainland.\fStatic.\fI tried again...\fNothing."}},
    },
  }

  local function pokopiaData(game)
    -- Everything that changes the demo's story lives in save.modData so the
    -- normal Gen1Recomp save serializer writes it with the playthrough.
    return normalizePokopiaSave(game.save)
  end


  local function restorePlayerInput(game,ow)
    if ow and ow.player then
      ow.player.inputLocked=false
      ow.player.frozen=false
      ow.player.targetX=nil
      ow.player.targetY=nil
      ow.player.moving=false
      ow.player.progress=0
    end
    if ow then
      ow.emote=nil
    end

    -- Use only Gen1Recomp core input services. TouchControls:reset() releases
    -- any overlay-held buttons whose touch-release event was lost while a
    -- cutscene owned input. Input:reset() clears held sources, and reconcile()
    -- restores physical keyboard/gamepad holds from hardware state.
    if game and game.touchControls and game.touchControls.reset then
      pcall(game.touchControls.reset,game.touchControls)
    end
    if game and game.input and game.input.reset then
      pcall(game.input.reset,game.input)
      if game.input.reconcile then
        pcall(game.input.reconcile,game.input)
      end
    end
  end

  activeOverworld=function(game)
    local stack=game and game.stack
    local states=stack and stack.states
    if type(states)=="table" then
      for i=#states,1,-1 do
        local st=states[i]
        if st and st.map and st.player and st.npcs then
          return st
        end
      end
    end
    local ow=game and game.overworld
    if ow and ow.map and ow.player then return ow end
    return nil
  end

  local function unlockedForms(game)
    local q=pokopiaData(game)
    q.forms=q.forms or {}
    return q.forms
  end

  local function transformedSpriteDef(game,spriteId)
    local src=game.data.sprites[spriteId]
    if not src then return nil end
    local def={}
    for k,v in pairs(src) do def[k]=v end

    -- Forms use the source Pokemon geometry with a manually baked
    -- Ditto-purple image.
    def.trueColor=true
    def.id="POKOPIA_FORM_"..tostring(spriteId)
    return def
  end

  local function exteriorMask(id)
    local w,h=id:getDimensions()
    local seen={}
    local queue={}
    local head=1
    local function key(x,y) return y*w+x+1 end
    local function isBg(x,y)
      local r,g,b,a=id:getPixel(x,y)
      return a==0 or (r>0.83 and g>0.83 and b>0.83)
    end
    local function add(x,y)
      if x<0 or y<0 or x>=w or y>=h then return end
      local k=key(x,y)
      if seen[k] or not isBg(x,y) then return end
      seen[k]=true
      queue[#queue+1]={x,y}
    end
    for x=0,w-1 do add(x,0); add(x,h-1) end
    for y=0,h-1 do add(0,y); add(w-1,y) end
    while head<=#queue do
      local q=queue[head]; head=head+1
      local x,y=q[1],q[2]
      add(x-1,y); add(x+1,y); add(x,y-1); add(x,y+1)
    end
    return seen,w
  end

  local function bakeDittoPurpleImage(path)
    if not (love and love.image and love.image.newImageData
        and love.graphics and love.graphics.newImage) then
      return nil
    end

    local Assets=require("src.render.Assets")
    local ok,id=pcall(Assets.imageData,path)
    if not ok or not id then return nil end

    local exterior,w=exteriorMask(id)
    id:mapPixel(function(x,y,r,g,b,a)
      -- Only edge-connected sheet background is transparent. White/light
      -- details enclosed by the Pokemon outline remain fully opaque.
      if exterior[y*w+x+1] then return 1,1,1,0 end
      if a==0 then return r,g,b,0 end
      if r>0.83 and g>0.83 and b>0.83 then
        return 221/255,178/255,242/255,1
      elseif r>0.50 then
        return 221/255,178/255,242/255,1
      elseif r>0.17 then
        return 167/255,92/255,201/255,1
      else
        return 79/255,38/255,104/255,1
      end
    end)

    local okImg,img=pcall(love.graphics.newImage,id)
    if okImg then return img end
    return nil
  end

  -- Build a derived four-shade follower sheet that preserves the dependency's
  -- art but fixes its transparency key. Only the background connected to the
  -- outside of the sheet becomes alpha. Enclosed light pixels are moved just
  -- below the engine's OBJ color-0 key, so they remain opaque while the normal
  -- SpriteRenderer still owns palette selection. This means COLORS changes in
  -- the in-game menu continue to recolor these sprites normally.
  local function alphaSafeFollowerPath(path,name)
    if not (love and love.image and love.image.newImageData
        and love.filesystem and love.filesystem.createDirectory) then
      return path
    end
    local Assets=require("src.render.Assets")
    local ok,id=pcall(Assets.imageData,path)
    if not ok or not id then return path end
    local exterior,w=exteriorMask(id)
    id:mapPixel(function(x,y,r,g,b,a)
      if exterior[y*w+x+1] then return 1,1,1,0 end
      if a==0 then return r,g,b,0 end
      -- SpriteRenderer reserves shade 0 as transparent OBJ color 0.
      -- Preserve enclosed light detail as opaque OBJ color 1. The active
      -- PaletteFX mode still decides its actual displayed color.
      if r>0.83 and g>0.83 and b>0.83 then
        return 0.82,0.82,0.82,1
      end
      return r,g,b,1
    end)
    -- Assets.resolve only consults derived mod files for assets/generated/*
    -- paths. Write the processed sheet into this mod's derived tree and return
    -- the matching generated-asset key, so SpriteRenderer can load it normally.
    local derivedDir="mod-derived/pokopia_log568_demo/pokopia_followers"
    love.filesystem.createDirectory("mod-derived")
    love.filesystem.createDirectory("mod-derived/pokopia_log568_demo")
    love.filesystem.createDirectory(derivedDir)
    local fileName="follower_"..name..".png"
    local writePath=derivedDir.."/"..fileName
    local okEncode=pcall(function() id:encode("png",writePath) end)
    if okEncode then
      return "assets/generated/pokopia_followers/"..fileName
    end
    return path
  end

  applyDittoForm=function(game,form,ow)
    ow=ow or activeOverworld(game)
    if not (ow and ow.player) then return false end

    local SpriteRenderer=require("src.render.SpriteRenderer")
    local formSpriteIds={
      PERSIAN=PERSIAN,
      ELECTRODE=ELECTRODE,
      OLD_WOMAN="SPRITE_SILPH_WORKER_F",
      SCALPER="SPRITE_GAMBLER",
      HITMONLEE="HITMONLEE",
      HITMONCHAN="HITMONCHAN",
      PORYGON=PORYGON,
    }
    local spriteId=formSpriteIds[form] or DITTO
    local def
    if form=="DITTO" or not form then
      def=game.data.sprites[DITTO]
      form="DITTO"
    else
      def=transformedSpriteDef(game,spriteId)
    end
    if not def then return end

    local renderer=SpriteRenderer.new(def,"player")
    if form~="DITTO" then
      local purple=bakeDittoPurpleImage(def.image)
      if purple then
        renderer.image=purple
      end
    end
    ow.player.sprite=renderer
    ow.player.surfSprite=renderer
    ow.player.surfPikachuSprite=renderer
    ow.player.bikeSprite=renderer
    ow.player.pokopiaForm=form
    ow.player.pokopiaElectrodeAccelSteps=0
    ow.player.pokopiaElectrodeAccelDirection=nil

    local q=pokopiaData(game)
    local userRequestedForm=(q.requestedForm==form)
    q.currentForm=form
    q.requestedForm=nil

    -- Giovanni-room disguise rule: selecting a Pokemon form other than
    -- PERSIAN while within four walk cells of Giovanni immediately blows
    -- Ditto's cover.  Only a real transform-menu selection arms the event;
    -- restoring a saved form on map load must not retrigger it.
    if userRequestedForm and form~="DITTO" and form~="PERSIAN"
        and ow.map and ow.map.id=="POKEMON_MANSION_1F" then
      local boss=nil
      for _,n in ipairs(ow.npcs or {}) do
        if n.def and n.def.name=="GIOVANNI" then boss=n break end
      end
      if boss then
        local d=math.abs(ow.player.cellX-boss.cellX)+math.abs(ow.player.cellY-boss.cellY)
        if d<=4 then q.giovanniWrongFormPending=true end
      end
    end
    -- ELECTRODE does NOT use Gen 1's ordinary bicycle state.  Its movement
    -- is driven entirely by the Emerald Mach Bike transition/momentum state
    -- below; the transformed player sprite itself is already ELECTRODE.
    game.save.onBike=false
    ow.player.onBike=false
    if form~="ELECTRODE" then
      q.electrodeBikeFrameCounter=0
      q.electrodeBikeSpeed=0
      q.electrodeBikeTransition=nil
      q.electrodeBikeDirection=nil
      q.electrodeBikeCharge=0
    end
    return true
  end

  local function findNpc(ow,name)
    for _,npc in ipairs(ow.npcs or {}) do
      if npc.def and npc.def.name==name then return npc end
    end
  end

  local function removeNpc(ow,name)
    for i=#(ow.npcs or {}),1,-1 do
      local npc=ow.npcs[i]
      if npc.def and npc.def.name==name then
        table.remove(ow.npcs,i)
        for j=#(ow.entities or {}),1,-1 do
          if ow.entities[j]==npc then table.remove(ow.entities,j) end
        end
        return npc
      end
    end
  end

  local function showBox(game,text,done,opts)
    local TextBox=require("src.render.TextBox")
    game.stack:push(TextBox.new(game,text,done,opts))
  end


  -- Rattata dialogue portraits are chosen from the line's dramatic context.
  -- Callers can override the inferred expression for non-verbal/narration beats.
  local function rattataExpressionFor(text)
    local t=string.upper(tostring(text or ""))
    if t:find("AHHGGH",1,true) then return "Pain" end
    if t:find("STAND BACK",1,true) or t:find("I'LL HANDLE THIS",1,true) then return "Determined" end
    if t:find("SLOWPOKE",1,true) or t:find("YOU CALL THAT",1,true) then return "Shouting" end
    if t:find("TCH",1,true) or t:find("WASTING MY TIME",1,true) then return "Angry" end
    if t:find("COME BACK WHEN",1,true) then return "Sigh" end
    if t:find("HEY...",1,true) or t:find("CHEDDAR",1,true) then return "Surprised" end
    if t:find("HEH! DEAL",1,true) then return "Joyous" end
    if t:find("LEAD THE WAY",1,true) then return "Happy" end
    if t:find("WHAT'S IN IT",1,true) then return "Inspired" end
    if t:find("SECRET MEETING",1,true) then return "Normal" end
    return "Normal"
  end

  local function showRattataBox(game,text,done,expression,opts)
    opts=opts or {}
    opts.portrait={
      speaker="RATTATA",
      expression=expression or rattataExpressionFor(text),
    }
    showBox(game,text,done,opts)
  end

  -- MAGNETON alarm-shutdown effect state. These locals must be declared
  -- before magnetonTalk so its callback and the render hook share them.
  local magnetonSurgeFrames=0
  local magnetonSurgeDone=nil
  local magnetonSurgeOw=nil

  local function magnetonTalk(game,ow,npc,done)
    local q=pokopiaData(game)

    if q.alarmDisabled then
      showBox(game,
        "MAGNETON: MAGNE!\f"
        .."It looks very proud\nof itself.",
        done)
      return
    end

    showBox(game,
      "MAGNETON: BZZZT...\f"
      .."MAGNE-TON...\f"
      .."It listens closely\nto the alarm.\f"
      .."Its magnets spin\nfaster and faster.\f"
      .."MAGNETON: ZZZT?\f"
      .."Disrupt the alarm?",
      nil,{
        choice=function(yes)
          if not yes then
            showBox(game,
              "MAGNETON: BZZT...\f"
              .."Its magnets slowly\nstop spinning.",
              done)
            return
          end

          showBox(game,
            "MAGNETON: MAGNE-TON!\f"
            .."A magnetic pulse\nfills the room!\f"
            .."BZZZZZZT...\f"
            .."The alarm sputters...",
            function()
              q.alarmDisabled=true

              -- Gen I's Thunder Wave animation is keyed to the THUNDER_WAVE
              -- move SFX. Gen1Recomp exposes generated SFX using this name.
              require("src.core.Sound").play(game.data,"Thunder_Wave")
              stopPokopiaAlarm(game)

              if ow and ow.player then
                ow.player.inputLocked=false
                ow.player.frozen=false
              end

              magnetonSurgeFrames=60
              magnetonSurgeOw=ow

              magnetonSurgeDone=function()
                showBox(game,
                  "...and goes silent.\f"
                  .."MAGNETON: MAGNE!",
                  done)
              end
            end)
        end
      })
  end

  --------------------------------------------------------------------------
  -- VOLTORB hallway race.
  --
  -- Voltorb permanently patrols the race hallway on y=7. Race starts reset
  -- Voltorb to (22,7) and Ditto to (22,6); the turnaround end is x=10.  The score HUD is compositor
  -- UI only, so it never becomes a stack state and therefore never steals
  -- movement input from the player.
  --------------------------------------------------------------------------
  local walkNpcTo
  local routeNpcTo
  local setActorCell

  local function voltorbTalk(game,ow,npc,done)
    showBox(game,
      "VOLTORB races up and\ndown the hall.\f"
      .."It seems to think the\nalarm is cheering it on.",
      done,{speaker="VOLTORB",portrait={speaker="VOLTORB",expression="Normal"}})
  end

  setActorCell=function(actor,x,y)
    actor.cellX,actor.cellY=x,y
    actor.targetX,actor.targetY=nil,nil
    actor.moving=false
    actor.progress=0
    actor.px,actor.py=x*16,y*16
  end

  local function larvitarTalk(game,ow,npc,done)
    showBox(game,
      "LARVITAR stands watch in\nthe lobby.\f"
      .."It keeps nudging loose\nrubble away from the path.",
      done,{speaker="LARVITAR",portrait={speaker="LARVITAR",expression="Normal"}})
  end

  local function electrodeTalk(game,ow,npc,done)
    showBox(game,
      "ELECTRODE races through\nthe hall, grinning.\f"
      .."Every loud crash makes\nit bounce higher.\f"
      .."It seems delighted.",
      done,{speaker="ELECTRODE",portrait={speaker="ELECTRODE",expression="Normal"}})
  end

  local function hasItem(game,id)
    return game and game.save and game.save.inventory
      and (game.save.inventory[id] or 0)>0
  end

  local function takeItem(game,id)
    if not hasItem(game,id) then return false end
    require("src.inventory.Bag").remove(game.save,id,1)
    return true
  end

  local function makeQuestNpc(game,ow,index,name,sprite,x,y,facing,text)
    local NPC=require("src.world.NPC")
    local n=NPC.new(game.data,ow.map.id,{
      index=index,name=name,sprite=sprite,movement="STAY",range="NONE",
      text=text,x=x,y=y,
    })
    n.facing=facing or "down"
    n.wanders=false
    n.passable=false
    n.stepFrames=10
    table.insert(ow.npcs,n)
    table.insert(ow.entities,n)
    return n
  end

  walkNpcTo=function(ow,npc,tx,ty,done,collide)
    local Collision=require("src.world.Collision")
    local dirs={{0,-1,"up"},{0,1,"down"},{-1,0,"left"},{1,0,"right"}}
    local function key(x,y) return x..":"..y end
    local q={{npc.cellX,npc.cellY}}
    local qi=1
    local prev={[key(npc.cellX,npc.cellY)]=false}

    while q[qi] do
      local cx,cy=q[qi][1],q[qi][2]
      qi=qi+1
      if cx==tx and cy==ty then break end
      for _,d in ipairs(dirs) do
        local nx,ny=cx+d[1],cy+d[2]
        local k=key(nx,ny)
        local target=(nx==tx and ny==ty)
        if prev[k]==nil and ow.map:inBounds(nx,ny)
            and ow.map:isWalkableCell(nx,ny)
            and not ow.map:warpAtCell(nx,ny)
            and (target or not Collision.occupied(ow.entities,nx,ny,npc)) then
          prev[k]={cx,cy,d[3]}
          q[#q+1]={nx,ny}
        end
      end
    end

    if prev[key(tx,ty)]==nil and not (npc.cellX==tx and npc.cellY==ty) then
      if done then done(false) end
      return
    end

    local route={}
    local k=key(tx,ty)
    while prev[k] do
      local v=prev[k]
      table.insert(route,1,v[3])
      k=key(v[1],v[2])
    end

    local ri=1
    local function nextStep()
      local dir=route[ri]
      if not dir then
        if done then done(true) end
        return
      end
      ri=ri+1
      ow:scriptMove(npc,dir,1,nextStep,{collide=collide~=false})
    end
    nextStep()
  end

  routeNpcTo=function(ow,npc,tx,ty)
    local Collision=require("src.world.Collision")
    local dirs={{0,-1,"up"},{0,1,"down"},{-1,0,"left"},{1,0,"right"}}
    local function key(x,y) return x..":"..y end
    local q={{npc.cellX,npc.cellY}}
    local qi=1
    local prev={[key(npc.cellX,npc.cellY)]=false}

    while q[qi] do
      local cx,cy=q[qi][1],q[qi][2]
      qi=qi+1
      if cx==tx and cy==ty then break end
      for _,d in ipairs(dirs) do
        local nx,ny=cx+d[1],cy+d[2]
        local k=key(nx,ny)
        local target=(nx==tx and ny==ty)
        if prev[k]==nil and ow.map:inBounds(nx,ny)
            and ow.map:isWalkableCell(nx,ny)
            and not ow.map:warpAtCell(nx,ny)
            and (target or not Collision.occupied(ow.entities,nx,ny,npc)) then
          prev[k]={cx,cy,d[3]}
          q[#q+1]={nx,ny}
        end
      end
    end

    if prev[key(tx,ty)]==nil and not (npc.cellX==tx and npc.cellY==ty) then
      return nil
    end

    local route={}
    local k=key(tx,ty)
    while prev[k] do
      local v=prev[k]
      table.insert(route,1,v[3])
      k=key(v[1],v[2])
    end
    return route
  end

  local function walkNpcOutOfRoom(ow,npc,done)
    -- Find a real map warp and make the actor physically reach it before
    -- removal. Prefer a southern exit because this meeting room's staged
    -- departure already sends the scientist downward.
    local candidates={}
    for y=0,63 do
      for x=0,63 do
        if ow.map:inBounds(x,y) and ow.map:warpAtCell(x,y) then
          local adj={
            {x,y-1,"down"},{x,y+1,"up"},{x-1,y,"right"},{x+1,y,"left"},
          }
          for _,a in ipairs(adj) do
            if ow.map:inBounds(a[1],a[2]) and ow.map:isWalkableCell(a[1],a[2]) then
              local route=routeNpcTo(ow,npc,a[1],a[2])
              if route then
                candidates[#candidates+1]={
                  x=a[1],y=a[2],dir=a[3],warpX=x,warpY=y,
                  route=#route,south=(y>=npc.cellY) and 1 or 0,warpSouth=y,
                }
              end
            end
          end
        end
      end
    end

    table.sort(candidates,function(a,b)
      if a.south~=b.south then return a.south>b.south end
      if a.warpSouth~=b.warpSouth then return a.warpSouth>b.warpSouth end
      return a.route<b.route
    end)

    local exit=candidates[1]
    if not exit then
      if done then done(false) end
      return
    end

    walkNpcTo(ow,npc,exit.x,exit.y,function(ok)
      if not ok then
        if done then done(false) end
        return
      end
      npc.facing=exit.dir
      -- One final visible tile into the doorway/warp. Only after that movement
      -- completes does the event remove the actor and release Giovanni's line.
      ow:scriptMove(npc,exit.dir,1,function()
        if done then done(true) end
      end,{collide=false})
    end,false)
  end

  local function runRattataCircles(ow,rat,persian,done)
    -- Build a four-cell ring around Persian from live collision data.
    -- Use only cells that are genuinely walkable, non-warp, and currently
    -- unoccupied. If the room cannot support a full ring, fall back to a
    -- short collision-safe dart between legal adjacent cells.
    local Collision=require("src.world.Collision")
    local px,py=persian.cellX,persian.cellY
    local ring={
      {px-1,py-1},{px,py-1},{px+1,py-1},
      {px+1,py},{px+1,py+1},{px,py+1},
      {px-1,py+1},{px-1,py},
    }

    local legal={}
    for _,c in ipairs(ring) do
      local x,y=c[1],c[2]
      if ow.map:inBounds(x,y)
          and ow.map:isWalkableCell(x,y)
          and not ow.map:warpAtCell(x,y)
          and not Collision.occupied(ow.entities,x,y,rat) then
        legal[#legal+1]={x,y}
      end
    end

    if #legal<2 then
      if done then done() end
      return
    end

    -- About three seconds at Rattata's fast 7-frame step cadence.
    local laps=3
    local sequence={}
    for _=1,laps do
      for _,c in ipairs(legal) do sequence[#sequence+1]=c end
    end

    local i=1
    local function nextPoint()
      local c=sequence[i]
      if not c then
        if done then done() end
        return
      end
      i=i+1
      walkNpcTo(ow,rat,c[1],c[2],function(ok)
        if not ok then
          if done then done() end
          return
        end
        -- Keep Persian visually tracking Rattata while it circles.
        persian.facing=(rat.cellX<persian.cellX) and "left"
          or (rat.cellX>persian.cellX) and "right"
          or (rat.cellY<persian.cellY) and "up" or "down"
        nextPoint()
      end,true)
    end

    nextPoint()
  end

  local function chaseOneBlockBehind(ow,rat,persian,tx,ty,done)
    local route=routeNpcTo(ow,rat,tx,ty)
    if not route or #route==0 then
      if done then done(false) end
      return
    end

    rat.passable=false
    persian.passable=false
    rat.stepFrames=7
    persian.stepFrames=7

    -- Script Rattata's already collision-validated route as one continuous
    -- movement queue. Persian is updated by the render/update hook below:
    -- every time Rattata commits a new target cell, that cell becomes
    -- Persian's next goal after a one-cell delay. This is the same timing
    -- model used by PIXIE's smooth follower.
    ow.pokopiaPersianChase={
      rat=rat,
      persian=persian,
      trail={{x=rat.cellX,y=rat.cellY}},
      lastX=rat.cellX,lastY=rat.cellY,
      done=done,
    }

    local i=1
    local function moveNext()
      local dir=route[i]
      if not dir then
        local chase=ow.pokopiaPersianChase

        -- Rattata reaching the end of its validated escape route is the
        -- authoritative end of this cutscene. Never wait for Persian's
        -- trailing follower queue to drain before restoring gameplay.
        ow.pokopiaPersianChase=nil
        restorePlayerInput(liveGame,ow)

        if chase and chase.done then
          local done=chase.done
          chase.done=nil
          done(true)
        end
        return
      end
      i=i+1
      ow:scriptMove(rat,dir,1,moveNext,{collide=true})
    end
    moveNext()
  end


  local function openAdjacent(ow,npc,order)
    local Collision=require("src.world.Collision")
    order=order or {{1,0},{-1,0},{0,1},{0,-1}}
    for _,d in ipairs(order) do
      local x,y=npc.cellX+d[1],npc.cellY+d[2]
      if ow.map:inBounds(x,y) and ow.map:isWalkableCell(x,y)
          and not ow.map:warpAtCell(x,y)
          and not Collision.occupied(ow.entities,x,y,npc) then
        return x,y
      end
    end
  end

  local function findBasementArgumentPair(ow)
    local Collision=require("src.world.Collision")
    for y=ow.map.def.height*2-3,3,-1 do
      for x=3,ow.map.def.width*2-4 do
        if ow.map:isWalkableCell(x,y)
            and ow.map:isWalkableCell(x+1,y)
            and not ow.map:warpAtCell(x,y)
            and not ow.map:warpAtCell(x+1,y)
            and not Collision.occupied(ow.entities,x,y,nil)
            and not Collision.occupied(ow.entities,x+1,y,nil) then
          return x,y,x+1,y
        end
      end
    end
  end

  local function makePixieFollower(game,ow,x,y,facing)
    local NPC=require("src.world.NPC")
    local pixie=NPC.new(game.data,ow.map.id,{
      index=98,
      name="VULPIX",
      sprite=VULPIX,
      movement="STAY",
      range="NONE",
      x=x,
      y=y,
    })
    pixie.passable=true
    pixie.wanders=false
    pixie.pokopiaPixieFollower=true
    pixie.stepFrames=12
    pixie.facing=facing or "down"
    return pixie
  end

  local function resetPixieTrail(ow)
    local p=ow.player
    ow.pokopiaPixieTrail={
      mapId=ow.map and ow.map.id,
      x=p.cellX,
      y=p.cellY,
    }
  end

  local function ensurePixieFollower(game,ow,warpArrival)
    local q=pokopiaData(game)
    if not q.pixieFollowing then return nil end

    local pixie=findNpc(ow,"VULPIX")
    if not pixie then
      -- Match the engine's fresh-warp follower rule: spawn on the player's
      -- arrival cell, passable, then let the newly seeded trail pull PIXIE
      -- out behind the player as Ditto moves away.
      local x,y=ow.player.cellX,ow.player.cellY
      pixie=makePixieFollower(game,ow,x,y,ow.player.facing)
      table.insert(ow.npcs,pixie)
      table.insert(ow.entities,pixie)
    else
      pixie.passable=true
      pixie.wanders=false
      pixie.pokopiaPixieFollower=true
      pixie.stepFrames=12
      if warpArrival then
        pixie.cellX,pixie.cellY=ow.player.cellX,ow.player.cellY
        pixie.px,pixie.py=pixie.cellX*16,pixie.cellY*16
        pixie.targetX,pixie.targetY=nil,nil
        pixie.goalX,pixie.goalY=nil,nil
        pixie.moving=false
      end
    end

    resetPixieTrail(ow)
    return pixie
  end

  local function startPixieFollower(game,ow)
    local q=pokopiaData(game)
    q.pixieFollowing=true

    local pixie=findNpc(ow,"VULPIX")
    if pixie then
      pixie.passable=true
      pixie.wanders=false
      pixie.pokopiaPixieFollower=true
      pixie.stepFrames=12
    end

    resetPixieTrail(ow)
  end

  local function startRattataFollower(game,ow,npc)
    local q=pokopiaData(game)
    q.rattataFollowing=true
    npc.passable=true
    npc.wanders=false
    npc.pokopiaRattataFollower=true
    npc.stepFrames=10
    ow.pokopiaRattataTrail={
      mapId=ow.map.id,x=ow.player.cellX,y=ow.player.cellY,
    }
  end

  local function rattataTalk(game,ow,npc,done)
    local q=pokopiaData(game)

    if q.rattataFollowing then
      showRattataBox(game,"RATTATA: Lead the way,\npunk!",done,"Happy")
      return
    end
    if not q.rocketStopped then
      showRattataBox(game,
        "RATTATA digs through\nthe fallen papers.",
        function()
          showRattataBox(game,
            "It found some crackers.",
            function()
              showRattataBox(game,
                "It looks very pleased.",
                done,"Joyous")
            end,"Surprised")
        end,"Normal")
      return
    end

    showRattataBox(game,
      "RATTATA: Trying to get\ninto that secret meeting?",
      function()
        showRattataBox(game,
          "RATTATA: And you need\nmy help?",
          function()
            showRattataBox(game,
              "RATTATA: Heh. What's in it\nfor me?",
              function()
                if not hasItem(game,"CHEESE") then
                  showRattataBox(game,
                    "RATTATA: Come back when\nyou've got something\nworth my time.",
                    done,"Sigh")
                  return
                end

                showRattataBox(game,
                  "RATTATA: Hey...",
                  function()
                    showRattataBox(game,
                      "RATTATA: That block of\nCHEDDAR.",
                      function()
                        showRattataBox(game,
                          "RATTATA: How about it?",
                          nil,"Inspired",{
                            choice=function(yes)
                              if not yes then
                                showRattataBox(game,"RATTATA: Tch.",function()
                                  showRattataBox(game,
                                    "RATTATA: You're wasting my\ntime, punk.",
                                    done,"Angry")
                                end,"Angry")
                                return
                              end
                              takeItem(game,"CHEESE")
                              showRattataBox(game,
                                "RATTATA: Heh! Deal.",
                                function()
                                  showRattataBox(game,
                                    "RATTATA: Lead me there, punk.",
                                    function()
                                      startRattataFollower(game,ow,npc)
                                      done()
                                    end,"Happy")
                                end,"Joyous")
                            end
                          })
                      end,"Surprised")
                  end,"Surprised")
              end,"Inspired")
          end,"Happy")
      end,"Normal")
  end

  local function rocketGuardTalk(game,ow,npc,done)
    local q=pokopiaData(game)

    if q.currentForm=="PERSIAN" and q.forms and q.forms.PERSIAN then
      showBox(game,
        "ROCKET: Hey PERSIAN!\f"
        .."Welcome back!\f"
        .."The Boss has been\nwaiting.",
        done)
      return
    end

    if q.distractionDone then
      showBox(game,
        "ROCKET: That RATTATA\nsure was funny\f"
        .."coming in here and\ngetting PERSIAN all\nriled up like that.\f"
        .."I wonder where\nthey went?\f"
        .."Oh, please stay\noutside.\f"
        .."The only POKeMON\nallowed in here is\nPERSIAN.",
        done)
      return
    end

    if q.rocketStopped then
      showBox(game,
        "ROCKET: Sorry, only\nthe boss and his\nPERSIAN are allowed\nback here.",
        done)
      return
    end

    showBox(game,
      "ROCKET: Whoa there,\nlittle fella!\f"
      .."You can't go back there.\f"
      .."Hey... don't be scared.\f"
      .."The Boss has everything\nunder control.",
      done)
  end

  local function persistArgumentPair(game,ow)
    local q=pokopiaData(game)
    local rat=findNpc(ow,"RATTATA_ARGUMENT")
    local persian=findNpc(ow,"PERSIAN_ARGUMENT")
    if not (rat and persian) then return end

    q.argumentPositions={
      ratX=rat.cellX,ratY=rat.cellY,
      persianX=persian.cellX,persianY=persian.cellY,
      ratFacing=rat.facing or "right",
      persianFacing=persian.facing or "left",
      locked=true,
    }
  end

  local function finishPersianLesson(game,done,ow)
    local q=pokopiaData(game)
    local forms=unlockedForms(game)
    forms.PERSIAN=true
    q.persianLessonDone=true
    if ow then persistArgumentPair(game,ow) end
    showBox(game,
      "DITTO had an idea!",
      function()
        showBox(game,
          "DITTO learned to\ntransform into a\nPERSIAN!",
          done)
      end)
  end

  local function basementPairTalk(game,ow,npc,done)
    local q=pokopiaData(game)

    if q.persianLessonDone then
      -- The post-FALSE SWIPE tableau is fixed. Interacting with Rattata must
      -- not make it turn toward Ditto; restore both actors to their saved
      -- cutscene facings before opening the textbox.
      local a=q.argumentPositions
      local rat=findNpc(ow,"RATTATA_ARGUMENT")
      local persian=findNpc(ow,"PERSIAN_ARGUMENT")
      if a and rat then rat.facing=a.ratFacing or "right" end
      if a and persian then persian.facing=a.persianFacing or "left" end
      persistArgumentPair(game,ow)
      showBox(game,
        "Better leave them alone.",
        function()
          if a and rat then rat.facing=a.ratFacing or "right" end
          if a and persian then persian.facing=a.persianFacing or "left" end
          done()
        end)
      return
    end

    if q.persianLessonPlaying then
      showBox(game,
        "Better leave them alone.",
        done)
      return
    end

    q.persianLessonPlaying=true
    local rat=findNpc(ow,"RATTATA_ARGUMENT")
    local persian=findNpc(ow,"PERSIAN_ARGUMENT")

    if rat and persian then
      rat.facing="right"
      persian.facing="left"
    end

    showRattataBox(game,
      "RATTATA: You call that\na chase?",
      function()
        showRattataBox(game,
          "RATTATA: I've seen SLOWPOKE\nmove faster than you!",
          function()
            showBox(game,
              "PERSIAN used\nFALSE SWIPE!",
              function()
                -- Verified engine SFX id: battle hit playback uses "Damage".
                require("src.core.Sound").play(game.data,"Damage")

                -- FALSE SWIPE is the final movement beat. Freeze both actors
                -- exactly where the hit lands and persist that tableau before
                -- any follow-up dialogue can alter facing or wander state.
                if rat then
                  rat.moving=false
                  rat.targetX,rat.targetY=rat.cellX,rat.cellY
                  rat.wanders=false
                  rat.frozen=true
                end
                if persian then
                  persian.moving=false
                  persian.targetX,persian.targetY=persian.cellX,persian.cellY
                  persian.wanders=false
                  persian.frozen=true
                end
                persistArgumentPair(game,ow)

                showRattataBox(game,
                  "RATTATA: AHHGGH...",
                  function()
                    finishPersianLesson(game,function()
                      q.persianLessonPlaying=nil
                      persistArgumentPair(game,ow)
                      done()
                    end,ow)
                end,"Pain")
              end)
          end,"Shouting")
      end,"Shouting")
  end


  local function vulpixTalk(game,ow,npc,done)
    local q=pokopiaData(game)

    if not q.loganAsked then
      showBox(game,
        "VULPIX is trembling.\f"
        .."Its ears twitch at\nevery alarm.\f"
        .."It keeps staring at\nthe stairwell.",
        done)
      return
    end

    if q.pixieFollowing then
      showBox(game,
        "PIXIE stays close behind\nyou.",
        done)
      return
    end

    showBox(game,
      "PIXIE: I'm scared...\f"
      .."What's happening?\f"
      .."...LOGIE sent you?\f"
      .."He wants me downstairs?\f"
      .."O-okay. I'll follow.",
      function()
        startPixieFollower(game,ow)
        done()
      end)
  end

  -- TCG services must live at module scope so both the Celadon attendant and
  -- Mansion Hypno can use them regardless of which story scene initialized first.
  local function createTCGServices()
  --------------------------------------------------------------------------
  -- Celadon Pokemon TCG integration.
  -- The database, expansion membership, artwork manifest, booster variants,
  -- rarity slots and weighting are packaged verbatim from
  -- pokemon_tcg_gbc_complete.zip under assets/tcg/.
  --------------------------------------------------------------------------
  -- Generated directly from the four source Lua tables in the supplied TCG
  -- package. The verbatim source tables are also retained under assets/tcg/data.
  local TCG_ART={["booster_pack_art"]={["Colosseum"]={"colosseum1.png","colosseum2.png",},["Evolution"]={"evolution1.png","evolution2.png",},["Laboratory"]={"laboratory1.png","laboratory2.png",},["Mystery"]={"mystery1.png","mystery2.png",},["_oam_layout"]="oam.png",},["cards"]={["AbraCard"]={["art_file"]="abra.png",["name"]="Abra",},["AerodactylCard"]={["art_file"]="aerodactyl.png",["name"]="Aerodactyl",},["AlakazamCard"]={["art_file"]="alakazam.png",["name"]="Alakazam",},["ArbokCard"]={["art_file"]="arbok.png",["name"]="Arbok",},["ArcanineLv34Card"]={["art_file"]="arcanine1.png",["name"]="Arcanine",},["ArcanineLv45Card"]={["art_file"]="arcanine2.png",["name"]="Arcanine",},["ArticunoLv35Card"]={["art_file"]="articuno1.png",["name"]="Articuno",},["ArticunoLv37Card"]={["art_file"]="articuno2.png",["name"]="Articuno",},["BeedrillCard"]={["art_file"]="beedrill.png",["name"]="Beedrill",},["BellsproutCard"]={["art_file"]="bellsprout.png",["name"]="Bellsprout",},["BillCard"]={["art_file"]="bill.png",["name"]="Bill",},["BlastoiseCard"]={["art_file"]="blastoise.png",["name"]="Blastoise",},["BulbasaurCard"]={["art_file"]="bulbasaur.png",["name"]="Bulbasaur",},["ButterfreeCard"]={["art_file"]="butterfree.png",["name"]="Butterfree",},["CaterpieCard"]={["art_file"]="caterpie.png",["name"]="Caterpie",},["ChanseyCard"]={["art_file"]="chansey.png",["name"]="Chansey",},["CharizardCard"]={["art_file"]="charizard.png",["name"]="Charizard",},["CharmanderCard"]={["art_file"]="charmander.png",["name"]="Charmander",},["CharmeleonCard"]={["art_file"]="charmeleon.png",["name"]="Charmeleon",},["ClefableCard"]={["art_file"]="clefable.png",["name"]="Clefable",},["ClefairyCard"]={["art_file"]="clefairy.png",["name"]="Clefairy",},["ClefairyDollCard"]={["art_file"]="clefairydoll.png",["name"]="Clefairy Doll",},["CloysterCard"]={["art_file"]="cloyster.png",["name"]="Cloyster",},["ComputerSearchCard"]={["art_file"]="computersearch.png",["name"]="Computer Search",},["CuboneCard"]={["art_file"]="cubone.png",["name"]="Cubone",},["DefenderCard"]={["art_file"]="defender.png",["name"]="Defender",},["DevolutionSprayCard"]={["art_file"]="devolutionspray.png",["name"]="Devolution Spray",},["DewgongCard"]={["art_file"]="dewgong.png",["name"]="Dewgong",},["DiglettCard"]={["art_file"]="diglett.png",["name"]="Diglett",},["DittoCard"]={["art_file"]="ditto.png",["name"]="Ditto",},["DodrioCard"]={["art_file"]="dodrio.png",["name"]="Dodrio",},["DoduoCard"]={["art_file"]="doduo.png",["name"]="Doduo",},["DoubleColorlessEnergyCard"]={["art_file"]="doublecolorlessenergy.png",["name"]="Double Colorless Energy",},["DragonairCard"]={["art_file"]="dragonair.png",["name"]="Dragonair",},["DragoniteLv41Card"]={["art_file"]="dragonite1.png",["name"]="Dragonite",},["DragoniteLv45Card"]={["art_file"]="dragonite2.png",["name"]="Dragonite",},["DratiniCard"]={["art_file"]="dratini.png",["name"]="Dratini",},["DrowzeeCard"]={["art_file"]="drowzee.png",["name"]="Drowzee",},["DugtrioCard"]={["art_file"]="dugtrio.png",["name"]="Dugtrio",},["EeveeCard"]={["art_file"]="eevee.png",["name"]="Eevee",},["EkansCard"]={["art_file"]="ekans.png",["name"]="Ekans",},["ElectabuzzLv20Card"]={["art_file"]="electabuzz1.png",["name"]="Electabuzz",},["ElectabuzzLv35Card"]={["art_file"]="electabuzz2.png",["name"]="Electabuzz",},["ElectrodeLv35Card"]={["art_file"]="electrode1.png",["name"]="Electrode",},["ElectrodeLv42Card"]={["art_file"]="electrode2.png",["name"]="Electrode",},["EnergyRemovalCard"]={["art_file"]="energyremoval.png",["name"]="Energy Removal",},["EnergyRetrievalCard"]={["art_file"]="energyretrieval.png",["name"]="Energy Retrieval",},["EnergySearchCard"]={["art_file"]="energysearch.png",["name"]="Energy Search",},["ExeggcuteCard"]={["art_file"]="exeggcute.png",["name"]="Exeggcute",},["ExeggutorCard"]={["art_file"]="exeggutor.png",["name"]="Exeggutor",},["FarfetchdCard"]={["art_file"]="farfetchd.png",["name"]="Farfetch'd",},["FearowCard"]={["art_file"]="fearow.png",["name"]="Fearow",},["FightingEnergyCard"]={["art_file"]="fightingenergy.png",["name"]="Fighting Energy",},["FireEnergyCard"]={["art_file"]="fireenergy.png",["name"]="Fire Energy",},["FlareonLv22Card"]={["art_file"]="flareon1.png",["name"]="Flareon",},["FlareonLv28Card"]={["art_file"]="flareon2.png",["name"]="Flareon",},["FlyingPikachuCard"]={["art_file"]="flyingpikachu.png",["name"]="Flying Pikachu",},["FullHealCard"]={["art_file"]="fullheal.png",["name"]="Full Heal",},["GamblerCard"]={["art_file"]="gambler.png",["name"]="Gambler",},["GastlyLv17Card"]={["art_file"]="gastly2.png",["name"]="Gastly",},["GastlyLv8Card"]={["art_file"]="gastly1.png",["name"]="Gastly",},["GengarCard"]={["art_file"]="gengar.png",["name"]="Gengar",},["GeodudeCard"]={["art_file"]="geodude.png",["name"]="Geodude",},["GloomCard"]={["art_file"]="gloom.png",["name"]="Gloom",},["GolbatCard"]={["art_file"]="golbat.png",["name"]="Golbat",},["GoldeenCard"]={["art_file"]="goldeen.png",["name"]="Goldeen",},["GolduckCard"]={["art_file"]="golduck.png",["name"]="Golduck",},["GolemCard"]={["art_file"]="golem.png",["name"]="Golem",},["GrassEnergyCard"]={["art_file"]="grassenergy.png",["name"]="Grass Energy",},["GravelerCard"]={["art_file"]="graveler.png",["name"]="Graveler",},["GrimerCard"]={["art_file"]="grimer.png",["name"]="Grimer",},["GrowlitheCard"]={["art_file"]="growlithe.png",["name"]="Growlithe",},["GustOfWindCard"]={["art_file"]="gustofwind.png",["name"]="Gust of Wind",},["GyaradosCard"]={["art_file"]="gyarados.png",["name"]="Gyarados",},["HaunterLv17Card"]={["art_file"]="haunter1.png",["name"]="Haunter",},["HaunterLv22Card"]={["art_file"]="haunter2.png",["name"]="Haunter",},["HitmonchanCard"]={["art_file"]="hitmonchan.png",["name"]="Hitmonchan",},["HitmonleeCard"]={["art_file"]="hitmonlee.png",["name"]="Hitmonlee",},["HorseaCard"]={["art_file"]="horsea.png",["name"]="Horsea",},["HypnoCard"]={["art_file"]="hypno.png",["name"]="Hypno",},["ImakuniCard"]={["art_file"]="imakuni.png",["name"]="Imakuni?",},["ImposterProfessorOakCard"]={["art_file"]="imposterprofessoroak.png",["name"]="Imposter Professor Oak",},["ItemFinderCard"]={["art_file"]="itemfinder.png",["name"]="Item Finder",},["IvysaurCard"]={["art_file"]="ivysaur.png",["name"]="Ivysaur",},["JigglypuffLv12Card"]={["art_file"]="jigglypuff1.png",["name"]="Jigglypuff",},["JigglypuffLv13Card"]={["art_file"]="jigglypuff2.png",["name"]="Jigglypuff",},["JigglypuffLv14Card"]={["art_file"]="jigglypuff3.png",["name"]="Jigglypuff",},["JolteonLv24Card"]={["art_file"]="jolteon1.png",["name"]="Jolteon",},["JolteonLv29Card"]={["art_file"]="jolteon2.png",["name"]="Jolteon",},["JynxCard"]={["art_file"]="jynx.png",["name"]="Jynx",},["KabutoCard"]={["art_file"]="kabuto.png",["name"]="Kabuto",},["KabutopsCard"]={["art_file"]="kabutops.png",["name"]="Kabutops",},["KadabraCard"]={["art_file"]="kadabra.png",["name"]="Kadabra",},["KakunaCard"]={["art_file"]="kakuna.png",["name"]="Kakuna",},["KangaskhanCard"]={["art_file"]="kangaskhan.png",["name"]="Kangaskhan",},["KinglerCard"]={["art_file"]="kingler.png",["name"]="Kingler",},["KoffingCard"]={["art_file"]="koffing.png",["name"]="Koffing",},["KrabbyCard"]={["art_file"]="krabby.png",["name"]="Krabby",},["LaprasCard"]={["art_file"]="lapras.png",["name"]="Lapras",},["LassCard"]={["art_file"]="lass.png",["name"]="Lass",},["LickitungCard"]={["art_file"]="lickitung.png",["name"]="Lickitung",},["LightningEnergyCard"]={["art_file"]="lightningenergy.png",["name"]="Lightning Energy",},["MachampCard"]={["art_file"]="machamp.png",["name"]="Machamp",},["MachokeCard"]={["art_file"]="machoke.png",["name"]="Machoke",},["MachopCard"]={["art_file"]="machop.png",["name"]="Machop",},["MagikarpCard"]={["art_file"]="magikarp.png",["name"]="Magikarp",},["MagmarLv24Card"]={["art_file"]="magmar1.png",["name"]="Magmar",},["MagmarLv31Card"]={["art_file"]="magmar2.png",["name"]="Magmar",},["MagnemiteLv13Card"]={["art_file"]="magnemite1.png",["name"]="Magnemite",},["MagnemiteLv15Card"]={["art_file"]="magnemite2.png",["name"]="Magnemite",},["MagnetonLv28Card"]={["art_file"]="magneton1.png",["name"]="Magneton",},["MagnetonLv35Card"]={["art_file"]="magneton2.png",["name"]="Magneton",},["MaintenanceCard"]={["art_file"]="maintenance.png",["name"]="Maintenance",},["MankeyCard"]={["art_file"]="mankey.png",["name"]="Mankey",},["MarowakLv26Card"]={["art_file"]="marowak1.png",["name"]="Marowak",},["MarowakLv32Card"]={["art_file"]="marowak2.png",["name"]="Marowak",},["MeowthLv14Card"]={["art_file"]="meowth1.png",["name"]="Meowth",},["MeowthLv15Card"]={["art_file"]="meowth2.png",["name"]="Meowth",},["MetapodCard"]={["art_file"]="metapod.png",["name"]="Metapod",},["MewLv15Card"]={["art_file"]="mew2.png",["name"]="Mew",},["MewLv23Card"]={["art_file"]="mew3.png",["name"]="Mew",},["MewLv8Card"]={["art_file"]="mew1.png",["name"]="Mew",},["MewtwoAltLV60Card"]={["art_file"]="mewtwo3.png",["name"]="Mewtwo",},["MewtwoLv53Card"]={["art_file"]="mewtwo1.png",["name"]="Mewtwo",},["MewtwoLv60Card"]={["art_file"]="mewtwo2.png",["name"]="Mewtwo",},["MoltresLv35Card"]={["art_file"]="moltres1.png",["name"]="Moltres",},["MoltresLv37Card"]={["art_file"]="moltres2.png",["name"]="Moltres",},["MrFujiCard"]={["art_file"]="mrfuji.png",["name"]="Mr.Fuji",},["MrMimeCard"]={["art_file"]="mrmime.png",["name"]="Mr. Mime",},["MukCard"]={["art_file"]="muk.png",["name"]="Muk",},["MysteriousFossilCard"]={["art_file"]="mysteriousfossil.png",["name"]="Mysterious Fossil",},["NidokingCard"]={["art_file"]="nidoking.png",["name"]="Nidoking",},["NidoqueenCard"]={["art_file"]="nidoqueen.png",["name"]="Nidoqueen",},["NidoranFCard"]={["art_file"]="nidoranf.png",["name"]="Nidoran♀",},["NidoranMCard"]={["art_file"]="nidoranm.png",["name"]="Nidoran♂",},["NidorinaCard"]={["art_file"]="nidorina.png",["name"]="Nidorina",},["NidorinoCard"]={["art_file"]="nidorino.png",["name"]="Nidorino",},["NinetalesLv32Card"]={["art_file"]="ninetales1.png",["name"]="Ninetails",},["NinetalesLv35Card"]={["art_file"]="ninetales2.png",["name"]="Ninetails",},["OddishCard"]={["art_file"]="oddish.png",["name"]="Oddish",},["OmanyteCard"]={["art_file"]="omanyte.png",["name"]="Omanyte",},["OmastarCard"]={["art_file"]="omastar.png",["name"]="Omastar",},["OnixCard"]={["art_file"]="onix.png",["name"]="Onix",},["ParasCard"]={["art_file"]="paras.png",["name"]="Paras",},["ParasectCard"]={["art_file"]="parasect.png",["name"]="Parasect",},["PersianCard"]={["art_file"]="persian.png",["name"]="Persian",},["PidgeotLv38Card"]={["art_file"]="pidgeot1.png",["name"]="Pidgeot",},["PidgeotLv40Card"]={["art_file"]="pidgeot2.png",["name"]="Pidgeot",},["PidgeottoCard"]={["art_file"]="pidgeotto.png",["name"]="Pidgeotto",},["PidgeyCard"]={["art_file"]="pidgey.png",["name"]="Pidgey",},["PikachuAltLv16Card"]={["art_file"]="pikachu4.png",["name"]="Pikachu",},["PikachuLv12Card"]={["art_file"]="pikachu1.png",["name"]="Pikachu",},["PikachuLv14Card"]={["art_file"]="pikachu2.png",["name"]="Pikachu",},["PikachuLv16Card"]={["art_file"]="pikachu3.png",["name"]="Pikachu",},["PinsirCard"]={["art_file"]="pinsir.png",["name"]="Pinsir",},["PlusPowerCard"]={["art_file"]="pluspower.png",["name"]="PlusPower",},["PokeBallCard"]={["art_file"]="pokeball.png",["name"]="Poké Ball",},["PokedexCard"]={["art_file"]="pokedex.png",["name"]="Pokédex",},["PokemonBreederCard"]={["art_file"]="pokemonbreeder.png",["name"]="Pokémon Breeder",},["PokemonCenterCard"]={["art_file"]="pokemoncenter.png",["name"]="Pokémon Center",},["PokemonFluteCard"]={["art_file"]="pokemonflute.png",["name"]="Pokémon Flute",},["PokemonTraderCard"]={["art_file"]="pokemontrader.png",["name"]="Pokémon Trader",},["PoliwagCard"]={["art_file"]="poliwag.png",["name"]="Poliwag",},["PoliwhirlCard"]={["art_file"]="poliwhirl.png",["name"]="Poliwhirl",},["PoliwrathCard"]={["art_file"]="poliwrath.png",["name"]="Poliwrath",},["PonytaCard"]={["art_file"]="ponyta.png",["name"]="Ponyta",},["PorygonCard"]={["art_file"]="porygon.png",["name"]="Porygon",},["PotionCard"]={["art_file"]="potion.png",["name"]="Potion",},["PrimeapeCard"]={["art_file"]="primeape.png",["name"]="Primeape",},["ProfessorOakCard"]={["art_file"]="professoroak.png",["name"]="Professor Oak",},["PsychicEnergyCard"]={["art_file"]="psychicenergy.png",["name"]="Psychic Energy",},["PsyduckCard"]={["art_file"]="psyduck.png",["name"]="Psyduck",},["RaichuLv40Card"]={["art_file"]="raichu1.png",["name"]="Raichu",},["RaichuLv45Card"]={["art_file"]="raichu2.png",["name"]="Raichu",},["RapidashCard"]={["art_file"]="rapidash.png",["name"]="Rapidash",},["RaticateCard"]={["art_file"]="raticate.png",["name"]="Raticate",},["RattataCard"]={["art_file"]="rattata.png",["name"]="Rattata",},["RecycleCard"]={["art_file"]="recycle.png",["name"]="Recycle",},["ReviveCard"]={["art_file"]="revive.png",["name"]="Revive",},["RhydonCard"]={["art_file"]="rhydon.png",["name"]="Rhydon",},["RhyhornCard"]={["art_file"]="rhyhorn.png",["name"]="Rhyhorn",},["SandshrewCard"]={["art_file"]="sandshrew.png",["name"]="Sandshrew",},["SandslashCard"]={["art_file"]="sandslash.png",["name"]="Sandslash",},["ScoopUpCard"]={["art_file"]="scoopup.png",["name"]="Scoop Up",},["ScytherCard"]={["art_file"]="scyther.png",["name"]="Scyther",},["SeadraCard"]={["art_file"]="seadra.png",["name"]="Seadra",},["SeakingCard"]={["art_file"]="seaking.png",["name"]="Seaking",},["SeelCard"]={["art_file"]="seel.png",["name"]="Seel",},["ShellderCard"]={["art_file"]="shellder.png",["name"]="Shellder",},["SlowbroCard"]={["art_file"]="slowbro.png",["name"]="Slowbro",},["SlowpokeLv18Card"]={["art_file"]="slowpoke2.png",["name"]="Slowpoke",},["SlowpokeLv9Card"]={["art_file"]="slowpoke1.png",["name"]="Slowpoke",},["SnorlaxCard"]={["art_file"]="snorlax.png",["name"]="Snorlax",},["SpearowCard"]={["art_file"]="spearow.png",["name"]="Spearow",},["SquirtleCard"]={["art_file"]="squirtle.png",["name"]="Squirtle",},["StarmieCard"]={["art_file"]="starmie.png",["name"]="Starmie",},["StaryuCard"]={["art_file"]="staryu.png",["name"]="Staryu",},["SuperEnergyRemovalCard"]={["art_file"]="superenergyremoval.png",["name"]="Super Energy Removal",},["SuperEnergyRetrievalCard"]={["art_file"]="superenergyretrieval.png",["name"]="Super Energy Retrieval",},["SuperPotionCard"]={["art_file"]="superpotion.png",["name"]="Super Potion",},["SurfingPikachuAltLv13Card"]={["art_file"]="surfingpikachu2.png",["name"]="Surfing Pikachu",},["SurfingPikachuLv13Card"]={["art_file"]="surfingpikachu1.png",["name"]="Surfing Pikachu",},["SwitchCard"]={["art_file"]="switch.png",["name"]="Switch",},["TangelaLv12Card"]={["art_file"]="tangela2.png",["name"]="Tangela",},["TangelaLv8Card"]={["art_file"]="tangela1.png",["name"]="Tangela",},["TaurosCard"]={["art_file"]="tauros.png",["name"]="Tauros",},["TentacoolCard"]={["art_file"]="tentacool.png",["name"]="Tentacool",},["TentacruelCard"]={["art_file"]="tentacruel.png",["name"]="Tentacruel",},["VaporeonLv29Card"]={["art_file"]="vaporeon1.png",["name"]="Vaporeon",},["VaporeonLv42Card"]={["art_file"]="vaporeon2.png",["name"]="Vaporeon",},["VenomothCard"]={["art_file"]="venomoth.png",["name"]="Venomoth",},["VenonatCard"]={["art_file"]="venonat.png",["name"]="Venonat",},["VenusaurLv64Card"]={["art_file"]="venusaur1.png",["name"]="Venusaur",},["VenusaurLv67Card"]={["art_file"]="venusaur2.png",["name"]="Venusaur",},["VictreebelCard"]={["art_file"]="victreebel.png",["name"]="Victreebel",},["VileplumeCard"]={["art_file"]="vileplume.png",["name"]="Vileplume",},["VoltorbCard"]={["art_file"]="voltorb.png",["name"]="Voltorb",},["VulpixCard"]={["art_file"]="vulpix.png",["name"]="Vulpix",},["WartortleCard"]={["art_file"]="wartortle.png",["name"]="Wartortle",},["WaterEnergyCard"]={["art_file"]="waterenergy.png",["name"]="Water Energy",},["WeedleCard"]={["art_file"]="weedle.png",["name"]="Weedle",},["WeepinbellCard"]={["art_file"]="weepinbell.png",["name"]="Weepinbell",},["WeezingCard"]={["art_file"]="weezing.png",["name"]="Weezing",},["WigglytuffCard"]={["art_file"]="wigglytuff.png",["name"]="Wigglytuff",},["ZapdosLv40Card"]={["art_file"]="zapdos1.png",["name"]="Zapdos",},["ZapdosLv64Card"]={["art_file"]="zapdos2.png",["name"]="Zapdos",},["ZapdosLv68Card"]={["art_file"]="zapdos3.png",["name"]="Zapdos",},["ZubatCard"]={["art_file"]="zubat.png",["name"]="Zubat",},},["ui_sheets"]={{["contents"]="Three card-type header labels used on the card Check screen: TRAINER / ENERGY / POKEMON.",["file"]="card_headers.png",["size"]="64x48",},{["contents"]="Color (CGB) symbol tile sheet: coin faces, HP/damage digit font, weakness/resistance/retreat-cost pips, status condition icons (Confused/Asleep/Paralyzed/Poisoned), and energy-type icons, as rendered on Game Boy Color.",["file"]="cgb_symbols.png",["size"]="64x136",},{["contents"]="Same symbol set as cgb_symbols.png, but the palette/rendering used on original monochrome Game Boy / Super Game Boy.",["file"]="dmg_sgb_symbols.png",["size"]="64x136",},{["contents"]="Miscellaneous duel-screen icons (cursor, arrows, and other small UI glyphs).",["file"]="other.png",["size"]="64x56",},{["contents"]="The text-box message graphics used for turn announcements (\"Player's turn\" / \"Opponent's turn\"), the coin-toss prompt, and similar full-width dialog boxes.",["file"]="box_messages.png",["size"]="80x224",},{["contents"]="The small stacked-cards icon used for the \"Hand\" option on the main duel menu.",["file"]="hand_cards.png",["size"]="16x16",},},}
  local TCG_EXPANSIONS={["Colosseum"]={"NidoranMCard","NidorinoCard","TangelaLv12Card","ScytherCard","PinsirCard","CharmanderCard","CharmeleonCard","GrowlitheCard","ArcanineLv45Card","PonytaCard","MagmarLv24Card","SeelCard","DewgongCard","GoldeenCard","SeakingCard","StaryuCard","MagikarpCard","GyaradosCard","PikachuLv12Card","RaichuLv40Card","MagnemiteLv13Card","MagnetonLv28Card","ElectabuzzLv35Card","ZapdosLv64Card","DiglettCard","DugtrioCard","MachopCard","HitmonchanCard","AbraCard","KadabraCard","RattataCard","RaticateCard","JigglypuffLv14Card","WigglytuffCard","MeowthLv14Card","ChanseyCard","KangaskhanCard","SnorlaxCard","ProfessorOakCard","BillCard","SwitchCard","PokeBallCard","ScoopUpCard","ComputerSearchCard","PlusPowerCard","DefenderCard","ItemFinderCard","PotionCard","FullHealCard","ReviveCard",},["Energy"]={"GrassEnergyCard","FireEnergyCard","WaterEnergyCard","LightningEnergyCard","FightingEnergyCard","PsychicEnergyCard","DoubleColorlessEnergyCard",},["Evolution"]={"BulbasaurCard","IvysaurCard","VenusaurLv67Card","CaterpieCard","MetapodCard","ButterfreeCard","WeedleCard","KakunaCard","BeedrillCard","NidokingCard","BellsproutCard","WeepinbellCard","VictreebelCard","CharizardCard","RapidashCard","FlareonLv28Card","SquirtleCard","WartortleCard","BlastoiseCard","KrabbyCard","KinglerCard","StarmieCard","VaporeonLv42Card","JolteonLv29Card","SandshrewCard","SandslashCard","MachokeCard","MachampCard","GeodudeCard","GravelerCard","GolemCard","CuboneCard","MarowakLv32Card","GastlyLv8Card","HaunterLv22Card","GengarCard","JynxCard","PidgeyCard","PidgeottoCard","PidgeotLv40Card","JigglypuffLv13Card","EeveeCard","PokemonTraderCard","PokemonBreederCard","ClefairyDollCard","EnergyRetrievalCard","EnergySearchCard","GustOfWindCard","SuperPotionCard","PokemonFluteCard",},["Laboratory"]={"EkansCard","ArbokCard","ZubatCard","GolbatCard","VenonatCard","VenomothCard","GrimerCard","MukCard","KoffingCard","WeezingCard","TangelaLv8Card","NinetalesLv35Card","MagmarLv31Card","PsyduckCard","GolduckCard","PoliwagCard","PoliwhirlCard","PoliwrathCard","TentacoolCard","TentacruelCard","HorseaCard","SeadraCard","MagnemiteLv15Card","MagnetonLv35Card","ElectrodeLv35Card","OnixCard","MarowakLv26Card","HitmonleeCard","SlowpokeLv18Card","SlowbroCard","GastlyLv17Card","HaunterLv17Card","HypnoCard","MrMimeCard","MewtwoLv53Card","PidgeotLv38Card","SpearowCard","FearowCard","ClefableCard","DoduoCard","DodrioCard","DittoCard","PorygonCard","ImposterProfessorOakCard","LassCard","SuperEnergyRemovalCard","PokedexCard","DevolutionSprayCard","MaintenanceCard","GamblerCard","RecycleCard",},["Mystery"]={"NidoranFCard","NidorinaCard","NidoqueenCard","OddishCard","GloomCard","VileplumeCard","ParasCard","ParasectCard","ExeggcuteCard","ExeggutorCard","VulpixCard","NinetalesLv32Card","FlareonLv22Card","MoltresLv35Card","ShellderCard","CloysterCard","LaprasCard","VaporeonLv29Card","OmanyteCard","OmastarCard","ArticunoLv35Card","PikachuLv14Card","RaichuLv45Card","VoltorbCard","ElectrodeLv42Card","JolteonLv24Card","ZapdosLv40Card","MankeyCard","PrimeapeCard","RhyhornCard","RhydonCard","KabutoCard","KabutopsCard","AerodactylCard","AlakazamCard","DrowzeeCard","MewLv23Card","ClefairyCard","MeowthLv15Card","PersianCard","FarfetchdCard","LickitungCard","TaurosCard","DratiniCard","DragonairCard","DragoniteLv45Card","MrFujiCard","MysteriousFossilCard","EnergyRemovalCard","PokemonCenterCard",},["Promotional"]={"VenusaurLv64Card","ArcanineLv34Card","MoltresLv37Card","ArticunoLv37Card","PikachuLv16Card","PikachuAltLv16Card","FlyingPikachuCard","SurfingPikachuLv13Card","SurfingPikachuAltLv13Card","ElectabuzzLv20Card","ZapdosLv68Card","SlowpokeLv9Card","MewtwoLv60Card","MewtwoAltLV60Card","MewLv8Card","MewLv15Card","JigglypuffLv12Card","DragoniteLv41Card","ImakuniCard","SuperEnergyRetrievalCard",},}
  local TCG_BOOSTERS={["rarity_slots"]={["COLOSSEUM"]={["commons"]=5,["energies"]=1,["rares"]=1,["uncommons"]=3,},["EVOLUTION"]={["commons"]=5,["energies"]=1,["rares"]=1,["uncommons"]=3,},["LABORATORY"]={["commons"]=6,["energies"]=0,["rares"]=1,["uncommons"]=3,},["MYSTERY"]={["commons"]=6,["energies"]=0,["rares"]=1,["uncommons"]=3,},},["variants"]={["BoosterPack_ColosseumFighting"]={["booster_set"]="COLOSSEUM",["energy_source"]="FIGHTING_ENERGY",["type_chances"]={["Colorless"]=16,["Energy"]=0,["Fighting"]=48,["Fire"]=16,["Grass"]=16,["Lightning"]=16,["Psychic"]=16,["Trainer"]=16,["Water"]=16,},},["BoosterPack_ColosseumFire"]={["booster_set"]="COLOSSEUM",["energy_source"]="FIRE_ENERGY",["type_chances"]={["Colorless"]=16,["Energy"]=0,["Fighting"]=16,["Fire"]=48,["Grass"]=16,["Lightning"]=16,["Psychic"]=16,["Trainer"]=16,["Water"]=16,},},["BoosterPack_ColosseumGrass"]={["booster_set"]="COLOSSEUM",["energy_source"]="GRASS_ENERGY",["type_chances"]={["Colorless"]=16,["Energy"]=0,["Fighting"]=16,["Fire"]=16,["Grass"]=48,["Lightning"]=16,["Psychic"]=16,["Trainer"]=16,["Water"]=16,},},["BoosterPack_ColosseumLightning"]={["booster_set"]="COLOSSEUM",["energy_source"]="LIGHTNING_ENERGY",["type_chances"]={["Colorless"]=16,["Energy"]=0,["Fighting"]=16,["Fire"]=16,["Grass"]=16,["Lightning"]=48,["Psychic"]=16,["Trainer"]=16,["Water"]=16,},},["BoosterPack_ColosseumNeutral"]={["booster_set"]="COLOSSEUM",["energy_source"]="GenerateRandomEnergy",["type_chances"]={["Colorless"]=20,["Energy"]=0,["Fighting"]=20,["Fire"]=20,["Grass"]=20,["Lightning"]=20,["Psychic"]=20,["Trainer"]=20,["Water"]=20,},},["BoosterPack_ColosseumTrainer"]={["booster_set"]="COLOSSEUM",["energy_source"]="GenerateRandomEnergy",["type_chances"]={["Colorless"]=16,["Energy"]=0,["Fighting"]=16,["Fire"]=16,["Grass"]=16,["Lightning"]=16,["Psychic"]=16,["Trainer"]=48,["Water"]=16,},},["BoosterPack_ColosseumWater"]={["booster_set"]="COLOSSEUM",["energy_source"]="WATER_ENERGY",["type_chances"]={["Colorless"]=16,["Energy"]=0,["Fighting"]=16,["Fire"]=16,["Grass"]=16,["Lightning"]=16,["Psychic"]=16,["Trainer"]=16,["Water"]=48,},},["BoosterPack_EnergyGrassPsychic"]={["booster_set"]="COLOSSEUM",["energy_source"]="GenerateEnergyBoosterGrassPsychic",["type_chances"]={["Colorless"]=0,["Energy"]=0,["Fighting"]=0,["Fire"]=0,["Grass"]=0,["Lightning"]=0,["Psychic"]=0,["Trainer"]=0,["Water"]=0,},},["BoosterPack_EnergyLightningFire"]={["booster_set"]="COLOSSEUM",["energy_source"]="GenerateEnergyBoosterLightningFire",["type_chances"]={["Colorless"]=0,["Energy"]=0,["Fighting"]=0,["Fire"]=0,["Grass"]=0,["Lightning"]=0,["Psychic"]=0,["Trainer"]=0,["Water"]=0,},},["BoosterPack_EnergyWaterFighting"]={["booster_set"]="COLOSSEUM",["energy_source"]="GenerateEnergyBoosterWaterFighting",["type_chances"]={["Colorless"]=0,["Energy"]=0,["Fighting"]=0,["Fire"]=0,["Grass"]=0,["Lightning"]=0,["Psychic"]=0,["Trainer"]=0,["Water"]=0,},},["BoosterPack_EvolutionFighting"]={["booster_set"]="EVOLUTION",["energy_source"]="FIGHTING_ENERGY",["type_chances"]={["Colorless"]=16,["Energy"]=0,["Fighting"]=48,["Fire"]=16,["Grass"]=16,["Lightning"]=16,["Psychic"]=16,["Trainer"]=16,["Water"]=16,},},["BoosterPack_EvolutionGrass"]={["booster_set"]="EVOLUTION",["energy_source"]="GRASS_ENERGY",["type_chances"]={["Colorless"]=16,["Energy"]=0,["Fighting"]=16,["Fire"]=16,["Grass"]=48,["Lightning"]=16,["Psychic"]=16,["Trainer"]=16,["Water"]=16,},},["BoosterPack_EvolutionNeutral"]={["booster_set"]="EVOLUTION",["energy_source"]="GenerateRandomEnergy",["type_chances"]={["Colorless"]=20,["Energy"]=0,["Fighting"]=20,["Fire"]=20,["Grass"]=20,["Lightning"]=20,["Psychic"]=20,["Trainer"]=20,["Water"]=20,},},["BoosterPack_EvolutionNeutralFireEnergy"]={["booster_set"]="EVOLUTION",["energy_source"]="FIRE_ENERGY",["type_chances"]={["Colorless"]=20,["Energy"]=0,["Fighting"]=20,["Fire"]=20,["Grass"]=20,["Lightning"]=20,["Psychic"]=20,["Trainer"]=20,["Water"]=20,},},["BoosterPack_EvolutionPsychic"]={["booster_set"]="EVOLUTION",["energy_source"]="PSYCHIC_ENERGY",["type_chances"]={["Colorless"]=16,["Energy"]=0,["Fighting"]=16,["Fire"]=16,["Grass"]=16,["Lightning"]=16,["Psychic"]=48,["Trainer"]=16,["Water"]=16,},},["BoosterPack_EvolutionTrainer"]={["booster_set"]="EVOLUTION",["energy_source"]="GenerateRandomEnergy",["type_chances"]={["Colorless"]=16,["Energy"]=0,["Fighting"]=16,["Fire"]=16,["Grass"]=16,["Lightning"]=16,["Psychic"]=16,["Trainer"]=48,["Water"]=16,},},["BoosterPack_EvolutionWater"]={["booster_set"]="EVOLUTION",["energy_source"]="WATER_ENERGY",["type_chances"]={["Colorless"]=16,["Energy"]=0,["Fighting"]=16,["Fire"]=16,["Grass"]=16,["Lightning"]=16,["Psychic"]=16,["Trainer"]=16,["Water"]=48,},},["BoosterPack_LaboratoryGrass"]={["booster_set"]="LABORATORY",["energy_source"]="NULL",["type_chances"]={["Colorless"]=16,["Energy"]=0,["Fighting"]=16,["Fire"]=16,["Grass"]=48,["Lightning"]=16,["Psychic"]=16,["Trainer"]=16,["Water"]=16,},},["BoosterPack_LaboratoryMostlyNeutral"]={["booster_set"]="LABORATORY",["energy_source"]="NULL",["type_chances"]={["Colorless"]=20,["Energy"]=0,["Fighting"]=16,["Fire"]=20,["Grass"]=20,["Lightning"]=20,["Psychic"]=20,["Trainer"]=24,["Water"]=20,},},["BoosterPack_LaboratoryPsychic"]={["booster_set"]="LABORATORY",["energy_source"]="NULL",["type_chances"]={["Colorless"]=16,["Energy"]=0,["Fighting"]=16,["Fire"]=16,["Grass"]=16,["Lightning"]=16,["Psychic"]=48,["Trainer"]=16,["Water"]=16,},},["BoosterPack_LaboratoryTrainer"]={["booster_set"]="LABORATORY",["energy_source"]="NULL",["type_chances"]={["Colorless"]=16,["Energy"]=0,["Fighting"]=16,["Fire"]=16,["Grass"]=16,["Lightning"]=16,["Psychic"]=16,["Trainer"]=48,["Water"]=16,},},["BoosterPack_LaboratoryWater"]={["booster_set"]="LABORATORY",["energy_source"]="NULL",["type_chances"]={["Colorless"]=16,["Energy"]=0,["Fighting"]=16,["Fire"]=16,["Grass"]=16,["Lightning"]=16,["Psychic"]=16,["Trainer"]=16,["Water"]=48,},},["BoosterPack_MysteryFightingColorless"]={["booster_set"]="MYSTERY",["energy_source"]="NULL",["type_chances"]={["Colorless"]=22,["Energy"]=12,["Fighting"]=48,["Fire"]=12,["Grass"]=12,["Lightning"]=12,["Psychic"]=12,["Trainer"]=12,["Water"]=12,},},["BoosterPack_MysteryGrassColorless"]={["booster_set"]="MYSTERY",["energy_source"]="NULL",["type_chances"]={["Colorless"]=22,["Energy"]=12,["Fighting"]=12,["Fire"]=12,["Grass"]=48,["Lightning"]=12,["Psychic"]=12,["Trainer"]=12,["Water"]=12,},},["BoosterPack_MysteryLightningColorless"]={["booster_set"]="MYSTERY",["energy_source"]="NULL",["type_chances"]={["Colorless"]=22,["Energy"]=12,["Fighting"]=12,["Fire"]=12,["Grass"]=12,["Lightning"]=48,["Psychic"]=12,["Trainer"]=12,["Water"]=12,},},["BoosterPack_MysteryNeutral"]={["booster_set"]="MYSTERY",["energy_source"]="NULL",["type_chances"]={["Colorless"]=17,["Energy"]=17,["Fighting"]=17,["Fire"]=17,["Grass"]=17,["Lightning"]=17,["Psychic"]=17,["Trainer"]=17,["Water"]=17,},},["BoosterPack_MysteryTrainerColorless"]={["booster_set"]="MYSTERY",["energy_source"]="NULL",["type_chances"]={["Colorless"]=22,["Energy"]=12,["Fighting"]=12,["Fire"]=12,["Grass"]=12,["Lightning"]=12,["Psychic"]=12,["Trainer"]=48,["Water"]=12,},},["BoosterPack_MysteryWaterColorless"]={["booster_set"]="MYSTERY",["energy_source"]="NULL",["type_chances"]={["Colorless"]=22,["Energy"]=12,["Fighting"]=12,["Fire"]=12,["Grass"]=12,["Lightning"]=12,["Psychic"]=12,["Trainer"]=12,["Water"]=48,},},["BoosterPack_RandomEnergies"]={["booster_set"]="COLOSSEUM",["energy_source"]="GenerateRandomEnergyBooster",["type_chances"]={["Colorless"]=0,["Energy"]=0,["Fighting"]=0,["Fire"]=0,["Grass"]=0,["Lightning"]=0,["Psychic"]=0,["Trainer"]=0,["Water"]=0,},},},}
  local TCG_DB={["Colosseum"]={{["attacks"]={{["damage"]=30,["description"]="Flip a coin. If tails, this attack does nothing.",["effect_fn"]="NidoranMHornHazardEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="Attack",["name"]="Horn Hazard",},},["card_type"]="Grass",["hp"]=40,["label"]="NidoranMCard",["name"]="Nidoran♂",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=30,["description"]="Flip 2 coins. This attack does 30 damage times the number of heads.",["effect_fn"]="NidorinoDoubleKickEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},{["count"]=2,["type"]="Colorless",},},["kind"]="DAMAGE_X",["name"]="Double Kick",},{["damage"]=50,["energy_cost"]={{["count"]=2,["type"]="Grass",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Horn Drill",},},["card_type"]="Grass",["evolves_from"]="Nidoran♂",["hp"]=60,["label"]="NidorinoCard",["name"]="Nidorino",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Psychic",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="TangelaStunSporeEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="Attack",["name"]="Stun Spore",},{["damage"]=10,["description"]="The Defending Pokémon is now Poisoned.",["effect_fn"]="TangelaPoisonWhipEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Poison Whip",},},["card_type"]="Grass",["hp"]=50,["label"]="TangelaLv12Card",["name"]="Tangela",["rarity"]="Common",["retreat_cost"]=2,["stage"]="Basic",["weakness"]="Fire",},{["attacks"]={{["damage"]=0,["description"]="During your next turn, Scyther's Slash attack's base damage is doubled.",["effect_fn"]="ScytherSwordsDanceEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="RESIDUAL",["name"]="Swords Dance",},{["damage"]=30,["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Slash",},},["card_type"]="Grass",["hp"]=70,["label"]="ScytherCard",["name"]="Scyther",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=0,["stage"]="Basic",["weakness"]="Fire",},{["attacks"]={{["damage"]=20,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="PinsirIronGripEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},},["kind"]="Attack",["name"]="Irongrip",},{["damage"]=50,["energy_cost"]={{["count"]=2,["type"]="Grass",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Guillotine",},},["card_type"]="Grass",["hp"]=60,["label"]="PinsirCard",["name"]="Pinsir",["rarity"]="Rare",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fire",},{["attacks"]={{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Scratch",},{["damage"]=30,["description"]="Discard 1 <FIRE> Energy card attached to Charmander in order to use this attack.",["effect_fn"]="CharmanderEmberEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Fire",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Ember",},},["card_type"]="Fire",["hp"]=50,["label"]="CharmanderCard",["name"]="Charmander",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Water",},{["attacks"]={{["damage"]=30,["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Slash",},{["damage"]=50,["description"]="Discard 1 <FIRE> Energy card attached to Charmeleon in order to use this attack.",["effect_fn"]="CharmeleonFlamethrowerEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fire",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Flamethrower",},},["card_type"]="Fire",["evolves_from"]="Charmander",["hp"]=80,["label"]="CharmeleonCard",["name"]="Charmeleon",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Water",},{["attacks"]={{["damage"]=20,["energy_cost"]={{["count"]=1,["type"]="Fire",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Flare",},},["card_type"]="Fire",["hp"]=60,["label"]="GrowlitheCard",["name"]="Growlithe",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Water",},{["attacks"]={{["damage"]=50,["description"]="Discard 1 <FIRE> Energy card attached to Arcanine in order to use this attack.",["effect_fn"]="ArcanineFlamethrowerEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fire",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Flamethrower",},{["damage"]=80,["description"]="Arcanine does 30 damage to itself.",["effect_fn"]="ArcanineTakeDownEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fire",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Take Down",},},["card_type"]="Fire",["evolves_from"]="Growlithe",["hp"]=100,["label"]="ArcanineLv45Card",["name"]="Arcanine",["rarity"]="Uncommon",["retreat_cost"]=3,["stage"]="Stage 1",["weakness"]="Water",},{["attacks"]={{["damage"]=20,["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Smash Kick",},{["damage"]=30,["energy_cost"]={{["count"]=2,["type"]="Fire",},},["kind"]="Attack",["name"]="Flame Tail",},},["card_type"]="Fire",["hp"]=40,["label"]="PonytaCard",["name"]="Ponyta",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Water",},{["attacks"]={{["damage"]=30,["energy_cost"]={{["count"]=2,["type"]="Fire",},},["kind"]="Attack",["name"]="Fire Punch",},{["damage"]=50,["description"]="Discard 1 <FIRE> Energy card attached to Magmar in order to use this attack.",["effect_fn"]="MagmarFlamethrowerEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fire",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Flamethrower",},},["card_type"]="Fire",["hp"]=50,["label"]="MagmarLv24Card",["name"]="Magmar",["rarity"]="Uncommon",["retreat_cost"]=2,["stage"]="Basic",["weakness"]="Water",},{["attacks"]={{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="Attack",["name"]="Headbutt",},},["card_type"]="Water",["hp"]=60,["label"]="SeelCard",["name"]="Seel",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Lightning",},{["attacks"]={{["damage"]=50,["energy_cost"]={{["count"]=2,["type"]="Water",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Aurora Beam",},{["damage"]=30,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="DewgongIceBeamEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Water",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Ice Beam",},},["card_type"]="Water",["evolves_from"]="Seel",["hp"]=80,["label"]="DewgongCard",["name"]="Dewgong",["rarity"]="Uncommon",["retreat_cost"]=3,["stage"]="Stage 1",["weakness"]="Lightning",},{["attacks"]={{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="Attack",["name"]="Horn Attack",},},["card_type"]="Water",["hp"]=40,["label"]="GoldeenCard",["name"]="Goldeen",["rarity"]="Common",["retreat_cost"]=0,["stage"]="Basic",["weakness"]="Lightning",},{["attacks"]={{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="Attack",["name"]="Horn Attack",},{["damage"]=30,["energy_cost"]={{["count"]=1,["type"]="Water",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Waterfall",},},["card_type"]="Water",["evolves_from"]="Goldeen",["hp"]=70,["label"]="SeakingCard",["name"]="Seaking",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Lightning",},{["attacks"]={{["damage"]=20,["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="Attack",["name"]="Slap",},},["card_type"]="Water",["hp"]=40,["label"]="StaryuCard",["name"]="Staryu",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Lightning",},{["attacks"]={{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Tackle",},{["damage"]=10,["description"]="Does 10 damage times the number of damage counters on Magikarp.",["effect_fn"]="MagikarpFlailEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="DAMAGE_X",["name"]="Flail",},},["card_type"]="Water",["hp"]=30,["label"]="MagikarpCard",["name"]="Magikarp",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Lightning",},{["attacks"]={{["damage"]=50,["energy_cost"]={{["count"]=3,["type"]="Water",},},["kind"]="Attack",["name"]="Dragon Rage",},{["damage"]=40,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="GyaradosBubblebeamEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Water",},},["kind"]="Attack",["name"]="Bubblebeam",},},["card_type"]="Water",["evolves_from"]="Magikarp",["hp"]=100,["label"]="GyaradosCard",["name"]="Gyarados",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=3,["stage"]="Stage 1",["weakness"]="Grass",},{["attacks"]={{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Gnaw",},{["damage"]=30,["description"]="Flip a coin. If tails, Pikachu does 10 damage to itself.",["effect_fn"]="PikachuThunderJoltEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Lightning",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Thunder Jolt",},},["card_type"]="Lightning",["hp"]=40,["label"]="PikachuLv12Card",["name"]="Pikachu",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=20,["description"]="Flip a coin. If heads, during your opponent's next turn, prevent all effects of attacks, including damage, done to Raichu.",["effect_fn"]="RaichuAgilityEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Lightning",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Agility",},{["damage"]=60,["description"]="Flip a coin. If tails, Raichu does 30 damage to itself.",["effect_fn"]="RaichuThunderEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Lightning",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Thunder",},},["card_type"]="Lightning",["evolves_from"]="Pikachu",["hp"]=80,["label"]="RaichuLv40Card",["name"]="Raichu",["rarity"]="Rare",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Fighting",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="MagnemiteThunderWaveEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Lightning",},},["kind"]="Attack",["name"]="Thunder Wave",},{["damage"]=40,["description"]="Does 10 damage to each Pokémon on each player's Bench. (Don't apply Weakness and Resistance for Benched Pokémon.) Magnemite does 40 damage to itself.",["effect_fn"]="MagnemiteSelfdestructEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Lightning",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Selfdestruct",},},["card_type"]="Lightning",["hp"]=40,["label"]="MagnemiteLv13Card",["name"]="Magnemite",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=30,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="MagnetonThunderWaveEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Lightning",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Thunder Wave",},{["damage"]=80,["description"]="Does 20 damage to each Pokémon on each player's Bench. (Don't apply Weakness and Resistance for Benched Pokémon.) Magneton does 80 damage to itself.",["effect_fn"]="MagnetonLv28SelfdestructEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Lightning",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Selfdestruct",},},["card_type"]="Lightning",["evolves_from"]="Magnemite",["hp"]=60,["label"]="MagnetonLv28Card",["name"]="Magneton",["rarity"]="Rare",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Fighting",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="ElectabuzzThundershockEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Lightning",},},["kind"]="Attack",["name"]="Thundershock",},{["damage"]=30,["description"]="Flip a coin. If heads, this attack does 30 damage plus 10 more damage; if tails, this attack does 30 damage and Electabuzz does 10 damage to itself.",["effect_fn"]="ElectabuzzThunderpunchEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Lightning",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Thunderpunch",},},["card_type"]="Lightning",["hp"]=70,["label"]="ElectabuzzLv35Card",["name"]="Electabuzz",["rarity"]="Rare",["retreat_cost"]=2,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=60,["description"]="Flip a coin. If tails, Zapdos does 30 damage to itself.",["effect_fn"]="ZapdosThunderEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Lightning",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Thunder",},{["damage"]=100,["description"]="Discard all Energy cards attached to Zapdos in order to use this attack.",["effect_fn"]="ZapdosThunderboltEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Lightning",},},["kind"]="Attack",["name"]="Thunderbolt",},},["card_type"]="Lightning",["hp"]=90,["label"]="ZapdosLv64Card",["name"]="Zapdos",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=3,["stage"]="Basic",},{["attacks"]={{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Fighting",},},["kind"]="Attack",["name"]="Dig",},{["damage"]=30,["energy_cost"]={{["count"]=2,["type"]="Fighting",},},["kind"]="Attack",["name"]="Mud Slap",},},["card_type"]="Fighting",["hp"]=30,["label"]="DiglettCard",["name"]="Diglett",["rarity"]="Common",["resistance"]="Lightning",["retreat_cost"]=0,["stage"]="Basic",["weakness"]="Grass",},{["attacks"]={{["damage"]=40,["energy_cost"]={{["count"]=2,["type"]="Fighting",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Slash",},{["damage"]=70,["description"]="Does 10 damage to each of your own Benched Pokémon. (Don't apply Weakness and Resistance for Benched Pokémon.)",["effect_fn"]="DugtrioEarthquakeEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Fighting",},},["kind"]="Attack",["name"]="Earthquake",},},["card_type"]="Fighting",["evolves_from"]="Diglett",["hp"]=70,["label"]="DugtrioCard",["name"]="Dugtrio",["rarity"]="Rare",["resistance"]="Lightning",["retreat_cost"]=2,["stage"]="Stage 1",["weakness"]="Grass",},{["attacks"]={{["damage"]=20,["energy_cost"]={{["count"]=1,["type"]="Fighting",},},["kind"]="Attack",["name"]="Low Kick",},},["card_type"]="Fighting",["hp"]=50,["label"]="MachopCard",["name"]="Machop",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=20,["energy_cost"]={{["count"]=1,["type"]="Fighting",},},["kind"]="Attack",["name"]="Jab",},{["damage"]=40,["energy_cost"]={{["count"]=2,["type"]="Fighting",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Special Punch",},},["card_type"]="Fighting",["hp"]=70,["label"]="HitmonchanCard",["name"]="Hitmonchan",["rarity"]="Rare",["retreat_cost"]=2,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="AbraPsyshockEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},},["kind"]="Attack",["name"]="Psyshock",},},["card_type"]="Psychic",["hp"]=30,["label"]="AbraCard",["name"]="Abra",["rarity"]="Common",["retreat_cost"]=0,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=0,["description"]="Discard 1 <PSYCHIC> Energy card attached to Kadabra in order to use this attack. Remove all damage counters from Kadabra.",["effect_fn"]="KadabraRecoverEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Psychic",},},["kind"]="RESIDUAL",["name"]="Recover",},{["damage"]=50,["energy_cost"]={{["count"]=2,["type"]="Psychic",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Super Psy",},},["card_type"]="Psychic",["evolves_from"]="Abra",["hp"]=60,["label"]="KadabraCard",["name"]="Kadabra",["rarity"]="Uncommon",["retreat_cost"]=3,["stage"]="Stage 1",["weakness"]="Psychic",},{["attacks"]={{["damage"]=20,["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Bite",},},["card_type"]="Colorless",["hp"]=30,["label"]="RattataCard",["name"]="Rattata",["rarity"]="Common",["resistance"]="Psychic",["retreat_cost"]=0,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=20,["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Bite",},{["damage"]=0,["description"]="Does damage to the Defending Pokémon equal to half the Defending Pokémon's remaining HP (rounded up to the nearest 10).",["effect_fn"]="RaticateSuperFangEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Super Fang",},},["card_type"]="Colorless",["evolves_from"]="Rattata",["hp"]=60,["label"]="RaticateCard",["name"]="Raticate",["rarity"]="Uncommon",["resistance"]="Psychic",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Fighting",},{["attacks"]={{["damage"]=0,["description"]="The Defending Pokémon is now Asleep.",["effect_fn"]="JigglypuffLullabyEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Lullaby",},{["damage"]=20,["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Pound",},},["card_type"]="Colorless",["hp"]=60,["label"]="JigglypuffLv14Card",["name"]="Jigglypuff",["rarity"]="Common",["resistance"]="Psychic",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=0,["description"]="The Defending Pokémon is now Asleep.",["effect_fn"]="WigglytuffLullabyEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Lullaby",},{["damage"]=10,["description"]="Does 10 damage plus 10 more damage for each of your Benched Pokémon.",["effect_fn"]="WigglytuffDoTheWaveEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Do the Wave",},},["card_type"]="Colorless",["evolves_from"]="Jigglypuff",["hp"]=80,["label"]="WigglytuffCard",["name"]="Wigglytuff",["rarity"]="Rare",["resistance"]="Psychic",["retreat_cost"]=2,["stage"]="Stage 1",["weakness"]="Fighting",},{["attacks"]={{["damage"]=0,["description"]="Does 20 damage to 1 of your opponent's Pokémon chosen at random. Don't apply Weakness and Resistance for this attack. (Any other effects that would happen after applying Weakness and Resistance still happen.)",["effect_fn"]="MeowthCatPunchEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Cat Punch",},},["card_type"]="Colorless",["hp"]=50,["label"]="MeowthLv14Card",["name"]="Meowth",["rarity"]="Common",["resistance"]="Psychic",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=0,["description"]="Flip a coin. If heads, prevent all damage done to Chansey during your opponent's next turn. (Any other effects of attacks still happen.)",["effect_fn"]="ChanseyScrunchEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Scrunch",},{["damage"]=80,["description"]="Chansey does 80 damage to itself.",["effect_fn"]="ChanseyDoubleEdgeEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Colorless",},},["kind"]="Attack",["name"]="Double-edge",},},["card_type"]="Colorless",["hp"]=120,["label"]="ChanseyCard",["name"]="Chansey",["rarity"]="Rare",["resistance"]="Psychic",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=0,["description"]="Draw a card.",["effect_fn"]="KangaskhanFetchEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Fetch",},{["damage"]=20,["description"]="Flip 4 coins. This attack does 20 damage times the number of heads.",["effect_fn"]="KangaskhanCometPunchEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Colorless",},},["kind"]="DAMAGE_X",["name"]="Comet Punch",},},["card_type"]="Colorless",["hp"]=90,["label"]="KangaskhanCard",["name"]="Kangaskhan",["rarity"]="Rare",["resistance"]="Psychic",["retreat_cost"]=3,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=0,["description"]="Snorlax can't become Asleep, Confused, Paralyzed, or Poisoned. This power can't be used if Snorlax is already Asleep, Confused, or Paralyzed.",["effect_fn"]="SnorlaxThickSkinnedEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Thick Skinned",},{["damage"]=30,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="SnorlaxBodySlamEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Colorless",},},["kind"]="Attack",["name"]="Body Slam",},},["card_type"]="Colorless",["hp"]=90,["label"]="SnorlaxCard",["name"]="Snorlax",["rarity"]="Rare",["resistance"]="Psychic",["retreat_cost"]=4,["stage"]="Basic",["weakness"]="Fighting",},{["card_type"]="Trainer",["description"]="Discard your hand, then draw 7 cards.",["effect_fn"]="ProfessorOakEffectCommands",["label"]="ProfessorOakCard",["name"]="Professor Oak",["rarity"]="Uncommon",},{["card_type"]="Trainer",["description"]="Draw 2 cards.",["effect_fn"]="BillEffectCommands",["label"]="BillCard",["name"]="Bill",["rarity"]="Common",},{["card_type"]="Trainer",["description"]="Switch 1 of your Benched Pokémon with your Active Pokémon.",["effect_fn"]="SwitchEffectCommands",["label"]="SwitchCard",["name"]="Switch",["rarity"]="Common",},{["card_type"]="Trainer",["description"]="Flip a coin. If heads, you may search your deck for any Basic Pokémon or Evolution card. Show that card to your opponent, then put it into your hand. Shuffle your deck afterward.",["effect_fn"]="PokeBallEffectCommands",["label"]="PokeBallCard",["name"]="Poké Ball",["rarity"]="Common",},{["card_type"]="Trainer",["description"]="Choose 1 of your Pokémon in play and return its Basic Pokémon card to your hand. (Discard all cards attached to that card.)",["effect_fn"]="ScoopUpEffectCommands",["label"]="ScoopUpCard",["name"]="Scoop Up",["rarity"]="Rare",},{["card_type"]="Trainer",["description"]="Discard 2 of the other cards from your hand in order to search your deck for any card and put it into your hand. Shuffle your deck afterward.",["effect_fn"]="ComputerSearchEffectCommands",["label"]="ComputerSearchCard",["name"]="Computer Search",["rarity"]="Rare",},{["card_type"]="Trainer",["description"]="Attach PlusPower to your Active Pokémon. At the end of your turn, discard PlusPower. If this Pokémon's attack does damage to any Active Pokémon (after applying Weakness and Resistance), the attack does 10 more damage to that Active Pokémon.",["effect_fn"]="PlusPowerEffectCommands",["label"]="PlusPowerCard",["name"]="PlusPower",["rarity"]="Uncommon",},{["card_type"]="Trainer",["description"]="Attach Defender to 1 of your Pokémon. At the end of your opponent's next turn, discard Defender. Damage done to that Pokémon by attacks is reduced by 20 (after applying Weakness and Resistance).",["effect_fn"]="DefenderEffectCommands",["label"]="DefenderCard",["name"]="Defender",["rarity"]="Uncommon",},{["card_type"]="Trainer",["description"]="Discard 2 of the other cards from your hand in order to put a Trainer card from your discard pile into your hand.",["effect_fn"]="ItemFinderEffectCommands",["label"]="ItemFinderCard",["name"]="Item Finder",["rarity"]="Rare",},{["card_type"]="Trainer",["description"]="Remove 2 damage counters from 1 of your Pokémon. If that Pokémon has fewer damage counters than that, remove all of them.",["effect_fn"]="PotionEffectCommands",["label"]="PotionCard",["name"]="Potion",["rarity"]="Common",},{["card_type"]="Trainer",["description"]="Your Active Pokémon is no longer Asleep, Confused, Paralyzed, or Poisoned.",["effect_fn"]="FullHealEffectCommands",["label"]="FullHealCard",["name"]="Full Heal",["rarity"]="Uncommon",},{["card_type"]="Trainer",["description"]="Put 1 Basic Pokémon card from your discard pile onto your Bench. Put damage counters on that Pokémon equal to half its HP (rounded down to the nearest 10). (You can't play Revive if your Bench is full.)",["effect_fn"]="ReviveEffectCommands",["label"]="ReviveCard",["name"]="Revive",["rarity"]="Uncommon",},},["Energy"]={{["card_type"]="Energy (Grass)",["description"]="Provides 1 <GRASS> Energy.",["effect_fn"]="GrassEnergyEffectCommands",["label"]="GrassEnergyCard",["name"]="Grass Energy",["rarity"]="Common",},{["card_type"]="Energy (Fire)",["description"]="Provides 1 <FIRE> Energy.",["effect_fn"]="FireEnergyEffectCommands",["label"]="FireEnergyCard",["name"]="Fire Energy",["rarity"]="Common",},{["card_type"]="Energy (Water)",["description"]="Provides 1 <WATER> Energy.",["effect_fn"]="WaterEnergyEffectCommands",["label"]="WaterEnergyCard",["name"]="Water Energy",["rarity"]="Common",},{["card_type"]="Energy (Lightning)",["description"]="Provides 1 <LIGHTNING> Energy.",["effect_fn"]="LightningEnergyEffectCommands",["label"]="LightningEnergyCard",["name"]="Lightning Energy",["rarity"]="Common",},{["card_type"]="Energy (Fighting)",["description"]="Provides 1 <FIGHTING> Energy.",["effect_fn"]="FightingEnergyEffectCommands",["label"]="FightingEnergyCard",["name"]="Fighting Energy",["rarity"]="Common",},{["card_type"]="Energy (Psychic)",["description"]="Provides 1 <PSYCHIC> Energy.",["effect_fn"]="PsychicEnergyEffectCommands",["label"]="PsychicEnergyCard",["name"]="Psychic Energy",["rarity"]="Common",},{["card_type"]="Energy (Double Colorless)",["description"]="Provides <COLORLESS><COLORLESS> Energy. (Doesn't count as a basic Energy card.)  Colorless Energy can't be used to pay colored Energy costs. (Any type of Energy can be used to pay Colorless Energy costs.)",["effect_fn"]="DoubleColorlessEnergyEffectCommands",["label"]="DoubleColorlessEnergyCard",["name"]="Double Colorless Energy",["rarity"]="Uncommon",},},["Evolution"]={{["attacks"]={{["damage"]=20,["description"]="Unless all damage from this attack is prevented, you may remove 1 damage counter from Bulbasaur.",["effect_fn"]="BulbasaurLeechSeedEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},},["kind"]="Attack",["name"]="Leech Seed",},},["card_type"]="Grass",["hp"]=40,["label"]="BulbasaurCard",["name"]="Bulbasaur",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fire",},{["attacks"]={{["damage"]=30,["energy_cost"]={{["count"]=1,["type"]="Grass",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Vine Whip",},{["damage"]=20,["description"]="The Defending Pokémon is now Poisoned.",["effect_fn"]="IvysaurPoisonPowderEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Grass",},},["kind"]="Attack",["name"]="Poisonpowder",},},["card_type"]="Grass",["evolves_from"]="Bulbasaur",["hp"]=60,["label"]="IvysaurCard",["name"]="Ivysaur",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Fire",},{["attacks"]={{["damage"]=0,["description"]="As often as you like during your turn (before your attack), you may take 1 <GRASS> Energy card attached to 1 of your Pokémon and attach it to a different one. This power can't be used if Venusaur is Asleep, Confused, or Paralyzed.",["effect_fn"]="VenusaurEnergyTransEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Energy Trans",},{["damage"]=60,["energy_cost"]={{["count"]=4,["type"]="Grass",},},["kind"]="Attack",["name"]="Solarbeam",},},["card_type"]="Grass",["evolves_from"]="Ivysaur",["hp"]=100,["label"]="VenusaurLv67Card",["name"]="Venusaur",["rarity"]="Rare",["retreat_cost"]=2,["stage"]="Stage 2",["weakness"]="Fire",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="CaterpieStringShotEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="Attack",["name"]="String Shot",},},["card_type"]="Grass",["hp"]=40,["label"]="CaterpieCard",["name"]="Caterpie",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fire",},{["attacks"]={{["damage"]=0,["description"]="Flip a coin. If heads, prevent all damage done to Metapod during your opponent's next turn. (Any other effects of attacks still happen.)",["effect_fn"]="MetapodStiffenEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Stiffen",},{["damage"]=20,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="MetapodStunSporeEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},},["kind"]="Attack",["name"]="Stun Spore",},},["card_type"]="Grass",["evolves_from"]="Caterpie",["hp"]=70,["label"]="MetapodCard",["name"]="Metapod",["rarity"]="Common",["retreat_cost"]=2,["stage"]="Stage 1",["weakness"]="Fire",},{["attacks"]={{["damage"]=20,["description"]="If your opponent has any Benched Pokémon, he or she chooses 1 of them and switches it with the Defending Pokémon. (Do the damage before switching the Pokémon.)",["effect_fn"]="ButterfreeWhirlwindEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Whirlwind",},{["damage"]=40,["description"]="Remove a number of damage counters from Butterfree equal to half the damage done to the Defending Pokémon (after applying Weakness and Resistance) (rounded up to the nearest 10).",["effect_fn"]="ButterfreeMegaDrainEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Grass",},},["kind"]="Attack",["name"]="Mega Drain",},},["card_type"]="Grass",["evolves_from"]="Metapod",["hp"]=70,["label"]="ButterfreeCard",["name"]="Butterfree",["rarity"]="Uncommon",["resistance"]="Fighting",["retreat_cost"]=0,["stage"]="Stage 2",["weakness"]="Fire",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Poisoned.",["effect_fn"]="WeedlePoisonStingEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="Attack",["name"]="Poison Sting",},},["card_type"]="Grass",["hp"]=40,["label"]="WeedleCard",["name"]="Weedle",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fire",},{["attacks"]={{["damage"]=0,["description"]="Flip a coin. If heads, prevent all damage done to Kakuna during your opponent's next turn. (Any other effects of attacks still happen.)",["effect_fn"]="KakunaStiffenEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Stiffen",},{["damage"]=20,["description"]="Flip a coin. If heads, the Defending Pokémon is now Poisoned.",["effect_fn"]="KakunaPoisonPowderEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},},["kind"]="Attack",["name"]="Poisonpowder",},},["card_type"]="Grass",["evolves_from"]="Weedle",["hp"]=80,["label"]="KakunaCard",["name"]="Kakuna",["rarity"]="Uncommon",["retreat_cost"]=2,["stage"]="Stage 1",["weakness"]="Fire",},{["attacks"]={{["damage"]=30,["description"]="Flip 2 coins. This attack does 30 damage times the number of heads.",["effect_fn"]="BeedrillTwineedleEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="DAMAGE_X",["name"]="Twineedle",},{["damage"]=40,["description"]="Flip a coin. If heads, the Defending Pokémon is now Poisoned.",["effect_fn"]="BeedrillPoisonStingEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Grass",},},["kind"]="Attack",["name"]="Poison Sting",},},["card_type"]="Grass",["evolves_from"]="Kakuna",["hp"]=80,["label"]="BeedrillCard",["name"]="Beedrill",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=0,["stage"]="Stage 2",["weakness"]="Fire",},{["attacks"]={{["damage"]=30,["description"]="Flip a coin. If heads, this attack does 30 damage plus 10 more damage; if tails, this attack does 30 damage and Nidoking does 10 damage to itself.",["effect_fn"]="NidokingThrashEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Thrash",},{["damage"]=20,["description"]="The Defending Pokémon is now Poisoned. It now takes 20 Poison damage instead of 10 after each player's turn (even if it was already Poisoned).",["effect_fn"]="NidokingToxicEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Grass",},},["kind"]="Attack",["name"]="Toxic",},},["card_type"]="Grass",["evolves_from"]="Nidorino",["hp"]=90,["label"]="NidokingCard",["name"]="Nidoking",["rarity"]="Rare",["retreat_cost"]=3,["stage"]="Stage 2",["weakness"]="Psychic",},{["attacks"]={{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="Attack",["name"]="Vine Whip",},{["damage"]=0,["description"]="Search your deck for a Basic Pokémon named Bellsprout and put it onto your Bench. Shuffle your deck afterward. (You can't use this attack if your Bench is full.)",["effect_fn"]="BellsproutCallForFamilyEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="RESIDUAL",["name"]="Call for Family",},},["card_type"]="Grass",["hp"]=40,["label"]="BellsproutCard",["name"]="Bellsprout",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fire",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Poisoned.",["effect_fn"]="WeepinbellPoisonPowderEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="Attack",["name"]="Poisonpowder",},{["damage"]=30,["energy_cost"]={{["count"]=2,["type"]="Grass",},},["kind"]="Attack",["name"]="Razor Leaf",},},["card_type"]="Grass",["evolves_from"]="Bellsprout",["hp"]=70,["label"]="WeepinbellCard",["name"]="Weepinbell",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Fire",},{["attacks"]={{["damage"]=0,["description"]="If your opponent has any Benched Pokémon, choose 1 of them and switch it with his or her Active Pokémon.",["effect_fn"]="VictreebelLureEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="RESIDUAL",["name"]="Lure",},{["damage"]=20,["description"]="Flip a coin. If heads, the Defending Pokémon can't retreat during your opponent's next turn.",["effect_fn"]="VictreebelAcidEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},},["kind"]="Attack",["name"]="Acid",},},["card_type"]="Grass",["evolves_from"]="Weepinbell",["hp"]=80,["label"]="VictreebelCard",["name"]="Victreebel",["rarity"]="Rare",["retreat_cost"]=2,["stage"]="Stage 2",["weakness"]="Fire",},{["attacks"]={{["damage"]=0,["description"]="As often as you like during your turn (before your attack), you may turn all Energy attached to Charizard into <FIRE> Energy for the rest of the turn. This power can't be used if Charizard is Asleep, Confused, or Paralyzed.",["effect_fn"]="CharizardEnergyBurnEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Energy Burn",},{["damage"]=100,["description"]="Discard 2 Energy cards attached to Charizard in order to use this attack.",["effect_fn"]="CharizardFireSpinEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Fire",},},["kind"]="Attack",["name"]="Fire Spin",},},["card_type"]="Fire",["evolves_from"]="Charmeleon",["hp"]=120,["label"]="CharizardCard",["name"]="Charizard",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=3,["stage"]="Stage 2",["weakness"]="Water",},{["attacks"]={{["damage"]=20,["description"]="Flip a coin. If heads, this attack does 20 damage plus 10 more damage; if tails, this attack does 20 damage.",["effect_fn"]="RapidashStompEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Stomp",},{["damage"]=30,["description"]="Flip a coin. If heads, during your opponent's next turn, prevent all effects of attacks, including damage, done to Rapidash.",["effect_fn"]="RapidashAgilityEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fire",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Agility",},},["card_type"]="Fire",["evolves_from"]="Ponyta",["hp"]=70,["label"]="RapidashCard",["name"]="Rapidash",["rarity"]="Uncommon",["retreat_cost"]=0,["stage"]="Stage 1",["weakness"]="Water",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, this attack does 10 damage plus 20 more damage; if tails, this attack does 10 damage.",["effect_fn"]="FlareonQuickAttackEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Quick Attack",},{["damage"]=60,["description"]="Discard 1 <FIRE> Energy card attached to Flareon in order to use this attack.",["effect_fn"]="FlareonFlamethrowerEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fire",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Flamethrower",},},["card_type"]="Fire",["evolves_from"]="Eevee",["hp"]=70,["label"]="FlareonLv28Card",["name"]="Flareon",["rarity"]="Rare",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Water",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="SquirtleBubbleEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="Attack",["name"]="Bubble",},{["damage"]=0,["description"]="Flip a coin. If heads, prevent all damage done to Squirtle during your opponent's next turn. (Any other effects of attacks still happen.)",["effect_fn"]="SquirtleWithdrawEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},{["count"]=1,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Withdraw",},},["card_type"]="Water",["hp"]=40,["label"]="SquirtleCard",["name"]="Squirtle",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Lightning",},{["attacks"]={{["damage"]=0,["description"]="Flip a coin. If heads, prevent all damage done to Wartortle during your opponent's next turn. (Any other effects of attacks still happen.)",["effect_fn"]="WartortleWithdrawEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},{["count"]=1,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Withdraw",},{["damage"]=40,["energy_cost"]={{["count"]=1,["type"]="Water",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Bite",},},["card_type"]="Water",["evolves_from"]="Squirtle",["hp"]=70,["label"]="WartortleCard",["name"]="Wartortle",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Lightning",},{["attacks"]={{["damage"]=0,["description"]="As often as you like during your turn (before your attack), you may attach 1 <WATER> Energy card to 1 of your <WATER> Pokémon. (This doesn't use up your 1 Energy card attachment for the turn.)",["effect_fn"]="BlastoiseRainDanceEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Rain Dance",},{["damage"]=40,["description"]="Does 40 damage plus 10 more damage for each <WATER> Energy attached to Blastoise but not used to pay for this attack's Energy cost. You can't add more than 20 damage in this way.",["effect_fn"]="BlastoiseHydroPumpEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Water",},},["kind"]="Attack",["name"]="Hydro Pump",},},["card_type"]="Water",["evolves_from"]="Wartortle",["hp"]=100,["label"]="BlastoiseCard",["name"]="Blastoise",["rarity"]="Rare",["retreat_cost"]=3,["stage"]="Stage 2",["weakness"]="Lightning",},{["attacks"]={{["damage"]=0,["description"]="Search your deck for a Basic Pokémon named Krabby and put it onto your Bench. Shuffle your deck afterward. (You can't use this attack if your Bench is full.)",["effect_fn"]="KrabbyCallForFamilyEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="RESIDUAL",["name"]="Call for Family",},{["damage"]=20,["energy_cost"]={{["count"]=1,["type"]="Water",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Irongrip",},},["card_type"]="Water",["hp"]=50,["label"]="KrabbyCard",["name"]="Krabby",["rarity"]="Common",["retreat_cost"]=2,["stage"]="Basic",["weakness"]="Lightning",},{["attacks"]={{["damage"]=10,["description"]="Does 10 damage times the number of damage counters on Kingler.",["effect_fn"]="KinglerFlailEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="DAMAGE_X",["name"]="Flail",},{["damage"]=40,["energy_cost"]={{["count"]=2,["type"]="Water",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Crabhammer",},},["card_type"]="Water",["evolves_from"]="Krabby",["hp"]=60,["label"]="KinglerCard",["name"]="Kingler",["rarity"]="Uncommon",["retreat_cost"]=3,["stage"]="Stage 1",["weakness"]="Lightning",},{["attacks"]={{["damage"]=0,["description"]="Discard 1 <WATER> Energy card attached to Starmie in order to use this attack. Remove all damage counters from Starmie.",["effect_fn"]="StarmieRecoverEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Water",},},["kind"]="RESIDUAL",["name"]="Recover",},{["damage"]=20,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="StarmieStarFreezeEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Star Freeze",},},["card_type"]="Water",["evolves_from"]="Staryu",["hp"]=60,["label"]="StarmieCard",["name"]="Starmie",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Lightning",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, this attack does 10 damage plus 20 more damage; if tails, this attack does 10 damage.",["effect_fn"]="VaporeonQuickAttackEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Quick Attack",},{["damage"]=30,["description"]="Does 30 damage plus 10 more damage for each <WATER> Energy attached to Vaporeon but not used to pay for this attack's Energy cost. You can't add more than 20 damage in this way.",["effect_fn"]="VaporeonWaterGunEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Water",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Water Gun",},},["card_type"]="Water",["evolves_from"]="Eevee",["hp"]=80,["label"]="VaporeonLv42Card",["name"]="Vaporeon",["rarity"]="Rare",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Lightning",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, this attack does 10 damage plus 20 more damage; if tails, this attack does 10 damage.",["effect_fn"]="JolteonQuickAttackEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Quick Attack",},{["damage"]=20,["description"]="Flip 4 coins. This attack does 20 damage times the number of heads.",["effect_fn"]="JolteonPinMissileEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Lightning",},{["count"]=1,["type"]="Colorless",},},["kind"]="DAMAGE_X",["name"]="Pin Missile",},},["card_type"]="Lightning",["evolves_from"]="Eevee",["hp"]=70,["label"]="JolteonLv29Card",["name"]="Jolteon",["rarity"]="Rare",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Fighting",},{["attacks"]={{["damage"]=10,["description"]="If the Defending Pokémon tries to attack during your opponent's next turn, your opponent flips a coin. If tails, that attack does nothing.",["effect_fn"]="SandshrewSandAttackEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Fighting",},},["kind"]="Attack",["name"]="Sand-attack",},},["card_type"]="Fighting",["hp"]=40,["label"]="SandshrewCard",["name"]="Sandshrew",["rarity"]="Common",["resistance"]="Lightning",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Grass",},{["attacks"]={{["damage"]=20,["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Slash",},{["damage"]=20,["description"]="Flip 3 coins. This attack does 20 damage times the number of heads.",["effect_fn"]="SandslashFurySwipesEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fighting",},},["kind"]="DAMAGE_X",["name"]="Fury Swipes",},},["card_type"]="Fighting",["evolves_from"]="Sandshrew",["hp"]=70,["label"]="SandslashCard",["name"]="Sandslash",["rarity"]="Uncommon",["resistance"]="Lightning",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Grass",},{["attacks"]={{["damage"]=50,["description"]="Does 50 damage minus 10 damage for each damage counter on Machoke.",["effect_fn"]="MachokeKarateChopEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fighting",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Karate Chop",},{["damage"]=60,["description"]="Machoke does 20 damage to itself.",["effect_fn"]="MachokeSubmissionEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fighting",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Submission",},},["card_type"]="Fighting",["evolves_from"]="Machop",["hp"]=80,["label"]="MachokeCard",["name"]="Machoke",["rarity"]="Uncommon",["retreat_cost"]=3,["stage"]="Stage 1",["weakness"]="Psychic",},{["attacks"]={{["damage"]=0,["description"]="Whenever your opponent's attack damages Machamp (even if Machamp is Knocked Out), this power does 10 damage to the attacking Pokémon. (Don't apply Weakness and Resistance.)",["effect_fn"]="MachampStrikesBackEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Strikes Back",},{["damage"]=60,["energy_cost"]={{["count"]=3,["type"]="Fighting",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Seismic Toss",},},["card_type"]="Fighting",["evolves_from"]="Machoke",["hp"]=100,["label"]="MachampCard",["name"]="Machamp",["rarity"]="Rare",["retreat_cost"]=3,["stage"]="Stage 2",["weakness"]="Psychic",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin until you get tails. This attack does 10 damage times the number of heads.",["effect_fn"]="GeodudeStoneBarrageEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Fighting",},{["count"]=1,["type"]="Colorless",},},["kind"]="DAMAGE_X",["name"]="Stone Barrage",},},["card_type"]="Fighting",["hp"]=50,["label"]="GeodudeCard",["name"]="Geodude",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Grass",},{["attacks"]={{["damage"]=0,["description"]="During your opponent's next turn, whenever 30 or less damage is done to Graveler (after applying Weakness and Resistance), prevent that damage. (Any other effects of attacks still happen.)",["effect_fn"]="GravelerHardenEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fighting",},},["kind"]="RESIDUAL",["name"]="Harden",},{["damage"]=40,["energy_cost"]={{["count"]=2,["type"]="Fighting",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Rock Throw",},},["card_type"]="Fighting",["evolves_from"]="Geodude",["hp"]=60,["label"]="GravelerCard",["name"]="Graveler",["rarity"]="Uncommon",["retreat_cost"]=2,["stage"]="Stage 1",["weakness"]="Grass",},{["attacks"]={{["damage"]=60,["energy_cost"]={{["count"]=3,["type"]="Fighting",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Avalanche",},{["damage"]=100,["description"]="Does 20 damage to each Pokémon on each player's Bench. (Don't apply Weakness and Resistance for Benched Pokémon.) Golem does 100 damage to itself.",["effect_fn"]="GolemSelfdestructEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Fighting",},},["kind"]="Attack",["name"]="Selfdestruct",},},["card_type"]="Fighting",["evolves_from"]="Graveler",["hp"]=80,["label"]="GolemCard",["name"]="Golem",["rarity"]="Uncommon",["retreat_cost"]=4,["stage"]="Stage 2",["weakness"]="Grass",},{["attacks"]={{["damage"]=0,["description"]="If the Defending Pokémon attacks Cubone during your opponent's next turn, any damage done by the attack is reduced by 20 (after applying Weakness and Resistance). (Benching or evolving either Pokémon ends this effect.)",["effect_fn"]="CuboneSnivelEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Snivel",},{["damage"]=10,["description"]="Does 10 damage plus 10 more damage for each damage counter on Cubone.",["effect_fn"]="CuboneRageEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fighting",},},["kind"]="Attack",["name"]="Rage",},},["card_type"]="Fighting",["hp"]=40,["label"]="CuboneCard",["name"]="Cubone",["rarity"]="Common",["resistance"]="Lightning",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Grass",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon can't attack during your opponent's next turn.",["effect_fn"]="MarowakBoneAttackEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Fighting",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Bone Attack",},{["damage"]=0,["description"]="Each player fills his or her Bench with Basic Pokémon chosen at random from his or her deck. If a player has fewer Basic Pokémon than that in his or deck, he or she chooses all of them. Each player shuffles his or her deck afterward.",["effect_fn"]="MarowakWailEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Fighting",},},["kind"]="RESIDUAL",["name"]="Wail",},},["card_type"]="Fighting",["evolves_from"]="Cubone",["hp"]=70,["label"]="MarowakLv32Card",["name"]="Marowak",["rarity"]="Uncommon",["resistance"]="Lightning",["retreat_cost"]=2,["stage"]="Stage 1",["weakness"]="Grass",},{["attacks"]={{["damage"]=0,["description"]="Flip a coin. If heads, the Defending Pokémon is now Asleep.",["effect_fn"]="GastlySleepingGasEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},},["kind"]="Attack",["name"]="Sleeping Gas",},{["damage"]=0,["description"]="Discard 1 <PSYCHIC> Energy card attached to Gastly in order to use this attack. If a Pokémon Knocks Out Gastly during your opponent's next turn, Knock Out that Pokémon.",["effect_fn"]="GastlyDestinyBondEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},{["count"]=1,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Destiny Bond",},},["card_type"]="Psychic",["hp"]=30,["label"]="GastlyLv8Card",["name"]="Gastly",["rarity"]="Common",["resistance"]="Fighting",["retreat_cost"]=0,["stage"]="Basic",},{["attacks"]={{["damage"]=0,["description"]="The Defending Pokémon is now Asleep.",["effect_fn"]="HaunterHypnosisEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},},["kind"]="Attack",["name"]="Hypnosis",},{["damage"]=50,["description"]="You can't use this attack unless the Defending Pokémon is Asleep.",["effect_fn"]="HaunterDreamEaterEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Psychic",},},["kind"]="Attack",["name"]="Dream Eater",},},["card_type"]="Psychic",["evolves_from"]="Gastly",["hp"]=60,["label"]="HaunterLv22Card",["name"]="Haunter",["rarity"]="Uncommon",["resistance"]="Fighting",["retreat_cost"]=1,["stage"]="Stage 1",},{["attacks"]={{["damage"]=0,["description"]="Once during your turn (before your attack), you may move 1 damage counter from 1 of your opponent's Pokémon to another (even if it would Knock Out the other Pokémon). This power can't be used if Gengar is Asleep, Confused, or Paralyzed.",["effect_fn"]="GengarCurseEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Curse",},{["damage"]=30,["description"]="If your opponent has any Benched Pokémon, choose 1 of them and this attack does 10 damage to it. (Don't apply Weakness and Resistance for Benched Pokémon.)",["effect_fn"]="GengarDarkMindEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Psychic",},},["kind"]="Attack",["name"]="Dark Mind",},},["card_type"]="Psychic",["evolves_from"]="Haunter",["hp"]=80,["label"]="GengarCard",["name"]="Gengar",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=1,["stage"]="Stage 2",},{["attacks"]={{["damage"]=10,["description"]="Flip 2 coins. This attack does 10 damage times the number of heads.",["effect_fn"]="JynxDoubleslapEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},},["kind"]="DAMAGE_X",["name"]="Doubleslap",},{["damage"]=20,["description"]="Does 20 damage plus 10 more damage for each damage counter on the Defending Pokémon.",["effect_fn"]="JynxMeditateEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Psychic",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Meditate",},},["card_type"]="Psychic",["hp"]=70,["label"]="JynxCard",["name"]="Jynx",["rarity"]="Uncommon",["retreat_cost"]=2,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=10,["description"]="If your opponent has any Benched Pokémon, he or she chooses 1 of them and switches it with the Defending Pokémon. (Do the damage before switching the Pokémon.)",["effect_fn"]="PidgeyWhirlwindEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Whirlwind",},},["card_type"]="Colorless",["hp"]=40,["label"]="PidgeyCard",["name"]="Pidgey",["rarity"]="Common",["resistance"]="Fighting",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Lightning",},{["attacks"]={{["damage"]=20,["description"]="If your opponent has any Benched Pokémon, he or she chooses 1 of them and switches it with the Defending Pokémon. (Do the damage before switching the Pokémon.)",["effect_fn"]="PidgeottoWhirlwindEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Whirlwind",},{["damage"]=0,["description"]="If Pidgeotto was attacked last turn, do the final result of that attack on Pidgeotto to the Defending Pokémon.",["effect_fn"]="PidgeottoMirrorMoveEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Mirror Move",},},["card_type"]="Colorless",["evolves_from"]="Pidgey",["hp"]=60,["label"]="PidgeottoCard",["name"]="Pidgeotto",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Lightning",},{["attacks"]={{["damage"]=20,["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Wing Attack",},{["damage"]=30,["description"]="Unless this attack Knocks Out the Defending Pokémon, return the Defending Pokémon and all cards attached to it to your opponent's hand.",["effect_fn"]="PidgeotHurricaneEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Hurricane",},},["card_type"]="Colorless",["evolves_from"]="Pidgeotto",["hp"]=80,["label"]="PidgeotLv40Card",["name"]="Pidgeot",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=0,["stage"]="Stage 2",["weakness"]="Lightning",},{["attacks"]={{["damage"]=0,["description"]="Flip a coin. If heads, put a Basic Pokémon card chosen at random from your deck onto your Bench. (You can't use this attack if your Bench is full.)",["effect_fn"]="JigglypuffFriendshipSongEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Friendship Song",},{["damage"]=10,["description"]="All damage done to Jigglypuff during your opponent's next turn is reduced by 10 (after applying Weakness and Resistance).",["effect_fn"]="JigglypuffExpandEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Expand",},},["card_type"]="Colorless",["hp"]=50,["label"]="JigglypuffLv13Card",["name"]="Jigglypuff",["rarity"]="Common",["resistance"]="Psychic",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=0,["description"]="Flip a coin. If heads, the Defending Pokémon can't attack Eevee during your opponent's next turn. (Benching or evolving either Pokémon ends this effect.)",["effect_fn"]="EeveeTailWagEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Tail Wag",},{["damage"]=10,["description"]="Flip a coin. If heads, this attack does 10 damage plus 20 more damage; if tails, this attack does 10 damage.",["effect_fn"]="EeveeQuickAttackEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Quick Attack",},},["card_type"]="Colorless",["hp"]=50,["label"]="EeveeCard",["name"]="Eevee",["rarity"]="Common",["resistance"]="Psychic",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["card_type"]="Trainer",["description"]="Trade 1 of the Basic Pokémon or Evolution cards in your hand for 1 of the Basic Pokémon or Evolution cards from your deck. Show both cards to your opponent. Shuffle your deck afterward.",["effect_fn"]="PokemonTraderEffectCommands",["label"]="PokemonTraderCard",["name"]="Pokémon Trader",["rarity"]="Rare",},{["card_type"]="Trainer",["description"]="Put a Stage 2 Evolution card from your hand on the matching Basic Pokémon. You can only play this card when you would be allowed to evolve that Pokémon anyway.",["effect_fn"]="PokemonBreederEffectCommands",["label"]="PokemonBreederCard",["name"]="Pokémon Breeder",["rarity"]="Rare",},{["card_type"]="Trainer",["description"]="Play Clefairy Doll as if it were a Basic Pokémon. While in play, Clefairy Doll counts as a Pokémon (instead of a Trainer card). Clefairy Doll has no attacks, can't retreat, and can't be Asleep, Confused, Paralyzed, or Poisoned.",["effect_fn"]="ClefairyDollEffectCommands",["label"]="ClefairyDollCard",["name"]="Clefairy Doll",["rarity"]="Rare",},{["card_type"]="Trainer",["description"]="Trade 1 of the other cards in your hand for up to 2 basic Energy cards from your discard pile.",["effect_fn"]="EnergyRetrievalEffectCommands",["label"]="EnergyRetrievalCard",["name"]="Energy Retrieval",["rarity"]="Uncommon",},{["card_type"]="Trainer",["description"]="Search your deck for a basic Energy card and put it into your hand. Shuffle your deck afterward.",["effect_fn"]="EnergySearchEffectCommands",["label"]="EnergySearchCard",["name"]="Energy Search",["rarity"]="Common",},{["card_type"]="Trainer",["description"]="Choose 1 of your opponent's Benched Pokémon and switch it with his or her Active Pokémon.",["effect_fn"]="GustOfWindEffectCommands",["label"]="GustOfWindCard",["name"]="Gust of Wind",["rarity"]="Common",},{["card_type"]="Trainer",["description"]="Discard 1 Energy card attached to 1 of your own Pokémon in order to remove 4 damage counters from that Pokémon. If the Pokémon has fewer damage counters than that, remove all of them.",["effect_fn"]="SuperPotionEffectCommands",["label"]="SuperPotionCard",["name"]="Super Potion",["rarity"]="Uncommon",},{["card_type"]="Trainer",["description"]="Choose 1 Basic Pokémon card from your opponent's discard pile and put it onto his or her Bench. (You can't play Pokémon Flute if your opponent's Bench is full.)",["effect_fn"]="PokemonFluteEffectCommands",["label"]="PokemonFluteCard",["name"]="Pokémon Flute",["rarity"]="Uncommon",},},["Laboratory"]={{["attacks"]={{["damage"]=0,["description"]="Flip a coin. If heads, the Defending Pokémon is now Poisoned.",["effect_fn"]="EkansSpitPoisonEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="Attack",["name"]="Spit Poison",},{["damage"]=20,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="EkansWrapEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Wrap",},},["card_type"]="Grass",["hp"]=40,["label"]="EkansCard",["name"]="Ekans",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads and if your opponent has any Benched Pokémon, he or she chooses 1 of them and switches it with the Defending Pokémon. (Do the damage before switching the Pokémon.)",["effect_fn"]="ArbokTerrorStrikeEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="Attack",["name"]="Terror Strike",},{["damage"]=20,["description"]="The Defending Pokémon is now Poisoned.",["effect_fn"]="ArbokPoisonFangEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Poison Fang",},},["card_type"]="Grass",["evolves_from"]="Ekans",["hp"]=60,["label"]="ArbokCard",["name"]="Arbok",["rarity"]="Uncommon",["retreat_cost"]=2,["stage"]="Stage 1",["weakness"]="Psychic",},{["attacks"]={{["damage"]=0,["description"]="Flip a coin. If heads, the Defending Pokémon is now Confused.",["effect_fn"]="ZubatSupersonicEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Supersonic",},{["damage"]=10,["description"]="Remove a number of damage counters from Zubat equal to the damage done to the Defending Pokémon (after applying Weakness and Resistance). If Zubat has fewer damage counters than that, remove all of them.",["effect_fn"]="ZubatLeechLifeEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Leech Life",},},["card_type"]="Grass",["hp"]=40,["label"]="ZubatCard",["name"]="Zubat",["rarity"]="Common",["resistance"]="Fighting",["retreat_cost"]=0,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=30,["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Wing Attack",},{["damage"]=20,["description"]="Remove a number of damage counters from Golbat equal to the damage done to the Defending Pokémon (after applying Weakness and Resistance). If Golbat has fewer damage counters than that, remove all of them.",["effect_fn"]="GolbatLeechLifeEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Leech Life",},},["card_type"]="Grass",["evolves_from"]="Zubat",["hp"]=60,["label"]="GolbatCard",["name"]="Golbat",["rarity"]="Uncommon",["resistance"]="Fighting",["retreat_cost"]=0,["stage"]="Stage 1",["weakness"]="Psychic",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="VenonatStunSporeEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="Attack",["name"]="Stun Spore",},{["damage"]=10,["description"]="Remove a number of damage counters from Venonat equal to the damage done to the Defending Pokémon (after applying Weakness and Resistance). If Venonat has fewer damage counters than that, remove all of them.",["effect_fn"]="VenonatLeechLifeEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Leech Life",},},["card_type"]="Grass",["hp"]=40,["label"]="VenonatCard",["name"]="Venonat",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fire",},{["attacks"]={{["damage"]=0,["description"]="Once during your turn (before your attack), you may change the type of Venomoth to the type of any other Pokémon in play other than Colorless. This power can't be used if Venomoth is Asleep, Confused, or Paralyzed.",["effect_fn"]="VenomothShiftEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Shift",},{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Confused and Poisoned.",["effect_fn"]="VenomothVenomPowderEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},},["kind"]="Attack",["name"]="Venom Powder",},},["card_type"]="Grass",["evolves_from"]="Venonat",["hp"]=70,["label"]="VenomothCard",["name"]="Venomoth",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=0,["stage"]="Stage 1",["weakness"]="Fire",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="GrimerNastyGooEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Nasty Goo",},{["damage"]=0,["description"]="All damage done by attacks to Grimer during your opponent's next turn is reduced by 20 (after applying Weakness and Resistance).",["effect_fn"]="GrimerMinimizeEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="RESIDUAL",["name"]="Minimize",},},["card_type"]="Grass",["hp"]=50,["label"]="GrimerCard",["name"]="Grimer",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=0,["description"]="Ignore all Pokémon Powers other than Toxic Gases. This power stops working while Muk is Asleep, Confused, or Paralyzed.",["effect_fn"]="MukToxicGasEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Toxic Gas",},{["damage"]=30,["description"]="Flip a coin. If heads, the Defending Pokémon is now Poisoned.",["effect_fn"]="MukSludgeEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Grass",},},["kind"]="Attack",["name"]="Sludge",},},["card_type"]="Grass",["evolves_from"]="Grimer",["hp"]=70,["label"]="MukCard",["name"]="Muk",["rarity"]="Rare",["retreat_cost"]=2,["stage"]="Stage 1",["weakness"]="Psychic",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Poisoned; if tails, it is now Confused.",["effect_fn"]="KoffingFoulGasEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},},["kind"]="Attack",["name"]="Foul Gas",},},["card_type"]="Grass",["hp"]=50,["label"]="KoffingCard",["name"]="Koffing",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=20,["description"]="Flip a coin. If heads, the Defending Pokémon is now Poisoned.",["effect_fn"]="WeezingSmogEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},},["kind"]="Attack",["name"]="Smog",},{["damage"]=60,["description"]="Does 10 damage to each Pokémon on each player's Bench. (Don't apply Weakness and Resistance for Benched Pokémon.) Weezing does 60 damage to itself.",["effect_fn"]="WeezingSelfdestructEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Selfdestruct",},},["card_type"]="Grass",["evolves_from"]="Koffing",["hp"]=60,["label"]="WeezingCard",["name"]="Weezing",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Psychic",},{["attacks"]={{["damage"]=20,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="TangelaBindEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Bind",},{["damage"]=20,["description"]="The Defending Pokémon is now Poisoned.",["effect_fn"]="TangelaPoisonPowderEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Grass",},},["kind"]="Attack",["name"]="Poisonpowder",},},["card_type"]="Grass",["hp"]=50,["label"]="TangelaLv8Card",["name"]="Tangela",["rarity"]="Common",["retreat_cost"]=2,["stage"]="Basic",["weakness"]="Fire",},{["attacks"]={{["damage"]=0,["description"]="If your opponent has any Basic Pokémon or Evolution cards in his or her hand, your opponent shuffles them into his or her deck. Then, your opponent puts an equal number of Basic Pokémon or Evolution cards chosen at random from his or",["effect_fn"]="NinetalesMixUpEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fire",},},["kind"]="RESIDUAL",["name"]="Mix-Up",},{["damage"]=10,["description"]="Flip 8 coins. This attack does 10 damage times the number of heads.",["effect_fn"]="NinetalesDancingEmbersEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Fire",},},["kind"]="DAMAGE_X",["name"]="Dancing Embers",},},["card_type"]="Fire",["evolves_from"]="Vulpix",["hp"]=80,["label"]="NinetalesLv35Card",["name"]="Ninetails",["rarity"]="Rare",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Water",},{["attacks"]={{["damage"]=10,["description"]="If the Defending Pokémon tries to attack during your opponent's next turn, your opponent flips a coin. If tails, that attack does nothing.",["effect_fn"]="MagmarSmokescreenEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Fire",},},["kind"]="Attack",["name"]="Smokescreen",},{["damage"]=20,["description"]="Flip a coin. If heads, the Defending Pokémon is now Poisoned.",["effect_fn"]="MagmarSmogEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fire",},},["kind"]="Attack",["name"]="Smog",},},["card_type"]="Fire",["hp"]=70,["label"]="MagmarLv31Card",["name"]="Magmar",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Water",},{["attacks"]={{["damage"]=0,["description"]="Your opponent can't play Trainer cards during his or her next turn.",["effect_fn"]="PsyduckHeadacheEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},},["kind"]="RESIDUAL",["name"]="Headache",},{["damage"]=10,["description"]="Flip 3 coins. This attack does 10 damage times the number of heads.",["effect_fn"]="PsyduckFurySwipesEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="DAMAGE_X",["name"]="Fury Swipes",},},["card_type"]="Water",["hp"]=50,["label"]="PsyduckCard",["name"]="Psyduck",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Lightning",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="GolduckPsyshockEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},},["kind"]="Attack",["name"]="Psyshock",},{["damage"]=20,["description"]="If the Defending Pokémon has any Energy cards attached to it, choose 1 of them and discard it.",["effect_fn"]="GolduckHyperBeamEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Water",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Hyper Beam",},},["card_type"]="Water",["evolves_from"]="Psyduck",["hp"]=70,["label"]="GolduckCard",["name"]="Golduck",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Lightning",},{["attacks"]={{["damage"]=10,["description"]="Does 10 damage plus 10 more damage for each <WATER> Energy attached to Poliwag but not used to pay for this attack's Energy cost. You can't add more than 20 damage in this way.",["effect_fn"]="PoliwagWaterGunEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="Attack",["name"]="Water Gun",},},["card_type"]="Water",["hp"]=40,["label"]="PoliwagCard",["name"]="Poliwag",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Grass",},{["attacks"]={{["damage"]=0,["description"]="Choose 1 of the Defending Pokémon's attacks. That Pokémon can't use that attack during your opponent's next turn.",["effect_fn"]="PoliwhirlAmnesiaEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Water",},},["kind"]="Attack",["name"]="Amnesia",},{["damage"]=30,["description"]="Flip 2 coins. This attack does 30 damage times the number of heads.",["effect_fn"]="PoliwhirlDoubleslapEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Water",},{["count"]=1,["type"]="Colorless",},},["kind"]="DAMAGE_X",["name"]="Doubleslap",},},["card_type"]="Water",["evolves_from"]="Poliwag",["hp"]=60,["label"]="PoliwhirlCard",["name"]="Poliwhirl",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Grass",},{["attacks"]={{["damage"]=30,["description"]="Does 30 damage plus 10 more damage for each <WATER> Energy attached to Poliwrath but not used to pay for this attack's Energy cost. You can't add more than 20 damage in this way.",["effect_fn"]="PoliwrathWaterGunEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Water",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Water Gun",},{["damage"]=40,["description"]="If the Defending Pokémon has any Energy cards attached to it, choose 1 of them and discard it.",["effect_fn"]="PoliwrathWhirlpoolEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Water",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Whirlpool",},},["card_type"]="Water",["evolves_from"]="Poliwhirl",["hp"]=90,["label"]="PoliwrathCard",["name"]="Poliwrath",["rarity"]="Rare",["retreat_cost"]=3,["stage"]="Stage 2",["weakness"]="Grass",},{["attacks"]={{["damage"]=0,["description"]="At any time during your turn (before your attack), you may return Tentacool to your hand. (Discard all cards attached to Tentacool.) This power can't be used the turn you put Tentacool into play or if Tentacool is Asleep, Confused, or Paralyzed.",["effect_fn"]="TentacoolCowardiceEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Cowardice",},{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="Attack",["name"]="Acid",},},["card_type"]="Water",["hp"]=30,["label"]="TentacoolCard",["name"]="Tentacool",["rarity"]="Common",["retreat_cost"]=0,["stage"]="Basic",["weakness"]="Lightning",},{["attacks"]={{["damage"]=0,["description"]="Flip a coin. If heads, the Defending Pokémon is now Confused.",["effect_fn"]="TentacruelSupersonicEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="Attack",["name"]="Supersonic",},{["damage"]=10,["description"]="The Defending Pokémon is now Poisoned.",["effect_fn"]="TentacruelJellyfishStingEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Water",},},["kind"]="Attack",["name"]="Jellyfish Sting",},},["card_type"]="Water",["evolves_from"]="Tentacool",["hp"]=60,["label"]="TentacruelCard",["name"]="Tentacruel",["rarity"]="Uncommon",["retreat_cost"]=0,["stage"]="Stage 1",["weakness"]="Lightning",},{["attacks"]={{["damage"]=10,["description"]="If the Defending Pokémon tries to attack during your opponent's next turn, your opponent flips a coin. If tails, that attack does nothing.",["effect_fn"]="HorseaSmokescreenEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="Attack",["name"]="Smokescreen",},},["card_type"]="Water",["hp"]=40,["label"]="HorseaCard",["name"]="Horsea",["rarity"]="Common",["retreat_cost"]=0,["stage"]="Basic",["weakness"]="Lightning",},{["attacks"]={{["damage"]=20,["description"]="Does 20 damage plus 10 more damage for each <WATER> Energy attached to Seadra but not used to pay for this attack's Energy cost. You can't add more than 20 damage in this way.",["effect_fn"]="SeadraWaterGunEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Water Gun",},{["damage"]=20,["description"]="Flip a coin. If heads, during your opponent's next turn, prevent all  effects of attacks, including damage, done to Seadra.",["effect_fn"]="SeadraAgilityEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Agility",},},["card_type"]="Water",["evolves_from"]="Horsea",["hp"]=60,["label"]="SeadraCard",["name"]="Seadra",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Lightning",},{["attacks"]={{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Tackle",},{["damage"]=0,["description"]="Remove all Energy cards attached to all of your Pokémon, then randomly reattach each of them.",["effect_fn"]="MagnemiteMagneticStormEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Lightning",},{["count"]=1,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Magnetic Storm",},},["card_type"]="Lightning",["hp"]=40,["label"]="MagnemiteLv15Card",["name"]="Magnemite",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=20,["description"]="Don't apply Weakness and Resistance for this attack. (Any other effects that would happen after applying Weakness and Resistance still happen.)",["effect_fn"]="MagnetonSonicboomEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Lightning",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Sonicboom",},{["damage"]=100,["description"]="Does 20 damage to each Pokémon on each player's Bench. (Don't apply Weakness and Resistance for Benched Pokémon.) Magneton does 100 damage to itself.",["effect_fn"]="MagnetonLv35SelfdestructEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Lightning",},},["kind"]="Attack",["name"]="Selfdestruct",},},["card_type"]="Lightning",["evolves_from"]="Magnemite",["hp"]=80,["label"]="MagnetonLv35Card",["name"]="Magneton",["rarity"]="Rare",["retreat_cost"]=2,["stage"]="Stage 1",["weakness"]="Fighting",},{["attacks"]={{["damage"]=30,["description"]="Don't apply Weakness and Resistance for this attack. (Any other effects that would happen after applying Weakness and Resistance still happen.)",["effect_fn"]="ElectrodeSonicboomEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Lightning",},},["kind"]="Attack",["name"]="Sonicboom",},{["damage"]=0,["description"]="Search your deck for a basic Energy card and attach it to 1 of your Pokémon. Shuffle your deck afterward.",["effect_fn"]="ElectrodeEnergySpikeEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Lightning",},},["kind"]="RESIDUAL",["name"]="Energy Spike",},},["card_type"]="Lightning",["evolves_from"]="Voltorb",["hp"]=70,["label"]="ElectrodeLv35Card",["name"]="Electrode",["rarity"]="Rare",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Fighting",},{["attacks"]={{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Fighting",},},["kind"]="Attack",["name"]="Rock Throw",},{["damage"]=0,["description"]="During your opponent's next turn, whenever 30 or less damage is done to Onix (after applying Weakness and Resistance), prevent that damage. (Any other effects of attacks still happen.)",["effect_fn"]="OnixHardenEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fighting",},},["kind"]="RESIDUAL",["name"]="Harden",},},["card_type"]="Fighting",["hp"]=90,["label"]="OnixCard",["name"]="Onix",["rarity"]="Common",["retreat_cost"]=3,["stage"]="Basic",["weakness"]="Grass",},{["attacks"]={{["damage"]=30,["description"]="Flip 2 coins. This attack does 30 damage times the number of heads.",["effect_fn"]="MarowakBonemerangEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fighting",},},["kind"]="DAMAGE_X",["name"]="Bonemerang",},{["damage"]=0,["description"]="Search your deck for a <FIGHTING> Basic Pokémon card and put it onto your Bench. Shuffle your deck afterward. (You can't use this attack if your Bench is full.)",["effect_fn"]="MarowakCallforFriendEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fighting",},{["count"]=1,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Call for Friend",},},["card_type"]="Fighting",["evolves_from"]="Cubone",["hp"]=60,["label"]="MarowakLv26Card",["name"]="Marowak",["rarity"]="Uncommon",["resistance"]="Lightning",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Grass",},{["attacks"]={{["damage"]=0,["description"]="If your opponent has any Benched Pokémon, choose 1 of them and this attack does 20 damage to it. (Don't apply Weakness and Resistance for Benched Pokémon.)",["effect_fn"]="HitmonleeStretchKickEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fighting",},},["kind"]="RESIDUAL",["name"]="Stretch Kick",},{["damage"]=50,["energy_cost"]={{["count"]=3,["type"]="Fighting",},},["kind"]="Attack",["name"]="High Jump Kick",},},["card_type"]="Fighting",["hp"]=60,["label"]="HitmonleeCard",["name"]="Hitmonlee",["rarity"]="Rare",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=0,["description"]="Flip a coin. If heads, remove a damage counter from Slowpoke. This attack can't be used if Slowpoke has no damage counters on it.",["effect_fn"]="SlowpokeSpacingOutEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Spacing Out",},{["damage"]=0,["description"]="Discard 1 <PSYCHIC> Energy card attached to Slowpoke in order to use this attack. Put a Trainer card from your discard pile into your hand.",["effect_fn"]="SlowpokeScavengeEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Psychic",},},["kind"]="RESIDUAL",["name"]="Scavenge",},},["card_type"]="Psychic",["hp"]=50,["label"]="SlowpokeLv18Card",["name"]="Slowpoke",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=0,["description"]="As often as you like during your turn (before your attack), you may move 1 damage counter from 1 of your Pokémon to Slowbro as long as you don't Knock Out Slowbro. This power can't be used if Slowbro is Asleep, Confused, or Paralyzed.",["effect_fn"]="SlowbroStrangeBehaviorEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Strange Behavior",},{["damage"]=20,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="SlowbroPsyshockEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Psychic",},},["kind"]="Attack",["name"]="Psyshock",},},["card_type"]="Psychic",["evolves_from"]="Slowpoke",["hp"]=60,["label"]="SlowbroCard",["name"]="Slowbro",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Psychic",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="GastlyLickEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},},["kind"]="Attack",["name"]="Lick",},{["damage"]=0,["description"]="Put up to 2 Energy cards from your discard pile into your hand. Gastly does 10 damage to itself.",["effect_fn"]="GastlyEnergyConversionEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Psychic",},},["kind"]="RESIDUAL",["name"]="Energy Conversion",},},["card_type"]="Psychic",["hp"]=50,["label"]="GastlyLv17Card",["name"]="Gastly",["rarity"]="Uncommon",["resistance"]="Fighting",["retreat_cost"]=0,["stage"]="Basic",},{["attacks"]={{["damage"]=0,["description"]="Whenever an attack does anything to Haunter, flip a coin. If heads, prevent all effects of that attack, including damage, done to Haunter. This power stops working while Haunter is Asleep, Confused, or Paralyzed.",["effect_fn"]="HaunterTransparencyEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Transparency",},{["damage"]=10,["description"]="The Defending Pokémon is now Asleep.",["effect_fn"]="HaunterNightmareEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Nightmare",},},["card_type"]="Psychic",["evolves_from"]="Gastly",["hp"]=50,["label"]="HaunterLv17Card",["name"]="Haunter",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=0,["stage"]="Stage 1",},{["attacks"]={{["damage"]=0,["description"]="Look at up to 3 cards from the top of either player's deck and rearrange them as you like.",["effect_fn"]="HypnoProphecyEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},},["kind"]="RESIDUAL",["name"]="Prophecy",},{["damage"]=30,["description"]="If your opponent has any Benched Pokémon, choose 1 of them and this attack does 10 damage to it. (Don't apply Weakness and Resistance for Benched Pokémon.)",["effect_fn"]="HypnoDarkMindEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Psychic",},},["kind"]="Attack",["name"]="Dark Mind",},},["card_type"]="Psychic",["evolves_from"]="Drowzee",["hp"]=90,["label"]="HypnoCard",["name"]="Hypno",["rarity"]="Rare",["retreat_cost"]=2,["stage"]="Stage 1",["weakness"]="Psychic",},{["attacks"]={{["damage"]=0,["description"]="Whenever an attack (including your own) does 30 or more damage to Mr. Mime (after applying Weakness and Resistance), prevent that damage. (Any other effects of attacks still happen.)",["effect_fn"]="MrMimeInvisibleWallEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Invisible Wall",},{["damage"]=10,["description"]="Does 10 damage plus 10 more damage for each damage counter on the Defending Pokémon.",["effect_fn"]="MrMimeMeditateEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Meditate",},},["card_type"]="Psychic",["hp"]=40,["label"]="MrMimeCard",["name"]="Mr. Mime",["rarity"]="Rare",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=10,["description"]="Does 10 damage plus 10 more damage for each Energy card attached to the Defending Pokémon.",["effect_fn"]="MewtwoPsychicEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Psychic",},{["damage"]=0,["description"]="Discard 1 <PSYCHIC> Energy card attached to Mewtwo in order to use this attack. During your opponent's next turn, prevent all effects of attacks, including damage, done to Mewtwo.",["effect_fn"]="MewtwoBarrierEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Psychic",},},["kind"]="RESIDUAL",["name"]="Barrier",},},["card_type"]="Psychic",["hp"]=60,["label"]="MewtwoLv53Card",["name"]="Mewtwo",["rarity"]="Rare",["retreat_cost"]=3,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=0,["description"]="Does 30 damage to 1 of your opponent's Pokémon chosen at random. Don't apply Weakness and Resistance for this attack. (Any other effects that would happen after applying Weakness and Resistance still happen.)",["effect_fn"]="PidgeotSlicingWindEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Slicing Wind",},{["damage"]=20,["description"]="Switch Pidgeot with 1 of your Benched Pokémon chosen at random. If your opponent has any Benched Pokémon, switch the Defending Pokémon with 1 of them chosen at random. (Do the damage before switching the Pokémon.)",["effect_fn"]="PidgeotGaleEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Colorless",},},["kind"]="Attack",["name"]="Gale",},},["card_type"]="Colorless",["evolves_from"]="Pidgeotto",["hp"]=80,["label"]="PidgeotLv38Card",["name"]="Pidgeot",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=1,["stage"]="Stage 2",["weakness"]="Lightning",},{["attacks"]={{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Peck",},{["damage"]=0,["description"]="If Spearow was attacked last turn, do the final result of that attack on Spearow to the Defending Pokémon.",["effect_fn"]="SpearowMirrorMoveEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Mirror Move",},},["card_type"]="Colorless",["hp"]=50,["label"]="SpearowCard",["name"]="Spearow",["rarity"]="Common",["resistance"]="Fighting",["retreat_cost"]=0,["stage"]="Basic",["weakness"]="Lightning",},{["attacks"]={{["damage"]=20,["description"]="Flip a coin. If heads, during your opponent's next turn, prevent all effects of attacks, including damage, done to Fearow.",["effect_fn"]="FearowAgilityEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Agility",},{["damage"]=40,["energy_cost"]={{["count"]=4,["type"]="Colorless",},},["kind"]="Attack",["name"]="Drill Peck",},},["card_type"]="Colorless",["evolves_from"]="Spearow",["hp"]=70,["label"]="FearowCard",["name"]="Fearow",["rarity"]="Uncommon",["resistance"]="Fighting",["retreat_cost"]=0,["stage"]="Stage 1",["weakness"]="Lightning",},{["attacks"]={{["damage"]=0,["description"]="Choose 1 of the Defending Pokémon's attacks. Metronome copies that attack except for its Energy costs. (No matter what type the Defending Pokémon is, Clefable's type is still Colorless.)",["effect_fn"]="ClefableMetronomeEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Metronome",},{["damage"]=0,["description"]="All damage done by attacks to Clefable during your opponent's next turn is reduced by 20 (after applying Weakness and Resistance).",["effect_fn"]="ClefableMinimizeEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Minimize",},},["card_type"]="Colorless",["evolves_from"]="Clefairy",["hp"]=70,["label"]="ClefableCard",["name"]="Clefable",["rarity"]="Rare",["resistance"]="Psychic",["retreat_cost"]=2,["stage"]="Stage 1",["weakness"]="Fighting",},{["attacks"]={{["damage"]=10,["description"]="Flip 2 coins. This attack does 10 damage times the number of heads.",["effect_fn"]="DoduoFuryAttackEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="DAMAGE_X",["name"]="Fury Attack",},},["card_type"]="Colorless",["hp"]=50,["label"]="DoduoCard",["name"]="Doduo",["rarity"]="Common",["resistance"]="Fighting",["retreat_cost"]=0,["stage"]="Basic",["weakness"]="Lightning",},{["attacks"]={{["damage"]=0,["description"]="As long as Dodrio is Benched, pay <COLORLESS> less to retreat your Active Pokémon.",["effect_fn"]="DodrioRetreatAidEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Retreat Aid",},{["damage"]=10,["description"]="Does 10 damage plus 10 more damage for each damage counter on Dodrio.",["effect_fn"]="DodrioRageEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Rage",},},["card_type"]="Colorless",["evolves_from"]="Doduo",["hp"]=70,["label"]="DodrioCard",["name"]="Dodrio",["rarity"]="Uncommon",["resistance"]="Fighting",["retreat_cost"]=0,["stage"]="Stage 1",["weakness"]="Lightning",},{["attacks"]={{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Pound",},{["damage"]=0,["description"]="Remove all damage counters from Ditto. For the rest of the game, replace Ditto with a copy of a Basic Pokémon card (other than Ditto) chosen at random from your deck.",["effect_fn"]="DittoMorphEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Morph",},},["card_type"]="Colorless",["hp"]=50,["label"]="DittoCard",["name"]="Ditto",["rarity"]="Rare",["resistance"]="Psychic",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=0,["description"]="If the Defending Pokémon has a Weakness, you may change it to a type of your choice other than Colorless.",["effect_fn"]="PorygonConversion1EffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Conversion 1",},{["damage"]=0,["description"]="Change Porygon's Resistance to a type of your choice other than Colorless.",["effect_fn"]="PorygonConversion2EffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Conversion 2",},},["card_type"]="Colorless",["hp"]=30,["label"]="PorygonCard",["name"]="Porygon",["rarity"]="Uncommon",["resistance"]="Psychic",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["card_type"]="Trainer",["description"]="Your opponent shuffles his or her hand into his or her deck, then draws 7 cards.",["effect_fn"]="ImposterProfessorOakEffectCommands",["label"]="ImposterProfessorOakCard",["name"]="Imposter Professor Oak",["rarity"]="Rare",},{["card_type"]="Trainer",["description"]="You and your opponent show each other your hands, then shuffle all the Trainer cards from your hands into your decks.",["effect_fn"]="LassEffectCommands",["label"]="LassCard",["name"]="Lass",["rarity"]="Rare",},{["card_type"]="Trainer",["description"]="Discard 1 Energy card attached to 1 of your own Pokémon in order to choose 1 of your opponent's Pokémon and up to 2 Energy cards attached to it. Discard those Energy cards.",["effect_fn"]="SuperEnergyRemovalEffectCommands",["label"]="SuperEnergyRemovalCard",["name"]="Super Energy Removal",["rarity"]="Rare",},{["card_type"]="Trainer",["description"]="Look at up to 5 cards from the top of your deck and rearrange them as you like.",["effect_fn"]="PokedexEffectCommands",["label"]="PokedexCard",["name"]="Pokédex",["rarity"]="Uncommon",},{["card_type"]="Trainer",["description"]="Choose 1 of your own Pokémon in play and a Stage of Evolution. Discard all Evolution cards of that Stage or higher attached to that Pokémon.",["effect_fn"]="DevolutionSprayEffectCommands",["label"]="DevolutionSprayCard",["name"]="Devolution Spray",["rarity"]="Rare",},{["card_type"]="Trainer",["description"]="Shuffle 2 of the other cards from your hand into your deck in order to draw a card.",["effect_fn"]="MaintenanceEffectCommands",["label"]="MaintenanceCard",["name"]="Maintenance",["rarity"]="Uncommon",},{["card_type"]="Trainer",["description"]="Shuffle your hand into your deck. Flip a coin. If heads, draw 8 cards. If tails, draw 1 card.",["effect_fn"]="GamblerEffectCommands",["label"]="GamblerCard",["name"]="Gambler",["rarity"]="Common",},{["card_type"]="Trainer",["description"]="Flip a coin. If heads, put a card in your discard pile on top of your deck.",["effect_fn"]="RecycleEffectCommands",["label"]="RecycleCard",["name"]="Recycle",["rarity"]="Common",},},["Mystery"]={{["attacks"]={{["damage"]=10,["description"]="Flip 3 coins. This attack does 10 damage times the number of heads.",["effect_fn"]="NidoranFFurySwipesEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="DAMAGE_X",["name"]="Fury Swipes",},{["damage"]=0,["description"]="Search your deck for a Basic Pokémon named Nidoran♀ or Nidoran♂ and put it onto your Bench. Shuffle your deck afterward. (You can't use this attack if your Bench is full.)",["effect_fn"]="NidoranFCallForFamilyEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},},["kind"]="RESIDUAL",["name"]="Call for Family",},},["card_type"]="Grass",["hp"]=60,["label"]="NidoranFCard",["name"]="Nidoran♀",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=0,["description"]="Flip a coin. If heads, the Defending Pokémon is now Confused.",["effect_fn"]="NidorinaSupersonicEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="Attack",["name"]="Supersonic",},{["damage"]=30,["description"]="Flip 2 coins. This attack does 30 damage times the number of heads.",["effect_fn"]="NidorinaDoubleKickEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},{["count"]=2,["type"]="Colorless",},},["kind"]="DAMAGE_X",["name"]="Double Kick",},},["card_type"]="Grass",["evolves_from"]="Nidoran♀",["hp"]=70,["label"]="NidorinaCard",["name"]="Nidorina",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Psychic",},{["attacks"]={{["damage"]=20,["description"]="Does 20 damage plus 20 more damage for each Nidoking you have in play.",["effect_fn"]="NidoqueenBoyfriendsEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Boyfriends",},{["damage"]=50,["energy_cost"]={{["count"]=2,["type"]="Grass",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Mega Punch",},},["card_type"]="Grass",["evolves_from"]="Nidorina",["hp"]=90,["label"]="NidoqueenCard",["name"]="Nidoqueen",["rarity"]="Rare",["retreat_cost"]=3,["stage"]="Stage 2",["weakness"]="Psychic",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="OddishStunSporeEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="Attack",["name"]="Stun Spore",},{["damage"]=0,["description"]="Search your deck for a Basic Pokémon named Oddish and put it onto your Bench. Shuffle your deck afterward. (You can't use this attack if your Bench is full.)",["effect_fn"]="OddishSproutEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},},["kind"]="RESIDUAL",["name"]="Sprout",},},["card_type"]="Grass",["hp"]=50,["label"]="OddishCard",["name"]="Oddish",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fire",},{["attacks"]={{["damage"]=0,["description"]="The Defending Pokémon is now Poisoned.",["effect_fn"]="GloomPoisonPowderEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Grass",},},["kind"]="Attack",["name"]="Poisonpowder",},{["damage"]=20,["description"]="Both the Defending Pokémon and Gloom are now Confused (after doing damage).",["effect_fn"]="GloomFoulOdorEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},},["kind"]="Attack",["name"]="Foul Odor",},},["card_type"]="Grass",["evolves_from"]="Oddish",["hp"]=60,["label"]="GloomCard",["name"]="Gloom",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Fire",},{["attacks"]={{["damage"]=0,["description"]="Once during your turn (before your attack), you may flip a coin. If heads, remove 1 damage counter from 1 of your Pokémon. This power can't be used if Vileplume is Asleep, Confused, or Paralyzed.",["effect_fn"]="VileplumeHealEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Heal",},{["damage"]=40,["description"]="Flip 3 coins. This attack does 40 damage times the number of heads. Vileplume is now Confused (after doing damage).",["effect_fn"]="VileplumePetalDanceEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Grass",},},["kind"]="DAMAGE_X",["name"]="Petal Dance",},},["card_type"]="Grass",["evolves_from"]="Gloom",["hp"]=80,["label"]="VileplumeCard",["name"]="Vileplume",["rarity"]="Rare",["retreat_cost"]=2,["stage"]="Stage 2",["weakness"]="Fire",},{["attacks"]={{["damage"]=20,["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Scratch",},{["damage"]=0,["description"]="The Defending Pokémon is now Asleep.",["effect_fn"]="ParasSporeEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},},["kind"]="Attack",["name"]="Spore",},},["card_type"]="Grass",["hp"]=40,["label"]="ParasCard",["name"]="Paras",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fire",},{["attacks"]={{["damage"]=0,["description"]="The Defending Pokémon is now Asleep.",["effect_fn"]="ParasectSporeEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},},["kind"]="Attack",["name"]="Spore",},{["damage"]=30,["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Slash",},},["card_type"]="Grass",["evolves_from"]="Paras",["hp"]=60,["label"]="ParasectCard",["name"]="Parasect",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Fire",},{["attacks"]={{["damage"]=0,["description"]="The Defending Pokémon is now Asleep.",["effect_fn"]="ExeggcuteHypnosisEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},},["kind"]="Attack",["name"]="Hypnosis",},{["damage"]=20,["description"]="Unless all damage from this attack is prevented, you may remove 1 damage counter from Exeggcute.",["effect_fn"]="ExeggcuteLeechSeedEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Grass",},},["kind"]="Attack",["name"]="Leech Seed",},},["card_type"]="Grass",["hp"]=50,["label"]="ExeggcuteCard",["name"]="Exeggcute",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fire",},{["attacks"]={{["damage"]=0,["description"]="Switch Exeggutor with 1 of your Benched Pokémon.",["effect_fn"]="ExeggutorTeleportEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},},["kind"]="RESIDUAL",["name"]="Teleport",},{["damage"]=20,["description"]="Flip a number of coins equal to the number of Energy attached to Exeggutor. This attack does 20 damage times the number of heads.",["effect_fn"]="ExeggutorBigEggsplosionEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="DAMAGE_X",["name"]="Big Eggsplosion",},},["card_type"]="Grass",["evolves_from"]="Exeggcute",["hp"]=80,["label"]="ExeggutorCard",["name"]="Exeggutor",["rarity"]="Uncommon",["retreat_cost"]=3,["stage"]="Stage 1",["weakness"]="Fire",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Confused.",["effect_fn"]="VulpixConfuseRayEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fire",},},["kind"]="Attack",["name"]="Confuse Ray",},},["card_type"]="Fire",["hp"]=50,["label"]="VulpixCard",["name"]="Vulpix",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Water",},{["attacks"]={{["damage"]=0,["description"]="If your opponent has any Benched Pokémon, choose 1 of them and switch it with the Defending Pokémon.",["effect_fn"]="NinetalesLureEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Lure",},{["damage"]=80,["description"]="Discard 1 <FIRE> Energy card attached to Ninetales in order to use this attack.",["effect_fn"]="NinetalesFireBlastEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Fire",},},["kind"]="Attack",["name"]="Fire Blast",},},["card_type"]="Fire",["evolves_from"]="Vulpix",["hp"]=80,["label"]="NinetalesLv32Card",["name"]="Ninetails",["rarity"]="Rare",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Water",},{["attacks"]={{["damage"]=30,["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Bite",},{["damage"]=10,["description"]="Does 10 damage plus 10 more damage for each damage counter on Flareon.",["effect_fn"]="FlareonRageEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Rage",},},["card_type"]="Fire",["evolves_from"]="Eevee",["hp"]=60,["label"]="FlareonLv22Card",["name"]="Flareon",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Water",},{["attacks"]={{["damage"]=0,["description"]="You may discard any number of <FIRE> Energy cards attached to Moltres when you use this attack. If you do, discard that many cards from the top of your opponent's deck.",["effect_fn"]="MoltresWildfireEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Fire",},},["kind"]="RESIDUAL",["name"]="Wildfire",},{["damage"]=80,["description"]="Flip a coin. If tails, this attack does nothing.",["effect_fn"]="MoltresLv35DiveBombEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Fire",},},["kind"]="Attack",["name"]="Dive Bomb",},},["card_type"]="Fire",["hp"]=70,["label"]="MoltresLv35Card",["name"]="Moltres",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=2,["stage"]="Basic",},{["attacks"]={{["damage"]=0,["description"]="Flip a coin. If heads, the Defending Pokémon is now Confused.",["effect_fn"]="ShellderSupersonicEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="Attack",["name"]="Supersonic",},{["damage"]=0,["description"]="Flip a coin. If heads, prevent all damage done to Shellder during your opponent's next turn. (Any other effects of attacks still happen.)",["effect_fn"]="ShellderHideInShellEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="RESIDUAL",["name"]="Hide in Shell",},},["card_type"]="Water",["hp"]=30,["label"]="ShellderCard",["name"]="Shellder",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Lightning",},{["attacks"]={{["damage"]=30,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed. If tails, this attack does nothing (not even damage).",["effect_fn"]="CloysterClampEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Water",},},["kind"]="Attack",["name"]="Clamp",},{["damage"]=30,["description"]="Flip 2 coins. This attack does 30 damage times the number of heads.",["effect_fn"]="CloysterSpikeCannonEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Water",},},["kind"]="DAMAGE_X",["name"]="Spike Cannon",},},["card_type"]="Water",["evolves_from"]="Shellder",["hp"]=50,["label"]="CloysterCard",["name"]="Cloyster",["rarity"]="Uncommon",["retreat_cost"]=2,["stage"]="Stage 1",["weakness"]="Lightning",},{["attacks"]={{["damage"]=10,["description"]="Does 10 damage plus 10 more damage for each <WATER> Energy attached to Lapras but not used to pay for this attack's Energy cost. You can't add more than 20 damage in this way.",["effect_fn"]="LaprasWaterGunEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="Attack",["name"]="Water Gun",},{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Confused.",["effect_fn"]="LaprasConfuseRayEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Water",},},["kind"]="Attack",["name"]="Confuse Ray",},},["card_type"]="Water",["hp"]=80,["label"]="LaprasCard",["name"]="Lapras",["rarity"]="Rare",["retreat_cost"]=2,["stage"]="Basic",["weakness"]="Lightning",},{["attacks"]={{["damage"]=0,["description"]="During your next turn, Vaporeon's Bite attack's base damage is doubled.",["effect_fn"]="VaporeonFocusEnergyEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Focus Energy",},{["damage"]=30,["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Bite",},},["card_type"]="Water",["evolves_from"]="Eevee",["hp"]=60,["label"]="VaporeonLv29Card",["name"]="Vaporeon",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Lightning",},{["attacks"]={{["damage"]=0,["description"]="Your opponent plays with his or her hand face up. This power stops working while Omanyte is Asleep, Confused, or Paralyzed.",["effect_fn"]="OmanyteClairvoyanceEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Clairvoyance",},{["damage"]=10,["description"]="Does 10 damage plus 10 more damage for each <WATER> Energy attached to Omanyte but not used to pay for this attack's Energy cost. You can't add more than 20 damage in this way.",["effect_fn"]="OmanyteWaterGunEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},},["kind"]="Attack",["name"]="Water Gun",},},["card_type"]="Water",["evolves_from"]="Mysterious Fossil",["hp"]=40,["label"]="OmanyteCard",["name"]="Omanyte",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Grass",},{["attacks"]={{["damage"]=20,["description"]="Does 20 damage plus 10 more damage for each <WATER> Energy attached to Omastar but not used to pay for this attack's Energy cost. You can't add more than 20 damage in this way.",["effect_fn"]="OmastarWaterGunEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Water",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Water Gun",},{["damage"]=30,["description"]="Flip 2 coins. This attack does 30 damage times the number of heads.",["effect_fn"]="OmastarSpikeCannonEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Water",},},["kind"]="DAMAGE_X",["name"]="Spike Cannon",},},["card_type"]="Water",["evolves_from"]="Omanyte",["hp"]=70,["label"]="OmastarCard",["name"]="Omastar",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 2",["weakness"]="Grass",},{["attacks"]={{["damage"]=30,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="ArticunoFreezeDryEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Water",},},["kind"]="Attack",["name"]="Freeze Dry",},{["damage"]=50,["description"]="Flip a coin. If heads, this attack does 10 damage to each of your opponent's Benched Pokémon. If tails, this attack does 10 damage to each of your own Benched Pokémon. (Don't apply Weakness and Resistance for Benched Pokémon.)",["effect_fn"]="ArticunoBlizzardEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Water",},},["kind"]="Attack",["name"]="Blizzard",},},["card_type"]="Water",["hp"]=70,["label"]="ArticunoLv35Card",["name"]="Articuno",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=2,["stage"]="Basic",},{["attacks"]={{["damage"]=20,["description"]="If your opponent has any Benched Pokémon, choose 1 of them and this attack does 10 damage to it. (Don't apply Weakness and Resistance for Benched Pokémon.)",["effect_fn"]="PikachuSparkEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Lightning",},},["kind"]="Attack",["name"]="Spark",},},["card_type"]="Lightning",["hp"]=50,["label"]="PikachuLv14Card",["name"]="Pikachu",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=30,["description"]="Choose 3 of your opponent's Benched Pokémon and this attack does 10 damage to each of them. (Don't apply Weakness and Resistance for Benched Pokémon.) If your opponent has fewer than 3 Benched Pokémon, do the damage to each of them.",["effect_fn"]="RaichuGigashockEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Lightning",},},["kind"]="Attack",["name"]="Gigashock",},},["card_type"]="Lightning",["evolves_from"]="Pikachu",["hp"]=90,["label"]="RaichuLv45Card",["name"]="Raichu",["rarity"]="Rare",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Fighting",},{["attacks"]={{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Tackle",},},["card_type"]="Lightning",["hp"]=40,["label"]="VoltorbCard",["name"]="Voltorb",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=20,["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Tackle",},{["damage"]=20,["description"]="If the Defending Pokémon isn't Colorless, this attack does 10 damage to each Benched Pokémon of the same type as the Defending Pokémon (including your own).",["effect_fn"]="ElectrodeChainLightningEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Lightning",},},["kind"]="Attack",["name"]="Chain Lightning",},},["card_type"]="Lightning",["evolves_from"]="Voltorb",["hp"]=90,["label"]="ElectrodeLv42Card",["name"]="Electrode",["rarity"]="Rare",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Fighting",},{["attacks"]={{["damage"]=20,["description"]="Flip 2 coins. This attack does 20 damage times the number of heads.",["effect_fn"]="JolteonDoubleKickEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="DAMAGE_X",["name"]="Double Kick",},{["damage"]=30,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="JolteonStunNeedleEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Colorless",},},["kind"]="Attack",["name"]="Stun Needle",},},["card_type"]="Lightning",["evolves_from"]="Eevee",["hp"]=60,["label"]="JolteonLv24Card",["name"]="Jolteon",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Fighting",},{["attacks"]={{["damage"]=40,["description"]="For each of your opponent's Benched Pokémon, flip a coin. If heads, this attack does 20 damage to that Pokémon. (Don't apply Weakness and Resistance for Benched Pokémon.) Then, Zapdos does 10 damage times the number of tails to itself.",["effect_fn"]="ZapdosThunderstormEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Lightning",},},["kind"]="Attack",["name"]="Thunderstorm",},},["card_type"]="Lightning",["hp"]=80,["label"]="ZapdosLv40Card",["name"]="Zapdos",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=2,["stage"]="Basic",},{["attacks"]={{["damage"]=0,["description"]="Once during your turn (before your attack), you may look at one of the following: the top card of either player's deck, a random card from your opponent's hand, or one of either player's Prizes.",["effect_fn"]="MankeyPeekEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Peek",},{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Scratch",},},["card_type"]="Fighting",["hp"]=30,["label"]="MankeyCard",["name"]="Mankey",["rarity"]="Common",["retreat_cost"]=0,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=20,["description"]="Flip 3 coins. This attack does 20 damage times the number of heads.",["effect_fn"]="PrimeapeFurySwipesEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fighting",},},["kind"]="DAMAGE_X",["name"]="Fury Swipes",},{["damage"]=50,["description"]="Flip a coin. If tails, Primeape is now Confused (after doing damage).",["effect_fn"]="PrimeapeTantrumEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fighting",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Tantrum",},},["card_type"]="Fighting",["evolves_from"]="Mankey",["hp"]=70,["label"]="PrimeapeCard",["name"]="Primeape",["rarity"]="Uncommon",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Psychic",},{["attacks"]={{["damage"]=0,["description"]="Flip a coin. If heads, the Defending Pokémon can't attack Rhyhorn during your opponent's next turn. (Benching or evolving either Pokémon ends this effect.)",["effect_fn"]="RhyhornLeerEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Leer",},{["damage"]=30,["energy_cost"]={{["count"]=1,["type"]="Fighting",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Horn Attack",},},["card_type"]="Fighting",["hp"]=70,["label"]="RhyhornCard",["name"]="Rhyhorn",["rarity"]="Common",["resistance"]="Lightning",["retreat_cost"]=3,["stage"]="Basic",["weakness"]="Grass",},{["attacks"]={{["damage"]=30,["energy_cost"]={{["count"]=1,["type"]="Fighting",},{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Horn Attack",},{["damage"]=50,["description"]="Rhydon does 20 damage to itself. If your opponent has any Benched Pokémon, he or she chooses 1 of them and switches it with the Defending Pokémon.(Do the damage before switching the Pokémon.",["effect_fn"]="RhydonRamEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Fighting",},},["kind"]="Attack",["name"]="Ram",},},["card_type"]="Fighting",["evolves_from"]="Rhyhorn",["hp"]=100,["label"]="RhydonCard",["name"]="Rhydon",["rarity"]="Uncommon",["resistance"]="Lightning",["retreat_cost"]=3,["stage"]="Stage 1",["weakness"]="Grass",},{["attacks"]={{["damage"]=0,["description"]="Whenever an attack (even your own) does damage to Kabuto (after applying Weakness and Resistance), that attack only does half the damage to Kabuto (rounded down to the nearest 10).",["effect_fn"]="KabutoKabutoArmorEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Kabuto Armor",},{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Scratch",},},["card_type"]="Fighting",["evolves_from"]="Mysterious Fossil",["hp"]=30,["label"]="KabutoCard",["name"]="Kabuto",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Grass",},{["attacks"]={{["damage"]=30,["energy_cost"]={{["count"]=2,["type"]="Fighting",},},["kind"]="Attack",["name"]="Sharp Sickle",},{["damage"]=40,["description"]="Remove a number of damage counters from Kabutops equal to half the damage done to the Defending Pokémon (after applying Weakness and Resistance) (rounded up to the nearest 10).",["effect_fn"]="KabutopsAbsorbEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Fighting",},},["kind"]="Attack",["name"]="Absorb",},},["card_type"]="Fighting",["evolves_from"]="Kabuto",["hp"]=60,["label"]="KabutopsCard",["name"]="Kabutops",["rarity"]="Rare",["retreat_cost"]=1,["stage"]="Stage 2",["weakness"]="Grass",},{["attacks"]={{["damage"]=0,["description"]="No more Evolution cards can be played. This power stops working while Aerodactyl is Asleep, Confused, or Paralyzed.",["effect_fn"]="AerodactylPrehistoricPowerEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Prehistoric Power",},{["damage"]=30,["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Wing Attack",},},["card_type"]="Fighting",["evolves_from"]="Mysterious Fossil",["hp"]=60,["label"]="AerodactylCard",["name"]="Aerodactyl",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=2,["stage"]="Stage 1",["weakness"]="Grass",},{["attacks"]={{["damage"]=0,["description"]="As often as you like during your turn (before your attack), you may move 1 damage counter from 1 of your Pokémon to another as long as you don't Knock Out that Pokémon. This power can't be used if Alakazam is Asleep, Confused, or Paralyzed.",["effect_fn"]="AlakazamDamageSwapEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Damage Swap",},{["damage"]=30,["description"]="Flip a coin. If heads, the Defending Pokémon is now Confused.",["effect_fn"]="AlakazamConfuseRayEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Psychic",},},["kind"]="Attack",["name"]="Confuse Ray",},},["card_type"]="Psychic",["evolves_from"]="Kadabra",["hp"]=80,["label"]="AlakazamCard",["name"]="Alakazam",["rarity"]="Rare",["retreat_cost"]=3,["stage"]="Stage 2",["weakness"]="Psychic",},{["attacks"]={{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Pound",},{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Confused.",["effect_fn"]="DrowzeeConfuseRayEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Psychic",},},["kind"]="Attack",["name"]="Confuse Ray",},},["card_type"]="Psychic",["hp"]=50,["label"]="DrowzeeCard",["name"]="Drowzee",["rarity"]="Common",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=10,["description"]="Does 10 damage times the number of Energy cards attached to the Defending Pokémon.",["effect_fn"]="MewPsywaveEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},},["kind"]="DAMAGE_X",["name"]="Psywave",},{["damage"]=0,["description"]="Choose an evolved Pokémon (Your own or your opponent's). Return the highest stage evolution card on that Pokémon to Its player's hand.",["effect_fn"]="MewDevolutionBeamEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Psychic",},},["kind"]="RESIDUAL",["name"]="Devolution Beam",},},["card_type"]="Psychic",["hp"]=50,["label"]="MewLv23Card",["name"]="Mew",["rarity"]="Rare",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=0,["description"]="Flip a coin. If heads, the Defending Pokémon is now Asleep.",["effect_fn"]="ClefairySingEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Sing",},{["damage"]=0,["description"]="Choose 1 of the Defending Pokémon's attacks. Metronome copies that attack except for its Energy costs. (No matter what type the Defending Pokemon is, Clefairy's type is still Colorless.)",["effect_fn"]="ClefairyMetronomeEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="Metronome",},},["card_type"]="Colorless",["hp"]=40,["label"]="ClefairyCard",["name"]="Clefairy",["rarity"]="Rare",["resistance"]="Psychic",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, draw a card.",["effect_fn"]="MeowthPayDayEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Pay Day",},},["card_type"]="Colorless",["hp"]=50,["label"]="MeowthLv15Card",["name"]="Meowth",["rarity"]="Common",["resistance"]="Psychic",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=20,["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Scratch",},{["damage"]=30,["description"]="If the Defending Pokémon attacks Persian during your opponent's next turn, any damage done by the attack is reduced by 10 (after applying Weakness and Resistance). (Benching or evolving either Pokémon ends this effect.)",["effect_fn"]="PersianPounceEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Pounce",},},["card_type"]="Colorless",["evolves_from"]="Meowth",["hp"]=70,["label"]="PersianCard",["name"]="Persian",["rarity"]="Uncommon",["resistance"]="Psychic",["retreat_cost"]=0,["stage"]="Stage 1",["weakness"]="Fighting",},{["attacks"]={{["damage"]=30,["description"]="Flip a coin. If tails, this attack does nothing. Either way, you can't use this attack again as long as Farfetch'd stays in play (even putting Farfetch'd on the Bench won't let you use it again).",["effect_fn"]="FarfetchdLeekSlapEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Leek Slap",},{["damage"]=30,["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Pot Smash",},},["card_type"]="Colorless",["hp"]=50,["label"]="FarfetchdCard",["name"]="Farfetch'd",["rarity"]="Uncommon",["resistance"]="Fighting",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Lightning",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="LickitungTongueWrapEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Tongue Wrap",},{["damage"]=0,["description"]="Flip a coin. If heads, the Defending Pokémon is now Confused.",["effect_fn"]="LickitungSupersonicEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Supersonic",},},["card_type"]="Colorless",["hp"]=90,["label"]="LickitungCard",["name"]="Lickitung",["rarity"]="Uncommon",["resistance"]="Psychic",["retreat_cost"]=3,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=20,["description"]="Flip a coin. If heads, this attack does 20 damage plus 10 more damage; if tails, this attack does 20 damage.",["effect_fn"]="TaurosStompEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Stomp",},{["damage"]=20,["description"]="Does 20 damage plus 10 more damage for each damage counter on Tauros. Flip a coin. If tails, Tauros is now Confused (after doing damage).",["effect_fn"]="TaurosRampageEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Rampage",},},["card_type"]="Colorless",["hp"]=60,["label"]="TaurosCard",["name"]="Tauros",["rarity"]="Uncommon",["resistance"]="Psychic",["retreat_cost"]=2,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Pound",},},["card_type"]="Colorless",["hp"]=40,["label"]="DratiniCard",["name"]="Dratini",["rarity"]="Uncommon",["resistance"]="Psychic",["retreat_cost"]=1,["stage"]="Basic",},{["attacks"]={{["damage"]=30,["description"]="Flip 2 coins. This attack does 30 damage times the number of heads.",["effect_fn"]="DragonairSlamEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="DAMAGE_X",["name"]="Slam",},{["damage"]=20,["description"]="If the Defending Pokémon has any Energy cards attached to it, choose 1 of them and discard it.",["effect_fn"]="DragonairHyperBeamEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Colorless",},},["kind"]="Attack",["name"]="Hyper Beam",},},["card_type"]="Colorless",["evolves_from"]="Dratini",["hp"]=80,["label"]="DragonairCard",["name"]="Dragonair",["rarity"]="Rare",["resistance"]="Psychic",["retreat_cost"]=2,["stage"]="Stage 1",},{["attacks"]={{["damage"]=0,["description"]="Once during your turn (before your attack), if Dragonite is on your Bench, you may switch it with your Active Pokémon.",["effect_fn"]="DragoniteStepInEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Step In",},{["damage"]=40,["description"]="Flip 2 coins. This attack does 40 damage times the number of heads.",["effect_fn"]="DragoniteLv45SlamEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Colorless",},},["kind"]="DAMAGE_X",["name"]="Slam",},},["card_type"]="Colorless",["evolves_from"]="Dragonair",["hp"]=100,["label"]="DragoniteLv45Card",["name"]="Dragonite",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=1,["stage"]="Stage 2",},{["card_type"]="Trainer",["description"]="Choose a Pokémon on your Bench. Shuffle it and any cards attached to it into your deck.",["effect_fn"]="MrFujiEffectCommands",["label"]="MrFujiCard",["name"]="Mr.Fuji",["rarity"]="Uncommon",},{["card_type"]="Trainer",["description"]="Play Mysterious Fossil as if it were a Basic Pokémon. While in play, Mysterious Fossil counts as a Pokémon (instead of a Trainer card). Mysterious Fossil has no attacks, can't retreat, and can't be Asleep, Confused, Paralyzed, or Poisoned.",["effect_fn"]="MysteriousFossilEffectCommands",["label"]="MysteriousFossilCard",["name"]="Mysterious Fossil",["rarity"]="Common",},{["card_type"]="Trainer",["description"]="Choose 1 Energy card attached to 1 of your opponent's Pokémon and discard it.",["effect_fn"]="EnergyRemovalEffectCommands",["label"]="EnergyRemovalCard",["name"]="Energy Removal",["rarity"]="Common",},{["card_type"]="Trainer",["description"]="Remove all damage counters from all of your own Pokémon with damage counters on them, then discard all Energy cards attached to those Pokémon.",["effect_fn"]="PokemonCenterEffectCommands",["label"]="PokemonCenterCard",["name"]="Pokémon Center",["rarity"]="Uncommon",},},["Promotional"]={{["attacks"]={{["damage"]=0,["description"]="Once during your turn (before your attack), you may use this power. Your Active Pokémon and the Defending Pokémon are no longer Asleep, Confused, Paralyzed, or Poisoned.",["effect_fn"]="VenusaurSolarPowerEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Solar Power",},{["damage"]=40,["description"]="Remove a number of damage counters from Venusaur equal to half the damage done to the Defending Pokémon (after applying Weakness and Resistance) (rounded up to the nearest 10).",["effect_fn"]="VenusaurMegaDrainEffectCommands",["energy_cost"]={{["count"]=4,["type"]="Grass",},},["kind"]="Attack",["name"]="Mega Drain",},},["card_type"]="Grass",["evolves_from"]="Ivysaur",["hp"]=100,["label"]="VenusaurLv64Card",["name"]="Venusaur",["rarity"]="Rare",["retreat_cost"]=2,["stage"]="Stage 2",["weakness"]="Fire",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, this attack does 10 damage plus 20 more damage; if tails, this attack does 10 damage.",["effect_fn"]="ArcanineQuickAttackEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Quick Attack",},{["damage"]=40,["description"]="Discard 2 <FIRE> Energy cards attached to Arcanine in order to use this attack. This attack does 40 damage plus 10 more damage for each damage counter on Arcanine.",["effect_fn"]="ArcanineFlamesOfRageEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Fire",},},["kind"]="Attack",["name"]="Flames of Rage",},},["card_type"]="Fire",["evolves_from"]="Growlithe",["hp"]=70,["label"]="ArcanineLv34Card",["name"]="Arcanine",["rarity"]="Promo Star",["retreat_cost"]=1,["stage"]="Stage 1",["weakness"]="Water",},{["attacks"]={{["damage"]=0,["description"]="When you put Moltres into play during your turn (not during set-up), put from 1 to 4 (chosen at random) <FIRE> Energy cards from your deck into your hand. Shuffle your deck afterward.",["effect_fn"]="MoltresFiregiverEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Firegiver",},{["damage"]=70,["description"]="Flip a coin. If tails, this attack does nothing.",["effect_fn"]="MoltresLv37DiveBombEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Fire",},},["kind"]="Attack",["name"]="Dive Bomb",},},["card_type"]="Fire",["hp"]=100,["label"]="MoltresLv37Card",["name"]="Moltres",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=2,["stage"]="Basic",},{["attacks"]={{["damage"]=0,["description"]="When you put Articuno into play during your turn (not during set-up), flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="ArticunoQuickfreezeEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Quickfreeze",},{["damage"]=0,["description"]="Does 40 damage to 1 of your opponent's Pokémon chosen at random. Don't apply Weakness and Resistance for this attack. (Any other effects that would happen after applying Weakness and Resistance still happen.)",["effect_fn"]="ArticunoIceBreathEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Water",},},["kind"]="RESIDUAL",["name"]="Ice Breath",},},["card_type"]="Water",["hp"]=100,["label"]="ArticunoLv37Card",["name"]="Articuno",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=2,["stage"]="Basic",},{["attacks"]={{["damage"]=0,["description"]="If the Defending Pokémon attacks Pikachu during your opponent's next turn, any damage done by the attack is reduced by 10 (after applying Weakness and Resistance).  (Benching or evolving either Pokémon ends this effect.)",["effect_fn"]="PikachuLv16GrowlEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Growl",},{["damage"]=20,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="PikachuLv16ThundershockEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Lightning",},},["kind"]="Attack",["name"]="Thundershock",},},["card_type"]="Lightning",["hp"]=60,["label"]="PikachuLv16Card",["name"]="Pikachu",["rarity"]="Promo Star",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=0,["description"]="If the Defending Pokémon attacks Pikachu during your opponent's next turn, any damage done by the attack is reduced by 10 (after applying Weakness and Resistance).  (Benching or evolving either Pokémon ends this effect.)",["effect_fn"]="PikachuAltLv16GrowlEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Growl",},{["damage"]=20,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="PikachuAltLv16ThundershockEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Lightning",},},["kind"]="Attack",["name"]="Thundershock",},},["card_type"]="Lightning",["hp"]=60,["label"]="PikachuAltLv16Card",["name"]="Pikachu",["rarity"]="Promo Star",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="FlyingPikachuThundershockEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Lightning",},},["kind"]="Attack",["name"]="Thundershock",},{["damage"]=30,["description"]="Flip a coin. If heads, during your opponent's next turn, prevent all effects of attacks, including damage, done to Flying Pikachu.  If tails, this attack does nothing  (not even damage).",["effect_fn"]="FlyingPikachuFlyEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Fly",},},["card_type"]="Lightning",["hp"]=40,["label"]="FlyingPikachuCard",["name"]="Flying Pikachu",["rarity"]="Promo Star",["resistance"]="Fighting",["retreat_cost"]=1,["stage"]="Basic",},{["attacks"]={{["damage"]=30,["energy_cost"]={{["count"]=2,["type"]="Water",},},["kind"]="Attack",["name"]="Surf",},},["card_type"]="Lightning",["hp"]=50,["label"]="SurfingPikachuLv13Card",["name"]="Surfing Pikachu",["rarity"]="Promo Star",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=30,["energy_cost"]={{["count"]=2,["type"]="Water",},},["kind"]="Attack",["name"]="Surf",},},["card_type"]="Lightning",["hp"]=50,["label"]="SurfingPikachuAltLv13Card",["name"]="Surfing Pikachu",["rarity"]="Promo Star",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=0,["description"]="Whenever an attack does damage to Electabuzz (after applying Weakness and Resistance) during your opponent's next turn, that attack only does half the damage to Electabuzz (rounded down to the nearest 10).",["effect_fn"]="ElectabuzzLightScreenEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Lightning",},},["kind"]="RESIDUAL",["name"]="Light Screen",},{["damage"]=10,["description"]="Flip a coin. If heads, this attack does 10 damage plus 20 more damage;  if tails, this attack does 10 damage.",["effect_fn"]="ElectabuzzQuickAttackEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Colorless",},},["kind"]="Attack",["name"]="Quick Attack",},},["card_type"]="Lightning",["hp"]=60,["label"]="ElectabuzzLv20Card",["name"]="Electabuzz",["rarity"]="Promo Star",["retreat_cost"]=2,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=0,["description"]="When you put Zapdos into play during your turn (not during set-up), do 30 damage to a Pokémon other than Zapdos chosen at random. (Don't apply Weakness and Resistance.)",["effect_fn"]="ZapdosPealOfThunderEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Peal of Thunder",},{["damage"]=0,["description"]="Choose a Pokémon other than Zapdos at random. This attack does 70 damage to that Pokémon. Don't apply Weakness and Resistance for this attack. (Any other effects that would happen after applying Weakness and Resistance still happen.)",["effect_fn"]="ZapdosBigThunderEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Lightning",},},["kind"]="RESIDUAL",["name"]="Big Thunder",},},["card_type"]="Lightning",["hp"]=100,["label"]="ZapdosLv68Card",["name"]="Zapdos",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=2,["stage"]="Basic",},{["attacks"]={{["damage"]=10,["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Headbutt",},{["damage"]=0,["description"]="Choose 1 of the Defending Pokémon's attacks. That Pokémon can't use that attack during your opponent's next turn.",["effect_fn"]="SlowpokeAmnesiaEffectCommands",["energy_cost"]={{["count"]=2,["type"]="Psychic",},},["kind"]="Attack",["name"]="Amnesia",},},["card_type"]="Psychic",["hp"]=40,["label"]="SlowpokeLv9Card",["name"]="Slowpoke",["rarity"]="Promo Star",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=0,["description"]="Choose up to 2 Energy cards from your discard pile and attach them to Mewtwo.",["effect_fn"]="MewtwoEnergyAbsorptionEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},},["kind"]="RESIDUAL",["name"]="Energy Absorption",},{["damage"]=40,["energy_cost"]={{["count"]=2,["type"]="Psychic",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Psyburn",},},["card_type"]="Psychic",["hp"]=70,["label"]="MewtwoLv60Card",["name"]="Mewtwo",["rarity"]="Promo Star",["retreat_cost"]=2,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=0,["description"]="Choose up to 2 Energy cards from your discard pile and attach them to Mewtwo.",["effect_fn"]="MewtwoAltEnergyAbsorptionEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},},["kind"]="RESIDUAL",["name"]="Energy Absorption",},{["damage"]=40,["energy_cost"]={{["count"]=2,["type"]="Psychic",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Psyburn",},},["card_type"]="Psychic",["hp"]=70,["label"]="MewtwoAltLV60Card",["name"]="Mewtwo",["rarity"]="Promo Star",["retreat_cost"]=2,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=0,["description"]="Prevent all effects of attacks, including damage, done to Mew by evolved Pokémon (excluding your own). This power stops working while Mew is Asleep, Confused, or Paralyzed.",["effect_fn"]="MewNeutralizingShieldEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Neutralizing Shield",},{["damage"]=10,["description"]="Flip a coin. If heads, the Defending Pokémon is now Paralyzed.",["effect_fn"]="MewPsyshockEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},},["kind"]="Attack",["name"]="Psyshock",},},["card_type"]="Psychic",["hp"]=40,["label"]="MewLv8Card",["name"]="Mew",["rarity"]="Promo Star",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=0,["description"]="Does a random amount of damage to the Defending Pokémon and may cause a random effect to the Defending Pokémon.",["effect_fn"]="MewMysteryAttackEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Psychic",},{["count"]=1,["type"]="Colorless",},},["kind"]="Attack",["name"]="Mystery Attack",},},["card_type"]="Psychic",["hp"]=50,["label"]="MewLv15Card",["name"]="Mew",["rarity"]="Rare",["retreat_cost"]=0,["stage"]="Basic",["weakness"]="Psychic",},{["attacks"]={{["damage"]=0,["description"]="Remove 1 damage counter from Jigglypuff.",["effect_fn"]="JigglypuffFirstAidEffectCommands",["energy_cost"]={{["count"]=1,["type"]="Colorless",},},["kind"]="RESIDUAL",["name"]="First Aid",},{["damage"]=40,["description"]="Jigglypuff does 20 damage to itself.",["effect_fn"]="JigglypuffDoubleEdgeEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="Attack",["name"]="Double-edge",},},["card_type"]="Colorless",["hp"]=50,["label"]="JigglypuffLv12Card",["name"]="Jigglypuff",["rarity"]="Promo Star",["resistance"]="Psychic",["retreat_cost"]=1,["stage"]="Basic",["weakness"]="Fighting",},{["attacks"]={{["damage"]=0,["description"]="When you put Dragonite into play, remove 2 damage counters from each of your Pokémon. If a Pokémon has  fewer damage counters than that, remove all of them from that Pokémon.",["effect_fn"]="DragoniteHealingWindEffectCommands",["energy_cost"]={},["kind"]="Pokemon Power",["name"]="Healing Wind",},{["damage"]=30,["description"]="Flip 2 coins. This attack does 30 damage times the number of heads.",["effect_fn"]="DragoniteLv41SlamEffectCommands",["energy_cost"]={{["count"]=3,["type"]="Colorless",},},["kind"]="DAMAGE_X",["name"]="Slam",},},["card_type"]="Colorless",["evolves_from"]="Dragonair",["hp"]=100,["label"]="DragoniteLv41Card",["name"]="Dragonite",["rarity"]="Rare",["resistance"]="Fighting",["retreat_cost"]=2,["stage"]="Stage 2",},{["card_type"]="Trainer",["description"]="Your Active Pokémon is now Confused. Imakuni wants you to play him as a Basic Pokémon, but you can't. A mysterious creature not listed in the Pokédex. He asks kids around the world,”Who is cuter-Pikachu or me?”",["effect_fn"]="ImakuniEffectCommands",["label"]="ImakuniCard",["name"]="Imakuni?",["rarity"]="Promo Star",},{["card_type"]="Trainer",["description"]="Trade 2 of the other cards in your hand for up to 4 basic Energy cards from your discard pile.",["effect_fn"]="SuperEnergyRetrievalEffectCommands",["label"]="SuperEnergyRetrievalCard",["name"]="Super Energy Retrieval",["rarity"]="Promo Star",},},}

  local TCG_BY_LABEL={}
  local TCG_POOLS={}
  local TCG_SET_ORDER={"Colosseum","Evolution","Mystery","Laboratory","Promotional","Energy"}
  for set,cards in pairs(TCG_DB or {}) do
    TCG_POOLS[set]={}
    for _,c in ipairs(cards or {}) do
      c.set=set
      TCG_BY_LABEL[c.label]=c
      TCG_POOLS[set][c.rarity]=TCG_POOLS[set][c.rarity] or {}
      local r=TCG_POOLS[set][c.rarity]
      r[c.card_type]=r[c.card_type] or {}
      r[c.card_type][#r[c.card_type]+1]=c.label
    end
  end

  local TCG_PACKS={
    COLOSSEUM={item="TCG_COLOSSEUM_PACK",set="Colosseum",variant="BoosterPack_ColosseumNeutral",art="colosseum"},
    EVOLUTION={item="TCG_EVOLUTION_PACK",set="Evolution",variant="BoosterPack_EvolutionNeutral",art="evolution"},
    MYSTERY={item="TCG_MYSTERY_PACK",set="Mystery",variant="BoosterPack_MysteryNeutral",art="mystery"},
    LABORATORY={item="TCG_LABORATORY_PACK",set="Laboratory",variant="BoosterPack_LaboratoryMostlyNeutral",art="laboratory"},
  }
  local TCG_ITEM_TO_SET={}
  for key,p in pairs(TCG_PACKS) do TCG_ITEM_TO_SET[p.item]=key end

  -- Exact 60-card starter lists from the supplied TCG package's
  -- data/ai_and_deck_mechanics.lua. The attendant gives one choice free;
  -- the other starter recipes can later be bought from the same counter.
  local TCG_STARTER_ORDER={"CHARMANDER","SQUIRTLE","BULBASAUR"}
  local TCG_STARTER_PRICE=100
  local TCG_STARTER_DECKS={
    CHARMANDER={source="CharmanderAndFriendsDeck",label="CHARMANDER",name="Charmander & Friends",cards={["FireEnergyCard"]=10, ["LightningEnergyCard"]=8, ["FightingEnergyCard"]=6, ["CharmanderCard"]=2, ["CharmeleonCard"]=1, ["CharizardCard"]=1, ["GrowlitheCard"]=2, ["ArcanineLv45Card"]=1, ["PonytaCard"]=2, ["MagmarLv24Card"]=1, ["PikachuLv12Card"]=2, ["RaichuLv40Card"]=1, ["MagnemiteLv13Card"]=2, ["MagnetonLv28Card"]=1, ["ZapdosLv64Card"]=1, ["DiglettCard"]=2, ["DugtrioCard"]=1, ["MachopCard"]=1, ["MachokeCard"]=1, ["RattataCard"]=2, ["RaticateCard"]=1, ["MeowthLv14Card"]=1, ["ProfessorOakCard"]=1, ["BillCard"]=2, ["SwitchCard"]=1, ["ComputerSearchCard"]=1, ["PlusPowerCard"]=1, ["PotionCard"]=2, ["FullHealCard"]=2}},
    SQUIRTLE={source="SquirtleAndFriendsDeck",label="SQUIRTLE",name="Squirtle & Friends",cards={["WaterEnergyCard"]=11, ["FightingEnergyCard"]=6, ["PsychicEnergyCard"]=8, ["SquirtleCard"]=2, ["WartortleCard"]=1, ["BlastoiseCard"]=1, ["SeelCard"]=2, ["DewgongCard"]=1, ["StaryuCard"]=1, ["StarmieCard"]=1, ["GoldeenCard"]=1, ["SeakingCard"]=1, ["LaprasCard"]=1, ["AbraCard"]=2, ["KadabraCard"]=1, ["GastlyLv8Card"]=2, ["HaunterLv22Card"]=1, ["MachopCard"]=1, ["MachokeCard"]=1, ["GeodudeCard"]=2, ["HitmonchanCard"]=1, ["RattataCard"]=2, ["RaticateCard"]=1, ["MeowthLv14Card"]=1, ["ProfessorOakCard"]=1, ["BillCard"]=1, ["SwitchCard"]=1, ["PokeBallCard"]=1, ["ScoopUpCard"]=1, ["ItemFinderCard"]=1, ["PotionCard"]=1, ["FullHealCard"]=1}},
    BULBASAUR={source="BulbasaurAndFriendsDeck",label="BULBASAUR",name="Bulbasaur & Friends",cards={["GrassEnergyCard"]=11, ["FireEnergyCard"]=3, ["WaterEnergyCard"]=9, ["BulbasaurCard"]=2, ["IvysaurCard"]=1, ["VenusaurLv67Card"]=1, ["CaterpieCard"]=2, ["MetapodCard"]=1, ["NidoranFCard"]=2, ["NidoranMCard"]=2, ["NidorinoCard"]=1, ["TangelaLv12Card"]=1, ["FlareonLv28Card"]=1, ["SeelCard"]=1, ["DewgongCard"]=1, ["KrabbyCard"]=2, ["KinglerCard"]=1, ["GoldeenCard"]=2, ["SeakingCard"]=1, ["VaporeonLv42Card"]=1, ["JigglypuffLv14Card"]=1, ["MeowthLv14Card"]=1, ["EeveeCard"]=2, ["KangaskhanCard"]=1, ["ProfessorOakCard"]=1, ["SwitchCard"]=1, ["PokeBallCard"]=1, ["PlusPowerCard"]=2, ["DefenderCard"]=1, ["FullHealCard"]=2, ["ReviveCard"]=1}},
  }

  local function tcgState(game)
    local q=normalizePokopiaSave(game.save)
    q.tcg=type(q.tcg)=="table" and q.tcg or {}
    local t=q.tcg
    t.collection=type(t.collection)=="table" and t.collection or {}
    t.deck=type(t.deck)=="table" and t.deck or {name="CELADON DECK",cards={}}
    t.deck.cards=type(t.deck.cards)=="table" and t.deck.cards or {}
    t.freePacksUsed=math.max(0,tonumber(t.freePacksUsed) or 0)
    t.packsOpened=math.max(0,tonumber(t.packsOpened) or 0)
    t.starterDecksOwned=type(t.starterDecksOwned)=="table" and t.starterDecksOwned or {}
    if t.starterDeckClaimed and TCG_STARTER_DECKS[t.starterDeckClaimed] then
      t.starterDecksOwned[t.starterDeckClaimed]=true
    end
    if t.packsOpened>0 then t.binderUnlocked=true end

    -- One-time migration from the pre-1.0.321 parallel pack table into the
    -- actual Bag. If the Bag cannot accept a stack yet, leave that stack in
    -- place and retry next time instead of deleting it.
    if not t.packBagMigration321 and type(q.cardPackInventory)=="table" then
      local Bag=require("src.inventory.Bag")
      local left=false
      for key,p in pairs(TCG_PACKS) do
        local n=math.max(0,math.floor(tonumber(q.cardPackInventory[key]) or 0))
        if n>0 then
          if Bag.add(game.save,p.item,n,game.data) then
            q.cardPackInventory[key]=nil
          else
            left=true
          end
        end
      end
      if not left then t.packBagMigration321=true end
    end
    return t
  end

  local function tcgSafe(s)
    s=tostring(s or "")
    s=s:gsub("Pokémon","POKeMON"):gsub("Poké","POKe")
    s=s:gsub("é","e"):gsub("♀","F"):gsub("♂","M")
    s=s:gsub("<([A-Z ]+)>","%1")
    return s
  end

  local tcgImageCache={}
  local function tcgImage(path)
    if not path then return nil end
    if tcgImageCache[path]~=nil then return tcgImageCache[path] or nil end
    local ok,img=pcall(function()
      if mod.assets and mod.assets.image then
        return mod.assets:image("assets/tcg/graphics/"..path)
      end
      return love.graphics.newImage(tostring(mod.path).."/assets/tcg/graphics/"..path)
    end)
    if ok and img and img.setFilter then img:setFilter("nearest","nearest") end
    tcgImageCache[path]=ok and img or false
    return ok and img or nil
  end
  local function tcgCardImage(label)
    local a=TCG_ART and TCG_ART.cards and TCG_ART.cards[label]
    return a and tcgImage("cards/"..a.art_file) or nil
  end
  local function tcgMarkTrueColor(x,y,w,h)
    local ok,fx=pcall(require,"src.render.PaletteFX")
    if ok and fx and fx.markTrueColor then fx.markTrueColor(x,y,w,h) end
  end

  local function tcgWeightedType(weights)
    local keys,total={},0
    for k,w in pairs(weights or {}) do
      if (tonumber(w) or 0)>0 then keys[#keys+1]=k; total=total+(tonumber(w) or 0) end
    end
    table.sort(keys)
    if total<=0 then return nil end
    local roll=love.math.random()*total
    local sum=0
    for _,k in ipairs(keys) do
      sum=sum+(tonumber(weights[k]) or 0)
      if roll<sum then return k end
    end
    return keys[#keys]
  end

  local function tcgPickCard(setName,rarity,ctype)
    local byType=TCG_POOLS[setName] and TCG_POOLS[setName][rarity]
    if not byType then return nil end
    local pool=byType[ctype]
    if not pool or #pool==0 then
      pool={}
      for _,list in pairs(byType) do
        for _,label in ipairs(list) do pool[#pool+1]=label end
      end
    end
    return #pool>0 and pool[love.math.random(1,#pool)] or nil
  end

  local BASIC_ENERGY={
    GRASS_ENERGY="GrassEnergyCard",FIRE_ENERGY="FireEnergyCard",
    WATER_ENERGY="WaterEnergyCard",LIGHTNING_ENERGY="LightningEnergyCard",
    FIGHTING_ENERGY="FightingEnergyCard",PSYCHIC_ENERGY="PsychicEnergyCard",
  }
  local BASIC_ENERGY_LIST={"GrassEnergyCard","FireEnergyCard","WaterEnergyCard","LightningEnergyCard","FightingEnergyCard","PsychicEnergyCard"}
  local function tcgEnergy(source)
    if BASIC_ENERGY[source] then return BASIC_ENERGY[source] end
    return BASIC_ENERGY_LIST[love.math.random(1,#BASIC_ENERGY_LIST)]
  end

  -- Mirrors booster_packs_data.lua: fixed rarity slots, weighted card types,
  -- and the source file's stated anti-streak rule that reduces a selected
  -- type's remaining weight by the variant's original average after a pull.
  local function tcgGeneratePack(setKey)
    local p=TCG_PACKS[setKey]
    local variant=p and TCG_BOOSTERS.variants[p.variant]
    local slots=p and TCG_BOOSTERS.rarity_slots[setKey]
    if not (p and variant and slots) then return {} end
    local out={}
    for _=1,(slots.energies or 0) do out[#out+1]=tcgEnergy(variant.energy_source) end
    local weights={}; local total,n=0,0
    for k,w in pairs(variant.type_chances or {}) do
      weights[k]=tonumber(w) or 0; total=total+weights[k]; n=n+1
    end
    -- raw_source_reference/booster_pack_odds.asm performs integer division
    -- across the nine stored chance bytes: 160 / 9 = 17 for normal packs.
    -- After a type is drawn, subtract that original average and clamp to 1.
    local drop=(n>0) and math.floor(total/n) or 0
    local function fill(rarity,count)
      for _=1,(count or 0) do
        local typ=tcgWeightedType(weights)
        local label
        if typ=="Energy" then label=tcgEnergy("GenerateRandomEnergy")
        else label=tcgPickCard(p.set,rarity,typ) end
        if label then out[#out+1]=label end
        if typ and (weights[typ] or 0)>0 then
          weights[typ]=math.max(1,(weights[typ] or 0)-drop)
        end
      end
    end
    fill("Common",slots.commons); fill("Uncommon",slots.uncommons); fill("Rare",slots.rares)
    return out
  end

  -- Fit TCG labels to a pixel budget using the engine font's glyph spans.
  -- This keeps long card/set names inside Gen I text-box borders and avoids
  -- splitting multibyte symbols such as Nidoran's gender glyph.
  local function tcgFit(text,maxPixels)
    local Font=require("src.render.Font")
    text=tcgSafe(text)
    if Font.width(text)<=maxPixels then return text end
    local spans=Font.split(text)
    local out=""
    for i=1,#spans do
      local ch=text:sub(spans[i].from,spans[i].to)
      if Font.width(out..ch..".")>maxPixels then break end
      out=out..ch
    end
    return out.."."
  end

  -- Compact Pokemon TCG GB-style menu used by every custom TCG list outside
  -- the duel itself.  Keeping these screens on the source half-width font
  -- gives us a predictable 4px glyph advance inside the real 160x144 safe
  -- area, so card names, quantities, status text and footers cannot collide.
  local TCG_MENU_SYM={
    CURSOR_U=0x0c,CURSOR_R=0x0f,
    BOX_TOP_L=0x18,BOX_TOP_R=0x19,BOX_BTM_L=0x1a,BOX_BTM_R=0x1b,
    BOX_TOP=0x1c,BOX_BTM=0x1d,BOX_LEFT=0x1e,BOX_RIGHT=0x1f,
    CURSOR_D=0x2f,
  }
  local tcgMenuHalfQuads,tcgMenuSymbolQuads={},{}

  local function tcgMenuAscii(text)
    text=tcgSafe(text)
    text=text:gsub("’","'"):gsub("“",'"'):gsub("”",'"')
    return text
  end

  local function tcgMenuHalfQuad(font,index)
    if not font then return nil end
    local q=tcgMenuHalfQuads[index]
    if q then return q end
    local iw,ih=font:getDimensions()
    local col,row=index%8,math.floor(index/8)
    q=love.graphics.newQuad(col*8,row*8,8,8,iw,ih)
    tcgMenuHalfQuads[index]=q
    return q
  end

  local function tcgMenuSymbolQuad(font,index)
    if not font then return nil end
    local q=tcgMenuSymbolQuads[index]
    if q then return q end
    local iw,ih=font:getDimensions()
    local col,row=index%8,math.floor(index/8)
    q=love.graphics.newQuad(col*8,row*8,8,8,iw,ih)
    tcgMenuSymbolQuads[index]=q
    return q
  end

  local function tcgMenuWidth(text)
    text=tcgMenuAscii(text)
    local longest,cur=0,0
    for i=1,#text do
      if text:byte(i)==10 then longest=math.max(longest,cur); cur=0
      else cur=cur+4 end
    end
    return math.max(longest,cur)
  end

  local function tcgMenuFit(text,pixels)
    text=tcgMenuAscii(text)
    if tcgMenuWidth(text)<=pixels then return text end
    local maxChars=math.max(1,math.floor((tonumber(pixels) or 4)/4))
    if maxChars<=1 then return "." end
    return text:sub(1,maxChars-1).."."
  end

  local function tcgMenuDrawText(text,x,y)
    text=tcgMenuAscii(text)
    local halfFont=tcgImage("ui/half_width.png")
    if not halfFont then
      local Font=require("src.render.Font")
      love.graphics.push(); love.graphics.scale(0.5,1)
      Font.draw(text,x*2,y)
      love.graphics.pop()
      return
    end
    love.graphics.setColor(1,1,1,1)
    local dx=x
    for i=1,#text do
      local b=text:byte(i)
      if b==10 then y=y+8; dx=x
      else
        if b<0x20 or b>0x7f then b=string.byte("?") end
        local q=tcgMenuHalfQuad(halfFont,b-0x20)
        if q then love.graphics.draw(halfFont,q,dx,y) end
        dx=dx+4
      end
    end
  end

  local function tcgMenuDrawSymbol(index,x,y)
    local symbolFont=tcgImage("ui/symbols_font.png")
    if symbolFont then
      local q=tcgMenuSymbolQuad(symbolFont,index)
      if q then
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(symbolFont,q,x,y)
        return
      end
    end
    love.graphics.setColor(0,0,0,1)
    love.graphics.rectangle("line",x+1,y+1,5,5)
  end

  local function tcgMenuDrawBox(x,y,wTiles,hTiles)
    local w,h=wTiles*8,hTiles*8
    love.graphics.setColor(1,1,1,1)
    love.graphics.rectangle("fill",x,y,w,h)
    tcgMenuDrawSymbol(TCG_MENU_SYM.BOX_TOP_L,x,y)
    tcgMenuDrawSymbol(TCG_MENU_SYM.BOX_TOP_R,x+w-8,y)
    tcgMenuDrawSymbol(TCG_MENU_SYM.BOX_BTM_L,x,y+h-8)
    tcgMenuDrawSymbol(TCG_MENU_SYM.BOX_BTM_R,x+w-8,y+h-8)
    for xx=x+8,x+w-16,8 do
      tcgMenuDrawSymbol(TCG_MENU_SYM.BOX_TOP,xx,y)
      tcgMenuDrawSymbol(TCG_MENU_SYM.BOX_BTM,xx,y+h-8)
    end
    for yy=y+8,y+h-16,8 do
      tcgMenuDrawSymbol(TCG_MENU_SYM.BOX_LEFT,x,yy)
      tcgMenuDrawSymbol(TCG_MENU_SYM.BOX_RIGHT,x+w-8,yy)
    end
  end

  local function tcgMenuFooterLines(text)
    text=tcgMenuAscii(text or "")
    local lines={}
    for explicit in (text.."\n"):gmatch("(.-)\n") do
      if #explicit<=34 then lines[#lines+1]=explicit
      else
        local line=""
        for word in explicit:gmatch("%S+") do
          if #line==0 then line=word
          elseif #line+1+#word<=34 then line=line.." "..word
          else lines[#lines+1]=line; line=word end
        end
        if line~="" then lines[#lines+1]=line end
      end
    end
    return lines
  end

  local function tcgMenu(game,title,rows,onPick,onCancel,opts)
    local Sound=require("src.core.Sound")
    opts=opts or {}; rows=rows or {}
    local menu={isOpaque=true,index=1,scroll=0,items=rows}
    menu.visible=math.max(1,math.min(5,tonumber(opts.visible) or 5))

    local function clamp(self)
      local n=#self.items
      if n<=0 then self.index,self.scroll=1,0; return end
      self.index=math.max(1,math.min(n,self.index))
      if self.index-self.scroll>self.visible then self.scroll=self.index-self.visible end
      if self.index-self.scroll<1 then self.scroll=self.index-1 end
    end

    function menu:update()
      local input=game.input; local n=#self.items
      if input:wasPressed("up") and n>0 then
        self.index=self.index>1 and self.index-1 or n; clamp(self)
        Sound.play(game.data,"Press_AB")
      elseif input:wasPressed("down") and n>0 then
        self.index=self.index<n and self.index+1 or 1; clamp(self)
        Sound.play(game.data,"Press_AB")
      elseif input:wasPressed("b") then
        Sound.play(game.data,"Press_AB")
        if game.stack:top()==self then game.stack:pop() end
        if onCancel then onCancel() end
      elseif input:wasPressed("a") and n>0 then
        Sound.play(game.data,"Press_AB")
        local row,idx=self.items[self.index],self.index
        if game.stack:top()==self then game.stack:pop() end
        if onPick then onPick(row,idx) end
      end
    end

    function menu:draw()
      love.graphics.setColor(1,1,1,1)
      love.graphics.rectangle("fill",0,0,160,144)
      -- Match the duel card-list geometry: five safe list rows above a
      -- dedicated two-line footer box.  The shared 104px border is deliberate.
      tcgMenuDrawBox(0,0,20,14)
      tcgMenuDrawBox(0,104,20,5)

      local status=opts.status and tcgMenuFit(opts.status,136) or nil
      tcgMenuDrawText(tcgMenuFit(title or "POKeMON TCG",136),8,8)
      if status and status~="" then tcgMenuDrawText(status,8,16) end

      local firstY=24
      for slot=1,self.visible do
        local idx=self.scroll+slot
        local row=self.items[idx]
        if not row then break end
        local source=type(row)=="table" and row or {label=tostring(row)}
        local y=firstY+(slot-1)*16
        local right=source.right and tcgMenuFit(source.right,56) or nil
        local rightX=right and (144-tcgMenuWidth(right)) or 144
        local labelX=20
        local budget=math.max(16,rightX-labelX-(right and 4 or 0))
        tcgMenuDrawText(tcgMenuFit(source.label or "",budget),labelX,y)
        if right then tcgMenuDrawText(right,rightX,y) end
        if idx==self.index then tcgMenuDrawSymbol(TCG_MENU_SYM.CURSOR_R,8,y) end
      end

      if self.scroll>0 then tcgMenuDrawSymbol(TCG_MENU_SYM.CURSOR_U,144,16) end
      if self.scroll+self.visible<#self.items then tcgMenuDrawSymbol(TCG_MENU_SYM.CURSOR_D,144,96) end

      local footer=opts.footer
      if footer==nil then footer="A SELECT  B BACK" end
      local lines=tcgMenuFooterLines(footer)
      if lines[1] then tcgMenuDrawText(tcgMenuFit(lines[1],136),8,112) end
      if lines[2] then tcgMenuDrawText(tcgMenuFit(lines[2],136),8,128) end
      love.graphics.setColor(1,1,1,1)
    end

    game.stack:push(menu)
    return menu
  end

  local function tcgSay(game,text,after)
    local TextBox=require("src.render.TextBox")
    game.stack:push(TextBox.new(game,tcgSafe(text),after,{speaker="ATTENDANT"}))
  end


  local function tcgCopyCardCounts(cards)
    local out={}
    for label,count in pairs(cards or {}) do out[label]=tonumber(count) or 0 end
    return out
  end

  local function tcgDeckHasCards(deck)
    for _,count in pairs((deck and deck.cards) or {}) do
      if (tonumber(count) or 0)>0 then return true end
    end
    return false
  end

  local function tcgGrantStarterDeck(game,key,isFree,repeatable)
    local def=TCG_STARTER_DECKS[key]
    if not def then return false,false end
    local t=tcgState(game)
    if t.starterDecksOwned[key] and not repeatable then return false,false end
    for label,count in pairs(def.cards) do
      t.collection[label]=(tonumber(t.collection[label]) or 0)+(tonumber(count) or 0)
    end
    t.starterDecksOwned[key]=true
    if isFree then t.starterDeckClaimed=key end
    -- New players immediately receive a playable 60-card active deck.
    -- Existing hand-built decks are never overwritten by the migration.
    local activated=not tcgDeckHasCards(t.deck)
    if activated then
      t.deck.name=def.name
      t.deck.cards=tcgCopyCardCounts(def.cards)
    end
    return true,activated
  end

  local function tcgWrap(text,width)
    local out,line={},""
    for word in tcgSafe(text):gmatch("%S+") do
      if #line==0 then line=word
      elseif #line+1+#word<=width then line=line.." "..word
      else out[#out+1]=line; line=word end
    end
    if #line>0 then out[#out+1]=line end
    return out
  end

  local function tcgDrawCardArt(label,x,y,scale)
    local img=tcgCardImage(label)
    if img then
      scale=scale or 1
      love.graphics.setColor(1,1,1,1); love.graphics.draw(img,x,y,0,scale,scale)
      local w,h=img:getDimensions(); tcgMarkTrueColor(x,y,w*scale,h*scale)
    end
  end

  local function tcgDrawCardReveal(card,index,total)
    love.graphics.setColor(1,1,1,1)
    love.graphics.rectangle("fill",0,0,160,144)
    tcgMenuDrawBox(0,0,20,18)

    -- The reveal uses the same 160x144 TCG card-screen language as the Binder
    -- and duel sub-screens.  Header, art, metadata and controls each own a
    -- fixed source-style row, so no RPG-font text can overrun the frame.
    local counter=("CARD %d/%d"):format(index,total)
    local counterW=tcgMenuWidth(counter)
    tcgMenuDrawText(tcgMenuFit(card and card.name or "UNKNOWN CARD",132-counterW),8,8)
    tcgMenuDrawText(counter,152-counterW,8)

    tcgDrawCardArt(card and card.label,48,24,1)

    local meta=tcgSafe((card and card.set or "?").." / "..(card and card.rarity or "?"))
    tcgMenuDrawText(tcgMenuFit(meta,144),8,80)
    if card and card.hp then
      tcgMenuDrawText(tcgMenuFit(tcgSafe(card.card_type).."  HP "..tostring(card.hp),144),8,88)
      tcgMenuDrawText(tcgMenuFit(tcgSafe(card.stage or "").."  RET "..tostring(card.retreat_cost or 0),144),8,96)
    else
      tcgMenuDrawText(tcgMenuFit(card and card.card_type or "",144),8,88)
    end

    tcgMenuDrawBox(0,104,20,5)
    local prompt=index<total and "A NEXT" or "A FINISH"
    tcgMenuDrawText(prompt,8,120)
    love.graphics.setColor(1,1,1,1)
  end

  local openAnotherPackPrompt

  local function openPackAnimation(game,setKey,cards,firstUnlock,onDone)
    local Sound=require("src.core.Sound")
    local p=TCG_PACKS[setKey]
    -- The source PNGs are raw 96-tile sheets, not screen-ready sprites. The
    -- packaged assembled image rebuilds the original 8x12 booster scene. Its
    -- 32 OAM tiles are then placed using the supplied booster scene table and
    -- Gen I's Y,X OAM coordinate order, yielding the original 64x32 logo block.
    local artFile="booster_packs/assembled/"..tostring(p.art)..".png"
    local screen={isOpaque=true,phase="sealed",timer=0,index=1,artFile=artFile}
    local function finishPackScreen()
      if game.stack:top()==screen then game.stack:pop() end
      if onDone then onDone() end
    end
    function screen:update()
      self.timer=self.timer+1
      local input=game.input
      if self.phase=="sealed" and input:wasPressed("a") then
        Sound.play(game.data,"Press_AB"); self.phase="rip"; self.timer=0
      elseif self.phase=="rip" and self.timer>=28 then
        self.phase="cards"; self.timer=0
      elseif self.phase=="cards" and input:wasPressed("a") then
        Sound.play(game.data,"Press_AB")
        if self.index<#cards then self.index=self.index+1
        elseif firstUnlock then self.phase="unlock" else finishPackScreen() end
      elseif self.phase=="unlock" and (input:wasPressed("a") or input:wasPressed("b")) then
        Sound.play(game.data,"Press_AB"); finishPackScreen()
      end
    end
    function screen:draw()
      love.graphics.setColor(1,1,1,1)
      love.graphics.rectangle("fill",0,0,160,144)
      if self.phase=="cards" then
        tcgDrawCardReveal(TCG_BY_LABEL[cards[self.index]],self.index,#cards)
        return
      end

      tcgMenuDrawBox(0,0,20,18)
      if self.phase=="unlock" then
        tcgMenuDrawText("BINDER UNLOCKED!",8,40)
        tcgMenuDrawText("Cards can now be viewed",8,64)
        tcgMenuDrawText("from the START menu.",8,72)
        tcgMenuDrawText("A CONTINUE",8,120)
        love.graphics.setColor(1,1,1,1)
        return
      end

      local packTitle=tcgMenuFit(setKey.." PACK",144)
      tcgMenuDrawText(packTitle,80-math.floor(tcgMenuWidth(packTitle)/2),8)
      local img=tcgImage(self.artFile)
      if img then
        local iw,ih=img:getDimensions(); local x,y=48,24
        if self.phase=="sealed" then
          love.graphics.setColor(1,1,1,1)
          love.graphics.draw(img,x,y)
          tcgMarkTrueColor(x,y,iw,ih)
        else
          -- Tear across the wrapper at one tenth of its height, like pulling
          -- the sealed top strip away rather than splitting the pack down its
          -- middle. On a 64x96 source scene this seam is about 10 px from top.
          local cut=math.max(1,math.floor(ih*0.10+0.5))
          local top=love.graphics.newQuad(0,0,iw,cut,iw,ih)
          local body=love.graphics.newQuad(0,cut,iw,ih-cut,iw,ih)
          local d=math.min(28,self.timer)
          local topX=x-d*0.75
          local topY=y-d*0.45
          local bodyX=x+math.min(3,d*0.10)
          local bodyY=y+cut+math.min(5,d*0.18)
          love.graphics.setColor(1,1,1,1)
          love.graphics.draw(img,top,topX,topY)
          love.graphics.draw(img,body,bodyX,bodyY)
          tcgMarkTrueColor(topX,topY,iw,cut)
          tcgMarkTrueColor(bodyX,bodyY,iw,ih-cut)
          local tearY=bodyY
          love.graphics.setColor(0,0,0,1)
          love.graphics.line(bodyX,tearY,bodyX+8,tearY-2,bodyX+16,tearY+1,bodyX+24,tearY-2,bodyX+32,tearY+1,bodyX+40,tearY-1,bodyX+48,tearY+2,bodyX+56,tearY-1,bodyX+64,tearY)
        end
      end
      local prompt=self.phase=="sealed" and "A OPEN" or "RIPPING..."
      tcgMenuDrawText(prompt,80-math.floor(tcgMenuWidth(prompt)/2),128)
      love.graphics.setColor(1,1,1,1)
    end
    game.stack:push(screen)
  end

  -- TCG-styled YES/NO prompt.  It stays transparent so the game world remains
  -- visible behind the card-game box, but the prompt itself uses the GB1 font,
  -- frame and cursor.  YES is intentionally the default for chained boosters.
  local function tcgYesNoPrompt(game,text,onChoice,defaultNo)
    local Sound=require("src.core.Sound")
    local prompt={isOpaque=false,index=defaultNo and 2 or 1}
    function prompt:update()
      local input=game.input
      if input:wasPressed("up") or input:wasPressed("down")
          or input:wasPressed("left") or input:wasPressed("right") then
        self.index=self.index==1 and 2 or 1
        Sound.play(game.data,"Press_AB")
      elseif input:wasPressed("b") then
        Sound.play(game.data,"Press_AB")
        if game.stack:top()==self then game.stack:pop() end
        if onChoice then onChoice(false) end
      elseif input:wasPressed("a") then
        Sound.play(game.data,"Press_AB")
        local yes=self.index==1
        if game.stack:top()==self then game.stack:pop() end
        if onChoice then onChoice(yes) end
      end
    end
    function prompt:draw()
      tcgMenuDrawBox(0,88,20,7)
      tcgMenuDrawText(tcgMenuFit(text or "",104),8,96)
      local choices={{"YES",112},{"NO",128}}
      for i,row in ipairs(choices) do
        if i==self.index then tcgMenuDrawSymbol(TCG_MENU_SYM.CURSOR_R,112,row[2]) end
        tcgMenuDrawText(row[1],124,row[2])
      end
      love.graphics.setColor(1,1,1,1)
    end
    game.stack:push(prompt)
  end

  -- After a booster finishes, keep opening friction low: if any physical TCG
  -- packs remain in the Bag, ask whether to open another. YES is preselected;
  -- selecting it opens a source-font expansion list with live Bag quantities.
  openAnotherPackPrompt=function(game)
    local Bag=require("src.inventory.Bag")
    local order={"COLOSSEUM","EVOLUTION","MYSTERY","LABORATORY"}

    local function availableRows()
      local rows={}
      local inv=(game.save and game.save.inventory) or {}
      for _,key in ipairs(order) do
        local pack=TCG_PACKS[key]
        local count=pack and math.max(0,tonumber(inv[pack.item]) or 0) or 0
        if count>0 then
          rows[#rows+1]={
            label=tcgSafe((pack.set or key).." PACK"),
            right="x"..tostring(count),
            key=key,
          }
        end
      end
      return rows
    end

    if #availableRows()==0 then return end
    tcgYesNoPrompt(game,"Open another pack?",function(yes)
      if not yes then return end
      local rows=availableRows()
      if #rows==0 then return end
      tcgMenu(game,"OPEN WHICH PACK?",rows,function(row)
        local key=row and row.key
        local pack=key and TCG_PACKS[key]
        local inv=(game.save and game.save.inventory) or {}
        if not (pack and (tonumber(inv[pack.item]) or 0)>0) then
          openAnotherPackPrompt(game)
          return
        end
        local cards=tcgGeneratePack(key)
        if #cards~=10 then
          tcgSay(game,"This pack could not be opened.\nIts source card table is incomplete.",
            function() openAnotherPackPrompt(game) end)
          return
        end
        Bag.remove(game.save,pack.item,1)
        local t=tcgState(game)
        for _,label in ipairs(cards) do
          t.collection[label]=(tonumber(t.collection[label]) or 0)+1
        end
        t.packsOpened=(tonumber(t.packsOpened) or 0)+1
        t.binderUnlocked=true
        openPackAnimation(game,key,cards,false,function() openAnotherPackPrompt(game) end)
      end,function()
        -- Cancelling the pack picker is equivalent to answering NO.
      end,{footer="A SELECT  B CANCEL"})
    end,false)
  end

  -- Attach the runtime implementation to the item-effect bridge that was
  -- registered during mod load. Do not mutate mod.content.item_effects here:
  -- Gen1Recomp freezes content registries before this story function runs.
  tcgOpenPackEffectUse=function(ctx)
    local game=liveGame
    local id=ctx and ctx.itemId
    local setKey=TCG_ITEM_TO_SET[id]
    if not game or not setKey then
      return "failed",{"This pack could not be opened."}
    end
    local cards=tcgGeneratePack(setKey)
    if #cards~=10 then
      return "failed",{"This pack could not be opened.\nIts source card table is incomplete."}
    end
    local t=tcgState(game)
    local firstUnlock=not t.binderUnlocked
    for _,label in ipairs(cards) do
      t.collection[label]=(tonumber(t.collection[label]) or 0)+1
    end
    t.packsOpened=t.packsOpened+1
    t.binderUnlocked=true
    openPackAnimation(game,setKey,cards,firstUnlock,function() openAnotherPackPrompt(game) end)
    return "consumed",{}
  end

  local function tcgDetailPages(card)
    local pages={}
    local function addChunks(lines)
      local i=1
      while i<=#lines do
        local chunk={}
        for j=i,math.min(i+5,#lines) do chunk[#chunk+1]=lines[j] end
        pages[#pages+1]=chunk
        i=i+6
      end
    end
    local p1={tcgSafe(card.set).." / "..tcgSafe(card.rarity),tcgSafe(card.card_type)}
    if card.hp then
      p1[#p1+1]="HP "..tostring(card.hp).."  "..tcgSafe(card.stage)
      if card.evolves_from then p1[#p1+1]="FROM "..tcgSafe(card.evolves_from) end
      p1[#p1+1]="WEAK "..tcgSafe(card.weakness or "NONE")
      p1[#p1+1]="RES "..tcgSafe(card.resistance or "NONE").." RET "..tostring(card.retreat_cost or 0)
    end
    addChunks(p1)
    for _,atk in ipairs(card.attacks or {}) do
      local lines={tcgSafe(atk.name).."  "..tostring(atk.damage or 0).." DMG"}
      local costs={}
      for _,e in ipairs(atk.energy_cost or {}) do costs[#costs+1]=tostring(e.count).." "..tcgSafe(e.type) end
      if #costs>0 then lines[#lines+1]="COST "..table.concat(costs,"+") end
      for _,l in ipairs(tcgWrap(atk.description or "No additional effect.",19)) do lines[#lines+1]=l end
      addChunks(lines)
    end
    if (not card.hp) or (card.description and card.description~="") then
      local lines={tcgSafe(card.card_type)}
      for _,l in ipairs(tcgWrap(card.description or "No additional text.",19)) do lines[#lines+1]=l end
      addChunks(lines)
    end
    return pages
  end

  local function openBinderCard(game,card,onBack)
    local Sound=require("src.core.Sound")
    local pages=tcgDetailPages(card); local s={isOpaque=true,page=1}
    function s:update()
      local input=game.input
      if input:wasPressed("b") then
        Sound.play(game.data,"Press_AB"); game.stack:pop(); if onBack then onBack() end
      elseif input:wasPressed("left") then
        self.page=self.page-1; if self.page<1 then self.page=#pages end; Sound.play(game.data,"Press_AB")
      elseif input:wasPressed("right") or input:wasPressed("a") then
        self.page=self.page+1; if self.page>#pages then self.page=1 end; Sound.play(game.data,"Press_AB")
      end
    end
    function s:draw()
      love.graphics.setColor(1,1,1,1); love.graphics.rectangle("fill",0,0,160,144)
      tcgMenuDrawBox(0,0,20,18)
      local pageLabel=(self.page.."/"..#pages)
      local pageW=tcgMenuWidth(pageLabel)
      tcgMenuDrawText(tcgMenuFit(card.name,132-pageW),8,8)
      tcgMenuDrawText(pageLabel,152-pageW,8)
      tcgDrawCardArt(card.label,48,24,1)
      local lines=pages[self.page] or {}
      for i=1,math.min(6,#lines) do
        tcgMenuDrawText(tcgMenuFit(lines[i],144),8,80+(i-1)*8)
      end
      tcgMenuDrawText(#pages>1 and "A NEXT   B BACK" or "B BACK",8,128)
      love.graphics.setColor(1,1,1,1)
    end
    game.stack:push(s)
  end

  local function openBinderSet(game,setName,onBack)
    local Sound=require("src.core.Sound")
    local cards={}
    for _,label in ipairs(TCG_EXPANSIONS[setName] or {}) do
      if TCG_BY_LABEL[label] then cards[#cards+1]=TCG_BY_LABEL[label] end
    end
    local s={isOpaque=true,index=1}
    local function pageStart(self) return math.floor((self.index-1)/4)*4+1 end
    local function ownedCount()
      local coll=tcgState(game).collection
      local n=0
      for _,c in ipairs(cards) do if (tonumber(coll[c.label]) or 0)>0 then n=n+1 end end
      return n
    end
    function s:update()
      local input=game.input; local n=#cards
      if input:wasPressed("b") then
        Sound.play(game.data,"Press_AB"); game.stack:pop(); if onBack then onBack() end; return
      end
      if n==0 then return end
      local before=self.index
      if input:wasPressed("left") then self.index=math.max(1,self.index-1)
      elseif input:wasPressed("right") then self.index=math.min(n,self.index+1)
      elseif input:wasPressed("up") then self.index=math.max(1,self.index-2)
      elseif input:wasPressed("down") then self.index=math.min(n,self.index+2)
      elseif input:wasPressed("a") then
        local c=cards[self.index]
        local owned=(tcgState(game).collection[c.label] or 0)>0
        Sound.play(game.data,"Press_AB")
        if owned then openBinderCard(game,c)
        else tcgSay(game,"That card has not been\ncollected yet.") end
        return
      end
      if self.index~=before then Sound.play(game.data,"Press_AB") end
    end
    function s:draw()
      love.graphics.setColor(1,1,1,1); love.graphics.rectangle("fill",0,0,160,144)
      tcgMenuDrawBox(0,0,20,18)
      local start=pageStart(self)
      local pages=math.max(1,math.ceil(#cards/4))
      local pageLabel=(math.floor((start-1)/4)+1).."/"..pages
      local ownedLabel=ownedCount().."/"..#cards
      tcgMenuDrawText(tcgMenuFit(tcgSafe(setName):upper(),88),8,8)
      tcgMenuDrawText(ownedLabel,112-tcgMenuWidth(ownedLabel),8)
      tcgMenuDrawText(pageLabel,152-tcgMenuWidth(pageLabel),8)
      local coll=tcgState(game).collection
      for slot=0,3 do
        local idx=start+slot; local c=cards[idx]
        if c then
          local col=slot%2; local row=math.floor(slot/2)
          local x=8+col*76; local y=28+row*48
          local w,h=68,44
          love.graphics.setColor(0,0,0,1); love.graphics.rectangle("line",x,y,w,h)
          local owned=tonumber(coll[c.label]) or 0
          if owned>0 then
            tcgDrawCardArt(c.label,x+14,y+2,0.625)
            local countLabel="x"..owned
            local nameX=x+3
            if idx==self.index then
              tcgMenuDrawSymbol(TCG_MENU_SYM.CURSOR_R,x+2,y+34)
              nameX=x+11
            end
            local countW=tcgMenuWidth(countLabel)
            tcgMenuDrawText(tcgMenuFit(c.name,math.max(20,x+w-5-nameX-countW)),nameX,y+34)
            tcgMenuDrawText(countLabel,x+w-3-countW,y+34)
          else
            tcgMenuDrawText("????",x+26,y+12)
            local nameX=x+3
            if idx==self.index then tcgMenuDrawSymbol(TCG_MENU_SYM.CURSOR_R,x+2,y+34); nameX=x+11 end
            tcgMenuDrawText("UNKNOWN",nameX,y+34)
          end
          if idx==self.index then
            love.graphics.setColor(0,0,0,1); love.graphics.rectangle("line",x-1,y-1,w+2,h+2)
          end
        end
      end
      tcgMenuDrawText("A CARD   B SETS",8,128)
      love.graphics.setColor(1,1,1,1)
    end
    game.stack:push(s)
  end

  local function openTCGBinder(game,onCancel)
    local t=tcgState(game)
    if not t.binderUnlocked then
      tcgSay(game,"Open a booster pack to\nunlock the BINDER.",onCancel)
      return
    end
    local rows={}
    local totalOwned,totalCards=0,0
    for _,setName in ipairs(TCG_SET_ORDER) do
      local owned,total=0,#(TCG_EXPANSIONS[setName] or {})
      for _,label in ipairs(TCG_EXPANSIONS[setName] or {}) do
        if (t.collection[label] or 0)>0 then owned=owned+1 end
      end
      totalOwned=totalOwned+owned; totalCards=totalCards+total
      rows[#rows+1]={label=tcgSafe(setName):upper(),right=owned.."/"..total,setName=setName}
    end
    tcgMenu(game,"BINDER",rows,function(row)
      openBinderSet(game,row.setName,function()
        openTCGBinder(game,onCancel)
      end)
    end,onCancel,{
      status="COLLECTED "..totalOwned.."/"..totalCards,
      footer="A OPEN  B BACK",
    })
  end

  local tcgDeckBuilder

  local function openTCGDeckPlaceholder(game,onCancel)
    local Sound=require("src.core.Sound")
    local s={isOpaque=true}
    function s:update()
      if game.input:wasPressed("a") or game.input:wasPressed("b") then
        Sound.play(game.data,"Press_AB")
        game.stack:pop()
        if onCancel then onCancel() end
      end
    end
    function s:draw()
      love.graphics.setColor(1,1,1,1)
      love.graphics.rectangle("fill",0,0,160,144)
      tcgMenuDrawBox(0,0,20,18)
      tcgMenuDrawText("DECK",8,8)
      tcgMenuDrawText("DECK MENU",56,56)
      tcgMenuDrawText("COMING SOON",52,72)
      tcgMenuDrawText("A/B BACK",8,128)
      love.graphics.setColor(1,1,1,1)
    end
    game.stack:push(s)
  end

  -- BINDER and DECK appear directly beneath the player-name row after the
  -- first successfully opened booster. DECK now opens the live builder; the
  -- placeholder remains only as an initialization fallback.
  mod.hooks:wrap("ui.start_menu.items",function(next,game,items)
    local out=next(game,items)
    if type(out)~="table" then return out end
    local t=tcgState(game)
    if not t.binderUnlocked then return out end
    local anchor
    for i,row in ipairs(out) do
      local lab=tostring(row.label or "")
      if lab=="DITTO" or lab==(game.save.player and game.save.player.name) then anchor=i; break end
    end
    anchor=anchor or math.min(1,#out)
    table.insert(out,anchor+1,{label="BINDER",onSelect=function()
      openTCGBinder(game,function() require("src.ui.Screens").push(game,"StartMenu") end)
    end})
    table.insert(out,anchor+2,{label="DECK",onSelect=function()
      local back=function() require("src.ui.Screens").push(game,"StartMenu") end
      if tcgDeckBuilder then tcgDeckBuilder(game,back) else openTCGDeckPlaceholder(game,back) end
    end})
    return out
  end)

  -- The load-time item.use wrapper delegates here after Celadon has loaded
  -- the TCG tables. This route is location-independent: a booster can be
  -- opened from the Bag on any map (and from a battle Bag if one is open).
  tcgOpenPackDirectUse=function(game,battle,id,target,list,moveIndex,picker)
    local setKey=TCG_ITEM_TO_SET[id]
    if not setKey then return false end
    local Bag=require("src.inventory.Bag")
    if not (game and game.save and game.save.inventory and (game.save.inventory[id] or 0)>0) then
      return true
    end
    local t=tcgState(game); local firstUnlock=not t.binderUnlocked
    local cards=tcgGeneratePack(setKey)
    if #cards~=10 then
      tcgSay(game,"This pack could not be opened.\nIts source card table is incomplete.")
      return true
    end
    Bag.remove(game.save,id,1)
    for _,label in ipairs(cards) do
      t.collection[label]=(tonumber(t.collection[label]) or 0)+1
    end
    t.packsOpened=t.packsOpened+1; t.binderUnlocked=true
    if list and list.close then list:close() end
    if list and list.closeStartMenu then list.closeStartMenu() end
    openPackAnimation(game,setKey,cards,firstUnlock,function() openAnotherPackPrompt(game) end)
    if battle and battle.itemUsed then battle:itemUsed({}) end
    return true
  end

  -- Use the stock Gen I storefront building blocks for booster purchases:
  -- ListMenu item box + its native cursor, QuantityBox, YES/NO ChoiceBox,
  -- and the normal bottom dialogue box. The only special rule is currency:
  -- the Game Corner counter charges COINS after the first ten free boosters.
  local function tcgPackShop(game,done,alwaysFree)
    local Bag=require("src.inventory.Bag")
    local ListMenu=require("src.ui.ListMenu")
    local QuantityBox=require("src.ui.QuantityBox")
    local ChoiceBox=require("src.ui.ChoiceBox")
    local TextBox=require("src.render.TextBox")
    local Sound=require("src.core.Sound")
    local list

    local function freeLeft()
      if alwaysFree then return 99 end
      return math.max(0,10-(tonumber(tcgState(game).freePacksUsed) or 0))
    end

    local function clerkLine()
      local free=freeLeft()
      if alwaysFree then
        return "Choose a booster.\nALL PACKS ARE FREE."
      elseif free>0 then
        return "Choose a booster.\nFREE PACKS LEFT: "..free
      end
      return "Choose a booster.\n10 COINS EACH."
    end

    local function buildRows()
      local free=freeLeft()
      local rows={}
      for _,key in ipairs({"COLOSSEUM","EVOLUTION","MYSTERY","LABORATORY"}) do
        local pack=TCG_PACKS[key]
        -- The stock Gen I mart item box only has room for short item names.
        -- Show the expansion name here; the purchased Bag item still keeps
        -- its full "... PACK" name.
        local displayName=(pack and pack.set and tostring(pack.set):upper()) or key
        rows[#rows+1]={
          value=key,
          -- Keep every renderer-facing field concrete. Some Gen1Recomp
          -- revisions do not take the item-box draw branch here and will
          -- call Font.draw on these values directly.
          label=tostring(displayName or key or "BOOSTER"),
          price=tostring((free>0) and "FREE" or "10C"),
        }
      end
      rows[#rows+1]={cancel=true,value="CANCEL",label="CANCEL"}
      return rows
    end

    local function refresh()
      if not list then return end
      list.items=buildRows()
      list.footer=clerkLine()
      list.index=math.max(1,math.min(list.index,#list.items))
    end

    local function message(text,after)
      game.stack:push(TextBox.new(game,text,function()
        refresh()
        if after then after() end
      end,{speaker="ATTENDANT"}))
    end

    -- Always provide a real title. Older ListMenu revisions can fall back
    -- to their full-screen draw path even when itemBox=true; a nil title
    -- then reaches Font.draw and crashes before the native cursor appears.
    list=ListMenu.new(game,"BUY PACKS",buildRows(),{
      kind="shop",
      itemBox=true,
      messageBox=true,
      footer=clerkLine(),
      onCancel=function()
        if done then done() end
      end,
      onChoose=function(row)
        if row.cancel then
          list:close()
          if done then done() end
          return
        end

        local setKey=row.value
        local free=freeLeft()
        local unitPrice=(free>0) and 0 or 10
        -- While free boosters remain, the quantity selector cannot exceed the
        -- remaining free allotment. Once all ten are claimed it becomes the
        -- normal 1-99 storefront quantity selector at 10 Coins each.
        local maxQty=alwaysFree and 99 or ((free>0) and free or 99)
        game.stack:push(QuantityBox.new(game,{
          max=maxQty,
          onDone=function(qty)
            if not qty then return end
            local cost=qty*unitPrice
            local pack=TCG_PACKS[setKey]
            local def=pack and game.data.items[pack.item]
            local itemName=(def and def.name) or (setKey.." PACK")
            list.footer=(unitPrice==0)
              and (itemName.." x"..qty.."?\nThese are FREE. OK?")
              or (itemName.." x"..qty.."?\n"..cost.." COINS. OK?")
            game.stack:push(ChoiceBox.new(game,function(yes)
              if not yes then refresh(); return end
              if unitPrice>0 and (game.save.coins or 0)<cost then
                message("You don't have enough\nCOINS.")
                return
              end
              if not (pack and Bag.add(game.save,pack.item,qty,game.data)) then
                message("You can't carry any\nmore booster packs.")
                return
              end
              if unitPrice==0 and not alwaysFree then
                local t=tcgState(game)
                t.freePacksUsed=(tonumber(t.freePacksUsed) or 0)+qty
              else
                game.save.coins=(game.save.coins or 0)-cost
              end
              Sound.play(game.data,"Purchase")
              message("Here you are!\nThank you!")
            end))
          end,
        }))
      end,
    })
    game.stack:push(list)
  end

  local function tcgStarterChooser(game,isFree,done,repeatable)
    local t=tcgState(game)
    local rows={}
    for _,key in ipairs(TCG_STARTER_ORDER) do
      local d=TCG_STARTER_DECKS[key]
      if isFree or not t.starterDecksOwned[key] then
        rows[#rows+1]={label=d.label,right="60",key=key}
      end
    end
    rows[#rows+1]={label="BACK",back=true}
    tcgMenu(game,isFree and "CHOOSE FREE DECK" or "STARTER DECK",rows,function(row)
      if row.back then if done then done() end; return end
      local d=TCG_STARTER_DECKS[row.key]
      local ok,activated=tcgGrantStarterDeck(game,row.key,isFree,repeatable)
      if not ok then
        tcgSay(game,"You already own that\nstarter deck.",done); return
      end
      local msg=d.name.." is yours!"
      if activated then msg=msg.."\nIt is now your active deck."
      else msg=msg.."\nLoad it in DECK BUILDER."
      end
      tcgSay(game,msg,done)
    end,done,{
      status=isFree and "CHOOSE 1 FREE DECK" or nil,
      footer="A CHOOSE  B BACK",
    })
  end

  local function tcgStarterDeckShop(game,done)
    local t=tcgState(game)
    local remaining=0
    for _,key in ipairs(TCG_STARTER_ORDER) do if not t.starterDecksOwned[key] then remaining=remaining+1 end end
    if remaining==0 then tcgSay(game,"You own all three\nstarter decks.",done); return end
    local ListMenu=require("src.ui.ListMenu")
    local ChoiceBox=require("src.ui.ChoiceBox")
    local TextBox=require("src.render.TextBox")
    local Sound=require("src.core.Sound")
    local list
    local function rows()
      local out={}
      for _,key in ipairs(TCG_STARTER_ORDER) do
        local d=TCG_STARTER_DECKS[key]
        if not tcgState(game).starterDecksOwned[key] then
          out[#out+1]={value=key,label=d.label,price=tostring(TCG_STARTER_PRICE).."C"}
        end
      end
      out[#out+1]={cancel=true,value="CANCEL",label="CANCEL"}
      return out
    end
    local function refresh()
      if list then
        list.items=rows(); list.index=math.max(1,math.min(list.index,#list.items))
        list.footer="Starter decks are\n"..TCG_STARTER_PRICE.." COINS each."
      end
    end
    local function message(text)
      game.stack:push(TextBox.new(game,text,refresh,{speaker="ATTENDANT"}))
    end
    list=ListMenu.new(game,"STARTER DECKS",rows(),{
      kind="shop",itemBox=true,messageBox=true,
      footer="Starter decks are\n"..TCG_STARTER_PRICE.." COINS each.",
      onCancel=function() if done then done() end end,
      onChoose=function(row)
        if row.cancel then list:close(); if done then done() end; return end
        local key=row.value; local d=TCG_STARTER_DECKS[key]
        list.footer=d.label.." DECK?\n"..TCG_STARTER_PRICE.." COINS. OK?"
        game.stack:push(ChoiceBox.new(game,function(yes)
          if not yes then refresh(); return end
          if (game.save.coins or 0)<TCG_STARTER_PRICE then message("You don't have enough\nCOINS."); return end
          local ok,activated=tcgGrantStarterDeck(game,key,false)
          if not ok then message("You already own that\nstarter deck."); return end
          game.save.coins=(game.save.coins or 0)-TCG_STARTER_PRICE
          Sound.play(game.data,"Purchase")
          message(d.name.." added!\n"..(activated and "It is now active." or "Load it in DECK BUILDER."))
        end))
      end,
    })
    game.stack:push(list)
  end

  -- Keep the previously integrated deck builder / AI duel available at the
  -- counter, now backed by the complete TCG database and collection.
  local function tcgDeckCount(deck)
    local n=0; for _,count in pairs(deck.cards or {}) do n=n+(tonumber(count) or 0) end; return n
  end
  local TCG_BASIC_ENERGY_LABELS={
    GrassEnergyCard=true,FireEnergyCard=true,WaterEnergyCard=true,
    LightningEnergyCard=true,FightingEnergyCard=true,PsychicEnergyCard=true,
  }
  local function tcgDeckNameCopies(deck,card)
    if not card or not card.name then return 0 end
    local n=0
    for label,count in pairs(deck.cards or {}) do
      local other=TCG_BY_LABEL[label]
      if other and other.name==card.name then n=n+(tonumber(count) or 0) end
    end
    return n
  end
  tcgDeckBuilder=function(game,done)
    local t=tcgState(game); local deck=t.deck
    done=done or function() end
    local hub

    local function viewDeck()
      local rows={}
      for label,count in pairs(deck.cards or {}) do
        count=tonumber(count) or 0
        if count>0 then
          local c=TCG_BY_LABEL[label]
          rows[#rows+1]={label=(c and c.name or label),right="x"..count,key=label}
        end
      end
      table.sort(rows,function(a,b)
        if a.label==b.label then return a.key<b.key end
        return a.label<b.label
      end)
      if #rows==0 then tcgSay(game,"Deck is empty.",hub); return end
      tcgMenu(game,"VIEW DECK",rows,function(row)
        local c=TCG_BY_LABEL[row.key]
        if c then openBinderCard(game,c,viewDeck) else viewDeck() end
      end,hub,{
        status=tcgSafe(deck.name or "DECK").."  "..tcgDeckCount(deck).."/60",
        footer="A CARD  B BACK",
      })
    end

    hub=function()
      local count=tcgDeckCount(deck)
      local rows={
        {label="ADD CARD",right=count.."/60"},
        {label="REMOVE CARD"},
        {label="VIEW DECK",right=count..""},
        {label="LOAD STARTER"},
        {label="BACK"},
      }
      tcgMenu(game,"DECK BUILDER",rows,function(_,idx)
        if idx==5 then
          if count~=60 then
            tcgSay(game,"This isn't a 60-card Deck!\nThe Deck must include 60 cards.",hub)
          else
            done()
          end
          return
        end
        if idx==4 then
          local owned={}
          for _,key in ipairs(TCG_STARTER_ORDER) do
            if t.starterDecksOwned[key] then
              owned[#owned+1]={label=TCG_STARTER_DECKS[key].label,right="60",key=key}
            end
          end
          owned[#owned+1]={label="BACK",back=true}
          if #owned==1 then tcgSay(game,"You don't own a\nstarter deck yet.",hub); return end
          tcgMenu(game,"LOAD STARTER",owned,function(ch)
            if ch.back then hub(); return end
            local d=TCG_STARTER_DECKS[ch.key]
            deck.name=d.name; deck.cards=tcgCopyCardCounts(d.cards)
            tcgSay(game,d.name.." loaded.",hub)
          end,hub,{status="REPLACES ACTIVE",footer="A LOAD  B BACK"})
          return
        end
        if idx==3 then viewDeck(); return end

        local adding=idx==1; local choices={}
        for label,ownedCount in pairs(t.collection) do
          ownedCount=tonumber(ownedCount) or 0
          local inDeck=tonumber(deck.cards[label]) or 0
          if (adding and ownedCount>inDeck) or ((not adding) and inDeck>0) then
            local c=TCG_BY_LABEL[label]
            choices[#choices+1]={
              label=(c and c.name or label),
              right=inDeck.."/"..ownedCount,
              key=label,
            }
          end
        end
        table.sort(choices,function(a,b)
          if a.label==b.label then return a.key<b.key end
          return a.label<b.label
        end)
        choices[#choices+1]={label="BACK",back=true}
        tcgMenu(game,adding and "ADD CARD" or "REMOVE CARD",choices,function(ch)
          if ch.back then hub(); return end
          local c=TCG_BY_LABEL[ch.key]; local cur=tonumber(deck.cards[ch.key]) or 0
          if adding then
            local basicEnergy=TCG_BASIC_ENERGY_LABELS[ch.key]==true
            local sameName=tcgDeckNameCopies(deck,c)
            if tcgDeckCount(deck)>=60 then tcgSay(game,"The deck is full.",hub)
            elseif not basicEnergy and sameName>=4 then
              tcgSay(game,"Only 4 cards with the\nsame name are allowed.",hub)
            else deck.cards[ch.key]=cur+1; hub() end
          else
            deck.cards[ch.key]=math.max(0,cur-1); hub()
          end
        end,hub,{
          status=(adding and "OWNED / DECK" or "DECK / OWNED").."   "..tcgDeckCount(deck).."/60",
          footer="A CHANGE  B BACK",
        })
      end,done,{
        status=tcgSafe(deck.name or "DECK").."  "..count.."/60",
        footer="A SELECT  B BACK",
      })
    end
    hub()
  end

  local TCG_BATTLE_MODULE=nil
  local function loadTCGBattleModule()
    if TCG_BATTLE_MODULE then return TCG_BATTLE_MODULE end
    local path=tostring(mod.path or "").."/tcg_battle.lua"
    local chunk,err=loadfile(path)
    if not chunk and love.filesystem and love.filesystem.load then chunk,err=love.filesystem.load(path) end
    if not chunk then return nil,err end
    local ok,value=pcall(chunk)
    if not ok then return nil,value end
    TCG_BATTLE_MODULE=value
    return value
  end

  local function tcgDuel(game,done)
    local t=tcgState(game)
    local battle,err=loadTCGBattleModule()
    if not battle or type(battle.start)~="function" then
      tcgSay(game,"TCG DUEL ENGINE ERROR\n"..tostring(err or "could not load"),done)
      return
    end
    battle.start(game,{
      modPath=tostring(mod.path or ""),
      cards=TCG_BY_LABEL,
      deckCounts=t.deck.cards,
      starterDecks=TCG_STARTER_DECKS,
      safe=tcgSafe,fit=tcgFit,menu=tcgMenu,say=tcgSay,
      cardImage=tcgCardImage,image=tcgImage,openCard=openBinderCard,done=done,
    })
  end

  local function celadonGameCornerTCGTalk(game,ow,npc,done)
    done=done or function() end
    local function hub()
      local t=tcgState(game)
      local starterLabel=t.starterDeckClaimed and "STARTER DECKS" or "STARTER DECK"
      local free=math.max(0,10-(tonumber(t.freePacksUsed) or 0))
      local deckCount=tcgDeckCount(t.deck)
      local rows={
        {label="BUY PACKS",right=free>0 and ("FREE "..free) or "10C"},
        {label=starterLabel,right=t.starterDeckClaimed and "SHOP" or "FREE"},
        {label="BINDER",right=t.binderUnlocked and "OPEN" or "LOCKED"},
        {label="DECK BUILDER",right=deckCount.."/60"},
        {label="DUEL ATTENDANT"},
        {label="LEAVE"},
      }
      tcgMenu(game,"POKeMON TCG",rows,function(_,idx)
        if idx==1 then tcgPackShop(game,hub)
        elseif idx==2 then
          if tcgState(game).starterDeckClaimed then tcgStarterDeckShop(game,hub)
          else tcgStarterChooser(game,true,hub) end
        elseif idx==3 then openTCGBinder(game,hub)
        elseif idx==4 then tcgDeckBuilder(game,hub)
        elseif idx==5 then tcgDuel(game,hub)
        else done() end
      end,done,{
        status="COINS "..tostring(game.save.coins or 0).."  OPEN "..tostring(t.packsOpened or 0),
        footer="A SELECT  B LEAVE",
      })
    end
    local function afterWelcome()
      if not tcgState(game).starterDeckClaimed then
        tcgSay(game,"Your first starter deck\nis FREE. Choose one!",function()
          tcgStarterChooser(game,true,hub)
        end)
      else
        hub()
      end
    end
    tcgSay(game,"Welcome to the\nPOKeMON CARD counter!",afterWelcome)
  end
    return {
      state=tcgState, packShop=tcgPackShop, starterChooser=tcgStarterChooser,
      deckBuilder=tcgDeckBuilder, deckCount=tcgDeckCount, duel=tcgDuel,
      menu=tcgMenu, counterTalk=celadonGameCornerTCGTalk,
    }
  end
  local TCGServices=createTCGServices()

  local function startCeladonEnding(game, skipToCleanup)
    local Overworld=require("src.world.OverworldController")
    local NPC=require("src.world.NPC")
    local TextBox=require("src.render.TextBox")

    -- The chronology handoff clears the old Mansion stack before showing its
    -- intertitle. Do not empty the stack again from inside a state:update()
    -- callback; that could remove the freshly-created Celadon overworld.
    game.stack:push(Overworld,"CELADON_CITY",6,10,"down")
    local ow=game.stack:top()

    -- ROOT FIX: Gen1Recomp's LAST_MAP exits resolve through
    -- OverworldController.lastOutdoor / save.lastOutdoor. Native
    -- startWarpTo() normally refreshes this when entering a building from an
    -- outdoor map, but this cutscene changes maps with direct setMap(...,
    -- {via="boot"}) calls, bypassing startWarpTo(). Seed the real wLastMap
    -- equivalent once Scene 2 begins so every LAST_MAP door in the Game
    -- Corner, Department Store, and other Celadon interiors resolves back to
    -- CELADON_CITY rather than the Mansion value inherited from Scene 1.
    if ow.rememberOutdoor then
      ow:rememberOutdoor("CELADON_CITY",24,28)
    else
      ow.lastOutdoor={id="CELADON_CITY",x=24,y=28}
      game.save.lastOutdoor=ow.lastOutdoor
    end

    local function removePlayer()
      ow.playerHidden=true
      ow.player.inputLocked=true
      for i=#(ow.entities or {}),1,-1 do
        if ow.entities[i]==ow.player then table.remove(ow.entities,i) end
      end
    end
    removePlayer()

    local cut={
      isOpaque=false,timer=0,phase=1,
      views={{10,10},{18,12},{28,16}},
      ow=ow,storyStarted=false,storyStep=0,storyTimer=0,
      deferred={},cameraPan=nil,
    }

    -- Small non-blocking cinematic beat used after a walk finishes.  Native
    -- Gen I movement lands hard on a tile boundary; giving the pose a handful
    -- of frames to settle before the next textbox/fade keeps chained actions
    -- from looking like they fire on the exact same frame.
    local function defer(frames,fn)
      cut.deferred[#cut.deferred+1]={frames=math.max(1,frames or 1),fn=fn}
    end

    local function addActor(name,sprite,x,y,facing)
      local n=NPC.new(game.data,ow.map.id,{
        index=120+#(ow.npcs or {}),name=name,sprite=sprite,
        movement="STAY",range="NONE",x=x,y=y,runtime=true,
      })
      n.facing=facing or "down"
      n.wanders=false
      n.passable=false
      -- Match vanilla NPC movement timing.  The earlier 16-frame override
      -- made every cutscene actor move at double the engine's normal speed,
      -- which made walk cycles and camera tracking look jerky.
      n.stepFrames=32
      table.insert(ow.npcs,n)
      table.insert(ow.entities,n)
      return n
    end

    local function box(text,done,opts)
      game.stack:push(TextBox.new(game,text,done,opts))
    end



    local function removeRuntimeActor(actor)
      if not actor then return end
      for i=#(ow.npcs or {}),1,-1 do
        if ow.npcs[i]==actor then table.remove(ow.npcs,i) end
      end
      for i=#(ow.entities or {}),1,-1 do
        if ow.entities[i]==actor then table.remove(ow.entities,i) end
      end
    end

    local function ensureGameCornerCast()
      if not (ow and ow.map and ow.map.id=="GAME_CORNER") then return {} end

      local Collision=require("src.world.Collision")
      local cast={}

      local function findLive(name)
        for _,npc in ipairs(ow.npcs or {}) do
          if npc and npc.def and npc.def.name==name then return npc end
        end
        return nil
      end

      local function openCell(x,y)
        return ow.map:inBounds(x,y)
          and ow.map:isWalkableCell(x,y)
          and not ow.map:warpAtCell(x,y)
          and not Collision.occupied(ow.entities,x,y,nil)
      end

      local function openNear(sx,sy)
        if openCell(sx,sy) then return sx,sy end
        for r=1,12 do
          for dy=-r,r do
            for dx=-r,r do
              if math.abs(dx)==r or math.abs(dy)==r then
                local x,y=sx+dx,sy+dy
                if openCell(x,y) then return x,y end
              end
            end
          end
        end
        return nil,nil
      end

      local function spawn(name,sprite,x,y,facing,exact)
        local live=findLive(name)
        if live then cast[name]=live; return live end
        local sx,sy
        if exact and ow.map:inBounds(x,y)
            and not Collision.occupied(ow.entities,x,y,nil) then
          -- Counter staff can occupy their authored service-side cell even
          -- when that cell is not part of the customer's walkable floor.
          sx,sy=x,y
        else
          sx,sy=openNear(x,y)
        end
        if not sx then return nil end
        local a=addActor(name,sprite,sx,sy,facing or "down")
        cast[name]=a
        return a
      end

      -- These are the ordinary new Game Corner patrons. They are present during
      -- the refund scene as witnesses and remain afterward for free roam.
      spawn("GC_NEAR_WIN","SPRITE_GAMBLER",3,11,"down")
      spawn("GC_BROKE","SPRITE_GAMBLER",5,12,"right")
      spawn("GC_ONE_MORE","SPRITE_BEAUTY",7,11,"down")
      spawn("GC_BAD_LUCK","SPRITE_GAMBLER",9,12,"right")
      spawn("GC_STREAK","SPRITE_GENTLEMAN",11,11,"down")
      spawn("GC_ALMOST_JACKPOT","SPRITE_GAMBLER",13,12,"left")
      spawn("GC_RENT_MONEY","SPRITE_BEAUTY",15,11,"down")
      spawn("GC_LUCKY_MACHINE","SPRITE_GAMBLER",17,12,"left")

      -- The Giovanni/Silph theory NPC requested previously.
      spawn("GC_GIOVANNI_THEORY","SPRITE_GENTLEMAN",13,9,"left")

      -- Put the TCG attendant in the original Gen I service-clerk position,
      -- behind the northwest Game Corner counter.
      spawn("GC_ATTENDANT","SPRITE_BEAUTY",5,6,"down",true)

      local q=pokopiaData(game)
      if q.emptyCoinCaseDropped and not q.emptyCoinCaseFound then
        spawn("GC_EMPTY_COIN_CASE","SPRITE_POKE_BALL",
          q.emptyCoinCaseX or 9,q.emptyCoinCaseY or 14,"down")
      end

      return cast
    end


    ------------------------------------------------------------------------
    -- Celadon Cafe delivery jobs. This is deliberately independent from the
    -- Game Corner attendant/TCG counter.
    ------------------------------------------------------------------------
    local cafeItems={
      berries={"Cheri","Chesto","Pecha","Rawst","Aspear","Leppa","Oran","Persim","Lum","Sitrus"},
      forms={"syrup","glaze","cream","icing","sauce","jam","compote","sugar","curd","spread"},
      ways={"dipped","topped","filled","drizzled","covered","stuffed","layered","coated","frosted","glazed"},
      items={"donuts","pancakes","croissants","waffles","muffins","crepes","danishes","scones","cupcakes","pastries"},
    }
    local function cafeChoose(t) return t[math.random(1,#t)] end
    local function generateCafeOrder()
      local berry=cafeChoose(cafeItems.berries)
      local form=cafeChoose(cafeItems.forms)
      local way=cafeChoose(cafeItems.ways)
      local item=cafeChoose(cafeItems.items)
      return {berry=berry,form=form,way=way,item=item,
        name=berry.." "..form.."-"..way.." "..item}
    end

    -- Coordinates are Gen I Celadon outdoor cells, anchored around the actual
    -- door/sign positions in the authored map. A runtime collision/warp check
    -- is still applied before a temporary customer is spawned.
    local cafeDeliveryLocations={
      {name="outside the GAME CORNER",short="GAME CORNER",x=27,y=20},
      {name="near the CAFE",short="CAFE",x=30,y=28},
      {name="near the DEPT. STORE",short="DEPT. STORE",x=12,y=16},
      {name="outside the POKeMON CENTER",short="POKeMON CENTER",x=40,y=10},
      {name="near CELADON MANSION",short="MANSION",x=23,y=10},
      {name="near the PRIZE building",short="PRIZE BLDG",x=34,y=20},
      {name="by the west road",short="WEST ROAD",x=5,y=18},
      {name="near the south path",short="SOUTH PATH",x=22,y=29},
    }

    local function cafeLocationPool()
      local pool={}
      for _,loc in ipairs(cafeDeliveryLocations) do
        -- Pokopia's current Celadon story barrier occupies the north-east
        -- approach. Never brief a job to that forbidden quadrant.
        if not ((loc.x or 0)>21 and (loc.y or 0)<14) then pool[#pool+1]=loc end
      end
      return pool
    end

    local function cafeWrapPixels(text,pixels,maxLines)
      local lines,current={},""
      for word in tostring(text or ""):gmatch("%S+") do
        local candidate=(current=="") and word or (current.." "..word)
        if current~="" and tcgMenuWidth(candidate)>pixels then
          lines[#lines+1]=current; current=word
          if maxLines and #lines>=maxLines then break end
        else current=candidate end
      end
      if current~="" and (not maxLines or #lines<maxLines) then lines[#lines+1]=current end
      return lines
    end

    local cafeCustomerDefs={
      {name="LASS",sprite="SPRITE_GIRL"},
      {name="BEAUTY",sprite="SPRITE_BEAUTY"},
      {name="YOUNGSTER",sprite="SPRITE_YOUNGSTER"},
      {name="GAMBLER",sprite="SPRITE_GAMBLER"},
      {name="JR. TRAINER",sprite="SPRITE_JR_TRAINER_F"},
      {name="BUG CATCHER",sprite="SPRITE_BUG_CATCHER"},
      {name="HIKER",sprite="SPRITE_HIKER"},
      {name="GENTLEMAN",sprite="SPRITE_GENTLEMAN"},
    }

    local cafeSessionSanitized=false
    local cafeBerryCache={}
    local cafeRuntimeCustomer=nil

    local function cafeJobsState()
      local q=pokopiaData(game)
      local jobs=q.cafeJobs
      if not cafeSessionSanitized then
        cafeSessionSanitized=true
        -- Active map-spawn state is intentionally not reconstructed on load.
        -- Cancelling is safer than duplicating either payout or penalty.
        if jobs.currentOrder then
          jobs.currentOrder=nil
        end
      end
      return jobs
    end

    local function cafeAvailableCustomers()
      local out={}
      for _,c in ipairs(cafeCustomerDefs) do
        if game.data and game.data.sprites and game.data.sprites[c.sprite] then
          out[#out+1]=c
        end
      end
      if #out==0 then out={{name="LASS",sprite="SPRITE_GIRL"}} end
      return out
    end

    local function cafeFindNpc(name)
      for _,npc in ipairs(ow.npcs or {}) do
        if npc and npc.def and npc.def.name==name then return npc end
      end
      return nil
    end

    local function ensureCafeGirl()
      if not (ow and ow.map and ow.map.id=="CELADON_DINER") then return nil end
      local live=cafeFindNpc("CAFE_OWNERS_DAUGHTER")
      if live then return live end
      -- The diner cook already occupies 8,5. 7,5 is the matching authored
      -- service-side cell on the lower counter, so do not use openNear().
      local a=addActor("CAFE_OWNERS_DAUGHTER","SPRITE_GIRL",7,5,"down")
      if a then
        a.wanders=false
        a.frozen=true
      end
      return a
    end

    local function cafeCellOpen(x,y,ignore)
      if not (ow and ow.map and ow.map.id=="CELADON_CITY") then return false end
      local Collision=require("src.world.Collision")
      return ow.map:inBounds(x,y)
        and ow.map:isWalkableCell(x,y)
        and not ow.map:warpAtCell(x,y)
        and not Collision.occupied(ow.entities,x,y,ignore)
    end

    local function cafeSpawnCell(loc)
      if cafeCellOpen(loc.x,loc.y,nil) then return loc.x,loc.y end
      for r=1,2 do
        for dy=-r,r do
          for dx=-r,r do
            if math.abs(dx)==r or math.abs(dy)==r then
              local x,y=loc.x+dx,loc.y+dy
              if cafeCellOpen(x,y,nil) then return x,y end
            end
          end
        end
      end
      return nil,nil
    end

    local function removeCafeCustomer()
      if cafeRuntimeCustomer then
        removeRuntimeActor(cafeRuntimeCustomer)
        cafeRuntimeCustomer=nil
      end
      for i=#(ow.npcs or {}),1,-1 do
        local n=ow.npcs[i]
        local name=n and n.def and n.def.name or ""
        if name:match("^CAFE_DELIVERY_") then removeRuntimeActor(n) end
      end
    end

    local function ensureCafeCustomer()
      local jobs=cafeJobsState()
      local order=jobs.currentOrder
      if not order or order.state~="active" or not (ow.map and ow.map.id=="CELADON_CITY") then
        return nil
      end
      local runtimeName="CAFE_DELIVERY_"..tostring(order.id)
      local existing=cafeFindNpc(runtimeName)
      if existing then cafeRuntimeCustomer=existing; return existing end
      local x,y=cafeSpawnCell(order.location)
      if not x then return nil end
      order.location.x,order.location.y=x,y
      local n=addActor(runtimeName,order.customer.sprite,x,y,"down")
      if n then
        n.wanders=false
        n.frozen=true
        n.pokopiaCafeDeliveryId=order.id
        cafeRuntimeCustomer=n
      end
      return n
    end

    local function cafeBerryImage(berry)
      local key=string.lower(tostring(berry or ""))
      if cafeBerryCache[key]~=nil then return cafeBerryCache[key] or nil end
      local path=tostring(mod.path or "").."/assets/cafe/berries/"..key..".png"
      local ok,id=pcall(love.image.newImageData,path)
      if not ok or not id then cafeBerryCache[key]=false; return nil end
      local w,h=id:getDimensions()
      for y=0,h-1 do
        for x=0,w-1 do
          local r,g,b,a=id:getPixel(x,y)
          if a>0 then
            local lum=r*0.299+g*0.587+b*0.114
            local shade
            if lum>=0.75 then shade=1
            elseif lum>=0.50 then shade=2/3
            elseif lum>=0.25 then shade=1/3
            else shade=0 end
            id:setPixel(x,y,shade,shade,shade,a)
          end
        end
      end
      local okImg,img=pcall(love.graphics.newImage,id)
      if okImg and img and img.setFilter then img:setFilter("nearest","nearest") end
      cafeBerryCache[key]=okImg and img or false
      return okImg and img or nil
    end

    -- Cafe jobs are ordinary Pokopia overworld content, so they must use the
    -- game's native Gen I menu/font renderer. The TCG half-width frame/font is
    -- intentionally scoped to card-game screens only.
    local function cafeNativeFit(text,maxPixels)
      local Font=require("src.render.Font")
      text=tostring(text or "")
      if Font.width(text)<=maxPixels then return text end
      local spans=Font.split(text)
      local out=""
      for i=1,#spans do
        local ch=text:sub(spans[i].from,spans[i].to)
        if Font.width(out..ch..".")>maxPixels then break end
        out=out..ch
      end
      return out.."."
    end

    local function cafeNativeWrap(text,maxPixels,maxLines)
      local Font=require("src.render.Font")
      local lines,current={},""
      for word in tostring(text or ""):gmatch("%S+") do
        local candidate=current=="" and word or (current.." "..word)
        if current~="" and Font.width(candidate)>maxPixels then
          lines[#lines+1]=current
          current=word
          if maxLines and #lines>=maxLines then break end
        else
          current=candidate
        end
      end
      if current~="" and (not maxLines or #lines<maxLines) then lines[#lines+1]=current end
      return lines
    end

    local function cafeNativeMenu(title,labels,onPick,onCancel)
      local Font=require("src.render.Font")
      local Sound=require("src.core.Sound")
      local menu={isOpaque=false,index=1,labels=labels or {}}
      function menu:update()
        local input=game.input
        if input:wasPressed("up") then
          self.index=self.index-1
          if self.index<1 then self.index=#self.labels end
          Sound.play(game.data,"Press_AB")
        elseif input:wasPressed("down") then
          self.index=self.index+1
          if self.index>#self.labels then self.index=1 end
          Sound.play(game.data,"Press_AB")
        elseif input:wasPressed("b") then
          Sound.play(game.data,"Press_AB")
          if game.stack:top()==self then game.stack:pop() end
          if onCancel then onCancel() end
        elseif input:wasPressed("a") then
          Sound.play(game.data,"Press_AB")
          local idx=self.index
          if game.stack:top()==self then game.stack:pop() end
          if onPick then onPick(idx) end
        end
      end
      function menu:draw()
        local rows=#self.labels
        local h=math.max(5,3+rows*2)
        local y=18-h
        Font.drawBox(1,y,18,h)
        love.graphics.setColor(0,0,0,1)
        Font.draw(cafeNativeFit(title or "",128),16,(y+1)*8)
        for i,label in ipairs(self.labels) do
          local py=(y+1+i*2)*8
          Font.draw(i==self.index and ">" or " ",16,py)
          Font.draw(cafeNativeFit(label,112),32,py)
        end
        love.graphics.setColor(1,1,1,1)
      end
      game.stack:push(menu)
      return menu
    end

    local function cafeDrawBriefing(order)
      local Font=require("src.render.Font")
      love.graphics.push("all")
      love.graphics.setColor(1,1,1,1)
      Font.drawBox(0,0,20,18)
      love.graphics.setColor(0,0,0,1)
      Font.draw("DELIVERY",8,8)
      local img=cafeBerryImage(order.food.berry)
      if img then love.graphics.setColor(1,1,1,1); love.graphics.draw(img,8,24); love.graphics.setColor(0,0,0,1) end
      -- The delivery target is the finished cafe item, not the ingredient.
      -- Keep the berry art as recipe flavor, but label the order by item.
      Font.draw(cafeNativeFit(order.food.item:upper(),104),48,24)
      local foodLines=cafeNativeWrap(order.food.name:upper(),144,2)
      if foodLines[1] then Font.draw(foodLines[1],8,56) end
      if foodLines[2] then Font.draw(foodLines[2],8,64) end
      Font.draw("CUSTOMER:",8,80)
      Font.draw(cafeNativeFit(order.customer.name,64),88,80)
      Font.draw("LOCATION:",8,88)
      local locLines=cafeNativeWrap(order.location.name:upper(),144,2)
      if locLines[1] then Font.draw(locLines[1],8,96) end
      if locLines[2] then Font.draw(locLines[2],8,104) end
      Font.draw("TIME 1:00",8,120)
      Font.draw("A START",88,120)
      love.graphics.setColor(1,1,1,1)
      love.graphics.pop()
    end

    local function cafeFoodHud(order)
      -- Lead with the thing being delivered; the berry remains a recipe detail.
      local s=(order.food.item.." - "..order.food.berry.." "..order.food.form):upper()
      return cafeNativeFit(s,144)
    end

    local function cafeClock(seconds)
      local n=math.max(0,math.ceil(tonumber(seconds) or 0))
      return string.format("%d:%02d",math.floor(n/60),n%60)
    end

    local function cafeAnotherMenu(success)
      local prompt=success and "Want another delivery?" or "Want to try another?"
      cafeNativeMenu(prompt,{"YES","NO"},function(i)
        if i==1 then
          local girl=ensureCafeGirl()
          if girl then
            local jobs=cafeJobsState()
            jobs.currentOrder=nil
            -- Continue directly into a new order without requiring another A press.
            local customers=cafeAvailableCustomers()
            local customer=cafeChoose(customers)
            local loc=copy(cafeChoose(cafeLocationPool()))
            local id=jobs.nextDeliveryId; jobs.nextDeliveryId=id+1
            jobs.currentOrder={id=id,food=generateCafeOrder(),customer=copy(customer),location=loc,
              timeLimit=60,timeRemaining=60,state="briefing",paid=false,penaltyApplied=false}
            local order=jobs.currentOrder
            local briefing={isOpaque=true}
            function briefing:update()
              if game.input and game.input.wasPressed and game.input:wasPressed("a") then
                order.state="active"; order.timeRemaining=60
                game.stack:pop(); restorePlayerInput(game,ow)
              elseif game.input and game.input.wasPressed and game.input:wasPressed("b") then
                jobs.currentOrder=nil; game.stack:pop(); restorePlayerInput(game,ow)
              end
            end
            function briefing:draw()
              cafeDrawBriefing(order)
            end
            game.stack:push(briefing)
          end
        else
          restorePlayerInput(game,ow)
        end
      end,function() restorePlayerInput(game,ow) end)
    end

    local function cafeResultDialogue(success)
      local jobs=cafeJobsState()
      local order=jobs.currentOrder
      if not order then restorePlayerInput(game,ow); return end
      if success then
        box("Great job!\fHere's your ¥50.",function()
          if not order.paid then
            order.paid=true
            game.save.money=(tonumber(game.save.money) or 0)+50
            jobs.deliveriesCompleted=jobs.deliveriesCompleted+1
            jobs.totalEarned=jobs.totalEarned+50
            require("src.core.Sound").play(game.data,"Get_Item1")
          end
          jobs.currentOrder=nil
          cafeAnotherMenu(true)
        end,{speaker="LASS",portrait={speaker="GIRL",expression="Normal"}})
      else
        box("Oh no...\fThe order didn't\nmake it in time.\fWe lost ¥25 on it,\nso I had to take\nthat out of your pay.",function()
          jobs.currentOrder=nil
          cafeAnotherMenu(false)
        end,{speaker="LASS",portrait={speaker="GIRL",expression="Normal"}})
      end
    end

    local function cafeReturnToCounter(success)
      -- Native Gen I script fade: the customer remains visible through the
      -- fade-out and is removed only once the screen has reached full black.
      local Transition=require("src.render.Transition")
      game.stack:push(Transition.new(game,function()
        removeCafeCustomer()
        ow:setMap("CELADON_DINER",7,7,"up",{via="boot"})
        ensureCafeGirl()
        local p=ow.player
        if p then
          p.cellX,p.cellY=7,7
          p.px,p.py=7*16,7*16
          p.facing="up"
          p.inputLocked=true
        end
      end,function()
        cafeResultDialogue(success)
      end,false))
    end

    local function cafeFailActiveOrder()
      local jobs=cafeJobsState(); local order=jobs.currentOrder
      if not order or order.state~="active" then return false end
      order.state="failed" -- state first: active -> failed only
      order.timeRemaining=0
      if not order.penaltyApplied then
        order.penaltyApplied=true
        game.save.money=math.max(0,(tonumber(game.save.money) or 0)-25)
        jobs.deliveriesFailed=jobs.deliveriesFailed+1
        jobs.totalPenalties=jobs.totalPenalties+25
      end
      if ow.player then ow.player.inputLocked=true end
      cafeReturnToCounter(false)
      return true
    end

    local function cafeStartOrder()
      local jobs=cafeJobsState()
      local customers=cafeAvailableCustomers()
      local id=jobs.nextDeliveryId; jobs.nextDeliveryId=id+1
      jobs.currentOrder={id=id,food=generateCafeOrder(),customer=copy(cafeChoose(customers)),
        location=copy(cafeChoose(cafeLocationPool())),timeLimit=60,timeRemaining=60,
        state="briefing",paid=false,penaltyApplied=false}
      local order=jobs.currentOrder
      local briefing={isOpaque=true}
      function briefing:update()
        if game.input and game.input.wasPressed and game.input:wasPressed("a") then
          order.state="active"; order.timeRemaining=60
          game.stack:pop(); restorePlayerInput(game,ow)
        elseif game.input and game.input.wasPressed and game.input:wasPressed("b") then
          jobs.currentOrder=nil; game.stack:pop(); restorePlayerInput(game,ow)
        end
      end
      function briefing:draw()
        cafeDrawBriefing(order)
      end
      game.stack:push(briefing)
    end

    local function cafeGirlMenu()
      cafeNativeMenu("CAFE JOBS",{
        "TAKE DELIVERY","HOW IT WORKS","NEVER MIND"
      },function(i)
        if i==1 then cafeStartOrder()
        elseif i==2 then
          box("I'll give you an order,\nthe customer's name,\nand where to find them.\fGet there before the\ntimer runs out!\fA delivery pays ¥50.\fIf you miss one,\nit costs us ¥25...\nso that comes out\nof your pay.",cafeGirlMenu,{speaker="LASS",portrait={speaker="GIRL",expression="Normal"}})
        else restorePlayerInput(game,ow) end
      end,function() restorePlayerInput(game,ow) end)
    end

    local function talkCafeGirl(girl)
      local jobs=cafeJobsState()
      if ow.player then ow.player.inputLocked=true end
      if not jobs.introduced then
        jobs.introduced=true
        box("Hi! My dad owns\nthis cafe.\fWe get delivery orders\nall over CELADON.\fWant to make some\nextra money?",cafeGirlMenu,
          {speaker="LASS",portrait={speaker="GIRL",expression="Normal"}})
      else cafeGirlMenu() end
    end

    local function updateCafeDelivery(dt)
      local jobs=cafeJobsState(); local order=jobs.currentOrder
      if not order or order.state~="active" then return false end
      if ow.map and ow.map.id=="CELADON_CITY" then ensureCafeCustomer() end
      order.timeRemaining=math.max(0,(tonumber(order.timeRemaining) or 60)-(tonumber(dt) or 1/60))
      if order.timeRemaining<=0 then return cafeFailActiveOrder() end
      return false
    end

    local function handleCafeInteraction()
      local p=ow.player; local input=game.input
      if not (p and input and input.wasPressed and input:wasPressed("a")
          and not p.moving and not p.inputLocked) then return false end
      if ow.map.id=="CELADON_DINER" then
        local girl=ensureCafeGirl()
        if girl and p.facing=="up" and girl.cellX==p.cellX
            and (girl.cellY==p.cellY-1 or girl.cellY==p.cellY-2) then
          girl.facing="down"; talkCafeGirl(girl); return true
        end
      elseif ow.map.id=="CELADON_CITY" then
        local jobs=cafeJobsState(); local order=jobs.currentOrder
        if order and order.state=="active" then
          local customer=ensureCafeCustomer()
          if customer then
            local dx,dy=0,0
            if p.facing=="up" then dy=-1 elseif p.facing=="down" then dy=1
            elseif p.facing=="left" then dx=-1 elseif p.facing=="right" then dx=1 end
            if customer.cellX==p.cellX+dx and customer.cellY==p.cellY+dy
                and customer.pokopiaCafeDeliveryId==order.id then
              -- Set completion state before dialogue/fade so repeated A presses
              -- and timer expiry can never transition this order again.
              order.state="success"
              p.inputLocked=true
              box("Thanks!",function() cafeReturnToCounter(true) end,
                {speaker=order.customer.name})
              return true
            end
          end
        end
      end
      return false
    end

    local SCALPER_LINE={
      {8,14,"SPRITE_GAMBLER",
        "MAN: See this line?\f"
        .."I'm getting the first\nspot tonight.\f"
        .."Tomorrow, when the\nDEPT. STORE opens,\f"
        .."I'm buying every\nCOLOSSEUM box I can.\f"
        .."If there's no limit,\neven better.\f"
        .."Then they're going\nonline for triple.\f"
        .."Easy money."},
      {9,14,"SPRITE_SUPER_NERD",
        "EVOLUTION packs are\ngoing to disappear\f"
        .."the second those\ndoors open."},
      {10,14,"SPRITE_BEAUTY",
        "MYSTERY has the\nbest chase cards.\f"
        .."I'm buying a case."},
      {11,14,"SPRITE_GAMBLER",
        "LABORATORY is easy\nmoney if you know\f"
        .."which boxes to flip."},
      {12,14,"SPRITE_GENTLEMAN",
        "COLOSSEUM, EVOLUTION,\nMYSTERY, LABORATORY...\f"
        .."I'll take whatever\nis left to resell."},

      -- The kids are directly behind the five scalpers in the same queue.
      {13,14,"SPRITE_YOUNGSTER"},
      {14,14,"SPRITE_YOUNGSTER"},
      {15,14,"SPRITE_GIRL"},
    }

    local CARD_KID_FIRST=6
    local CARD_KIDS={
      [6]={13,14,"SPRITE_YOUNGSTER",
        "YOUNGSTER: I got here early\nso I could get a pack.\f"
        .."I hope the scalpers\ndon't buy them all."},
      [7]={14,14,"SPRITE_YOUNGSTER",
        "YOUNGSTER: I saved my allowance.\f"
        .."I hope there's still\na pack when it's my turn."},
      [8]={15,14,"SPRITE_GIRL",
        "GIRL: I just want a pack\nto open with my friends.\f"
        .."The scalpers keep\nbuying everything."},
    }

    local KID_PROGRESS_LINES={
      [6]={hopeful="YOUNGSTER: Whoa...\nthe line's actually\ngetting shorter!",near="YOUNGSTER: Just a few\nmore!\fWe might actually\nget our packs!"},
      [7]={hopeful="YOUNGSTER: They're\nstarting to leave!\fMaybe my allowance\nwon't go to waste.",near="YOUNGSTER: I can almost\nsee the front now!"},
      [8]={hopeful="GIRL: DITTO's really\nscaring them off!\fMaybe that Leafeon\nis still here.",near="GIRL: Please let there\nstill be a Leafeon!"},
    }

    local NERVOUS_SCALPER_LINES={
      "Uh... did you see\nwhat happened\nto that guy?",
      "The guy at the front\nsaid this would be\neasy money...",
      "Maybe I don't need\nthat many boxes.",
      "Okay, this line is\nstarting to feel\nlike a bad idea.",
      "Do you think DITTO\ncan tell who's\na scalper?",
      "Nobody panic.\f"
        .."I'm definitely\nnot panicking.",
    }

    local function defeatedScalperCount(q)
      local n=0
      q.scalpersDefeated=q.scalpersDefeated or {}
      for i=1,CARD_KID_FIRST-1 do
        if q.scalpersDefeated[i] then n=n+1 end
      end
      return n
    end

    -- Permanent version of the original Celadon barrier layout.
    -- Keep the first two vertical border blocks and intentionally omit the
    -- old third/bottom block so the house tile below remains untouched.
    local CELADON_KID_BARRIER_BLOCKS={
      {10,5},{10,6},
    }
    local function applyCeladonKidBarrier(ow)
      if not (ow and ow.map and ow.map.id=="CELADON_CITY") then return end
      local map=ow.map

      -- Remove stale temporary/NPC barrier artifacts from intermediate builds.
      for i=#(ow.npcs or {}),1,-1 do
        local n=ow.npcs[i]
        local name=n and n.def and n.def.name or ""
        if name:match("^CEL_HOUSE_BARRIER_")
            or name:match("^CEL_KID_BARRIER_") then
          table.remove(ow.npcs,i)
          for j=#(ow.entities or {}),1,-1 do
            if ow.entities[j]==n then table.remove(ow.entities,j) end
          end
        end
      end
      for i=#(ow.entities or {}),1,-1 do
        local e=ow.entities[i]
        if e and e.pokopiaKidBarrier then table.remove(ow.entities,i) end
      end

      -- If 1.0.319 already changed the horizontal row on this live map,
      -- restore those cells from the map's original definition where possible.
      -- Fresh loads never need this branch.
      if map._pokopiaPermanentHouseBarrier and map._pokopiaHouseBarrierOriginal then
        for k,original in pairs(map._pokopiaHouseBarrierOriginal) do
          local bx,by=k:match("^(%-?%d+):(%-?%d+)$")
          bx,by=tonumber(bx),tonumber(by)
          if bx and by and original~=nil then
            ow:replaceBlock(bx,by,original)
          end
        end
      end

      -- Original barrier style: use Celadon's normal border block, in the
      -- same vertical block column as the first implementation.
      local barrierBlock=(map.def and map.def.borderBlock) or 0x0f
      for _,pos in ipairs(CELADON_KID_BARRIER_BLOCKS) do
        ow:replaceBlock(pos[1],pos[2],barrierBlock)
      end
      map._pokopiaPermanentKidBarrier=true
    end

    local function scalperCutoutSpeaker(sprite)
      if sprite=="SPRITE_SUPER_NERD" then return "SUPER NERD" end
      if sprite=="SPRITE_BEAUTY" then return "BEAUTY" end
      if sprite=="SPRITE_GENTLEMAN" then return "GENTLEMAN" end
      return "GAMBLER"
    end

    local function ensureCeladonScalperLine()
      if not (ow and ow.map and ow.map.id=="CELADON_CITY") then return {} end
      local cast={}
      local function findLive(name)
        for _,npc in ipairs(ow.npcs or {}) do
          if npc and npc.def and npc.def.name==name then return npc end
        end
        return nil
      end
      local function removeNpcAt(x,y)
        for i=#(ow.npcs or {}),1,-1 do
          local npc=ow.npcs[i]
          local name=npc and npc.def and npc.def.name or ""
          if npc and npc.cellX==x and npc.cellY==y
              and not name:match("^CEL_") then
            table.remove(ow.npcs,i)
            for j=#(ow.entities or {}),1,-1 do
              if ow.entities[j]==npc then table.remove(ow.entities,j) end
            end
          end
        end
      end
      local function exactSpawn(name,sprite,x,y,facing)
        local live=findLive(name)
        if live then cast[name]=live; return live end
        removeNpcAt(x,y)
        local a=addActor(name,sprite,x,y,facing or "down")
        a.wanders=false
        a.frozen=true
        a.passable=false
        cast[name]=a
        return a
      end
      local function removeNamed(name)
        for i=#(ow.npcs or {}),1,-1 do
          local npc=ow.npcs[i]
          if npc and npc.def and npc.def.name==name then
            table.remove(ow.npcs,i)
            for j=#(ow.entities or {}),1,-1 do
              if ow.entities[j]==npc then table.remove(ow.entities,j) end
            end
          end
        end
      end

      local q=pokopiaData(game)
      if type(q.scalpersDefeated)~="table" then q.scalpersDefeated={} end
      applyCeladonKidBarrier(ow)

      -- Remove Celadon's stock gym-peeping old man permanently. In the
      -- original map he occupies (11,28), just outside the south gym.
      removeNpcAt(11,28)

      -- There is only one physical queue now. Before quest completion, every
      -- surviving scalper and all three kids occupy consecutive queue slots.
      if not q.cardQuestComplete then
        local slot=1
        for i=1,CARD_KID_FIRST-1 do
          if not q.scalpersDefeated[i] then
            local row=SCALPER_LINE[i]
            local pos=SCALPER_LINE[slot]
            exactSpawn(string.format("CEL_SCALPER_%02d",i),
              row[3],pos[1],pos[2],({"down","left","right","up"})[((i-1)%4)+1])
            slot=slot+1
          else
            removeNamed(string.format("CEL_SCALPER_%02d",i))
          end
        end
        for i=CARD_KID_FIRST,#SCALPER_LINE do
          local kid=CARD_KIDS[i]
          local pos=SCALPER_LINE[slot]
          exactSpawn(string.format("CEL_CARD_KID_%02d",i),
            kid[3],pos[1],pos[2],"left")
          slot=slot+1
        end
      else
        -- Once the kids have entered the store, none of the queue actors
        -- respawn outside.
        for i=1,CARD_KID_FIRST-1 do
          removeNamed(string.format("CEL_SCALPER_%02d",i))
        end
        for i=CARD_KID_FIRST,#SCALPER_LINE do
          removeNamed(string.format("CEL_CARD_KID_%02d",i))
        end
      end

      -- Keep the surrounding Celadon flavor cast stable in both states.
      local chatterA=exactSpawn("CEL_TCG_CHAT_A","SPRITE_BEAUTY",6,15,"right")
      local chatterB=exactSpawn("CEL_TCG_CHAT_B","SPRITE_SUPER_NERD",7,15,"left")
      chatterA.facing="right"; chatterB.facing="left"
      if q.cardQuestComplete then
        exactSpawn("CEL_STORE_GREETER","SPRITE_GENTLEMAN",11,14,"up")
      else
        removeNamed("CEL_STORE_GREETER")
      end
      exactSpawn("CEL_CARD_COLLECTOR","SPRITE_SUPER_NERD",28,18,"left")
      exactSpawn("CEL_SLOT_BUDGET","SPRITE_GAMBLER",25,20,"right")

      local sleeperSprite=nil
      local viridian=game.data.maps and game.data.maps.VIRIDIAN_CITY
      for _,obj in ipairs((viridian and viridian.objects) or {}) do
        if obj and obj.name=="VIRIDIANCITY_OLD_MAN_SLEEPY" then
          sleeperSprite=obj.sprite
          break
        end
      end
      sleeperSprite=sleeperSprite
        or (game.data.sprites["SPRITE_GAMBLER_ASLEEP"] and "SPRITE_GAMBLER_ASLEEP")
        or "SPRITE_GAMBLER"

      local old=exactSpawn("CEL_DRUNK_OLD_MAN",sleeperSprite,36,17,"down")
      old.frozen=true
      old.wanders=false

      local officerSprite=game.data.sprites["SPRITE_GUARD"] and "SPRITE_GUARD"
        or "SPRITE_GENTLEMAN"
      local officer=exactSpawn("CEL_DRUNK_OFFICER",officerSprite,37,17,"left")
      officer.facing="left"
      officer.frozen=true
      officer.wanders=false

      if not q.grandsonInHouse then
        exactSpawn("CEL_GYM_GRANDSON",
          game.data.sprites["SPRITE_YOUNGSTER"] and "SPRITE_YOUNGSTER"
            or "SPRITE_SUPER_NERD",
          25,22,"left")
      else
        removeNamed("CEL_GYM_GRANDSON")
      end
      exactSpawn("CEL_SLOWBRO","SLOWBRO",22,16,"down")

      local lee=exactSpawn("CEL_HITMONLEE","HITMONLEE",3,11,"right")
      local chan=exactSpawn("CEL_HITMONCHAN","HITMONCHAN",4,11,"left")
      lee.facing="right"
      chan.facing="left"

      return cast
    end

    local function showOldPhotoPortrait(done)
      local Font=require("src.render.Font")

      local erika,erikaMask=trainerPortraitImage(game,"ERIKA")
      local oldman=nil
      do
        local Assets=require("src.render.Assets")
        local ok,img=pcall(function()
          return love.graphics.newImage(Assets.resolve("assets/generated/battle/oldmanb.png"))
        end)
        if ok and img then
          if img.setFilter then img:setFilter("nearest","nearest") end
          oldman=img
        end
      end

      local photoBg=nil
      do
        local ok,img=pcall(function()
          return love.graphics.newImage(tostring(mod.path).."/assets/old_photo/celadon_gym_background.jpg")
        end)
        if ok and img then
          if img.setFilter then img:setFilter("nearest","nearest") end
          photoBg=img
        end
      end

      local view={isOpaque=false}
      function view:update()
        local input=game.input
        if input:wasPressed("a") or input:wasPressed("b") then
          game.stack:pop()
          if done then done() end
        end
      end

      local function drawFull(img,mask,x,bottom,targetW)
        if not img then return end
        local iw,ih=img:getDimensions()
        local scale=targetW/iw
        local y=bottom-ih*scale
        if mask then
          local shader=getTrainerMaskShader()
          if shader then
            shader:send("cutoutMask",mask)
            love.graphics.setShader(shader)
          end
        end
        love.graphics.draw(img,x,y,0,scale,scale)
        love.graphics.setShader()
      end

      local function drawPhotoBackground()
        if not photoBg then
          love.graphics.setColor(1,1,1,1)
          love.graphics.rectangle("fill",8,8,144,108)
          return
        end
        local iw,ih=photoBg:getDimensions()
        local targetX,targetY,targetW,targetH=8,8,144,108
        local targetAspect=targetW/targetH
        local srcAspect=iw/ih
        local sx,sy,sw,sh=0,0,iw,ih
        if srcAspect>targetAspect then
          sw=math.floor(ih*targetAspect)
          sx=math.floor((iw-sw)/2)
        elseif srcAspect<targetAspect then
          sh=math.floor(iw/targetAspect)
          sy=math.floor((ih-sh)/2)
        end
        local quad=love.graphics.newQuad(sx,sy,sw,sh,iw,ih)
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(photoBg,quad,targetX,targetY,0,targetW/sw,targetH/sh)
      end

      function view:draw()
        love.graphics.push("all")
        love.graphics.setColor(1,1,1,1)
        love.graphics.rectangle("fill",4,4,152,132)
        drawPhotoBackground()

        love.graphics.setColor(1,1,1,1)
        -- Grandpa's battle sprite has extra source padding compared with Erika.
        -- Nudge him toward her and use a lower baseline so the visible figures,
        -- rather than their source-image rectangles, read as bottom-aligned.
        drawFull(oldman,nil,26,118,64)
        drawFull(erika,erikaMask,75,112,64)

        love.graphics.setColor(0,0,0,1)
        love.graphics.rectangle("line",4,4,152,132)
        love.graphics.rectangle("line",8,8,144,108)
        Font.draw("OLD PHOTO",48,120)
        love.graphics.setColor(1,1,1,1)
        love.graphics.pop()
      end

      game.stack:push(view)
    end

    local function walkGrandsonIntoChiefHouse(ow,npc,done)
      if not (ow and npc) then if done then done(false) end return end
      npc.frozen=false
      npc.wanders=false
      npc.passable=true
      npc.stepFrames=6

      -- This is a story walk, not a teleport. Build a route using the map's
      -- real walkable cells but deliberately ignore temporary NPC occupancy so
      -- a wandering Celadon pedestrian cannot make the grandson's cutscene
      -- fail and silently advance him into the house.
      local tx,ty=35,26 -- one tile above the CELADON_CHIEF_HOUSE door
      local dirs={{0,-1,"up"},{0,1,"down"},{-1,0,"left"},{1,0,"right"}}
      local function key(x,y) return x..":"..y end
      local q={{npc.cellX,npc.cellY}}
      local qi=1
      local prev={[key(npc.cellX,npc.cellY)]=false}
      while q[qi] do
        local cx,cy=q[qi][1],q[qi][2]
        qi=qi+1
        if cx==tx and cy==ty then break end
        for _,d in ipairs(dirs) do
          local nx,ny=cx+d[1],cy+d[2]
          local k=key(nx,ny)
          local target=(nx==tx and ny==ty)
          if prev[k]==nil and ow.map:inBounds(nx,ny)
              and ow.map:isWalkableCell(nx,ny)
              and (target or not ow.map:warpAtCell(nx,ny)) then
            prev[k]={cx,cy,d[3]}
            q[#q+1]={nx,ny}
          end
        end
      end

      if prev[key(tx,ty)]==nil and not (npc.cellX==tx and npc.cellY==ty) then
        if done then done(false) end
        return
      end

      local route={}
      local k=key(tx,ty)
      while prev[k] do
        local v=prev[k]
        table.insert(route,1,v[3])
        k=key(v[1],v[2])
      end

      local ri=1
      local function nextStep()
        local dir=route[ri]
        if dir then
          ri=ri+1
          ow:scriptMove(npc,dir,1,nextStep,{collide=false})
          return
        end
        npc.facing="down"
        -- Only after the visible final step onto the door warp do we remove
        -- the outdoor actor and mark him as having reached home.
        ow:scriptMove(npc,"down",1,function()
          removeRuntimeActor(npc)
          if done then done(true) end
        end,{collide=false})
      end
      nextStep()
    end

    -- Play the original Gen I MEGA KICK / MEGA PUNCH battle animation as a
    -- transparent overlay on the overworld. The overworld remains visible and
    -- frozen underneath; AnimPlayer supplies the real move OAM sequence while
    -- Sound.playMove uses the ROM-derived move sound/pitch/tempo.
    local function playScalperStrike(form,done)
      local moveId=(form=="HITMONLEE") and "MEGA_KICK" or "MEGA_PUNCH"
      local move=game.data.moves and game.data.moves[moveId]
      local AnimPlayer=require("src.battle.AnimPlayer")
      local Sound=require("src.core.Sound")
      local anim=game.data.battle_anims and AnimPlayer.new(game.data.battle_anims) or nil
      if anim then anim:start(moveId,true) end
      if move and move.anim then Sound.playMove(game.data,move.anim) end

      local fx={
        isOpaque=false,
        frame=0,
        flash=0,
      }
      function fx:update()
        self.frame=self.frame+1
        if anim and not anim:isDone() then
          anim:update()
          for _,ev in ipairs(anim:pollEffects()) do
            if ev.effect=="SE_DARK_SCREEN_FLASH" then self.flash=4 end
          end
        end
        if self.flash>0 then self.flash=self.flash-1 end
        -- Keep the impact readable, but do not make Ditto wait for the full
        -- cosmetic move animation before regaining overworld control.
        if self.frame>=4 or (anim and anim:isDone() and self.frame>=3) then
          if anim and anim.release then anim:release() end
          if game.stack:top()==self then game.stack:pop() end
          if done then done() end
        end
      end
      function fx:draw()
        if anim then anim:draw() end
        if self.flash>0 and self.flash%2==0 then
          love.graphics.setColor(1,1,1,0.75)
          love.graphics.rectangle("fill",0,0,160,144)
          love.graphics.setColor(1,1,1,1)
        end
      end
      game.stack:push(fx)
    end

    local function openScalperRound(idx,target,done)
      local q=pokopiaData(game)
      local row=SCALPER_LINE[idx]
      if not row then
        if done then done(false) end
        return
      end

      local playerSpecies=q.currentForm
      if playerSpecies~="HITMONLEE" and playerSpecies~="HITMONCHAN" then
        if done then done(false) end
        return
      end

      local BattleState=require("src.battle.BattleState")
      local Pokemon=require("src.pokemon.Pokemon")
      local Timing=require("src.core.Timing")
      local Sound=require("src.core.Sound")
      local Assets=require("src.render.Assets")
      local Sprites=require("src.pokemon.Sprites")
      local Font=require("src.render.Font")

      -- Reuse a harmless internal Pokémon record for BattleState's HP/status
      -- bookkeeping, but replace every visible enemy identity with the human.
      local battle=BattleState.newWild(game,"DITTO",30)
      local playerMon=Pokemon.new(game.data,playerSpecies,30)
      local enemyMon=Pokemon.new(game.data,"DITTO",30)

      playerMon.stats.hp=3
      playerMon.hp=3
      enemyMon.stats.hp=3
      enemyMon.hp=3

      battle.player=BattleState.makeBattler(game.data,playerMon,true,nil)
      battle.enemy=BattleState.makeBattler(game.data,enemyMon,false,nil)
      battle.playerParty={playerMon}
      battle.enemyParty={enemyMon}
      battle.player.shownHP=3
      battle.enemy.shownHP=3
      battle.player.shownPx=Timing.hpBarPixels(3,3)
      battle.enemy.shownPx=Timing.hpBarPixels(3,3)
      battle.player.name=playerSpecies
      battle.player.mon.nickname=playerSpecies

      battle.enemy.name="SCALPER"
      battle.enemy.mon.nickname="SCALPER"

      -- Use the exact differentiated trainer cutout for this line member as
      -- the enemy battler image. No Pokémon is shown on the scalper's side.
      local cutoutSpeaker=scalperCutoutSpeaker(row[3])
      local cutout=trainerPortraitImage(game,cutoutSpeaker)
      if cutout then
        battle.enemy.sprite=cutout
      end

      battle:syncSides()
      battle.introText="SCALPER wants\nto fight!"
      battle.rpsCursor=1
      battle.rpsChoices={"ROCK","PAPER","SCISSORS","FORFEIT"}
      battle.rpsBeats={
        ROCK="SCISSORS",
        PAPER="ROCK",
        SCISSORS="PAPER",
      }

      -- Ditto stays visibly transformed in its learned purple Hitmon form.
      local purpleCache={}
      local function purpleBack(species)
        if purpleCache[species] then return purpleCache[species] end
        local path=Sprites.path(game.data,species,"back",{kind="battle"})
        if not path then return nil end
        local ok,id=pcall(Assets.imageData,path)
        if not ok or not id then return nil end
        id:mapPixel(function(_,_,r,g,b,a)
          if a==0 then return r,g,b,0 end
          if r>0.83 and g>0.83 and b>0.83 then return 1,1,1,0 end
          if r>0.50 then return 221/255,178/255,242/255,1 end
          if r>0.17 then return 167/255,92/255,201/255,1 end
          return 79/255,38/255,104/255,1
        end)
        local okImg,img=pcall(love.graphics.newImage,id)
        if okImg and img then
          img:setFilter("nearest","nearest")
          purpleCache[species]=img
          return img
        end
        return nil
      end

      local originalEnter=battle.enter
      function battle:enter()
        -- Safari's intro path suppresses the normal player Poké Ball/send-out.
        local originalKind=self.battleKind
        self.safari=true
        self.battleKind=function() return "wild" end

        -- A human opponent should not emit a Pokémon cry.
        local originalCry=self.playEntranceCry
        self.playEntranceCry=function() return nil end

        originalEnter(self)

        self.safari=nil
        self.battleKind=originalKind
        self.playEntranceCry=originalCry

        self.playerBackPic=purpleBack(playerSpecies)
        self.showPlayerBack=self.playerBackPic~=nil

        -- originalEnter builds the wild enemy pic after our pre-enter setup;
        -- force the scalper cutout back over that slot once the intro exists.
        local freshCutout=trainerPortraitImage(game,cutoutSpeaker)
        if freshCutout then self.enemy.sprite=freshCutout end
      end

      local originalUpdate=battle.update
      local originalDrawTextArea=battle.drawTextArea

      local function queueRpsTurn(self,move)
        self.phase="messages"
        self.afterQueue="menu"

        if move=="FORFEIT" then
          self:say(playerSpecies.." forfeited!")
          self.result="lose"
          self.afterQueue="finish"
          return
        end

        local foeMoves={"ROCK","PAPER","SCISSORS"}
        local foeMove=foeMoves[love.math.random(1,3)]
        self:say(playerSpecies..": "..move.."!\n"
          .."SCALPER: "..foeMove.."!")

        if move==foeMove then
          self:say("It's a tie!")
          return
        end

        local playerHit=self.rpsBeats[move]==foeMove
        local hitTarget=playerHit and self.enemy or self.player
        local newHP=math.max(1,hitTarget.mon.hp-1)
        hitTarget.mon.hp=newHP

        self:act(function()
          Sound.play(self.data,"Damage")
          self.fx=self.fx or {}
          self.fx.blink={target=hitTarget,frames=20}
        end)
        table.insert(self.queue,{drain=true,battler=hitTarget,stopAt=newHP})
        self:say("A clean hit!")

        if newHP<=1 then
          if playerHit then
            self:say("SCALPER is beaten!")
            self.result="win"
            self:act(function() self:playVictoryMusic() end)
          else
            self:say("SCALPER wins\nthe round!")
            self.result="lose"
          end
          self.afterQueue="finish"
        end
      end

      function battle:update(dt)
        if self.phase~="menu" then
          return originalUpdate(self,dt)
        end

        self.frame=(self.frame or 0)+1
        if self.updateFx then self:updateFx() end

        local input=self.game.input
        local col=(self.rpsCursor-1)%2
        local rowIndex=math.floor((self.rpsCursor-1)/2)

        if input:wasPressed("left") then col=math.max(0,col-1)
        elseif input:wasPressed("right") then col=math.min(1,col+1)
        elseif input:wasPressed("up") then rowIndex=math.max(0,rowIndex-1)
        elseif input:wasPressed("down") then rowIndex=math.min(1,rowIndex+1)
        end
        self.rpsCursor=rowIndex*2+col+1

        if input:wasPressed("a") then
          Sound.play(self.data,"Press_AB")
          queueRpsTurn(self,self.rpsChoices[self.rpsCursor])
        end
      end

      function battle:drawTextArea()
        if self.phase~="menu" then
          return originalDrawTextArea(self)
        end

        Font.drawBox(0,12,20,6)
        love.graphics.setColor(0,0,0,1)
        Font.draw("ROCK",16,104)
        Font.draw("PAPER",88,104)
        Font.draw("SCISSORS",16,120)
        Font.draw("FORFEIT",88,120)

        local pos={{8,104},{80,104},{8,120},{80,120}}
        local cp=pos[self.rpsCursor]
        love.graphics.polygon("fill",
          cp[1],cp[2]+2,cp[1],cp[2]+8,cp[1]+5,cp[2]+5)
        love.graphics.setColor(1,1,1,1)
      end

      battle.onFinish=function(result)
        local won=result=="win"
        if won then require("src.core.Sound").play(game.data,"Get_Item1") end
        if done then done(won) end
      end

      if ow and ow.pushBattle then
        ow:pushBattle(battle)
      else
        game.stack:push(battle)
      end
    end

    local function openHitmonRound(done)
      local Font=require("src.render.Font")
      local Assets=require("src.render.Assets")
      local Sprites=require("src.pokemon.Sprites")
      local q=pokopiaData(game)

      local imageCache={}
      local function battlerPic(species)
        if imageCache[species] then return imageCache[species] end
        local path=Sprites.path(game.data,species,"front",{kind="battle"})
        if not path then return nil end
        local ok,img=pcall(Assets.image,path)
        if ok and img then
          img:setFilter("nearest","nearest")
          imageCache[species]=img
          return img
        end
        return nil
      end

      -- Ditto's battle transformation palette. This is the same purple ramp
      -- used by the overworld transform system: background white is discarded,
      -- and the three visible GB shades become Ditto purple.
      local purpleBackCache={}
      local function purpleBack(species)
        if purpleBackCache[species] then return purpleBackCache[species] end
        local path=Sprites.path(game.data,species,"back",{kind="battle"})
        if not path then return nil end
        local ok,id=pcall(Assets.imageData,path)
        if not ok or not id then return nil end
        id:mapPixel(function(_,_,r,g,b,a)
          if a==0 then return r,g,b,0 end
          if r>0.83 and g>0.83 and b>0.83 then
            return 1,1,1,0
          elseif r>0.50 then
            return 221/255,178/255,242/255,1
          elseif r>0.17 then
            return 167/255,92/255,201/255,1
          end
          return 79/255,38/255,104/255,1
        end)
        local okImg,img=pcall(love.graphics.newImage,id)
        if okImg and img then
          img:setFilter("nearest","nearest")
          purpleBackCache[species]=img
          return img
        end
        return nil
      end

      local function drawBattler(img,x,y,maxW,maxH)
        if not img then return end
        local iw,ih=img:getDimensions()
        local sc=math.min(maxW/iw,maxH/ih)
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(img,x,y,0,sc,sc)
      end

      local select={
        isOpaque=false,
        cursor=1,
        choices={"HITMONLEE","HITMONCHAN"},
      }

      local function startActualBattle(chosen)
        -- The selected Hitmon is the form Ditto copies for this spar.
        -- Record the selection separately; it becomes permanent only on a win.
        q.hitmonPendingChoice=chosen
        local playerSpecies=chosen
        local foeSpecies=(chosen=="HITMONLEE") and "HITMONCHAN" or "HITMONLEE"

        -- Commit the learned form as soon as the spar itself declares a win.
        -- The old path waited for BattleState:onFinish, but this is a synthetic
        -- one-Pokemon battle and some engine revisions normalize its teardown
        -- result before invoking that callback.  Transformation progression
        -- must not depend on that unrelated party-health cleanup.
        local function commitHitmonWin()
          q.forms=q.forms or {}
          local existing=(q.hitmonLearnedChoice=="HITMONLEE"
              or q.hitmonLearnedChoice=="HITMONCHAN")
            and q.hitmonLearnedChoice or nil
          local learned=existing or q.hitmonPendingChoice or chosen
          if learned~="HITMONLEE" and learned~="HITMONCHAN" then
            return nil,false
          end
          local newlyLearned=existing==nil
          q.hitmonWinChoice=learned
          q.hitmonLearnedChoice=learned
          q.hitmonLearnedForm=learned
          q.forms[learned]=true
          return learned,newlyLearned
        end

        game.stack:pop()

        local BattleState=require("src.battle.BattleState")
        local Pokemon=require("src.pokemon.Pokemon")
        local Timing=require("src.core.Timing")
        local Sound=require("src.core.Sound")

        local battle=BattleState.newWild(game,foeSpecies,30)

        local playerMon=Pokemon.new(game.data,playerSpecies,30)
        local enemyMon=Pokemon.new(game.data,foeSpecies,30)

        playerMon.stats.hp=3
        playerMon.hp=3
        enemyMon.stats.hp=3
        enemyMon.hp=3

        battle.player=BattleState.makeBattler(game.data,playerMon,true,nil)
        battle.enemy=BattleState.makeBattler(game.data,enemyMon,false,nil)
        battle.playerParty={playerMon}
        battle.enemyParty={enemyMon}
        battle.player.shownHP=3
        battle.enemy.shownHP=3
        battle.player.shownPx=Timing.hpBarPixels(3,3)
        battle.enemy.shownPx=Timing.hpBarPixels(3,3)
        battle.player.name=playerSpecies
        battle.enemy.name=foeSpecies
        battle.player.mon.nickname=playerSpecies
        battle.enemy.mon.nickname=foeSpecies
        battle:syncSides()

        -- This spar uses synthetic battlers rather than the save-file party.
        -- BattleState:finish() normally changes any non-loss result to "lose"
        -- when Party.firstHealthy(playerPartyView()) is empty. Temporarily mark
        -- only teardown as a demo-style non-party battle so the engine keeps
        -- the RPS result we set ("win" / "lose") and onFinish receives it.
        local originalFinish=battle.finish
        function battle:finish()
          local priorDemo=self.demo
          self.demo=true
          originalFinish(self)
          self.demo=priorDemo
        end

        battle.introText=foeSpecies.." wants\nto go a round!"
        battle.rpsCursor=1
        battle.rpsChoices={"ROCK","PAPER","SCISSORS","FORFEIT"}
        battle.rpsBeats={
          ROCK="SCISSORS",
          PAPER="ROCK",
          SCISSORS="PAPER",
        }

        local originalEnter=battle.enter
        function battle:enter()
          -- Temporarily take the Safari no-send-out branch. We immediately
          -- clear it again after the stock intro is constructed, so every
          -- later battle rule remains a normal wild BattleState battle.
          local originalKind=self.battleKind
          self.safari=true
          self.battleKind=function() return "wild" end
          originalEnter(self)
          self.safari=nil
          self.battleKind=originalKind

          -- Red's trainer back is never shown. Ditto itself enters the frame.
          self.playerBackPic=purpleBack("DITTO")
          self.showPlayerBack=self.playerBackPic~=nil

          -- There is no Poké Ball / send-out. Ditto transforms in place into
          -- the fighter opposite the opponent before the command menu opens.
          -- BattleState has no sayAuto method. Queue the transformation
          -- announcement through its supported battle-message API.
          self:say("DITTO transformed into\n"..playerSpecies.."!")
          self:act(function()
            -- Once Transform lands, move the purple Hitmon back sprite into
            -- the normal player-battler slot. BattleState deliberately hides
            -- the player HP HUD while showPlayerBack is true because that flag
            -- normally means the trainer intro is still on screen.
            local transformed=purpleBack(playerSpecies)
            if transformed then
              self.player.sprite=transformed
            end
            self.playerBackPic=nil
            self.showPlayerBack=false
            Sound.play(self.data,"Faint_Fall")
          end)
          table.insert(self.queue,{wait=22})
        end

        local originalUpdate=battle.update
        local originalDrawTextArea=battle.drawTextArea

        local function queueRpsTurn(self,move)
          self.phase="messages"
          self.afterQueue="menu"

          if move=="FORFEIT" then
            self:say(playerSpecies.." forfeited!")
            self.result="lose"
            self.afterQueue="finish"
            return
          end

          local foeMoves={"ROCK","PAPER","SCISSORS"}
          local foeMove=foeMoves[love.math.random(1,3)]
          self:say(playerSpecies..": "..move.."!\n"
            ..foeSpecies..": "..foeMove.."!")

          if move==foeMove then
            self:say("It's a tie!")
            return
          end

          local playerHit=self.rpsBeats[move]==foeMove
          local target=playerHit and self.enemy or self.player
          local newHP=math.max(1,target.mon.hp-1)
          target.mon.hp=newHP

          self:act(function()
            Sound.play(self.data,"Damage")
            self.fx=self.fx or {}
            self.fx.blink={target=target,frames=20}
          end)
          table.insert(self.queue,{
            drain=true,battler=target,stopAt=newHP
          })
          self:say("A clean hit!")

          if newHP<=1 then
            if playerHit then
              self:say(playerSpecies.." wins\nthe round!")
              self.result="win"
              self.pokopiaHitmonWon=true
              local learned,newlyLearned=commitHitmonWin()
              self.pokopiaHitmonLearned=learned
              self.pokopiaHitmonNewlyLearned=newlyLearned
              self:act(function() self:playVictoryMusic() end)
            else
              self:say(foeSpecies.." wins\nthe round!")
              self.result="lose"
            end
            self.afterQueue="finish"
          end
        end

        function battle:update(dt)
          if self.phase~="menu" then
            return originalUpdate(self,dt)
          end

          self.frame=(self.frame or 0)+1
          if self.updateFx then self:updateFx() end

          local input=self.game.input
          local col=(self.rpsCursor-1)%2
          local row=math.floor((self.rpsCursor-1)/2)

          if input:wasPressed("left") then col=math.max(0,col-1)
          elseif input:wasPressed("right") then col=math.min(1,col+1)
          elseif input:wasPressed("up") then row=math.max(0,row-1)
          elseif input:wasPressed("down") then row=math.min(1,row+1)
          end
          self.rpsCursor=row*2+col+1

          if input:wasPressed("a") then
            Sound.play(self.data,"Press_AB")
            queueRpsTurn(self,self.rpsChoices[self.rpsCursor])
          end
        end

        function battle:drawTextArea()
          if self.phase~="menu" then
            return originalDrawTextArea(self)
          end

          Font.drawBox(0,12,20,6)
          love.graphics.setColor(0,0,0,1)
          Font.draw("ROCK",16,104)
          Font.draw("PAPER",88,104)
          Font.draw("SCISSORS",16,120)
          Font.draw("FORFEIT",88,120)

          local pos={
            {8,104},{80,104},{8,120},{80,120},
          }
          local cp=pos[self.rpsCursor]
          love.graphics.polygon("fill",
            cp[1],cp[2]+2,
            cp[1],cp[2]+8,
            cp[1]+5,cp[2]+5)
          love.graphics.setColor(1,1,1,1)
        end

        battle.onFinish=function(result)
          local coins=math.max(0,game.save.coins or 0)
          -- Trust the spar's own terminal state over BattleState teardown.
          -- `pokopiaHitmonWon` is set at the exact RPS win frame, before the
          -- synthetic battle can be reclassified by generic party cleanup.
          local won=(result=="win") or battle.pokopiaHitmonWon==true
          if won then
            require("src.core.Sound").play(game.data,"Get_Item1")
            game.save.coins=coins+10

            local learnedChoice=battle.pokopiaHitmonLearned
            local newlyLearned=battle.pokopiaHitmonNewlyLearned==true
            if not learnedChoice then
              learnedChoice,newlyLearned=commitHitmonWin()
            else
              -- Reassert all aliases in case another callback touched the
              -- root form table between the win frame and this dialogue.
              q.forms=q.forms or {}
              q.hitmonWinChoice=learnedChoice
              q.hitmonLearnedChoice=learnedChoice
              q.hitmonLearnedForm=learnedChoice
              q.forms[learnedChoice]=true
            end

            q.hitmonPendingChoice=nil

            local function finishWin()
              if done then done() end
            end

            local function showIdea()
              -- Keep this beat separate from the learned-state flag so saves
              -- that already won in an earlier build still receive the missing
              -- story moment once.
              q.hitmonIdeaShown=true
              local learned=q.hitmonLearnedChoice or chosen
              box("DITTO got an idea!\f"
                .."Maybe it can copy the\nway "..learned.." fights...\f"
                .."DITTO learned to\ntransform into\f"
                ..learned.."!",
                finishWin,
                {speaker="DITTO",
                 portrait={speaker="DITTO",expression="Determined"}})
            end

            box("You won 10 COINS!",
              function()
                if newlyLearned or not q.hitmonIdeaShown then
                  showIdea()
                else
                  finishWin()
                end
              end)
          else
            q.hitmonPendingChoice=nil
            game.save.coins=math.max(0,coins-10)
            box("You paid 10 COINS.",
              function() if done then done() end end)
          end
        end

        if ow and ow.pushBattle then
          ow:pushBattle(battle)
        else
          game.stack:push(battle)
        end
      end

      function select:update()
        local input=game.input
        if input:wasPressed("left") or input:wasPressed("right") then
          self.cursor=(self.cursor==1) and 2 or 1
        elseif input:wasPressed("b") then
          game.stack:pop()
          if done then done() end
        elseif input:wasPressed("a") then
          startActualBattle(self.choices[self.cursor])
        end
      end

      function select:draw()
        local lee=battlerPic("HITMONLEE")
        local chan=battlerPic("HITMONCHAN")

        -- No full-screen chooser panel. The overworld remains visible and
        -- only the two equally sized Pokemon cards receive boxed backgrounds.
        local boxes={
          {x=8,y=28,w=64,h=72,img=lee},
          {x=88,y=28,w=64,h=72,img=chan},
        }

        for _,box in ipairs(boxes) do
          Font.drawBox(box.x/8,box.y/8,box.w/8,box.h/8)
          if box.img then
            local iw,ih=box.img:getDimensions()
            local maxW,maxH=52,56
            local sc=math.min(maxW/iw,maxH/ih)
            local dw,dh=iw*sc,ih*sc
            local dx=box.x+(box.w-dw)/2
            local dy=box.y+(box.h-dh)/2
            love.graphics.setColor(1,1,1,1)
            love.graphics.draw(box.img,dx,dy,0,sc,sc)
          end
        end

        -- One cursor moves between the two cards. Only the highlighted
        -- Pokemon's name is shown, so the selection reads at a glance.
        local selected=boxes[self.cursor]
        local cursorX=selected.x+selected.w/2
        love.graphics.setColor(0,0,0,1)
        love.graphics.polygon("fill",
          cursorX-5,selected.y+selected.h+8,
          cursorX+5,selected.y+selected.h+8,
          cursorX,selected.y+selected.h+3)

        local name=self.choices[self.cursor]
        -- The hovered name gets its own compact box, separate from the
        -- Pokemon cards, so the selection label reads as a modern UI element.
        Font.drawBox(4,13,12,3)
        love.graphics.setColor(0,0,0,1)
        local nameX=(name=="HITMONLEE") and 44 or 40
        Font.draw(name,nameX,112)
        love.graphics.setColor(1,1,1,1)
      end

      game.stack:push(select)
    end

    local function ensureChiefHouseFamily()
      if not (ow and ow.map and ow.map.id=="CELADON_CHIEF_HOUSE") then return {} end
      local cast={}

      local function findLive(name)
        for _,npc in ipairs(ow.npcs or {}) do
          if npc and npc.def and npc.def.name==name then return npc end
        end
        return nil
      end

      local function spawn(name,sprite,x,y,facing)
        local live=findLive(name)
        if live then
          cast[name]=live
          return live
        end
        local a=addActor(name,sprite,x,y,facing)
        a.wanders=false
        a.frozen=true
        a.passable=false
        cast[name]=a
        return a
      end

      -- Reuse the original room's three safe occupied cells.
      spawn("CHIEF_HOUSE_MOM","SPRITE_BEAUTY",4,2,"down")
      spawn("CHIEF_HOUSE_DAD","SPRITE_GENTLEMAN",1,4,"right")
      spawn("CHIEF_HOUSE_KID","SPRITE_SUPER_NERD",5,6,"left")
      local q=pokopiaData(game)
      if q.grandsonInHouse then
        spawn("CHIEF_HOUSE_GRANDSON",
          game.data.sprites["SPRITE_YOUNGSTER"] and "SPRITE_YOUNGSTER"
            or "SPRITE_SUPER_NERD",
          4,6,"right")
      end
      return cast
    end

    local function restorePlayableDitto(actor,x,y,facing)
      if actor then
        x,y=x or actor.cellX,y or actor.cellY
        facing=facing or actor.facing
        removeRuntimeActor(actor)
      end
      local p=ow.player
      ow.playerHidden=false
      setActorCell(p,x or 10,y or 10)
      p.facing=facing or "down"
      p.inputLocked=false
      p.frozen=false
      p.passable=false
      local found=false
      for _,e in ipairs(ow.entities or {}) do if e==p then found=true break end end
      if not found then table.insert(ow.entities,p) end
      applyDittoForm(game,"DITTO",ow)
      restorePlayerInput(game,ow)
      if ow.camera then ow.camera:follow(p.px,p.py) end
      return p
    end

    local function walkActorTo(actor,tx,ty,done)
      local Collision=require("src.world.Collision")
      local dirs={
        {0,-1,"up"},{0,1,"down"},{-1,0,"left"},{1,0,"right"},
      }
      local function key(x,y) return x..":"..y end
      local q={{actor.cellX,actor.cellY}}
      local qi=1
      local prev={[key(actor.cellX,actor.cellY)]=false}

      while q[qi] do
        local cx,cy=q[qi][1],q[qi][2]
        qi=qi+1
        if cx==tx and cy==ty then break end

        for _,d in ipairs(dirs) do
          local nx,ny=cx+d[1],cy+d[2]
          local k=key(nx,ny)
          local target=(nx==tx and ny==ty)
          if prev[k]==nil
              and ow.map:inBounds(nx,ny)
              and ow.map:isWalkableCell(nx,ny)
              and not ow.map:warpAtCell(nx,ny)
              and not Collision.occupied(ow.entities,nx,ny,actor) then
            prev[k]={cx,cy,d[3]}
            q[#q+1]={nx,ny}
          end
        end
      end

      -- Scripted staging targets can occasionally be occupied or separated by
      -- furniture even though the intended motion is simply "head toward that
      -- side of the room". Keep normal collision rules, but if the exact cell
      -- is unreachable, stop on the reachable cell closest to the requested
      -- target instead of crashing or walking through an NPC/wall.
      local endX,endY=tx,ty
      if prev[key(tx,ty)]==nil and not (actor.cellX==tx and actor.cellY==ty) then
        local bestX,bestY=actor.cellX,actor.cellY
        local bestDist=math.abs(bestX-tx)+math.abs(bestY-ty)
        for _,cell in ipairs(q) do
          local x,y=cell[1],cell[2]
          local dist=math.abs(x-tx)+math.abs(y-ty)
          if dist<bestDist then
            bestX,bestY,bestDist=x,y,dist
          end
        end
        endX,endY=bestX,bestY
      end

      local route={}
      local k=key(endX,endY)
      while prev[k] do
        local p=prev[k]
        table.insert(route,1,p[3])
        k=key(p[1],p[2])
      end

      local ri=1
      local function nextStep()
        local dir=route[ri]
        if not dir then
          if done then defer(4,done) end
          return
        end
        ri=ri+1
        ow:scriptMove(actor,dir,1,nextStep,{collide=true})
      end
      nextStep()
    end

    local function switchSceneWithFade(change)
      -- Use the engine's real Gen 1 palette fade, the same transition class
      -- used by ordinary building/map transitions.
      local Transition=require("src.render.Transition")
      game.stack:push(Transition.new(game,change,nil,false))
    end

    local function startCardHeroEnding()
      local q=pokopiaData(game)
      local learnedHitmon=(q.hitmonLearnedChoice=="HITMONLEE"
        or q.hitmonLearnedChoice=="HITMONCHAN")
      if q.cardQuestComplete or q.cardHeroEndingStarted
          or not learnedHitmon
          or not (ow and ow.map and ow.map.id=="CELADON_CITY" and ow.player) then
        q.cardHeroPending=nil
        return
      end

      q.cardHeroEndingStarted=true
      q.cardHeroPending=nil
      local p=ow.player
      p.inputLocked=true

      local kids={}
      for _,npc in ipairs(ow.npcs or {}) do
        local name=npc and npc.def and npc.def.name or ""
        if name:match("^CEL_CARD_KID_") then kids[#kids+1]=npc end
      end
      table.sort(kids,function(a,b)
        local an=a and a.def and a.def.name or ""
        local bn=b and b.def and b.def.name or ""
        return an<bn
      end)

      local function faceDitto(actor)
        if not actor then return end
        local dx=p.cellX-(actor.cellX or 0)
        local dy=p.cellY-(actor.cellY or 0)
        if math.abs(dx)>math.abs(dy) then
          actor.facing=(dx<0) and "left" or "right"
        else
          actor.facing=(dy<0) and "up" or "down"
        end
      end
      for _,kid in ipairs(kids) do faceDitto(kid) end

      box("YOUNGSTER: You did it!\f"
        .."You chased every\nscalper away!\f"
        .."You're our hero,\nDITTO!",
        function()
          box("GIRL: Come on!\f"
            .."The card vendors are\nopen on the 2nd floor!\f"
            .."Let's go get packs!",
            function()
              q.cardQuestComplete=true
              q.cardHeroEndingStarted=nil

              -- Chasing the scalpers out is the last authored beat of the
              -- Celadon prequel. That makes it the point where the story
              -- finally catches up with the LOG 568 flash-forward the player
              -- was shown before they understood any of it, so the ending
              -- rolls directly out of this scene rather than waiting for a
              -- Mansion replay. `shouldAutoPlay` keeps it to exactly once.
              local function finishCardHero()
                ensureCeladonScalperLine()
                restorePlayerInput(game,ow)
                if not Finale then return end
                Finale.markPrequelComplete(game)
                if Finale.shouldAutoPlay(game) then Finale.play(game) end
              end

              -- All three kids head toward the Department Store together.
              -- They are temporarily passable so their simultaneous paths do
              -- not serialize behind one another.
              local goals={{8,13},{9,13},{10,13}}
              local remaining=#kids
              if remaining==0 then
                finishCardHero()
                return
              end
              for i,kid in ipairs(kids) do
                kid.passable=true
                kid.stepFrames=12
                local goal=goals[i] or goals[#goals]
                walkActorTo(kid,goal[1],goal[2],function()
                  removeRuntimeActor(kid)
                  remaining=remaining-1
                  if remaining<=0 then finishCardHero() end
                end)
              end
            end,
            {speaker="GIRL",portrait={speaker="GIRL",expression="Normal"}})
        end,
        {speaker="YOUNGSTER",portrait={speaker="YOUNGSTER",expression="Normal"}})
    end

    local function beginGameCornerStory()
      cut.storyStarted=true

      -- The actual redemption counter is GAME_CORNER_PRIZE_ROOM. Its
      -- attendants are vanilla BG interactions rather than overworld sprites,
      -- so keep the counter staff off-screen just like the original game.
      ow:setMap("GAME_CORNER_PRIZE_ROOM",4,6,"up",{via="boot"})
      removePlayer()

      -- Enter just above the verified south doorway (warps at 4,7 / 5,7).
      cut.nerd=addActor("EPILOGUE_NERD","SPRITE_SUPER_NERD",4,6,"up")

      if ow.camera and cut.nerd then
        ow.camera:follow(cut.nerd.px,cut.nerd.py)
      end

      -- Start the event only after the building-style fade-in finishes.
      cut.storyStep=0
      cut.storyTimer=0
    end

    local function cafeScene()
      -- After collecting his prize, the Nerd stops at the Celadon café/diner.
      -- This replaces the old Department Store detour.
      ow:setMap("CELADON_DINER",4,6,"up",{via="boot"})
      removePlayer()

      local Collision=require("src.world.Collision")
      local function openNear(sx,sy)
        local function valid(x,y)
          return ow.map:inBounds(x,y)
            and ow.map:isWalkableCell(x,y)
            and not ow.map:warpAtCell(x,y)
            and not Collision.occupied(ow.entities,x,y,nil)
        end
        if valid(sx,sy) then return sx,sy end
        for r=1,10 do
          for dy=-r,r do
            for dx=-r,r do
              if math.abs(dx)==r or math.abs(dy)==r then
                local x,y=sx+dx,sy+dy
                if valid(x,y) then return x,y end
              end
            end
          end
        end
        return sx,sy
      end

      local nx,ny=openNear(4,6)
      cut.nerd=addActor("EPILOGUE_NERD","SPRITE_SUPER_NERD",nx,ny,"up")
      if ow.camera and cut.nerd then
        ow.camera:follow(cut.nerd.px,cut.nerd.py)
      end
      cut.storyStep=19
      cut.storyTimer=0
    end

    local function setCityCameraFocus(px,py)
      if not ow.camera then return end
      -- Keep the hidden player at the cinematic focus as well as moving the
      -- Camera object. Overworld rendering may re-center the camera from the
      -- player during its own draw path; mirroring the focus here prevents
      -- that native follow from cancelling the Celadon pan on screen.
      local p=ow.player
      if p and ow.playerHidden then
        p.px,p.py=px,py
        p.targetX,p.targetY=px,py
      end
      ow.camera:follow(px,py)
    end

    local function frameCityView(v)
      if not (ow.camera and v) then return end
      setCityCameraFocus(v[1]*16,v[2]*16)
    end

    local function panCityView(v,frames)
      if not (ow.camera and v) then return end
      -- Tween the camera's *focus point* rather than its raw x/y. Each frame
      -- goes back through Camera:follow(), matching the engine's own camera
      -- contract and making the sweep survive any native re-centering.
      local sx=ow.camera.x+(160/2-16)
      local sy=ow.camera.y+(144/2-8)
      cut.cameraPan={
        sx=sx,sy=sy,tx=v[1]*16,ty=v[2]*16,
        frame=0,frames=math.max(1,frames or 60),
      }
    end

    function cut:enter()
      if skipToCleanup then
        -- Hypno Scene 2.5 is a checkpoint jump, not a replay of Scene 2.
        -- Land at the exact state reached once the officer has removed the
        -- Super Nerd from the Game Corner and the dropped Coin Case remains.
        local q=pokopiaData(game)
        q.refundDemanded=true
        q.policeCalled=true
        q.superNerdArrested=true
        q.emptyCoinCaseDropped=true
        q.emptyCoinCaseFound=nil
        q.emptyCoinCaseX=9
        q.emptyCoinCaseY=14
        q.emptyCoinCaseDropAnnounced=true
        q.gameCornerAttendantCheckedIn=false

        ow:setMap("GAME_CORNER",9,15,"up",{via="boot"})

        -- The checkpoint must contain neither the arrested Nerd nor the escort
        -- officer, even if a developer jump is used over a dirty runtime.
        for i=#(ow.npcs or {}),1,-1 do
          local n=ow.npcs[i]
          local name=n and n.def and n.def.name
          if name=="EPILOGUE_NERD" or name=="GC_OFFICER" then
            removeRuntimeActor(n)
          end
        end
        self.nerd=nil
        self.officer=nil
        self.porygon=nil
        self.cameraSubject=nil

        restorePlayableDitto(nil,9,15,"up")
        self.postRefundGameplay=true
        ensureGameCornerCast()

        box("The SUPER NERD was\narrested and taken away.\f"
          .."He dropped his\nCOIN CASE.",
          function() restorePlayerInput(game,ow) end)
        return
      end

      -- Scene 2 begins directly on the Super Nerd in the Game Corner prize
      -- room. The former Celadon establishing pan is intentionally skipped.
      beginGameCornerStory()
    end

    ------------------------------------------------------------------------
    -- WOOPER introduction -- west Celadon / Route 16 return connection.
    --
    -- The event is keyed to the actual seamless map transition rather than a
    -- guessed coordinate. Ditto must first be on ROUTE_16, then cross back into
    -- CELADON_CITY. That makes the trigger stable even if the connection offset
    -- or camera padding changes in a later Gen1Recomp build.
    ------------------------------------------------------------------------
    local function beginWooperIntro()
      local q=pokopiaData(game)
      q.characters=q.characters or {}
      q.characters.WOOPER=q.characters.WOOPER or {streetCred=0}
      local ws=q.characters.WOOPER
      if ws.introComplete or cut.wooperIntroPlaying then return false end
      if not (ow and ow.map and ow.map.id=="CELADON_CITY" and ow.player) then
        return false
      end

      local p=ow.player
      local Collision=require("src.world.Collision")
      local Menu=require("src.ui.Menu")
      cut.wooperIntroPlaying=true
      ws.met=true

      -- Halt Ditto cleanly on the first Celadon tile after the connection.
      p.inputLocked=true
      p.frozen=true
      p.targetX,p.targetY=nil,nil
      p.moving=false
      p.progress=0
      p.px,p.py=p.cellX*16,p.cellY*16

      local function openCell(x,y)
        return ow.map:inBounds(x,y)
          and ow.map:isWalkableCell(x,y)
          and not ow.map:warpAtCell(x,y)
          and not Collision.occupied(ow.entities,x,y,nil)
      end

      -- Prefer a Wooper coming from deeper inside Celadon so the two are
      -- visibly travelling toward each other. Fall back vertically only if
      -- the connection lane has been obstructed by another runtime actor.
      local candidates={
        {dx=1,dy=0,wooperFace="left",dittoFace="right"},
        {dx=0,dy=-1,wooperFace="down",dittoFace="up"},
        {dx=0,dy=1,wooperFace="up",dittoFace="down"},
      }
      local chosen=nil
      for _,c in ipairs(candidates) do
        local meetX,meetY=p.cellX+c.dx,p.cellY+c.dy
        if openCell(meetX,meetY) then
          for dist=4,2,-1 do
            local sx,sy=p.cellX+c.dx*dist,p.cellY+c.dy*dist
            if openCell(sx,sy) then
              chosen={c=c,meetX=meetX,meetY=meetY,spawnX=sx,spawnY=sy}
              break
            end
          end
        end
        if chosen then break end
      end

      if not chosen then
        -- Extremely defensive fallback: use any free neighbouring tile. The
        -- dialogue still occurs instead of leaving Ditto permanently locked.
        for _,c in ipairs(candidates) do
          local x,y=p.cellX+c.dx,p.cellY+c.dy
          if openCell(x,y) then
            chosen={c=c,meetX=x,meetY=y,spawnX=x,spawnY=y}
            break
          end
        end
      end

      if not chosen then
        cut.wooperIntroPlaying=nil
        restorePlayerInput(game,ow)
        return false
      end

      local c=chosen.c
      local wooper=addActor("WOOPER",WOOPER,chosen.spawnX,chosen.spawnY,c.wooperFace)
      wooper.wanders=false
      wooper.frozen=false
      wooper.passable=false
      wooper.stepFrames=16
      p.facing=c.dittoFace

      local function wooperBox(text,done,expression)
        box(text,done,{
          speaker="WOOPER",
          portrait={speaker="WOOPER",expression=expression or "Normal"},
        })
      end

      local function choice(labels,onChoose)
        local rows={}
        for i,label in ipairs(labels) do
          rows[i]={label=label,onSelect=function() onChoose(i) end}
        end
        game.stack:push(Menu.new(game,rows,{
          tx=2,ty=9,tw=16,rowStep=2,cancelable=false,noWrap=true,
        }))
      end

      local function finishAndLeave()
        ws.introComplete=true
        cut.wooperIntroPlaying=nil
        wooper.frozen=false
        wooper.passable=true

        -- Wooper reverses course after the conversation and heads deeper into
        -- Celadon. This visibly carries him away from Ditto without asking an
        -- NPC to cross a player-only outdoor map connection.
        local exitX,exitY=wooper.cellX,wooper.cellY
        local dx,dy=c.dx,c.dy
        for dist=5,2,-1 do
          local x,y=p.cellX+dx*dist,p.cellY+dy*dist
          if ow.map:inBounds(x,y) and ow.map:isWalkableCell(x,y)
              and not ow.map:warpAtCell(x,y) then
            exitX,exitY=x,y
            break
          end
        end
        wooper.facing=(dx>0 and "right") or (dx<0 and "left")
          or (dy>0 and "down") or "up"
        walkNpcTo(ow,wooper,exitX,exitY,function()
          removeRuntimeActor(wooper)
          restorePlayerInput(game,ow)
        end,false)
      end

      local function friendshipBeat()
        wooperBox(
          "Anyway... let's be friends.\f"
          .."You seem all right, kid.\f"
          .."I'll see ya around.",
          finishAndLeave,"Happy")
      end

      local function rocketChoice()
        wooperBox(
          "Haven't I seen you\nhanging around with\nTEAM ROCKET?\f"
          .."I heard they're bad news.",
          function()
            choice({"DEFEND ROCKET","AGREE"},function(which)
              if which==2 then
                ws.rocketView="AGREE"
                ws.streetCred=(tonumber(ws.streetCred) or 0)+1
                wooperBox(
                  "Yeah. See? You got\nstreet sense.\f"
                  .."Those guys are trouble.\f"
                  .."I respect a POKeMON\nwho can read a room.",
                  friendshipBeat,"Inspired")
              else
                ws.rocketView="DEFEND"
                wooperBox(
                  "TEAM ROCKET is out\nfor the money.\f"
                  .."I'm out for the money\ntoo, but also survival.\f"
                  .."POKeMON like me eat\nscraps from trash cans\f"
                  .."while POKeMON like you\neat...\f"
                  .."What DO DITTOS eat?\f"
                  .."Whatever. Point is,\nsome of us hustle\nbecause we gotta.",
                  friendshipBeat,"Normal")
              end
            end)
          end,"Normal")
      end

      local function kiddingBeat()
        -- One silent Ditto reaction beat makes Wooper's sudden retreat from
        -- the argument land harder without inventing dialogue for Ditto.
        box("DITTO's expression\ndarkens...",function()
          wooperBox(
            "HA! I'm just kidding.\f"
            .."I thought it'd be funny.\f"
            .."Relax. I know how\nthis works.",
            rocketChoice,"Joyous")
        end,{speaker="DITTO",portrait={speaker="DITTO",expression="Angry"}})
      end

      local function firstChoice()
        choice({"APOLOGIZE","ARGUE"},function(which)
          if which==1 then
            ws.firstResponse="APOLOGIZE"
            wooperBox(
              "Yeah, well... good.\f"
              .."You should apologize!\f"
              .."You nearly flattened me.\f"
              .."You think 'sorry' just\nfixes everything?",
              kiddingBeat,"Shouting")
          else
            ws.firstResponse="ARGUE"
            wooperBox(
              "Oh, we're doing this?\f"
              .."YOU walked into ME, bub!\f"
              .."What, you got a\nproblem with Wooper?",
              kiddingBeat,"Angry")
          end
        end)
      end

      local function collideDialogue()
        p.facing=c.dittoFace
        wooper.facing=c.wooperFace
        wooper.frozen=true
        wooperBox("Watch where you're\nwalking, bub!",firstChoice,"Shouting")
      end

      if wooper.cellX==chosen.meetX and wooper.cellY==chosen.meetY then
        collideDialogue()
      else
        walkNpcTo(ow,wooper,chosen.meetX,chosen.meetY,function(ok)
          if not ok then
            cut.wooperIntroPlaying=nil
            removeRuntimeActor(wooper)
            restorePlayerInput(game,ow)
            return
          end
          collideDialogue()
        end,true)
      end
      return true
    end

    function cut:update(dt)
      -- Fleeing scalpers use a visual-only dialogue overlay on the existing
      -- overworld state. A tiny reaction delay keeps the panic beat from
      -- landing on the exact same frame as every strike.
      if self.fleeBark then
        if (self.fleeBark.delay or 0)>0 then
          self.fleeBark.delay=self.fleeBark.delay-1
        else
          self.fleeBark.frames=self.fleeBark.frames-1
          if self.fleeBark.frames<=0 then self.fleeBark=nil end
        end
      end

      -- Finish queued post-movement beats before advancing the story machine.
      -- Multiple actors may arrive on the same frame, so process the whole
      -- queue and allow all formation callbacks to resolve together.
      local firedDeferred=false
      for i=#(self.deferred or {}),1,-1 do
        local d=self.deferred[i]
        d.frames=d.frames-1
        if d.frames<=0 then
          table.remove(self.deferred,i)
          if d.fn then d.fn() end
          firedDeferred=true
        end
      end
      if firedDeferred then return end

      if self.cameraPan and ow.camera then
        local pan=self.cameraPan
        pan.frame=pan.frame+1
        local u=math.min(1,pan.frame/pan.frames)
        local eased=u*u*(3-2*u)
        local px=pan.sx+(pan.tx-pan.sx)*eased
        local py=pan.sy+(pan.ty-pan.sy)*eased
        setCityCameraFocus(px,py)
        if u>=1 then self.cameraPan=nil end
      end

      if self.postRefundGameplay then
        local p=ow and ow.player
        local input=game and game.input
        local q=pokopiaData(game)

        -- Until Ditto checks in with the attendant after the police escort,
        -- intercept only the Game Corner -> Celadon exterior warp. This runs
        -- before OverworldController:update(), so Ditto never actually leaves.
        if p and input and ow and ow.map and ow.map.id=="GAME_CORNER"
            and not q.gameCornerAttendantCheckedIn then
          local dir=nil
          for _,d in ipairs({"up","down","left","right"}) do
            if input.isDown and input:isDown(d) then dir=d break end
          end

          if dir and not p.moving and not p.inputLocked then
            local Collision=require("src.world.Collision")
            local tx,ty=Collision.target(p.cellX,p.cellY,dir)
            local currentWarp=ow.map:warpAtCell(p.cellX,p.cellY)
            local targetWarp=ow.map:inBounds(tx,ty) and ow.map:warpAtCell(tx,ty) or nil

            local function isCeladonExit(w)
              local def=w and w.def
              if not def then return false end
              if def.destMap=="CELADON_CITY" then return true end
              -- Interior exits normally use LAST_MAP; Scene 2 explicitly
              -- remembers CELADON_CITY before this sequence begins.
              if def.destMap=="LAST_MAP" and ow.lastMap
                  and ow.lastMap.id=="CELADON_CITY" then
                return true
              end
              return false
            end

            if isCeladonExit(currentWarp) or isCeladonExit(targetWarp) then
              p.inputLocked=true
              local cast=ensureGameCornerCast()
              local attendant=cast.GC_ATTENDANT
              if attendant then
                if p.cellX<(attendant.cellX or 0) then attendant.facing="left"
                elseif p.cellX>(attendant.cellX or 0) then attendant.facing="right"
                elseif p.cellY<(attendant.cellY or 0) then attendant.facing="up"
                else attendant.facing="down" end
              end
              box("ATTENDANT: Hey, where are\nyou going?\f"
                .."Come see me real quick.",
                function()
                  restorePlayerInput(game,ow)
                end,{speaker="ATTENDANT"})
              return
            end
          end
        end

        -- The Department Store is sold out and locked. Intercept any
        -- Celadon exterior warp whose destination is one of its MART floors.
        if p and input and ow and ow.map and ow.map.id=="CELADON_CITY" then
          local dir=nil
          for _,d in ipairs({"up","down","left","right"}) do
            if input.isDown and input:isDown(d) then dir=d break end
          end
          if dir and not p.moving and not p.inputLocked then
            local Collision=require("src.world.Collision")
            local tx,ty=Collision.target(p.cellX,p.cellY,dir)
            local currentWarp=ow.map:warpAtCell(p.cellX,p.cellY)
            local targetWarp=ow.map:inBounds(tx,ty) and ow.map:warpAtCell(tx,ty) or nil

            local function deptStoreWarp(w)
              local dest=w and w.def and w.def.destMap
              return type(dest)=="string"
                and (dest:find("CELADON_MART",1,true)
                  or dest:find("DEPT_STORE",1,true))
            end

            if (deptStoreWarp(currentWarp) or deptStoreWarp(targetWarp))
                and not q.cardQuestComplete then
              p.inputLocked=true
              box("The doors are locked.\f"
                .."OUT OF STOCK.",
                function() restorePlayerInput(game,ow) end)
              return
            end
          end
        end

        -- Department Store counter interactions are overridden at the
        -- map-script layer above, before native mart menus can open.

        -- OLD PHOTO pickup: moved outdoors to the user-authored Celadon
        -- coordinate (48,16). Treat that cell as the photo location; pressing
        -- A while standing on it or facing it discovers the photo.
        if p and input and ow and ow.map and ow.map.id=="CELADON_CITY"
            and input.wasPressed and input:wasPressed("a")
            and not p.moving and not p.inputLocked then
          local dx,dy=0,0
          if p.facing=="up" then dy=-1
          elseif p.facing=="down" then dy=1
          elseif p.facing=="left" then dx=-1
          elseif p.facing=="right" then dx=1 end
          local fx,fy=p.cellX+dx,p.cellY+dy
          local onPhoto=(p.cellX==48 and p.cellY==16)
            or (fx==48 and fy==16)
          if onPhoto then
            p.inputLocked=true
            if not q.oldPhotoFound then
              q.oldPhotoFound=true
              require("src.core.Sound").play(game.data,"Get_Item1")
              box("Something old is tucked\namong the bushes...\f"
                .."DITTO found an\nOLD PHOTO!",
                function() restorePlayerInput(game,ow) end)
            else
              box("The spot where the\nOLD PHOTO was hidden\nis empty now.",
                function() restorePlayerInput(game,ow) end)
            end
            return
          end
        end

        -- Replace the stock Celadon girl line at (14,19). Handle this
        -- before the native overworld update so the original dialogue never opens.
        if p and input and ow and ow.map and ow.map.id=="CELADON_CITY"
            and input.wasPressed and input:wasPressed("a")
            and not p.moving and not p.inputLocked then
          local dx,dy=0,0
          if p.facing=="up" then dy=-1
          elseif p.facing=="down" then dy=1
          elseif p.facing=="left" then dx=-1
          elseif p.facing=="right" then dx=1 end
          if not q.cardQuestComplete
              and p.cellX+dx==14 and p.cellY+dy==19 then
            p.inputLocked=true
            box("TCG scalpers are bad\nfor our city's image.\f"
              .."They camp outside the\nDEPT. STORE\f"
              .."and buy everything\nbefore anyone else can.",
              function() restorePlayerInput(game,ow) end,
              {speaker="GIRL",portrait={speaker="GIRL",expression="Normal"}})
            return
          end
        end

        -- Repurpose Celadon's real Department Store and Game Corner signs
        -- as visible card-craze worldbuilding instead of adding floating props.
        if p and input and ow and ow.map and ow.map.id=="CELADON_CITY"
            and input.wasPressed and input:wasPressed("a")
            and not p.moving and not p.inputLocked then
          local dx,dy=0,0
          if p.facing=="up" then dy=-1
          elseif p.facing=="down" then dy=1
          elseif p.facing=="left" then dx=-1
          elseif p.facing=="right" then dx=1 end
          local fx,fy=p.cellX+dx,p.cellY+dy

          if fx==12 and fy==13 then
            p.inputLocked=true
            local gone=defeatedScalperCount(q)
            local signText
            if q.cardQuestComplete then
              signText="CELADON DEPT. STORE\f"
                .."TCG PACKS - 2F!\f"
                .."COLOSSEUM / EVOLUTION\nMYSTERY / LABORATORY"
            elseif gone>=4 then
              signText="CELADON DEPT. STORE\f"
                .."TCG RESTOCK TODAY!\f"
                .."NOTICE: Purchase\nlimits under review."
            else
              signText="CELADON DEPT. STORE\f"
                .."TCG RESTOCK TODAY!\f"
                .."COLOSSEUM / EVOLUTION\nMYSTERY / LABORATORY"
            end
            box(signText,function() restorePlayerInput(game,ow) end)
            return
          elseif fx==27 and fy==21 then
            p.inputLocked=true
            box("ROCKET GAME CORNER\f"
              .."TRADE COINS FOR PRIZES!\f"
              .."Rumor says today's\nplayers are unusually\nlucky.",
              function() restorePlayerInput(game,ow) end)
            return
          end
        end

        -- The three kids live on 2F after the quest and compare pulls.
        if p and input and ow and ow.map and ow.map.id=="CELADON_MART_2F"
            and q.cardQuestComplete
            and input.wasPressed and input:wasPressed("a")
            and not p.moving and not p.inputLocked then
          local dx,dy=0,0
          if p.facing=="up" then dy=-1
          elseif p.facing=="down" then dy=1
          elseif p.facing=="left" then dx=-1
          elseif p.facing=="right" then dx=1 end
          local tx,ty=p.cellX+dx,p.cellY+dy
          local target=nil
          for _,npc in ipairs(ow.npcs or {}) do
            local n=npc and npc.def and npc.def.name or ""
            if n:match("^CEL_2F_CARD_KID_")
                and npc.cellX==tx and npc.cellY==ty then
              target=npc
              break
            end
          end
          if target then
            p.inputLocked=true
            local n=target.def and target.def.name or ""
            local text,speaker
            if n=="CEL_2F_CARD_KID_06" then
              text="YOUNGSTER: I opened\nCOLOSSEUM!\f"
                .."Look at this pull!\f"
                .."We're comparing all\nfour sets now."
              speaker="YOUNGSTER"
            elseif n=="CEL_2F_CARD_KID_07" then
              text="YOUNGSTER: My EVOLUTION\npack was awesome!\f"
                .."I want to try\nLABORATORY next."
              speaker="YOUNGSTER"
            else
              text="GIRL: I got the card\nI wanted from MYSTERY!\f"
                .."We're trading doubles\nwith each other."
              speaker="GIRL"
            end
            box(text,function() restorePlayerInput(game,ow) end,{
              speaker=speaker,portrait={speaker=speaker,expression="Normal"}})
            return
          end
        end

        local mapBeforeNativeUpdate=ow and ow.map and ow.map.id or nil
        if ow and ow.update then ow:update(dt) end

        -- First Wooper encounter: only the real Route 16 -> Celadon outdoor
        -- connection can fire it. Trigger immediately after the map handoff so
        -- Ditto visibly pauses on the city side before ordinary input resumes.
        if mapBeforeNativeUpdate=="ROUTE_16"
            and ow and ow.map and ow.map.id=="CELADON_CITY" then
          local wq=pokopiaData(game)
          local wstate=wq.characters and wq.characters.WOOPER
          if not (wstate and wstate.introComplete) and beginWooperIntro() then
            return
          end
        end

        p=ow and ow.player
        input=game and game.input
        local cast=ensureGameCornerCast()
        local celadonCast=ensureCeladonScalperLine()
        local chiefFamily=ensureChiefHouseFamily()

        if ow.map and ow.map.id=="CELADON_CHIEF_HOUSE"
            and q.grandsonInHouse and not q.oldPhotoDadRewardClaimed then
          q.oldPhotoDadRewardClaimed=true
          game.save.coins=math.min(9999,(game.save.coins or 0)+500)
          require("src.core.Sound").play(game.data,"Get_Item1")
          if p then p.inputLocked=true end
          local dad=chiefFamily and chiefFamily.CHIEF_HOUSE_DAD
          if dad then dad.facing="right" end
          box("DAD: That old photo...\f"
            .."When the house burned\ndown, all of our old\nfamily photos went\nwith it.\f"
            .."I thought we'd never\nsee Grandma and Grandpa\nlike that again.\f"
            .."Thank you for bringing\na piece of our family\nback to us.\f"
            .."Please, take these\n500 COINS.",
            function() restorePlayerInput(game,ow) end,
            {speaker="DAD",portrait={speaker="DAD",expression="Normal"}})
          return
        end

        if self.postRefundGameplay and ow.map and ow.map.id=="CELADON_DINER" then ensureCafeGirl() end
        if self.postRefundGameplay and handleCafeInteraction() then return end
        if self.postRefundGameplay and updateCafeDelivery(dt) then return end

        if q.cardHeroPending and not q.cardHeroEndingStarted
            and not q.cardQuestComplete and ow.map.id=="CELADON_CITY" then
          startCardHeroEnding()
          return
        end

        if p and input and ow.map and ow.map.id=="GAME_CORNER"
            and input.wasPressed and input:wasPressed("a") then
          local dx,dy=0,0
          if p.facing=="up" then dy=-1
          elseif p.facing=="down" then dy=1
          elseif p.facing=="left" then dx=-1
          elseif p.facing=="right" then dx=1 end

          local target=nil
          local tx,ty=p.cellX+dx,p.cellY+dy
          for _,npc in pairs(cast) do
            local npcName=npc and npc.def and npc.def.name or ""
            local adjacent=npc and npc.cellX==tx and npc.cellY==ty
            -- The Game Corner counter occupies the cell between Ditto and the
            -- attendant. Match Gen I counter service by allowing A to reach
            -- the clerk two cells north while Ditto faces up.
            local acrossCounter=npcName=="GC_ATTENDANT"
              and p.facing=="up"
              and npc.cellX==p.cellX and npc.cellY==p.cellY-2
            if adjacent or acrossCounter then
              target=npc
              break
            end
          end

          if target then
            p.inputLocked=true
            local targetName=target.def and target.def.name or ""
            if targetName=="GC_EMPTY_COIN_CASE" then
              q.emptyCoinCaseFound=true
              q.emptyCoinCaseDropped=nil
              removeRuntimeActor(target)
              game.save.inventory=game.save.inventory or {}
              game.save.inventory.COIN_CASE=math.max(1,game.save.inventory.COIN_CASE or 0)
              if game.save.coins==nil then game.save.coins=0 end
              box("DITTO picked up the\nCOIN CASE!\f"
                .."There are no COINS\ninside.",
                function() restorePlayerInput(game,ow) end)
              return
            end
            if p.cellX<(target.cellX or 0) then target.facing="left"
            elseif p.cellX>(target.cellX or 0) then target.facing="right"
            elseif p.cellY<(target.cellY or 0) then target.facing="up"
            else target.facing="down" end

            local name=target.def and target.def.name or ""
            local text,speaker,portrait
            if name=="GC_GIOVANNI_THEORY" then
              speaker="OLD TIMER"
              portrait={speaker="OLD TIMER",expression="Normal"}
              text="You know...\f"
                .."TEAM ROCKET was always\npretty nice to us here.\f"
                .."Even back in the old\ndays.\f"
                .."Makes you wonder if\nthey were really bad,\f"
                .."or just misunderstood.\f"
                .."Maybe all those stories\nwe heard were lies--\f"
                .."a SILPH CO. smear\ncampaign against\f"
                .."GIOVANNI, the VIRIDIAN\nCITY GYM LEADER.\f"
                .."See, I figure SILPH and\nthe POKeMON LEAGUE\f"
                .."wanted him replaced\nbecause he opposed\f"
                .."corporate sponsorships\nfor GYMS.\f"
                .."Like those giant sponsor\ndeals you hear about\f"
                .."over in the GALAR\nregion.\f"
                .."SILPH had a lot of money\nriding on that idea.\f"
                .."They were developing\nthe MASTER BALL, too.\f"
                .."More POKe BALLS sold\nmeans more POKeMON caught.\f"
                .."More POKeMON caught means\nmore GYM challengers.\f"
                .."More GYM battles means\nmore money flowing\f"
                .."through the POKeMON\nLEAGUE.\f"
                .."But GIOVANNI knew there\nwas another side to it.\f"
                .."Powerful POKeMON in the\nhands of trainers\f"
                .."who couldn't control them\ncould be dangerous\f"
                .."for everybody.\f"
                .."Especially after what\nhappened on CINNABAR.\f"
                .."So maybe he pushed back\nagainst SILPH and\f"
                .."the LEAGUE, and stopped\na corporate takeover\f"
                .."of the KANTO POKeMON\nLEAGUE.\f"
                .."...Anyway.\f"
                .."That's just my head canon.\f"
                .."May not have happened\nthat way at all."
            elseif name=="GC_NEAR_WIN" then
              speaker="GAMBLER"
              if q.superNerdArrested then
                text="Wait... you're that\nDITTO from earlier!\f"
                  .."After what happened,\nI'm keeping my COINS\nwhere I can see them."
              else
                text="I was ONE symbol away!\fOne more spin and\nI've got it. I know it."
              end
            elseif name=="GC_BROKE" then
              speaker="GAMBLER"; text="I came in with 3000\nPOKeDOLLARS.\fI now have enough\nfor bus fare. Maybe."
            elseif name=="GC_ONE_MORE" then
              speaker="PLAYER"; text="I keep saying\n'one more game.'\fI've been saying that\nfor two hours."
            elseif name=="GC_BAD_LUCK" then
              speaker="YOUNGSTER"; text="These slots are\ndefinitely rigged!\f...I'm still going to\ntry this one again."
            elseif name=="GC_STREAK" then
              speaker="GENTLEMAN"; text="I won twice in a row\nearlier.\fThat was apparently\nall my luck for today."
            elseif name=="GC_ALMOST_JACKPOT" then
              speaker="GAMBLER"; text="Three sevens.\fI needed THREE SEVENS.\fThe last reel stopped\none notch too soon!"
            elseif name=="GC_RENT_MONEY" then
              speaker="PLAYER"; text="I told myself I'd\nonly spend 500.\fThen I spent another\n500 trying to win it back."
            elseif name=="GC_LUCKY_MACHINE" then
              speaker="YOUNGSTER"
              if q.cardQuestComplete then
                text="Hey, DITTO!\f"
                  .."People are talking\nabout you all over\nCELADON now!"
              else
                text="This machine is lucky.\fIt hasn't paid me once,\nso it's DUE."
              end
            elseif name=="GC_ATTENDANT" then
              speaker="ATTENDANT"
              if not q.gameCornerAttendantCheckedIn then
                text="Thanks for coming over.\f"
                  .."I just wanted to make\nsure you're okay.\f"
                  .."You can head out now.\f"
                  .."Come back and I'll show\nyou our new POKeMON\nCARD counter!"
              else
                restorePlayerInput(game,ow)
                TCGServices.counterTalk(game,ow,target,function() restorePlayerInput(game,ow) end)
                return
              end
            end

            if text then
              box(text,function()
                if name=="GC_ATTENDANT" then
                  q.gameCornerAttendantCheckedIn=true
                end
                restorePlayerInput(game,ow)
              end,{
                speaker=speaker,portrait=portrait
              })
            else
              restorePlayerInput(game,ow)
            end
            return
          end
        end
        if p and input and ow.map and ow.map.id=="CELADON_CITY"
            and input.wasPressed and input:wasPressed("a") then
          local dx,dy=0,0
          if p.facing=="up" then dy=-1
          elseif p.facing=="down" then dy=1
          elseif p.facing=="left" then dx=-1
          elseif p.facing=="right" then dx=1 end

          local target=nil
          for _,npc in pairs(celadonCast) do
            if npc and npc.cellX==p.cellX+dx and npc.cellY==p.cellY+dy then
              target=npc
              break
            end
          end

          if target then
            p.inputLocked=true
            local name=target.def and target.def.name or ""
            if name=="CEL_DRUNK_OFFICER" then
              target.facing="left"
            elseif p.cellX<(target.cellX or 0) then target.facing="left"
            elseif p.cellX>(target.cellX or 0) then target.facing="right"
            elseif p.cellY<(target.cellY or 0) then target.facing="up"
            else target.facing="down" end

            if name=="CEL_CARD_COLLECTOR" then
              box("SUPER NERD: I'm trying\nto trade for the last\ncard in my set.\fOpening packs is fun,\nbut trading's cheaper.",
                function() restorePlayerInput(game,ow) end,{speaker="SUPER NERD",portrait={speaker="SUPER NERD",expression="Normal"}})
              return
            elseif name=="CEL_SLOT_BUDGET" then
              box("GAMBLER: I was going to\nbuy a booster box.\fThen the slots ate my\ncard budget.",
                function() restorePlayerInput(game,ow) end,{speaker="GAMBLER",portrait={speaker="GAMBLER",expression="Normal"}})
              return
            elseif name=="CEL_KEY_FAN_A" then
              box("BEAUTY: That's the\nKEY TO THE CITY!\fYou're the DITTO the\nkids were cheering for!",
                function() restorePlayerInput(game,ow) end,{speaker="BEAUTY",portrait={speaker="BEAUTY",expression="Normal"}})
              return
            elseif name=="CEL_KEY_FAN_B" then
              box("GENTLEMAN: A KEY TO\nCELADON isn't handed\nout every day.\fYou must have made quite\nan impression.",
                function() restorePlayerInput(game,ow) end,{speaker="GENTLEMAN",portrait={speaker="GENTLEMAN",expression="Normal"}})
              return
            elseif name=="CEL_KEY_FAN_C" then
              box("YOUNGSTER: Whoa!\fYou're the DITTO with\nthe city key!\fThat's so cool!",
                function() restorePlayerInput(game,ow) end,{speaker="YOUNGSTER",portrait={speaker="YOUNGSTER",expression="Normal"}})
              return
            elseif name=="CEL_TCG_CHAT_A" then
              local text
              if q.cardQuestComplete then
                text="BEAUTY: They finally\nput purchase limits on\nthe new set.\f"
                  .."About time."
              else
                text="BEAUTY: I heard people\nstarted lining up\nyesterday."
              end
              box(text,function() restorePlayerInput(game,ow) end,
                {speaker="BEAUTY",portrait={speaker="BEAUTY",expression="Normal"}})
              return
            elseif name=="CEL_TCG_CHAT_B" then
              local text
              if q.cardQuestComplete then
                text="SUPER NERD: Good.\f"
                  .."Maybe collectors can\nactually buy cards now."
              else
                text="SUPER NERD: If they\nclear the shelves again,\nI'm going home."
              end
              box(text,function() restorePlayerInput(game,ow) end,
                {speaker="SUPER NERD",portrait={speaker="SUPER NERD",expression="Normal"}})
              return
            elseif name=="CEL_STORE_GREETER" then
              local gone=defeatedScalperCount(q)
              local text
              if q.cardQuestComplete then
                text="SALESMAN: The crowd's\nfinally under control.\f"
                  .."We're enforcing one\ncase per customer."
              elseif gone>=4 then
                text="SALESMAN: We're watching\nthe line.\f"
                  .."Management is discussing\npurchase limits."
              else
                text="SALESMAN: Big release\ntoday.\f"
                  .."Please keep the entrance\nclear."
              end
              box(text,function() restorePlayerInput(game,ow) end,
                {speaker="SALESMAN",portrait={speaker="GENTLEMAN",expression="Normal"}})
              return
            elseif name=="CEL_POST_SHOPPER_A" then
              box("The sidewalk feels\nnormal again.",
                function() restorePlayerInput(game,ow) end,
                {speaker="BEAUTY",portrait={speaker="BEAUTY",expression="Normal"}})
              return
            elseif name=="CEL_POST_SHOPPER_B" then
              box("I can actually get\nto the DEPT. STORE\nwithout a maze now.",
                function() restorePlayerInput(game,ow) end,
                {speaker="GENTLEMAN",portrait={speaker="GENTLEMAN",expression="Normal"}})
              return
            elseif name=="CEL_POST_SHOPPER_C" then
              box("The kids got their\npacks!\fEverybody's comparing\npulls over there.",
                function() restorePlayerInput(game,ow) end,
                {speaker="YOUNGSTER",portrait={speaker="YOUNGSTER",expression="Normal"}})
              return
            elseif name=="CEL_POST_SHOPPER_D" then
              box("GIRL: It feels like\nCELADON again.\f"
                .."You can actually walk\npast the store now.",
                function() restorePlayerInput(game,ow) end,
                {speaker="GIRL",portrait={speaker="GIRL",expression="Normal"}})
              return
            elseif name=="CEL_HITMONLEE" or name=="CEL_HITMONCHAN" then
              local who=(name=="CEL_HITMONLEE") and "HITMONLEE" or "HITMONCHAN"
              local gone=defeatedScalperCount(q)
              local text
              if q.cardQuestComplete then
                text=(who=="HITMONLEE")
                  and "Your technique's\nlooking sharp, DITTO!"
                  or "You really made that\nmove your own!"
              elseif gone>=3 then
                text=(who=="HITMONLEE")
                  and "You're getting faster.\fKeep your balance."
                  or "Nice timing, DITTO!\fYou're reading them\nbetter now."
              end
              if text then
                box(text,function() restorePlayerInput(game,ow) end,
                  {speaker=who,portrait={speaker=who,expression="Normal"}})
                return
              end
            elseif name=="CEL_SLOWBRO" then
              local gone=defeatedScalperCount(q)
              local text=(q.cardQuestComplete and "SLOWBRO: ...Bro.")
                or ((gone>=4) and "SLOWBRO: Sloooow...\f...Bro?" or "SLOWBRO: Sloooow...")
              box(text,function() restorePlayerInput(game,ow) end,
                {speaker="SLOWBRO",portrait={speaker="SLOWBRO",expression="Normal"}})
              return
            end

            local kidIdx=tonumber(name:match("^CEL_CARD_KID_(%d+)$"))
            if kidIdx and CARD_KIDS[kidIdx] then
              local kid=CARD_KIDS[kidIdx]
              local speaker=(kid[3]=="SPRITE_GIRL") and "GIRL" or "YOUNGSTER"
              local kidText=kid[4]
              local gone=defeatedScalperCount(q)
              local progress=KID_PROGRESS_LINES[kidIdx]
              if progress and gone>=4 then kidText=progress.near
              elseif progress and gone>=2 then kidText=progress.hopeful end
              box(kidText,
                function() restorePlayerInput(game,ow) end,
                {speaker=speaker,
                 portrait={speaker=speaker,expression="Normal"}})
              return
            end

            local idx=tonumber(name:match("^CEL_SCALPER_(%d+)$"))
            if idx and idx<CARD_KID_FIRST and SCALPER_LINE[idx] then
              local hitmonForm=(q.currentForm=="HITMONLEE" or q.currentForm=="HITMONCHAN")

              if hitmonForm and q.hitmonLearnedChoice==q.currentForm then
                local cutoutSpeaker=scalperCutoutSpeaker(SCALPER_LINE[idx][3])

                local function turnNearbyKidsToward(actor)
                  if not actor then return end
                  for _,kidNpc in ipairs(ow.npcs or {}) do
                    local kidName=kidNpc and kidNpc.def and kidNpc.def.name or ""
                    if kidName:match("^CEL_CARD_KID_") then
                      local dx=(actor.cellX or 0)-(kidNpc.cellX or 0)
                      local dy=(actor.cellY or 0)-(kidNpc.cellY or 0)
                      if math.abs(dx)+math.abs(dy)<=8 then
                        if math.abs(dx)>math.abs(dy) then
                          kidNpc.facing=(dx<0) and "left" or "right"
                        else
                          kidNpc.facing=(dy<0) and "up" or "down"
                        end
                      end
                    end
                  end
                end

                local lineGapX,lineGapY=target.cellX,target.cellY

                local function advanceRemainingQueue(done)
                  -- Compact every surviving queue member at once. All movers
                  -- are temporarily passable so one occupied destination does
                  -- not serialize the line into one-by-one motion.
                  local members={}
                  for _,npc in ipairs(ow.npcs or {}) do
                    local n=npc and npc.def and npc.def.name or ""
                    local si=tonumber(n:match("^CEL_SCALPER_(%d+)$"))
                    local ki=tonumber(n:match("^CEL_CARD_KID_(%d+)$"))
                    if si and si<CARD_KID_FIRST and not q.scalpersDefeated[si] then
                      members[#members+1]={npc=npc,order=si}
                    elseif ki and ki>=CARD_KID_FIRST then
                      members[#members+1]={npc=npc,order=ki}
                    end
                  end
                  table.sort(members,function(a,b) return a.order<b.order end)

                  local moving=0
                  local finished=false
                  local function oneDone(entry)
                    entry.npc.stepFrames=entry.oldFrames
                    entry.npc.passable=false
                    moving=moving-1
                    if moving<=0 and not finished then
                      finished=true
                      if done then done() end
                    end
                  end

                  for slot,entry in ipairs(members) do
                    local pos=SCALPER_LINE[slot]
                    local npc=entry.npc
                    if pos and (npc.cellX~=pos[1] or npc.cellY~=pos[2]) then
                      moving=moving+1
                      entry.oldFrames=npc.stepFrames or 32
                      npc.stepFrames=12
                      npc.passable=true
                      walkActorTo(npc,pos[1],pos[2],function()
                        oneDone(entry)
                      end)
                    end
                  end

                  if moving==0 and not finished then
                    finished=true
                    if done then done() end
                  end
                end

                local function finishScalperEscape()
                  cut.fleeBark=nil
                  q.scalpersDefeated=q.scalpersDefeated or {}
                  q.scalpersDefeated[idx]=true
                  removeRuntimeActor(target)

                  local allGone=true
                  for n=1,CARD_KID_FIRST-1 do
                    if not q.scalpersDefeated[n] then allGone=false break end
                  end
                  if allGone then
                    q.scalperLineCleared=true
                    advanceRemainingQueue(function()
                      if q.hitmonLearnedChoice=="HITMONLEE"
                          or q.hitmonLearnedChoice=="HITMONCHAN" then
                        q.cardHeroPending=true
                      end
                      restorePlayerInput(game,ow)
                    end)
                  else
                    advanceRemainingQueue(function()
                      restorePlayerInput(game,ow)
                    end)
                  end
                end

                local function fleeScalper()
                  local Collision=require("src.world.Collision")
                  -- Run at 4x normal NPC speed, but only for up to fifteen
                  -- collision-safe cells. Player control remains locked until
                  -- the short escape finishes.
                  target.stepFrames=8
                  turnNearbyKidsToward(target)

                  local dirs={
                    {0,-1,"up"},{0,1,"down"},{-1,0,"left"},{1,0,"right"},
                  }
                  local function key(x,y) return x..":"..y end
                  local sx,sy=target.cellX,target.cellY
                  local queue={{sx,sy,0}}
                  local qi=1
                  local prev={[key(sx,sy)]=false}
                  local bestX,bestY,bestDist=sx,sy,0
                  local bestAway=-1

                  -- Find the best reachable cell no more than fifteen steps away.
                  -- Prefer exactly fifteen cells; within the same distance, prefer
                  -- whichever endpoint is farther from Ditto.
                  while queue[qi] do
                    local cx,cy,dist=queue[qi][1],queue[qi][2],queue[qi][3]
                    qi=qi+1
                    local away=math.abs(cx-p.cellX)+math.abs(cy-p.cellY)
                    if dist>bestDist or (dist==bestDist and away>bestAway) then
                      bestX,bestY,bestDist,bestAway=cx,cy,dist,away
                    end

                    if dist<15 then
                      for _,d in ipairs(dirs) do
                        local nx,ny=cx+d[1],cy+d[2]
                        local k=key(nx,ny)
                        if prev[k]==nil
                            and ow.map:inBounds(nx,ny)
                            and ow.map:isWalkableCell(nx,ny)
                            and not ow.map:warpAtCell(nx,ny)
                            and not Collision.occupied(ow.entities,nx,ny,target) then
                          prev[k]={cx,cy,d[3]}
                          queue[#queue+1]={nx,ny,dist+1}
                        end
                      end
                    end
                  end

                  local route={}
                  local k=key(bestX,bestY)
                  while prev[k] do
                    local v=prev[k]
                    table.insert(route,1,v[3])
                    k=key(v[1],v[2])
                  end

                  local ri=1
                  local function nextStep()
                    local dir=route[ri]
                    if not dir then
                      finishScalperEscape()
                      return
                    end
                    ri=ri+1
                    ow:scriptMove(target,dir,1,nextStep,{collide=true})
                  end

                  if #route==0 then
                    -- A boxed-in scalper should not pop out of existence.
                    -- After Ditto has been shoved aside, try any newly opened
                    -- adjacent cell, preferring one that increases distance.
                    local fallback={}
                    for _,d in ipairs(dirs) do
                      local nx,ny=sx+d[1],sy+d[2]
                      if ow.map:inBounds(nx,ny)
                          and ow.map:isWalkableCell(nx,ny)
                          and not ow.map:warpAtCell(nx,ny)
                          and not Collision.occupied(ow.entities,nx,ny,target) then
                        fallback[#fallback+1]={
                          dir=d[3],
                          away=math.abs(nx-p.cellX)+math.abs(ny-p.cellY),
                        }
                      end
                    end
                    table.sort(fallback,function(a,b) return a.away>b.away end)
                    if fallback[1] then
                      route[1]=fallback[1].dir
                    end
                  end

                  nextStep()
                end

                local function nervousBackstepThen(cb)
                  local gone=defeatedScalperCount(q)
                  if gone<3 or love.math.random(1,3)~=1 then
                    cb()
                    return
                  end

                  local Collision=require("src.world.Collision")
                  local dirs={
                    {0,-1,"up"},{0,1,"down"},{-1,0,"left"},{1,0,"right"},
                  }
                  local options={}
                  for _,d in ipairs(dirs) do
                    local nx,ny=target.cellX+d[1],target.cellY+d[2]
                    if ow.map:inBounds(nx,ny)
                        and ow.map:isWalkableCell(nx,ny)
                        and not ow.map:warpAtCell(nx,ny)
                        and not Collision.occupied(ow.entities,nx,ny,target) then
                      options[#options+1]={
                        dir=d[3],
                        away=math.abs(nx-p.cellX)+math.abs(ny-p.cellY),
                      }
                    end
                  end
                  table.sort(options,function(a,b) return a.away>b.away end)
                  if options[1] then
                    target.stepFrames=12
                    ow:scriptMove(target,options[1].dir,1,function()
                      target.stepFrames=8
                      cb()
                    end,{collide=true})
                  else
                    cb()
                  end
                end

                local function runAway()
                  local panicLines={
                    "WAAAH!\nI'M OUTTA HERE!",
                    "I WANT\nMY MOMMY!",
                    "MY WIFE'S BOYFRIEND\nIS GONNA HEAR\nABOUT THIS!",
                    "IF I HAD A REAL JOB\nI WOULDN'T\nBE HERE!",
                    "CALM DOWN!\nIT'S JUST A\nCHILDREN'S GAME!",
                    "MY FEELINGS!\nMY PRECIOUS\nFEELINGS!",
                    "DON'T PUT THIS\nON THE\nINTERNET!",
                    "I'M SORRY!\n...FOR\nNOTHING!",
                    "THIS IS WHY\nI ONLY SELL\nONLINE!",
                    "I'M LEAVING\nA ONE-STAR\nREVIEW!",
                    "YOU CAN'T DO THIS!\nI HAVE\nFOLLOWERS!",
                    "I WAS JUST\nHOLDING THOSE\nFOR A FRIEND!",
                  }
                  cut.fleeBark={
                    text=panicLines[love.math.random(1,#panicLines)],
                    frames=72,
                    delay=love.math.random(0,8),
                    speaker="SCALPER",
                    portrait={speaker=cutoutSpeaker,expression="Normal"},
                  }

                  -- Shove Ditto one cell directly away when possible,
                  -- then calculate the scalper's capped escape route from the
                  -- newly opened space. Keep normal cutscene control lock until
                  -- the scalper finishes running and disappears.
                  local Collision=require("src.world.Collision")
                  local shoveDir={
                    up="down",down="up",left="right",right="left",
                  }
                  local away=shoveDir[p.facing] or "down"
                  local tx,ty=Collision.target(p.cellX,p.cellY,away)
                  local canShove=ow.map:inBounds(tx,ty)
                    and ow.map:isWalkableCell(tx,ty)
                    and not ow.map:warpAtCell(tx,ty)
                    and not Collision.occupied(ow.entities,tx,ty,p)

                  if canShove then
                    ow:scriptMove(p,away,1,fleeScalper,{collide=true})
                  else
                    fleeScalper()
                  end
                end

                -- No battle transition: A immediately uses the learned Hitmon
                -- technique in the overworld.
                nervousBackstepThen(function()
                  playScalperStrike(q.currentForm,runAway)
                end)
                return
              end

              local cutoutSpeaker=scalperCutoutSpeaker(SCALPER_LINE[idx][3])
              local gone=defeatedScalperCount(q)
              local idleText=SCALPER_LINE[idx][4]
              if gone==0 and idx==2 then
                idleText="SCALPER: The guy at\nthe front organized this.\f"
                  .."He says if we buy\ntogether, nobody else\ngets a chance."
              elseif gone==0 and idx==3 then
                idleText="SCALPER: Front guy\nsays stick to the plan.\f"
                  .."Buy first. Sort out\nwho gets what later."
              elseif gone>=3 then
                idleText="SCALPER: "
                  ..NERVOUS_SCALPER_LINES[((idx+gone-1)%#NERVOUS_SCALPER_LINES)+1]
              end
              box(idleText,
                function() restorePlayerInput(game,ow) end,
                {speaker="SCALPER",
                 portrait={speaker=cutoutSpeaker,expression="Normal"}})
              return
            elseif q.cardQuestComplete
                and (q.currentForm=="HITMONLEE" or q.currentForm=="HITMONCHAN")
                and q.hitmonLearnedChoice==q.currentForm
                and name~="CEL_HITMONLEE" and name~="CEL_HITMONCHAN" then
              local opponentName="TRAINER"
              if name=="CEL_DRUNK_OFFICER" then opponentName="OFFICER"
              elseif name:find("SCALPER",1,true) then opponentName="TRAINER"
              elseif target.def and target.def.sprite=="SPRITE_BEAUTY" then opponentName="BEAUTY"
              elseif target.def and target.def.sprite=="SPRITE_GENTLEMAN" then opponentName="GENTLEMAN"
              elseif target.def and target.def.sprite=="SPRITE_YOUNGSTER" then opponentName="YOUNGSTER"
              end
              local challenge={isOpaque=false,cursor=1,choices={"ROCK","PAPER","SCISSORS"}}
              function challenge:update()
                local input=game.input
                if input:wasPressed("left") then self.cursor=math.max(1,self.cursor-1)
                elseif input:wasPressed("right") then self.cursor=math.min(3,self.cursor+1)
                elseif input:wasPressed("b") then
                  game.stack:pop(); restorePlayerInput(game,ow)
                elseif input:wasPressed("a") then
                  local mine=self.choices[self.cursor]
                  local theirs=self.choices[love.math.random(1,3)]
                  local beats={ROCK="SCISSORS",PAPER="ROCK",SCISSORS="PAPER"}
                  game.stack:pop()
                  local playerWon=(mine~=theirs and beats[mine]==theirs)
                  local result=(mine==theirs) and "It's a tie!"
                    or (playerWon and q.currentForm.." wins!" or opponentName.." wins!")
                  if playerWon then require("src.core.Sound").play(game.data,"Get_Item1") end
                  box(q.currentForm..": "..mine.."!\n"
                    ..opponentName..": "..theirs.."!\f"..result,
                    function() restorePlayerInput(game,ow) end,
                    {speaker=opponentName,
                     portrait={speaker=opponentName,expression="Normal"}})
                end
              end
              function challenge:draw()
                local Font=require("src.render.Font")
                Font.drawBox(1,10,18,4)
                love.graphics.setColor(0,0,0,1)
                Font.draw("ROCK   PAPER  SCISSORS",12,96)
                local xs={8,56,104}
                local x=xs[self.cursor]
                love.graphics.polygon("fill",x,112,x,118,x+5,115)
                love.graphics.setColor(1,1,1,1)
              end
              box(opponentName..": Want a friendly\nROCK PAPER SCISSORS?",
                function() game.stack:push(challenge) end,
                {speaker=opponentName,
                 portrait={speaker=opponentName,expression="Normal"}})
              return
            elseif name=="CEL_GYM_GRANDSON" then
              if q.oldPhotoFound and not q.oldPhotoGivenToGrandson then
                box("YOUNGSTER: Hey!\f"
                  .."That's Grandma!\f"
                  .."That's the day\nGrandpa proposed!",
                  function()
                    showOldPhotoPortrait(function()
                      box("YOUNGSTER: Can I keep\nthis photo?\f"
                        .."I want to show\nmy parents!",
                        nil,{
                          speaker="YOUNGSTER",
                          portrait={speaker="YOUNGSTER",expression="Normal"},
                          choice=function(yes)
                            if not yes then
                              box("YOUNGSTER: Okay.\f"
                                .."But please show me\nagain sometime!",
                                function() restorePlayerInput(game,ow) end,
                                {speaker="YOUNGSTER",
                                 portrait={speaker="YOUNGSTER",expression="Normal"}})
                              return
                            end

                            q.oldPhotoGivenToGrandson=true
                            q.forms=q.forms or {}
                            local learnedNow=not q.forms.OLD_WOMAN
                            q.forms.OLD_WOMAN=true

                            local function sendHimHome()
                              box("YOUNGSTER: Thanks!\f"
                                .."I'm taking it\nhome right now!",
                                function()
                                  local live=nil
                                  for _,n in ipairs(ow.npcs or {}) do
                                    if n and n.def and n.def.name=="CEL_GYM_GRANDSON" then
                                      live=n; break
                                    end
                                  end
                                  if not live then
                                    -- Do not advance the quest invisibly. If the actor is
                                    -- unavailable, leave the state pending so the player can
                                    -- speak to him again and see the walk happen.
                                    restorePlayerInput(game,ow)
                                    return
                                  end
                                  live.frozen=false
                                  live.passable=true
                                  walkGrandsonIntoChiefHouse(ow,live,function(ok)
                                    if ok then q.grandsonInHouse=true end
                                    restorePlayerInput(game,ow)
                                  end)
                                end,
                                {speaker="YOUNGSTER",
                                 portrait={speaker="YOUNGSTER",expression="Normal"}})
                            end

                            if learnedNow then
                              require("src.core.Sound").play(game.data,"Get_Item2")
                              box("DITTO got an idea!\f"
                                .."DITTO learned to\ntransform into\nOLD WOMAN!",
                                sendHimHome,
                                {speaker="DITTO",
                                 portrait={speaker="DITTO",expression="Determined"}})
                            else
                              sendHimHome()
                            end
                          end
                        })
                    end)
                  end,
                  {speaker="YOUNGSTER",
                   portrait={speaker="YOUNGSTER",expression="Normal"}})
              elseif q.oldPhotoGivenToGrandson and not q.grandsonInHouse then
                box("YOUNGSTER: I'm taking it\nhome right now!",
                  function()
                    target.frozen=false
                    target.passable=true
                    walkGrandsonIntoChiefHouse(ow,target,function(ok)
                      if ok then q.grandsonInHouse=true end
                      restorePlayerInput(game,ow)
                    end)
                  end,
                  {speaker="YOUNGSTER",
                   portrait={speaker="YOUNGSTER",expression="Normal"}})
              else
                box("YOUNGSTER: My parents\nare going to love this!",
                  function() restorePlayerInput(game,ow) end,
                  {speaker="YOUNGSTER",
                   portrait={speaker="YOUNGSTER",expression="Normal"}})
              end
              return
            elseif name=="CEL_SLOWBRO" then
              box("SLOWBRO: Sloooow...",
                function() restorePlayerInput(game,ow) end,
                {speaker="SLOWBRO",portrait={speaker="SLOWBRO",expression="Normal"}})
              return
            elseif name=="CEL_HITMONLEE" or name=="CEL_HITMONCHAN" then
              local partner=(name=="CEL_HITMONLEE")
                and celadonCast.CEL_HITMONCHAN or celadonCast.CEL_HITMONLEE
              if target then
                target.facing=(name=="CEL_HITMONLEE") and "right" or "left"
              end
              if partner then
                partner.facing=(name=="CEL_HITMONLEE") and "left" or "right"
              end
              box("HITMONLEE and HITMONCHAN\nare trading blows!\f"
                .."Want to go a round?",
                nil,{
                  speaker="HITMONLEE",
                  portrait={speaker="HITMONLEE",expression="Normal"},
                  choice=function(yes)
                    if yes then
                      openHitmonRound(function()
                        restorePlayerInput(game,ow)
                      end)
                    else
                      restorePlayerInput(game,ow)
                    end
                  end
                })
              return
            elseif name=="CEL_DRUNK_OLD_MAN" then
              box("OLD MAN: Mmmph...\f"
                .."Road's comfortable.",
                function() restorePlayerInput(game,ow) end,
                {speaker="OLD MAN",portrait={speaker="OLD MAN",expression="Normal"}})
              return
            elseif name=="CEL_DRUNK_OFFICER" then
              box("OFFICER: Sir, get up.\f"
                .."You can't sleep in\nthe road.\f"
                .."Get up and leave.",
                function() restorePlayerInput(game,ow) end,
                {speaker="OFFICER",portrait={speaker="OFFICER",expression="Normal"}})
              return
            end
            restorePlayerInput(game,ow)
          end
        end
        if p and input and ow.map and ow.map.id=="CELADON_CHIEF_HOUSE"
            and input.wasPressed and input:wasPressed("a") then
          local dx,dy=0,0
          if p.facing=="up" then dy=-1
          elseif p.facing=="down" then dy=1
          elseif p.facing=="left" then dx=-1
          elseif p.facing=="right" then dx=1 end

          local target=nil
          for _,npc in pairs(chiefFamily) do
            if npc and npc.cellX==p.cellX+dx and npc.cellY==p.cellY+dy then
              target=npc
              break
            end
          end

          if target then
            p.inputLocked=true
            local name=target.def and target.def.name or ""
            if p.cellX<(target.cellX or 0) then target.facing="left"
            elseif p.cellX>(target.cellX or 0) then target.facing="right"
            elseif p.cellY<(target.cellY or 0) then target.facing="up"
            else target.facing="down" end

            if name=="CHIEF_HOUSE_MOM" then
              box("MOM: Welcome in.\f"
                .."It's not a big place,\nbut it's home.\f"
                .."Please excuse the toys.",
                function() restorePlayerInput(game,ow) end,
                {speaker="MOM",portrait={speaker="MOM",expression="Normal"}})
              return
            elseif name=="CHIEF_HOUSE_DAD" then
              box("DAD: Quiet evening,\nhuh?\f"
                .."We try to keep things\nsimple around here.",
                function() restorePlayerInput(game,ow) end,
                {speaker="DAD",portrait={speaker="DAD",expression="Normal"}})
              return
            elseif name=="CHIEF_HOUSE_GRANDSON" then
              box("YOUNGSTER: Look!\f"
                .."I told them about\nGrandma and Grandpa!",
                function() restorePlayerInput(game,ow) end,
                {speaker="YOUNGSTER",portrait={speaker="YOUNGSTER",expression="Normal"}})
              return
            elseif name=="CHIEF_HOUSE_KID" then
              box("KID: I made a POKeMON\nteam on paper!\f"
                .."Dad says I can get my\nfirst one someday.",
                function() restorePlayerInput(game,ow) end,
                {speaker="KID",portrait={speaker="KID",expression="Normal"}})
              return
            end
            restorePlayerInput(game,ow)
          end
        end

        return
      end

      -- This remains one continuous cutscene state. Advance the scripted
      -- Nerd and any other runtime actors through NPC:update()
      -- so targetX/targetY movement actually animates frame by frame.
      for _,npc in ipairs(ow.npcs or {}) do
        npc:update(ow.map,ow.entities)
      end

      -- Match OverworldController's native order: after entity updates,
      -- retire finished scripted tiles and immediately queue/start the next
      -- tile in the same route.
      if ow.updateScriptMoves then
        ow:updateScriptMoves()
      end

      self.timer=self.timer+1

      -- Celadon opening montage: a visible west-to-east camera move with
      -- short rests at each composition.  Do not advance while a tween is
      -- active; every shot must actually be seen before the next transition.
      if not self.storyStarted then
        if self.cityPanStage=="hold_first" and self.timer>=36 then
          self.timer=0
          self.cityPanStage="pan_second"
          panCityView(self.views[2],120)
        elseif self.cityPanStage=="pan_second" and not self.cameraPan then
          self.timer=0
          self.cityPanStage="hold_second"
        elseif self.cityPanStage=="hold_second" and self.timer>=42 then
          self.timer=0
          self.cityPanStage="pan_third"
          panCityView(self.views[3],132)
        elseif self.cityPanStage=="pan_third" and not self.cameraPan then
          self.timer=0
          self.cityPanStage="hold_third"
        elseif self.cityPanStage=="hold_third" and self.timer>=54 then
          self.cityPanStage="transition"
          switchSceneWithFade(beginGameCornerStory)
        end
        return
      end
      self.storyTimer=self.storyTimer+1

      -- During the Game Corner portion, frame the Super Nerd like the
      -- engine normally frames the player. This follows him as he moves
      -- from the machines to the prize counter.
      if ow.map and (ow.map.id=="GAME_CORNER_PRIZE_ROOM"
          or ow.map.id=="CELADON_DINER"
          or ow.map.id=="GAME_CORNER") and ow.camera then
        if self.cameraSubject=="ditto" and self.porygon then
          -- Hand the shot to Ditto before the Nerd starts walking away.
          -- Keep this lock for the entire exit so the camera never chases him.
          ow.camera:follow(self.porygon.px,self.porygon.py)
        elseif self.nerd then
          ow.camera:follow(self.nerd.px,self.nerd.py)
        elseif self.porygon then
          ow.camera:follow(self.porygon.px,self.porygon.py)
        end
      end

      if self.storyStep==0 and self.storyTimer>=18 then
        self.storyStep=-1
        -- Let the Nerd actually enter the room instead of materializing on the
        -- doorway and immediately talking. One clean step establishes motion,
        -- then a short look toward the counter sells his excitement.
        walkActorTo(self.nerd,4,5,function()
          self.nerd.facing="left"
          defer(10,function()
            self.nerd.facing="up"
            box("SUPER NERD: YES!\f"
              .."I finally did it!\f"
              .."9999 COINS!\f"
              .."That's enough for\nPORYGON!\f"
              .."I've been saving\nforever!",
              function() self.storyStep=1; self.storyTimer=0 end)
          end)
        end)

      elseif self.storyStep==1 and self.storyTimer>=30 then
        -- Native-style event beat: walk up to the counter first, then speak.
        self.storyStep=-1
        walkActorTo(self.nerd,4,3,function()
          self.nerd.facing="up"
          box("SUPER NERD: Excuse me!\f"
            .."9999 COINS!\f"
            .."One PORYGON, please!",
            function()
              box("PRIZE LADY: 9999 COINS?!\f"
                .."Wow!\f"
                .."We've only given out\none PORYGON before!\f"
                .."Just a moment.\f"
                .."I'll check the back.",
                function() self.storyStep=2; self.storyTimer=0 end)
            end)
        end)

      elseif self.storyStep==2 and self.storyTimer>=8 then
        -- The staff are BG events, so sell their off-screen conference through
        -- pauses and the Nerd reacting toward the adjacent counter.
        self.storyStep=-1
        self.nerd.facing="right"
        box("PRIZE LADY: (whisper)\f"
          .."Hey... We have a problem.\f"
          .."He wants a PORYGON.\f"
          .."That kid from PALLET\ngot the last one!",
          function() self.storyStep=3; self.storyTimer=0 end)

      elseif self.storyStep==3 and self.storyTimer>=6 then
        self.storyStep=-1
        self.nerd.facing="left"
        box("PRIZE WORKER: Oh...\f"
          .."Uh...\f"
          .."Here. Give him this.",
          function() self.storyStep=4; self.storyTimer=0 end)

      elseif self.storyStep==4 and self.storyTimer>=6 then
        self.storyStep=-1
        self.nerd.facing="right"
        box("PRIZE LADY: This?",
          function() self.storyStep=5; self.storyTimer=0 end)

      elseif self.storyStep==5 and self.storyTimer>=6 then
        self.storyStep=-1
        self.nerd.facing="left"
        box("PRIZE WORKER: Yeah...\f"
          .."He won't know.",
          function() self.storyStep=6; self.storyTimer=0 end)

      elseif self.storyStep==6 and self.storyTimer>=12 then
        -- Keep him planted at the counter. The old down/up pacing loop looked
        -- like a pathfinding correction rather than nervous anticipation.
        self.storyStep=7
        self.storyTimer=0
        self.nerd.facing="up"

      elseif self.storyStep==7 and self.storyTimer>=10 then
        self.storyStep=-1
        self.nerd.facing="up"
        box("PRIZE LADY: Sorry to keep\nyou waiting!\f"
          .."Here you are!\f"
          .."Your PORYGON!",
          function() self.storyStep=8; self.storyTimer=0 end)

      elseif self.storyStep==8 and self.storyTimer>=6 then
        self.storyStep=-1
        -- Brief reaction turn before the Nerd answers, like a Gen I event
        -- script separating an item handoff from the recipient's response.
        self.nerd.facing="down"
        box("SUPER NERD: Finally!\f"
          .."I really got one!",
          function() self.storyStep=9; self.storyTimer=0 end)

      elseif self.storyStep==9 and self.storyTimer>=6 then
        self.storyStep=-1
        self.nerd.facing="up"
        box("PRIZE LADY: Enjoy your\nprize!\f"
          .."No returns!\f"
          .."...Heh.",
          function() self.storyStep=10; self.storyTimer=0 end)

      elseif self.storyStep==10 and self.storyTimer>=10 then
        self.storyStep=-1
        -- Let the punchline hang, then visibly leave through the south side of
        -- the room before invoking the building-style map transition.
        self.nerd.facing="down"
        walkActorTo(self.nerd,4,6,function()
          self.nerd.facing="down"
          self.storyStep=11; self.storyTimer=0
        end)

      elseif self.storyStep==11 and self.storyTimer>=4 then
        self.storyStep=-1
        switchSceneWithFade(cafeScene)

      elseif self.storyStep==19 and self.storyTimer>=18 then
        self.storyStep=-1
        walkActorTo(self.nerd,7,5,function()
          box("SUPER NERD: I can't wait\nuntil I get home!\f"
            .."I have to see it now!\f"
            .."Come on out, PORYGON!",
            function()
              -- Pick a nearby clear cell for the prize reveal.
              local px,py=self.nerd.cellX,self.nerd.cellY-1
              if not ow.map:isWalkableCell(px,py)
                  or require("src.world.Collision").occupied(ow.entities,px,py,self.nerd) then
                px,py=self.nerd.cellX+1,self.nerd.cellY
              end
              self.porygon=addActor("EPILOGUE_PORYGON",PORYGON,px,py,"down")
              -- The prize is Ditto already disguised as Porygon, so its
              -- silhouette is Porygon from the instant it appears but its
              -- colors are unmistakably Ditto-purple.
              local SpriteRenderer=require("src.render.SpriteRenderer")
              local porygonDef=transformedSpriteDef(game,PORYGON)
              if porygonDef then
                local renderer=SpriteRenderer.new(porygonDef,"epilogue_porygon_disguise")
                local purple=bakeDittoPurpleImage(porygonDef.image)
                if purple then renderer.image=purple end
                self.porygon.sprite=renderer
                self.porygon.def.sprite=PORYGON
              end
              self.storyStep=20; self.storyTimer=0
            end)
        end)

      elseif self.storyStep==20 then
        -- Hold his attention on the prize instead of snapping through several
        -- facings. A single reaction pose reads much more naturally.
        if self.storyTimer==8 and self.porygon then
          local dx=(self.porygon.cellX or 0)-(self.nerd.cellX or 0)
          local dy=(self.porygon.cellY or 0)-(self.nerd.cellY or 0)
          if math.abs(dx)>math.abs(dy) then
            self.nerd.facing=dx<0 and "left" or "right"
          else
            self.nerd.facing=dy<0 and "up" or "down"
          end
        elseif self.storyTimer>=28 then
          self.storyStep=-1
          box("SUPER NERD: Whoa...\f"
            .."A real PORYGON!\f"
            .."9999 COINS...\f"
            .."Worth every one!",
            function() self.storyStep=21; self.storyTimer=0 end)
        end

      elseif self.storyStep==21 and self.storyTimer>=28 then
        self.storyStep=-1
        -- Give the hesitation its own page. As the question begins, the
        -- purple Porygon disguise visibly drops into Ditto with Transform.
        box("SUPER NERD: Uhh...",
          function()
            local SpriteRenderer=require("src.render.SpriteRenderer")
            local dittoDef=game.data.sprites[DITTO]
            if self.porygon and dittoDef then
              self.porygon.sprite=SpriteRenderer.new(dittoDef,"epilogue_revealed_ditto")
              self.porygon.def.sprite=DITTO
              self.porygon.def.name="EPILOGUE_DITTO"
            end
            require("src.core.Sound").playMove(game.data,{
              sound="Faint_Fall",pitch=0xff,tempo=0xff
            })
            -- Let the sprite change land before the next line without forcing
            -- a collision-ignoring recoil step.
            self.nerd.facing="up"
            defer(10,function()
              box("SUPER NERD: Is my PORYGON\nsick?",
                function() self.storyStep=22; self.storyTimer=0 end)
            end)
          end)

      elseif self.storyStep==22 and self.storyTimer>=16 then
        self.storyStep=-1
        box("SUPER NERD: ...\f"
          .."WHAT?!\f"
          .."A DITTO?!\f"
          .."You were pretending\nto be PORYGON?!\f"
          .."I paid 9999 COINS\nfor a DITTO?!",
          function()
            box("SUPER NERD: That's it!\f"
              .."I'm going back to\nthe GAME CORNER!\f"
              .."I'm getting a refund!",
              function()
                -- Ditto does not become his follower. The camera stays on the
                -- Nerd and Ditto is left behind while he returns to complain.
                self.cameraSubject="nerd"
                self.storyStep=23; self.storyTimer=0
              end)
          end)

      elseif self.storyStep==23 and self.storyTimer>=8 then
        self.storyStep=-1

        -- The Nerd storms toward the café exit. Revealed Ditto follows him out
        -- instead of being left behind or teleporting directly to the refund.
        local exitX,exitY=4,6
        if not ow.map:inBounds(exitX,exitY) or not ow.map:isWalkableCell(exitX,exitY) then
          exitX,exitY=self.nerd.cellX,self.nerd.cellY
        end

        walkActorTo(self.nerd,exitX,exitY,function()
          self.nerd.passable=true
          local ditto=self.porygon
          if not ditto then
            switchSceneWithFade(function() self.storyStep=29; self.storyTimer=0 end)
            return
          end
          local followX,followY=exitX,math.max(0,exitY-1)
          walkActorTo(ditto,followX,followY,function()
            switchSceneWithFade(function()
              ow:setMap("GAME_CORNER",9,15,"up",{via="boot"})
              removePlayer()

              local Collision=require("src.world.Collision")
              local function openNear(sx,sy)
                local function valid(x,y)
                  return ow.map:inBounds(x,y)
                    and ow.map:isWalkableCell(x,y)
                    and not ow.map:warpAtCell(x,y)
                    and not Collision.occupied(ow.entities,x,y,nil)
                end
                if valid(sx,sy) then return sx,sy end
                for r=1,12 do
                  for dy=-r,r do
                    for dx=-r,r do
                      if math.abs(dx)==r or math.abs(dy)==r then
                        local x,y=sx+dx,sy+dy
                        if valid(x,y) then return x,y end
                      end
                    end
                  end
                end
                return sx,sy
              end

              ensureGameCornerCast()
              local nx,ny=openNear(9,14)
              self.nerd=addActor("EPILOGUE_NERD","SPRITE_SUPER_NERD",nx,ny,"up")
              local dx,dy=openNear(nx,ny+1)
              self.porygon=addActor("EPILOGUE_DITTO",DITTO,dx,dy,"up")
              self.porygon.passable=true
              self.cameraSubject="nerd"
              if ow.camera then ow.camera:follow(self.nerd.px,self.nerd.py) end
              self.storyStep=30
              self.storyTimer=0
            end)
          end)
        end)

      elseif self.storyStep==30 and self.storyTimer>=8 then
        self.storyStep=-1
        local targetX,targetY=self.nerd.cellX,math.max(1,self.nerd.cellY-3)
        if not ow.map:isWalkableCell(targetX,targetY) then
          targetX,targetY=self.nerd.cellX,self.nerd.cellY
        end

        -- Ditto trails behind while the Nerd reaches the attendant.
        walkActorTo(self.nerd,targetX,targetY,function()
          local ditto=self.porygon
          local function demandRefund()
            self.nerd.facing="up"
            box("SUPER NERD: I want a refund!\f"
              .."That wasn't a PORYGON!\f"
              .."It was a DITTO!\f"
              .."Give me back my\n9999 COINS!",
              function()
                local q=pokopiaData(game)
                q.refundDemanded=true
                local cast=ensureGameCornerCast()
                local attendant=cast.GC_ATTENDANT
                if attendant then attendant.facing="down" end
                box("ATTENDANT: Sir, you need\nto leave.\f"
                  .."You aren't allowed\nback here.\f"
                  .."I'm calling the police.",
                  function()
                    local q=pokopiaData(game)
                    q.policeCalled=true
                    self.storyStep=31
                    self.storyTimer=0
                  end,{speaker="ATTENDANT"})
              end)
          end

          if ditto then
            local fx,fy=targetX,math.min(targetY+1,(ow.map.height or targetY+1))
            walkActorTo(ditto,fx,fy,demandRefund)
          else
            demandRefund()
          end
        end)

      elseif self.storyStep==31 and self.storyTimer>=24 then
        self.storyStep=-1

        -- Use the real Gen I guard sheet for the officer and explicitly preserve
        -- its walker metadata before NPC.new builds the SpriteRenderer. The
        -- guard sheet is a six-frame field walker; this keeps the step frames
        -- animating while the officer enters and escorts the Nerd.
        local officerSprite="SPRITE_GUARD"
        local officerDef=game.data.sprites and game.data.sprites[officerSprite]
        if not officerDef or (officerDef.frames or 0)<6 then
          officerSprite="SPRITE_ROCKET"
          officerDef=game.data.sprites and game.data.sprites[officerSprite]
        end
        if officerDef and (officerDef.frames or 0)>=6 then
          officerDef.walker=true
        end

        local Collision=require("src.world.Collision")
        local function openNear(sx,sy,ignore)
          local function valid(x,y)
            return ow.map:inBounds(x,y)
              and ow.map:isWalkableCell(x,y)
              and not ow.map:warpAtCell(x,y)
              and not Collision.occupied(ow.entities,x,y,ignore)
          end
          if valid(sx,sy) then return sx,sy end
          for r=1,12 do
            for dy=-r,r do
              for dx=-r,r do
                if math.abs(dx)==r or math.abs(dy)==r then
                  local x,y=sx+dx,sy+dy
                  if valid(x,y) then return x,y end
                end
              end
            end
          end
          return nil,nil
        end

        -- Enter from the same south doorway the Nerd will later leave through.
        -- The officer approaches one clean adjacent tile instead of searching
        -- the whole room for an arbitrary nearest position.
        local ox,oy=openNear(9,15,nil)
        self.officer=ox and addActor("GC_OFFICER",officerSprite,ox,oy,"up") or nil
        if self.officer then
          self.officer.stepFrames=32
          self.officer.wanders=false
          self.officer.passable=true
        end

        if not self.officer then
          self.storyStep=32
          self.storyTimer=0
        else
          local nerd=self.nerd
          local approachX,approachY=nil,nil
          if nerd then
            local candidates={
              {nerd.cellX+1,nerd.cellY},
              {nerd.cellX-1,nerd.cellY},
              {nerd.cellX,nerd.cellY+1},
              {nerd.cellX,nerd.cellY-1},
            }
            local best,bestRoute
            for _,c in ipairs(candidates) do
              if ow.map:inBounds(c[1],c[2])
                  and ow.map:isWalkableCell(c[1],c[2])
                  and not ow.map:warpAtCell(c[1],c[2]) then
                local r=routeNpcTo(ow,self.officer,c[1],c[2])
                if r and (not bestRoute or #r<#bestRoute) then
                  best,bestRoute=c,r
                end
              end
            end
            if best then approachX,approachY=best[1],best[2] end
          end

          local function officerTalk()
            local officer=self.officer
            local nerd=self.nerd
            if officer and nerd then
              officer.facing=(nerd.cellX<officer.cellX) and "left"
                or (nerd.cellX>officer.cellX) and "right"
                or (nerd.cellY<officer.cellY) and "up" or "down"
              nerd.facing=(officer.cellX<nerd.cellX) and "left"
                or (officer.cellX>nerd.cellX) and "right"
                or (officer.cellY<nerd.cellY) and "up" or "down"
            end
            box("OFFICER: That's enough.\f"
              .."The attendant says\nyou're trespassing.\f"
              .."You're coming outside.",
              function()
                self.storyStep=32
                self.storyTimer=0
              end,{speaker="OFFICER",portrait={speaker="OFFICER",expression="Normal"}})
          end

          if approachX then
            walkActorTo(self.officer,approachX,approachY,officerTalk)
          else
            officerTalk()
          end
        end

      elseif self.storyStep==32 and self.storyTimer>=8 then
        self.storyStep=-1
        local nerd=self.nerd
        local officer=self.officer

        -- One authoritative route owns the escort. The Nerd walks first; after
        -- each tile lands, the officer advances into the tile the Nerd just
        -- vacated. This produces a stable one-tile escort formation instead of
        -- two independent pathfinders crossing or overtaking each other.
        local function completeEscort()
          local ditto=self.porygon
          local px,py=9,15
          if ditto then px,py=ditto.cellX,ditto.cellY end

          local q=pokopiaData(game)
          if not q.emptyCoinCaseFound then
            q.emptyCoinCaseDropped=true
            q.emptyCoinCaseX=9
            q.emptyCoinCaseY=14
          end

          removeRuntimeActor(nerd)
          removeRuntimeActor(officer)
          q.superNerdArrested=true
          self.nerd=nil
          self.officer=nil
          self.cameraSubject=nil

          restorePlayableDitto(ditto,px,py,"up")
          self.porygon=nil
          q.gameCornerAttendantCheckedIn=false
          self.postRefundGameplay=true
          ensureGameCornerCast()
          if q.emptyCoinCaseDropped and not q.emptyCoinCaseDropAnnounced then
            q.emptyCoinCaseDropAnnounced=true
            box("The SUPER NERD dropped\nhis COIN CASE.",
              function() restorePlayerInput(game,ow) end)
          end
        end

        if not nerd then
          completeEscort()
        else
          nerd.passable=true
          if officer then
            officer.passable=true
            officer.wanders=false
            officer.stepFrames=32
          end

          local route=routeNpcTo(ow,nerd,9,15) or {}
          local ri=1

          -- Put the officer immediately behind the Nerd before the procession
          -- starts. "Behind" is chosen from the first route direction so the
          -- pair forms a straight line into the exit.
          local function desiredBehind()
            local first=route[1]
            if first=="down" then return nerd.cellX,nerd.cellY-1
            elseif first=="up" then return nerd.cellX,nerd.cellY+1
            elseif first=="left" then return nerd.cellX+1,nerd.cellY
            elseif first=="right" then return nerd.cellX-1,nerd.cellY end
            return nerd.cellX,nerd.cellY-1
          end

          local function runEscort()
            local dir=route[ri]
            if not dir then
              completeEscort()
              return
            end
            ri=ri+1

            local oldX,oldY=nerd.cellX,nerd.cellY
            ow:scriptMove(nerd,dir,1,function()
              if not officer then
                runEscort()
                return
              end

              -- The officer uses normal script movement whenever the previous
              -- Nerd cell is adjacent. If a corner or obstacle broke formation,
              -- repair it with the same route helper, then continue.
              local dx=oldX-officer.cellX
              local dy=oldY-officer.cellY
              local followDir=(dx==1 and dy==0 and "right")
                or (dx==-1 and dy==0 and "left")
                or (dy==1 and dx==0 and "down")
                or (dy==-1 and dx==0 and "up")

              if followDir then
                ow:scriptMove(officer,followDir,1,runEscort,{collide=false})
              else
                walkActorTo(officer,oldX,oldY,runEscort)
              end
            end,{collide=false})
          end

          if officer and #route>0 then
            local bx,by=desiredBehind()
            if ow.map:inBounds(bx,by) and ow.map:isWalkableCell(bx,by)
                and not ow.map:warpAtCell(bx,by) then
              walkActorTo(officer,bx,by,runEscort)
            else
              runEscort()
            end
          else
            runEscort()
          end
        end

      end
    end

    function cut:draw()
      local jobs=cafeJobsState()
      local order=jobs and jobs.currentOrder
      if self.postRefundGameplay and order and order.state=="active"
          and ow and ow.map and ow.map.id=="CELADON_CITY" then
        local Font=require("src.render.Font")
        love.graphics.push("all")
        love.graphics.setColor(1,1,1,1)
        Font.drawBox(0,0,20,5)
        love.graphics.setColor(0,0,0,1)
        Font.draw(cafeFoodHud(order),8,8)
        Font.draw(tcgMenuFit(order.customer.name.." - "..order.location.short,144),8,16)
        Font.draw("TIME "..cafeClock(order.timeRemaining),8,24)
        love.graphics.pop()
      end

      local bark=self.fleeBark
      if not bark or (bark.delay or 0)>0 then return end
      local Font=require("src.render.Font")
      local meta={
        speaker=bark.speaker,
        portrait=bark.portrait,
        box={boxTx=0,boxTy=11,boxTw=20,boxTh=7},
      }
      local ctx={ww=160,wh=144}

      -- Preserve the mod's normal human-dialogue presentation: trainer-class
      -- cutout behind the box and a SCALPER nameplate above it.
      drawTrainerSpeaker(game,meta,ctx)
      love.graphics.push("all")
      love.graphics.setColor(1,1,1,1)
      Font.drawBox(0,11,20,7)
      love.graphics.setColor(0,0,0,1)
      Font.draw(bark.text,8,104)
      love.graphics.pop()
      drawSpeakerMeta(game,meta,ctx)
    end

    game.stack:push(cut)

  end

  muchEarlier=function(game, skipToCleanup)
    -- This intertitle is the hard chronology reset. Nothing Ditto learned in
    -- the later Mansion sequence may leak backward into the earlier Celadon
    -- scene or into saves made from it.
    local q=pokopiaData(game)
    q.forms={}
    q.currentForm="DITTO"
    q.requestedForm=nil
    q.electrodeFormLearned=nil
    q.electrodeBikeFrameCounter=0
    q.electrodeBikeSpeed=0
    q.electrodeBikeTransition=nil
    q.electrodeBikeDirection=nil
    q.electrodeBikeCharge=0
    q.hitmonLearnedChoice=nil
    q.hitmonLearnedForm=nil
    q.hitmonPendingChoice=nil
    q.hitmonIdeaShown=nil
    q.scalpersDefeated=nil
    q.scalperLineCleared=nil
    q.cardHeroPending=nil
    q.cardHeroEndingStarted=nil
    q.cardQuestComplete=nil
    q.cardPackInventory=nil
    local ow=activeOverworld and activeOverworld(game) or nil
    if ow and ow.player then
      ow.player.pokopiaForm="DITTO"
      ow.player.pokopiaElectrodeAccelSteps=0
      ow.player.pokopiaElectrodeMomentumMap=nil
    end

    -- End the Mansion timeline before presenting the intertitle. This keeps
    -- the black "Much earlier..." card self-contained instead of layering it
    -- over a still-live Mansion overworld and then trying to tear that stack
    -- down during the Celadon load.
    while game.stack:top() do game.stack:pop() end

    local state={isOpaque=true,timer=0}
    function state:update()
      self.timer=self.timer+1
      if self.timer>=120 and not self.finished then
        self.finished=true

        -- Remove only this title card, then create Celadon immediately.
        -- There is no extra blank handoff state and no second stack wipe.
        game.stack:pop()
        startCeladonEnding(game, skipToCleanup)
      end
    end
    function state:draw()
      love.graphics.clear(0,0,0,1)
      love.graphics.setColor(1,1,1,1)
      love.graphics.printf("Much earlier...",0,66,160,"center")
    end
    game.stack:push(state)
  end

  ------------------------------------------------------------------------
  -- LOG 568 bookend finale.
  --
  -- The opening OakSpeech scene (`intro.oak_speech.build`, above) is a
  -- flash-forward. finale.lua is the payoff: it plays the departure, the
  -- liftoff, then reproduces the opening's exact presentation and exact
  -- lines before continuing the log past the point where the intro stopped.
  --
  -- Loaded with the same loadfile/love.filesystem pattern used for
  -- rocket_quests.lua and tcg_battle.lua. Constructed here because it needs
  -- the dialogue portrait helpers, the alarm control and the live overworld
  -- accessor, all of which are defined above this point.
  ------------------------------------------------------------------------
  do
    local finalePath=tostring(mod.path or "").."/finale.lua"
    local chunk,err=loadfile(finalePath)
    if not chunk and love.filesystem and love.filesystem.load then
      chunk,err=love.filesystem.load(finalePath)
    end
    assert(chunk,err)
    local FinaleModule=chunk()
    Finale=FinaleModule.new({
      data=pokopiaData,
      modPath=tostring(mod.path or ""),
      overworld=function(game) return activeOverworld and activeOverworld(game) or nil end,
      trainerImage=function(game,speaker) return trainerPortraitImage(game,speaker) end,
      trainerMaskShader=getTrainerMaskShader,
      stopAlarm=stopPokopiaAlarm,
    })
    Finale.module=FinaleModule
  end

  local function pcBoxTalk(game,ow,npc,done)
    local q=pokopiaData(game)
    if q.distractionDone and q.giovanniMeetingDone then
      showBox(game,"The PC is active.",done)
    else
      showBox(game,"The PC is inactive.",done)
    end
  end

  local function loganTalk(game,ow,npc,done)
    local q=pokopiaData(game)

    -- PIXIE's quest cannot begin until the PERSIAN distraction is complete
    -- and Giovanni has finished his post-scientist speech.
    if not (q.distractionDone and q.giovanniMeetingDone) then
      showBox(game,"The PC is inactive.",done)
      return
    end

    if q.currentForm=="PERSIAN" then
      showBox(game,
        "LOGAN: PERSIAN!\f"
        .."How many times have\nI told you?\f"
        .."Leave the lab POKeMON\nalone!\f"
        .."I know you belong\nto the Boss...\f"
        .."But that doesn't mean\nyou can bully everyone.\f"
        .."And you owe RATTY\nan apology!",
        done)
      return
    end

    if q.pixieStored then
      showBox(game,
        "LOGAN: Please...\f"
        .."Watch over PIXIE.",
        done)
      return
    end

    if not q.loganAsked then
      showBox(game,
        "LOGAN: It started...\f"
        .."The CONSERVATION\nPROJECT has launched.\f"
        .."If anything survives\nthis...\f"
        .."This may be its\nonly chance.\f"
        .."It's really happening...",
        function()
          npc.facing=(ow.player.cellX<npc.cellX) and "left"
            or (ow.player.cellX>npc.cellX) and "right"
            or (ow.player.cellY<npc.cellY) and "up" or "down"
          showBox(game,
            "LOGAN: DITTO...\f"
            .."Please help me!\f"
            .."I can't find PIXIE,\nmy VULPIX.\f"
            .."Please find her...\f"
            .."Bring her back here.",
            function()
              showBox(game,
                "LOGAN: She has to be\nsomewhere in the lab.\f"
                .."Please hurry, DITTO!",
                function()
                  q.loganAsked=true
                  done()
                end)
            end)
        end)
      return
    end

    if not q.pixieFollowing then
      showBox(game,
        "LOGAN: Please!\fFind PIXIE for me!",
        done)
      return
    end

    showBox(game,
      "LOGAN: PIXIE!\f"
      .."You're safe!\f"
      .."Thank goodness...",
      function()
        showBox(game,
          "PIXIE runs to LOGAN.\f"
          .."He kneels and holds\nher close.",
          function()
            showBox(game,
              "LOGAN: Okay, PIXIE...\f"
              .."It's time.",
              function()
                removeNpc(ow,"VULPIX")
                q.pixieFollowing=false
                q.pixieStored=true

                showBox(game,
                  "LOGAN places PIXIE\ninto the PC.\f"
                  .."LOGAN: I'm sorry, PIXIE...\f"
                  .."I have to go now.",
              function()
                npc.facing=(ow.player.cellX<npc.cellX) and "left"
                  or (ow.player.cellX>npc.cellX) and "right"
                  or (ow.player.cellY<npc.cellY) and "up" or "down"

                showBox(game,
                  "LOGAN: DITTO...\f"
                  .."Please watch over PIXIE.\f"
                  .."Stay with her until\nwe come back.\f"
                  .."I'm counting on you.\f"
                  .."LOGAN places you\ninto the PC BOX.",
                  function()
                    -- Early-game PERSIAN is only a temporary copied form.
                    -- Entering the PC clears that learned transformation and
                    -- guarantees the later timeline starts as ordinary DITTO.
                    q.forms=q.forms or {}
                    q.forms.PERSIAN=nil
                    q.currentForm="DITTO"
                    q.requestedForm="DITTO"
                    local liveOw=activeOverworld and activeOverworld(game)
                    if liveOw and applyDittoForm then
                      applyDittoForm(game,"DITTO",liveOw)
                    end
                    done()

                    -- This is the story's chronological hinge. On a first
                    -- pass the demo still hands off to `Much earlier...` and
                    -- the Celadon prequel, because the player has not yet
                    -- been told how the world reached LOG 568. Once that
                    -- prequel has been played, the same moment continues
                    -- forward instead: departure, liftoff, and the bookend.
                    if Finale and Finale.shouldAutoPlay(game) then
                      Finale.play(game,{onFinish=function(g)
                        -- The demo loop is preserved. After the ending, the
                        -- Celadon chapter is still reachable exactly as before.
                        muchEarlier(g)
                      end})
                    else
                      muchEarlier(game)
                    end
                  end)
                end)
              end)
          end)
      end)
  end

  local function giovanniMeetingTalk(game,ow,npc,done)
    local q=pokopiaData(game)

    if q.giovanniMeetingDone then
      showBox(game,
        "GIOVANNI: We're going\nto do everything we can\f"
        .."to save every\nPOKeMON.\f"
        .."You have my word.",
        done)
      return
    end

    local scientist=findNpc(ow,"SCI_1C")
    if scientist then
      scientist.facing="left"
      scientist.wanders=false
      scientist.frozen=true
    end
    npc.facing="down"

    showBox(game,
      "SCIENTIST: Sir...\f"
      .."The POKeMON\nCONSERVATION PROJECT\f"
      .."is ready to\ncommence.\f"
      .."We'll preserve the\nPOKeMON\f"
      .."that could not\ncome with us\f"
      .."in the PC system.\f"
      .."There, they'll\nremain safe\f"
      .."while the planet\nrecovers.\f"
      .."Mankind will\nleave Earth\f"
      .."and establish\nourselves in space.\f"
      .."When Earth can\nsupport POKeMON again,\f"
      .."the system will\nrelease them\f"
      .."into suitable\nhabitats.\f"
      .."God help us all...",
      function()
        local function giovanniReply()
          -- Keep the silent beat as narration, then give Giovanni his own
          -- speaker-scoped dialogue so the trainer portrait + GIOVANNI
          -- nameplate are present throughout his actual lines.
          showBox(game,
            "Giovanni sits silent\nfor a moment.\f"
            .."He lowers his gaze\nat DITTO, considering it.",
            function()
              showBox(game,
                "GIOVANNI: So...\f"
                .."We abandon the world,\fpreserve what we can,\f"
                .."and trust that one day\fit will be waiting\nfor us.\f"
                .."An ambitious plan.\f"
                .."Perhaps the only one\nwe have.\f"
                .."He gives DITTO a final\npat on the head.\f"
                .."Nice try, little DITTO...\f"
                .."But you couldn't copy\nthat twitch PERSIAN does\f"
                .."when I scratch behind\nhis ear.\f"
                .."A faint smile crosses\nhis face.\f"
                .."Tell PERSIAN to join me\f"
                .."when it's finished\nplaying with that RATTATA.\f"
                .."He pauses, his hand\nresting gently\f"
                .."on DITTO's head with\none last pat.\f"
                .."We're going to do\neverything we can\f"
                .."to save every POKeMON.\f"
                .."You have my word.",
                function()
                  q.giovanniMeetingDone=true
                  done()
                end,
                {speaker="GIOVANNI"})
            end)
        end

        if not scientist then
          giovanniReply()
          return
        end

        -- The scientist leaves the room completely before Giovanni responds.
        -- Walk the original first beats, then continue all the way through a
        -- real room exit. Giovanni's textbox is gated on the final exit step.
        scientist.frozen=false
        walkNpcTo(ow,scientist,7,6,function()
          walkNpcTo(ow,scientist,9,6,function()
            walkNpcOutOfRoom(ow,scientist,function()
              removeNpc(ow,"SCI_1C")
              giovanniReply()
            end)
          end)
        end)
      end)
  end

  local function hypnoTimeTalk(game,ow,npc,done)
    local q=pokopiaData(game)
    npc.frozen=true
    npc.wanders=false

    local function prepScene2State()
      -- Mark the Mansion timeline's required completion state before
      -- entering the exact chronology handoff used by normal play.
      q.distractionDone=true
      q.distractionCommitted=true
      q.distractionStarted=nil
      q.rattataFollowing=false
      q.giovanniMeetingDone=true
      q.pixieFollowing=false
      q.pixieStored=true
      q.persianLessonPlaying=nil
    end

    local function startScene1()
      -- Fresh Mansion story state, without touching unrelated engine save data.
      -- This developer jump begins at the normal Scene 1 gameplay spawn rather
      -- than replaying OakSpeech.
      game.save.modData=game.save.modData or {}
      game.save.modData.pokopia_log568={
        schemaVersion=POKOPIA_SAVE_SCHEMA,
        forms={},
        currentForm="DITTO",
      }
      game.save.flags=game.save.flags or {}
      game.save.flags.EVENT_MANSION_SWITCH_ON=nil

      if done then done() end
      ow:setMap(START_MAP,8,10,"left",{via="boot"})
      ow.playerHidden=false
      setActorCell(ow.player,8,10)
      ow.player.facing="left"
      applyDittoForm(game,"DITTO",ow)
      restorePlayerInput(game,ow)
      startPokopiaAlarm(game)
      if ow.camera then ow.camera:follow(ow.player.px,ow.player.py) end
    end

    local hypnoHub

    local function openScenePicker()
      -- Keep the original developer scene picker as a submenu.
      local Font=require("src.render.Font")
      local Sound=require("src.core.Sound")
      -- SCENE 3 is the LOG 568 bookend. FINALE LOG jumps straight to the
      -- Scientist so the recognition beat can be checked without replaying
      -- the departure and the launch.
      local rows={"SCENE 1","SCENE 2","SCENE 2.5","SCENE 3","FINALE LOG","BACK"}
      local menu={isOpaque=false,cursor=1}

      local function cancelPicker()
        hypnoHub()
      end

      local function chooseScene(choice)
      if choice=="SCENE 1" then
        startScene1()
      elseif choice=="SCENE 2" then
        prepScene2State()
        if done then done() end
        muchEarlier(game)
      elseif choice=="SCENE 2.5" then
        prepScene2State()
        if done then done() end
        muchEarlier(game,true)
      elseif choice=="SCENE 3" then
        prepScene2State()
        npc.frozen=false
        if done then done() end
        if Finale then Finale.play(game,{dev=true}) end
      elseif choice=="FINALE LOG" then
        prepScene2State()
        npc.frozen=false
        if done then done() end
        if Finale then Finale.play(game,{dev=true,from="LOG568"}) end
      else
        cancelPicker()
      end
    end

      function menu:update()
      local input=game.input
      if input:wasPressed("up") then
        self.cursor=self.cursor-1
        if self.cursor<1 then self.cursor=#rows end
        Sound.play(game.data,"Press_AB")
      elseif input:wasPressed("down") then
        self.cursor=self.cursor+1
        if self.cursor>#rows then self.cursor=1 end
        Sound.play(game.data,"Press_AB")
      elseif input:wasPressed("b") then
        game.stack:pop()
        cancelPicker()
      elseif input:wasPressed("a") then
        Sound.play(game.data,"Press_AB")
        local choice=rows[self.cursor]
        game.stack:pop()
        chooseScene(choice)
      end
    end

      function menu:draw()
      -- The frame and row pitch are sized to the actual row count so no
      -- entry paints outside the box (the old 4-row layout already did).
      Font.drawBox(2,2,16,15)
      love.graphics.setColor(0,0,0,1)
      Font.draw("HYPNO",56,28)
      Font.draw("PICK A SCENE",32,42)
      for i,row in ipairs(rows) do
        Font.draw(row,40,60+(i-1)*12)
      end
      local ay=62+(self.cursor-1)*12
      love.graphics.polygon("fill",28,ay,28,ay+8,34,ay+4)
      love.graphics.setColor(1,1,1,1)
    end

      game.stack:push(menu)
    end

    hypnoHub=function()
      local t=TCGServices.state(game)
      local rows={
        {label="FREE BOOSTER PACKS",right="UNLIMITED"},
        {label="FREE STARTER DECKS",right="UNLIMITED"},
        {label="DECK BUILDER",right=TCGServices.deckCount(t.deck).."/60"},
        {label="DUEL HYPNO"},
        {label="SCENE JUMPS"},
        {label="LEAVE"},
      }
      TCGServices.menu(game,"HYPNO'S CARD CLUB",rows,function(_,idx)
        if idx==1 then TCGServices.packShop(game,hypnoHub,true)
        elseif idx==2 then TCGServices.starterChooser(game,true,hypnoHub,true)
        elseif idx==3 then TCGServices.deckBuilder(game,hypnoHub)
        elseif idx==4 then TCGServices.duel(game,hypnoHub)
        elseif idx==5 then openScenePicker()
        else
          npc.frozen=false
          if done then done() end
        end
      end,function()
        npc.frozen=false
        if done then done() end
      end,{
        status="PACKS FREE  DECKS FREE",
        footer="A SELECT  B LEAVE",
      })
    end

    hypnoHub()
  end

  local function talkFor(id)
    local t={}
    for k,v in pairs(COMMON) do t[k]=v end
    for k,v in pairs(FLOOR_TALK[id] or {}) do t[k]=v end
    -- magnetonTalk is declared by the time talkFor runs; binding here avoids
    -- the earlier Lua lexical-order bug that made MAGNETON non-interactive.
    t.TEXT_MAGNETON=magnetonTalk
    t.TEXT_VOLTORB=voltorbTalk
    t.TEXT_ELECTRODE=electrodeTalk

    if id=="POKEMON_MANSION_1F" then
      t.TEXT_RATTATA=rattataTalk
      t.TEXT_LARVITAR=larvitarTalk
      t.TEXT_ROCKET_GUARD=rocketGuardTalk
      t.TEXT_GIOVANNI=giovanniMeetingTalk
      t.TEXT_1S3=giovanniMeetingTalk
    end
    if id=="POKEMON_MANSION_2F" then t.TEXT_VULPIX=vulpixTalk end
    if id=="POKEMON_MANSION_3F" then t.TEXT_HYPNO_TIME=hypnoTimeTalk end
    if id=="POKEMON_MANSION_B1F" then
      t.TEXT_PC_END=loganTalk
      t.TEXT_RATTATA_ARGUMENT=basementPairTalk
      t.TEXT_PERSIAN_ARGUMENT=basementPairTalk
    end
    return t
  end

  local function nearestValidNpcCell(map,sx,sy,occupied)
    local function valid(x,y)
      if not map:inBounds(x,y) then return false end
      if not map:isWalkableCell(x,y) then return false end
      if map:warpAtCell(x,y) then return false end
      return not occupied[x..":"..y]
    end

    if valid(sx,sy) then return sx,sy end

    for radius=1,12 do
      for dy=-radius,radius do
        for dx=-radius,radius do
          if math.abs(dx)==radius or math.abs(dy)==radius then
            local x,y=sx+dx,sy+dy
            if valid(x,y) then return x,y end
          end
        end
      end
    end
    return nil,nil
  end

  local function sanitizeNpcPositions(ow)
    if not (ow and ow.map and ow.npcs) then return end

    local occupied={}
    if ow.player then
      occupied[ow.player.cellX..":"..ow.player.cellY]=true
    end

    -- Process stationary blockers first so wandering NPC relocation cannot
    -- steal their intended cells.
    local ordered={}
    for _,npc in ipairs(ow.npcs) do
      if not npc.wanders then ordered[#ordered+1]=npc end
    end
    for _,npc in ipairs(ow.npcs) do
      if npc.wanders then ordered[#ordered+1]=npc end
    end

    for _,npc in ipairs(ordered) do
      local x,y=nearestValidNpcCell(ow.map,npc.cellX,npc.cellY,occupied)
      if x and y then
        npc.cellX,npc.cellY=x,y
        npc.px,npc.py=x*16,y*16
        npc.targetX,npc.targetY=nil,nil
        npc.moving=false

        if npc.def then
          npc.def.x,npc.def.y=x,y
        end

        occupied[x..":"..y]=true
      else
        -- A custom actor with no legal placement is frozen rather than being
        -- allowed to wander through invalid geometry.
        npc.wanders=false
      end
    end
  end

  local function apply3FMansionPuzzle(game,ow)
    if not (ow and ow.map and ow.map.id=="POKEMON_MANSION_3F") then return end
    local on=game.save.flags and game.save.flags.EVENT_MANSION_SWITCH_ON
    -- Original 3F switch-door pair from data/scripts/story6.lua.
    ow:replaceBlock(7,2,on and 0x5f or 0x0e)
    ow:replaceBlock(7,5,on and 0x0e or 0x5f)
  end

  local function mansionEnter(game,ow)
    for _,p in ipairs(OPEN_GATES[ow.map.id] or {}) do
      ow:replaceBlock(p[1],p[2],0x0e)
    end

    -- Keep the lower-right 1F perimeter barrier closed. Opening this single
    -- switch block exposes the edge of the map and lets the player walk out
    -- of bounds, so unlike the other emergency-open gates it stays solid.
    if ow.map.id=="POKEMON_MANSION_1F" then
      ow:replaceBlock(13,13,0x5f)
    end

    -- 3F is the exception: retain its real statue/barrier puzzle.
    apply3FMansionPuzzle(game,ow)

    local q=pokopiaData(game)

    if q.alarmDisabled then
      stopPokopiaAlarm(game)
    end

    -- Once the distraction has happened, the original 1F RATTATA and
    -- Giovanni's PERSIAN have left this room for good. The static POP table
    -- recreates map actors on every load, so remove those original population
    -- instances immediately on every later 1F entry.
    if q.distractionDone and ow.map.id=="POKEMON_MANSION_1F" then
      removeNpc(ow,"RATTATA")
      removeNpc(ow,"PERSIAN")
    end

    if q.giovanniMeetingDone and ow.map.id=="POKEMON_MANSION_1F" then
      removeNpc(ow,"SCI_1C")
    end

    if ow.map.id=="POKEMON_MANSION_B1F"
        and not (q.distractionDone and q.giovanniMeetingDone) then
      removeNpc(ow,"PC_SCIENTIST")
    end

    if ow.map.id=="POKEMON_MANSION_B1F" then
      -- Vanilla POKECENTER block $22 contains the PC terminal in its
      -- upper-left 16x16 cell.  Keep the PC as map geometry instead of an
      -- overworld sprite; block (7,7) maps that terminal cell to (14,14).
      ow:replaceBlock(7,7,0x22)
    end

    -- Recover saves made while an older distraction implementation left the
    -- player locked after the chase object had already disappeared.
    if q and q.distractionStarted and not ow.pokopiaPersianChase then
      q.distractionStarted=nil
      restorePlayerInput(game,ow)
    end

    -- Older saves may have already completed the distraction without the new
    -- one-shot latch. Treat completed state as committed too.
    if q and q.distractionDone then
      q.distractionCommitted=true
      if q.postChaseGuardArmed==nil then
        q.postChaseGuardArmed=false
      end

      -- Completed distraction state must never leave runtime movement locks.
      ow.pokopiaPersianChase=nil
      for i=#(ow.scriptMoves or {}),1,-1 do
        local mv=ow.scriptMoves[i]
        local n=mv and mv.entity and mv.entity.def and mv.entity.def.name
        if n=="RATTATA" or n=="PERSIAN" then
          table.remove(ow.scriptMoves,i)
        end
      end
      restorePlayerInput(game,ow)
    end

    -- The basement argument pair has deliberately persistent coordinates.
    -- Sanitize the ordinary room population first; spawn/restore the pair
    -- afterward so revisiting the floor cannot relocate them.
    sanitizeNpcPositions(ow)
    if q and q.currentForm and ow.player.pokopiaForm~=q.currentForm then
      applyDittoForm(game,q.currentForm,ow)
    end
    if q and q.pixieFollowing then
      ensurePixieFollower(game,ow,true)
    end

    if q and q.distractionDone and ow.map.id=="POKEMON_MANSION_B1F"
        and (not findNpc(ow,"RATTATA_ARGUMENT")
          or not findNpc(ow,"PERSIAN_ARGUMENT")) then
      -- Never leave half of the persistent pair behind. Rebuild both from
      -- the single saved position record.
      removeNpc(ow,"RATTATA_ARGUMENT")
      removeNpc(ow,"PERSIAN_ARGUMENT")

      local rx,ry,px,py
      if q.argumentPositions then
        rx,ry=q.argumentPositions.ratX,q.argumentPositions.ratY
        px,py=q.argumentPositions.persianX,q.argumentPositions.persianY
      else
        rx,ry,px,py=findBasementArgumentPair(ow)
        if rx then
          q.argumentPositions={
            ratX=rx,ratY=ry,persianX=px,persianY=py,
            ratFacing="right",persianFacing="left",locked=true,
          }
        end
      end
      if rx then
        local ratFacing=(q.argumentPositions and q.argumentPositions.ratFacing) or "right"
        local persianFacing=(q.argumentPositions and q.argumentPositions.persianFacing) or "left"
        makeQuestNpc(game,ow,96,"RATTATA_ARGUMENT",RATTATA,
          rx,ry,ratFacing,"TEXT_RATTATA_ARGUMENT")
        makeQuestNpc(game,ow,97,"PERSIAN_ARGUMENT",PERSIAN,
          px,py,persianFacing,"TEXT_PERSIAN_ARGUMENT")
      end
    end

    if q and q.persianLessonDone and q.argumentPositions
        and ow.map.id=="POKEMON_MANSION_B1F" then
      local a=q.argumentPositions
      local rat=findNpc(ow,"RATTATA_ARGUMENT")
      local persian=findNpc(ow,"PERSIAN_ARGUMENT")
      if rat then
        rat.cellX,rat.cellY=a.ratX,a.ratY
        rat.targetX,rat.targetY=a.ratX,a.ratY
        rat.facing=a.ratFacing or "right"
        rat.moving=false
        rat.frozen=true
      end
      if persian then
        persian.cellX,persian.cellY=a.persianX,a.persianY
        persian.targetX,persian.targetY=a.persianX,a.persianY
        persian.facing=a.persianFacing or "left"
        persian.moving=false
        persian.frozen=true
      end
    end

    -- Emergency movement characterization. Lower stepFrames = faster travel.
    -- Movement remains handled by NPC:update -> Collision.canMove.
    local speedByName={
      -- electrical Pokemon: rapid rolling/hovering patrols
      VOLTORB=10,
      ELECTRODE=8,
      MAGNEMITE=18,
      MAGNETON=16,

      -- airborne poison Pokemon: slower drifting
      KOFFING=30,
      WEEZING=34,

      -- ground Pokemon
      RATTATA=10,
      TOTODILE=13,
      CHARMANDER=20,
      GRIMER=28,
      MUK=34,

      -- frantic scientists
      SCI_1A=12,
      SCI_1B=14,
      SCI_2A=11,
      SCI_2B=13,
      SCI_3A=10,
      SCI_3B=12,
      SCI_3C=11,
      SCI_BA=12,
      SCI_BB=13,
    }

    -- A subset of scientists use deterministic pacing instead of random
    -- wandering. axis controls the corridor direction; dir is remembered
    -- on the live NPC and reverses whenever collision blocks the next cell.
    local patrolByName={
      VOLTORB={axis="h",dir="left",minX=21,maxX=22,minY=7,maxY=7},
      SCI_1A={axis="h",dir="right"},
      SCI_2A={axis="h",dir="left"},
      SCI_3A={axis="v",dir="down"},
      SCI_3B={axis="h",dir="right"},
      SCI_BA={axis="h",dir="left"},
    }

    for _,npc in ipairs(ow.npcs or {}) do
      local name=npc.def and npc.def.name

      if name=="RATTATA_ARGUMENT" or name=="PERSIAN_ARGUMENT" then
        npc.wanders=false
        npc.pokopiaPatrol=nil
        if q.persianLessonDone then
          npc.frozen=true
        end
      end

      local speed=name and speedByName[name]
      if speed then
        npc.stepFrames=speed
        -- Running/patrolling actors make decisions more often.
        npc.timer=math.min(npc.timer or 30,12)
      end

      local patrol=name and patrolByName[name]
      if patrol then
        npc.pokopiaPatrol={
          axis=patrol.axis,
          dir=patrol.dir,
          minX=patrol.minX,maxX=patrol.maxX,
          minY=patrol.minY,maxY=patrol.maxY,
        }
        -- Disable NPC.lua's random wander decisions for these actors.
        npc.wanders=false
      end
    end

  end

  -- Override, rather than patch, so vanilla switch scripts cannot re-close
  -- the Mansion's puzzle barriers.
  for mapId in pairs(MANSION) do
    local record={
      onEnter=mansionEnter,
      talk=talkFor(mapId),
    }

    if mapId=="POKEMON_MANSION_1F" then
      record.onStep=function(game,ow,x,y)
        local TextBox=require("src.render.TextBox")
        local q=pokopiaData(game)

        -- After the Rattata/Persian chase, Ditto may still be standing on or
        -- immediately beside the old interceptor trigger when control returns.
        -- Do not let that same tile instantly start another emote lock.
        -- The first successful step away arms the guard for later visits.
        if q.distractionDone and not q.postChaseGuardArmed then
          if x~=9 or y~=2 then
            q.postChaseGuardArmed=true
          else
            return false
          end
        end

        -- Room shown in the supplied 1F reference, directly north of stairs.
        if x==9 and y==2 then
          if q.currentForm=="PERSIAN" and q.forms and q.forms.PERSIAN then
            return false
          end
          if q.distractionDone and not q.postChaseGuardArmed then
            return false
          end
          local guard=findNpc(ow,"ROCKET_GUARD")
          if guard then
            guard.facing="down"

            -- Same overworld emote state used by normal trainer detection.
            -- The engine renders EXCLAMATION_BUBBLE for 60 frames and
            -- freezes overworld input until onDone runs.
            ow.emote={
              npc=guard,
              frames=60,
              onDone=function()
                local q=pokopiaData(game)
                local text
                if q.distractionDone then
                  text="ROCKET: That RATTATA\nsure was funny\f"
                    .."coming in here and\ngetting PERSIAN all\nriled up like that.\f"
                    .."I wonder where\nthey went?\f"
                    .."Oh, please stay\noutside.\f"
                    .."The only POKeMON\nallowed in here is\nPERSIAN."
                elseif q.rocketStopped then
                  text="ROCKET: Sorry, only\nthe boss and his\nPERSIAN are allowed\nback here."
                else
                  text="ROCKET: Woah,\nlittle fella!\f"
                    .."You don't have\nclearance to come\nin here.\f"
                    .."Don't worry.\f"
                    .."I know the sounds\nare scary...\f"
                    .."But it'll be okay.\f"
                    .."The boss is making\nsure of it!"
                end
                game.stack:push(TextBox.new(game,text,function()
                  q.rocketStopped=true
                  ow:scriptMove(ow.player,"right",1,nil,{collide=true})
                end))
              end,
            }
          end
          return true
        end

        if y~=26 or (x~=5 and x~=6) then return false end
        local text
        if x==5 then
          text="SCIENTIST: Hey!\nStay back!\f"
            .."Those doors stay shut!"
        else
          text="SCIENTIST: Don't try\nto squeeze through!\f"
            .."Back inside! Now!"
        end

        game.stack:push(TextBox.new(game,text,function()
          ow:scriptMove(ow.player,"up",1,nil,{collide=true})
        end))
        return true
      end
    end

    if mapId=="POKEMON_MANSION_B1F" then
      -- The Pokémon Center PC graphic occupies cell (14,14) inside the
      -- transplanted vanilla block.  Keep the Mansion PC behavior attached
      -- to that map position rather than to an NPC/object sprite.
      record.onInteract=function(game,ow,fx,fy)
        if fx~=14 or fy~=14 then return false end
        pcBoxTalk(game,ow,nil,nil)
        return true
      end
    end

    if mapId=="POKEMON_MANSION_3F" then
      -- Restore the original 3F statue switch at (10,5).
      record.onInteract=function(game,ow,fx,fy)
        if ow.player.facing~="up" or fx~=10 or fy~=5 then return false end

        local TextBox=require("src.render.TextBox")
        local t=game.data.text or {}
        local question=t._PokemonMansion2FSwitchText
          or "A secret switch!\fPress it?"

        game.stack:push(TextBox.new(game,question,nil,{
          choice=function(yes)
            if not yes then
              game.stack:push(TextBox.new(game,
                t._PokemonMansion2FSwitchNotPressedText or "Not quite yet!"))
              return
            end

            game.save.flags=game.save.flags or {}
            if game.save.flags.EVENT_MANSION_SWITCH_ON then
              game.save.flags.EVENT_MANSION_SWITCH_ON=nil
            else
              game.save.flags.EVENT_MANSION_SWITCH_ON=true
            end

            require("src.core.Sound").play(game.data,"Go_Inside")
            apply3FMansionPuzzle(game,ow)
            game.stack:push(TextBox.new(game,
              t._PokemonMansion2FSwitchPressedText or "Who wouldn't?"))
          end
        }))
        return true
      end
    end

    mod.content.map_scripts:override(mapId,record)
  end

  --------------------------------------------------------------------------
  -- Celadon Department Store card shop / post-quest kids.
  --------------------------------------------------------------------------
  local CARD_EXPANSIONS={"COLOSSEUM","EVOLUTION","MYSTERY","LABORATORY"}

  local function ensureMart2FCardKids(game,ow)
    if not (ow and ow.map and ow.map.id=="CELADON_MART_2F") then return end
    local q=normalizePokopiaSave(game.save)
    if not q.cardQuestComplete then return end

    local NPC=require("src.world.NPC")
    local Collision=require("src.world.Collision")

    local function findLive(name)
      for _,npc in ipairs(ow.npcs or {}) do
        if npc and npc.def and npc.def.name==name then return npc end
      end
      return nil
    end
    local function openCell(x,y)
      return ow.map:inBounds(x,y)
        and ow.map:isWalkableCell(x,y)
        and not ow.map:warpAtCell(x,y)
        and not Collision.occupied(ow.entities,x,y,nil)
    end
    local function openNear(sx,sy)
      if openCell(sx,sy) then return sx,sy end
      for r=1,8 do
        for dy=-r,r do
          for dx=-r,r do
            if math.abs(dx)==r or math.abs(dy)==r then
              local x,y=sx+dx,sy+dy
              if openCell(x,y) then return x,y end
            end
          end
        end
      end
      return nil,nil
    end
    local function spawn(name,sprite,x,y,facing)
      if findLive(name) then return end
      local sx,sy=openNear(x,y)
      if not sx then return end
      local n=NPC.new(game.data,ow.map.id,{
        index=220+#(ow.npcs or {}),name=name,sprite=sprite,
        movement="STAY",range="NONE",x=sx,y=sy,runtime=true,
      })
      n.facing=facing or "down"
      n.wanders=false
      n.frozen=true
      n.passable=false
      table.insert(ow.npcs,n)
      table.insert(ow.entities,n)
    end

    spawn("CEL_2F_CARD_KID_06","SPRITE_YOUNGSTER",5,5,"right")
    spawn("CEL_2F_CARD_KID_07","SPRITE_YOUNGSTER",6,5,"left")
    spawn("CEL_2F_CARD_KID_08","SPRITE_GIRL",7,5,"left")
  end

  local function ensureMart3FYellow(game,ow)
    if not (ow and ow.map and ow.map.id=="CELADON_MART_3F") then return end

    for _,npc in ipairs(ow.npcs or {}) do
      if npc and npc.def and npc.def.name=="CEL_3F_YELLOW" then return end
    end

    local NPC=require("src.world.NPC")
    local Collision=require("src.world.Collision")

    local function openCell(x,y)
      return ow.map:inBounds(x,y)
        and ow.map:isWalkableCell(x,y)
        and not ow.map:warpAtCell(x,y)
        and not Collision.occupied(ow.entities,x,y,nil)
    end

    local sx,sy=nil,nil
    local preferredX,preferredY=5,5
    if openCell(preferredX,preferredY) then
      sx,sy=preferredX,preferredY
    else
      for r=1,8 do
        if sx then break end
        for dy=-r,r do
          if sx then break end
          for dx=-r,r do
            if math.abs(dx)==r or math.abs(dy)==r then
              local x,y=preferredX+dx,preferredY+dy
              if openCell(x,y) then sx,sy=x,y break end
            end
          end
        end
      end
    end
    if not sx then return end

    local n=NPC.new(game.data,ow.map.id,{
      index=240+#(ow.npcs or {}),
      name="CEL_3F_YELLOW",
      sprite="POKOPIA_YELLOW",
      text="TEXT_POKOPIA_YELLOW",
      movement="WALK",range="ALL",x=sx,y=sy,runtime=true,
    })
    n.facing="down"
    n.wanders=true
    n.frozen=false
    n.passable=false
    table.insert(ow.npcs,n)
    table.insert(ow.entities,n)
  end

  local function yellowTalk(game,ow,npc,done)
    done=done or function() end
    local TextBox=require("src.render.TextBox")

    if npc and ow and ow.player then
      if ow.player.cellX<(npc.cellX or 0) then npc.facing="left"
      elseif ow.player.cellX>(npc.cellX or 0) then npc.facing="right"
      elseif ow.player.cellY<(npc.cellY or 0) then npc.facing="up"
      else npc.facing="down" end
    end

    local text=
      "Oh! You're a DITTO.\f"
      .."I can tell you're\ncurious about me.\f"
      .."I'm YELLOW, from\nVIRIDIAN FOREST.\f"
      .."I don't like seeing\nPOKeMON get hurt.\f"
      .."Sometimes I can feel\nwhat they're feeling...\f"
      .."and help them heal.\f"
      .."So if you're ever\nhurt, come find me, okay?"

    game.stack:push(TextBox.new(game,text,done,{
      speaker="YELLOW",
      portrait={speaker="YELLOW",expression="Normal"},
    }))
  end

  local function celadonCardVendorTalk(game,ow,npc,done)
    done=done or function() end
    local q=normalizePokopiaSave(game.save)
    local TextBox=require("src.render.TextBox")
    local Sound=require("src.core.Sound")
    local Bag=require("src.inventory.Bag")

    local function say(text,after)
      game.stack:push(TextBox.new(game,text,after or done,{
        speaker="CLERK",
        portrait={speaker="GENTLEMAN",expression="Normal"},
      }))
    end

    if not q.cardQuestComplete then
      say("Sorry! The card counter\nis closed until the\nline outside clears.")
      return
    end

    local function buy(expansion,qty,price)
      if (game.save.coins or 0)<price then
        say("You don't have enough\nCOINS.")
        return
      end
      local pack=TCG_PACKS[expansion]
      if not (pack and Bag.add(game.save,pack.item,qty,game.data)) then
        say("There is not enough room\nin the BAG for those packs.")
        return
      end
      game.save.coins=(game.save.coins or 0)-price
      Sound.play(game.data,"Get_Item1")
      say("DITTO bought "..expansion.." PACK x"..qty.."!\nUse it from INVENTORY.")
    end

    local function quantityMenu(expansion)
      local rows={
        {label="1 PACK",right="10C",price=10,qty=1},
        {label="6-PACK",right="60C",price=60,qty=6},
        {label="BACK",back=true},
      }
      tcgMenu(game,tcgSafe(expansion).." PACKS",rows,function(row)
        if row.back then done() else buy(expansion,row.qty,row.price) end
      end,done,{status="COINS "..tostring(game.save.coins or 0),footer="A BUY  B BACK"})
    end

    local function expansionMenu()
      local rows={}
      for _,name in ipairs(CARD_EXPANSIONS) do
        rows[#rows+1]={label=tcgSafe(name),expansion=name}
      end
      rows[#rows+1]={label="CANCEL",cancel=true}
      tcgMenu(game,"CARD PACKS",rows,function(row)
        if row.cancel then done() else quantityMenu(row.expansion) end
      end,done,{status="10 COINS EACH",footer="A SELECT  B BACK"})
    end

    say("CARD COUNTER: Pick an\nexpansion!",expansionMenu)
  end

  --------------------------------------------------------------------------
  -- Celadon Department Store: Ditto cannot use human shop counters.
  -- Hook the map-script talk layer itself, before native open_mart dispatch.
  --------------------------------------------------------------------------
  local function celadonMartClerkTalk(game,ow,npc,done)
    done=done or function() end
    local q=normalizePokopiaSave(game.save)
    local TextBox=require("src.render.TextBox")
    local mapId=ow and ow.map and ow.map.id or ""

    if mapId=="CELADON_MART_2F" and q.cardQuestComplete then
      celadonCardVendorTalk(game,ow,npc,done)
      return
    end

    local function say(text,speaker,portrait,after)
      game.stack:push(TextBox.new(game,text,after or done,{
        speaker=speaker or "CLERK",
        portrait={speaker=portrait or "GENTLEMAN",expression="Normal"},
      }))
    end

    if mapId=="CELADON_MART_1F" or mapId=="CELADON_MART" then
      if q.cardQuestComplete then
        say("Welcome, DITTO!\f"
          .."The card counter is\nopen on the 2nd floor.",
          "CLERK","BEAUTY")
      else
        say("Sorry, DITTO.\f"
          .."We're waiting for the\nline outside to clear.",
          "CLERK","BEAUTY")
      end
      return
    end

    say("Hello, DITTO!\f"
      .."Welcome to the\nDEPT. STORE.",
      "CLERK","GENTLEMAN")
  end

  local function blockCeladonMartTalk(mapId)
    local base=mod.content.map_scripts:get(mapId) or {}
    local record={}
    for k,v in pairs(base) do record[k]=v end
    record.talk={}

    for k,v in pairs(base.talk or {}) do
      if mapId=="CELADON_MART_2F" and type(v)=="table" and v.mart then
        record.talk[k]=celadonCardVendorTalk
      elseif type(v)=="table" and v.mart then
        record.talk[k]=celadonMartClerkTalk
      elseif tostring(k):find("CLERK",1,true)
          or tostring(k):find("SALESMAN",1,true)
          or tostring(k):find("CASHIER",1,true)
          or tostring(k):find("RECEPTION",1,true) then
        record.talk[k]=(mapId=="CELADON_MART_2F")
          and celadonCardVendorTalk or celadonMartClerkTalk
      else
        record.talk[k]=v
      end
    end

    if mapId=="CELADON_MART_1F" then
      for k,_ in pairs(base.talk or {}) do
        record.talk[k]=celadonMartClerkTalk
      end
    elseif mapId=="CELADON_MART_2F" then
      local originalOnEnter=base.onEnter
      record.onEnter=function(game,ow,...)
        if originalOnEnter then originalOnEnter(game,ow,...) end
        ensureMart2FCardKids(game,ow)
      end
    elseif mapId=="CELADON_MART_3F" then
      local originalOnEnter=base.onEnter
      record.onEnter=function(game,ow,...)
        if originalOnEnter then originalOnEnter(game,ow,...) end
        ensureMart3FYellow(game,ow)
      end
      record.talk.TEXT_POKOPIA_YELLOW=yellowTalk
    end

    mod.content.map_scripts:override(mapId,record)
  end

  for _,mapId in ipairs({
    "CELADON_MART_1F","CELADON_MART_2F","CELADON_MART_3F",
    "CELADON_MART_4F","CELADON_MART_5F"
  }) do
    blockCeladonMartTalk(mapId)
  end

  --------------------------------------------------------------------------
  -- Rocket Hideout: post-story casual Team Rocket hangout.
  --------------------------------------------------------------------------
  local ROCKET_HANGOUT_MAPS={
    ROCKET_HIDEOUT_B1F=true,
    ROCKET_HIDEOUT_B2F=true,
    ROCKET_HIDEOUT_B3F=true,
    ROCKET_HIDEOUT_B4F=true,
  }

  local function rocketNativeMenu(game,title,labels,onPick,onCancel)
    local Font=require("src.render.Font")
    local Sound=require("src.core.Sound")
    local menu={isOpaque=false,index=1,labels=labels or {}}
    function menu:update()
      local input=game.input
      if input:wasPressed("up") then
        self.index=self.index-1
        if self.index<1 then self.index=#self.labels end
        Sound.play(game.data,"Press_AB")
      elseif input:wasPressed("down") then
        self.index=self.index+1
        if self.index>#self.labels then self.index=1 end
        Sound.play(game.data,"Press_AB")
      elseif input:wasPressed("b") then
        Sound.play(game.data,"Press_AB")
        if game.stack:top()==self then game.stack:pop() end
        if onCancel then onCancel() end
      elseif input:wasPressed("a") then
        Sound.play(game.data,"Press_AB")
        local i=self.index
        if game.stack:top()==self then game.stack:pop() end
        if onPick then onPick(i) end
      end
    end
    function menu:draw()
      local rows=#self.labels
      local h=math.max(5,3+rows*2)
      local y=18-h
      Font.drawBox(1,y,18,h)
      love.graphics.setColor(0,0,0,1)
      Font.draw(tostring(title or ""),16,(y+1)*8)
      for i,label in ipairs(self.labels) do
        local py=(y+1+i*2)*8
        Font.draw(i==self.index and ">" or " ",16,py)
        Font.draw(tostring(label or ""),32,py)
      end
      love.graphics.setColor(1,1,1,1)
    end
    game.stack:push(menu)
  end

  local rocketQuestChunk,rocketQuestErr=loadfile(tostring(mod.path or "").."/rocket_quests.lua")
  if not rocketQuestChunk and love.filesystem and love.filesystem.load then
    rocketQuestChunk,rocketQuestErr=love.filesystem.load(tostring(mod.path or "").."/rocket_quests.lua")
  end
  assert(rocketQuestChunk,rocketQuestErr)
  local RocketQuests=rocketQuestChunk().new({
    data=pokopiaData,
    say=showBox,
    menu=rocketNativeMenu,
    tcgState=TCGServices.state,
    duel=TCGServices.duel,
  })

  local function cueBonesGame(game,done)
    local Font=require("src.render.Font")
    local Sound=require("src.core.Sound")
    local Assets=require("src.render.Assets")
    local Sprites=require("src.pokemon.Sprites")
    local state={isOpaque=true,die1=1,die2=1,total=2,point=nil,message="",finished=false}

    local cubonePic=nil
    do
      local path=Sprites.path(game.data,"CUBONE","front",{kind="battle"})
      if path then
        local ok,img=pcall(Assets.image,path)
        if ok then cubonePic=img end
      end
    end

    local boulderImage,boulderQuad=nil,nil
    do
      -- Read the stock boulder sheet directly. This works on both older and
      -- newer Gen1Recomp builds and avoids relying on optional renderer helper
      -- methods such as getPoseGeometry.
      local def=game.data.sprites and game.data.sprites.SPRITE_BOULDER
      if def and def.image then
        local ok,img=pcall(Assets.image,def.image)
        if ok and img then
          boulderImage=img
          local iw,ih=img:getDimensions()
          boulderQuad=love.graphics.newQuad(0,0,16,16,iw,ih)
        end
      end
    end

    local pips={
      [1]={{.5,.5}},
      [2]={{.27,.27},{.73,.73}},
      [3]={{.27,.27},{.5,.5},{.73,.73}},
      [4]={{.27,.27},{.73,.27},{.27,.73},{.73,.73}},
      [5]={{.27,.27},{.73,.27},{.5,.5},{.27,.73},{.73,.73}},
      [6]={{.27,.23},{.73,.23},{.27,.5},{.73,.5},{.27,.77},{.73,.77}},
    }

    local function drawDie(value,x,y)
      love.graphics.setColor(1,1,1,1)
      if boulderImage and boulderQuad then
        local scale=2
        love.graphics.draw(boulderImage,boulderQuad,x,y,0,scale,scale)
      else
        love.graphics.rectangle("line",x,y,32,32)
      end
      love.graphics.setColor(0,0,0,1)
      for _,pt in ipairs(pips[value] or {}) do
        love.graphics.circle("fill",x+pt[1]*32,y+pt[2]*32,2.5)
      end
      love.graphics.setColor(1,1,1,1)
    end

    local function finish(won,text)
      state.finished=true
      state.won=won
      state.message=text
      if won then
        local reward=300
        game.save.money=(tonumber(game.save.money) or 0)+reward
        local q=pokopiaData(game)
        q.cueBonesWins=(tonumber(q.cueBonesWins) or 0)+1
        RocketQuests.cueBonesWin(game)
        Sound.play(game.data,"Get_Item1")
        state.reward=reward
      end
    end

    local function roll()
      state.die1=love.math.random(1,6)
      state.die2=love.math.random(1,6)
      state.total=state.die1+state.die2
      Sound.play(game.data,"Press_AB")
      local n=state.total
      if not state.point then
        if n==7 or n==11 then
          finish(true,"NATURAL! YOU WIN")
        elseif n==2 or n==3 or n==12 then
          finish(false,"CRAPS - HOUSE WINS")
        else
          state.point=n
          state.message="HIT POINT BEFORE 7"
        end
      else
        if n==state.point then
          finish(true,"POINT! YOU WIN")
        elseif n==7 then
          finish(false,"SEVEN OUT - LOSE")
        else
          state.message="HIT POINT BEFORE 7"
        end
      end
    end

    function state:update()
      local input=game.input
      if self.finished then
        if input:wasPressed("a") or input:wasPressed("b") then
          Sound.play(game.data,"Press_AB")
          if game.stack:top()==self then game.stack:pop() end
          if self.won and self.reward then
            showBox(game,"You won $"..tostring(self.reward).."!",done,{speaker="ROCKET"})
          elseif done then done() end
        end
        return
      end
      if input:wasPressed("a") then roll()
      elseif input:wasPressed("b") then
        Sound.play(game.data,"Press_AB")
        if game.stack:top()==self then game.stack:pop() end
        if done then done() end
      end
    end

    function state:draw()
      local function center(text,y)
        text=tostring(text or "")
        local x=math.floor((160-#text*8)/2)
        if x<8 then x=8 end
        Font.draw(text,x,y)
      end

      love.graphics.push("all")
      love.graphics.clear(1,1,1,1)
      Font.drawBox(0,0,20,18)

      -- The native viewport is 160x144. Keep every label inside the 8..136
      -- content rows so nothing collides with the frame or gets cropped.
      love.graphics.setColor(0,0,0,1)
      center("CUE BONES",8)
      center("ROCKET STREET",24)
      Font.draw("------------------",8,32)

      love.graphics.setColor(1,1,1,1)
      if cubonePic then
        local iw,ih=cubonePic:getDimensions()
        local scale=math.min(52/iw,60/ih)
        love.graphics.draw(cubonePic,12,44,0,scale,scale)
      end
      drawDie(self.die1,80,48)
      drawDie(self.die2,120,48)

      love.graphics.setColor(0,0,0,1)
      Font.draw("TOTAL "..tostring(self.total),88,88)
      if self.point then center("POINT: "..tostring(self.point),104)
      else center("COME-OUT ROLL",104) end
      if self.message~="" then center(self.message,116) end
      if self.finished then center("A CONTINUE",128)
      else center("A ROLL   B QUIT",128) end

      love.graphics.setColor(1,1,1,1)
      love.graphics.pop()
    end
    game.stack:push(state)
  end

  local function cueBonesMenu(game,done)
    done=done or function() end
    local function openMenu()
      rocketNativeMenu(game,"CUE BONES",{"PLAY","RULES","LEAVE"},function(i)
        if i==1 then cueBonesGame(game,openMenu)
        elseif i==2 then
          showBox(game,
            "First roll is the\nCOME-OUT roll.\f"
            .."7 or 11 wins.\f"
            .."2, 3, or 12 loses.\f"
            .."Anything else sets\nyour POINT.\f"
            .."Hit the POINT\nbefore a 7 to win.",
            openMenu,{speaker="ROCKET"})
        else done() end
      end,done)
    end
    showBox(game,"We call it\nCUE BONES.\fSmall stakes.\nWant in?",openMenu,{speaker="ROCKET"})
  end

  -- The original Cue Bones board is present in every version of the lounge,
  -- including live map instances restored from an older save. Make it the
  -- canonical quest entry point so Operations never depends on finding a newly
  -- spawned terminal after a mod update.
  local function rocketBoardHub(game,done)
    done=done or function() end
    local function open()
      rocketNativeMenu(game,"ROCKET HQ",{"OPERATIONS","CUE BONES","LEAVE"},function(i)
        if i==1 then RocketQuests.board(game,open)
        elseif i==2 then cueBonesMenu(game,open)
        else done() end
      end,done)
    end
    showBox(game,"ROCKET HQ NOTICE BOARD\fShifts and orders.\nOff-duty games.",open,{speaker="DISPATCH"})
  end

  local function rocketHangoutTalk(game,ow,npc,done)
    done=done or function() end
    local name=npc and npc.def and npc.def.name or ""
    if RocketQuests.talk(game,name,done) then return end
    local lines={
      RH_GAMBLER_1="Point's set.\nOne clean roll.\fDon't jinx it.",
      RH_GAMBLER_2="I hold the pot.\nI settle disputes.\fTwo separate jobs.",
      RH_GAMBLER_3="CUE BONES beats\npatrol duty.\fDice stay quiet.",
      RH_WALKER_F="Came in from the\nCERULEAN route.\fCELADON pays more.\nBunks are closer.",
      RH_WALKER_M="Between shifts.\fAlarm rings?\nI wasn't sitting.",
      RH_LOUNGE_F="Cards after chow?\fI'm in.\nNo marked decks.",
      RH_LOUNGE_M="Roof watch again.\fCold air.\nQuiet shift.",
      RH_PACER_M="I check the floor\nbefore each shift.\fLoose doors mean\nbig problems.",
      RH_B1_MECHANIC="Lift motor catches\non the way down.\fI can fix it.\nNo helpers.",
      RH_B1_BOOKIE="CUE BONES pot is\nkept small.\fBig pots make\nsore losers.",
      RH_B1_COOK="Stew's hot until\nmidnight.\fThen it's noodles.",
      RH_B2_NIGHTSHIFT="Night shift starts\nat closing time.\fThen the base gets\nquiet.",
      RH_B2_LAUNDRY="Uniforms left.\nTowels right.\fPOKe BALL pocket?\nYou explain it.",
      RH_B2_RECRUITER="New grunts report\nhere for a locker.\fThen I teach the\nstair layout.",
      RH_B2_SNORER="Wake me before\nroll call.\fFive if the BOSS\nis coming.",
      RH_B2_QUARTERMASTER="Sign gear out.\nBring it back.\fI count it all\nat shift's end.",
      RH_B3_TECH="Monitor feed is\nstable again.\fDon't kick it.\nOld repair trick.",
      RH_B3_CHANNELSURFER="LEAGUE match after\nthe news.\fBig couch is ours.",
      RH_B3_CARDPLAYER="Testing a new deck\nbetween shifts.\fWins just enough\nto keep me at it.",
      RH_B3_TRAINEE="B4F in under a\nminute now.\fNext: do it with\na crate.",
      RH_B3_JANITOR="Feet off couches.\nNo console drinks.\fI keep writing\nthat same sign.",
      RH_B4_ARCHIVIST="Old jobs here.\nSupply logs there.\fNo date? Back to\nthe writer.",
      RH_B4_MEDIC="Burns or bites?\nSit down.\fWorse than that?\nGo upstairs.",
      RH_B4_LOOKOUT="North feed clear.\nLift feed clear.\fI'll call if that\nchanges.",
      RH_B4_ACCOUNTANT="Front receipts.\fHideout books stay\nseparate.",
      RH_B4_VETERAN="Used to be all\nbusiness here.\fCouch and hot food\nhelp morale.",
      RH_B4_SLEEPER="Second shift.\fWake me when the\nlift lamp is on.",
      RH_ZUBAT="ZUBAT circles the\nrafters, clicking.\fKnows every echo\nin this place.",
      RH_RATICATE="RATICATE checks\nthe pantry.\fIt's guarding\nthe snacks.",
      RH_CUBONE="CUBONE sits by the\ncard table.\fIt buffs the club.\nHandle worn down.",
      RH_EKANS="EKANS curls under\na chair.\fIt lifts its head\nat each footstep.",
      RH_MURKROW="MURKROW watches\nfrom a cabinet.\fShiny trinkets sit\nbeside it.",
      RH_HOUNDOUR="HOUNDOUR patrols\nthe bunk aisle.\fIt checks every\nopen locker.",
      RH_DROWZEE="DROWZEE sways by\nthe bunks.\fThe room feels\nquieter nearby.",
      RH_GOLBAT="GOLBAT hangs above\nthe common room.\fThe TV doesn't\nbother it.",
      RH_ARBOK="ARBOK rests by the\nworkshop wall.\fThe techs give it\nroom.",
      RH_HOUNDOOM="HOUNDOOM watches\nthe records room.\fIt tracks each\nstranger.",
      RH_VILEPLUME="VILEPLUME rests\nby a lounge lamp.\fThe air smells\nsweet nearby.",
      RH_BOARD="CUE BONES",
      RH_DISPATCH="ROCKET OPERATIONS",
      RH_HYPNO="HYPNO waits by the\ndream-test rig.\fIt doesn't move.",
      RH_TV="A late-night\nLEAGUE replay.",
      RH_BED="A neat bunk.\fBlack uniform\nat the foot.",
      RH_CHAIR="A worn chair.\fBoth arms were\nrepaired.",
      RH_TABLE="Cards and mugs.\fShift reports fill\nthe table.",
    }
    if name=="RH_BOARD" then
      rocketBoardHub(game,done)
      return
    end
    local text=lines[name] or "The ROCKET is taking it easy."
    local pokemonSpeakers={
      RH_ZUBAT="ZUBAT",RH_RATICATE="RATICATE",RH_CUBONE="CUBONE",
      RH_EKANS="EKANS",RH_MURKROW="MURKROW",RH_HOUNDOUR="HOUNDOUR",
      RH_DROWZEE="DROWZEE",RH_GOLBAT="GOLBAT",RH_ARBOK="ARBOK",
      RH_HOUNDOOM="HOUNDOOM",RH_VILEPLUME="VILEPLUME",RH_HYPNO="HYPNO",
    }
    local speaker=pokemonSpeakers[name]
    if not speaker then
      if name=="RH_BOARD" then speaker="GAME BOARD"
      elseif name=="RH_DISPATCH" then speaker="DISPATCH"
      else speaker="ROCKET" end
    end
    showBox(game,text,done,{speaker=speaker})
  end

  local function applyRocketHomeLayoutLive(ow)
    if not (ow and ow.map and ow.replaceBlock) then return end
    local plan=ROCKET_HOME_LAYOUTS[ow.map.id]
    if not plan then return end

    -- Belt-and-suspenders live-map pass. Some render/world pipelines clone the
    -- vanilla map before mod content overrides settle; applying the exact same
    -- room plan on entry guarantees the player cannot ever receive the old
    -- spinner maze. Native warp blocks are excluded exactly as in the authored
    -- pass, so stairs and elevator pads keep their original behavior.
    local keep=rocketHomeWarpBlocks(ow.map)
    local mapDef=ow.map.def or {}
    local mapWidth=tonumber(mapDef.width or ow.map.width)
    local mapHeight=tonumber(mapDef.height or ow.map.height)
    if not (mapWidth and mapHeight) then return end

    local function setBlock(bx,by,block)
      if bx<0 or by<0 or bx>=mapWidth or by>=mapHeight then return end
      if keep[rocketHomeBlockKey(bx,by)] then return end
      ow:replaceBlock(bx,by,block)
    end
    for _,r in ipairs(plan.clear or {}) do
      for by=r[3],r[4] do
        for bx=r[1],r[2] do setBlock(bx,by,ROCKET_HOME_FLOOR) end
      end
    end
    for _,f in ipairs(plan.furniture or {}) do
      setBlock(f[1],f[2],f[3])
    end
    ow._pokopiaRocketHomeLayoutApplied=true

    -- Invalidate persistent voxel/runtime geometry after the whole batch. This
    -- is the same reload signal used by the Gym remodel and prevents a cached
    -- pre-remodel mesh from visually retaining spinner walls or arrows.
    local ok,Runtime=pcall(require,"src.mods.Runtime")
    if ok and Runtime and Runtime.emit then
      Runtime.emit("map.reloaded",{
        mapId=ow.map.id,map=ow.map,reason="pokopia_rocket_home",
      })
    end
  end

  local function prepareRocketHangoutFloor(game,ow)
    if not (ow and ow.map and ROCKET_HANGOUT_MAPS[ow.map.id]) then return end
    applyRocketHomeLayoutLive(ow)
    -- All four basement floors are usable again. After geometry reconciliation,
    -- strip only the old battle actors; all stairs/elevator warps remain live.
    for i=#(ow.npcs or {}),1,-1 do
      local n=ow.npcs[i]
      local d=n and n.def
      if d and not d.runtime
          and (d.sprite=="SPRITE_ROCKET" or d.sprite=="SPRITE_GIOVANNI") then
        table.remove(ow.npcs,i)
        for j=#(ow.entities or {}),1,-1 do
          if ow.entities[j]==n then table.remove(ow.entities,j) end
        end
      end
    end
  end

  local function ensureRocketHangout(game,ow)
    if not (ow and ow.map and ROCKET_HANGOUT_MAPS[ow.map.id]) then return end
    prepareRocketHangoutFloor(game,ow)

    -- Reconcile the runtime hangout cast from scratch on entry. This prevents
    -- hot-reload/save remnants from ever producing duplicate Pokemon or a
    -- partially spawned lounge. There will be exactly one of each named actor.
    for i=#(ow.npcs or {}),1,-1 do
      local n=ow.npcs[i]
      local name=n and n.def and n.def.name
      if name and tostring(name):find("RH_",1,true)==1 then
        table.remove(ow.npcs,i)
        for j=#(ow.entities or {}),1,-1 do
          if ow.entities[j]==n then table.remove(ow.entities,j) end
        end
      end
    end

    local NPC=require("src.world.NPC")
    local id=ow.map.id

    -- Build the exact connected set of walkable floor cells the player can
    -- reach from the Game Corner entrance. Any sealed/locked room is excluded
    -- automatically, even if a preferred spawn coordinate happens to be in it.
    local reachable={}
    local function cellKey(x,y) return tostring(x)..":"..tostring(y) end
    do
      local map=ow.map
      -- Seed from the player's actual entry position. That makes the allowed
      -- spawn region exactly the floor the player can currently reach, even
      -- if another mod changes the entrance coordinates or door geometry.
      local seedX,seedY=21,2
      if ow.player then
        seedX,seedY=ow.player.cellX,ow.player.cellY
      end
      local queue={{seedX,seedY}}
      local qi=1
      reachable[cellKey(seedX,seedY)]=true
      local dirs={{0,-1},{0,1},{-1,0},{1,0}}
      while queue[qi] do
        local x,y=queue[qi][1],queue[qi][2]
        qi=qi+1
        for _,d in ipairs(dirs) do
          local nx,ny=x+d[1],y+d[2]
          local k=cellKey(nx,ny)
          if not reachable[k] and map:inBounds(nx,ny)
              and map:isWalkableCell(nx,ny) then
            reachable[k]=true
            queue[#queue+1]={nx,ny}
          end
        end
      end
    end

    local reserved={}
    local function occupied(x,y)
      if reserved[cellKey(x,y)] then return true end
      for _,n in ipairs(ow.npcs or {}) do
        if n and n.cellX==x and n.cellY==y then return true end
      end
      return false
    end

    local function nearestReachable(px,py)
      local map=ow.map
      local queue={{px,py}}
      local qi=1
      local seen={[cellKey(px,py)]=true}
      local dirs={{0,-1},{0,1},{-1,0},{1,0}}
      while queue[qi] do
        local x,y=queue[qi][1],queue[qi][2]
        qi=qi+1
        local k=cellKey(x,y)
        if reachable[k] and map:isWalkableCell(x,y)
            and not map:warpAtCell(x,y) and not occupied(x,y) then
          return x,y
        end
        for _,d in ipairs(dirs) do
          local nx,ny=x+d[1],y+d[2]
          local nk=cellKey(nx,ny)
          if not seen[nk] and map:inBounds(nx,ny) then
            seen[nk]=true
            queue[#queue+1]={nx,ny}
          end
        end
      end
      return nil,nil
    end

    local function spawn(name,sprite,x,y,facing,walk,passable)
      local sx,sy=nearestReachable(x,y)
      if sx==nil or not game.data.sprites[sprite] then return nil end
      reserved[cellKey(sx,sy)]=true
      local n=NPC.new(game.data,ow.map.id,{
        index=300+#(ow.npcs or {}),name=name,sprite=sprite,
        text="TEXT_POKOPIA_ROCKET_HANGOUT",movement=walk and "WALK" or "STAY",
        range=walk and "ALL" or "NONE",x=sx,y=sy,runtime=true,
      })
      n.facing=facing or "down"; n.wanders=walk and true or false
      n.frozen=false; n.passable=passable and true or false; n.stepFrames=10
      table.insert(ow.npcs,n); table.insert(ow.entities,n)
      return n
    end

    if id=="ROCKET_HIDEOUT_B1F" then
      -- Recreation / dining floor. Stationary people are placed where a person
      -- would actually stop: around the table, beside the lounge, at the east
      -- dispatch nook and behind the kitchen line. Walkers start in clear lanes.
      spawn("RH_BOARD","SPRITE_POKEDEX",25,13,"left",false,true)
      spawn("RH_DISPATCH","SPRITE_POKEDEX",27,13,"left",false,true)
      spawn("RH_GAMBLER_1","SPRITE_ROCKET",14,15,"down",false)
      spawn("RH_GAMBLER_2","POKOPIA_ROCKET_GIRL",18,15,"down",false)
      spawn("RH_GAMBLER_3","SPRITE_ROCKET",16,13,"down",false)
      spawn("RH_LOUNGE_F","POKOPIA_ROCKET_GIRL",13,15,"up",false)
      spawn("RH_B1_MECHANIC","SPRITE_ROCKET",10,7,"right",true)
      spawn("RH_B1_BOOKIE","POKOPIA_ROCKET_GIRL",24,15,"up",true)
      spawn("RH_B1_COOK","SPRITE_ROCKET",14,25,"up",true)
      spawn("RH_ZUBAT",ZUBAT,20,10,"left",true)
      spawn("RH_EKANS",EKANS,13,14,"right",true)
      spawn("RH_MURKROW",MURKROW,27,15,"left",true)

    elseif id=="ROCKET_HIDEOUT_B2F" then
      -- Barracks. Nobody stands on a bunk or in the stair lane: sleepers stay
      -- near beds, laundry/kitchen staff stay south, and the quartermaster owns
      -- the east office.
      spawn("RH_WALKER_M","SPRITE_ROCKET",11,12,"right",true)
      spawn("RH_WALKER_F","POKOPIA_ROCKET_GIRL",19,17,"left",true)
      spawn("RH_B2_NIGHTSHIFT","SPRITE_ROCKET",5,18,"down",true)
      spawn("RH_B2_LAUNDRY","POKOPIA_ROCKET_GIRL",7,19,"right",true)
      spawn("RH_B2_RECRUITER","SPRITE_ROCKET",11,17,"down",true)
      spawn("RH_B2_SNORER","SPRITE_ROCKET",5,10,"down",false)
      spawn("RH_B2_QUARTERMASTER","POKOPIA_ROCKET_GIRL",25,16,"up",false)
      spawn("RH_RATICATE",RATICATE,9,24,"right",true)
      spawn("RH_HOUNDOUR",HOUNDOUR,7,25,"left",true)
      spawn("RH_DROWZEE",DROWZEE,15,12,"down",true)

    elseif id=="ROCKET_HIDEOUT_B3F" then
      -- Common room / workshop. TV watchers cluster near the lounge, card
      -- players use the east tables, and technicians occupy the lower work area.
      spawn("RH_PACER_M","SPRITE_ROCKET",20,18,"left",true)
      spawn("RH_LOUNGE_M","SPRITE_ROCKET",20,14,"up",false)
      spawn("RH_B3_TECH","POKOPIA_ROCKET_GIRL",12,19,"up",false)
      spawn("RH_B3_CHANNELSURFER","SPRITE_ROCKET",16,15,"up",false)
      spawn("RH_B3_CARDPLAYER","POKOPIA_ROCKET_GIRL",23,15,"up",true)
      spawn("RH_B3_TRAINEE","SPRITE_ROCKET",24,16,"left",true)
      spawn("RH_B3_JANITOR","SPRITE_ROCKET",17,24,"left",true)
      spawn("RH_CUBONE",CUBONE,25,15,"left",false)
      spawn("RH_GOLBAT",GOLBAT,18,8,"down",true)
      spawn("RH_ARBOK",ARBOK,20,17,"left",true)

    elseif id=="ROCKET_HIDEOUT_B4F" then
      -- Quiet floor. The medic/sleeper stay near beds, archive staff remain by
      -- the records wall, and the veteran/kitchen traffic stays in the south.
      spawn("RH_HYPNO",HYPNO,17,7,"down",false)
      spawn("RH_B4_ARCHIVIST","POKOPIA_ROCKET_GIRL",13,12,"up",false)
      spawn("RH_B4_MEDIC","POKOPIA_ROCKET_GIRL",23,8,"left",true)
      spawn("RH_B4_LOOKOUT","SPRITE_ROCKET",25,10,"left",true)
      spawn("RH_B4_ACCOUNTANT","SPRITE_ROCKET",17,12,"up",false)
      spawn("RH_B4_VETERAN","SPRITE_ROCKET",19,20,"up",true)
      spawn("RH_B4_SLEEPER","POKOPIA_ROCKET_GIRL",19,8,"down",false)
      spawn("RH_HOUNDOOM",HOUNDOOM,19,13,"left",true)
      spawn("RH_VILEPLUME",VILEPLUME,11,17,"right",true)
    end
  end

  for mapId,_ in pairs(ROCKET_HANGOUT_MAPS) do
    local base=mod.content.map_scripts:get(mapId) or {}
    local record={}
    for k,v in pairs(base) do record[k]=v end
    record.talk={}
    for k,v in pairs(base.talk or {}) do record.talk[k]=v end
    record.talk.TEXT_POKOPIA_ROCKET_HANGOUT=rocketHangoutTalk
    record.talk.TEXT_POKOPIA_ROCKET_OPERATIONS=function(game,ow,npc,done)
      RocketQuests.board(game,done or function() end)
    end
    record.talk.TEXT_POKOPIA_ROCKET_LOWER_CLOSED=function(game,ow,npc,done)
      showBox(game,"LOWER FLOORS CLOSED.\f"
        .."ROCKET: Nothing down there\nyou need to see.",
        done or function() end,{speaker="ROCKET"})
    end
    local originalOnEnter=base.onEnter
    record.onEnter=function(game,ow,...)
      if originalOnEnter then originalOnEnter(game,ow,...) end
      ensureRocketHangout(game,ow)
    end
    mod.content.map_scripts:override(mapId,record)
  end

  -- The Game Corner poster is now decorative flavor only. Set the hideout
  -- event before vanilla onEnter runs, force the open staircase block again
  -- after it runs, and replace the poster script so pressing A never plays the
  -- old switch sequence or changes geometry.
  do
    local base=mod.content.map_scripts:get("GAME_CORNER") or {}
    local record={}
    for k,v in pairs(base) do record[k]=v end
    record.talk={}
    for k,v in pairs(base.talk or {}) do record.talk[k]=v end
    record.talk.TEXT_GAMECORNER_POSTER=function(game,ow,npc,done)
      showBox(game,"Home Sweet Home!",done or function() end,{speaker="POSTER"})
    end
    local originalOnEnter=base.onEnter
    record.onEnter=function(game,ow,...)
      game.save.flags=game.save.flags or {}
      local poster=game.data.field and game.data.field.gameCornerPoster
      if poster then game.save.flags[poster.event]=true end
      if originalOnEnter then originalOnEnter(game,ow,...) end
      if poster and ow and ow.map and ow.map.id=="GAME_CORNER" then
        ow:replaceBlock(poster.x,poster.y,poster.openBlock)
      end
    end
    mod.content.map_scripts:override("GAME_CORNER",record)
  end

  --------------------------------------------------------------------------
  -- Celadon Gym: reactive transformation room + south barrier opening.
  --------------------------------------------------------------------------
  local CELADON_GYM_TALK_KEYS={
    "TEXT_CELADONGYM_ERIKA",
    "TEXT_CELADONGYM_COOLTRAINER_F1",
    "TEXT_CELADONGYM_BEAUTY1",
    "TEXT_CELADONGYM_COOLTRAINER_F2",
    "TEXT_CELADONGYM_BEAUTY2",
    "TEXT_CELADONGYM_COOLTRAINER_F3",
    "TEXT_CELADONGYM_BEAUTY3",
    "TEXT_CELADONGYM_COOLTRAINER_F4",
  }

  local CELADON_GYM_POSITIONS={
    ["4:3"]=true,["2:11"]=true,["7:10"]=true,["9:5"]=true,
    ["1:5"]=true,["6:3"]=true,["3:3"]=true,["5:3"]=true,
  }

  local function removeEntityRef(ow,npc)
    for i=#(ow.entities or {}),1,-1 do
      if ow.entities[i]==npc then table.remove(ow.entities,i) end
    end
  end

  local function removeGymNpc(ow,npc)
    for i=#(ow.npcs or {}),1,-1 do
      if ow.npcs[i]==npc then table.remove(ow.npcs,i) break end
    end
    removeEntityRef(ow,npc)
  end

  local function gymNpcAt(ow,x,y)
    for _,npc in ipairs(ow.npcs or {}) do
      if npc.cellX==x and npc.cellY==y then return npc end
    end
  end

  local function notifyPokopiaGeometryChanged(ow,reason)
    if not (ow and ow.map and ow.map.id) then return end
    -- Dramatic Shape Voxel Mod keeps a persistent/runtime mesh cache.
    -- replaceBlock announces individual edits, but a batch of authored Pokopia
    -- geometry can race a mesh restored from disk. A non-color map reload
    -- notification makes voxel renderers evict that runtime mesh and rebuild
    -- against the final live block layer/fingerprint. Vanilla ignores this.
    local ok,Runtime=pcall(require,"src.mods.Runtime")
    if ok and Runtime and Runtime.emit then
      Runtime.emit("map.reloaded",{mapId=ow.map.id,map=ow.map,reason=reason or "pokopia_geometry"})
    end
  end

  local function removeCeladonGymTrees(ow)
    if not (ow and ow.map and ow.map.id=="CELADON_GYM") then return end
    -- Vanilla GYM cut-tree blocks use the same swaps as Cut in pokered:
    -- $3C->$35, $3F->$35, $3D->$36. Apply the swaps across the authored
    -- Celadon Gym blockmap so both the tree artwork and its collision vanish.
    local swaps={[0x3c]=0x35,[0x3f]=0x35,[0x3d]=0x36}
    local def=ow.map.def
    local changed=false
    for by=0,(def.height or 0)-1 do
      for bx=0,(def.width or 0)-1 do
        local block=ow.map:blockAt(bx,by)
        local replacement=swaps[block]
        if replacement and replacement~=block then
          ow:replaceBlock(bx,by,replacement)
          changed=true
        end
      end
    end
    ow.map._pokopiaGymTreesRemoved=true
    if changed then notifyPokopiaGeometryChanged(ow,"pokopia_geometry") end
  end

  local function ensureCeladonGymCast(game,ow)
    if not (ow and ow.map and ow.map.id=="CELADON_GYM") then return end
    removeCeladonGymTrees(ow)
    local q=pokopiaData(game)

    if q.celadonGymGhostScare then
      for i=#(ow.npcs or {}),1,-1 do
        local n=ow.npcs[i]
        if CELADON_GYM_POSITIONS[tostring(n.cellX)..":"..tostring(n.cellY)] then
          table.remove(ow.npcs,i)
          removeEntityRef(ow,n)
        end
      end
      return
    end

    -- Erika is gone in Pokopia. Keep her authored leader position but replace
    -- her with an ordinary female gym attendant. OLD WOMAN uses Erika's own
    -- Gen-I overworld silhouette separately (SPRITE_SILPH_WORKER_F).
    local oldLeader=gymNpcAt(ow,4,3)
    if oldLeader and not (oldLeader.def and oldLeader.def.name=="CELADON_GYM_ATTENDANT") then
      removeGymNpc(ow,oldLeader)
      oldLeader=nil
    end
    if not oldLeader then
      local n=makeQuestNpc(game,ow,9401,"CELADON_GYM_ATTENDANT",
        "SPRITE_GIRL",4,3,"down","TEXT_CELADONGYM_ERIKA")
      n.stepFrames=8
    end

    -- No one in this room battles Ditto. The global trainer stripping remains
    -- in force, and these actors are explicitly frozen/non-trainer for builds
    -- whose map objects retain trainer metadata at runtime.
    for _,n in ipairs(ow.npcs or {}) do
      if CELADON_GYM_POSITIONS[tostring(n.cellX)..":"..tostring(n.cellY)] then
        n.wanders=false
        n.frozen=true
        n.trainer=nil
        n.trainerClass=nil
        n.partyIndex=nil
        if n.def then
          n.def.trainer=nil
          n.def.trainerClass=nil
          n.def.partyIndex=nil
        end
      end
    end
  end

  local function removeCeladonSouthGymBarriers(ow)
    if not (ow and ow.map and ow.map.id=="CELADON_CITY") then return end
    -- The supplied coordinate references place Ditto at X=22,Y=31 and
    -- X=26,Y=31 immediately north of the barrier strip. Those cells lie over
    -- block columns 11..13; the blocking tree/bush strip itself is block row
    -- 16 (cells Y=32..33). Replace exactly that three-block span with Celadon's
    -- normal open-ground block 0x55, leaving the rest of the southern border.
    local changed=false
    for bx=11,13 do
      if ow.map:blockAt(bx,16)~=0x55 then
        ow:replaceBlock(bx,16,0x55)
        changed=true
      end
    end
    ow.map._pokopiaGymSouthOpening=true
    if changed then notifyPokopiaGeometryChanged(ow,"pokopia_geometry") end
  end

  local function gymFormLabel(q)
    local form=(q and q.currentForm) or "DITTO"
    return tostring(form):gsub("_"," ")
  end

  local GYM_REACTIONS={
    DITTO="A DITTO in the GYM?\fYou're a curious little\nvisitor, aren't you?",
    PERSIAN="A PERSIAN?\fYou carry yourself like\nyou own the place.",
    ELECTRODE="An ELECTRODE?!\fCareful around the\nflower beds!",
    SCALPER="You look familiar...\fWeren't you hanging\naround the card line?",
    HITMONLEE="HITMONLEE in a GRASS\nGYM?\fThat's certainly bold.",
    HITMONCHAN="HITMONCHAN in a GRASS\nGYM?\fThat's certainly bold.",
    PORYGON="PORYGON?\fI've never seen one\ninside this GYM before.",
  }

  local function runCeladonGymAway(game,ow)
    local q=pokopiaData(game)
    if q.celadonGymGhostScare then return end
    -- Commit first so re-entry/reload cannot resurrect the cast midway.
    q.celadonGymGhostScare=true

    local runners={}
    for _,n in ipairs(ow.npcs or {}) do
      if CELADON_GYM_POSITIONS[tostring(n.cellX)..":"..tostring(n.cellY)] then
        runners[#runners+1]=n
        n.frozen=false
        n.wanders=false
        -- Passable runners do not block one another, so every route can begin
        -- on the same frame and the whole room evacuates as one crowd.
        n.passable=true
        n.stepFrames=4
      end
    end

    if ow.player then ow.player.inputLocked=true end
    if #runners==0 then
      if ow.player then ow.player.inputLocked=false end
      return
    end

    local remaining=#runners
    local function runnerDone(n)
      removeGymNpc(ow,n)
      remaining=remaining-1
      if remaining<=0 and ow.player then ow.player.inputLocked=false end
    end

    -- Launch all runners at once. Because they are passable during this
    -- scripted panic, pathing/movement cannot serialize behind another NPC.
    for _,n in ipairs(runners) do
      walkNpcOutOfRoom(ow,n,function()
        runnerDone(n)
      end)
    end
  end

  local function celadonGymReactiveTalk(game,ow,npc,done)
    done=done or function() end
    local TextBox=require("src.render.TextBox")
    local q=pokopiaData(game)
    if q.celadonGymGhostScare then done(); return end

    if q.currentForm=="OLD_WOMAN" then
      game.stack:push(TextBox.new(game,
        "Lady Erika?\fBut you died 20\nyears ago...\fGHOST!\fIt's a ghost!",
        function()
          runCeladonGymAway(game,ow)
          done()
        end,{speaker="GYM TRAINER",portrait={speaker="BEAUTY",expression="Normal"}}))
      return
    end

    local form=gymFormLabel(q)
    local text=GYM_REACTIONS[q.currentForm or "DITTO"]
      or (form.."?\fThat's quite a form,\nDITTO.")
    game.stack:push(TextBox.new(game,text,done,{
      speaker="GYM TRAINER",portrait={speaker="BEAUTY",expression="Normal"},
    }))
  end

  do
    local base=mod.content.map_scripts:get("CELADON_GYM") or {}
    local record={}
    for k,v in pairs(base) do record[k]=v end
    local originalOnEnter=base.onEnter
    record.onEnter=function(game,ow,...)
      if originalOnEnter then originalOnEnter(game,ow,...) end
      ensureCeladonGymCast(game,ow)
    end
    record.talk={}
    for k,v in pairs(base.talk or {}) do record.talk[k]=v end
    for _,key in ipairs(CELADON_GYM_TALK_KEYS) do
      record.talk[key]=celadonGymReactiveTalk
    end
    mod.content.map_scripts:override("CELADON_GYM",record)
  end

  --------------------------------------------------------------------------
  -- Erika's ghost / Rainbow Badge epilogue.
  -- After OLD WOMAN scares the Celadon Gym staff away, the next return to the
  -- outdoor city produces Erika's spirit once.  Her sprite is her original
  -- Gen-I overworld silhouette, recolored with an inverted grayscale OBJ ramp:
  -- transparent color 0 plus three visible grays, deliberately never black.
  --------------------------------------------------------------------------
  local ERIKA_GHOST_NAME="CELADON_ERIKA_GHOST"
  local ERIKA_GHOST_TEXT="TEXT_POKOPIA_ERIKA_GHOST"
  local CELADON_GYM_CLOSED_TEXT="TEXT_POKOPIA_CELADON_GYM_CLOSED"
  local CELADON_GYM_DOOR_X,CELADON_GYM_DOOR_Y=12,27

  local function removeNamedNpc(ow,name)
    for i=#(ow.npcs or {}),1,-1 do
      local n=ow.npcs[i]
      if n and n.def and n.def.name==name then
        table.remove(ow.npcs,i)
        removeEntityRef(ow,n)
      end
    end
  end

  local function applyCeladonGymClosure(game,ow)
    if not (ow and ow.map and ow.map.id=="CELADON_CITY") then return end
    local q=pokopiaData(game)
    if not q.erikaGhostResolved then return end

    local map=ow.map
    local key=CELADON_GYM_DOOR_Y*map.widthCells+CELADON_GYM_DOOR_X

    -- The authored warp is removed from the live map every time Celadon loads.
    -- Keep the doorway itself solid so walking into it bumps like a locked
    -- entrance; A against the door reads the closure notice below.
    map.warpAt[key]=nil
    map.signAt[key]={
      x=CELADON_GYM_DOOR_X,y=CELADON_GYM_DOOR_Y,
      text=CELADON_GYM_CLOSED_TEXT,
    }
    if not map._pokopiaGymClosedWalkableWrapped then
      local originalIsWalkableCell=map.isWalkableCell
      map.isWalkableCell=function(self,x,y)
        if x==CELADON_GYM_DOOR_X and y==CELADON_GYM_DOOR_Y then return false end
        return originalIsWalkableCell(self,x,y)
      end
      map._pokopiaGymClosedWalkableWrapped=true
    end
  end

  local function grantRainbowBadge(game)
    game.save.inventory=game.save.inventory or {}
    -- Badges.count uses these inventory keys directly. Boolean true matches
    -- vanilla Gen1Recomp badge saves and cannot be duplicated as a quantity.
    game.save.inventory.RAINBOWBADGE=true
  end

  local function finishErikaGhost(game,ow,ghost)
    local q=pokopiaData(game)
    if q.erikaGhostResolved then return end
    -- Commit completion before the fade so reloads cannot replay the
    -- encounter or grant the badge through a second completion path.
    q.erikaGhostResolved=true
    q.erikaGhostPending=nil

    -- Use Gen1Recomp's native script fade. Erika remains visible during the
    -- fade-out, disappears only at full black, then the city fades back in.
    local Transition=require("src.render.Transition")
    game.stack:push(Transition.new(game,function()
      grantRainbowBadge(game)
      removeNamedNpc(ow,ERIKA_GHOST_NAME)
      applyCeladonGymClosure(game,ow)
    end,function()
      showBox(game,
        "DITTO received the\nRAINBOW BADGE!",
        function()
          if ow and ow.player then ow.player.inputLocked=false end
        end,{speaker="RAINBOW BADGE"})
    end,false))
  end

  local function erikaGhostTalk(game,ow,npc,done)
    done=done or function() end
    local q=pokopiaData(game)
    if q.erikaGhostResolved then done(); return end
    if ow and ow.player then ow.player.inputLocked=true end
    if npc and npc.facePlayer and ow and ow.player then npc:facePlayer(ow.player) end

    showBox(game,
      "CELADON...\f"
      .."I hardly recognize\nwhat it has become.\f"
      .."So much noise.\nSo much greed.\f"
      .."People forgetting what\nonce made this city\nbeautiful.\f"
      .."But I can still see\nkindness taking root.\f"
      .."Flowers grow back,\neven after a hard\nseason.\f"
      .."Take care of CELADON.\f"
      .."I think its best days\nmay still be ahead.",
      function()
        finishErikaGhost(game,ow,npc)
        done()
      end,{speaker="ERIKA"})
  end

  local function ensureErikaGhost(game,ow)
    if not (ow and ow.map and ow.map.id=="CELADON_CITY") then return end
    local q=pokopiaData(game)
    if not q.celadonGymGhostScare or q.erikaGhostResolved then
      removeNamedNpc(ow,ERIKA_GHOST_NAME)
      return
    end

    local ghost=nil
    for _,n in ipairs(ow.npcs or {}) do
      if n and n.def and n.def.name==ERIKA_GHOST_NAME then ghost=n; break end
    end
    if not ghost then
      -- Just south of the Gym door, centered in the open approach so Erika is
      -- immediately visible when Ditto walks back outside.
      ghost=makeQuestNpc(game,ow,9410,ERIKA_GHOST_NAME,
        "SPRITE_SILPH_WORKER_F",12,29,"up",ERIKA_GHOST_TEXT)
      ghost.frozen=true
      ghost.wanders=false
      ghost.passable=false
      if ghost.sprite and ghost.sprite.setObjPalette then
        ghost.sprite:setObjPalette({
          {255,255,255}, -- OBJ color 0: transparent
          {80,80,80},   -- source light shade -> dark gray
          {156,156,156},
          {240,240,240},-- source darkest shade -> near-white (inverted)
        },"pokopia_erika_ghost_inverted_gray")
      end
    end

    -- Trigger once automatically after the outdoor map has settled.  The
    -- pending bit prevents repeated callbacks if Celadon onEnter is re-fired.
    if not q.erikaGhostPending then
      q.erikaGhostPending=true
      if ow.player then ow.player.inputLocked=true end
      defer(8,function()
        local liveQ=pokopiaData(game)
        if liveQ.erikaGhostResolved then return end
        if not (ow and ow.map and ow.map.id=="CELADON_CITY") then
          liveQ.erikaGhostPending=nil
          return
        end
        erikaGhostTalk(game,ow,ghost,function() end)
      end)
    end
  end

  -- Extend the existing Celadon-city script instead of replacing its other
  -- story/cafe/card-line behavior. The opening is re-applied on every entry so
  -- map reloads cannot restore the authored southern barrier strip. Once the
  -- ghost epilogue has completed, the Gym doorway is permanently non-warping
  -- and exposes a normal A-button sign interaction.
  do
    local base=mod.content.map_scripts:get("CELADON_CITY") or {}
    local record={}
    for k,v in pairs(base) do record[k]=v end
    local originalOnEnter=base.onEnter
    record.onEnter=function(game,ow,...)
      if originalOnEnter then originalOnEnter(game,ow,...) end
      removeCeladonSouthGymBarriers(ow)
      applyCeladonGymClosure(game,ow)
      ensureErikaGhost(game,ow)
    end
    record.talk={}
    for k,v in pairs(base.talk or {}) do record.talk[k]=v end
    record.talk[ERIKA_GHOST_TEXT]=erikaGhostTalk
    record.talk[CELADON_GYM_CLOSED_TEXT]=function(game,ow,npc,done)
      showBox(game,"CLOSED UNTIL\nFURTHER NOTICE",done or function() end)
    end
    mod.content.map_scripts:override("CELADON_CITY",record)
  end

  --------------------------------------------------------------------------
  -- Celadon Prize Room: Pokopia post-refund prize exchange.
  -- Three vanilla counter windows all use the same reduced catalog.
  --------------------------------------------------------------------------
  local function pokopiaPrizeCounter(game,ow,npc,done)
    done=done or function() end
    local q=normalizePokopiaSave(game.save)
    local TextBox=require("src.render.TextBox")
    local Bag=require("src.inventory.Bag")
    local Font=require("src.render.Font")
    local Sound=require("src.core.Sound")

    local function resultBox(text,speaker)
      game.stack:push(TextBox.new(game,text,done,{
        speaker=speaker or "PRIZE LADY",
        portrait={speaker=speaker or "PRIZE LADY",expression="Normal"},
      }))
    end

    local function activateOwnedPorygon()
      local changed=applyDittoForm(game,"PORYGON",ow)
      if changed then
        q.currentForm="PORYGON"
        q.requestedForm="PORYGON"
      end
      resultBox("DITTO transformed into\nPORYGON!","DITTO")
    end

    local function buyLemonade()
      if (game.save.coins or 0)<100 then
        resultBox("PRIZE LADY: You'll need\nmore COINS for that.")
        return
      end
      if not Bag.add(game.save,"LEMONADE",1,game.data) then
        resultBox("PRIZE LADY: Your BAG\nis full.")
        return
      end
      game.save.coins=(game.save.coins or 0)-100
      Sound.play(game.data,"Get_Item1")
      resultBox("DITTO received\nLEMONADE!")
    end

    local function buyCardPack()
      if not q.cardQuestComplete then
        resultBox("PRIZE LADY: CARD PACKS\naren't available yet.")
        return
      end

      local rows={
        {label="COLOSSEUM",key="COLOSSEUM"},
        {label="EVOLUTION",key="EVOLUTION"},
        {label="MYSTERY",key="MYSTERY"},
        {label="LABORATORY",key="LABORATORY"},
        {label="CANCEL",cancel=true},
      }

      local function award(expansion)
        if (game.save.coins or 0)<10 then
          resultBox("PRIZE LADY: You'll need\nmore COINS for that.")
          return
        end
        local pack=TCG_PACKS[expansion]
        if not (pack and Bag.add(game.save,pack.item,1,game.data)) then
          resultBox("PRIZE LADY: Your BAG\nis full.")
          return
        end
        game.save.coins=(game.save.coins or 0)-10
        Sound.play(game.data,"Get_Item1")
        resultBox("DITTO received\n"..expansion.." PACK x1!")
      end

      tcgMenu(game,"CARD PACKS",rows,function(row)
        if row.cancel then done() else award(row.key) end
      end,done,{status="10 COINS / PACK",footer="A SELECT  B BACK"})
    end

    local function buyPorygon()
      if q.porygonFormLearned or (q.forms and q.forms.PORYGON) then
        activateOwnedPorygon()
        return
      end
      if (game.save.coins or 0)<9999 then
        resultBox("PRIZE LADY: You'll need\nmore COINS for that.")
        return
      end
      game.save.coins=(game.save.coins or 0)-9999
      q.porygonFormLearned=true
      q.forms=q.forms or {}
      q.forms.PORYGON=true
      Sound.play(game.data,"Get_Key_Item")
      resultBox("DITTO got an idea!\f"
        .."DITTO learned a hidden\nPORYGON transformation!\f"
        .."It won't appear in the\nTRANSFORMATIONS menu.")
    end

    local function openCatalog()
      -- This menu is deliberately local to the mod. Older Gen1Recomp builds
      -- do not ship src.ui.PrizeCounter, so keep the catalog self-contained.
      local rows={
        {label="LEMONADE",price=100,action=buyLemonade},
      }
      if q.cardQuestComplete then
        rows[#rows+1]={label="CARD PACK",price=10,action=buyCardPack}
      end
      rows[#rows+1]={
        label="PORYGON",
        price=(q.porygonFormLearned or (q.forms and q.forms.PORYGON)) and 0 or 9999,
        action=buyPorygon,
      }
      rows[#rows+1]={label="NO THANKS",price=nil,cancel=true}

      local menu={
        isOpaque=false,
        cursor=1,
        rows=rows,
      }

      function menu:update()
        local input=game.input
        if input:wasPressed("up") then
          self.cursor=self.cursor-1
          if self.cursor<1 then self.cursor=#self.rows end
          Sound.play(game.data,"Press_AB")
        elseif input:wasPressed("down") then
          self.cursor=self.cursor+1
          if self.cursor>#self.rows then self.cursor=1 end
          Sound.play(game.data,"Press_AB")
        elseif input:wasPressed("b") then
          game.stack:pop()
          done()
        elseif input:wasPressed("a") then
          Sound.play(game.data,"Press_AB")
          local row=self.rows[self.cursor]
          game.stack:pop()
          if row.cancel then
            done()
          elseif row.action then
            row.action()
          end
        end
      end

      function menu:draw()
        -- A compact native-style window: product on the left, coin cost on
        -- the right, with the current balance printed beneath.
        local boxH=(#self.rows>=4) and 9 or 7
        Font.drawBox(1,5,18,boxH)
        love.graphics.setColor(0,0,0,1)
        Font.draw("PRIZES",16,48)
        for i,row in ipairs(self.rows) do
          local y=56+(i-1)*16
          local prefix=(i==self.cursor) and ">" or " "
          Font.draw(prefix..row.label,8,y)
          if row.price~=nil then
            local cost=(row.price==0) and "OWNED" or (tostring(row.price).."C")
            Font.draw(cost,112,y)
          end
        end
        Font.draw("COINS "..tostring(game.save.coins or 0),72,120)
        love.graphics.setColor(1,1,1,1)
      end

      game.stack:push(menu)
    end

    local text
    if q.cardQuestComplete then
      text="PRIZE LADY: We added\nCARD PACKS to the prizes!\f"
        .."Choose any of the\nfour expansions."
    elseif q.slotWinSeen then
      text="PRIZE LADY: Hey, look at you\ndoing the slots!\f"
        .."You can spend COINS\nhere."
    else
      text="PRIZE LADY: Ha!\f"
        .."You sure got him,\nDITTO!"
    end
    game.stack:push(TextBox.new(game,text,openCatalog,{
      speaker="PRIZE LADY",
      portrait={speaker="PRIZE LADY",expression="Normal"},
    }))
  end

  mod.content.map_scripts:override("GAME_CORNER_PRIZE_ROOM",{
    onEnter=function(game,ow)
      local q=normalizePokopiaSave(game.save)
      -- Do not interrupt Scene 2's original Super Nerd prize-room scene.
      -- On the first later visit, the staff recognize Ditto immediately.
      if (q.superNerdArrested or q.cardQuestComplete)
          and not q.prizeRoomRecognitionSeen then
        q.prizeRoomRecognitionSeen=true
        local TextBox=require("src.render.TextBox")
        game.stack:push(TextBox.new(game,
          "PRIZE LADY: Ha!\fYou sure got him,\nDITTO!",nil,{
            speaker="PRIZE LADY",
            portrait={speaker="PRIZE LADY",expression="Normal"},
          }))
      end
    end,
    talk={
      TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_1=pokopiaPrizeCounter,
      TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_2=pokopiaPrizeCounter,
      TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_3=pokopiaPrizeCounter,
    },
  })

  local function beginRattataDistraction(game,ow)
    local q=pokopiaData(game)
    if q.distractionStarted or q.distractionDone then return end

    local rat=findNpc(ow,"RATTATA")
    local persian=findNpc(ow,"PERSIAN")
    if not rat or not persian then return end

    q.distractionCommitted=true
    q.distractionStarted=true
    q.rattataFollowing=false
    ow.pokopiaRattataTrail=nil
    ow.player.inputLocked=true
    rat.pokopiaRattataFollower=nil
    rat.wanders=false
    persian.wanders=false
    rat.passable=false
    persian.passable=false
    rat.stepFrames=7
    persian.stepFrames=8

    local ax,ay=openAdjacent(ow,persian,{
      {1,0},{0,1},{-1,0},{0,-1},
    })
    if not ax then
      q.distractionStarted=nil
      ow.player.inputLocked=false
      return
    end

    local function finish()
      -- Single authoritative cleanup for the entire distraction.
      ow.pokopiaPersianChase=nil
      ow.pokopiaRattataTrail=nil
      ow.emote=nil

      -- Gen1Recomp gates normal player input while ANY scripted movement is
      -- queued. Persian can still have a one-cell chase move in scriptMoves
      -- when Rattata reaches the route end. Removing the NPC first leaves that
      -- move orphaned forever because the removed NPC is no longer updated.
      -- Retire every chase-owned move before removing either actor.
      for i=#(ow.scriptMoves or {}),1,-1 do
        local mv=ow.scriptMoves[i]
        if mv and (mv.entity==rat or mv.entity==persian) then
          table.remove(ow.scriptMoves,i)
        end
      end

      rat.moving=false
      rat.targetX,rat.targetY=nil,nil
      rat.progress=0
      persian.moving=false
      persian.targetX,persian.targetY=nil,nil
      persian.progress=0

      removeNpc(ow,"RATTATA")
      removeNpc(ow,"PERSIAN")

      q.rattataFollowing=false
      q.distractionDone=true
      q.distractionStarted=nil
      q.postChaseGuardArmed=false

      restorePlayerInput(game,ow)
    end

    walkNpcTo(ow,rat,ax,ay,function(ok)
      if not ok then finish(); return end

      persian.facing=(rat.cellX<persian.cellX) and "left"
        or (rat.cellX>persian.cellX) and "right"
        or (rat.cellY<persian.cellY) and "up" or "down"

      local bx,by=openAdjacent(ow,persian,{
        {0,1},{1,0},{-1,0},{0,-1},
      })
      if not bx or (bx==rat.cellX and by==rat.cellY) then
        finish()
        return
      end

      walkNpcTo(ow,rat,bx,by,function()
        persian.facing=(rat.cellX<persian.cellX) and "left"
          or (rat.cellX>persian.cellX) and "right"
          or (rat.cellY<persian.cellY) and "up" or "down"

        -- Find the farthest legal floor cell in the live 1F map and use it
        -- as the run-out point instead of hard-coding a route through walls.
        local ex,ey,best=nil,nil,-1
        for y=2,ow.map.def.height*2-2 do
          for x=2,ow.map.def.width*2-2 do
            if ow.map:isWalkableCell(x,y) and not ow.map:warpAtCell(x,y) then
              local d=math.abs(x-persian.cellX)+math.abs(y-persian.cellY)
              if d>best then best=d; ex,ey=x,y end
            end
          end
        end
        if not ex then finish(); return end

        runRattataCircles(ow,rat,persian,function()
          chaseOneBlockBehind(ow,rat,persian,ex,ey,function()
            finish()
          end)
        end)
      end)
    end)
  end

  --------------------------------------------------------------------------
  -- Random emergency white flashes.
  --
  -- Minimum gap is 3 seconds (180 frames at the engine's 60 Hz presentation).
  -- Additional random delay is added each time, so there is no fixed cadence.
  -- The flash lasts only two rendered frames and occurs only while physically
  -- inside one of the four Mansion maps.
  --------------------------------------------------------------------------
  liveGame=nil
  local flashWait=180
  local flashFrames=0


  local function reseedFlash()
    -- 3 to 8 seconds between flashes.
    flashWait=180+math.random(0,300)
  end

  -- Fixed-step minigame logic. render.compose is not a gameplay tick in
  -- current Gen1Recomp; use input.step so race AI, countdowns and Mach-Bike
  -- momentum advance exactly once per 60 Hz logic step.
  mod.hooks:wrap("input.step",function(next,game,dt)
    liveGame=game or liveGame

    -- Compatibility bridge for API-2 Gen1Recomp revisions where the custom
    -- item_effects registry exists but is not merged into Gen 1 ItemEffects.
    -- Repair the merged runtime data before Bag input is dispatched. This is
    -- ordinary game data, not the frozen mod registry, so it is safe here.
    if game and game.data then
      pcall(function()
        local data=game.data
        data.item_effects=data.item_effects or {}
        data.item_effects.TCG_OPEN_PACK=tcgOpenPackEffectDef
        for _,id in ipairs(tcgPackItemIds) do
          local def=data.items and data.items[id]
          if def then
            def.effect="TCG_OPEN_PACK"
            def.needsTarget=false
          end
        end
      end)
    end

    local ow=activeOverworld(game)
    local input=game and game.input
    local q=game and pokopiaData(game)

    -- LOG 568 bookend reconciliation.
    --
    -- The ending normally rolls straight out of the Celadon chapter's last
    -- beat. Two cases can still arrive here armed but unplayed: a save made
    -- before schema 5 that had already finished the card quest, and a session
    -- quit part-way through the ending itself. Fire it once the player is back
    -- in ordinary overworld control and away from the Mansion timeline, so it
    -- can never interrupt a scripted scene or a menu. `shouldAutoPlay` and the
    -- transient `running` flag together make this idempotent.
    if Finale and ow and ow.map and ow.player
        and not isMansion(ow.map.id)
        and not ow.player.inputLocked
        and not ow.player.frozen
        and not ow.playerHidden
        and game.stack:top()==ow
        and Finale.shouldAutoPlay(game) then
      Finale.play(game)
    end

    -- If Ditto changes into the wrong Pokemon beside Giovanni, the room
    -- guard physically comes over and escorts Ditto back through the door.
    -- The latch is consumed before animation starts so stack/input changes
    -- cannot fire a duplicate escort.
    if q and q.giovanniWrongFormPending and ow and ow.map
        and ow.map.id=="POKEMON_MANSION_1F" and ow.player
        and game.stack:top()==ow then
      q.giovanniWrongFormPending=nil
      local p=ow.player
      local guard=findNpc(ow,"ROCKET_GUARD")
      if guard then
        p.inputLocked=true
        guard.frozen=true
        guard.wanders=false

        local candidates={
          {p.cellX+1,p.cellY},{p.cellX-1,p.cellY},
          {p.cellX,p.cellY+1},{p.cellX,p.cellY-1},
        }
        local best=nil
        for _,c in ipairs(candidates) do
          if ow.map:inBounds(c[1],c[2]) and ow.map:isWalkableCell(c[1],c[2])
              and not ow.map:warpAtCell(c[1],c[2]) then
            local r=routeNpcTo(ow,guard,c[1],c[2])
            if r and (not best or #r<best.len) then
              best={x=c[1],y=c[2],len=#r}
            end
          end
        end

        local function escortOut()
          guard.facing=(p.cellX<guard.cellX) and "left"
            or (p.cellX>guard.cellX) and "right"
            or (p.cellY<guard.cellY) and "up" or "down"
          showBox(game,
            "ROCKET: Hey!\f"
            .."You're not PERSIAN.\f"
            .."The boss doesn't see\njust any POKeMON.\f"
            .."Come on. Out you go.",
            function()
              -- Walk Ditto to the room threshold first, then bring the guard
              -- up behind them.  The last step matches the room's existing
              -- guard rejection path and leaves control safely outside.
              walkNpcTo(ow,p,10,2,function()
                walkNpcTo(ow,guard,9,2,function()
                  guard.facing="right"
                  guard.frozen=false
                  p.inputLocked=false
                  q.rocketStopped=true
                end,false)
              end,false)
            end)
        end

        if best then
          walkNpcTo(ow,guard,best.x,best.y,function() escortOut() end,false)
        else
          escortOut()
        end
      else
        -- No live guard means the story has already removed him; do not
        -- strand the player in a locked state.
        p.inputLocked=false
      end
    end

    -- ELECTRODE momentum survives steering, but it is broken by an actual
    -- stop: releasing every D-pad direction, colliding with terrain/an NPC,
    -- or beginning an interaction. Player:tryMove marks blocked movement via
    -- bumpFrames, so this catches real collisions without treating a corner
    -- turn as a slowdown. A-button interactions and scripted input locks also
    -- kill momentum immediately.
    if input then
      local p=ow and ow.player
      if p and p.pokopiaForm=="ELECTRODE" then
        local held=false
        for _,d in ipairs({"up","down","left","right"}) do
          if input.isDown and input:isDown(d) then
            held=true
            break
          end
        end
        local hitSomething=(p.bumpFrames and p.bumpFrames>0) and true or false
        local interacting=(input.wasPressed and input:wasPressed("a")) or false
        local scriptedStop=(p.inputLocked and not p.moving) and true or false
        local mapId=ow and ow.map and ow.map.id or nil
        local changedMap=p.pokopiaElectrodeMomentumMap~=nil
          and mapId~=p.pokopiaElectrodeMomentumMap

        if not held or hitSomething or interacting or scriptedStop or changedMap then
          p.pokopiaElectrodeAccelSteps=0
        end
        p.pokopiaElectrodeMomentumMap=mapId
      elseif p then
        p.pokopiaElectrodeAccelSteps=0
        p.pokopiaElectrodeMomentumMap=nil
      end
    end

    -- A save can resume inside B1F without firing this build's onEnter hook.
    -- Reconcile once when the live lounge lacks either quest actor. The guard
    -- prevents rebuilding the cast every frame.
    if ow and ow.map and ow.map.id=="ROCKET_HIDEOUT_B1F"
        and (not findNpc(ow,"RH_DISPATCH") or not findNpc(ow,"RH_BOARD"))
        and not ow._pokopiaRocketQuestReconcile then
      ow._pokopiaRocketQuestReconcile=true
      ensureRocketHangout(game,ow)
    end

    return next(game,dt)
  end)

  -- World compositor effects remain below. Minigame HUD is intentionally
  -- NOT drawn here; render.hud above is the engine's post-endFrame seam.

  mod.hooks:wrap("render.compose",function(next,renderer,ctx)
    local ow=activeOverworld(liveGame)

    local surgeActive=magnetonSurgeFrames>0 and ow and ow==magnetonSurgeOw
    local handled
    if surgeActive then
      -- Deterministic ±2 px screen shake, changing every two frames.
      local phase=math.floor(magnetonSurgeFrames/2)%4
      local dx=(phase==0 and -2) or (phase==1 and 2) or 0
      local dy=(phase==2 and -2) or (phase==3 and 2) or 0

      love.graphics.push()
      love.graphics.translate(dx,dy)
      handled=next()
      love.graphics.pop()
    else
      handled=next()
    end

    -- Speaker UI is drawn by TextBox:draw(), where the exact live box and its
    -- emotion metadata are known.  Do not duplicate it from the compositor.

    local mapId=ow and ow.map and ow.map.id

    -- Voltorb should visibly roll through the emergency rather than spending
    -- long stretches idle. Keep its random-wander decision timer armed while
    -- leaving actual movement/collision to NPC:update.
    if ow and ow.npcs then
      local Collision=require("src.world.Collision")

      local q=liveGame and pokopiaData(liveGame)
      if q and q.requestedForm then
        local requested=q.requestedForm
        applyDittoForm(liveGame,requested,ow)

        -- The doorway guard is the single entrance gate. If Ditto changes
        -- into another form after entering as PERSIAN, return Ditto to the
        -- threshold with one deterministic correction rather than launching a
        -- second guard chase/pathfinding sequence.
        if requested~="DITTO" and requested~="PERSIAN"
            and ow and ow.map and ow.map.id=="POKEMON_MANSION_1F"
            and ow.player and not q.giovanniWrongFormEscort then
          local boss=findNpc(ow,"GIOVANNI")
          if boss then
            local dist=math.abs(ow.player.cellX-boss.cellX)
              +math.abs(ow.player.cellY-boss.cellY)
            if dist<=4 then
              q.giovanniWrongFormEscort=true
              ow.player.inputLocked=true
              local TextBox=require("src.render.TextBox")
              game.stack:push(TextBox.new(liveGame,
                "ROCKET: Hey!\f"
                .."Only PERSIAN is\nallowed near the Boss.\f"
                .."Come on. Out you go.",
                function()
                  local route=routeNpcTo(ow,ow.player,9,2)
                  local function finishEscort()
                    q.giovanniWrongFormEscort=nil
                    restorePlayerInput(liveGame,ow)
                  end
                  local function stepRoute(i)
                    if not route or not route[i] then
                      finishEscort()
                      return
                    end
                    ow:scriptMove(ow.player,route[i],1,function()
                      stepRoute(i+1)
                    end,{collide=false})
                  end
                  stepRoute(1)
                end))
            end
          end
        end
      elseif q and q.currentForm and ow and ow.player
          and ow.player.pokopiaForm~=q.currentForm then
        applyDittoForm(liveGame,q.currentForm,ow)
      end
      local chase=ow.pokopiaPersianChase
      if chase and chase.rat and chase.persian then
        local rat,persian=chase.rat,chase.persian

        local rx=rat.targetX or rat.cellX
        local ry=rat.targetY or rat.cellY

        if rx~=chase.lastX or ry~=chase.lastY then
          chase.trail[#chase.trail+1]={x=rx,y=ry}
          chase.lastX,chase.lastY=rx,ry
        end

        -- Keep one tile between them. As soon as Rattata commits its next
        -- step, Persian starts toward the cell Rattata just vacated.
        if not persian.moving and #chase.trail>=2 then
          local goal=table.remove(chase.trail,1)
          local dx=goal.x-persian.cellX
          local dy=goal.y-persian.cellY
          local dir=(dx==1 and dy==0 and "right")
            or (dx==-1 and dy==0 and "left")
            or (dy==1 and dx==0 and "down")
            or (dy==-1 and dx==0 and "up")
          if dir then
            ow:scriptMove(persian,dir,1,nil,{collide=false})
          end
        end

        -- Cutscene completion is handled directly by Rattata's route-end
        -- callback. This update block only animates Persian's one-cell trail.
      end

      if q and q.pixieFollowing then
        local mapIdNow=ow.map and ow.map.id
        local trail=ow.pokopiaPixieTrail

        -- Fresh warp/map rebuild: PIXIE is recreated on Ditto's arrival cell
        -- and the trail is reseeded there. The overworld draw-order tie break
        -- keeps a same-cell follower hidden under the player until movement.
        if not trail or trail.mapId~=mapIdNow then
          local oldPixie=findNpc(ow,"VULPIX")
          if oldPixie then
            oldPixie.goalX,oldPixie.goalY=nil,nil
            oldPixie.targetX,oldPixie.targetY=nil,nil
            oldPixie.moving=false
            oldPixie.progress=0
          end
          ensurePixieFollower(liveGame,ow,true)
          trail=ow.pokopiaPixieTrail
        end

        local pixie=findNpc(ow,"VULPIX")
        if not pixie then
          pixie=ensurePixieFollower(liveGame,ow,true)
          trail=ow.pokopiaPixieTrail
        end

        if pixie and trail then
          local p=ow.player
          pixie.passable=true
          pixie.wanders=false
          pixie.stepFrames=p.stepFrames or 16

          -- Match the verified Yellow follower timing: react when Ditto
          -- COMMITS a step, not after the step lands. The follower's goal is
          -- the cell Ditto is currently vacating, which keeps PIXIE exactly
          -- one tile behind while both sprites move smoothly at the same time.
          local destX=p.targetX or p.cellX
          local destY=p.targetY or p.cellY
          if destX~=trail.x or destY~=trail.y then
            pixie.goalX,pixie.goalY=trail.x,trail.y
            trail.x,trail.y=destX,destY
          end

          if not pixie.moving and pixie.goalX then
            local gx,gy=pixie.goalX,pixie.goalY

            if pixie.cellX==gx and pixie.cellY==gy then
              pixie.goalX,pixie.goalY=nil,nil
            else
              local far=math.abs(pixie.cellX-gx)+math.abs(pixie.cellY-gy)

              -- Same recovery rule as the built-in follower: if a forced map
              -- transition leaves it far behind, snap to the queued vacated
              -- cell instead of holding player input or carrying stale motion.
              if far>6 then
                pixie.cellX,pixie.cellY=gx,gy
                pixie.px,pixie.py=gx*16,gy*16
                pixie.goalX,pixie.goalY=nil,nil
                pixie.targetX,pixie.targetY=nil,nil
                pixie.moving=false
              else
                local dir
                if pixie.cellX<gx then dir="right"
                elseif pixie.cellX>gx then dir="left"
                elseif pixie.cellY<gy then dir="down"
                else dir="up" end

                local tx,ty=Collision.target(pixie.cellX,pixie.cellY,dir)
                if ow.map:inBounds(tx,ty) and ow.map:isWalkableCell(tx,ty) then
                  pixie.facing=dir
                  pixie.targetX,pixie.targetY=tx,ty
                  pixie.moving=true
                  pixie.progress=0
                else
                  -- Never let follower recovery interfere with player control.
                  pixie.goalX,pixie.goalY=nil,nil
                end
              end
            end
          end
        end
      end

      if q and q.rattataFollowing and mapId=="POKEMON_MANSION_1F" then
        local rat=findNpc(ow,"RATTATA")
        local p=ow.player
        local trail=ow.pokopiaRattataTrail

        if rat and trail then
          rat.passable=true
          rat.wanders=false
          rat.stepFrames=p.stepFrames or 10

          local destX=p.targetX or p.cellX
          local destY=p.targetY or p.cellY
          if destX~=trail.x or destY~=trail.y then
            rat.goalX,rat.goalY=trail.x,trail.y
            trail.x,trail.y=destX,destY
          end

          if not rat.moving and rat.goalX then
            local gx,gy=rat.goalX,rat.goalY
            if rat.cellX==gx and rat.cellY==gy then
              rat.goalX,rat.goalY=nil,nil
            else
              local dir
              if rat.cellX<gx then dir="right"
              elseif rat.cellX>gx then dir="left"
              elseif rat.cellY<gy then dir="down"
              else dir="up" end
              local tx,ty=Collision.target(rat.cellX,rat.cellY,dir)
              if ow.map:inBounds(tx,ty) and ow.map:isWalkableCell(tx,ty) then
                rat.facing=dir
                rat.targetX,rat.targetY=tx,ty
                rat.moving=true
                rat.progress=0
              else
                rat.goalX,rat.goalY=nil,nil
              end
            end
          end

          local guard=findNpc(ow,"ROCKET_GUARD")
          if guard and not q.distractionStarted
              and not q.distractionCommitted
              and not q.distractionDone
              and liveGame.stack:top()==ow then
            local d=math.abs(p.cellX-guard.cellX)+math.abs(p.cellY-guard.cellY)
            if d<=4 then
              -- One-shot latch: once Rattata commits to the distraction,
              -- walking around can never fire this proximity trigger again.
              q.distractionCommitted=true
              q.distractionStarted=true
              rat.frozen=true
              p.inputLocked=true

              showRattataBox(liveGame,
                "RATTATA: Stand back, kid!",
                function()
                  showRattataBox(liveGame,
                    "RATTATA: I'll handle this.",
                    function()
                      rat.frozen=false
                      p.inputLocked=false
                      q.distractionStarted=nil
                      beginRattataDistraction(liveGame,ow)
                    end,"Determined")
                end,"Determined")
            end
          end
        end
      end

      for _,npc in ipairs(ow.npcs) do
        if npc.def and npc.def.name=="SPINARAK" and mapId=="POKEMON_MANSION_3F" then
          npc.wanders=false
          npc.stepFrames=14
          npc.pokopiaSpinarakWait=(npc.pokopiaSpinarakWait or math.random(20,70))-1
          if npc.pokopiaSpinarakWait<=0 and not npc.moving and not npc.frozen then
            local d=npc.pokopiaSpinarakDir
            if not d then
              local dirs={"up","down","left","right"}
              d=dirs[math.random(#dirs)]
              npc.pokopiaSpinarakDir=d
            end
            local tx,ty=Collision.target(npc.cellX,npc.cellY,d)
            local terrainOK=tx<=5 and tx>=0 and ty<=5 and ty>=0 and ow.map:inBounds(tx,ty)
              and ow.map:isWalkableCell(tx,ty) and not ow.map:warpAtCell(tx,ty)
            if not terrainOK then
              -- A wall/warp/out-of-patrol-bounds tile ends this tiny patrol step.
              -- Pick a new direction after a short idle rather than bouncing.
              npc.pokopiaSpinarakDir=nil
              npc.pokopiaSpinarakWait=math.random(25,80)
            elseif Collision.canMove(ow.map,ow.entities,npc,d) then
              npc.facing=d; npc.targetX,npc.targetY=tx,ty; npc.moving=true; npc.progress=0
              npc.pokopiaSpinarakDir=nil
              npc.pokopiaSpinarakWait=math.random(25,80)
            else
              -- Another actor (including Ditto) is occupying the intended tile.
              -- Keep the same direction and simply wait until they move away.
              npc.facing=d
              npc.pokopiaSpinarakWait=1
            end
          end
        end
        if npc.def and npc.def.name=="VOLTORB" then
          npc.wanders=false
          npc.stepFrames=10
          npc.pokopiaPatrol=npc.pokopiaPatrol or {
            axis="h",
            dir="left",
            minX=21,maxX=22,minY=7,maxY=7,
          }
        end

        -- Deterministic pacing. When a pacer reaches an obstacle,
        -- wall, furniture, another actor or a warp tile, reverse direction
        -- and continue back along the same corridor.
        local patrol=npc.pokopiaPatrol
        if patrol and not npc.moving and not npc.frozen and ow.map then
          local dir=patrol.dir
          local reverse
          if patrol.axis=="h" then
            reverse=(dir=="left") and "right" or "left"
          else
            reverse=(dir=="up") and "down" or "up"
          end

          local function terrainStepOK(d)
            local tx,ty=Collision.target(npc.cellX,npc.cellY,d)
            if patrol.minX and tx<patrol.minX then return false end
            if patrol.maxX and tx>patrol.maxX then return false end
            if patrol.minY and ty<patrol.minY then return false end
            if patrol.maxY and ty>patrol.maxY then return false end
            return ow.map:inBounds(tx,ty)
              and ow.map:isWalkableCell(tx,ty)
              and not ow.map:warpAtCell(tx,ty)
          end

          -- Reverse only for actual map geometry. If Ditto or another actor is
          -- standing in the way, normal collision applies: the patroller waits
          -- facing its travel direction and continues once the tile clears.
          if not terrainStepOK(dir) then
            dir=reverse
            patrol.dir=dir
          end

          if terrainStepOK(dir) and Collision.canMove(ow.map,ow.entities,npc,dir) then
            local tx,ty=Collision.target(npc.cellX,npc.cellY,dir)
            npc.facing=dir
            npc.targetX,npc.targetY=tx,ty
            npc.moving=true
            npc.progress=0
          else
            npc.facing=dir
          end
        end
      end
    end

    if liveGame and liveGame.pokopiaAlarm then
      if isMansion(mapId) then
        pcall(liveGame.pokopiaAlarm.setVolume,liveGame.pokopiaAlarm,0.4)
      else
        pcall(liveGame.pokopiaAlarm.stop,liveGame.pokopiaAlarm)
        liveGame.pokopiaAlarm=nil
      end
    end

    if not isMansion(mapId) then
      flashFrames=0
      return handled
    end

    if magnetonSurgeFrames>0 and ow==magnetonSurgeOw then
      -- Electrical pulse: alternate white overlay every four frames while
      -- the entire scene shakes.
      if math.floor(magnetonSurgeFrames/4)%2==0 then
        love.graphics.setColor(1,1,1,1)
        love.graphics.rectangle("fill",0,0,ctx.ww,ctx.wh)
      end

      magnetonSurgeFrames=magnetonSurgeFrames-1
      if magnetonSurgeFrames<=0 then
        magnetonSurgeFrames=0
        magnetonSurgeOw=nil
        if ow and ow.player then
          ow.player.inputLocked=false
          ow.player.frozen=false
        end
        local cb=magnetonSurgeDone
        magnetonSurgeDone=nil
        if cb then cb() end
      end
      return handled
    end

    if flashFrames>0 then
      flashFrames=flashFrames-1
      love.graphics.setColor(1,1,1,1)
      love.graphics.rectangle("fill",0,0,ctx.ww,ctx.wh)
      return handled
    end

    flashWait=flashWait-1
    if flashWait<=0 then
      flashFrames=2
      reseedFlash()
    end
    return handled
  end)

  --------------------------------------------------------------------------
  -- Runtime bundled follower setup and defensive global battle suppression.
  --------------------------------------------------------------------------
  mod.events:on("game.ready",function(ev)
    local game=ev.game
    liveGame=game

    -- Keep the Celadon Game Corner hideout permanently revealed. The vanilla
    -- Game Corner onEnter script reads this same poster metadata and chooses
    -- the open block whenever its event flag is set, so this survives every
    -- later map reload without maintaining a duplicate door implementation.
    game.save.flags=game.save.flags or {}
    local poster=game.data.field and game.data.field.gameCornerPoster
    if poster then
      game.save.flags[poster.event]=true
      local ow=activeOverworld and activeOverworld(game)
      if ow and ow.map and ow.map.id=="GAME_CORNER" then
        ow:replaceBlock(poster.x,poster.y,poster.openBlock)
      end
    end

    -- Use the bundled normal follower sheets directly; no external follower
    -- dependency or runtime asset resolver is required.
    local followerDefs={
      DITTO,GRIMER,MAGNEMITE,MAGNETON,VOLTORB,ELECTRODE,
      KOFFING,WEEZING,POLIWHIRL,SLOWPOKE,DODRIO,TOTODILE,SPINARAK,AMPHAROS,
      LARVITAR,MUK,PORYGON,VULPIX,RATTATA,CHARMANDER,BULBASAUR,SQUIRTLE,PERSIAN,
      PICHU,TOGEPI,HYPNO,ZUBAT,RATICATE,"CUBONE",
      EKANS,ARBOK,GOLBAT,DROWZEE,VILEPLUME,MURKROW,HOUNDOUR,HOUNDOOM,
      TENTACOOL,TENTACRUEL,"SLOWBRO","HITMONLEE","HITMONCHAN",
    }
    for _,sid in ipairs(followerDefs) do
      local def=game.data.sprites[sid]
      local dex=FOLLOWER_DEX[sid]
      if def and dex then
        def.image=mod.path.."/assets/enhanced_overworld/poke_followers/follower_"..dex.."_normal.png"
        def.frames=6
        def.frameWidth=16
        def.frameHeight=16
        def.anchorX=8
        def.anchorY=16
        def.walker=true
        def.trueColor=true
      end
    end

    -- Defensive trainer stripping across the live dataset.
    for _,map in pairs(game.data.maps or {}) do
      for _,obj in ipairs((type(map)=="table" and map.objects) or {}) do
        obj.trainer=nil
        obj.trainerClass=nil
        obj.partyIndex=nil
      end
    end

    reseedFlash()
  end)
end
