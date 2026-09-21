## 2026-09-19 — Energy Trans preview + common retreat closure

- Translated the generic no-play/skip-evolution/skip-Arena Energy score preview used by Energy Trans, including score backup/restore, no `$85` Bench threshold and earlier-slot tie behavior.
- Energy Trans now re-runs the source preview before every Grass Energy transferred from Active to Bench.
- Completed common retreat boss/progression last-prize scoring, Energy-for-retreat flags, Porygon weakness handling and fully-powered/setup-count heuristics.
- Added Mysterious Fossil/Clefairy Doll trainer-as-Pokémon discard-Power execution during retreat.
- Promoted `AIProcessAndTryToPlayEnergy`, `AIProcessEnergyCards`, and `AITryToPlayEnergyCard`.
- Added four source/regression tests; suite is now **212/212**.
- Promoted accounting is **662 translated labels**, **62 partial labels / 27 partial entries / 54 explicit remaining items**, with **248/310** ordinary player effect lists unchanged.
- Engineering estimate remains **~56% whole game** and rises to **~95% AI**.

## 2026-09-19 — deck AI lists + Energy policy

- Added source parsing and ROM-validation for all six specialized deck AI list families.
- Wired exact play-from-hand ordering and promoted `AIDecidePlayPokemonCard` / `AIDecideEvolution`.
- Wired generated Energy cap/bonus and retreat-bonus lists, preserving missing retreat-pointer initialization bugs.
- Expanded normal Energy scoring through evolution anticipation, attached-Energy boost/discard, Legendary Articuno priority and repeated-Bench policy.
- Expanded Energy-card choice through special DCE anticipation and boss-deck DCE avoidance; Energy Spike now uses skip-evolution preview scoring.
- Added ten source/regression tests; suite is now **208/208**.
- Promoted accounting is **659 translated labels**, **65 partial labels / 28 partial entries / 58 explicit remaining items**, with **248/310** ordinary player effect lists unchanged.
- Engineering estimate remains **~56% whole game** and rises to **~94% AI**.

## 2026-09-19 — specialized attack AI + slot-aware damage estimation

## 2026-09-19 — Attack orchestration + hand/evolution AI

- Promoted `AIProcessAndTryToUseAttack` / `AIProcessAttacks` and added preview-without-execution score restoration.
- Preserved PlusPower saved-attack override, Barrier early exit, second-attack ties, phase-14 Trainer ordering and retreat-pressure updates.
- Replaced the common Basic/evolution shortcut with source-shaped score logic.
- Added Legendary Bird play policy and Legendary Dragonite / Invincible Ronald / Legendary Ronald special evolution branches.
- Preserved evolution HP, AI-info and Dragonair comparison quirks from the cartridge.
- Added six source-regression tests; suite is now **198/198**.
- Promoted accounting is **657 translated labels**, **67 partial labels / 29 partial entries / 60 explicit remaining items**, with **248/310** ordinary player effect lists unchanged.
- Engineering estimate remains **~56% whole game** and rises to **~93% AI**.

- Restored the previously completed player-side Metronome source changes that were described by the handoff docs but missing from the supplied full-project ZIP.
- Promoted `GetAIScoreOfAttack` with source-ordered common scoring, full low/high recoil policy, heal scoring, defending-KO interaction and status/discard terms.
- Promoted `HandleSpecialAIAttacks` across every source card-ID case, preserving cartridge quirks including Dugtrio Earthquake's documented pointer/prize-side bugs.
- Promoted `EstimateDamage_VersusDefendingCard` and `EstimateDamage_FromDefendingPokemon` with direct Active/Bench slot handling, switch-sensitive state clearing, slot-specific PlusPower/Defender, Active-only reduction and source poison windows.
- Replaced the reverse Bench temporary-Arena approximation with direct receiver-slot exact-KO estimation.
- Behavior coverage advances from **651 to 655** fully translated labels; partial accounting improves from **72 to 69 labels**, **31 to 30 partial entries**, and **63 to 61 explicit remaining items**.
- Ordinary player-side effect-list coverage remains **248/310**.
- Expanded regression/source coverage from **183/183 to 192/192 tests**.
- Working engineering estimate remains **~56% whole game** and advances to roughly **~92% AI**.
- Immediate next work is the remaining `AIProcessAttacks` orchestration, then hand-Pokémon/evolution scoring and unresolved Trainer/deck-specific AI policy.

