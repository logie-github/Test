# Next-generation research notes

## Immediate slice: final common retreat edge + Trainer AI

Energy's generic preview modes are now translated and the transfer-to-Bench Energy Trans target is source-shaped. Common retreat boss/setup/Fossil-Doll branches are also in place.

Primary target: close the remaining retreat future-KO/one-Energy branch without changing the meaning of generic damage estimators used elsewhere.

Source behavior to preserve:

- `CheckIfAnyAttackKnocksOutDefendingCard` estimates KO potential before usability is checked;
- `AIDecideWhetherToRetreat` and `AIDecideBenchPokemonToSwitchTo` then call `CheckIfSelectedAttackIsUnusable` on the selected KO attack;
- where applicable, `LookForEnergyNeededForAttackInHand` may make that otherwise-unusable KO attack relevant if exactly the required Energy can be supplied;
- do not make every caller of the Lua KO helper suddenly treat unusable attacks as immediately usable—add/source-shape the potential-KO layer deliberately;
- preserve the source `IGNORE_THIS_ATTACK` and one/two-Colorless handling order.

After that, the best bounded block is the remaining Trainer decision/play families in `trainer_cards.asm`:

- Super Potion;
- Pokémon Breeder;
- Imposter Professor Oak;
- Scoop Up;
- Lass;
- Imakuni?;
- Gambler;
- Clefairy Doll;
- Mysterious Fossil;
- Computer Search;
- Pokémon Trader.

Then continue specialized deck action tables and unresolved Pokémon Power policy.

## Cartridge quirks preserved by the completed generation

- `AI_ENERGY_FLAG_SKIP_ARENA_CARD` affects only the final Energy-target winner scan; Arena is still scored first;
- the Bench-only Energy preview has no `$85` score floor;
- equal preview scores keep the earlier/lower Bench slot;
- `wPlayAreaAIScore` and `wAIScore` are restored after every no-play preview;
- Energy Trans recalculates the preferred Bench target before every Grass Energy move;
- boss/progression last-prize retreat branches are gated by `CheckIfNotABossDeckID` semantics, not simply by whether the defender can KO;
- the setup heuristic encourages by the actual count returned when at least two Bench Pokémon qualify;
- Mysterious Fossil/Clefairy Doll use their pseudo-Pokémon Discard Power rather than paying a retreat cost.
