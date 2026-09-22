# Pokémon Trading Card Game (GBC) → Gen1Recomp

A from-scratch Lua/LÖVE port of `pret/poketcg` — the decompilation of the
Game Boy Color **Pokémon Trading Card Game** — built to run as a mod
inside [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp) (the
Pokémon Red/Blue/Yellow decompilation-recompilation project). It ships no
ROM bytes of its own: every card, deck, text string and piece of art is
read from **your own legally dumped ROM** at runtime, the same way
Gen1Recomp itself works.

## What "the project" actually is

Two things live in this repo:

1. **`src/tcg/`** — the duel engine itself: memory model, RNG, deck
   loading, duel setup, turn flow, combat/damage, status conditions,
   prizes, knockouts, every attack/Pokémon Power/Trainer card effect, and
   a complete AI opponent (covers all 19 real AI behavior tables the
   cartridge defines, including all 5 legendary "boss" decks). This is a
   line-by-line translation of the real Game Boy assembly in
   [`pret/poketcg`](https://github.com/pret/poketcg), not a
   reimplementation from memory — see "Source of truth" below.
2. **`gen1recomp_mod/pokemon_tcg/`** — that engine packaged as an
   installable Gen1Recomp mod (`profile: total_conversion`). This is the
   part you actually run. `gen1recomp_mod/build.sh` regenerates it from
   `src/tcg/` (rewrites `require()` paths into the mod's namespace, drops
   a couple of dev-only files); the two never drift apart by hand-editing.

## What files need to be imported from a ROM

Two, both supplied by *you*, from ROMs you legally own — this project
never contains, ships, or generates ROM bytes:

1. **A Pokémon Red/Blue/Yellow ROM.** Gen1Recomp itself requires this as
   its base import regardless of which mod you run; this mod rides on it
   for shared engine infrastructure (it doesn't reuse any of Red's actual
   game data — species, moves, maps — only its role as the required base).
2. **The Pokémon Trading Card Game ROM** — a completely different
   cartridge from Red/Blue/Yellow, not a hack of them. This is what
   actually supplies every card, deck, and piece of art the duel engine
   uses. The mod declares it as a `required_imports` entry in
   `gen1recomp_mod/pokemon_tcg/manifest.json`:

   | | |
   |---|---|
   | File | `pokemontcg.gbc` |
   | Size | 1,048,576 bytes (1 MiB) |
   | MD5 | `219b2cc64e5a052003015d4bd4c622cd` |
   | SHA-1 | `0f8670a583255cff3e5b7ca71b5d7454d928fc48` |
   | Release | Pokémon Trading Card Game (USA) |

   Once both ROMs are imported through Gen1Recomp's own launcher (never
   through this repo or this mod directly), the mod reads the TCG ROM's
   bytes in memory for one session via `mod.imports:read(...)` and never
   writes them back to disk — see `gen1recomp_mod/pokemon_tcg/README.md`
   for the exact mechanism and its legal posture.

## Source of truth

- [`pret/poketcg`](https://github.com/pret/poketcg) (commit
  `7a75fe810e91dda43538b249c70ee5da14e38686`) is the source of truth for
  every rule, quirk, and bug this engine reproduces.
- ROM addresses come from RGBDS `poketcg.sym`, built from that same
  source — never hand-guessed offsets.
- `tools/tcg/build_manifest.py` extracts a manifest (symbol addresses,
  card/deck layouts, effect-command identities, every constant referenced
  anywhere in `src/tcg/`) from the decomp source; `src/tcg/import/
  RomExtractor.lua` cross-checks that manifest against the player's actual
  ROM bytes at runtime and refuses to proceed on any mismatch.

## Status

- **The duel engine and AI are the most complete part.** All 19 real AI
  behavior tables are translated and were exercised for real this
  session — not just Sam's scripted practice duel, but the general
  opponent AI playing an actual, non-scripted deck.
- **Two playable modes**, both booting through the mod's `PokemonTCG`
  screen:
  - **Free duel** (the default): your Squirtle-and-Friends deck against
    the AI's Charmander-and-Friends deck — two real pre-built ROM decks,
    with a menu built fresh each turn from your actual hand and field.
    Validated by actually playing it end to end (real boot, interactive
    setup, 8 real turns, a real win/loss) against a from-source-built
    `poketcg.gbc`. The matchup is fixed for now (no deck-picker menu
    yet); a few Trainer cards that need a picker over deck/discard
    contents (Computer Search, Item Finder, Poké Ball) aren't wired into
    the menu yet. See `src/tcg/duel/DuelSession.lua`'s header for the
    full, current disclosure.
  - **Sam's practice duel** (automatic fallback if the free duel fails to
    boot): the scripted 7-turn tutorial duel.
  - Both render real, colorized card art (decoded from your ROM's
    embedded GBC palettes) with HP bars, not placeholder text.
- **Not yet built:** deck construction/selection UI, the cartridge's own
  menu chrome (the current screen is a native, stylized approximation),
  overworld/story/save-file systems outside a duel.

## Using it

1. Get a local checkout of `bryanthaboi/gen1recomp` with LÖVE installed.
2. `bash gen1recomp_mod/build.sh`, then copy
   `gen1recomp_mod/pokemon_tcg/` into that checkout's `mods/` directory.
3. Launch, import your Red ROM as usual, then supply your Pokémon TCG ROM
   when the mod's import prompt asks for it.
4. Press **F10** to open the mod manager and enable "Pokemon Trading Card
   Game" — it's flagged `experimental`, so it starts off.
5. `python3 tools/modkit.py lint mods/pokemon_tcg` and
   `python3 tools/modkit.py validate mods/pokemon_tcg` (from the
   Gen1Recomp checkout) before sharing a build.

## Tests

```sh
python3 -m unittest discover -s tests/tcg -p 'test_*.py' -v
```

504 tests across 84 files: source-shape assertions plus real LuaJIT
execution smoke tests (`tests/tcg/lua_fixtures/`) for every translated
module — not just that a function exists, but that calling it does the
right thing against representative data.

## Repo layout

- `src/tcg/` — the engine (canonical source; edit here).
- `gen1recomp_mod/` — the packaged mod (`build.sh` regenerates
  `pokemon_tcg/src/tcg/` from the canonical tree; `manifest.json`,
  `main.lua`, `README.md`, `data/tcg_manifest.lua` are hand-maintained).
- `tests/tcg/` — Python test suite plus LuaJIT fixtures it shells out to.
- `tools/tcg/build_manifest.py` — builds the extraction manifest from a
  `pret/poketcg` checkout + its RGBDS `.sym` file.
- `tools/tcg/behavior_coverage.json` / `behavior_pending.json` — the
  translation ledger: which decomp routines are translated, to where,
  and what's left.
