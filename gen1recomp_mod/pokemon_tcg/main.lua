-- pokemon_tcg: content mod. Adds a "PLAY TCG" row to Red's own START menu
-- (alongside POKéDEX/POKéMON/ITEM/SAVE), next to the launcher's Red
-- import you already run every session -- no boot takeover, no total
-- conversion. Selecting it shows a line of flavor text, then boots a
-- real Pokemon Trading Card Game duel fresh, off your own legally owned
-- TCG cartridge dump, supplied through the launcher's required-imports
-- flow the same way any other required ROM is.
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
-- 8 real turns to a real win/loss conclusion against that same built ROM.
-- The mod-loader wiring below (mod.hooks, mod.content.screens, mod.ui)
-- has NOT been run against a live LOVE + mod-loader session; it is
-- written directly against this engine's own source (src/mods/Sandbox.lua,
-- src/ui/ModUI.lua, src/ui/StartMenu.lua, the example_dexnav mod), not
-- guessed.

return function(mod)
  local RomExtractor = require("mods.pokemon_tcg.src.tcg.import.RomExtractor")
  local DuelSession = require("mods.pokemon_tcg.src.tcg.duel.DuelSession")
  local PracticeSession = require("mods.pokemon_tcg.src.tcg.duel.PracticeSession")
  local PracticePlayable = require("mods.pokemon_tcg.src.tcg.states.PracticePlayable")
  local manifest = require("mods.pokemon_tcg.data.tcg_manifest")

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

  local function waitScreen(game, bootError)
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
      love.graphics.print("choose PLAY TCG", 8, 92)
      love.graphics.print("again.", 8, 104)
      if bootError then
        love.graphics.setColor(0.6, 0, 0, 1)
        love.graphics.print(tostring(bootError), 4, 124)
      end
    end
    return state
  end

  -- Each visit builds its own data/session from scratch -- nothing is
  -- cached across PLAY TCG selections, so every visit really is a fresh
  -- boot, the same way turning a Game Boy back on is.
  mod.content.screens:register("PokemonTCG", {
    new = function(game, opts)
      local data, err = buildData()
      if not data then return waitScreen(game, err) end

      -- Free duel (a real deck vs a real AI deck, not a fixed script) is
      -- the primary experience; boot() runs synchronously and can throw
      -- (an unexpected duel-setup failure), so pcall it and fall back to
      -- the scripted Sam practice duel rather than leave the player stuck.
      local ok, built = pcall(DuelSession.new, data)
      if ok then
        return PracticePlayable.new(game, built)
      end
      local practiceOk, practiceSession = pcall(PracticeSession.new, data)
      if practiceOk then
        return PracticePlayable.new(game, practiceSession)
      end
      return waitScreen(game, tostring(built))
    end,
  })

  -- Row lives next to POKéDEX/POKéMON/ITEM/SAVE in the vanilla START
  -- menu -- the ui.start_menu.items hook exists exactly so mods can do
  -- this without patching src/ui/StartMenu.lua (see its own header
  -- comment). Anchored before SAVE, same placement the example_dexnav
  -- mod uses for its own row.
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    return mod.ui.insertBefore(out, "SAVE", {
      label = "PLAY TCG",
      onSelect = function()
        game.stack:push(mod.ui.TextBox.new(game,
          "You pull out your\nGameboy and play.", function()
            mod.ui.push(game, "PokemonTCG")
          end))
      end,
    })
  end)
end