## 2026-09-19 — player Metronome copied-attack execution

- Translated `HandlePlayerMetronomeEffect`, `ClefableMetronome_UseAttackEffect`, and `ClefairyMetronome_UseAttackEffect`.
- Preserved source Metronome behavior: Defending attack selection, `wMetronomeSelectedAttack` storage, name-based rejection of copying Metronome, copied `INITIAL_EFFECT_1`/`INITIAL_EFFECT_2` dispatch, and Clefable/Clefairy energy-cost overrides of 1/3.
- Left the copied attack loaded for the normal `DISCARD_ENERGY`, `REQUIRE_SELECTION`, `BEFORE_DAMAGE`, and `AFTER_DAMAGE` phases rather than flattening the copy into damage-only behavior.
- Added nested `selection.metronomeEffect` support for copied attacks that require their own player selections and an optional `sendMetronomeAttack` link-transport adapter boundary.
- Updated `Combat.useAttack` to re-read the loaded attack category after `INITIAL_EFFECT_2`, which is required when Metronome replaces the loaded attack before prevention/Transparency processing.
- Behavior coverage advances from **648 to 651** fully translated labels.
- Ordinary player-side effect-list coverage advances from **246/310 to 248/310**.
- Expanded regression/source coverage from **177/177 to 183/183 tests**.
- Working engineering estimate remains **~56% whole game / ~90% AI**.
- Immediate next work is specialized attack AI policy: `SPECIAL_AI_HANDLING`, high-recoil policy, full heal scoring, defending-KO bonus, and dependent reverse/Bench damage estimation.

## 2026-09-18 — final AI-selection identities

- Completed the final **9** unique `EFFECTCMDTYPE_AI_SELECTION` identities: Clefairy/Clefable Metronome, Pidgeotto/Spearow Mirror Move, Conversion 1/2, Prophecy, Scavenge and Wildfire.
- Preserved source quirks: Metronome AI is a literal no-op; Prophecy AI writes `$ff`; Wildfire AI chooses zero Fire Energy discards; Conversion uses its two-pass Bench color search with random colored fallback.
- Added ordinary supporting phases for both Mirror Move lists, both Conversion lists, Prophecy, Scavenge and Wildfire, advancing ordinary effect coverage to **246/310**.
- Mirror Move now replays last-turn damage, status, substatus2, Energy-discard and changed-weakness state.
- Behavior coverage advances from **609 to 648** fully translated labels.
- AI-selection coverage advances from **36/45 to 45/45**; generic AI remains **81/81** and forced-switch remains **5/5**.
- Expanded regression/source coverage from **168/168 to 177/177 tests**.
- Working engineering estimate advances to **~56% whole game / ~90% AI**.
- Metronome's player-facing copied-attack execution remains explicitly pending; no synthetic AI copied-attack behavior was added.

# Changelog

## 2026-09-18 — General AI: Special Selection, Devolution & Family Search

- Added **10** `EFFECTCMDTYPE_AI_SELECTION` identities: Barrier, Poliwhirl/Slowpoke Amnesia, Sprout, Bellsprout/Krabby/Nidoran F/Marowak Call for Family, Teleport and Devolution Beam.
- Completed the ten matching ordinary effect-command lists, advancing player-side coverage to **239/310**.
- Finished every source branch of `AISelectSpecialAttackParameters`, promoting the dispatcher from partial to translated.
- Added Mew Lv23 Devolution Beam's source KO-on-devolution target search and the complete one-stage devolution path with retained damage, status reset and return of the removed evolution card to hand.
- Added Exeggutor Teleport's special Bench-scorer branch while preserving the distinct generic `Teleport_AISelectEffect` cartridge quirk where `Random(number_in_play_area)` can return Arena slot 0.
- Added exact Amnesia attack-choice/state behavior and source-order Call for Family/Sprout deck scans, including Marowak's Basic Fighting criterion.
- AI-selection coverage advances from **26/45 to 36/45**; forced-switch identity coverage remains **5/5** and generic AI-effect coverage remains **81/81**.
- Behavior coverage advances from **567 to 609 fully translated labels**; partial accounting improves from **73 to 72 labels** across 31 partial entries / 63 explicit remaining items.
- Expanded regression/source coverage from **158/158 to 168/168 tests**.
- Working whole-game engineering estimate advances to **~54%**; AI maturity advances to roughly **~86%**.

