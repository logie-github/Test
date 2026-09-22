-- pokemon_tcg: total-conversion mod. Boots the Pokemon Trading Card Game
-- (Game Boy) duel engine instead of the Red overworld, once the player
-- supplies their own legally owned Pokemon TCG ROM through the launcher's
-- required-imports flow.
--
-- LEGAL POSTURE: this mod ships no ROM-derived bytes. data/tcg_manifest.lua
-- is the "recipe" -- symbol addresses, card-pointer offsets, effect-command
-- phase/function identities -- parsed entirely from the public pret/poketcg
-- decompilation source (see the sibling logie-github/Test repo,
-- tools/tcg/build_manifest.py), never from any ROM. All actual game bytes
-- (card text, stats, attacks, graphics) come from
-- mod.imports:read("pokemontcg", ...) at runtime, off the player's own
-- dump, and this mod never writes them to disk.
--
-- STATUS: the extraction/duel-engine half of this (RomExtractor + the
-- whole src/tcg/duel tree) was validated end to end against a real,
-- from-source-built poketcg.gbc -- every pointer, card record and
-- effect-command list RomExtractor reads was cross-checked against actual
-- ROM bytes, EffectCommands.lua's runtime handlers cover 569/569 of the
-- real function labels the cartridge's effect-command lists reference,
-- and DuelSession (a live, non-scripted duel: real deck vs real AI deck,
-- dynamic per-turn menu) was played through boot, interactive setup and
-- 8 real turns to a real win/loss conclusion against that same built ROM
-- -- the run that found and fixed three pre-existing bugs (see
-- DuelSession.lua's header and tests/tcg/test_duel_session_source.py in
-- the sibling logie-github/Test repo). The mod-loader wiring below
-- (mod.imports, mod.content.screens, mod.content.field:patch) has NOT
-- been run against a live LOVE + loader; it is written directly against
-- this engine's own source (src/mods/Sandbox.lua, docs/modding.md), not
-- guessed.

return function(mod)
  local RomExtractor = require("mods.pokemon_tcg.src.tcg.import.RomExtractor")
  local DuelSession = require("mods.pokemon_tcg.src.tcg.duel.DuelSession")
  local PracticeSession = require("mods.pokemon_tcg.src.tcg.duel.PracticeSession")
  local PracticePlayable = require("mods.pokemon_tcg.src.tcg.states.PracticePlayable")
  local manifest = require("mods.pokemon_tcg.data.tcg_manifest")

  -- Built once, the first time a player who has supplied the ROM opens the
  -- screen; nil until then. bootError explains why it hasn't happened yet.
  local session, bootError

  local function buildData()
    local info, infoErr = mod.imports:info("pokemontcg")
    if not info then
      return nil, infoErr or "Pokemon TCG ROM not supplied yet"
    end

    local romData, readErr = mod.imports:read("pokemontcg", 0, manifest.romSize)
    if not romData then return nil, readErr end

    local extractor = RomExtractor.new(romData, manifest, nil)
    local ok, result = pcall(function()
      extractor:validateAnchorSymbols()
      local memory = extractor:extractMemory()
      local core = extractor:extractCoreData()
      local effects = extractor:extractEffects()
      local text = extractor:extractText()
      local cards = extractor:extractCards(text)
      local decks = extractor:extractDecks(cards)
      return {
        meta = { schema = 5, translationComplete = true },
        memory = memory,
        constants = manifest.constants,
        core = core,
        effects = effects,
        text = text,
        cards = cards,
        decks = decks,
      }
    end)
    if not ok then return nil, tostring(result) end
    return result
  end

  local function waitScreen(game)
    local state = { game = game, isOpaque = true }
    function state:update() end
    function state:draw()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.print("POKEMON TCG", 8, 16)
      love.graphics.print("Import your own", 8, 44)
      love.graphics.print("Pokemon TCG ROM", 8, 56)
      love.graphics.print("from the launcher", 8, 68)
      love.graphics.print("import panel, then", 8, 80)
      love.graphics.print("reopen this mod.", 8, 92)
      if bootError then
        love.graphics.setColor(0.6, 0, 0, 1)
        love.graphics.print(tostring(bootError), 4, 116)
      end
    end
    return state
  end

  mod.content.screens:register("PokemonTCG", {
    new = function(game, opts)
      if not session and not bootError then
        local data, err = buildData()
        if data then
          -- Free duel (a real deck vs a real AI deck, not a fixed script)
          -- is the primary experience; boot() runs synchronously and can
          -- throw (an unexpected duel-setup failure), so pcall it and fall
          -- back to the scripted Sam practice duel rather than leave the
          -- player stuck on the wait screen.
          local ok, built = pcall(DuelSession.new, data)
          if ok then
            session = built
          else
            local practiceOk, practiceSession = pcall(PracticeSession.new, data)
            if practiceOk then
              session = practiceSession
              bootError = "Free duel failed to start (" .. tostring(built)
                .. "); showing the practice duel instead."
            else
              bootError = tostring(built)
            end
          end
        else
          bootError = err
        end
      end
      if session then
        return PracticePlayable.new(game, session)
      end
      return waitScreen(game)
    end,
  })

  -- Own the boot flow: this is what makes it a total conversion rather than
  -- a content patch. The Red import still runs underneath and supplies the
  -- fallback infrastructure (font, base LOVE services); nothing here reuses
  -- Red's species/move/map data, only its role as the required base import.
  mod.content.field:patch("boot", {
    screens = { title = "PokemonTCG" },
  })
end
