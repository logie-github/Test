# Full project breakdown — deck AI lists + Energy policy checkpoint

> **2026-09-19 checkpoint:** the generic Energy no-play/skip-Arena preview is native and wired into Energy Trans; common retreat boss/setup and Fossil/Doll paths are translated. Promoted accounting is 662 translated labels, 248/310 ordinary player-side effect lists and 212/212 tests.

## Progress

- **Validated-code target:** **~56% of the full game** (engineering estimate).
- **Working single-number estimate:** **~56% overall**.
- The previous promoted package was also ~56%; this small slice does not change the rounded whole-game estimate. Player-side effect coverage is now **248/310** nonempty effect lists with **4/4** played-Pokémon trigger-power tables; generic AI effects, AI selection and the forced-switch phase are complete, and every source branch of `AISelectSpecialAttackParameters` is native.
- The 34 `AIActionTable_GeneralDecks` mappings and two `GeneralNoRetreat` mappings use the native common turn core. GeneralDecks now include a native common retreat/switch path; specialized deck action tables remain explicit boundaries.
- These percentages are **not audited source-byte coverage**. Final 100% requires label/range/file accounting across the whole decomp.

## What is playable right now

The package still contains the first source-backed playable vertical slice: **Sam's original practice duel**, all eight player turns and seven scripted Sam turns, through a temporary LÖVE/Gen1Recomp-facing UI. Core setup, attacks used by the tutorial, prizes, knockouts, status and turn progression go through translated Lua routines.

The generalized duel engine extends well beyond the tutorial: common damage/prevention, ROM-backed effect dispatch, broad card-effect families, generic Trainer/manual-Power routing, search/retrieval, advanced Energy mechanics, forced switching, direct Bench/play-area damage, all four played-Pokémon trigger powers, and a native common CPU turn engine with common retreat and selected Trainer/Power policy. Unsupported specialized AI/effects remain explicit fail-closed boundaries.

## Overall subsystem status

| Subsystem | Estimated completion | What exists / what remains |
| --- | --- | --- |
| ROM profile / import / extraction | ~85% | Exact ROM profile, source/symbol manifest, ROM-extracted core/deck/card/text/effect-command data, cache integration. Full asset/hardware audit remains. |
| Memory / constants / card & deck core | ~80% | Address-based WRAM/HRAM/SRAM model, duel pages, RNG/shuffle, card/deck/hand/discard/play-area operations and attached-Energy helpers. |
| Duel setup / state machine | ~55–60% | Duel init, hands/prizes, substantial turn/status/save/KO state and host target-selection boundaries. Original selection presentation/link branches remain partial. |
| Sam practice duel | ~80% | Eight player turns/seven Sam turns are playable through temporary host UI; cartridge menus/rendering remain. |
| Combat / effect engine | ~76% | Common damage/prevention, generic dispatcher, 248/310 ordinary player-side effect lists, search/retrieval, advanced Energy, switch/bench-damage/Lure, Recover, Destiny Bond, Energy Conversion/Energy Absorption and Energy Spike families, Water bonus effects, seven common manual Power families and all trigger-power tables. Residual/special and remaining card-specific families remain. |
| AI | ~95% | Common turn order, source-backed attack scoring/execution, full Basic/evolution scoring with generated deck priority lists, most normal Energy placement including generated Energy caps/bonuses, Legendary Articuno/repeated-Bench policy and source Energy-card choice, common retreat/switch with generated retreat bonuses, major Trainer decisions, Energy Trans, common active Power AI, all 81/81 generic AI-effect identities, all 45/45 AI-selection identities, all 5/5 forced-switch identities, and all source `AISelectSpecialAttackParameters` branches. The one-Energy potential-KO retreat edge, Trainer/Power decisions and specialized deck tables remain. |
| Original duel UI / presentation | ~5–10% | Temporary practice UI exists; cartridge renderer/card lists/menus/animations remain. |
| Link duel / serial | <5% | State boundaries and fail-closed transport hooks exist; serial synchronization/presentation remains. |
| Overworld / scripts / events | ~0–5% | Not meaningfully translated yet. |
| Collection / deck machines / album / trades / Card Pop | ~0–5% | Not meaningfully translated yet. |
| General save / progression | ~10–15% | Duel SRAM snapshot format is translated; full-game save/progression is not. |
| Audio / graphics / hardware-facing systems | ~0–5% | Extraction groundwork exists; original rendering/audio/timing/hardware replacement remains large. |