## 2026-09-18 — General AI: Recover, Energy Absorption & Special Parameters

- Added **7** `EFFECTCMDTYPE_AI_SELECTION` identities: Starmie Recover, Kadabra Recover, Destiny Bond, Energy Conversion, both Mewtwo Energy Absorption variants and Energy Spike.
- Completed the seven matching ordinary effect-command lists, including Recover all-damage healing, Destiny Bond Psychic discard, Energy Conversion recoil/return-to-hand, Energy Absorption direct discard-to-Arena attachment, and Energy Spike Deck search/attachment.
- Added a source-shaped partial `AISelectSpecialAttackParameters` bridge: handled branches skip generic `AI_SELECTION` and reload the selected attack before use, matching `AITryUseAttack`.
- Preserved the HRAM-union semantics used by Mewtwo Energy Absorption special parameters: `hTemp_ffa0`, `hTempPlayAreaLocation_ffa1` and `hTempRetreatCostCards[0]` map to `hTempList[0..2]`.
- Added Electrode Lv35 Energy Spike special selection: search Deck order for Lightning Energy, choose an attachment target through the translated no-play Energy scoring path, and fall back to the source `$ff` generic selector when the special path cannot complete.
- Devolution Beam and Teleport special-parameter branches remain explicit fail-closed boundaries for the next generation.
- AI-selection coverage advances from **19/45 to 26/45**; forced-switch identity coverage remains complete at **5/5** and generic AI-effect coverage remains **81/81**.
- Behavior coverage advances from **537 to 567 fully translated labels**; ordinary player-side effect-list coverage advances from **222/310 to 229/310**.
- Partial-label accounting becomes **73 partial labels / 31 partial entries / 63 explicit remaining items** because `AISelectSpecialAttackParameters` is now tracked as partially translated.
- Expanded regression/source coverage from **150/150 to 158/158 tests**.
- Working whole-game engineering estimate advances to **~52%**; AI maturity advances to roughly **~82%**.

## 2026-09-18 — General AI: Lure & Forced-Switch Routing

- Added **2** `EFFECTCMDTYPE_AI_SELECTION` identities: Ninetales Lure and Victreebel Lure.
- Translated their matching Bench preflight, player-selection and switch-effect phases, including target-specific Mew Lv8 Neutralizing Shield and Haunter Lv17 Transparency checks.
- Added source-shaped `DuelistSelectForcedSwitch` ownership routing: human defender selection, link receive boundary, or AI action-table selection with attack-state reload.
- Preserved Sam practice's scripted forced-switch exception: random Bench choice before the script ends, common Bench scoring afterward.
- Promoted all **5/5** unique `EFFECTCMDTYPE_AI_SWITCH_DEFENDING_PKMN` identities.
- Translated Rhydon Ram's 20-recoil-before-switch behavior and Arbok Terror Strike's coin-gated switch with source temp-byte layout.
- AI-selection coverage advances from **17/45 to 19/45**; AI forced-switch identity coverage advances from **0/5 to 5/5**.
- Behavior coverage advances from **525 to 537 fully translated labels**; ordinary player-side effect-list coverage advances from **218/310 to 222/310**.
- Expanded regression/source coverage from **142/142 to 150/150 tests**.
- Working whole-game engineering estimate remains **~51%**; AI maturity advances to roughly **~80%**.

## 2026-09-18 — General AI: Bench-Target Selectors

- Added **5** `EFFECTCMDTYPE_AI_SELECTION` identities: Spark, Gengar Dark Mind, Hypno Dark Mind, Stretch Kick and Gigashock.
- Translated shared `AIFindTargetForBenchAttack` behavior: lowest remaining HP with later Bench slots winning equal-HP ties.
- Preserved the executable Gigashock compare/swap quirk: with 4-5 opposing Bench Pokemon, the source instructions order higher remaining HP first despite the source comment claiming lowest-first, then keep the first three targets.
- Added `Gigashock_PlayerSelectEffect` and `Gigashock_BenchDamageEffect`, completing the Raichu Gigashock ordinary effect-command list.
- AI-selection coverage advances from **12/45 to 17/45**; generic `EFFECTCMDTYPE_AI` coverage remains **81/81**.
- Behavior coverage advances from **518 to 525 fully translated labels**; ordinary player-side effect-list coverage advances from **217/310 to 218/310**.
- Expanded regression/source coverage from **135/135 to 142/142 tests**.
- Working whole-game engineering estimate remains **~51%**; AI maturity advances to roughly **~79%**.

