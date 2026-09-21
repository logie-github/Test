# MASTER AI HANDOFF — Pokémon TCG GB -> Gen1Recomp Lua/LÖVE

## 1. Project scope

Port the complete **Pokémon Trading Card Game for Game Boy** behavior from `pret/poketcg` into the Gen1Recomp Lua/LÖVE runtime.

This is a **full-game port**, not only a duel-engine or AI project. The end state must cover:

- ROM/source import and generated data products;
- memory/duel variable model and RNG/shuffle behavior;
- card/deck/hand/discard/play-area operations;
- duel setup, turns, status, prizes, knockouts and combat;
- every effect-command list and Pokémon Power/Trainer path;
- CPU AI, including generic and deck-specific policies;
- original duel UI/presentation and selection flows;
- link/serial duel behavior;
- overworld, scripts, NPCs, events and progression;
- collection/deck machines/album/trades/Card Pop;
- full-game save/progression state;
- graphics, audio, animations, timing and other hardware-facing replacements.

The current codebase is a source-backed partial port with a playable Sam practice-duel vertical slice and a substantially generalized duel/AI engine.

## 2. Source-of-truth contract

Behavior truth is **`pret/poketcg`**, not intuition or modern TCG rules.

Rules for every continuation:

1. Preserve cartridge ordering, quirks and bugs when source code does so.
2. Do not silently substitute heuristics for untranslated source behavior.
3. Unsupported behavior must fail closed or remain an explicit adapter boundary.
4. Source effect-command identity/order matters; avoid flattening effects into damage-only approximations.
5. Keep ROM-address behavior driven by the matching RGBDS symbols/generated manifest, not handwritten offsets.
6. Do not claim end-to-end runtime validation unless the user ROM, matching `poketcg.sym`/generated cache, and LÖVE runtime are actually available and exercised.

Latest source revision used during the AI translation work was the current `pret/poketcg` tree around commit/ref:

`7a75fe810e91dda43538b249c70ee5da14e38686`

Supported ROM profile documented by the project:

- Pokémon Trading Card Game (U) [C][!]
- SHA-1: `0f8670a583255cff3e5b7ca71b5d7454d928fc48`

## 3. Current promoted checkpoint

Engineering estimates, not audited byte coverage:

- **~56% entire game**
- **~95% AI subsystem**
- **662 fully translated source labels**
- **62 partial labels across 27 partial entries**
- **54 explicit remaining items** in the pending ledger
- **248/310 ordinary player-side nonempty effect-command lists complete**
- **4/4 played-Pokémon trigger-power tables complete**
- **81/81 unique `EFFECTCMDTYPE_AI` identities complete**
- **45/45 unique `EFFECTCMDTYPE_AI_SELECTION` identities complete**
- **5/5 unique `EFFECTCMDTYPE_AI_SWITCH_DEFENDING_PKMN` identities complete**
- **212/212 Python unit/source tests pass**
- **28/28 Lua modules parse with `texluac -p`**
- Python tooling/tests pass `py_compile`

The first playable vertical slice is still **Sam's scripted practice duel**: all eight player turns and seven scripted Sam turns through a temporary host UI.

## 4. What was just completed

This generation closes the generic no-play Energy preview used by Energy Trans and the planned common retreat branches.

Promoted tracked source labels:

- `AIProcessAndTryToPlayEnergy`
- `AIProcessEnergyCards`
- `AITryToPlayEnergyCard`

Important completed behavior:

- `AIProcessButDontPlayEnergy_SkipEvolutionAndArena` now preserves/restores score state and uses the source skip-evolution Energy score path;
- the source quirk is preserved where Arena is scored even though the final winner scan checks Bench only;
- the Bench-only winner scan has no `$85` threshold and keeps the earlier slot on ties;
- Energy Trans runs the preview as an initial viability test and again before every Grass Energy moved from Active to Bench;
- common retreat now includes boss/progression last-prize gates, Energy-for-retreat flags, Porygon's special weakness branch and full setup-count/fully-powered scoring;
- Mysterious Fossil/Clefairy Doll now execute their source trainer-as-Pokémon discard Power path instead of returning an untranslated retreat error.

The only explicit common-retreat gap left is the potential-KO branch where a currently unusable attack can become relevant after one Energy from hand.

## 5. Immediate work in progress / exact next slice

### Priority 1 — final common retreat Energy edge

Separate “potential KO damage” from “currently usable KO attack” exactly as the source does, then wire the one-Energy-from-hand branch without changing unrelated callers of the existing damage estimator.

### Priority 2 — remaining Trainer AI

Continue the unresolved Trainer decision/play families: Super Potion, Pokémon Breeder, Imposter Professor Oak, Scoop Up, Lass, Imakuni?, Gambler, Clefairy Doll, Mysterious Fossil, Computer Search and Pokémon Trader.

### Priority 3 — specialized deck/Power policy

Continue specialized deck action-table overrides and remaining Pokémon Power policy from `tools/tcg/behavior_pending.json`.