## Effect-command checkpoint

- **317 total effect-command lists**: 310 nonempty + 7 empty Energy lists.
- **632 command records** represented.
- **248/310 nonempty lists** have all ordinary player-side phases backed by translated handlers; this generation completes both Clefairy/Clefable Metronome lists by routing copied attacks through the normal dispatcher. The earlier Mirror Move, Conversion, Prophecy, Scavenge and Wildfire lists remain complete.
- **4/4 played-Pokémon trigger-power command tables** have translated trigger handlers.
- Missing relevant functions continue to return explicit `untranslated_effect:<label>` errors; missing host selections return explicit selection-required errors.

## AI checkpoint

- Common `GeneralDecks` turn ordering is native, including the source Professor Oak second pass.
- `GetAIScoreOfAttack` now follows the source common order: KO/damage range, recoil, defending-KO interaction, discard/encourage/nullify/draw/heal/status terms, and special handling.
- High-recoil policy includes the Rock Crusher, Zapping Selfdestruct, Boom Boom Selfdestruct and Power Generator deck branches; source self/Bench prize checks are retained.
- Common Energy placement keeps the `$80` baseline / `$85` threshold and source colored/DCE/fallback selection behavior.
- Common retreat uses the `$80` score baseline / 131 decision threshold; bench switch candidates use the source 50-point baseline with later-slot tie behavior.
- Retreat cost applies Dodrio Retreat Aid unless Muk suppresses Powers; Energy payment and confusion-failure ordering follow the source.
- Native Trainer policy covers Bill, Potion, Defender, PlusPower, Switch, Full Heal, Energy Search, general Professor Oak, Energy Removal, Pokémon Center, Pokédex, Mr. Fuji, Maintenance, Recycle, Item Finder, Revive, Pokémon Flute, Energy Retrieval, Super Energy Retrieval, Super Energy Removal, Gust of Wind and Poké Ball.
- `AIChooseRandomlyNotToDoAction` is native with source boss/progression handling and 25%/50% skip classes; common Trainer processing and Energy Trans use it.
- Venusaur Energy Trans has native attack/retreat/to-bench state paths. Blastoise Rain Dance remains integrated through normal Water Energy attachment rules.
- Common active Power AI is native for Damage Swap, Cowardice, Heal, Shift, Peek, Strange Behavior and Curse, with their manual effect-function state paths translated.
- Generic AI damage/effect expectation now covers **81/81 unique `EFFECTCMDTYPE_AI` handlers**.
- AI selection covers **45/45** unique `EFFECTCMDTYPE_AI_SELECTION` identities; forced-switch command phase is **5/5**. `AISelectSpecialAttackParameters` is fully native.
- `HandleSpecialAIAttacks` now covers every source card-ID branch, preserving documented cartridge quirks such as Dugtrio Earthquake's pointer/prize-side bugs.
- Forward and reverse AI damage estimators are slot-aware for Active/Bench candidates, including source switch-state clearing, slot-specific PlusPower/Defender handling, Active-only reductions, poison windows and equality-only exact-KO checks.
- Attack orchestration and hand/evolution score logic are promoted. Deck play-from-hand/Energy/retreat lists are generated and ROM-validated. Remaining AI boundaries are concentrated in the skip-Arena Energy preview path, retreat edge branches, Trainer/Power decisions and specialized deck action tables.