## 2026-09-18 — General AI: Defending Attached-Energy Selectors

- Added **4** more `EFFECTCMDTYPE_AI_SELECTION` identities: Golduck Hyper Beam, Whirlpool, Dragonair Hyper Beam and Energy Removal.
- Translated the shared `AIPickEnergyCardToDiscardFromDefendingPokemon` policy: prefer Colorless Energy, then the defending Pokemon's own-color Energy, then the cartridge `ShuffleCards` fallback.
- Preserved `$ff` when the defending Active Pokemon has no attached Energy.
- Preserved Energy Removal's source distinction: its command-table selector returns the picked deck index only in register A, while the actual AI Trainer path supplies play-area and Energy parameters separately.
- AI-selection coverage advances from **8/45 to 12/45**; generic `EFFECTCMDTYPE_AI` coverage remains **81/81**.
- Behavior coverage advances from **514 to 518 fully translated labels**; ordinary player-side effect-list coverage remains **217/310**.
- Expanded regression/source coverage from **130/130 to 135/135 tests**.
- Working whole-game engineering estimate remains **~51%**; AI maturity advances to roughly **~78%**.

## 2026-09-18 — General AI: Fire-Energy Selection Handlers

- Source-reviewed and promoted the final **21** generic attack-AI identities, bringing `EFFECTCMDTYPE_AI` coverage to **81/81**.
- Added the source-ordered AI attack-selection bridge so translated `AI_SELECTION` and `AI_SWITCH_DEFENDING_PKMN` phases can prepare local single-process attack parameters before combat execution.
- Added the first **8/45** `EFFECTCMDTYPE_AI_SELECTION` identities: six one-Fire discard selectors plus Flames of Rage and Fire Spin.
- Added the missing ordinary Flames of Rage and Fire Spin selection/check/discard handlers; Fire Spin preserves the source behavior of selecting the first two attached Energy cards regardless of type.
- Preserved fail-closed behavior when an attack needs a player-side selection phase but its AI selection path is not translated.
- Ordinary player-side nonempty effect-list coverage advances from **199/310 to 217/310**.
- Behavior coverage advances from **461 to 514 fully translated labels**, with **72 partial labels / 31 partial entries / 63 explicit remaining items**.
- Expanded regression/source coverage to **130/130 tests**.
- Working whole-game engineering estimate is **~51%**; AI maturity is roughly **~77%**.

## 2026-09-18 — General AI: Generic Damage-Expectation Handlers

- Added all **39** source `SetExpectedAIDamage` wrappers.
- Added `UpdateExpectedAIDamage`, `UpdateExpectedAIDamage_AccountForPoison`, and all **13** poison-aware expectation wrappers.
- Preserved the source already-poisoned short-circuit that removes additional poison expectation.
- Added `ApplyExtraWaterEnergyDamageBonus` and all **8** shared Water Gun/Hydro Pump handlers, including Metronome substitution, colorless-payment handling, and the two-extra-Water cap.
- Generic AI effect identity coverage now reaches **60/81 unique `EFFECTCMDTYPE_AI` handlers**.
- Ordinary player-side effect-list coverage advances from **191/310 to 199/310** because the Water family also serves `BEFORE_DAMAGE`.
- Expanded regression/source coverage to **118/118 tests**.
- Behavior coverage now records **461 fully translated labels** with **72 partial labels / 31 partial entries / 63 explicit remaining items**.
- Working whole-game engineering estimate advances conservatively to **~50%**; AI maturity is roughly **~70%**.

## 2026-09-18 — General AI: Common Pokémon Powers

