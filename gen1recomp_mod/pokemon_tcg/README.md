# Pokemon Trading Card Game

A `total_conversion` mod (api 2) that boots the Pokemon Trading Card Game
(Game Boy) duel engine instead of Red's overworld. Import your own Pokemon
Red ROM as usual (it supplies the fallback engine infrastructure this
conversion sits on), then supply your own Pokemon Trading Card Game ROM
through the launcher's import panel. Try: open the mod, and it walks you
through providing the TCG ROM if it isn't there yet. It's flagged
`experimental`, so enable it in the mod manager (**F10**) before it boots.

The mod boots straight into a real duel: your Squirtle-and-Friends starter
deck against the AI's Charmander-and-Friends deck (a fixed matchup for now
-- see Status), with a dynamic turn-by-turn menu built from your actual
hand and field, not a script. If it fails to start for any reason, it
falls back to the scripted 7-turn "Sam's practice" duel instead of leaving
you stuck.

## What this ships and what it doesn't

- **No ROM-derived bytes.** `data/tcg_manifest.lua` is a recipe -- symbol
  addresses, card-pointer offsets, effect-command phase/function identities
  -- parsed entirely from the public `pret/poketcg` decompilation source,
  never from any ROM. It tells the extractor *where* things are; it does
  not contain card text, stats, art, or any other cartridge content.
- **The Pokemon TCG ROM never touches disk here.** `mod.imports:read(...)`
  hands this mod your ROM's bytes for one session; extraction happens
  entirely in memory, and nothing gets written back to a cache.
- Card art decodes in memory and is colorized from its embedded GBC
  palette (`CardPalette.lua`), then drawn on the duel screen with HP bars
  and type-tinted frames -- see `PracticePlayable.lua`'s own header for
  what it is and isn't (a stylized approximation, not the cartridge's own
  menu chrome).

## Status

- **Validated for real:** the extraction pipeline (`src/tcg/import/
  RomExtractor.lua` + `data/tcg_manifest.lua`) was run against a real,
  from-source-built `poketcg.gbc` (SHA-1-verified byte-identical to the
  actual cartridge) entirely outside this engine, under plain LuaJIT.
  Every pointer, card record, deck list, and all 317 effect-command lists
  it reads were cross-checked against real ROM bytes -- zero mismatches.
  `src/tcg/duel/EffectCommands.lua`'s runtime handlers cover 569/569 of the
  real function labels those 317 lists reference. `DuelSession.lua` (the
  free-duel coordinator) was played through boot, interactive starting-hand
  setup and 8 real turns to a real win/loss conclusion against that same
  built ROM -- the run that found and fixed three real bugs: its own
  attackIndex off-by-one, a pre-existing forward-reference bug in AI.lua's
  `wrMask` helper (never live-tested before, since only the scripted
  practice duel had ever actually run), a misspelled constant in
  Combat.lua's recoil-damage path, and a `build_manifest.py` gap that had
  been silently omitting 20+ real ATK_ANIM_* constants from every manifest
  built before this fix. See `DuelSession.lua`'s own header and
  `tests/tcg/test_duel_session_source.py` in the sibling
  `logie-github/Test` repo for the full account.
- **Not yet validated:** the mod-loader wiring in `main.lua` (`mod.imports`,
  `mod.content.screens`, `mod.content.field:patch`) hasn't run inside a
  live LOVE + mod-loader session. It's written directly against this
  engine's own source (`src/mods/Sandbox.lua`, `docs/modding.md`), not
  guessed, and `python3 tools/modkit.py lint mods/pokemon_tcg` /
  `validate` both pass everything checkable without a live ROM import. The
  remaining gap is a real in-game boot.
- **Free-duel v1 scope**, disclosed in `DuelSession.lua`'s header: the
  matchup is fixed (no deck-picker menu yet), and of the Trainer cards in
  those two decks, Computer Search/Item Finder/Poke Ball (each need a
  picker over deck/discard contents) and PlusPower (attack-attachment
  timing) aren't wired into the menu yet. Retreat reuses `AI:tryToRetreat`'s
  execution path, so which specific attached energy cards pay the retreat
  cost is chosen by the same heuristic the AI uses on its own retreats,
  not by you.
- The scripted 7-turn "Sam's practice" duel (`PracticeSession.lua`) still
  works and is the automatic fallback if the free duel fails to start.

## Layout

- `manifest.json` -- identity, the `required_imports` declaration for the
  TCG ROM, `permissions: ["engine_internals"]` (needed for
  `src.import.Rom`/`ImageWriter`).
- `main.lua` -- entry chunk: reads the imported ROM, runs extraction, boots
  `DuelSession`/`PracticePlayable` (falling back to `PracticeSession` on
  any boot failure) as the `PokemonTCG` screen, or shows an import-prompt
  screen if the ROM hasn't been supplied yet.
- `src/tcg/` -- the duel engine (memory model, RNG, duel setup/turn flow/
  combat/status/prizes/knockouts, every attack/Power/Trainer effect
  command, the complete CPU AI, the free-duel session/menu builder, card
  art decode+colorize), copied from the sibling `logie-github/Test` repo
  with internal `require("src.tcg.*")` calls rewritten to
  `require("mods.pokemon_tcg.src.tcg.*")`. Source of truth for behavior:
  `pret/poketcg` at commit `7a75fe810e91dda43538b249c70ee5da14e38686`.
- `data/tcg_manifest.lua` -- the recipe described above.
- `transforms.lua` -- unused for now; reserved for deriving art from the
  player's own Red cache later, per this engine's asset-provenance rules.

## Loop

1. `POKEPORT_DEV=1 love .` once, leave it running.
2. Import a Red ROM as usual, then supply your own Pokemon Trading Card
   Game ROM when the mod's import prompt asks for it.
3. Press **F10**, find "Pokemon Trading Card Game" in the mod manager, and
   enable it (it's `experimental`, so it starts off).
4. `python3 tools/modkit.py lint mods/pokemon_tcg` and
   `python3 tools/modkit.py validate mods/pokemon_tcg` before sharing.
5. `python3 tools/modkit.py pack mods/pokemon_tcg` to ship.
