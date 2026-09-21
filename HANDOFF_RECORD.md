# Handoff record — 2026-09-19

## Purpose

This package is a durable handoff for the Pokémon TCG GB -> Gen1Recomp Lua/LÖVE project. The active user directive is to **complete the AI subsystem**.

## Project scope

See `PROJECT_SCOPE.md`. This is a complete game port from `pret/poketcg`, not an AI-only project. AI completion is the current milestone, after which the project continues through remaining effects, duel UI/presentation, link/serial, overworld/story, collection/deck systems, saves, graphics/audio/timing and hardware replacement.

## Authoritative current checkpoint

Engineering estimates:

- whole game: ~56%;
- AI: ~95%.

Auditable persisted accounting:

- 662 fully translated labels;
- 62 partial labels across 27 pending entries;
- 54 explicit remaining items;
- 248/310 ordinary player-side nonempty effect-command lists;
- 4/4 played-Pokémon trigger tables;
- 81/81 unique generic AI-effect identities;
- 45/45 AI-selection identities;
- 5/5 AI-switch identities;
- 212/212 Python unit/source tests;
- 28/28 Lua modules parse.

## Major implemented systems already present

The source tree contains a generalized duel foundation beyond the original practice slice, including:

- source-shaped duel memory/state and RNG abstractions;
- deck/card/hand/discard/play-area operations;
- duel setup/turn/KO/prize/status/combat modules;
- a large translated EffectCommands surface;
- attack scoring and damage estimation;
- generic AI turn core and many Trainer/Power selections;
- Energy placement policy and deck-specific Energy scoring/list data;
- common retreat/switch scoring including multiple source quirks;
- Sam's full scripted practice duel vertical slice;
- symbol/ROM extraction and manifest tooling.

The last promoted AI generation specifically completed the generic no-play Energy preview used by Energy Trans and most common retreat branches, including boss/progression gates, Porygon weakness behavior, setup-count scoring, and Mysterious Fossil/Clefairy Doll retreat Power handling.

## Latest session activity

The latest session was asked to complete AI. It performed source review of the remaining deck action tables, Trainer decisions/effects, boss startup and Mewtwo-mill detector. No new implementation from that source review was promoted to this persistent tree before the handoff request. See `LATEST_AI_RESEARCH.md` for the findings.

Earlier ephemeral chat-side work may have reported a higher passing-test count. Because those edits are absent from this package and cannot be clean-extracted or audited here, they are not part of the promoted checkpoint. Reconstruct any useful changes from source/research and validate them normally.

## Exact next implementation sequence

1. Retreat potential-KO + Energy-from-hand edge.
2. Remaining Trainer AI/effect families.
3. `_AIProcessHandTrainerCards` exact snapshot/relist cadence.
4. Specialized deck StartDuel/Turn tables and boss setup/list quirks.
5. Mewtwo Lv53 Barrier/mill detector and anti-mill branch.
6. Remaining rare Trainer/Power/core usability policy.
7. Recount ledgers and only then declare AI complete.

## Validation performed for this package

A fresh extraction of the source checkpoint was validated during packaging:

```text
Ran 212 tests ... OK
Python py_compile: PASS
Lua texluac parse: 28/28 PASS
```

No live ROM extraction/LÖVE run is claimed because the required user ROM/cache/runtime was not present.

## Source truth

Use `pret/poketcg` ref `7a75fe810e91dda43538b249c70ee5da14e38686` for this handoff's comparisons unless intentionally updating the baseline. Preserve original cartridge quirks and bugs.