## Concrete size and validation numbers

- **28 Lua modules** under `src/tcg/`
- **14,137 Lua source lines**
- **662 fully translated source labels** in `behavior_coverage.json`
- **62 explicitly tracked partial labels** across **27 partial entries**
- **54 explicit remaining items** in those partial entries
- **212/212 Python tests passing before release packaging**
- Python tooling/tests compile with `py_compile`
- All `src/tcg/*.lua` modules are required to parse with texlua/Lua 5.3 in release validation
- Full upstream effect-command parser checkpoint remains 317 lists / 632 records
- No end-to-end LÖVE run claimed in this environment

## Lua module inventory

| Module | Lines | Bytes |
| --- | ---: | ---: |
| `src/tcg/Data.lua` | 34 | 1,359 |
| `src/tcg/Game.lua` | 112 | 3,043 |
| `src/tcg/duel/AI.lua` | 4,780 | 208,427 |
| `src/tcg/duel/CardData.lua` | 181 | 6,331 |
| `src/tcg/duel/Combat.lua` | 648 | 29,986 |
| `src/tcg/duel/Constants.lua` | 9 | 448 |
| `src/tcg/duel/Core.lua` | 205 | 7,592 |
| `src/tcg/duel/DeckLoader.lua` | 90 | 3,275 |
| `src/tcg/duel/DuelInterface.lua` | 45 | 1,488 |
| `src/tcg/duel/DuelOps.lua` | 644 | 26,270 |
| `src/tcg/duel/DuelSetup.lua` | 364 | 14,277 |
| `src/tcg/duel/DuelVars.lua` | 64 | 1,782 |
| `src/tcg/duel/EffectCommands.lua` | 4,268 | 193,610 |
| `src/tcg/duel/KnockOuts.lua` | 246 | 9,411 |
| `src/tcg/duel/PlayerActions.lua` | 180 | 8,201 |
| `src/tcg/duel/Practice.lua` | 117 | 4,794 |
| `src/tcg/duel/PracticeSession.lua` | 364 | 14,692 |
| `src/tcg/duel/Prizes.lua` | 107 | 4,267 |
| `src/tcg/duel/RNG.lua` | 67 | 2,155 |
| `src/tcg/duel/Runtime.lua` | 93 | 3,892 |
| `src/tcg/duel/SaveData.lua` | 174 | 6,917 |
| `src/tcg/duel/Status.lua` | 601 | 24,971 |
| `src/tcg/duel/TurnFlow.lua` | 108 | 3,714 |
| `src/tcg/import/RomExtractor.lua` | 723 | 28,394 |
| `src/tcg/import/TextCodec.lua` | 97 | 3,209 |
| `src/tcg/memory/Memory.lua` | 111 | 3,344 |
| `src/tcg/states/PracticePlayable.lua` | 97 | 3,431 |
| `src/tcg/states/TranslationIncomplete.lua` | 35 | 1,413 |

## Explicit partial boundaries

