# Pokémon TCG -> Gen1Recomp translation

> **2026-09-19 checkpoint:** Energy Trans now uses the cartridge no-play/skip-Arena Energy preview, common retreat boss/setup and Fossil/Doll branches are translated, and the common Energy labels are fully promoted. Current accounting is 662 translated labels, 248/310 ordinary player-side effect lists, 81/81 generic AI-effect identities, 45/45 AI-selection identities, 5/5 AI-switch identities, and 212/212 tests.


This package is the current source-backed translation slice for porting `pret/poketcg` into the Gen 1 Recompilation Project's Lua/LÖVE runtime.

## Source contract

- `pret/poketcg` is the source of truth for behavior, layouts, data, quirks and bugs.
- Supported ROM: Pokémon Trading Card Game (U) [C][!], SHA-1 `0f8670a583255cff3e5b7ca71b5d7454d928fc48`.
- Runtime data/assets come from the user's validated ROM.
- ROM addresses come from matching RGBDS `poketcg.sym`; TCG structures are not based on handwritten ROM offsets.
- Declarative layouts/constants/table order and effect-command identities are generated from the matching decomp source.
- A player-ready full-game build remains gated until translation accounting reaches 100%. `POKEPORT_TCG_ALLOW_PARTIAL=1` is development-only.

## Current checkpoint

Working engineering estimate: **~56% of the full game**. See `PERCENTAGE_STATUS.md` and `FULL_BREAKDOWN.md` for scope and limitations.

The first playable vertical slice remains **Sam's original practice duel**: all eight player turns and seven scripted Sam turns through a temporary LÖVE state. The UI is host presentation rather than the original cartridge duel renderer.

This generation closes the final tracked common Energy preview mode and the planned common retreat branches:

- Energy Trans uses the source `DONT_PLAY | SKIP_EVOLUTION | SKIP_ARENA_CARD` score preview with score-array backup/restore;
- the preview still scores Arena, selects only Bench, has no `$85` floor and keeps the lower Bench slot on ties;
- transfer-to-Bench recalculates the preferred target before every Grass Energy move;
- common retreat includes source boss/progression last-prize gates, Energy-for-retreat flags, Porygon handling and fully-powered/setup-count scoring;
- Mysterious Fossil/Clefairy Doll execute their trainer-as-Pokémon discard Power during retreat;
- player-side ordinary effect coverage remains **248/310 nonempty effect-command lists**, with all **4/4** played-Pokémon trigger tables translated.

The earlier foundation remains: effect-table ROM/source extraction, common damage/prevention math, exact RNG/shuffle, address-based WRAM/HRAM/SRAM, card/deck extraction, source-format duel SRAM snapshots/rewind, prize/KO state, status/between-turn processing, scripted Sam AI and the playable practice coordinator.

## Manifest + ledger

Build `pret/poketcg` so the matching `poketcg.sym` exists, then run:

```sh
python tools/tcg/build_manifest.py \
  --decomp /path/to/poketcg \
  --sym /path/to/poketcg.sym \
  --out tools/tcg_rom_manifest.json \
  --ledger tools/tcg_translation_ledger.json

python tools/tcg/check_coverage.py \
  tools/tcg_rom_manifest.json tools/tcg_translation_ledger.json
```

Manifest schema 5 fingerprints canonical source/build inputs, includes source-ordered effect-command identities, and imports the AI-specific constants required by the native turn core. ROM import checks those identities against actual ROM bytes and RGBDS symbols before cache generation.

## Install into Gen1Recomp

```sh
python tools/tcg/apply_foundation.py /path/to/pokemon-gen1-recomp-project
```

The installer requires the v5 generated TCG data product. Older v4 caches are intentionally re-extracted so AI constants cannot be missing from a reused cache.

Development launch:

```sh
POKEPORT_TCG_ALLOW_PARTIAL=1 love .
```

Playable Sam practice checkpoint:

```sh
POKEPORT_TCG_PRACTICE=1 love .
```

## Tests

```sh
python -m unittest discover -s tests/tcg -p 'test_*.py' -v
```

Current checkpoint: **212/212 tests pass**. Python tooling compiles and all **28** Lua modules parse with Lua 5.3/texlua. A LÖVE executable and user-generated ROM cache were not present in this build environment, so this checkpoint is not claimed as an end-to-end LÖVE execution here.

## Next translation slice

Close the remaining retreat potential-KO/one-Energy-from-hand edge branch, then continue the unresolved Trainer AI families. After that, continue specialized deck action tables, remaining Pokémon Power policy, unresolved ordinary card effects, and the larger UI/overworld/save/audio systems.

---

## 2026-09-19 handoff

For the current project state and exact next AI-completion work, start with `START_HERE_HANDOFF.md`, then `HANDOFF_RECORD.md` and `LATEST_AI_RESEARCH.md`.