## 6. Major long-term unfinished systems

Do not confuse ~56% duel-engine progress with a nearly finished full game. Large systems remain:

- original duel renderer, menus, card-list UI and animations;
- link/serial synchronization implementation;
- overworld, club/NPC scripts, events and story progression;
- collection/deck-building machines, album, trades and Card Pop;
- general full-game saves/progression;
- audio/graphics/timing/hardware-facing behavior.

See `FULL_BREAKDOWN.md` and `tools/tcg/behavior_pending.json` for the current explicit boundaries.

## 7. Key implementation files

Primary Lua modules:

- `src/tcg/duel/AI.lua` — CPU turn core, attack scoring, selectors, retreat/switch, Trainer/Power policies.
- `src/tcg/duel/EffectCommands.lua` — source effect-label handlers and selection/effect logic.
- `src/tcg/duel/Combat.lua` — attack loading, phase dispatch, damage/effect execution.
- `src/tcg/duel/DuelOps.lua` — card/deck/play-area operations.
- `src/tcg/duel/DuelVars.lua` / `src/tcg/memory/Memory.lua` — source-shaped duel state and memory model.
- `src/tcg/duel/Status.lua` — status/substatus/prevention/between-turn state.
- `src/tcg/duel/KnockOuts.lua`, `Prizes.lua`, `TurnFlow.lua`, `DuelSetup.lua` — duel lifecycle.
- `src/tcg/duel/PlayerActions.lua` — host/player card/action boundaries.
- `src/tcg/duel/Practice.lua`, `PracticeSession.lua`, `states/PracticePlayable.lua` — Sam practice vertical slice.
- `src/tcg/import/RomExtractor.lua` / `tools/tcg/build_manifest.py` — source/symbol/ROM data pipeline.

Coverage/accounting:

- `tools/tcg/behavior_coverage.json`
- `tools/tcg/behavior_pending.json`
- `tools/tcg_translation_ledger.json` (generated by `build_manifest.py` when a matching local decomp/symbol build is available)
- `PERCENTAGE_STATUS.md`
- `FULL_BREAKDOWN.md`

## 8. Validation contract after every generation

Run all three before promotion/package:

```sh
python -m unittest discover -s tests/tcg -p 'test_*.py'
python -m py_compile tools/tcg/*.py tests/tcg/*.py
find src/tcg -name '*.lua' -print0 | xargs -0 -n1 texluac -p
```

Then:

1. update coverage/pending ledgers;
2. recount translated labels and ordinary effect lists from actual ledger data;
3. update `GENERATION_STATUS.md`, `PERCENTAGE_STATUS.md`, `HANDOFF_CURRENT_WORK.md`, `NEXT_GENERATION_RESEARCH.md`, `START_HERE_HANDOFF.md`, `README.md`, `FULL_BREAKDOWN.md`, `CHANGELOG.md`, `VALIDATION.txt`, and `NEW_CHAT_PROMPT.txt` as applicable;
4. regenerate `FILE_INVENTORY.txt` and `HANDOFF_INVENTORY_SHA256.txt`;
5. build a fresh ZIP;
6. extract that ZIP to a clean directory;
7. verify every recorded SHA-256 hash;
8. rerun tests, py_compile, and Lua parsing from the clean extraction.

## 9. Progress-reporting requirement

After every implementation generation report at minimum:

- whole-game completion percentage;
- AI completion percentage;
- fully translated label count;
- ordinary player-side effect-list count;
- generic AI count;
- AI-selection count;
- forced-switch count;
- test count/status;
- Lua parse count/status;
- exactly what was completed;
- exactly what comes next.

Percentages are engineering estimates and must not be presented as audited byte coverage.

## 10. Environment caveat at this handoff

This environment did **not** have the user's ROM, matching built `poketcg.sym`/generated ROM cache, or a usable LÖVE executable for a fresh end-to-end launch. Current validation is source/unit/static validation plus the previously developed practice/runtime architecture. Do not claim a fresh live ROM/LÖVE pass unless a future environment actually performs it.

## 11. Recommended first action for the next AI

Read, in this order:

1. `HANDOFF_RECORD.md`
2. `AI_HANDOFF_MASTER.md`
3. `START_HERE_HANDOFF.md`
4. `HANDOFF_CURRENT_WORK.md`
5. `NEXT_GENERATION_RESEARCH.md`
6. `tools/tcg/behavior_pending.json`
7. `tools/tcg/behavior_coverage.json`
8. `src/tcg/duel/AI.lua`
9. the relevant source-regression tests in `tests/tcg/`

The user's active directive is to **finish the AI subsystem**. First close the final retreat potential-KO + one-Energy-from-hand edge without changing unrelated KO/damage-estimator semantics. Then finish the remaining Trainer decision/play families, followed by specialized deck action tables and unresolved Pokémon Power policy. Recount the actual ledgers before declaring AI complete.