- Added native common active-Power AI for Damage Swap, Cowardice, Heal, Shift, Peek, Strange Behavior and Curse.
- Added the 19 matching manual effect-function handlers required for those seven Power command lists.
- Preserved source quirks including Damage Swap's fallback target register behavior, Cowardice compacted-play-area rescans, Peek's 3/50 activation and Curse's conditional Active-donor rule.
- Corrected common-Power preflight ordering so once-per-turn/status rejection happens before Peek consumes RNG.
- Expanded regression/source coverage to **114/114 tests**.
- Behavior coverage now records **397 fully translated labels** with **72 partial labels / 31 partial entries / 63 explicit remaining items**.
- Comparable ordinary player-side effect-list coverage advances to **191/310**; all **4/4** played-Pokémon trigger tables remain translated.
- Working whole-game engineering estimate advances conservatively to **~49%**; AI maturity is roughly **~65%**.

## 2026-09-18 — General AI: Retrieval, Removal, Gust & Poké Ball

- Added native source decisions for Energy Retrieval, Super Energy Retrieval, Super Energy Removal, Gust of Wind and Poké Ball.
- Preserved Go Go Rain Dance retrieval gating, deck-specific Poké Ball priority branches, Gust one-use/target priority, and Super Energy Removal attached-Energy selection behavior.
- Tightened the shared can-damage AI helper to require a usable positive-damage attack.
- Expanded regression/source coverage to **111/111 tests**.
- Behavior coverage now records **370 fully translated labels** with **72 partial labels / 31 partial entries / 64 explicit remaining items**.
- Working whole-game engineering estimate advances conservatively to **~48%**; AI maturity is roughly **60–63%**.


## General AI — Random Cadence & Common Trainer Batch

- Translated `AIChooseRandomlyNotToDoAction` with source boss/progression behavior and exact 25%/50% skip classes.
- Wired the random action gate into common Trainer processing and Venusaur Energy Trans.
- Added source-backed decisions for Pokémon Center, Pokédex, Mr. Fuji, Maintenance, Recycle, Item Finder, Revive and Pokémon Flute.
- Preserved Pokédex Energy→Pokémon→Trainer ordering and the Revive Kangaskhan/Tauros branch bug.
- Propagated modified-hand AI flags for Maintenance and Item Finder.
- Expanded regression/source coverage to **110/110 tests**.
- Behavior coverage now records **365 fully translated labels** with **72 partial labels / 31 partial entries / 64 explicit remaining items**.
- Working whole-game engineering estimate advances conservatively to **~47%**; AI maturity is roughly **55–60%**.

# TCG translation package changelog

## General AI — Retreat, Trainer Decisions & Energy Trans generation

- Removed the common retreat adapter boundary from `AIActionTable_GeneralDecks`; `GeneralNoRetreat` still skips retreat by design.
- Added source-shaped `AIDecideWhetherToRetreat`, `AIDecideBenchPokemonToSwitchTo` and `AITryToRetreat` state paths with cartridge score baselines/thresholds and later-slot tie behavior.
- Added exact `GetLoadedCard1RetreatCost` and `SetAIRetreatFlags`, including Dodrio Retreat Aid and Muk suppression.
- Preserved retreat-cost discard priority and the cartridge ordering where Energy is discarded before the confusion retreat toss.
- Added Switch substitution in common retreat processing.
- Added native Trainer AI policy for Bill, Potion, Defender, PlusPower, Switch, Full Heal, Energy Search, general Professor Oak and Energy Removal; rare/special cases remain conservatively partial.
- Added the Professor Oak second hand-processing pass.
- Added Venusaur Energy Trans attack/retreat/to-bench modes and corrected Blastoise/Venusaur so they do not trigger the generic manual-Power boundary.
- Behavior coverage records **356 fully translated labels**; the partial ledger explicitly tracks the remaining retreat/Trainer/Power branches instead of promoting them to translated status.
- Expanded regression/source coverage to **108/108 tests** before release packaging.

## General AI Turn Engine — Core Decision Loop generation

- Routed `AIActionTable_GeneralDecks` and `AIActionTable_GeneralNoRetreat` into a native source-ordered common turn core instead of `mainTurnLogic*` adapters.
- Bumped the manifest/cache contract to **v5** and added `deck_ai_constants.asm` to generated constants.
- Added common `InitAITurnVars` state and fail-closed Barrier/Mewtwo-mill deck probe boundary.
- Added common Energy-deficit analysis and Energy-card-ID mapping with Energy Burn support.
- Added forward/reverse AI damage estimation, including AI effect-phase validation and the source exact-KO comparison quirk.
- Added common attack scoring from `$50`, source tie preference, `CheckWhetherToSwitchToFirstAttack`, and phase-14 Trainer timing.
- Added common Basic/evolution decisions and generic Energy-placement scoring from `$80` with the `$85` play threshold, exact-colored/DCE preference and shuffled fallback.
- Added the source Trainer phase map; Bill's AI decision/play routine is native while untranslated Trainer decisions fail closed.
- Kept generic retreat, active Power decisions, `SPECIAL_AI_HANDLING`, high-recoil policy and specialized deck action tables explicit pending boundaries.
- Behavior coverage records **354 translated labels** and **48 explicitly partial labels**; **100/100 tests pass** at this checkpoint.

