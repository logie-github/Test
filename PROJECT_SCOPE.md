# Project scope — Pokémon TCG GB -> Gen1Recomp Lua/LÖVE

## Goal

Port the complete behavior of `pret/poketcg` (Pokémon Trading Card Game for Game Boy) into the Gen1Recomp Lua/LÖVE runtime.

This is a full-game port, not only an AI project. The decomp is the behavior source of truth. Preserve source ordering, quirks, and bugs. Do not invent substitute behavior for untranslated paths; keep unsupported behavior explicit/fail-closed.

## Full scope

The end state must cover:

- ROM/source import, symbol-driven extraction, and generated data products;
- memory model, duel variables, RNG, shuffle and deck/card operations;
- duel setup, turn flow, combat, status, prizes, knockouts and replacement;
- all attack, Pokémon Power and Trainer effect-command families;
- complete CPU AI: generic logic, deck-specific action tables, Trainer policy, Pokémon Power policy, switching/retreat, prizes and start-of-duel setup;
- cartridge duel menus, card-list selections, animations, timing and presentation;
- link/serial duel behavior;
- overworld, NPC/event scripts, clubs and story progression;
- collection, deck building/machines, album, trades and Card Pop;
- save/progression state;
- graphics, audio and hardware-facing replacements.

## Source contract

- Source truth: `pret/poketcg`.
- Reference used by this checkpoint: `7a75fe810e91dda43538b249c70ee5da14e38686`.
- Supported ROM profile documented by the project: Pokémon Trading Card Game (U) [C][!], SHA-1 `0f8670a583255cff3e5b7ca71b5d7454d928fc48`.
- Do not claim live end-to-end validation without the user's ROM, matching symbol/generated cache, and LÖVE runtime.
