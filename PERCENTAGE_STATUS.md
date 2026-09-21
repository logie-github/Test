# Percentage status

- **Whole-game engineering estimate: ~56%.**
- **AI subsystem engineering estimate: ~95%.**
- These are engineering estimates, not audited source-byte coverage.

Validated persisted accounting:

- 662 fully translated source labels;
- 248/310 ordinary player-side nonempty effect-command lists;
- 4/4 played-Pokémon trigger tables;
- 81/81 unique generic `EFFECTCMDTYPE_AI` identities;
- 45/45 unique `EFFECTCMDTYPE_AI_SELECTION` identities;
- 5/5 unique `EFFECTCMDTYPE_AI_SWITCH_DEFENDING_PKMN` identities;
- 62 partial labels across 27 pending entries;
- 54 explicit remaining items;
- 212/212 tests passing;
- 28/28 Lua modules parse.

AI is close but not complete. The remaining work is concentrated in specialized deck action tables, the final retreat Energy/KO edge, Trainer decision/effect/relist behavior, hidden Mewtwo-mill state, and rare specialized Trainer/Power/core policies.