## Search/Retrieval & Advanced Energy generation

- Added generic validated deck/hand/Discard Pile and multi-card selection helpers.
- Added Energy Search/Retrieval, Computer Search, Item Finder, Super Energy Retrieval and Super Energy Removal.
- Added Pokemon Trader, Pokedex ordering, Maintenance, Recycle, Full Heal and Poke Ball.
- Added Rain Dance Energy attachment, Energy Trans, and Charizard Energy Burn integration.
- Added PlusPower/Defender attachment plus Mr. Fuji, Pokemon Center, Revive and Pokemon Flute.
- Comparable ordinary player-phase effect-list coverage moved from **163 to 184/310**.
- Behavior coverage now records **348 translated labels**; **89/89 tests pass**.

## Selection, Energy Manipulation & Bench/Switch Effects generation

- Added fail-closed host selection helpers for own/opponent Bench targets and attached Energy cards.
- Added source-style attached-Energy list/presence helpers and direct play-area damage support with Defender/Pokémon Power/Strikes Back handling.
- Added Fire-Energy discard-cost families, Thunderbolt, Hyper Beam/Whirlpool Energy removal, and the Energy Removal Trainer.
- Added Switch, Gust of Wind and Whirlwind-style forced switching, including Destiny Bond/No Damage or Effect interactions.
- Added Stretch Kick, Spark, Dark Mind and Blizzard bench-damage families.
- Completed played-Pokémon trigger handlers for Firegiver, Peal of Thunder and Healing Wind; all four trigger-power command tables are now covered together with Quickfreeze.
- Comparable ordinary player-phase effect-list coverage moved from **142 to 163/310**; the previous 122 figure used a more conservative/incomplete registry count.
- Expanded source tests; **77/77 tests pass** at this checkpoint.

## Card Effect Families & Trainer/Power Integration generation

- Expanded the dispatcher registry from 60 to **122/310** nonempty effect-command lists complete for ordinary player-side phases.
- Added source-style fixed-count multi-coin state and a fail-closed link multi-coin adapter boundary.
- Added `SetDefiniteDamage`/`AddToDamage`, broad multiplier/bonus/no-damage coin families, Stone Barrage, and common attack modifiers.
- Added common SUBSTATUS1/SUBSTATUS2 families feeding the existing damage/prevention engine.
- Added drain/heal and fixed/conditional recoil families through common HP/self-damage helpers.
- Added generic `PlayTrainerCard` phase routing with Headache checks; Potion now uses the dispatcher, and Bill/Professor Oak are translated.
- Added manual Pokémon Power phase routing and played-Pokémon trigger preflight/dispatch; Articuno Quickfreeze is the first complete trigger-power path.
- Preserved fail-closed behavior for untranslated functions and missing interactive selections.
- Expanded source tests; **66/66 tests pass** at this checkpoint.

## Effect-command dispatcher & shared effects generation

- Bumped the manifest/meta/cache path to schema/cache v4 and added generated `tcg_effects.lua`.
- Parsed the full source effect-command table: 317 zero-terminated lists (310 nonempty plus 7 zero-command Energy lists) and 632 phase/function records with no parser anomalies in the current pinned upstream file.
- Added ROM/symbol cross-checking for each effect phase byte and 16-bit function pointer before cache output.
- Translated source `CheckMatchingCommand` / `TryExecuteEffectCommandFunction` semantics into a generic Lua dispatcher with first-match behavior and explicit fail-closed unknown functions.
- Rewired player attack execution to the cartridge phase order and removed the hardcoded Star Freeze branch.
- Added shared poison, double-poison, paralysis, confusion and sleep primitives plus 50% variants and compact wrappers for Spit Poison, Foul Gas, Stiffen, Swords Dance, Acid and Supersonic.
- Added translated substatus application helpers needed by those effects.
- The current registry makes 60/310 nonempty effect-command lists complete for their player-side phases; untranslated AI-only records do not block player execution.
- Added dispatcher/manifest/cache regression coverage; the TCG suite now contains 57 tests.

