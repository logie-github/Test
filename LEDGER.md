# Project Ledger

Canonical development state for **Pokopia: Log 568**.

Current phase: **LOG 568 Bookend Finale** (build 1.0.369).
Previous phase: Rocket Lounge Polish (build 1.0.368).

---

## Completed

- The opening LOG 568 OakSpeech scene is now a deliberate flash-forward with a
  paid-off bookend at the end of the story.
- Added `finale.lua`: a self-contained, save-persistent ending that runs the
  departure, the liftoff, the LOG 568 recreation and continuation, the
  preservation-system epilogue, and the closing image of Ditto dormant.
- Wired four entry points into the ending (Celadon chapter completion, the
  Mansion PC placement on a completed save, a per-frame reconciliation trigger
  for legacy and interrupted saves, and a developer scene jump) behind one gate
  that fires the real ending exactly once per save.
- Added `tests/finale.lua`, a standalone 292-check regression suite that runs
  without booting Gen1Recomp.
- Added a Logan character personality document.
- Added `LOG568_BOOKEND.md` recording the composition and its constraints.
- Fixed the Hypno scene-picker menu, whose last row previously painted below
  its own frame.

**Not changed:** the opening. `intro.oak_speech.build`, `log568_a/b/c` and
their text are untouched, and `tests/finale.lua` fails if any of them is
removed or edited.

## Files Added

| File | Purpose |
|---|---|
| `finale.lua` | The whole ending: script data plus the runtime state machine |
| `tests/finale.lua` | Standalone regression suite for the ending |
| `characters/logan/personality.md` | Character reference for Logan |
| `LOG568_BOOKEND.md` | Design record for the bookend composition |
| `LEDGER.md` | This file |

## Files Modified

| File | Change |
|---|---|
| `main.lua` | Forward-declared `Finale`; loaded and constructed `finale.lua`; bumped the save schema to 5 and added additive `finale` normalization; triggered the ending from `startCardHeroEnding`, `loganTalk` and an `input.step` reconciliation check; added `SCENE 3` / `FINALE LOG` to the Hypno scene picker and resized that menu |
| `manifest.json` | Version 1.0.368 → 1.0.369; description updated |
| `mod.card` | Recorded the flash-forward framing and the finale |
| `CHANGELOG.md` | 1.0.369 entry |
| `README.md` | Bookend section and test instructions |

## Core Systems

Systems this build depends on, and what owns them.

| System | Owner | Responsibility |
|---|---|---|
| Mod entry / content patching | `main.lua` | `mod.content.field:patch`, sprite and follower registration, map overrides |
| Ditto-as-player | `main.lua` | `playerSprites` patch, transform menu, form persistence and movement hooks |
| Dialogue presentation | `main.lua` | `TextBox.new`/`TextBox.draw` wrappers, speaker inference, trainer cutouts, Pokémon portrait cards |
| Trainer cutout art | `main.lua` | `trainerCutoutBundle`, `trainerPortraitImage`, mask shader; cached per trainer id |
| Mansion emergency scene | `main.lua` | Map-script overrides, authored cast, alarm, panic scripts |
| Celadon chapter | `main.lua` | `startCeladonEnding` and its cinematic controller, café jobs, Game Corner, scalper line, card quest |
| TCG | `tcg_battle.lua`, `tcg_engine/` | Packs, binder, deck builder, duels |
| Rocket operations | `rocket_quests.lua` | Five sequential save-persistent hideout quests |
| **Ending / bookend** | **`finale.lua`** | **Departure, liftoff, LOG 568 recreation and continuation, preservation system, closing image; its own trigger gate and save record** |

`finale.lua` follows the same dependency-injection contract as
`rocket_quests.lua` and `tcg_battle.lua`: `main.lua` loads the chunk with
`loadfile` and constructs it with an explicit API table, so the module never
reaches into `main.lua`'s locals and can be exercised standalone.

## Save Schema

Namespace: `save.modData.pokopia_log568`. Schema version **5** (was 4).

New in this phase — `q.finale`:

| Field | Type | Meaning |
|---|---|---|
| `version` | number | Finale schema version |
| `prequelComplete` | boolean | Celadon chapter finished; arms the ending |
| `logSeen` | boolean | The LOG 568 scene has been reached |
| `completed` | boolean | The ending has played; blocks a second automatic play |
| `playCount` | number | Diagnostics |
| `lastScene` | string | Diagnostics: last scene entered |
| `running` | nil | Transient; explicitly cleared on load |

Migration: `prequelComplete` is seeded from the pre-existing
`q.cardQuestComplete`, so schema-4 saves that already finished the Celadon
chapter reach the ending without replaying anything. No existing field is
renamed, cleared, or reinterpreted. Unknown fields are still preserved and the
schema number is still never downgraded.

## Transformations

Unchanged this phase. Current forms and how they are obtained:

| Form | Obtained | Notes |
|---|---|---|
| DITTO | default | Base form |
| PERSIAN | Mansion B1F Rattata/Persian scene | Faster movement; passes the Rocket guard |
| ELECTRODE | Celadon chapter | Momentum-based speed ramp |
| PORYGON | Celadon chapter | Used in the Game Corner prize scene |
| HITMONLEE / HITMONCHAN | Celadon spar, player choice | One of the two, persisted |

The finale does not grant, revoke, or read transformation state. The Mansion
PC placement continues to clear PERSIAN exactly as before.

## Characters

| Character | State variables | Documented |
|---|---|---|
| Logan | `loganAsked`, `pixieFollowing`, `pixieStored` | `characters/logan/personality.md` (new) |
| Wooper | `characters.WOOPER.streetCred` | `characters/wooper/personality.md` |
| Giovanni | `giovanniMeetingDone`, `giovanniWrongFormPending` | — |
| Pixie (Vulpix) | `pixieFollowing`, `pixieStored`; appears in the finale's storage roll under her nickname | — |
| Hypno | Card Club hub; now also the finale scene jump | — |
| Super Nerd | `refundDemanded`, `policeCalled`, `superNerdArrested` | — |

## Relationships

Unchanged this phase. `q.characters.<NAME>` remains the per-character
relationship namespace; Wooper's `streetCred` is the only tracked value so far.

## Quests

Unchanged this phase. Existing quest state machines:

- Mansion: Rattata distraction → Giovanni meeting → Pixie rescue → PC placement.
- Celadon: café delivery jobs, card-scalper quest (`cardQuestComplete`), Game
  Corner refund sequence.
- Rocket Operations: five sequential quests in `rocket_quests.lua`.

New completion consequence: finishing the Celadon card quest now also sets
`finale.prequelComplete` and rolls the ending.

## Minigames

Unchanged this phase: café delivery jobs, Cue Bones, TCG duels, pack opening.
The finale is a cutscene, not a minigame, and adds no scored systems.

## World State

Unchanged this phase. The finale is presentational: it does not move NPCs,
open paths, or alter map geometry, so it cannot desynchronise any existing
reconciliation pass. It locks the live overworld's player input while running
and restores the previous value on close.

## Story Progress

Playable, in play order:

1. Title → OakSpeech LOG 568 (flash-forward).
2. Pokémon Mansion: emergency, Rattata/Persian, Giovanni's Conservation Project
   briefing, Pixie rescue, PC placement.
3. `Much earlier...` → Celadon City prequel: Game Corner refund, café jobs,
   TCG, Rocket Hideout operations, card-scalper quest.
4. **Ending: departure → liftoff → LOG 568 → preservation system → Ditto
   dormant.**

The story now closes its own loop. The opening is no longer unresolved.

## Dependencies

Later phases can rely on:

- `Finale.SCRIPT` — the ending's text as pure data, safe to read without the
  renderer.
- `Finale.layout(text,maxWidth,maxRows,measure)` — reusable Gen I row breaking
  with a pluggable width measure.
- `Finale.pages(beats)` — `\f` page splitting that preserves per-beat speaker
  metadata.
- `Finale.state(q)` — the additive save accessor.
- `finale.markPrequelComplete(game)` / `finale.shouldAutoPlay(game)` — the
  trigger gate, if a later chapter should arm the ending instead of the Celadon
  card quest.

