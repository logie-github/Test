# Current work — finish the AI subsystem

## Durable state

- ~56% whole game.
- ~95% AI.
- 212/212 tests passing.
- 662 translated labels.
- 62 partial labels / 27 pending entries / 54 explicit remaining items.
- 248/310 ordinary player-side effect lists.
- Generic AI effect identities are complete: 81/81 AI, 45/45 AI selection, 5/5 AI switch.

## Last fully promoted implementation slice

The persisted source already contains the completed generic Energy no-play preview and common retreat work documented by the previous handoff:

- source-shaped `AIProcessButDontPlayEnergy_SkipEvolutionAndArena` score backup/restore and Bench-only final selection;
- repeated Energy Trans preview before moved Grass Energy;
- boss/progression last-prize retreat gates and Energy-for-retreat flags;
- fully-powered/setup-count scoring;
- Porygon weakness special handling;
- Mysterious Fossil/Clefairy Doll trainer-as-Pokémon discard Power path used by retreat.

## Work performed after that checkpoint

The latest session reviewed the remaining source in `pret/poketcg` but did not promote new code into the persistent tree. The important findings are written in `LATEST_AI_RESEARCH.md`, including:

- specialized `DeckAIPointerTable` routing and exact generic/no-retreat turn order;
- boss start-deck/hand setup behavior and its prize-avoidance source bug;
- specialized Legendary Moltres/Zapdos/Articuno/Dragonite/Ronald turn behavior;
- remaining Trainer decision/play policies and player-side effects;
- exact hidden Mewtwo-mill detector semantics.

## Immediate implementation order

### 1. Retreat potential-KO Energy edge

Separate "attack can deal KO damage" from "attack is currently usable" only for the callers that require it. Then implement the source's `LookForEnergyNeededForAttackInHand` behavior: one missing Energy, or exactly two Colorless satisfied by Double Colorless Energy. Do not globally relax existing attack-usability helpers.

### 2. Remaining Trainer AI/effects

Translate decision + play/effect mutation together so normal Trainer processing can execute the chosen card:

- Super Potion;
- Pokémon Breeder;
- Imposter Professor Oak;
- Scoop Up;
- Lass;
- Imakuni?;
- Gambler;
- Clefairy Doll / Mysterious Fossil;
- Computer Search;
- Pokémon Trader.

Preserve cartridge quirks, including Pokémon Trader Power Generator's missing-branch bug boundary; do not silently correct original behavior unless the port explicitly models the original invalid-state consequence.

### 3. Trainer relist cadence

Complete exact `_AIProcessHandTrainerCards` snapshot/table ordering and modified-hand relisting. Professor Oak is especially important because the source re-runs a defined subset of phases after drawing a new hand.

### 4. Specialized deck tables

Implement per-deck `AIDoAction_StartDuel` and `AIDoAction_Turn` routing. Reuse generic logic when the source table does. Add only the source-specific overrides.

### 5. Hidden Mewtwo-mill detector

Finish the three-consecutive-Barrier detector and anti-mill state machine from `src/engine/duel/ai/init.asm` and `common.asm`.

### 6. Residual AI policy

Finish rare Professor Oak/Energy Removal branches, unusual attack-usability/color edge cases, and remaining Pokémon Power policy.

## Do not claim AI completion until

- all AI-related `behavior_pending.json` items are cleared or narrowed to presentation-only choreography;
- the full tests pass;
- Lua parses;
- the updated coverage ledger is recounted from the actual source tree.