## Common damage & prevention generation

- Promoted the previously un-repackaged common-damage work into the validated checkpoint.
- Translated source-ordered target damage modifiers: double-damage substatus, changed attacker color, changed/default weakness and resistance, weakness doubling, resistance -30, attached PlusPower/Defender, common damage-reduction substatuses, and 16-bit underflow clamping.
- Preserved the cartridge's documented `sla d` halve-damage bug used by `SUBSTATUS1_HALVE_DAMAGE` and Kabuto Armor instead of normalizing it to arithmetic division.
- Added source `CountCardIDInLocation` behavior so PlusPower/Defender count their actual attached card/location bytes.
- Added target/self damage modifier paths, including confusion's 20-damage self-hit path and exact confusion coin polarity.
- Added Fly/Barrier/Agility no-damage state, Neutralizing Shield, Transparency, and `CheckNoDamageOrEffect` status-queue filtering for defender-targeted statuses.
- Kept the remaining card-specific effect-command dispatcher fail-closed; this generation does not claim general card-effect coverage.
- Added 4 common-damage source tests; the TCG suite now contains 49 tests.

## Playable Sam practice checkpoint

- Added a development-only `POKEPORT_TCG_PRACTICE=1` LÖVE state that runs the original eight-player-turn Sam tutorial through a temporary native UI.
- Translated all seven `AIPerformScriptedTurn` branches and preserved the source turn-5 deck-index/card-ID comparison bug.
- Added bounded practice combat: exact attack-buffer copies, attached-Energy validation, normal practice damage, KO handoff, and Star Freeze's shared 50% paralysis queue. Unsupported combat/effect states remain explicit errors rather than approximations.
- Added source-backed player actions for Basic placement, normal Energy attachment, evolution, Potion, and attacks used by the tutorial.
- Added `ZeroRAM` boot ranges for the standalone duel entry and source evolution helpers.
- Added a practice session coordinator using source-format SRAM rewind, between-turn status/KO/prize handling, turn swaps, and the 15-turn practice completion rule.
- Added 7 practice/playability source tests; the TCG suite now contains 45 tests.
- Corrected `ApplyStatusConditionQueue` ordering so both arena last-turn-status bytes are cleared even when the queue is empty.

## AI / status / prize / knockout checkpoint

- Core extraction schema 3 now includes the ROM-driven `DuelDataToSave` layout, `DeckAIPointerTable` mapping, and `HandleBetweenTurnKnockOuts.Data_6ed2`.
- Added source-format duel save/restore and practice rewind, including the original checksum and SRAM-bank aliases.
- Added native AI startup dispatch, general initial Basic placement, Sam practice startup, and common random prize selection.
- Added native start/end substatus mutation, active Pokemon Power counting, Clairvoyance, poison/sleep/paralysis processing, and PlusPower/Defender cleanup.
- Added prize-state selection/taking and the source knockout result-bit/result-table state machine.
- Added exact play-area energy/attachment/swap/discard/compaction primitives.
- Split `DuelMainInterface` into source player/link/AI branches; full menu/link/turn policies remain fail-closed boundaries.
- Fixed initial-placement Lua multi-return handling, `SetAllPlayAreaPokemonCanEvolve` low-byte wrapping, missing per-slot clears in Pokemon placement, and save-snapshot temp-card-ID writes.
- TCG cache generation bumped to `tcg-rom-cache-v3:` so older extracted core schemas are not reused.

## Behavioral foundation slice

- Manifest schema 3.
- WRAM/HRAM/SRAM symbols generated from the matching RGBDS `.sym`; aliases and
  unions retain identical addresses.
- `DUELVARS_*`, `PLAYER_TURN`, and `OPPONENT_TURN` now resolve from decomp
  `EQUS LOW/HIGH(symbol)` definitions rather than handwritten numbers.
- Generated `tcg_memory.lua` added to the cartridge cache contract.
- Every card now stores the exact 65-byte buffer image copied by
  `LoadCardDataToHL_FromCardID`, including bytes following short Trainer/Energy
  structures.
