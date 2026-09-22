# Pokemon Trading Card Game

A `total_conversion` mod (api 2) that boots the Pokemon Trading Card Game
(Game Boy) duel engine instead of Red's overworld. Import your own Pokemon
Red ROM as usual (it supplies the fallback engine infrastructure this
conversion sits on), then supply your own Pokemon Trading Card Game ROM
through the launcher's import panel. Try: open the mod, and it walks you
through providing the TCG ROM if it isn't there yet.

## What this ships and what it doesn't

- **No ROM-derived bytes.** `data/tcg_manifest.lua` is a recipe -- symbol
  addresses, card-pointer offsets, effect-command phase/function identities
  -- parsed entirely from the public `pret/poketcg` decompilation source,
  never from any ROM. It tells the extractor *where* things are; it does
  not contain card text, stats, art, or any other cartridge content.
- **The Pokemon TCG ROM never touches disk here.** `mod.imports:read(...)`
  hands this mod your ROM's bytes for one session; extraction happens
  entirely in memory, and nothing gets written back to a cache.
- Card art (`gfx.image` on each extracted card) decodes in memory but isn't
  wired into a screen yet -- the duel itself runs turn-by-turn text/data
  only for now.

## Status

- **Validated for real:** the extraction pipeline (`src/tcg/import/
  RomExtractor.lua` + `data/tcg_manifest.lua`) was run against a real,
  from-source-built `poketcg.gbc` (SHA-1-verified byte-identical to the
  actual cartridge) entirely outside this engine, under plain LuaJIT.
  Every pointer, card record, deck list, and all 317 effect-command lists
  it reads were cross-checked against real ROM bytes -- zero mismatches.
  Separately, `src/tcg/duel/EffectCommands.lua`'s actual runtime handlers
  were checked against every one of the 569 real function labels those
  317 lists reference: 569/569 covered.
- **Not yet validated:** the mod-loader wiring in `main.lua` (`mod.imports`,
  `mod.content.screens`, `mod.content.field:patch`) hasn't run inside a
  live LOVE + mod-loader session. It's written directly against this
  engine's own source (`src/mods/Sandbox.lua`, `docs/modding.md`), not
  guessed, and `python3 tools/modkit.py lint mods/pokemon_tcg` /
  `validate` both pass everything checkable without a live ROM import. The
  remaining gap is a real in-game boot.
- Only the scripted 7-turn "Sam's practice" duel is wired up
  (`PracticeSession.lua`/`PracticePlayable.lua`) -- the one part of the
  underlying port that's actually playable end to end. Free/AI-vs-AI/
  full-deck duels aren't hooked up to a screen yet.

## Layout

- `manifest.json` -- identity, the `required_imports` declaration for the
  TCG ROM, `permissions: ["engine_internals"]` (needed for
  `src.import.Rom`/`ImageWriter`).
- `main.lua` -- entry chunk: reads the imported ROM, runs extraction, boots
  `PracticeSession`/`PracticePlayable` as the `PokemonTCG` screen, or shows
  an import-prompt screen if the ROM hasn't been supplied yet.
- `src/tcg/` -- the duel engine (memory model, RNG, duel setup/turn flow/
  combat/status/prizes/knockouts, every attack/Power/Trainer effect
  command, the complete CPU AI), copied from the sibling `logie-github/Test`
  repo with internal `require("src.tcg.*")` calls rewritten to
  `require("mods.pokemon_tcg.src.tcg.*")`. Source of truth for behavior:
  `pret/poketcg` at commit `7a75fe810e91dda43538b249c70ee5da14e38686`.
- `data/tcg_manifest.lua` -- the recipe described above.
- `transforms.lua` -- unused for now; reserved for deriving art from the
  player's own Red cache later, per this engine's asset-provenance rules.

## Loop

1. `POKEPORT_DEV=1 love .` once, leave it running.
2. Import a Red ROM as usual, then supply your own Pokemon Trading Card
   Game ROM when the mod's import prompt asks for it.
3. `python3 tools/modkit.py lint mods/pokemon_tcg` and
   `python3 tools/modkit.py validate mods/pokemon_tcg` before sharing.
4. `python3 tools/modkit.py pack mods/pokemon_tcg` to ship.