| Source | Labels | Lua target | Remaining |
| --- | --- | --- | --- |
| src/engine/duel/core.asm | `HandleDuelSetup`<br>`ChooseInitialArenaAndBenchPokemon` | `src/tcg/duel/DuelSetup.lua` | DisplayPlaceInitialPokemonCardsScreen / initial-placement UI<br>specialized deck AIDoAction_StartDuel startup policy<br>DuelTransmissionError / serial transport presentation |
| src/home/ai.asm | `AIDoAction_StartDuel` | `src/tcg/duel/AI.lua` | specialized deck turn tables outside Sam practice<br>remaining deck-specific Pokemon Power, Trainer and attack-policy decisions |
| src/engine/duel/core.asm | `DoPracticeDuelAction` | `src/tcg/duel/Practice.lua` | practice instruction rendering/menu presentation<br>full duel-menu integration for wrong-action restart points |
| src/engine/duel/core.asm | `_TossCoin` | `src/tcg/duel/DuelSetup.lua` | coin-toss UI/animation timing<br>link-opponent serial result synchronization |
| src/home/serial.asm | `ExchangeRNG` | `src/tcg/duel/DuelSetup.lua` | SerialExchangeBytes hardware/transport implementation<br>DuelTransmissionError jump semantics |
| src/engine/duel/core.asm | `HandleTurn` | `src/tcg/duel/TurnFlow.lua` | DisplayDrawOneCardScreen<br>DisplayPlayerDrawCardScreen<br>DuelMainInterface player/AI/link action engines |
| src/engine/duel/core.asm | `HandleBetweenTurnsEvents` | `src/tcg/duel/Status.lua` | between-turn presentation/animation timing<br>completion of HandleBetweenTurnKnockOuts choice/policy boundaries |
| src/engine/duel/core.asm | `HandleBetweenTurnKnockOuts`<br>`ReplaceKnockedOutPokemon` | `src/tcg/duel/KnockOuts.lua` | player replacement selection UI<br>specialized deck-specific KO-switch overrides beyond the common native bench scorer<br>link replacement transport/presentation |
| src/engine/duel/core.asm | `TurnDuelistTakePrizes` | `src/tcg/duel/Prizes.lua` | player prize-selection UI presentation<br>link prize transport/presentation |
| src/engine/menus/duel.asm | `_SelectPrizeCards` | `src/tcg/duel/Prizes.lua` | cursor/menu/card-page presentation and input implementation |
| src/engine/duel/core.asm | `DuelMainInterface` | `src/tcg/duel/DuelInterface.lua` | DrawDuelMainScene cartridge rendering<br>PrintDuelMenuAndHandleInput cartridge menu/presentation<br>DoLinkOpponentTurn<br>per-deck AIDoAction_Turn policies outside Sam practice |
| src/home/ai.asm | `AIDoAction_Turn` | `src/tcg/duel/AI.lua` | specialized deck turn tables outside Sam practice<br>remaining deck-specific Pokemon Power, Trainer and attack-policy decisions |
| src/engine/duel/core.asm | `MainDuelLoop` | `src/tcg/duel/TurnFlow.lua` | DisplayDuelistTurnScreen presentation<br>DuelMainInterface action engine<br>duel-finished result/sudden-death presentation path |
| src/home/duel.asm | `CheckIfEnoughEnergiesForGivenAttack`<br>`CopyAttackDataAndDamage_FromDeckIndex`<br>`UseAttackOrPokemonPower`<br>`PlayAttackAnimation_DealAttackDamage`<br>`CheckSelfConfusionDamage`<br>`HandleConfusionDamageToSelf`<br>`DealConfusionDamageToSelf`<br>`ApplyTransparencyIfApplicable` | `src/tcg/duel/Combat.lua` | card-specific effect functions beyond the translated status/heal/recoil/energy/search/switch/bench-damage families<br>remaining special damage, residual effects, and complex multi-target/card-movement paths<br>remaining manual Pokemon Power handlers beyond Damage Swap/Cowardice/Heal/Shift/Peek/Strange Behavior/Curse and Energy Trans, plus attack/power animation and link action transport |
| src/engine/duel/core.asm | `ApplyStatusConditionQueue` | `src/tcg/duel/Status.lua` | No Damage or Effect prevention text/menu presentation |
| src/engine/duel/core.asm | `PlayPokemonCard`<br>`PlayTrainerCard` | `src/tcg/duel/PlayerActions.lua` | general hand/card-list UI and remaining arbitrary card/deck/discard selection presentation<br>remaining Trainer effects beyond the translated search/retrieval, Energy, switch, healing, and restoration families |
| src/engine/duel/ai/decks/sams_practice.asm | `AIPerformScriptedTurn` | `src/tcg/duel/AI.lua` | cartridge OppAction/AIMakeDecision presentation and incidental UI state writes |
| src/home/substatus.asm | `HandleNoDamageOrEffectSubstatus`<br>`HandleTransparency`<br>`CheckNoDamageOrEffect` | `src/tcg/duel/Status.lua` | prevention/Transparency text, screen-state, and animation presentation paths |
| src/home/coin_toss.asm | `TossCoinATimes` | `src/tcg/duel/DuelSetup.lua` | coin-toss screen/animation timing<br>link multi-coin serial synchronization adapter implementation |
| src/engine/duel/ai/init.asm | `InitAITurnVars` | `src/tcg/duel/AI.lua` | exact hidden-player-deck Mewtwo-mill identification branch when Barrier persists three turns |
| src/engine/duel/ai/core.asm | `CheckEnergyNeededForAttack`<br>`CheckIfSelectedAttackIsUnusable`<br>`CheckIfDefendingPokemonCanKnockOut` | `src/tcg/duel/AI.lua` | remaining unusual multi-color/custom attack edge cases and specialized AI-only usability checks |
| src/engine/duel/ai/decks/general.asm | `AIMainTurnLogic` | `src/tcg/duel/AI.lua` | remaining Trainer AI decisions<br>specialized deck action-table overrides |
| src/engine/duel/ai/decks/general_no_retreat.asm | `AIDoTurn_GeneralNoRetreat` | `src/tcg/duel/AI.lua` | remaining Trainer AI decisions<br>specialized attack/deck heuristics shared with GeneralDecks |
| src/engine/duel/ai/trainer_cards.asm | `_AIProcessHandTrainerCards` | `src/tcg/duel/AI.lua` | remaining Trainer decision/play families (Super Potion, Pokemon Breeder, Imposter Professor Oak, Scoop Up, Lass, Imakuni, Gambler, Clefairy Doll, Mysterious Fossil, Computer Search and Pokemon Trader)<br>exact hand-snapshot/table scan order and generic modified-hand relist semantics outside the explicitly translated restart paths |
| src/engine/duel/ai/retreat.asm | `AIDecideWhetherToRetreat`<br>`AIDecideBenchPokemonToSwitchTo`<br>`AITryToRetreat` | `src/tcg/duel/AI.lua` | specialized energy-needed branches for every card effect |
| src/engine/duel/ai/pkmn_powers.asm | `HandleAIEnergyTrans`<br>`AIEnergyTransTransferEnergyToBench` | `src/tcg/duel/AI.lua` | presentation/delay/OppAction choreography |
| src/engine/duel/ai/trainer_cards.asm | `AIDecide_Potion_Phase07`<br>`AIDecide_Potion_Phase10`<br>`AIPlay_Potion`<br>`AIDecide_Defender_Phase13`<br>`AIDecide_Defender_Phase14`<br>`AIPlay_Defender`<br>`AIDecide_PlusPower_Phase13`<br>`AIDecide_PlusPower_Phase14`<br>`AIPlay_PlusPower`<br>`AIDecide_Switch`<br>`AIPlay_Switch`<br>`AIDecide_FullHeal`<br>`AIPlay_FullHeal`<br>`AIDecide_EnergySearch`<br>`AIPlay_EnergySearch`<br>`AIDecide_ProfessorOak`<br>`AIPlay_ProfessorOak`<br>`AIDecide_EnergyRemoval`<br>`AIPlay_EnergyRemoval` | `src/tcg/duel/AI.lua` | rare deck/card-specific policy branches and exact random-skip cadence<br>Potion/Super-Potion high-recoil and BOOST_IF_TAKEN_DAMAGE interactions not yet complete<br>full Energy Removal target-priority and Professor Oak evolution/deck-special-case scoring |

## Next work

Close the remaining common retreat potential-KO/one-Energy edge branch, then continue unresolved Trainer decision/play families. Follow with specialized deck action-table overrides, remaining Pokémon Power policy, unresolved ordinary effect families, and the larger unfinished game systems.