- Deck extraction stores the two bytes immediately following each list
  terminator because `CopyDeckData` reads those bytes into `wDeckName`.
- Added sparse address-based RAM runtime (`src/tcg/memory/Memory.lua`).
- Translated duel page access/swap helpers, the original RNG, the original
  shuffle algorithm, deck copying and deck/hand/discard/list primitives, prize
  helpers, card-ID buffer access, hand/list sorting, and status clearing.
- Added label-level partial behavior coverage map.
- Translated `ConvertSpecialTrainerCardToPokemon` using its ROM-extracted local
  data template, completing both deck-index card-buffer wrappers without an
  approximation.
- Added decomp-symbol-derived `PrizeBitmasks` core data.
- Translated foundational `engine/duel/core.asm` state routines: duel/turn
  initialization, duel-variable page initialization, evolve flags, prize
  initialization/taking, non-turn temporary state clearing/status capture, and
  last-turn damage bookkeeping.
- Added exact opening-hand draw/redraw helper behavior and the two Basic-Pokémon
  test entry semantics.
- Added exact hand-to-arena/bench placement primitives with loaded-card HP/stage
  initialization and special-Trainer conversion.
- Added built-in deck loading, selected-player-deck SRAM copying, and the
  Sam/practice opponent-deck special path including the source RNG seed.
- Fourteen manifest/tooling/behavior-map/installer-upgrade tests.

## Data layer slice

- Manifest schema 2.
- Decomp-derived numeric constants, card/deck IDs, pointer order, text pointer
  order, charmaps, card source image dimensions, and card rgbgfx flags.
- ROM extraction for text, all cards, card graphics/palettes, and pointed decks.
- Symbol cross-checks for text/card/deck pointers and card graphics indices.
- Exact source deck-list comparison; preserves raw-terminated non-60-card data.
- Broadened translation ledger from ASM-only to canonical `src/` inputs.
- Gen1Recomp profile requires all generated TCG data products.
- Nine manifest/tooling tests.

## Duel setup coordinator

- translated `HandleDuelSetup` state/control flow without inventing player, AI, practice, or network choices;
- preserved one-side-only redraw versus both-sides restart behavior;
- translated initial active/bench RAM placement orchestration behind explicit selection/AI adapters;
- preserved the link branch's two sequential half-page duel-variable exchanges;
- translated local `_TossCoin` RNG result semantics and high-level `ExchangeRNG` byte direction;
- missing policy/transport dependencies fail closed instead of returning synthetic success.

## Turn-loop foundation

- translated `HandleTurn` state/control flow with explicit adapters for draw UI, Clairvoyance, save snapshots, and the main duel interface;
- preserved deck-empty `TURN_PLAYER_LOST`, second-turn evolution enabling, and exact turn-perspective swaps;
- translated `MainDuelLoop` through both between-turn RNG exchange points, turn increment/swap, and the 15-turn practice-duel completion branch;
- duel-finished presentation remains a distinct untranslated dependency rather than being approximated.
## 2026-09-18 — mid-generation AI handoff

- Working tree implements the 21 previously remaining unique `EFFECTCMDTYPE_AI` handlers, reaching code-level 81/81 generic AI identities.
- Added paired deterministic ordinary attack helpers from the same source cluster.
- Added `test_remaining_generic_ai_effects_source.py`; working suite is 124/124 passing.
- User requested a handoff before ledger/release promotion. Coverage/pending ledgers therefore intentionally remain at the previous validated checkpoint until the next AI reviews and promotes the batch.
- Added `HANDOFF_CURRENT_WORK.md` and refreshed handoff/start/validation guidance for safe continuation.

## 2026-09-19 — AI completion handoff packaging

- Revalidated the durable checkpoint from a clean extraction: 212/212 tests, Python compile pass, 28/28 Lua parse pass.
- Added `PROJECT_SCOPE.md` and `LATEST_AI_RESEARCH.md`.
- Updated the handoff/start/current-work/status/prompt/validation documents to distinguish persisted implementation from later unmerged source research.
- Recorded specialized deck action-table, boss setup, Mewtwo-mill and remaining Trainer AI source findings for the next ChatGPT.
- No unvalidated chat-side code was promoted into this package.
