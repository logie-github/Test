# START HERE — TCG handoff, 2026-09-19

## User directive

**Finish the AI subsystem**, then continue the complete Pokémon TCG GB -> Gen1Recomp Lua/LÖVE port.

## Authoritative persisted checkpoint in this ZIP

Use the files in this ZIP as the source tree. They were clean-extracted and revalidated while creating this handoff.

- Whole-game engineering estimate: **~56%**.
- AI engineering estimate: **~95%**.
- **662** fully translated source labels.
- **62** partial labels across **27** pending entries.
- **54** explicit remaining items in the pending ledger.
- **248/310** ordinary player-side nonempty effect-command lists complete.
- **4/4** played-Pokémon trigger-power tables complete.
- **81/81** unique `EFFECTCMDTYPE_AI` identities complete.
- **45/45** unique `EFFECTCMDTYPE_AI_SELECTION` identities complete.
- **5/5** unique `EFFECTCMDTYPE_AI_SWITCH_DEFENDING_PKMN` identities complete.
- **212/212** Python unit/source tests pass.
- **28/28** Lua modules parse with `texluac -p`.
- Python tooling/tests compile with `py_compile`.

The first playable vertical slice remains Sam's scripted practice duel through the temporary host UI.

## Important checkpoint distinction

There was later chat-side exploration of the remaining AI, and earlier ephemeral work in the conversation reportedly reached a larger test count, but those edits are **not present in the durable source tree in this ZIP**. Do not treat chat claims as merged implementation. The **212-test / 662-label tree in this package is authoritative**.

The latest session did perform useful source research. That research is captured in `LATEST_AI_RESEARCH.md` and should be used to reconstruct the next implementation slice without repeating the source-discovery work.

## Exact next step

1. Close the common retreat potential-KO + one-Energy-from-hand edge while keeping caller-specific usability semantics.
2. Translate the remaining Trainer AI decision/play families and their corresponding player-side effects where required: Super Potion, Pokémon Breeder, Imposter Professor Oak, Scoop Up, Lass, Imakuni?, Gambler, Clefairy Doll/Mysterious Fossil, Computer Search, Pokémon Trader.
3. Preserve exact `_AIProcessHandTrainerCards` hand-snapshot/relist ordering.
4. Implement specialized deck start/turn action tables from `DeckAIPointerTable`, including boss setup/list-pointer quirks.
5. Implement the exact Mewtwo Lv53 Barrier/mill detector in `InitAITurnVars` / anti-mill branch.
6. Finish remaining specialized Pokémon Power/core usability and rare Trainer policy branches.
7. Recount `behavior_coverage.json` / `behavior_pending.json`; only call AI complete when the AI-related pending items are actually exhausted or explicitly bounded as presentation-only adapters.

## Read next

1. `HANDOFF_RECORD.md`
2. `HANDOFF_CURRENT_WORK.md`
3. `LATEST_AI_RESEARCH.md`
4. `PROJECT_SCOPE.md`
5. `AI_HANDOFF_MASTER.md`
6. `tools/tcg/behavior_pending.json`
7. `tools/tcg/behavior_coverage.json`
8. `src/tcg/duel/AI.lua`
9. related tests under `tests/tcg/`

## Validation commands

```sh
python -m unittest discover -s tests/tcg -p 'test_*.py'
python -m py_compile tools/tcg/*.py tests/tcg/*.py
find src/tcg -name '*.lua' -print0 | xargs -0 -n1 env TERM=xterm texluac -p
```