## Known Issues

- The finale's storage display, launch and closing card are drawn from
  primitives and the existing DMG logo. If a later phase adds authored art for
  the storage system, `drawSystemChrome` and `drawDormantDitto` are the two
  functions to replace.
- `SYSTEM_RECORDS` is an authored list, not a read of the player's actual
  storage. If a later phase gives the PC real contents, that list should be
  derived from them.
- The ending returns the player to free roam rather than to the title, so a
  demo save is never stranded. That is a demo-scoped decision.
- `tests/finale.lua` runs standalone; `tests/core.lua` still requires the
  engine harness and was not extended.

## Regression Risks

Things a future change could break, and what protects them:

| Risk | Protection |
|---|---|
| Someone edits or removes the opening OakSpeech lines | `tests/finale.lua` asserts each line is still present in `main.lua` as source |
| Someone rewrites the finale's opening quote so the recognition beat stops landing | `tests/finale.lua` compares pages 1-4 and the last two pages byte-for-byte |
| Someone adds a cause for the disasters or shows humans returning | banned-vocabulary sweep in `tests/finale.lua` |
| A dialogue edit overruns the text frame | per-page row/width assertions |
| The ending fires twice, or never | `shouldAutoPlay` gating tests |
| A save written mid-cutscene resumes stuck | `running` is cleared in `normalizePokopiaSave` |
| Schema 4 saves lose access to the ending | `prequelComplete` seeded from `cardQuestComplete`, asserted by the migration path in `normalizePokopiaSave` |

## Testing Completed

- `lua5.1 tests/finale.lua` — 292 checks, all passing.
- Lua 5.1 (LuaJIT-compatible) parse sweep over `main.lua`, `finale.lua`,
  `rocket_quests.lua`, `tcg_battle.lua`, `tests/core.lua`, `mod.card` and every
  file in `tcg_engine/`.
- Bytecode symbol audit confirming `finale.lua` writes no globals and reads
  only `love`, `require`, `math`, `pcall`, `ipairs`, `type`, `tonumber`,
  `tostring`.
- Bytecode symbol audit confirming the new `main.lua` call sites resolve
  `Finale`, `pokopiaData`, `stopPokopiaAlarm`, `trainerPortraitImage`,
  `getTrainerMaskShader`, `activeOverworld`, `muchEarlier`,
  `restorePlayerInput` and `ensureCeladonScalperLine` as locals/upvalues rather
  than accidental globals.
- Headless drive of the full ending state machine through every mode
  (`DEPARTURE`, `LIFTOFF_RISE`, `LIFTOFF_TEXT`, `LIFTOFF_HOLD`, `TO_BLACK`,
  `LOG568`, `LOG_HOLD`, `SYSTEM`, `SYSTEM_CONTINGENCY`, `DORMANT`, `OUTRO`,
  `END`) with both update and draw executed each frame, asserting the state
  pops itself off the stack.
- `manifest.json` re-parsed as JSON after the version bump.

**Not performed:** in-engine playtesting. Gen1Recomp is not available in this
environment, so every engine-facing call was matched against a call site that
already ships in `main.lua`/`tcg_battle.lua`, and everything optional is
`pcall`-guarded with a working fallback.

## Next Phase

Suggested, in dependency order:

1. **In-engine verification pass.** Run the three finale entry points on a new
   game, a schema-4 development save, and a save reloaded mid-Celadon. Confirm
   the Scientist cutout lands in the same screen position as the intro's — that
   is the one thing that cannot be checked outside the engine.
2. **Wire the storage roll to real data.** Replace `SYSTEM_RECORDS` with the
   Pokémon the player actually put into the system.
3. **Departure scene staging.** The departure currently plays as a text scene
   over the sealed-system view. If the Mansion PC room is worth staging as an
   overworld scene (Logan walking out, lights failing bank by bank), it
   attaches at `enterScene("DEPARTURE")` without touching anything else.
4. **Character documents for Giovanni and the Scientist**, to match Logan and
   Wooper.
